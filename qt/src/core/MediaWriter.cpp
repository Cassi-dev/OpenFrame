#include "MediaWriter.h"

#include "FFmpeg.h"

#include <QFile>
#include <vector>

namespace of {

namespace {

struct OutputDeleter {
    void operator()(AVFormatContext *c) const
    {
        if (c && c->pb && !(c->oformat->flags & AVFMT_NOFILE))
            avio_closep(&c->pb);
        avformat_free_context(c);
    }
};
using OutputPtr = std::unique_ptr<AVFormatContext, OutputDeleter>;

const char *encoderName(VideoCodec c)
{
    switch (c) {
    case VideoCodec::H264: return "libx264";
    case VideoCodec::Hevc: return "libx265";
    case VideoCodec::ProRes422: return "prores_ks";
    }
    return "libx264";
}

} // namespace

struct MediaWriter::Impl {
    QString path;
    OutputPtr output;
    /// Só apagamos o arquivo se fomos nós que o abrimos.
    bool fileOpened = false;
    bool finished = false;
    QString error;

    ff::CodecPtr video;
    AVStream *videoStream = nullptr;
    ff::SwsPtr sws;
    ff::FramePtr videoFrame;
    Video videoSpec;

    ff::CodecPtr audio;
    AVStream *audioStream = nullptr;
    std::vector<float> pending; // amostras intercaladas ainda sem quadro completo
    qint64 audioPts = 0;
    int channels = 2;

    bool fail(const QString &what, int code = 0)
    {
        if (error.isEmpty())
            error = code ? QStringLiteral("%1: %2").arg(what, ff::errorString(code)) : what;
        return false;
    }

    bool drain(AVCodecContext *codec, AVStream *stream)
    {
        const ff::PacketPtr packet = ff::makePacket();
        for (;;) {
            const int r = avcodec_receive_packet(codec, packet.get());
            if (r == AVERROR(EAGAIN) || r == AVERROR_EOF)
                return true;
            if (r < 0)
                return fail(QStringLiteral("codificação"), r);
            // Sem duração no pacote, a lista de edição do MOV corta o último quadro.
            if (packet->duration <= 0 && codec->codec_type == AVMEDIA_TYPE_VIDEO)
                packet->duration = 1;
            av_packet_rescale_ts(packet.get(), codec->time_base, stream->time_base);
            packet->stream_index = stream->index;
            const int w = av_interleaved_write_frame(output.get(), packet.get());
            if (w < 0)
                return fail(QStringLiteral("gravação"), w);
        }
    }

    bool encode(AVCodecContext *codec, AVStream *stream, const AVFrame *frame)
    {
        const int r = avcodec_send_frame(codec, frame);
        if (r < 0 && r != AVERROR_EOF)
            return fail(QStringLiteral("codificação"), r);
        return drain(codec, stream);
    }

    bool sendAudio(int frames)
    {
        const ff::FramePtr frame = ff::makeFrame();
        frame->nb_samples = frames;
        frame->format = audio->sample_fmt;
        frame->sample_rate = audio->sample_rate;
        av_channel_layout_copy(&frame->ch_layout, &audio->ch_layout);
        if (av_frame_get_buffer(frame.get(), 0) < 0)
            return fail(QStringLiteral("memória de áudio"));
        for (int c = 0; c < channels; ++c) {
            auto *plane = reinterpret_cast<float *>(frame->data[c]);
            for (int i = 0; i < frames; ++i)
                plane[i] = pending[size_t(i * channels + c)];
        }
        pending.erase(pending.begin(), pending.begin() + qsizetype(frames) * channels);
        frame->pts = audioPts;
        audioPts += frames;
        return encode(audio.get(), audioStream, frame.get());
    }

