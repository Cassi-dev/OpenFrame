#pragma once

#include "Project.h"

#include <QLocale>

// As opções espelham a tela de exportação do CapCut (resolução, taxa de
// quadros, bitrate, codificador, formato e estimativa), como na versão Swift.

namespace of {

enum class ResolutionPreset { P480, P720, P1080, P1440, P2160, P4320, Custom };
OF_ENUM_KEYS(ResolutionPreset, "p480", "p720", "p1080", "p1440", "p2160", "p4320", "custom")
/// Lado menor do vídeo em pixels (vazio em "Personalizada").
std::optional<int> shortSide(ResolutionPreset);
QString label(ResolutionPreset);

/// Duração de quadro racional: `num/den` segundos (1001/30000 em 29,97 fps).
struct Rational {
    qint64 num = 1;
    qint64 den = 1;
    double seconds() const { return double(num) / double(den); }
    bool operator==(const Rational &) const = default;
};

enum class FrameRate { Fps23_976, Fps24, Fps25, Fps29_97, Fps30, Fps50, Fps59_94, Fps60, Fps120 };
OF_ENUM_KEYS(FrameRate, "fps23_976", "fps24", "fps25", "fps29_97", "fps30", "fps50", "fps59_94", "fps60", "fps120")
Rational frameDuration(FrameRate);
/// Quadros por segundo (24000/1001 etc.).
double fpsValue(FrameRate);
QString label(FrameRate);

enum class VideoCodec { H264, Hevc, ProRes422 };
OF_ENUM_KEYS(VideoCodec, "h264", "hevc", "proRes422")
QString label(VideoCodec);
/// Bits por pixel por quadro na qualidade "Recomendada".
double recommendedBitsPerPixel(VideoCodec);
/// Maior lado aceito (o mesmo limite do Swift, que vem dos codificadores de hardware).
int maxDimension(VideoCodec);

enum class ContainerFormat { Mp4, Mov, M4a };
OF_ENUM_KEYS(ContainerFormat, "mp4", "mov", "m4a")
QString label(ContainerFormat);
QString fileExtension(ContainerFormat);
inline bool isAudioOnly(ContainerFormat c) { return c == ContainerFormat::M4a; }

enum class BitrateMode { Lower, Recommended, Higher, Custom, TargetSize };
OF_ENUM_KEYS(BitrateMode, "lower", "recommended", "higher", "custom", "targetSize")
QString label(BitrateMode);

struct ExportSettings {
    ResolutionPreset resolution = ResolutionPreset::P1080;
    int customWidth = 1920;
    int customHeight = 1080;
    FrameRate frameRate = FrameRate::Fps30;
    VideoCodec codec = VideoCodec::H264;
    ContainerFormat container = ContainerFormat::Mp4;
    BitrateMode bitrateMode = BitrateMode::Recommended;
    /// Usado em `Custom`, em Mbps.
    double customMbps = 10;
    /// Usado em `TargetSize`, em MB.
    double targetMegabytes = 50;
    /// Intervalo entre quadros-chave, em segundos.
    double keyframeInterval = 2;
    bool audioEnabled = true;
    int audioKbps = 192;
    int audioSampleRate = 48000;

    static inline const QList<int> audioBitrates{96, 128, 192, 256, 320};
    static inline const QList<int> sampleRates{44100, 48000};

    /// Dimensões finais do vídeo (sempre pares, como exigem os codificadores).
    QSize outputSize(const Project &) const;
    /// Bitrate médio de vídeo em bits/s.
    qint64 videoBitrate(QSize size, Micros duration) const;
    /// Tamanho estimado do arquivo em bytes (vídeo + áudio + ~1% de contêiner).
    qint64 estimatedBytes(const Project &) const;
    /// Mensagem de erro se a combinação não puder ser exportada (vazio = pode).
    std::optional<QString> validationError(const Project &) const;
    /// Quadros entre quadros-chave (pelo menos 1).
    int keyframeDistance() const;

    bool operator==(const ExportSettings &) const = default;
};

/// "12,3 MB" etc., como o `ByteCountFormatter` (estilo arquivo, base 1000).
QString formattedFileSize(qint64 bytes, const QLocale &locale = QLocale());

} // namespace of
