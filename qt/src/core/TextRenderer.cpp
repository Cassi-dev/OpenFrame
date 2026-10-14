#include "TextRenderer.h"

#include "LinearImage.h"

#include <QFontDatabase>
#include <QGlyphRun>
#include <QLocale>
#include <QPainter>
#include <QPainterPath>
#include <QRawFont>
#include <QTextBoundaryFinder>
#include <QTextLayout>
#include <cmath>

namespace of {

namespace {

/// Inclinação do itálico sintético (12°).
const double syntheticSlant = std::tan(12 * M_PI / 180);
/// Espessura extra do negrito sintético, em em.
constexpr double syntheticBold = 0.03;

struct FontFace {
    QFont font;
    bool syntheticBold = false;
    bool syntheticItalic = false;
};

/// Família pedida; sem ela (Helvetica Neue fora do Mac), a Inter que o app
/// distribui ou a fonte padrão do sistema.
QString resolveFamily(const QString &name)
{
    if (QFontDatabase::hasFamily(name))
        return name;
    if (QFontDatabase::hasFamily(QStringLiteral("Inter")))
        return QStringLiteral("Inter");
    return QFontDatabase::systemFont(QFontDatabase::GeneralFont).family();
}

/// Escolhe o estilo da família como o Core Text: o estilo pedido (ou o normal),
/// depois a variante com negrito/itálico se a família tiver; senão, sintéticos.
FontFace makeFont(const TextStyle &style, int pixelSize)
{
    const QString family = resolveFamily(style.fontName);
    struct Face {
        QString name;
        int weight;
        bool italic;
    };
    QList<Face> faces;
    for (const QString &s : QFontDatabase::styles(family))
        faces.append({s, QFontDatabase::weight(family, s), QFontDatabase::italic(family, s)});

    std::optional<Face> current;
    if (!style.fontFace.isEmpty())
        for (const Face &f : faces)
            if (f.name.compare(style.fontFace, Qt::CaseInsensitive) == 0)
                current = f;
    if (!current)
        for (const Face &f : faces)
            if (!f.italic && (!current || std::abs(f.weight - QFont::Normal) < std::abs(current->weight - QFont::Normal)))
                current = f;

    FontFace face;
    if (current && style.bold && current->weight < QFont::DemiBold) {
        std::optional<Face> bold;
        for (const Face &f : faces)
            if (f.italic == current->italic && f.weight >= QFont::Bold &&
                (!bold || std::abs(f.weight - QFont::Bold) < std::abs(bold->weight - QFont::Bold)))
                bold = f;
        if (bold)
            current = bold;
        else
            face.syntheticBold = true;
    }
    if (current && style.italic && !current->italic) {
        std::optional<Face> italic;
        for (const Face &f : faces)
            if (f.italic && (!italic || std::abs(f.weight - current->weight) < std::abs(italic->weight - current->weight)))
                italic = f;
        if (italic)
            current = italic;
        else
            face.syntheticItalic = true;
    }
    if (!current) {
        // Família sem estilos listados: o Qt sintetiza o que faltar.
        face.syntheticBold = style.bold;
        face.syntheticItalic = style.italic;
    }
    face.font = current ? QFontDatabase::font(family, current->name, 12) : QFont(family);
    face.font.setPixelSize(pixelSize);
    face.font.setHintingPreference(QFont::PreferNoHinting);
    face.font.setKerning(true);
    return face;
}

QString styleKey(const TextStyle &s)
{
    const auto n = [](double v) { return QString::number(v, 'g', 17); };
    const auto c = [&](const RGBA &v) { return n(v.r) + u',' + n(v.g) + u',' + n(v.b) + u',' + n(v.a); };
    return QStringList{s.fontName, s.fontFace, n(s.fontSize), QString::number(s.bold), QString::number(s.italic),
                       QString::number(s.underline), QString::number(int(s.textCase)), c(s.color), n(s.opacity),
                       c(s.strokeColor), n(s.strokeWidth), n(s.letterSpacing), n(s.lineSpacing),
                       QString::number(s.backgroundEnabled), c(s.backgroundColor), n(s.backgroundRadius),
                       n(s.backgroundPaddingX), n(s.backgroundPaddingY), QString::number(s.shadow), c(s.shadowColor),
                       n(s.shadowDistance), n(s.shadowAngle), n(s.shadowBlur), QString::number(int(s.alignment)),
                       n(s.maxWidth)}
        .join(u'|');
}

/// Desfoque da sombra nos valores sRGB pré-multiplicados (como o Core Graphics).
void blurRaw(QImage &image, double sigma)
{
    if (sigma < 0.3)
        return;
    LinearImage buffer(image.width(), image.height());
    for (int y = 0; y < image.height(); ++y) {
        const auto *src = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x)
            buffer.at(x, y) = {qRed(src[x]) / 255.0f, qGreen(src[x]) / 255.0f, qBlue(src[x]) / 255.0f,
                               qAlpha(src[x]) / 255.0f};
    }
    buffer.blur(sigma);
    for (int y = 0; y < image.height(); ++y) {
        auto *dst = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const Pixel &p = buffer.at(x, y);
            const auto q = [](float v) { return std::clamp(int(std::lround(v * 255)), 0, 255); };
            const int a = q(p.a);
            dst[x] = qRgba(std::min(q(p.r), a), std::min(q(p.g), a), std::min(q(p.b), a), a);
        }
    }
}

