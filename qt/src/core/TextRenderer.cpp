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
                       n(s.maxWidth), QString::number(s.balanceLines), QString::number(s.fitLines)}
        .join(u'|');
}

/// Chave do conteúdo que muda o desenho: texto, estilo e palavra-chave (os tempos não mudam a imagem estática).
QString contentKey(const QString &text, const TextContent &content)
{
    QString key = text + u'\x1f' + styleKey(content.style);
    if (const auto &e = content.emphasis) {
        QStringList words;
        for (const int w : e->words)
            words.append(QString::number(w));
        key += u'\x1f' + words.join(u',') + u'|' + e->fontName + u'|' + e->fontFace + u'|' +
               QString::number(e->scale, 'g', 17);
        if (e->color)
            key += QStringLiteral("|%1,%2,%3,%4").arg(e->color->r).arg(e->color->g).arg(e->color->b).arg(e->color->a);
    }
    return key;
}

/// Trechos (UTF-16, [início, fim)) das palavras do texto: a divisão de `TextContent::wordsOf`.
QList<std::pair<int, int>> wordRanges(const QString &text)
{
    QList<std::pair<int, int>> ranges;
    int start = -1;
    for (int i = 0; i <= text.size(); ++i) {
        const bool blank = i == text.size() || text[i].isSpace();
        if (blank && start >= 0) {
            ranges.append({start, i});
            start = -1;
        } else if (!blank && start < 0) {
            start = i;
        }
    }
    return ranges;
}

/// Tamanho mínimo da fonte no QTextLayout. O QFont só aceita pixels inteiros: montar o texto grande e escalar
/// o resultado deixa o erro de arredondamento das fontes ampliadas ou reduzidas (palavra-chave, `fitLines`) em
/// ~0,1%. Sem hinting, o layout é linear no tamanho.
constexpr int minLayoutPx = 512;

int layoutPixels(double fontPx) { return std::max(minLayoutPx, int(std::lround(fontPx))); }

/// Faixa de escala de cada linha no `fitLines`.
constexpr double fitMin = 0.6, fitMax = 2.5;

/// Texto montado: fontes por trecho, linhas e caixa, em pixels. O QTextLayout trabalha em pixels inteiros
/// de fonte (`layoutPx`, no mínimo `minLayoutPx`) e tudo é escalado por `s = fontPx/layoutPx`.
struct Layout {
    FontFace face;
    double fontPx = 0;
    /// Maior fonte do texto (palavra-chave e linhas ampliadas pelo `fitLines`): as margens contam com ela.
    double peakFontPx = 0;
    double s = 1;
    /// Espaço extra entre letras da fonte base, em pixels.
    double kern = 0;
    std::shared_ptr<QTextLayout> layout;
    struct Line {
        int start, length;
        double width, top, height, baseline;
    };
    QList<Line> lines;
    QSizeF textSize;
    /// Trechos das palavras-chave e a cor delas (vazia = a do texto).
    QList<std::pair<int, int>> accent;
    std::optional<RGBA> accentColor;
};

/// Número de linhas da quebra automática na largura `width` (pixels de layout).
int countLines(QTextLayout &layout, double width)
{
    int count = 0;
    layout.beginLayout();
    for (;;) {
        QTextLine line = layout.createLine();
        if (!line.isValid())
            break;
        line.setLineWidth(width);
        ++count;
    }
    layout.endLayout();
    return count;
}

