// Porte da suíte "Texto" (TextTests.swift).
#include "FontCatalog.h"
#include "TestSupport.h"
#include "TextRenderer.h"

#include <QFontDatabase>

using namespace of;

namespace {

const QSize canvas(1280, 720);

TextStyle style(const std::function<void(TextStyle &)> &change = {})
{
    TextStyle s;
    s.shadow = false;
    s.fontSize = 0.1;
    if (change)
        change(s);
    return s;
}

QImage image(const QString &text, const TextStyle &s, double reveal = 1)
{
    // Renderizador próprio: o cache do compartilhado não interfere entre testes.
    static TextRenderer renderer;
    return renderer.image({text, s}, canvas, reveal);
}

/// Cor sem pré-multiplicação no pixel (x, y), linha 0 = topo.
QColor at(const QImage &img, int x, int y) { return img.pixelColor(x, y); }

bool isRed(const QColor &c) { return c.red() > 200 && c.green() < 40 && c.alpha() > 200; }

} // namespace

class TextTests : public QObject
{
    Q_OBJECT

private slots:
    // Espaçamento entre letras alarga a caixa
    void letterSpacingWidens()
    {
        const QImage normal = image(QStringLiteral("ESPAÇO"), style());
        const QImage wide = image(QStringLiteral("ESPAÇO"), style([](TextStyle &s) { s.letterSpacing = 0.5; }));
        const QImage tight = image(QStringLiteral("ESPAÇO"), style([](TextStyle &s) { s.letterSpacing = -0.1; }));
        // Seis letras com 0,5 em a mais cada: pelo menos ~2,5 em (180 px a 72 px/em) mais largo.
        QVERIFY2(wide.width() > normal.width() + 150, qPrintable(QStringLiteral("%1 × %2").arg(wide.width()).arg(normal.width())));
        QVERIFY(tight.width() < normal.width());
        QVERIFY(std::abs(wide.height() - normal.height()) < 2);
    }

    // Espaçamento entre linhas muda a altura
    void lineSpacingChangesHeight()
    {
        const QString text = QStringLiteral("um\ndois\ntrês");
        const QImage normal = image(text, style());
        const QImage loose = image(text, style([](TextStyle &s) { s.lineSpacing = 1; }));
        const QImage tight = image(text, style([](TextStyle &s) { s.lineSpacing = -0.3; }));
        // Duas entrelinhas de 1 em (72 px) a mais.
        QVERIFY2(loose.height() > normal.height() + 130,
                 qPrintable(QStringLiteral("%1 × %2").arg(loose.height()).arg(normal.height())));
        QVERIFY(tight.height() < normal.height());
        QVERIFY(std::abs(loose.width() - normal.width()) < 2);
    }

    // O cache distingue estilos que só mudam nos campos novos
    void cacheKeyUsesNewFields()
    {
        TextRenderer &renderer = TextRenderer::shared();
        const QImage a = renderer.image({QStringLiteral("Cache"), style()}, canvas);
        const QImage b =
            renderer.image({QStringLiteral("Cache"), style([](TextStyle &s) { s.letterSpacing = 0.4; })}, canvas);
        QVERIFY(b.width() > a.width());
    }

    // Contorno grosso fica do lado de fora da letra
    void strokeIsOutside()
    {
        // Um "I" com contorno de 20% do tamanho: o meio da haste continua da cor do texto.
        const QImage img = image(QStringLiteral("I"), style([](TextStyle &s) {
                                     s.strokeWidth = 20;
                                     s.strokeColor = {1, 0, 0, 1};
                                     s.color = RGBA::white();
                                     s.bold = true;
                                 }));
        const int w = img.width(), h = img.height();
        const QColor middle = at(img, w / 2, h / 2);
        QVERIFY(middle.red() > 240 && middle.green() > 240 && middle.blue() > 240);
        // E o contorno vermelho aparece ao lado.
        bool red = false;
        for (int x = 0; x < w; ++x)
            red = red || isRed(at(img, x, h / 2));
        QVERIFY(red);
    }

    // Sombra segue o ângulo
    void shadowFollowsAngle()
    {
        const QImage img = image(QStringLiteral("I"), style([](TextStyle &s) {
                                     s.color = RGBA::white();
                                     s.shadow = true;
                                     s.shadowColor = {1, 0, 0, 1};
                                     s.shadowDistance = 0.4;
                                     s.shadowBlur = 0;
                                     s.shadowAngle = 0;
                                 }));
        const int w = img.width(), h = img.height();
        const auto reds = [&](int from, int to) {
            int n = 0;
            for (int x = from; x < to; ++x)
                n += isRed(at(img, x, h / 2));
            return n;
        };
        QVERIFY(reds(w / 2, w) > 5);
        QCOMPARE(reds(0, w / 2 - 10), 0);
    }