QColor qcolor(const RGBA &c)
{
    return QColor::fromRgbF(float(std::clamp(c.r, 0.0, 1.0)), float(std::clamp(c.g, 0.0, 1.0)),
                            float(std::clamp(c.b, 0.0, 1.0)), float(std::clamp(c.a, 0.0, 1.0)));
}

/// Limites (em unidades UTF-16) de cada letra visível (grafema).
QList<int> graphemeEnds(const QString &text)
{
    QList<int> ends;
    QTextBoundaryFinder finder(QTextBoundaryFinder::Grapheme, text);
    while (finder.toNextBoundary() > 0)
        ends.append(int(finder.position()));
    return ends;
}

} // namespace

TextRenderer &TextRenderer::shared()
{
    static TextRenderer renderer;
    return renderer;
}

QString TextRenderer::cased(const QString &text, TextCase textCase)
{
    const QLocale locale;
    switch (textCase) {
    case TextCase::None: return text;
    case TextCase::Upper: return locale.toUpper(text);
    case TextCase::Lower: return locale.toLower(text);
    case TextCase::Title: {
        // Primeira letra de cada palavra em maiúscula, o resto em minúscula.
        QString out = locale.toLower(text);
        bool start = true;
        for (qsizetype i = 0; i < out.size(); ++i) {
            const QChar ch = out[i];
            if (ch.isLetterOrNumber()) {
                if (start)
                    out.replace(i, 1, locale.toUpper(QString(ch)));
                start = false;
            } else if (ch.isSpace() || ch.isPunct()) {
                start = ch != u'\'' && ch != u'’';
            }
        }
        return out;
    }
    }
    return text;
}

QImage TextRenderer::image(const TextContent &content, QSize canvas, double reveal)
{
    const QString text = cased(content.text, content.style.textCase);
    const QList<int> ends = graphemeEnds(text);
    const int characters = int(ends.size());
    if (characters == 0 || canvas.height() <= 0)
        return {};
    const int visible = reveal >= 1 ? characters : int(std::ceil(characters * reveal));
    const QString key = QStringLiteral("%1\x1f%2\x1f%3x%4\x1f%5")
                            .arg(text, styleKey(content.style))
                            .arg(canvas.width())
                            .arg(canvas.height())
                            .arg(visible);
    {
        QMutexLocker locker(&m_lock);
        if (const QImage *cached = m_cache.object(key))
            return *cached;
    }
    const QImage image = render(text, content.style, canvas, visible);
    QMutexLocker locker(&m_lock);
    m_cache.insert(key, new QImage(image));
    return image;
}