    bool openVideo(const Video &spec)
    {
        const AVCodec *codec = avcodec_find_encoder_by_name(encoderName(spec.codec));
        if (!codec)
            return fail(QStringLiteral("codificador %1 indisponível").arg(QLatin1StringView(encoderName(spec.codec))));
        video.reset(avcodec_alloc_context3(codec));
        AVCodecContext *c = video.get();
        c->width = spec.size.width();
        c->height = spec.size.height();
        c->time_base = AVRational{int(spec.frameDuration.num), int(spec.frameDuration.den)};
        c->framerate = AVRational{int(spec.frameDuration.den), int(spec.frameDuration.num)};
        c->sample_aspect_ratio = AVRational{1, 1};
        c->pix_fmt = spec.codec == VideoCodec::ProRes422 ? AV_PIX_FMT_YUV422P10LE : AV_PIX_FMT_YUV420P;
        if (spec.bitrate > 0 && spec.codec != VideoCodec::ProRes422)
            c->bit_rate = spec.bitrate;
        if (spec.keyframeDistance > 0)
            c->gop_size = spec.keyframeDistance;
        c->color_range = spec.fullRange ? AVCOL_RANGE_JPEG : AVCOL_RANGE_MPEG;
        if (spec.tagged) {
            const bool hd = spec.matrix == Matrix::BT709;
            c->colorspace = hd ? AVCOL_SPC_BT709 : AVCOL_SPC_SMPTE170M;
            c->color_primaries = hd ? AVCOL_PRI_BT709 : AVCOL_PRI_SMPTE170M;
            c->color_trc = hd ? AVCOL_TRC_BT709 : AVCOL_TRC_SMPTE170M;
        } else if (!spec.fullRange) {
            c->color_range = AVCOL_RANGE_UNSPECIFIED;
        }
        if (output->oformat->flags & AVFMT_GLOBALHEADER)
            c->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

        AVDictionary *options = nullptr;
        switch (spec.codec) {
        case VideoCodec::H264:
            av_dict_set(&options, "preset", spec.preset.toUtf8().constData(), 0);
            av_dict_set(&options, "profile", "high", 0);
            if (spec.bitrate <= 0)
                av_dict_set(&options, "crf", "18", 0);
            break;
        case VideoCodec::Hevc:
            av_dict_set(&options, "preset", spec.preset.toUtf8().constData(), 0);
            av_dict_set(&options, "x265-params", spec.bitrate > 0 ? "log-level=error" : "log-level=error:crf=20", 0);
            c->codec_tag = MKTAG('h', 'v', 'c', '1'); // o QuickTime só abre HEVC marcado como hvc1
            break;
        case VideoCodec::ProRes422:
            av_dict_set(&options, "profile", "standard", 0);
            av_dict_set(&options, "vendor", "apl0", 0);
            break;
        }
        const int r = avcodec_open2(c, codec, &options);
        av_dict_free(&options);
        if (r < 0)
            return fail(QStringLiteral("abrir %1").arg(QLatin1StringView(encoderName(spec.codec))), r);

        videoStream = avformat_new_stream(output.get(), nullptr);
        videoStream->time_base = c->time_base;
        avcodec_parameters_from_context(videoStream->codecpar, c);
        if (spec.rotation % 360 != 0) {
            AVPacketSideData *sd = av_packet_side_data_new(&videoStream->codecpar->coded_side_data,
                                                           &videoStream->codecpar->nb_coded_side_data,
                                                           AV_PKT_DATA_DISPLAYMATRIX, 9 * sizeof(int32_t), 0);
            if (sd)
                av_display_rotation_set(reinterpret_cast<int32_t *>(sd->data), spec.rotation); // sentido horário
        }

        sws.reset(sws_getContext(c->width, c->height, AV_PIX_FMT_BGRA, c->width, c->height, c->pix_fmt,
                                 SWS_BICUBIC | SWS_ACCURATE_RND | SWS_FULL_CHR_H_INP, nullptr, nullptr, nullptr));
        if (!sws)
            return fail(QStringLiteral("conversão de cor"));
        const int matrix = spec.matrix == Matrix::BT709 ? SWS_CS_ITU709 : SWS_CS_ITU601;
        sws_setColorspaceDetails(sws.get(), sws_getCoefficients(SWS_CS_DEFAULT), 1, sws_getCoefficients(matrix),
                                 spec.fullRange ? 1 : 0, 0, 1 << 16, 1 << 16);
        videoFrame = ff::makeFrame();
        videoFrame->format = c->pix_fmt;
        videoFrame->width = c->width;
        videoFrame->height = c->height;
        videoFrame->color_range = c->color_range;
        videoFrame->colorspace = c->colorspace;
        videoFrame->color_primaries = c->color_primaries;
        videoFrame->color_trc = c->color_trc;
        if (av_frame_get_buffer(videoFrame.get(), 0) < 0)
            return fail(QStringLiteral("memória de vídeo"));
        videoSpec = spec;
        return true;
    }

