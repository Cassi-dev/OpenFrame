#pragma once

// Gera arquivos de mídia sintéticos para os testes (como o TestMedia.swift),
// gravando com o FFmpeg pelo MediaWriter do núcleo.

#include "MediaWriter.h"

#include <QCoreApplication>
#include <QDir>
#include <QImageWriter>
#include <QPainter>
#include <QTest>
#include <cmath>

namespace of::test {

inline QString mediaDirectory()
{
    static const QString dir = [] {
        const QString d =
            QDir::temp().filePath(QStringLiteral("OpenFrameQtTests-%1").arg(QCoreApplication::applicationPid()));
        QDir().mkpath(d);
        return d;
    }();
    return dir;
}

inline QString tempPath(const QString &extension)
{
    return mediaDirectory() + u'/' + QUuid::createUuid().toString(QUuid::WithoutBraces) + u'.' + extension;
}

struct VideoOptions {
    int width = 320;
    int height = 180;
    double seconds = 2;
    int fps = 30;
    bool audio = true;
    /// Rotação de exibição gravada na trilha (graus, sentido horário).
    int rotation = 0;
    QString extension = QStringLiteral("mov");
    VideoCodec codec = VideoCodec::H264;
    MediaWriter::Matrix matrix = MediaWriter::Matrix::BT709;
    bool tagged = true;
    bool fullRange = false;
    QColor top{220, 30, 30};
    QColor bottom{30, 30, 220};
    /// Faixa branca que anda a cada quadro (desligar para cores lisas).
    bool bar = true;
};

/// Quadro do vídeo de teste: metade de cima `top`, de baixo `bottom` e uma
/// faixa branca de 5 px em x = largura × quadro / quadros.
inline QImage testFrame(const VideoOptions &o, int frame, int frames)
{
    QImage image(o.width, o.height, QImage::Format_ARGB32_Premultiplied);
    QPainter p(&image);
    p.fillRect(0, 0, o.width, o.height / 2, o.top);
    p.fillRect(0, o.height / 2, o.width, o.height - o.height / 2, o.bottom);
    if (o.bar) {
        const int barX = o.width * frame / std::max(frames, 1);
        p.fillRect(barX - 2, 0, 5, o.height, Qt::white);
    }
    return image;
}

/// Seno de 440 Hz com amplitude 12000/32768, mono.
inline std::vector<float> sine(qint64 start, int count, int sampleRate)
{
    std::vector<float> samples(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i)
        samples[size_t(i)] = float(std::sin(2 * M_PI * 440 * double(start + i) / sampleRate) * 12000 / 32768);
    return samples;
}

inline QString makeVideo(const VideoOptions &o = {})
{
    const QString path = tempPath(o.extension);
    MediaWriter::Video video;
    video.size = QSize(o.width, o.height);
    video.frameDuration = {1, o.fps};
    video.codec = o.codec;
    video.matrix = o.matrix;
    video.tagged = o.tagged;
    video.fullRange = o.fullRange;
    video.rotation = o.rotation;
    video.preset = QStringLiteral("veryfast");
    std::optional<MediaWriter::Audio> audio;
    if (o.audio)
        audio = MediaWriter::Audio{48000, 1, 96'000};
    QString error;
    auto writer = MediaWriter::create(path, video, audio, &error);
    if (!writer)
        qFatal("makeVideo: %s", qPrintable(error));
    const int frames = int(o.seconds * o.fps);
    for (int f = 0; f < frames; ++f)
        if (!writer->writeVideo(testFrame(o, f, frames), f))
            qFatal("makeVideo: %s", qPrintable(writer->errorString()));
    if (o.audio) {
        const int total = int(o.seconds * 48000);
        for (int offset = 0; offset < total; offset += 1024) {
            const int count = std::min(1024, total - offset);
            const auto samples = sine(offset, count, 48000);
            writer->writeAudio(samples.data(), count);
        }
    }
    if (!writer->finish(&error))
        qFatal("makeVideo: %s", qPrintable(error));
    return path;
}

/// Áudio AAC mono (seno) num .m4a.
inline QString makeAudio(double seconds = 1)
{
    const QString path = tempPath(QStringLiteral("m4a"));
    QString error;
    auto writer = MediaWriter::create(path, std::nullopt, MediaWriter::Audio{48000, 1, 96'000}, &error);
    if (!writer)
        qFatal("makeAudio: %s", qPrintable(error));
    const int total = int(seconds * 48000);
    const auto samples = sine(0, total, 48000);
    writer->writeAudio(samples.data(), total);
    if (!writer->finish(&error))
        qFatal("makeAudio: %s", qPrintable(error));
    return path;
}

/// Imagem de cor sólida (ou metade de cima/de baixo) gravada no formato da extensão.
/// `transformation` grava a orientação EXIF (só JPEG).
inline QString makeImage(const QString &extension, int width, int height, QColor top, QColor bottom,
                         QImageIOHandler::Transformations transformation = QImageIOHandler::TransformationNone)
{
    QImage image(width, height, QImage::Format_RGB32);
    QPainter p(&image);
    p.fillRect(0, 0, width, height / 2, top);
    p.fillRect(0, height / 2, width, height - height / 2, bottom);
    p.end();
    const QString path = tempPath(extension);
    QImageWriter writer(path);
    writer.setTransformation(transformation);
    writer.setQuality(100);
    if (!writer.write(image))
        qFatal("makeImage: %s", qPrintable(writer.errorString()));
    return path;
}

/// Cor do pixel em coordenadas normalizadas 0…1 (y = 0 no topo).
inline QColor pixel(const QImage &image, double x, double y)
{
    const int px = std::min(image.width() - 1, int(x * image.width()));
    const int py = std::min(image.height() - 1, int(y * image.height()));
    return image.pixelColor(px, py);
}

inline bool near(const QColor &a, const QColor &b, int tolerance)
{
    return std::abs(a.red() - b.red()) <= tolerance && std::abs(a.green() - b.green()) <= tolerance &&
           std::abs(a.blue() - b.blue()) <= tolerance;
}

inline QString describe(const QColor &c) { return QStringLiteral("(%1, %2, %3)").arg(c.red()).arg(c.green()).arg(c.blue()); }

} // namespace of::test