/// Monta o texto: fonte, palavras-chave, linhas ajustadas à largura (`fitLines`) e quebra (comum, equilibrada
/// ou só nos `\n`). Mesmas regras do `TextRenderer.layout` do Swift.
Layout buildLayout(const QString &text, const TextStyle &style, QSize canvas, const std::optional<WordEmphasis> &emphasis)
{
    Layout l;
    l.fontPx = std::max(4.0, style.fontSize * canvas.height());
    const int layoutPx = layoutPixels(l.fontPx);
    l.s = l.fontPx / layoutPx;
    l.face = makeFont(style, layoutPx);
    l.kern = style.letterSpacing * l.fontPx;
    l.peakFontPx = l.fontPx;
    const double s = l.s;

    // Fonte de cada posição: 0 = a do texto, 1 = a da palavra-chave; e o tamanho em pixels.
    const int n = int(text.size());
    QList<char> kind(n, 0);
    QList<double> size(n, l.fontPx);
    TextStyle accentStyle = style;
    double accentPx = l.fontPx;
    if (emphasis && !emphasis->words.isEmpty()) {
        accentStyle.fontName = emphasis->fontName;
        accentStyle.fontFace = emphasis->fontFace;
        accentStyle.bold = false;
        accentStyle.italic = false;
        accentPx = l.fontPx * std::clamp(emphasis->scale, 0.2, 5.0);
        const auto words = wordRanges(text);
        QList<int> picked = emphasis->words;
        std::sort(picked.begin(), picked.end());
        picked.erase(std::unique(picked.begin(), picked.end()), picked.end());
        for (const int w : picked) {
            if (w < 0 || w >= words.size())
                continue;
            for (int i = words[w].first; i < words[w].second; ++i) {
                kind[i] = 1;
                size[i] = accentPx;
            }
            l.accent.append(words[w]);
        }
        if (!l.accent.isEmpty()) {
            l.peakFontPx = std::max(l.peakFontPx, accentPx);
            l.accentColor = emphasis->color;
        }
    }

    // Fontes já criadas por (tipo, tamanho de layout).
    QHash<QString, QFont> fonts;
    const auto fontFor = [&](int k, double px) {
        const int layoutSize = std::max(1, int(std::lround(px / s)));
        const QString key = QStringLiteral("%1|%2").arg(k).arg(layoutSize);
        if (const auto it = fonts.constFind(key); it != fonts.constEnd())
            return *it;
        QFont font = k == 0 ? l.face.font : makeFont(accentStyle, layoutSize).font;
        font.setPixelSize(layoutSize);
        if (style.letterSpacing != 0)
            font.setLetterSpacing(QFont::AbsoluteSpacing, style.letterSpacing * px / s);
        fonts.insert(key, font);
        return font;
    };
    const auto formats = [&](int from, int to) {
        QList<QTextLayout::FormatRange> ranges;
        for (int i = from; i < to;) {
            int j = i + 1;
            while (j < to && kind[j] == kind[i] && size[j] == size[i])
                ++j;
            QTextLayout::FormatRange r;
            r.start = i - from;
            r.length = j - i;
            r.format.setFont(fontFor(kind[i], size[i]));
            ranges.append(r);
            i = j;
        }
        return ranges;
    };
    const auto naturalHeight = [&](double px) {
        const QFontMetricsF m(fontFor(0, px));
        return (m.ascent() + m.descent() + m.leading()) * s;
    };
    // Altura fixa de linha quando há espaçamento extra; senão, a natural da fonte.
    const auto fixedHeight = [&](double px) -> std::optional<double> {
        if (style.lineSpacing == 0)
            return std::nullopt;
        return std::max(px * 0.3, naturalHeight(px) + style.lineSpacing * px);
    };

    // Parágrafos (separados por `\n`) e a altura fixa de cada um.
    QList<std::pair<int, int>> paragraphs;
    for (int i = 0, start = 0; i <= n; ++i)
        if (i == n || text[i] == u'\n') {
            paragraphs.append({start, i});
            start = i + 1;
        }
    QList<std::optional<double>> paragraphHeight(paragraphs.size(), fixedHeight(l.fontPx));

    const double boxWidth = std::max(l.fontPx, style.maxWidth * canvas.width());
    if (style.fitLines) {
        // Cada linha ocupa a largura da caixa, dentro da faixa de escala, com a altura de linha da própria fonte.
        for (int p = 0; p < paragraphs.size(); ++p) {
            const auto [from, to] = paragraphs[p];
            if (to <= from)
                continue;
            QTextLayout measure(text.mid(from, to - from));
            measure.setFormats(formats(from, to));
            QTextOption option;
            option.setWrapMode(QTextOption::NoWrap);
            measure.setTextOption(option);
            measure.beginLayout();
            QTextLine line = measure.createLine();
            line.setLineWidth(1e6);
            measure.endLayout();
            const double natural = line.naturalTextWidth() * s - l.kern;
            if (natural <= 0)
                continue;
            const double k = std::clamp(boxWidth / natural, fitMin, fitMax);
            for (int i = from; i < to; ++i)
                size[i] *= k;
            paragraphHeight[p] = fixedHeight(l.fontPx * k);
            l.peakFontPx = std::max(l.peakFontPx, l.fontPx * k);
        }
    }

    // O QTextLayout só quebra a linha no separador de linha (U+2028), não no "\n";
    // a troca é de um caractere por um, então os índices continuam valendo.
    QString layoutText = text;
    layoutText.replace(u'\n', QChar::LineSeparator);
    l.layout = std::make_shared<QTextLayout>(layoutText, l.face.font);
    QTextOption option;
    option.setWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);
    l.layout->setTextOption(option);
    if (style.letterSpacing != 0 || !l.accent.isEmpty() || style.fitLines)
        l.layout->setFormats(formats(0, n));
    else {
        QFont font = l.face.font;
        if (l.kern != 0)
            font.setLetterSpacing(QFont::AbsoluteSpacing, l.kern / s);
        l.layout->setFont(font);
    }

    double wrap = boxWidth;
    if (style.fitLines) {
        // As linhas já têm a largura da caixa: só os `\n` quebram (o que passar dos limites de escala, sai).
        wrap = 1e6;
    } else if (style.balanceLines) {
        // Menor largura com o mesmo número de linhas (`text-wrap: balance`), até meio pixel.
        const int lines = countLines(*l.layout, wrap / s);
        if (lines > 1) {
            double lo = 0, hi = wrap;
            while (hi - lo > 0.5) {
                const double mid = (lo + hi) / 2;
                (countLines(*l.layout, mid / s) <= lines ? hi : lo) = mid;
            }
            wrap = hi;
        }
    }

    double y = 0, widest = 0;
    l.layout->beginLayout();
    for (;;) {
        QTextLine line = l.layout->createLine();
        if (!line.isValid())
            break;
        line.setLeadingIncluded(true);
        line.setLineWidth(wrap / s);
        const int start = line.textStart();
        int paragraph = 0;
        while (paragraph + 1 < paragraphs.size() && paragraphs[paragraph].second < start)
            ++paragraph;
        const double natural = line.height() * s;
        const double height = paragraphHeight[paragraph].value_or(natural);
        // A linha de base fica a (descida + entrelinha) do fim da linha, como no Core Text.
        const double lineDescent = line.descent() * s + line.leading() * s;
        l.lines.append({start, line.textLength(), line.naturalTextWidth() * s, y, height, y + height - lineDescent});
        widest = std::max(widest, line.naturalTextWidth() * s);
        y += height;
    }
    l.layout->endLayout();
    l.textSize = QSizeF(std::ceil(widest) + 1, std::ceil(y) + 1);
    return l;
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
    const QString key = QStringLiteral("%1\x1f%2x%3\x1f%4")
                            .arg(contentKey(text, content))
                            .arg(canvas.width())
                            .arg(canvas.height())
                            .arg(visible);
    {
        QMutexLocker locker(&m_lock);
        if (const QImage *cached = m_cache.object(key))
            return *cached;
    }
    const QImage image = render(text, content.style, content.emphasis, canvas, visible);
    QMutexLocker locker(&m_lock);
    m_cache.insert(key, new QImage(image));
    return image;
}

