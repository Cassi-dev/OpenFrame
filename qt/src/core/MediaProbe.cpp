#include "MediaProbe.h"

#include "FFmpeg.h"
#include "VideoDecoder.h"

#include <QColorSpace>
#include <QFileInfo>
#include <QImageReader>
#include <QSet>
#include <cmath>

namespace of {

namespace {

// Extensões que o macOS classifica como imagem ou conteúdo audiovisual
// (UTType .image / .audiovisualContent), as que o Swift aceita.
const QSet<QString> &imageExtensions()
{
    static const QSet<QString> set{"png", "jpg", "jpeg", "jpe", "heic", "heif", "hif", "avif", "gif", "bmp", "tif",
                                   "tiff", "webp", "jxl", "dng", "raw", "cr2", "cr3", "nef", "arw", "orf", "rw2",
                                   "raf", "ico", "icns", "tga", "psd", "exr", "hdr", "jp2", "pbm", "pgm", "ppm", "svg"};
    return set;
}

const QSet<QString> &audioExtensions()
{
    static const QSet<QString> set{"m4a", "mp3", "wav", "wave", "aac", "aif", "aiff", "aifc", "caf", "flac",
                                   "ogg", "oga", "opus", "wma", "m4b", "m4r", "amr", "ac3", "eac3", "mka", "au", "snd"};
    return set;
}

const QSet<QString> &videoExtensions()
{
    static const QSet<QString> set{"mov", "mp4", "m4v", "mkv", "webm", "avi", "mts", "m2ts", "ts", "3gp", "3g2",
                                   "mpg", "mpeg", "m2v", "vob", "wmv", "asf", "flv", "f4v", "ogv", "dv", "mxf", "qt"};
    return set;
}

QString extensionOf(const QString &path) { return QFileInfo(path).suffix().toLower(); }

void setError(QString *error, const QString &message)
{
    if (error)
        *error = message;
}

QString unsupported(const QString &name) { return QStringLiteral("Formato não suportado: %1").arg(name); }
QString unreadable(const QString &name) { return QStringLiteral("Não foi possível ler: %1").arg(name); }

std::optional<Material> probeImage(const QString &path, const QString &name, QString *error)
{
    Material m;
    m.kind = MaterialKind::Photo;
    m.path = path;
    m.name = name;
    QImageReader reader(path);
    QSize size = reader.size();
    if (size.isValid()) {
        // Orientações EXIF 5–8 giram a imagem em 90°.
        if (reader.transformation() & QImageIOHandler::TransformationRotate90)
            size.transpose();
    } else {
        // Formatos que o Qt não lê (HEIC fora do Mac): o FFmpeg decodifica.
        const auto decoder = VideoDecoder::open(path);
        size = decoder ? decoder->displaySize() : QSize();
    }
    if (!size.isValid() || size.isEmpty()) {
        setError(error, unreadable(name));
        return std::nullopt;
    }
    m.width = size.width();
    m.height = size.height();
    return m;
}

std::optional<Material> probeAV(const QString &path, const QString &name, bool audioOnlyType, QString *error)
{
    const ff::InputPtr input = ff::openInput(path);
    if (!input) {
        setError(error, unreadable(name));
        return std::nullopt;
    }
    const AVStream *video = nullptr;
    bool hasAudio = false;
    for (unsigned i = 0; i < input->nb_streams; ++i) {
        const AVStream *s = input->streams[i];
        if (!video && ff::isRealVideo(s))
            video = s;
        hasAudio = hasAudio || s->codecpar->codec_type == AVMEDIA_TYPE_AUDIO;
    }
    Material m;
    m.path = path;
    m.name = name;
    m.duration = input->duration != AV_NOPTS_VALUE ? Micros(input->duration) : 0;
    m.hasAudio = hasAudio;
    if (video && !audioOnlyType) {
        const AVRational sar = av_guess_sample_aspect_ratio(input.get(), const_cast<AVStream *>(video), nullptr);
        const double ratio = sar.num > 0 && sar.den > 0 ? av_q2d(sar) : 1;
        int w = int(std::lround(video->codecpar->width * ratio));
        int h = video->codecpar->height;
        if (ff::displayTransform(video).rotation % 180 != 0)
            std::swap(w, h);
        m.kind = MaterialKind::Video;
        m.width = w;
        m.height = h;
        if (m.duration <= 0 && video->duration != AV_NOPTS_VALUE)
            m.duration = ff::toMicros(video->duration, video->time_base);
        return m;
    }
    if (!hasAudio) {
        setError(error, unreadable(name));
        return std::nullopt;
    }
    m.kind = MaterialKind::Audio;
    m.hasAudio = true;
    return m;
}

} // namespace

bool MediaProbe::isImageExtension(const QString &extension) { return imageExtensions().contains(extension.toLower()); }

bool MediaProbe::isAudioExtension(const QString &extension) { return audioExtensions().contains(extension.toLower()); }

bool MediaProbe::isSupported(const QString &path)
{
    const QString ext = extensionOf(path);
    return imageExtensions().contains(ext) || audioExtensions().contains(ext) || videoExtensions().contains(ext);
}

std::optional<Material> MediaProbe::probe(const QString &path, QString *error)
{
    const QString name = QFileInfo(path).fileName();
    const QString ext = extensionOf(path);
    if (imageExtensions().contains(ext))
        return probeImage(path, name, error);
    if (audioExtensions().contains(ext) || videoExtensions().contains(ext))
        return probeAV(path, name, audioExtensions().contains(ext), error);
    setError(error, unsupported(name));
    return std::nullopt;
}

QImage Images::load(const QString &path, int maxSide, QString *error)
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QSize original = reader.size();
    if (maxSide > 0 && original.isValid() && std::max(original.width(), original.height()) > maxSide) {
        // A escala vale nos dois sentidos, então serve antes de girar.
        const double scale = double(maxSide) / std::max(original.width(), original.height());
        reader.setScaledSize(QSize(std::max(1, int(std::lround(original.width() * scale))),
                                   std::max(1, int(std::lround(original.height() * scale)))));
    }
    QImage image = reader.read();
    if (image.isNull()) {
        // Sem leitor no Qt: o FFmpeg decodifica (HEIC, alguns RAW).
        if (auto decoder = VideoDecoder::open(path)) {
            const QSize box = maxSide > 0 ? QSize(maxSide, maxSide) : QSize();
            image = decoder->frameAt(0, box);
        }
        if (image.isNull()) {
            if (error)
                *error = reader.errorString();
            return {};
        }
    }
    // Cores para sRGB, como o Core Image faz ao desenhar a foto no canvas.
    if (image.colorSpace().isValid() && image.colorSpace() != QColorSpace(QColorSpace::SRgb)) {
        image = image.convertedToColorSpace(QColorSpace(QColorSpace::SRgb),
                                            image.hasAlphaChannel() ? QImage::Format_ARGB32 : QImage::Format_RGB32);
    }
    image.convertTo(QImage::Format_ARGB32_Premultiplied);
    image.setColorSpace(QColorSpace());
    return image;
}

} // namespace of
