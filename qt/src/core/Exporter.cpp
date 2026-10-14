#include "Exporter.h"

#include "AudioMix.h"
#include "FFmpeg.h"
#include "MediaWriter.h"
#include "Renderer.h"

#include <QFile>
#include <QPointer>
#include <QThread>
#include <atomic>

namespace of {

namespace {

/// Leva a mixagem (48 kHz) à taxa do arquivo e grava.
class AudioSink
{
public:
    AudioSink(MediaWriter &writer, int sampleRate) : m_writer(writer), m_rate(sampleRate)
    {
        if (sampleRate == AudioMix::sampleRate)
            return;
        SwrContext *raw = nullptr;
        const AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
        if (swr_alloc_set_opts2(&raw, &stereo, AV_SAMPLE_FMT_FLT, sampleRate, &stereo, AV_SAMPLE_FMT_FLT,
                                AudioMix::sampleRate, 0, nullptr) >= 0) {
            m_swr.reset(raw);
            if (swr_init(m_swr.get()) < 0)
                m_swr.reset();
        }
    }

    bool valid() const { return m_rate == AudioMix::sampleRate || m_swr; }

    bool write(const float *samples, int frames)
    {
        if (!m_swr)
            return m_writer.writeAudio(samples, frames);
        const auto *in = reinterpret_cast<const uint8_t *>(samples);
        return convert(&in, frames);
    }

    /// O que restou no reamostrador.
    bool flush() { return !m_swr || convert(nullptr, 0); }

private:
    bool convert(const uint8_t **in, int frames)
    {
        const int capacity = swr_get_out_samples(m_swr.get(), frames);
        if (capacity <= 0)
            return true;
        m_buffer.resize(size_t(capacity) * AudioMix::channels);
        auto *out = reinterpret_cast<uint8_t *>(m_buffer.data());
        const int got = swr_convert(m_swr.get(), &out, capacity, in, frames);
        return got <= 0 || m_writer.writeAudio(m_buffer.data(), got);
    }

