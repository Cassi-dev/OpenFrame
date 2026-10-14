#include "ExportSettings.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <string>

namespace of {

std::optional<int> shortSide(ResolutionPreset r)
{
    switch (r) {
    case ResolutionPreset::P480: return 480;
    case ResolutionPreset::P720: return 720;
    case ResolutionPreset::P1080: return 1080;
    case ResolutionPreset::P1440: return 1440;
    case ResolutionPreset::P2160: return 2160;
    case ResolutionPreset::P4320: return 4320;
    case ResolutionPreset::Custom: return std::nullopt;
    }
    return std::nullopt;
}

QString label(ResolutionPreset r)
{
    switch (r) {
    case ResolutionPreset::P480: return QStringLiteral("480p");
    case ResolutionPreset::P720: return QStringLiteral("720p");
    case ResolutionPreset::P1080: return QStringLiteral("1080p");
    case ResolutionPreset::P1440: return QStringLiteral("2K");
    case ResolutionPreset::P2160: return QStringLiteral("4K");
    case ResolutionPreset::P4320: return QStringLiteral("8K");
    case ResolutionPreset::Custom: return QStringLiteral("Personalizada");
    }
    return {};
}

Rational frameDuration(FrameRate f)
{
    switch (f) {
    case FrameRate::Fps23_976: return {1001, 24000};
    case FrameRate::Fps24: return {1, 24};
    case FrameRate::Fps25: return {1, 25};
    case FrameRate::Fps29_97: return {1001, 30000};
    case FrameRate::Fps30: return {1, 30};
    case FrameRate::Fps50: return {1, 50};
    case FrameRate::Fps59_94: return {1001, 60000};
    case FrameRate::Fps60: return {1, 60};
    case FrameRate::Fps120: return {1, 120};
    }
    return {1, 30};
}

// Mesma conta do Swift (1 / frameDuration.seconds), para os mesmos bitrates.
double fpsValue(FrameRate f) { return 1 / frameDuration(f).seconds(); }

QString label(FrameRate f)
{
    switch (f) {
    case FrameRate::Fps23_976: return QStringLiteral("23,976 fps");
    case FrameRate::Fps24: return QStringLiteral("24 fps");
    case FrameRate::Fps25: return QStringLiteral("25 fps");
    case FrameRate::Fps29_97: return QStringLiteral("29,97 fps");
    case FrameRate::Fps30: return QStringLiteral("30 fps");
    case FrameRate::Fps50: return QStringLiteral("50 fps");
    case FrameRate::Fps59_94: return QStringLiteral("59,94 fps");
    case FrameRate::Fps60: return QStringLiteral("60 fps");
    case FrameRate::Fps120: return QStringLiteral("120 fps");
    }
    return {};
}

QString label(VideoCodec c)
{
    switch (c) {
    case VideoCodec::H264: return QStringLiteral("H.264");
    case VideoCodec::Hevc: return QStringLiteral("HEVC (H.265)");
    case VideoCodec::ProRes422: return QStringLiteral("Apple ProRes 422");
    }
    return {};
}

double recommendedBitsPerPixel(VideoCodec c)
{
    switch (c) {
    case VideoCodec::H264: return 0.1;
    case VideoCodec::Hevc: return 0.065;
    case VideoCodec::ProRes422: return 2.36; // ~147 Mbps em 1080p30 (ProRes não usa bitrate alvo)
    }
    return 0.1;
}

int maxDimension(VideoCodec c) { return c == VideoCodec::H264 ? 4096 : 8192; }

QString label(ContainerFormat c)
{
    switch (c) {
    case ContainerFormat::Mp4: return QStringLiteral("MP4");
    case ContainerFormat::Mov: return QStringLiteral("MOV");
    case ContainerFormat::M4a: return QStringLiteral("M4A (só áudio)");
    }
    return {};
}

QString fileExtension(ContainerFormat c) { return enumKey(c); }

QString label(BitrateMode m)
{
    switch (m) {
    case BitrateMode::Lower: return QStringLiteral("Mais baixa");
    case BitrateMode::Recommended: return QStringLiteral("Recomendada");
    case BitrateMode::Higher: return QStringLiteral("Mais alta");
    case BitrateMode::Custom: return QStringLiteral("Bitrate personalizado");
    case BitrateMode::TargetSize: return QStringLiteral("Tamanho de arquivo alvo");
    }
    return {};
}

// MARK: - Cálculos

QSize ExportSettings::outputSize(const Project &project) const
{
    const auto even = [](int v) { return std::max(2, v / 2 * 2); };
    if (const auto side = shortSide(resolution))
        return project.canvasSize(*side);
    return {even(customWidth), even(customHeight)};
}

qint64 ExportSettings::videoBitrate(QSize size, Micros duration) const
{
    const double pixelsPerSecond = double(size.width()) * double(size.height()) * fpsValue(frameRate);
    const double recommended = pixelsPerSecond * recommendedBitsPerPixel(codec);
    double bps = recommended;
    switch (bitrateMode) {
    case BitrateMode::Lower: bps = recommended * 0.55; break;
    case BitrateMode::Recommended: bps = recommended; break;
    case BitrateMode::Higher: bps = recommended * 1.8; break;
    case BitrateMode::Custom: bps = customMbps * 1'000'000; break;
    case BitrateMode::TargetSize: {
        const double seconds = std::max(Time::toSeconds(duration), 0.1);
        const double audio = audioEnabled ? double(audioKbps * 1000) : 0;
        bps = targetMegabytes * 8'000'000 / seconds - audio;
        break;
    }
    }
    return qint64(std::min(std::max(bps, 100'000.0), 800'000'000.0));
}

qint64 ExportSettings::estimatedBytes(const Project &project) const
{
    const Micros duration = project.duration();
    const double audio = audioEnabled ? double(audioKbps * 1000) : 0;
    const double video = isAudioOnly(container) ? 0 : double(videoBitrate(outputSize(project), duration));
    return qint64((video + audio) * Time::toSeconds(duration) / 8 * 1.01);
}

std::optional<QString> ExportSettings::validationError(const Project &project) const
{
    if (project.duration() <= 0)
        return QStringLiteral("A timeline está vazia.");
    if (isAudioOnly(container)) {
        if (audioEnabled)
            return std::nullopt;
        return QStringLiteral("Ative o áudio para exportar M4A.");
    }
    const QSize size = outputSize(project);
    if (size.width() < 16 || size.height() < 16)
        return QStringLiteral("Resolução muito pequena.");
    if (std::max(size.width(), size.height()) > maxDimension(codec))
        return QStringLiteral("%1 suporta até %2 px no lado maior. Use HEVC ou ProRes, ou reduza a resolução.")
            .arg(label(codec))
            .arg(maxDimension(codec));
    if (codec == VideoCodec::ProRes422 && container != ContainerFormat::Mov)
        return QStringLiteral("ProRes só pode ser exportado em MOV.");
    return std::nullopt;
}

int ExportSettings::keyframeDistance() const
{
    return std::max(1, int(Time::round(fpsValue(frameRate) * keyframeInterval)));
}

QString formattedFileSize(qint64 bytes, const QLocale &locale)
{
    if (bytes == 0)
        return QStringLiteral("Zero KB");
    if (std::abs(bytes) < 1000)
        return QStringLiteral("%1 %2").arg(locale.toString(bytes), std::abs(bytes) == 1 ? u"byte" : u"bytes");
    // Casas decimais por unidade, como o ByteCountFormatter: KB 0, MB 1, GB em diante 2.
    struct Unit {
        const char *name;
        int decimals;
    };
    static constexpr Unit units[] = {{"KB", 0}, {"MB", 1}, {"GB", 2}, {"TB", 2}, {"PB", 2}, {"EB", 2}};
    // Arredonda a representação decimal mais curta, metade para cima, como o
    // NumberFormatter: 1,005 GB vira "1,01 GB" (o double fica em 1,00499…).
    const auto roundDecimal = [](double v, int decimals) {
        char buf[64];
        const auto res = std::to_chars(buf, buf + sizeof buf, std::abs(v), std::chars_format::fixed);
        const std::string digits(buf, res.ptr);
        const auto point = digits.find('.');
        const std::string whole = digits.substr(0, point);
        std::string frac = point == std::string::npos ? std::string() : digits.substr(point + 1);
        frac.resize(std::max<size_t>(frac.size(), size_t(decimals) + 1), '0');
        qint64 units = std::stoll(whole);
        for (int i = 0; i < decimals; ++i)
            units = units * 10 + (frac[i] - '0');
        if (frac[decimals] >= '5')
            ++units;
        return std::copysign(double(units) / std::pow(10.0, decimals), v);
    };
    double value = double(bytes) / 1000;
    size_t u = 0;
    for (;;) {
        const double rounded = roundDecimal(value, units[u].decimals);
        if (std::abs(rounded) < 1000 || u + 1 == std::size(units)) {
            value = rounded;
            break;
        }
        value /= 1000;
        ++u;
    }
    QString number = locale.toString(value, 'f', units[u].decimals);
    if (units[u].decimals > 0) {
        const QString point = locale.decimalPoint();
        while (number.endsWith(u'0'))
            number.chop(1);
        if (number.endsWith(point))
            number.chop(point.size());
    }
    return QStringLiteral("%1 %2").arg(number, QLatin1StringView(units[u].name));
}

} // namespace of
