#pragma once

#include "Enums.h"
#include "Timing.h"

#include <QColor>
#include <QUuid>
#include <optional>

namespace of {

struct RGBA {
    double r = 0, g = 0, b = 0, a = 1;

    static RGBA white() { return {1, 1, 1, 1}; }
    static RGBA black() { return {0, 0, 0, 1}; }
    static RGBA yellow() { return {1, 0.85, 0.1, 1}; }
    QColor color() const { return QColor::fromRgbF(float(r), float(g), float(b), float(a)); }
    bool operator==(const RGBA &) const = default;
};

/// Posição, escala e rotação do clipe no canvas. `x`/`y` são normalizados
/// em -1...1 (centro = 0, `y` positivo para cima); `rotation` em graus.
struct Transform {
    double scale = 1;
    double x = 0;
    double y = 0;
    double rotation = 0;
    bool operator==(const Transform &) const = default;
};

/// Painel "Ajustar". Valores bipolares em -1...1, unipolares em 0...1.
struct Adjust {
    double brightness = 0;
    double contrast = 0;
    double saturation = 0;
    double exposure = 0;
    double temperature = 0;
    double tint = 0;
    double highlights = 0;
    double shadows = 0;
    double hue = 0;
    double sharpen = 0;
    double vignette = 0;
    double fade = 0;
    double grain = 0;

    bool isIdentity() const { return *this == Adjust{}; }
    bool operator==(const Adjust &) const = default;
};

enum class FilterPreset { None, Vivid, Warm, Cool, Cinematic, Vintage, Mono, Noir, Chrome, Fade, Instant, Process, Tonal, Transfer, Sepia };
OF_ENUM_KEYS(FilterPreset, "none", "vivid", "warm", "cool", "cinematic", "vintage", "mono", "noir", "chrome", "fade",
             "instant", "process", "tonal", "transfer", "sepia")
QString displayName(FilterPreset);

struct FilterSetting {
    FilterPreset preset = FilterPreset::None;
    double intensity = 1;
    bool operator==(const FilterSetting &) const = default;
};

enum class VideoEffectKind { Blur, Pixelate, RgbSplit, Mirror, Shake, Flash, ZoomPulse, Kaleidoscope, Comic, Edges };
OF_ENUM_KEYS(VideoEffectKind, "blur", "pixelate", "rgbSplit", "mirror", "shake", "flash", "zoomPulse", "kaleidoscope",
             "comic", "edges")
QString displayName(VideoEffectKind);

struct VideoEffect {
    QUuid id = QUuid::createUuid();
    VideoEffectKind kind = VideoEffectKind::Blur;
    double intensity = 0.5;
    bool operator==(const VideoEffect &) const = default;
};

enum class AnimationKind { Fade, ZoomIn, ZoomOut, SlideLeft, SlideRight, SlideUp, SlideDown, Spin, Typewriter };
OF_ENUM_KEYS(AnimationKind, "fade", "zoomIn", "zoomOut", "slideLeft", "slideRight", "slideUp", "slideDown", "spin",
             "typewriter")
QString displayName(AnimationKind);
/// Animações que só fazem sentido em texto.
inline bool isTextOnly(AnimationKind k) { return k == AnimationKind::Typewriter; }

struct SegmentAnimation {
    AnimationKind kind = AnimationKind::Fade;
    Micros duration = 500'000;
    bool operator==(const SegmentAnimation &) const = default;
};

enum class TransitionKind { Dissolve, FadeBlack, FadeWhite, WipeLeft, WipeRight, SlideLeft, SlideRight, Zoom, Blur };
OF_ENUM_KEYS(TransitionKind, "dissolve", "fadeBlack", "fadeWhite", "wipeLeft", "wipeRight", "slideLeft", "slideRight",
             "zoom", "blur")
QString displayName(TransitionKind);

/// Transição entre este segmento e o próximo da mesma faixa.
struct Transition {
    TransitionKind kind = TransitionKind::Dissolve;
    Micros duration = 500'000;
    bool operator==(const Transition &) const = default;
};

enum class TextAlignment { Left, Center, Right };
OF_ENUM_KEYS(TextAlignment, "left", "center", "right")

/// Caixa das letras aplicada na hora de desenhar; o texto guardado não muda.
enum class TextCase { None, Upper, Lower, Title };
OF_ENUM_KEYS(TextCase, "none", "upper", "lower", "title")

/// Estilo de um texto. Medidas tipográficas (espaçamentos, sombra, margens e
/// raio do fundo) são frações do tamanho da fonte (em), como no CapCut.
struct TextStyle {
    QString fontName = QStringLiteral("Helvetica Neue");
    /// Estilo dentro da família ("Light", "Medium"…); vazio = estilo normal.
    QString fontFace;
    /// Tamanho como fração da altura do canvas.
    double fontSize = 0.07;
    bool bold = true;
    bool italic = false;
    bool underline = false;
    TextCase textCase = TextCase::None;
    RGBA color = RGBA::white();
    double opacity = 1;
    RGBA strokeColor = RGBA::black();
    /// Espessura do contorno em % do tamanho da fonte (0 = sem contorno).
    double strokeWidth = 0;
    double letterSpacing = 0;
    double lineSpacing = 0;
    bool backgroundEnabled = false;
    RGBA backgroundColor{0, 0, 0, 0.6};
    double backgroundRadius = 0.18;
    double backgroundPaddingX = 0.21;
    double backgroundPaddingY = 0.21;
    bool shadow = true;
    RGBA shadowColor{0, 0, 0, 0.65};
    double shadowDistance = 0.04;
    /// Direção da sombra em graus: 0 = direita, 90 = cima, -90 = baixo.
    double shadowAngle = -90;
    double shadowBlur = 0.15;
    TextAlignment alignment = TextAlignment::Center;
    double x = 0;
    double y = -0.7;
    double scale = 1;
    double rotation = 0;
    /// Largura máxima da caixa como fração da largura do canvas.
    double maxWidth = 0.9;

    bool operator==(const TextStyle &) const = default;
};

struct TextContent {
    QString text;
    TextStyle style;
    bool operator==(const TextContent &) const = default;
};

} // namespace of