QImage TextRenderer::render(const QString &text, const TextStyle &style, QSize canvas, int visibleCharacters)
{
    const double fontPx = std::max(4.0, style.fontSize * canvas.height());
    // O layout roda num tamanho inteiro e tudo é escalado para o tamanho exato.
    const int layoutPx = std::max(1, int(std::lround(fontPx)));
    const double s = fontPx / layoutPx;
    const FontFace face = makeFont(style, layoutPx);
    QFont font = face.font;
    const double kern = style.letterSpacing * fontPx;
    if (kern != 0)
        font.setLetterSpacing(QFont::AbsoluteSpacing, kern / s);

    const QFontMetricsF metrics(face.font);
    const double ascent = metrics.ascent() * s, descent = metrics.descent() * s, leading = metrics.leading() * s;
    // Altura fixa de linha quando há espaçamento extra; senão, a natural da fonte.
    const std::optional<double> fixedLine =
        style.lineSpacing != 0
            ? std::optional(std::max(fontPx * 0.3, ascent + descent + leading + style.lineSpacing * fontPx))
            : std::nullopt;

    // O QTextLayout só quebra a linha no separador de linha (U+2028), não no "\n";
    // a troca é de um caractere por um, então os índices continuam valendo.
    QString layoutText = text;
    layoutText.replace(u'\n', QChar::LineSeparator);
    QTextLayout layout(layoutText, font);
    QTextOption option;
    option.setWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);
    layout.setTextOption(option);
    const double maxWidth = std::max(fontPx, style.maxWidth * canvas.width());
    struct LineInfo {
        int start, length;
        double width, top, height, baseline;
    };
    QList<LineInfo> lines;
    double y = 0, widest = 0;
    layout.beginLayout();
    for (;;) {
        QTextLine line = layout.createLine();
        if (!line.isValid())
            break;
        line.setLeadingIncluded(true);
        line.setLineWidth(maxWidth / s);
        const double natural = line.height() * s;
        const double height = fixedLine.value_or(natural);
        // A linha de base fica a (descida + entrelinha) do fim da linha, como no Core Text.
        const double lineDescent = line.descent() * s + line.leading() * s;
        lines.append({line.textStart(), line.textLength(), line.naturalTextWidth() * s, y, height,
                      y + height - lineDescent});
        widest = std::max(widest, line.naturalTextWidth() * s);
        y += height;
    }
    layout.endLayout();
    const QSizeF textSize(std::ceil(widest) + 1, std::ceil(y) + 1);

    // Contornos das letras visíveis e retângulos do sublinhado, em pixels da caixa de texto.
    const QList<int> ends = graphemeEnds(text);
    const int cut = visibleCharacters <= 0 ? 0 : ends[std::min(visibleCharacters, int(ends.size())) - 1];
    QPainterPath glyphs, underlines;
    glyphs.setFillRule(Qt::WindingFill);
    struct ColorRun {
        QRawFont font;
        QList<quint32> indexes;
        QList<QPointF> positions;
    };
    QList<ColorRun> colorRuns;
    // O espaço entre letras também vai depois da última da linha: desconta a sobra.
    const double shift = style.alignment == TextAlignment::Left ? 0 : style.alignment == TextAlignment::Center ? kern / 2 : kern;
    for (const LineInfo &info : lines) {
        const double offset = style.alignment == TextAlignment::Left     ? 0
                              : style.alignment == TextAlignment::Center ? (textSize.width() - info.width) / 2
                                                                         : textSize.width() - info.width;
        const QTextLine line = layout.lineForTextPosition(info.start);
        double minX = INFINITY, maxX = -INFINITY;
        const auto runs = layout.glyphRuns(info.start, info.length,
                                           QTextLayout::RetrieveGlyphIndexes | QTextLayout::RetrieveGlyphPositions |
                                               QTextLayout::RetrieveStringIndexes);
        for (const QGlyphRun &run : runs) {
            const QRawFont raw = run.rawFont();
            const auto indexes = run.glyphIndexes();
            const auto positions = run.positions();
            const auto strings = run.stringIndexes();
            const auto advances = raw.advancesForGlyphIndexes(indexes);
            ColorRun colored{raw, {}, {}};
            for (qsizetype i = 0; i < indexes.size(); ++i) {
                const qsizetype index = i < strings.size() ? strings[i] : info.start;
                if (index >= cut)
                    continue;
                // Posição no layout → pixels: x com o alinhamento, y na linha de base.
                const QPointF p((positions[i].x() - line.x()) * s + offset + shift,
                                info.baseline + (positions[i].y() - line.y() - line.ascent()) * s);
                const QChar ch = index < text.size() ? text[index] : QChar();
                if (!ch.isSpace()) {
                    minX = std::min(minX, p.x());
                    maxX = std::max(maxX, p.x() + advances[i].x() * s);
                }
                const QPainterPath outline = raw.pathForGlyph(indexes[i]);
                if (outline.isEmpty()) {
                    if (!ch.isSpace()) {
                        colored.indexes.append(indexes[i]);
                        colored.positions.append(p);
                    }
                    continue;
                }
                QTransform t;
                t.translate(p.x(), p.y());
                t.scale(s, s);
                if (face.syntheticItalic)
                    t.shear(-syntheticSlant, 0);
                glyphs.addPath(t.map(outline));
            }
            if (!colored.indexes.isEmpty())
                colorRuns.append(colored);
        }
        if (style.underline && maxX > minX) {
            // Posição e espessura em em, como `underline_offset`/`underline_width` do CapCut.
            const double thickness = fontPx * 0.05;
            underlines.addRect(QRectF(minX, info.baseline + fontPx * 0.12, maxX - minX, thickness));
        }
    }

    // Margens: o bastante para contorno, fundo, sombra e partes das letras que
    // passam da caixa tipográfica (itálico, linhas apertadas).
    const double strokeOut = std::max(0.0, style.strokeWidth) / 100 * fontPx / 2 +
                             (face.syntheticBold ? syntheticBold * fontPx / 2 : 0);
    const double bgX = style.backgroundEnabled ? std::max(0.0, style.backgroundPaddingX) * fontPx : 0;
    const double bgY = style.backgroundEnabled ? std::max(0.0, style.backgroundPaddingY) * fontPx : 0;
    const double distance = std::max(0.0, style.shadowDistance) * fontPx;
    const double angle = style.shadowAngle * M_PI / 180;
    // Ângulo com y para cima (90 = cima); na imagem, y cresce para baixo.
    const QPointF shadowOffset(std::cos(angle) * distance, -std::sin(angle) * distance);
    const double shadowBlur = style.shadow ? std::max(0.0, style.shadowBlur) * fontPx : 0;
    const double shadowX = style.shadow ? std::abs(shadowOffset.x()) + shadowBlur * 1.5 : 0;
    const double shadowY = style.shadow ? std::abs(shadowOffset.y()) + shadowBlur * 1.5 : 0;
    const double slant = (style.italic || face.syntheticItalic) ? fontPx * 0.25 : 0;
    const double tight = std::max(0.0, -style.lineSpacing) * fontPx;
    const double base = std::ceil(fontPx * 0.35);
    const double padX = std::max(base, std::ceil(fontPx * 0.12 + std::max(strokeOut, bgX) + shadowX + slant));
    const double padY = std::max(base, std::ceil(fontPx * 0.12 + std::max(strokeOut, bgY) + shadowY + tight));
    const int width = int(textSize.width() + padX * 2);
    const int height = int(textSize.height() + padY * 2);

    // Letras, contorno e sublinhado numa camada só: a sombra sai uma vez, do conjunto.
    QImage ink(width, height, QImage::Format_ARGB32_Premultiplied);
    ink.fill(Qt::transparent);
    {
        QPainter p(&ink);
        p.setRenderHint(QPainter::Antialiasing);
        p.translate(padX, padY);
        if (strokeOut > 0) {
            QPen pen(qcolor(style.strokeColor), strokeOut * 2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            p.strokePath(glyphs, pen);
            p.strokePath(underlines, pen);
        }
        const QColor color = qcolor(style.color);
        if (face.syntheticBold)
            p.strokePath(glyphs, QPen(color, syntheticBold * fontPx, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.fillPath(glyphs, color);
        p.fillPath(underlines, color);
        // Glifos coloridos (emoji) não têm contorno vetorial: são desenhados como estão.
        for (const ColorRun &run : colorRuns) {
            QRawFont raw = run.font;
            raw.setPixelSize(raw.pixelSize() * s);
            QGlyphRun glyphRun;
            glyphRun.setRawFont(raw);
            glyphRun.setGlyphIndexes(run.indexes);
            glyphRun.setPositions(run.positions);
            p.drawGlyphRun(QPointF(0, 0), glyphRun);
        }
    }

    QImage group(width, height, QImage::Format_ARGB32_Premultiplied);
    group.fill(Qt::transparent);
    {
        QPainter p(&group);
        p.setRenderHint(QPainter::Antialiasing);
        if (style.backgroundEnabled) {
            const QRectF box = QRectF(QPointF(padX, padY), textSize).adjusted(-bgX, -bgY, bgX, bgY);
            const double radius = std::min(std::max(0.0, style.backgroundRadius) * fontPx,
                                           std::min(box.width(), box.height()) / 2);
            QPainterPath path;
            path.addRoundedRect(box, radius, radius);
            p.fillPath(path, qcolor(style.backgroundColor));
        }
        if (style.shadow) {
            QImage shadow(width, height, QImage::Format_ARGB32_Premultiplied);
            shadow.fill(Qt::transparent);
            {
                QPainter sp(&shadow);
                sp.drawImage(shadowOffset, ink);
                sp.setCompositionMode(QPainter::CompositionMode_SourceIn);
                sp.fillRect(shadow.rect(), qcolor(style.shadowColor));
            }
            // O raio do Core Graphics corresponde a cerca de 2 desvios-padrão.
            blurRaw(shadow, shadowBlur / 2);
            p.drawImage(0, 0, shadow);
        }
        p.drawImage(0, 0, ink);
    }

    const double opacity = std::clamp(style.opacity, 0.0, 1.0);
    if (opacity >= 1)
        return group;
    QImage faded(width, height, QImage::Format_ARGB32_Premultiplied);
    faded.fill(Qt::transparent);
    QPainter p(&faded);
    p.setOpacity(opacity);
    p.drawImage(0, 0, group);
    return faded;
}

} // namespace of