    // Opacidade vale para o texto inteiro
    void opacity()
    {
        const QImage img = image(QStringLiteral("OPACO"), style([](TextStyle &s) {
                                     s.opacity = 0.5;
                                     s.backgroundEnabled = true;
                                     s.backgroundColor = RGBA::black();
                                 }));
        int maxAlpha = 0;
        for (int y = 0; y < img.height(); ++y)
            for (int x = 0; x < img.width(); ++x)
                maxAlpha = std::max(maxAlpha, qAlpha(img.pixel(x, y)));
        QVERIFY2(maxAlpha > 100 && maxAlpha < 140, qPrintable(QString::number(maxAlpha)));
    }

    // Sublinhado desenha embaixo da linha
    void underline()
    {
        const auto inkBelowBaseline = [](const TextStyle &s) {
            // "ama" não tem descendentes: abaixo da linha de base só pode haver o sublinhado.
            const QImage img = image(QStringLiteral("ama"), s);
            int count = 0;
            for (int y = img.height() * 62 / 100; y < img.height(); ++y)
                for (int x = 0; x < img.width(); ++x)
                    count += qAlpha(img.pixel(x, y)) > 128;
            return count;
        };
        QVERIFY(inkBelowBaseline(style([](TextStyle &s) { s.underline = true; })) > inkBelowBaseline(style()) + 100);
    }

    // Caixa das letras e máquina de escrever
    void textCase()
    {
        QCOMPARE(TextRenderer::cased(QStringLiteral("olá Mundo"), TextCase::Upper), QStringLiteral("OLÁ MUNDO"));
        QCOMPARE(TextRenderer::cased(QStringLiteral("Olá MUNDO"), TextCase::Lower), QStringLiteral("olá mundo"));
        QCOMPARE(TextRenderer::cased(QStringLiteral("olá mundo"), TextCase::Title), QStringLiteral("Olá Mundo"));
        // A revelação parcial não muda o tamanho da caixa (o layout não pula).
        const TextStyle s = style([](TextStyle &st) { st.textCase = TextCase::Upper; });
        const QImage partial = image(QStringLiteral("digitando"), s, 0.3);
        const QImage full = image(QStringLiteral("digitando"), s);
        QCOMPARE(partial.size(), full.size());
        // E desenha menos tinta.
        const auto ink = [](const QImage &img) {
            qint64 sum = 0;
            for (int y = 0; y < img.height(); ++y)
                for (int x = 0; x < img.width(); ++x)
                    sum += qAlpha(img.pixel(x, y));
            return sum;
        };
        QVERIFY(ink(partial) < ink(full) / 2);
        QVERIFY(image(QStringLiteral("x"), s, 0).width() > 0); // nada visível, mas a caixa existe
    }

    // Um estilo escolhido da família muda o desenho em relação ao padrão
    void fontFaces()
    {
        // Uma família com estilo normal e negrito de verdade.
        for (const QString &family : FontCatalog::families()) {
            const QStringList faces = FontCatalog::faces(family);
            QString regular, bold;
            for (const QString &f : faces) {
                const int weight = QFontDatabase::weight(family, f);
                if (!QFontDatabase::italic(family, f) && weight == QFont::Normal)
                    regular = f;
                if (!QFontDatabase::italic(family, f) && weight >= QFont::Bold && bold.isEmpty())
                    bold = f;
            }
            if (regular.isEmpty() || bold.isEmpty())
                continue;
            const QImage normal = image(QStringLiteral("Peso"), style([&](TextStyle &s) {
                                            s.fontName = family;
                                            s.bold = false;
                                        }));
            const QImage heavy = image(QStringLiteral("Peso"), style([&](TextStyle &s) {
                                           s.fontName = family;
                                           s.bold = false;
                                           s.fontFace = bold;
                                       }));
            QVERIFY2(heavy != normal, qPrintable(family + u'/' + bold));
            return;
        }
        QSKIP("nenhuma família com normal e negrito instalada");
    }

    // Itálico muda o desenho (variante da família ou inclinação sintética)
    void italicChangesDrawing()
    {
        const QImage plain = image(QStringLiteral("Texto"), style([](TextStyle &s) { s.bold = false; }));
        const QImage italic = image(QStringLiteral("Texto"), style([](TextStyle &s) {
                                        s.bold = false;
                                        s.italic = true;
                                    }));
        QVERIFY(italic != plain);
    }

    // Emoji aparece colorido (a maçã é vermelha; a claquete 🎬 seria cinza)
    void emoji()
    {
        const QImage img = image(QStringLiteral("🍎"), style([](TextStyle &s) { s.color = RGBA::white(); }));
        int colored = 0;
        for (int y = 0; y < img.height(); ++y)
            for (int x = 0; x < img.width(); ++x) {
                const QColor c = img.pixelColor(x, y);
                colored += c.alpha() > 200 && (std::abs(c.red() - c.green()) > 30 || std::abs(c.green() - c.blue()) > 30);
            }
        if (colored == 0)
            QSKIP("sem fonte de emoji colorida instalada");
        QVERIFY(colored > 20);
    }
};

QTEST_MAIN(TextTests)
#include "TextTests.moc"
