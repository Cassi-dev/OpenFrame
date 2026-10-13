#pragma once

#include "ExportSettings.h"

#include <QImage>
#include <memory>

namespace of {

/// Grava vídeo (H.264/HEVC/ProRes) e áudio AAC num MP4/MOV/M4A com o FFmpeg.
/// O contêiner sai da extensão do arquivo. Base do `Exporter` e do gerador de
/// mídia sintética dos testes.
class MediaWriter
{
public:
    enum class Matrix { BT709, BT601 };

    struct Video {
        QSize size;
        Rational frameDuration{1, 30};
        VideoCodec codec = VideoCodec::H264;
        /// Bitrate médio em bits/s; 0 = qualidade constante do codificador.
        qint64 bitrate = 0;
        /// Quadros entre quadros-chave (0 = padrão do codificador).
        int keyframeDistance = 0;
        /// Matriz RGB → YUV e as marcas de cor gravadas (primárias, transferência
        /// e matriz). `tagged = false` grava sem marcas, para os testes.
        Matrix matrix = Matrix::BT709;
        bool tagged = true;
        bool fullRange = false;
        /// Rotação de exibição gravada na matriz da trilha (graus, sentido horário).
        int rotation = 0;
        /// Preset do x264/x265 ("veryfast", "medium"…).
        QString preset = QStringLiteral("medium");
    };

    struct Audio {
        int sampleRate = 48000;
        int channels = 2;
        int bitrate = 192'000;
    };

    static std::unique_ptr<MediaWriter> create(const QString &path, const std::optional<Video> &video,
                                               const std::optional<Audio> &audio, QString *error = nullptr);
    ~MediaWriter();

    /// Quadro `index` (pts = index × frameDuration). A imagem é redimensionada
    /// se não tiver o tamanho do vídeo.
    bool writeVideo(const QImage &frame, qint64 index);
    /// Amostras float intercaladas (`frames` × canais), em ordem.
    bool writeAudio(const float *interleaved, int frames);
    /// Esvazia os codificadores e fecha o arquivo.
    bool finish(QString *error = nullptr);
    /// Fecha sem terminar e apaga o arquivo parcial.
    void abort();

    QString errorString() const;

private:
    MediaWriter();
    struct Impl;
    std::unique_ptr<Impl> d;
};

} // namespace of