    MediaWriter &m_writer;
    int m_rate;
    ff::SwrPtr m_swr;
    std::vector<float> m_buffer;
};

/// A exportação inteira, na thread de trabalho. Falso com `error` vazio = cancelado.
bool exportFile(const Project &project, const ExportSettings &settings, const QString &path,
                const std::atomic<bool> &cancelled, const std::function<void(double)> &progress, QString *error)
{
    if (const auto message = settings.validationError(project)) {
        *error = *message;
        return false;
    }
    const bool audioOnly = isAudioOnly(settings.container);
    const Rational fd = frameDuration(settings.frameRate);
    const Micros total = std::max(project.duration(), Time::round(fd.seconds() * 1e6));
    const QList<AudioClip> clips = settings.audioEnabled ? AudioMix::clips(project) : QList<AudioClip>{};
    if (audioOnly && clips.isEmpty()) {
        *error = QStringLiteral("O projeto não tem áudio para exportar.");
        return false;
    }

    const QSize size = settings.outputSize(project);
    std::optional<MediaWriter::Video> video;
    if (!audioOnly) {
        MediaWriter::Video v;
        v.size = size;
        v.frameDuration = fd;
        v.codec = settings.codec;
        v.bitrate = settings.codec == VideoCodec::ProRes422 ? 0 : settings.videoBitrate(size, total);
        v.keyframeDistance = settings.keyframeDistance();
        v.matrix = MediaWriter::Matrix::BT709;
        // O x265 no "medium" fica lento demais na CPU; "fast" ainda comprime bem.
        v.preset = settings.codec == VideoCodec::Hevc ? QStringLiteral("fast") : QStringLiteral("medium");
        video = v;
    }
    std::optional<MediaWriter::Audio> audio;
    if (!clips.isEmpty())
        audio = MediaWriter::Audio{settings.audioSampleRate, AudioMix::channels, settings.audioKbps * 1000};

    QFile::remove(path);
    auto writer = MediaWriter::create(path, video, audio, error);
    if (!writer)
        return false;
    const auto fail = [&](const QString &message) {
        writer->abort();
        *error = message;
        return false;
    };

    AudioMixer mixer(clips);
    AudioSink sink(*writer, settings.audioSampleRate);
    if (audio && !sink.valid())
        return fail(QStringLiteral("Taxa de amostragem não suportada: %1 Hz").arg(settings.audioSampleRate));
    std::vector<float> buffer;
    const qint64 audioTotal = AudioMix::sampleAt(total);
    qint64 audioDone = 0;
    const auto writeAudioUntil = [&](qint64 until) {
        constexpr int chunk = 4096;
        buffer.resize(size_t(chunk) * AudioMix::channels);
        while (audioDone < until) {
            const int n = int(std::min<qint64>(chunk, until - audioDone));
            mixer.read(buffer.data(), n);
            if (!sink.write(buffer.data(), n))
                return false;
            audioDone += n;
        }
        return true;
    };

    if (video) {
        Renderer renderer;
        // Quadros em k × duração do quadro, enquanto couberem na duração.
        const qint64 step = fd.num * 1'000'000;
        const qint64 frames = std::max<qint64>(1, (total * fd.den + step - 1) / step);
        for (qint64 k = 0; k < frames; ++k) {
            if (cancelled)
                return fail({});
            const Micros t = Time::round(double(k) * double(step) / double(fd.den));
            if (!writer->writeVideo(renderer.render(project, t, size), k))
                return fail(writer->errorString());
            if (audio) {
                const Micros next = std::min(total, Time::round(double(k + 1) * double(step) / double(fd.den)));
                if (!writeAudioUntil(AudioMix::sampleAt(next)))
                    return fail(writer->errorString());
            }
            progress(double(k + 1) / double(frames));
        }
    }
    if (audio) {
        // O resto do som (ou todo ele, no M4A) em blocos de ~1/10 s.
        const qint64 block = AudioMix::sampleRate / 10;
        while (audioDone < audioTotal) {
            if (cancelled)
                return fail({});
            if (!writeAudioUntil(std::min(audioTotal, audioDone + block)))
                return fail(writer->errorString());
            progress(double(audioDone) / double(audioTotal));
        }
        if (!sink.flush())
            return fail(writer->errorString());
    }
    if (cancelled)
        return fail({});
    if (!writer->finish(error))
        return false;
    progress(1);
    return true;
}

} // namespace

struct Exporter::Impl {
    std::atomic<bool> cancelled{false};
    QThread *thread = nullptr;
    bool running = false;
};

Exporter::Exporter(QObject *parent) : QObject(parent), d(std::make_unique<Impl>()) {}

Exporter::~Exporter()
{
    if (d->thread) {
        d->cancelled = true;
        d->thread->wait();
        delete d->thread;
    }
}

void Exporter::start(const Project &project, const ExportSettings &settings, const QString &path)
{
    if (d->running)
        return;
    if (d->thread) {
        d->thread->wait();
        delete d->thread;
        d->thread = nullptr;
    }
    d->running = true;
    d->cancelled = false;
    QPointer<Exporter> self(this);
    d->thread = QThread::create([this, self, project, settings, path] {
        double last = -1;
        const auto report = [&](double fraction) {
            // No máximo ~200 avisos por exportação.
            if (fraction < 1 && fraction - last < 0.005)
                return;
            last = fraction;
            QMetaObject::invokeMethod(this, [self, fraction] {
                if (self)
                    emit self->progress(fraction);
            }, Qt::QueuedConnection);
        };
        QString error;
        const bool ok = exportFile(project, settings, path, d->cancelled, report, &error);
        QMetaObject::invokeMethod(this, [self, ok, error] {
            if (!self)
                return;
            self->d->running = false;
            emit self->finished(ok, ok ? QString() : error);
        }, Qt::QueuedConnection);
    });
    d->thread->setObjectName(QStringLiteral("OpenFrame exportação"));
    d->thread->start();
}

void Exporter::cancel() { d->cancelled = true; }

bool Exporter::isRunning() const { return d->running; }

} // namespace of
