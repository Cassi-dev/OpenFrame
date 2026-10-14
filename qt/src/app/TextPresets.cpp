#include "TextPresets.h"

#include <QVariantMap>

namespace of::TextPresets {

QVariantList list()
{
    static const QList<std::pair<const char *, const char *>> presets{
        {"classic", "Clássico"}, {"outline", "Contorno"}, {"highlight", "Destaque"}, {"neon", "Neon"},
        {"caption", "Legenda"},  {"label", "Etiqueta"},   {"longShadow", "Sombra dura"}, {"spaced", "Espaçado"},
    };
    QVariantList out;
    for (const auto &[value, title] : presets)
        out.append(QVariantMap{{"value", QString::fromLatin1(value)}, {"title", QString::fromUtf8(title)}});
    return out;
}

TextStyle applied(const QString &preset, const TextStyle &old)
{
    TextStyle s;
    s.fontName = old.fontName;
    s.fontFace = old.fontFace;
    s.fontSize = old.fontSize;
    s.x = old.x;
    s.y = old.y;
    s.scale = old.scale;
    s.rotation = old.rotation;
    s.maxWidth = old.maxWidth;
    s.alignment = old.alignment;
    if (preset == "outline") {
        s.strokeWidth = 8;
        s.shadow = false;
    } else if (preset == "highlight") {
        s.color = RGBA::black();
        s.backgroundEnabled = true;
        s.backgroundColor = RGBA::yellow();
        s.backgroundRadius = 0.12;
        s.shadow = false;
    } else if (preset == "neon") {
        // Brilho feito com a sombra: sem distância, bem desfocada, na cor do texto.
        s.color = {0.3, 1, 0.95, 1};
        s.strokeWidth = 2;
        s.strokeColor = {0.05, 0.2, 0.4, 1};
        s.shadowColor = {0.3, 1, 0.95, 0.9};
        s.shadowDistance = 0;
        s.shadowBlur = 0.35;
    } else if (preset == "caption") {
        s.bold = false;
        s.backgroundEnabled = true;
        s.backgroundColor = {0, 0, 0, 0.55};
        s.backgroundRadius = 0.25;
        s.backgroundPaddingX = 0.35;
        s.backgroundPaddingY = 0.15;
        s.shadow = false;
    } else if (preset == "label") {
        s.textCase = TextCase::Upper;
        s.letterSpacing = 0.08;
        s.backgroundEnabled = true;
        s.backgroundColor = {0.9, 0.2, 0.25, 1};
        s.backgroundRadius = 1;
        s.backgroundPaddingX = 0.5;
        s.shadow = false;
    } else if (preset == "longShadow") {
        s.shadowColor = {0, 0, 0, 1};
        s.shadowAngle = -45;
        s.shadowDistance = 0.1;
        s.shadowBlur = 0;
    } else if (preset == "spaced") {
        s.textCase = TextCase::Upper;
        s.bold = false;
        s.letterSpacing = 0.3;
        s.lineSpacing = 0.2;
        s.shadow = false;
    }
    return s;
}

} // namespace of::TextPresets