    bool openAudio(const Audio &spec)
    {
        const AVCodec *codec = avcodec_find_encoder_by_name("aac");
        if (!codec)
            return fail(QStringLiteral("codificador AAC indisponível"));
        audio.reset(avcodec_alloc_context3(codec));
        AVCodecContext *c = audio.get();
        c->sample_fmt = AV_SAMPLE_FMT_FLTP;
        c->sample_rate = spec.sampleRate;
        av_channel_layout_default(&c->ch_layout, spec.channels);
        c->bit_rate = spec.bitrate;
        c->time_base = AVRational{1, spec.sampleRate};
        if (output->oformat->flags & AVFMT_GLOBALHEADER)
            c->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
        const int r = avcodec_open2(c, codec, nullptr);
        if (r < 0)
            return fail(QStringLiteral("abrir AAC"), r);
        audioStream = avformat_new_stream(output.get(), nullptr);
        audioStream->time_base = c->time_base;
        avcodec_parameters_from_context(audioStream->codecpar, c);
        channels = spec.channels;
        return true;
    }
};

MediaWriter::MediaWriter() : d(std::make_unique<Impl>()) {}

MediaWriter::~MediaWriter()
{
    if (!d->finished)
        abort();
}

std::unique_ptr<MediaWriter> MediaWriter::create(const QString &path, const std::optional<Video> &video,
                                                 const std::optional<Audio> &audio, QString *error)
{
    av_log_set_level(AV_LOG_ERROR);
    std::unique_ptr<MediaWriter> writer(new MediaWriter);
    Impl &d = *writer->d;
    d.path = path;
    const auto failed = [&]() -> std::unique_ptr<MediaWriter> {
        if (error)
            *error = d.error;
        writer->abort();
        return nullptr;
    };
    AVFormatContext *raw = nullptr;
    const QByteArray file = path.toUtf8();
    // M4A é o muxer "ipod" do FFmpeg.
    const char *format = path.endsWith(QStringLiteral(".m4a"), Qt::CaseInsensitive) ? "ipod" : nullptr;
    int r = avformat_alloc_output_context2(&raw, nullptr, format, file.constData());
    if (r < 0 || !raw) {
        d.fail(QStringLiteral("formato de saída"), r);
        return failed();
    }
    d.output.reset(raw);
    if ((video && !d.openVideo(*video)) || (audio && !d.openAudio(*audio)))
        return failed();
    if (!(d.output->oformat->flags & AVFMT_NOFILE)) {
        r = avio_open(&d.output->pb, file.constData(), AVIO_FLAG_WRITE);
        if (r < 0) {
            d.fail(QStringLiteral("abrir %1").arg(path), r);
            return failed();
        }
        d.fileOpened = true;
    }
    // Índice no começo do arquivo, como o `shouldOptimizeForNetworkUse` do Swift.
    AVDictionary *muxerOptions = nullptr;
    av_dict_set(&muxerOptions, "movflags", "+faststart", 0);
    r = avformat_write_header(d.output.get(), &muxerOptions);
    av_dict_free(&muxerOptions);
    if (r < 0) {
        d.fail(QStringLiteral("cabeçalho"), r);
        return failed();
    }
    return writer;
}

bool MediaWriter::writeVideo(const QImage &frame, qint64 index)
{
    Impl &impl = *d;
    if (!impl.video)
        return impl.fail(QStringLiteral("sem trilha de vídeo"));
    QImage image = frame.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    if (image.size() != impl.videoSpec.size)
        image = image.scaled(impl.videoSpec.size, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    if (av_frame_make_writable(impl.videoFrame.get()) < 0)
        return impl.fail(QStringLiteral("memória de vídeo"));
    const uint8_t *src[4] = {image.constBits(), nullptr, nullptr, nullptr};
    const int srcStride[4] = {int(image.bytesPerLine()), 0, 0, 0};
    sws_scale(impl.sws.get(), src, srcStride, 0, image.height(), impl.videoFrame->data, impl.videoFrame->linesize);
    impl.videoFrame->pts = index;
    impl.videoFrame->duration = 1;
    return impl.encode(impl.video.get(), impl.videoStream, impl.videoFrame.get());
}

bool MediaWriter::writeAudio(const float *interleaved, int frames)
{
    Impl &impl = *d;
    if (!impl.audio)
        return impl.fail(QStringLiteral("sem trilha de áudio"));
    impl.pending.insert(impl.pending.end(), interleaved, interleaved + qsizetype(frames) * impl.channels);
    const int frameSize = impl.audio->frame_size > 0 ? impl.audio->frame_size : 1024;
    while (int(impl.pending.size()) >= frameSize * impl.channels)
        if (!impl.sendAudio(frameSize))
            return false;
    return true;
}

bool MediaWriter::finish(QString *error)
{
    Impl &impl = *d;
    bool ok = impl.error.isEmpty();
    if (ok && impl.audio && !impl.pending.empty())
        ok = impl.sendAudio(int(impl.pending.size()) / impl.channels);
    if (ok && impl.video)
        ok = impl.encode(impl.video.get(), impl.videoStream, nullptr);
    if (ok && impl.audio)
        ok = impl.encode(impl.audio.get(), impl.audioStream, nullptr);
    if (ok) {
        const int r = av_write_trailer(impl.output.get());
        if (r < 0)
            ok = impl.fail(QStringLiteral("finalizar"), r);
    }
    impl.output.reset();
    impl.finished = true;
    if (!ok) {
        if (impl.fileOpened)
            QFile::remove(impl.path);
        if (error)
            *error = impl.error;
    }
    return ok;
}

void MediaWriter::abort()
{
    d->output.reset();
    d->finished = true;
    if (d->fileOpened)
        QFile::remove(d->path);
}

QString MediaWriter::errorString() const { return d->error; }

} // namespace of
