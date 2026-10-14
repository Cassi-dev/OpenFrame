#include "Effects.h"

namespace of {

QString displayName(FilterPreset p)
{
    switch (p) {
    case FilterPreset::None: return QStringLiteral("Nenhum");
    case FilterPreset::Vivid: return QStringLiteral("Vívido");
    case FilterPreset::Warm: return QStringLiteral("Quente");
    case FilterPreset::Cool: return QStringLiteral("Frio");
    case FilterPreset::Cinematic: return QStringLiteral("Cinema");
    case FilterPreset::Vintage: return QStringLiteral("Vintage");
    case FilterPreset::Mono: return QStringLiteral("Mono");
    case FilterPreset::Noir: return QStringLiteral("Noir");
    case FilterPreset::Chrome: return QStringLiteral("Cromo");
    case FilterPreset::Fade: return QStringLiteral("Desbotado");
    case FilterPreset::Instant: return QStringLiteral("Instantânea");
    case FilterPreset::Process: return QStringLiteral("Processo");
    case FilterPreset::Tonal: return QStringLiteral("Tonal");
    case FilterPreset::Transfer: return QStringLiteral("Transferência");
    case FilterPreset::Sepia: return QStringLiteral("Sépia");
    }
    return {};
}

QString displayName(VideoEffectKind k)
{
    switch (k) {
    case VideoEffectKind::Blur: return QStringLiteral("Desfoque");
    case VideoEffectKind::Pixelate: return QStringLiteral("Pixelizar");
    case VideoEffectKind::RgbSplit: return QStringLiteral("Glitch RGB");
    case VideoEffectKind::Mirror: return QStringLiteral("Espelho");
    case VideoEffectKind::Shake: return QStringLiteral("Tremor");
    case VideoEffectKind::Flash: return QStringLiteral("Flash");
    case VideoEffectKind::ZoomPulse: return QStringLiteral("Pulso de zoom");
    case VideoEffectKind::Kaleidoscope: return QStringLiteral("Caleidoscópio");
    case VideoEffectKind::Comic: return QStringLiteral("Quadrinhos");
    case VideoEffectKind::Edges: return QStringLiteral("Contornos neon");
    }
    return {};
}

QString displayName(AnimationKind k)
{
    switch (k) {
    case AnimationKind::Fade: return QStringLiteral("Esmaecer");
    case AnimationKind::ZoomIn: return QStringLiteral("Zoom de aproximação");
    case AnimationKind::ZoomOut: return QStringLiteral("Zoom de afastamento");
    case AnimationKind::SlideLeft: return QStringLiteral("Deslizar ←");
    case AnimationKind::SlideRight: return QStringLiteral("Deslizar →");
    case AnimationKind::SlideUp: return QStringLiteral("Deslizar ↑");
    case AnimationKind::SlideDown: return QStringLiteral("Deslizar ↓");
    case AnimationKind::Spin: return QStringLiteral("Girar");
    case AnimationKind::Typewriter: return QStringLiteral("Máquina de escrever");
    }
    return {};
}

QString displayName(TransitionKind k)
{
    switch (k) {
    case TransitionKind::Dissolve: return QStringLiteral("Dissolver");
    case TransitionKind::FadeBlack: return QStringLiteral("Escurecer");
    case TransitionKind::FadeWhite: return QStringLiteral("Clarear");
    case TransitionKind::WipeLeft: return QStringLiteral("Cortina ←");
    case TransitionKind::WipeRight: return QStringLiteral("Cortina →");
    case TransitionKind::SlideLeft: return QStringLiteral("Empurrar ←");
    case TransitionKind::SlideRight: return QStringLiteral("Empurrar →");
    case TransitionKind::Zoom: return QStringLiteral("Zoom");
    case TransitionKind::Blur: return QStringLiteral("Desfoque");
    }
    return {};
}

} // namespace of