QImage TextRenderer::render(const QString &text, const TextStyle &style, const std::optional<WordEmphasis> &emphasis,
                            QSize canvas, int visibleCharacters)
{
    const Layout l = buildLayout(text, style, canvas, emphasis);
    const double fontPx = l.fontPx, s = l.s, kern = l.kern;
    const FontFace &face = l.face;
    const QTextLayout &layout = *l.layout;
    const QSizeF textSize = l.textSize;
    const auto isAccent = [&](qsizetype index) {
        return std::any_of(l.accent.cbegin(), l.accent.cend(),
                           [&](const auto &r) { return index >= r.first && index < r.second; });
    };

    // Contornos das letras visíveis e retângulos do sublinhado, em pixels da caixa de texto.
    const QList<int> ends = graphemeEnds(text);
    const int cut = visibleCharacters <= 0 ? 0 : ends[std::min(visibleCharacters, int(ends.size())) - 1];
    QPainterPath glyphs, accentGlyphs, underlines;
    glyphs.setFillRule(Qt::WindingFill);
    accentGlyphs.setFillRule(Qt::WindingFill);
    struct ColorRun {
        QRawFont font;
        QList<quint32> indexes;
        QList<QPointF> positions;
    };
    QList<ColorRun> colorRuns;
    // O espaço entre letras também vai depois da última da linha: desconta a sobra.
    const double shift = style.alignment == TextAlignment::Left ? 0 : style.alignment == TextAlignment::Center ? kern / 2 : kern;
    for (const Layout::Line &info : l.lines) {
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
                // A palavra-chave tem a fonte própria (sem negrito nem itálico sintéticos) e a cor dela.
                const bool accent = isAccent(index);
                QTransform t;
                t.translate(p.x(), p.y());
                t.scale(s, s);
                if (face.syntheticItalic && !accent)
                    t.shear(-syntheticSlant, 0);
                (accent ? accentGlyphs : glyphs).addPath(t.map(outline));
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
    // A palavra-chave (às vezes itálica) e as linhas ampliadas pedem margens pela maior fonte.
    const double peak = l.peakFontPx;
    const double slant = (style.italic || face.syntheticItalic || !l.accent.isEmpty()) ? peak * 0.25 : 0;
    const double tight = std::max(0.0, -style.lineSpacing) * peak;
    const double base = std::ceil(peak * 0.35);
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
            p.strokePath(accentGlyphs, pen);
            p.strokePath(underlines, pen);
        }
        const QColor color = qcolor(style.color);
        if (face.syntheticBold)
            p.strokePath(glyphs, QPen(color, syntheticBold * fontPx, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.fillPath(glyphs, color);
        p.fillPath(underlines, color);
        if (!accentGlyphs.isEmpty())
            p.fillPath(accentGlyphs, qcolor(l.accentColor.value_or(style.color)));
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

std::optional<QSizeF> TextRenderer::boxSize(const TextContent &content, QSize canvas)
{
    const QString text = cased(content.text, content.style.textCase);
    if (text.isEmpty() || canvas.height() <= 0)
        return std::nullopt;
    const QString key = QStringLiteral("box\x1f%1\x1f%2x%3").arg(contentKey(text, content)).arg(canvas.width()).arg(canvas.height());
    {
        QMutexLocker locker(&m_lock);
        if (const QSizeF *cached = m_sizes.object(key))
            return *cached;
    }
    const TextStyle &style = content.style;
    const Layout l = buildLayout(text, style, canvas, content.emphasis);
    const double bgX = style.backgroundEnabled ? std::max(0.0, style.backgroundPaddingX) * l.fontPx : 0;
    const double bgY = style.backgroundEnabled ? std::max(0.0, style.backgroundPaddingY) * l.fontPx : 0;
    const QSizeF size(l.textSize.width() + bgX * 2, l.textSize.height() + bgY * 2);
    QMutexLocker locker(&m_lock);
    m_sizes.insert(key, new QSizeF(size));
    return size;
}

double TextRenderer::lineWidth(const QString &text, const TextStyle &style, double fontPx)
{
    const int layoutPx = layoutPixels(fontPx);
    const double s = fontPx / layoutPx;
    QFont font = makeFont(style, layoutPx).font;
    if (style.letterSpacing != 0)
        font.setLetterSpacing(QFont::AbsoluteSpacing, style.letterSpacing * fontPx / s);
    QTextLayout layout(cased(text, style.textCase), font);
    QTextOption option;
    option.setWrapMode(QTextOption::NoWrap);
    layout.setTextOption(option);
    layout.beginLayout();
    QTextLine line = layout.createLine();
    if (!line.isValid()) {
        layout.endLayout();
        return 0;
    }
    line.setLineWidth(1e9);
    layout.endLayout();
    // Como o `CTLineGetTypographicBounds`: com os espaços e o espaçamento do fim.
    return line.horizontalAdvance() * s;
}

QStringList TextRenderer::lineTexts(const TextContent &content, QSize canvas)
{
    const QString text = cased(content.text, content.style.textCase);
    if (text.isEmpty() || canvas.height() <= 0)
        return {};
    const Layout l = buildLayout(text, content.style, canvas, content.emphasis);
    QStringList out;
    for (const Layout::Line &line : l.lines)
        out.append(text.mid(line.start, line.length).trimmed());
    return out;
}

} // namespace of
