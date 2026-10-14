// Porte da suíte "Renderização" (RenderTests.swift) e comparação dos efeitos
// com as cores medidas no Swift/Core Image (fixtures/efeitos.json).
#include "ImageEffects.h"
#include "LinearImage.h"
#include "MediaProbe.h"
#include "Motion.h"
#include "Renderer.h"
#include "TestMedia.h"
#include "TimelineEditor.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

using namespace of;
using namespace of::test;
namespace TE = of::TimelineEditor;

namespace {

const QSize size(320, 180);

QImage render(const Project &p, Micros t, QSize s = size) { return Renderer().render(p, t, s); }

/// Cor no ponto (x, y) normalizado com y para cima, como o Bitmap dos testes Swift.
QColor color(const QImage &image, double x, double y) { return pixel(image, x, 1 - y); }

Material photoMaterial(QColor c, int width = 400, int height = 300)
{
    const QString path = makeImage(QStringLiteral("png"), width, height, c, c);
    return *MediaProbe::probe(path);
}

struct Golden {
    QList<QColor> colors;
    QHash<QString, QList<QColor>> cases;
};

const Golden &golden()
{
    static const Golden g = [] {
        QFile file(QStringLiteral(OPENFRAME_FIXTURES "/efeitos.json"));
        if (!file.open(QIODevice::ReadOnly))
            qFatal("efeitos.json ausente");
        const QJsonObject o = QJsonDocument::fromJson(file.readAll()).object();
        const auto toColors = [](const QJsonArray &list) {
            QList<QColor> out;
            for (const auto &v : list) {
                const QJsonArray c = v.toArray();
                out.append(QColor(c[0].toInt(), c[1].toInt(), c[2].toInt()));
            }
            return out;
        };
        Golden g;
        g.colors = toColors(o["colors"].toArray());
        for (const auto &c : o["cases"].toArray())
            g.cases.insert(c.toObject()["name"].toString(), toColors(c.toObject()["output"].toArray()));
        return g;
    }();
    return g;
}

/// Manchas 16×16 de cada cor de referência, processadas por `op`, lidas no centro.
QList<QColor> measure(const std::function<void(LinearImage &)> &op)
{
    QList<QColor> out;
    for (const QColor &c : golden().colors) {
        QImage patch(16, 16, QImage::Format_ARGB32_Premultiplied);
        patch.fill(c);
        LinearImage img = LinearImage::fromImage(patch);
        op(img);
        out.append(img.toImage().pixelColor(8, 8));
    }
    return out;
}

struct Error {
    int max = 0;
    double mean = 0;
    QString worst;
};

Error compare(const QString &name, const QList<QColor> &got)
{
    const QList<QColor> &want = golden().cases.value(name);
    if (want.size() != got.size())
        qFatal("caso %s sem referência", qPrintable(name));
    Error e;
    for (qsizetype i = 0; i < want.size(); ++i) {
        const int dr = std::abs(want[i].red() - got[i].red()), dg = std::abs(want[i].green() - got[i].green()),
                  db = std::abs(want[i].blue() - got[i].blue());
        const int d = std::max({dr, dg, db});
        // Média por canal, a mesma medida usada no ajuste dos modelos.
        e.mean += (dr + dg + db) / 3.0;
        if (d > e.max) {
            e.max = d;
            e.worst = describe(golden().colors[i]) + u" → " + describe(got[i]) + u", Swift " + describe(want[i]);
        }
    }
    e.mean /= double(want.size());
    return e;
}

#define EXPECT_GOLDEN(name, op, maxTolerance, meanTolerance)                                                           \
    do {                                                                                                               \
        const Error e = compare(name, measure(op));                                                                    \
        QVERIFY2(e.max <= (maxTolerance) && e.mean <= (meanTolerance),                                                 \
                 qPrintable(QStringLiteral("%1: máximo %2, média %3 (%4)").arg(name).arg(e.max).arg(e.mean).arg(e.worst))); \
    } while (false)

} // namespace

class RenderTests : public QObject
{
    Q_OBJECT

private slots:
    void cleanupTestCase()
    {
        if (qEnvironmentVariableIsEmpty("OPENFRAME_KEEP_MEDIA"))
            QDir(mediaDirectory()).removeRecursively();
    }

    // MARK: - Comparação com o Swift

    // Ajustes com fórmula reconstruída: os mesmos números do Core Image
    void adjustMatchesSwift_data()
    {
        QTest::addColumn<QString>("key");
        QTest::addColumn<double>("value");
        QTest::addColumn<int>("maxTolerance");
        for (const char *key : {"brightness", "contrast", "saturation", "exposure", "highlights", "shadows"})
            for (const double v : {-1.0, -0.5, 0.5, 1.0})
                QTest::addRow("%s=%g", key, v) << QString::fromLatin1(key) << v << 2;
        // Temperatura e tom: cores fora do gamut (roxo saturado) divergem um pouco.
        for (const char *key : {"temperature", "tint"})
            for (const double v : {-1.0, -0.5, 0.5, 1.0})
                QTest::addRow("%s=%g", key, v) << QString::fromLatin1(key) << v << 20;
        for (const double v : {-1.0, -0.5, -0.25, 0.25, 0.5, 1.0})
            QTest::addRow("hue=%g", v) << QStringLiteral("hue") << v << 4;
        for (const double v : {0.5, 1.0})
            QTest::addRow("fade=%g", v) << QStringLiteral("fade") << v << 2;
    }

    void adjustMatchesSwift()
    {
        QFETCH(QString, key);
        QFETCH(double, value);
        QFETCH(int, maxTolerance);
        Adjust a;
        double *fields[] = {&a.brightness, &a.contrast, &a.saturation, &a.exposure, &a.temperature, &a.tint,
                            &a.highlights, &a.shadows, &a.hue, &a.fade};
        const QStringList names{"brightness", "contrast", "saturation", "exposure", "temperature",
                                "tint",       "highlights", "shadows",  "hue",      "fade"};
        *fields[names.indexOf(key)] = value;
        const QString name = QStringLiteral("adjust.%1=%2").arg(key, value == std::trunc(value) ? QString::number(value, 'f', 1)
                                                                                                 : QString::number(value));
        EXPECT_GOLDEN(name, [&](LinearImage &img) { ImageEffects::adjust(img, a, 1, 0); }, maxTolerance, 1.5);
    }

    // Filtros: os compostos de ajustes batem; os "fotográficos" são aproximações ajustadas
    void filtersMatchSwift_data()
    {
        QTest::addColumn<int>("preset");
        QTest::addColumn<double>("intensity");
        QTest::addColumn<int>("maxTolerance");
        QTest::addColumn<double>("meanTolerance");
        struct Expect {
            FilterPreset preset;
            int max;
            double mean;
        };
        const Expect expectations[] = {
            {FilterPreset::Vivid, 50, 2.5},     {FilterPreset::Warm, 20, 1.5},    {FilterPreset::Cool, 20, 1.5},
            {FilterPreset::Cinematic, 3, 1},    {FilterPreset::Vintage, 30, 3},   {FilterPreset::Mono, 12, 3},
            {FilterPreset::Noir, 30, 8},        {FilterPreset::Chrome, 90, 9},    {FilterPreset::Fade, 30, 3.5},
            {FilterPreset::Instant, 45, 6.5},   {FilterPreset::Process, 50, 5},   {FilterPreset::Tonal, 2, 1},
            {FilterPreset::Transfer, 45, 8.5},  {FilterPreset::Sepia, 20, 1},
        };
        for (const Expect &e : expectations)
            for (const double intensity : {1.0, 0.5})
                QTest::addRow("%s=%g", qPrintable(enumKey(e.preset)), intensity)
                    << int(e.preset) << intensity << e.max << e.mean;
    }

    void filtersMatchSwift()
    {
        QFETCH(int, preset);
        QFETCH(double, intensity);
        QFETCH(int, maxTolerance);
        QFETCH(double, meanTolerance);
        const FilterSetting setting{FilterPreset(preset), intensity};
        const QString name = QStringLiteral("filter.%1=%2").arg(enumKey(setting.preset), QString::number(intensity, 'f', 1));
        EXPECT_GOLDEN(name, [&](LinearImage &img) { ImageEffects::filter(img, setting); }, maxTolerance, meanTolerance);
    }

    // Opacidade, transições e brilho do fundo desfocado em luz linear, como o Core Image
    void compositingMatchesSwift()
    {
        for (const double alpha : {0.25, 0.5, 0.75})
            EXPECT_GOLDEN(QStringLiteral("opacity=%1").arg(alpha),
                          [&](LinearImage &img) {
                              LinearImage black(img.width(), img.height(), Pixel{0, 0, 0, 1});
                              black.drawAt(img, 0, 0, float(alpha));
                              img = black;
                          },
                          1, 0.5);
        const QList<std::pair<QString, TransitionKind>> kinds{{"dissolve", TransitionKind::Dissolve},
                                                              {"fadeBlack", TransitionKind::FadeBlack},
                                                              {"fadeWhite", TransitionKind::FadeWhite}};
        for (const auto &[name, kind] : kinds)
            for (const double p : {0.25, 0.5, 0.75})
                EXPECT_GOLDEN(QStringLiteral("%1@%2").arg(name).arg(p),
                              [&](LinearImage &img) {
                                  const LinearImage red(img.width(), img.height(), Pixel{1, 0, 0, 1});
                                  img = Transitions::apply(kind, img, red, p, 1);
                              },
                              1, 0.5);
        EXPECT_GOLDEN(QStringLiteral("blurBackgroundBrightness"),
                      [](LinearImage &img) { ImageEffects::brightness(img, -0.08); }, 1, 0.5);
        for (const double t : {0.0, 0.1, 0.2})
            EXPECT_GOLDEN(QStringLiteral("effect.flash@%1").arg(QString::number(t, 'f', 1)),
                          [&](LinearImage &img) {
                              ImageEffects::effects(img, {VideoEffect{QUuid(), VideoEffectKind::Flash, 0.5}}, 1, t);
                          },
                          1, 0.5);
    }

    // MARK: - Porte do RenderTests.swift

    // Fundo colorido do canvas
    void backgroundColor()
    {
        Project p;
        p.canvas.background = CanvasBackground::color({1, 0, 0, 1});
        const QColor c = color(render(p, 0), 0.5, 0.5);
        QVERIFY(c.red() > 240 && c.green() < 15 && c.blue() < 15);
    }

    // Foto 4:3 encaixada num canvas 16:9 deixa barras laterais
    void photoFit()
    {
        Project p;
        p.canvas.aspect = AspectRatio::R16x9;
        TE::addMedia(photoMaterial(QColor(0, 255, 0)), p);
        const QImage bmp = render(p, 0);
        QVERIFY(color(bmp, 0.5, 0.5).green() > 240);
        QVERIFY(color(bmp, 0.03, 0.5).green() < 15);
    }

    // Escala, posição e opacidade
    void transformAndOpacity()
    {
        Project p;
        p.canvas.aspect = AspectRatio::R16x9;
        const QUuid id = TE::addMedia(photoMaterial(Qt::white, 320, 180), p);
        TE::update(p, id, [](Segment &s) {
            s.transform.scale = 0.5;
            s.transform.x = 0.5; // centro em 75% da largura
            s.opacity = 0.5;
        });
        const QImage bmp = render(p, 0);
        const QColor inside = color(bmp, 0.75, 0.5);
        QVERIFY2(inside.red() > 110 && inside.red() < 200, qPrintable(describe(inside))); // branco a 50% sobre preto
        QVERIFY(color(bmp, 0.25, 0.5).red() < 10);
        // Em luz linear, como o Core Image: 50% de branco sobre preto dá 188.
        QVERIFY2(std::abs(inside.red() - 188) <= 2, qPrintable(describe(inside)));
    }

    // Posição y para cima e rotação no sentido horário, como no Swift
    void positionAndRotation()
    {
        Project p;
        p.canvas.aspect = AspectRatio::R16x9;
        const QString path = makeImage(QStringLiteral("png"), 320, 180, Qt::red, Qt::blue);
        const QUuid id = TE::addMedia(*MediaProbe::probe(path), p);
        TE::update(p, id, [](Segment &s) {
            s.transform.scale = 0.5;
            s.transform.y = 0.5; // centro em 75% da altura (para cima)
        });
        QImage bmp = render(p, 0);
        QVERIFY(color(bmp, 0.5, 0.8).red() > 200);  // metade de cima vermelha
        QVERIFY(color(bmp, 0.5, 0.65).blue() > 200); // metade de baixo azul
        QVERIFY(color(bmp, 0.5, 0.3).red() < 10);
        TE::update(p, id, [](Segment &s) {
            s.transform.y = 0;
            s.transform.rotation = 90;
        });
        bmp = render(p, 0);
        // 90° no sentido horário: o topo vermelho vai para a direita.
        QVERIFY2(color(bmp, 0.53, 0.5).red() > 200, qPrintable(describe(color(bmp, 0.53, 0.5))));
        QVERIFY2(color(bmp, 0.47, 0.5).blue() > 200, qPrintable(describe(color(bmp, 0.47, 0.5))));
    }

    // Temperatura positiva esquenta a imagem
    void temperature()
    {
        Project p;
        const QUuid id = TE::addMedia(photoMaterial(QColor(128, 128, 128)), p);
        TE::update(p, id, [](Segment &s) { s.adjust.temperature = 0.8; });
        const QColor warm = color(render(p, 0), 0.5, 0.5);
        TE::update(p, id, [](Segment &s) { s.adjust.temperature = -0.8; });
        const QColor cool = color(render(p, 0), 0.5, 0.5);
        QVERIFY(warm.red() - warm.blue() > 20);
        QVERIFY(cool.blue() - cool.red() > 20);
    }

    // Filtro mono remove a cor
    void monoFilter()
    {
        Project p;
        const QUuid id = TE::addMedia(photoMaterial(QColor(230, 51, 51)), p);
        TE::update(p, id, [](Segment &s) { s.filter = FilterSetting{FilterPreset::Mono}; });
        const QColor c = color(render(p, 0), 0.5, 0.5);
        QVERIFY(std::abs(c.red() - c.green()) < 6 && std::abs(c.green() - c.blue()) < 6);
    }

    // Glitch RGB preserva as cores onde os canais se sobrepõem
    void rgbSplitKeepsColor()
    {
        Project p;
        const QUuid id = TE::addMedia(photoMaterial(Qt::white), p);
        TE::update(p, id, [](Segment &s) { s.effects = {VideoEffect{QUuid::createUuid(), VideoEffectKind::RgbSplit, 1}}; });
        const QColor c = color(render(p, 0), 0.5, 0.5);
        QVERIFY(c.red() > 240 && c.green() > 240 && c.blue() > 240);
    }

    // Efeitos não mudam o tamanho do clipe nem deixam transparência
    void effectsKeepExtent()
    {
        Project p;
        p.canvas.background = CanvasBackground::color({1, 0, 1, 1});
        const QUuid id = TE::addMedia(photoMaterial(QColor(51, 153, 77), 320, 180), p);
        for (const VideoEffectKind kind : allCases<VideoEffectKind>()) {
            if (kind == VideoEffectKind::Shake || kind == VideoEffectKind::ZoomPulse)
                continue;
            TE::update(p, id, [&](Segment &s) { s.effects = {VideoEffect{QUuid::createUuid(), kind, 1}}; });
            // O fundo magenta não pode vazar perto das bordas do clipe.
            const QColor edge = color(render(p, 0), 0.02, 0.5);
            QVERIFY2(!(edge.red() > 200 && edge.blue() > 200 && edge.green() < 60),
                     qPrintable(enumKey(kind) + u" deixou o fundo aparecer"));
        }
    }

    // Animação de entrada começa invisível
    void fadeIn()
    {
        Project p;
        const QUuid id = TE::addMedia(photoMaterial(Qt::white), p);
        TE::update(p, id, [](Segment &s) { s.animationIn = SegmentAnimation{AnimationKind::Fade, Time::second}; });
        QVERIFY(color(render(p, 0), 0.5, 0.5).red() < 10);
        QVERIFY(color(render(p, Time::seconds(1.5)), 0.5, 0.5).red() > 240);
    }

    // Transição dissolver mistura os dois clipes
    void dissolve()
    {
        Project p;
        const QUuid a = TE::addMedia(photoMaterial(Qt::red), p);
        TE::addMedia(photoMaterial(Qt::blue), p);
        TE::update(p, a, [](Segment &s) { s.transition = Transition{TransitionKind::Dissolve, Time::second}; });
        // Clipe A: 0–3 s; B começa em 2 s; meio da transição = 2,5 s.
        const QColor mid = color(render(p, Time::seconds(2.5)), 0.5, 0.5);
        QVERIFY(mid.red() > 60 && mid.blue() > 60);
        QVERIFY(color(render(p, Time::seconds(1)), 0.5, 0.5).blue() < 10);
        QVERIFY(color(render(p, Time::seconds(4)), 0.5, 0.5).red() < 10);
    }

    // Todas as transições começam no clipe A e terminam no B
    void transitionsGoFromAToB()
    {
        Project p;
        const QUuid a = TE::addMedia(photoMaterial(Qt::red), p);
        TE::addMedia(photoMaterial(Qt::blue), p);
        for (const TransitionKind kind : allCases<TransitionKind>()) {
            TE::update(p, a, [&](Segment &s) { s.transition = Transition{kind, Time::second}; });
            const QColor start = color(render(p, Time::seconds(2) + 1000), 0.5, 0.5);
            const QColor end = color(render(p, Time::seconds(3) - 1000), 0.5, 0.5);
            QVERIFY2(start.red() > 200 || kind == TransitionKind::FadeWhite,
                     qPrintable(enumKey(kind) + u" início " + describe(start)));
            QVERIFY2(end.blue() > 200 || kind == TransitionKind::FadeWhite,
                     qPrintable(enumKey(kind) + u" fim " + describe(end)));
        }
    }

    // Texto aparece na posição definida
    void text()
    {
        Project p;
        TextStyle style;
        style.y = 0;
        style.fontSize = 0.3;
        style.shadow = false;
        style.backgroundEnabled = true;
        style.backgroundColor = {1, 1, 0, 1};
        TE::addText({QStringLiteral("OPEN"), style}, p, 0);
        const QImage bmp = render(p, 0);
        bool yellowish = false;
        for (int i = 0; i < 10; ++i) {
            const QColor c = color(bmp, 0.3 + i * 0.04, 0.5);
            yellowish = yellowish || (c.red() > 200 && c.green() > 200 && c.blue() < 60);
        }
        QVERIFY(yellowish);
        QVERIFY(color(bmp, 0.02, 0.95).red() < 10);
        // Fora do intervalo do segmento, nada é desenhado.
        QVERIFY(color(render(p, Time::seconds(5)), 0.5, 0.5).red() < 10);
    }

    // Vídeo gravado em pé é exibido na orientação correta
    void rotatedVideo()
    {
        const QString path = makeVideo({.width = 320, .height = 180, .seconds = 1, .audio = false, .rotation = 90});
        const auto m = MediaProbe::probe(path);
        QVERIFY(m && m->width == 180 && m->height == 320);
        Project p;
        TE::addMedia(*m, p);
        const QSize renderSize = p.canvasSize(180);
        QCOMPARE(renderSize, QSize(180, 320));
        const QImage bmp = render(p, Time::seconds(0.5), renderSize);
        // O topo do quadro original (vermelho) vai para a direita ao girar 90° no sentido horário.
        const QColor right = color(bmp, 0.8, 0.3), left = color(bmp, 0.2, 0.3);
        QVERIFY2(right.red() > 150 && right.blue() < 100, qPrintable(describe(right)));
        QVERIFY2(left.blue() > 150 && left.red() < 100, qPrintable(describe(left)));
    }

    // Vídeo com velocidade 2×: o quadro mostrado anda duas vezes mais rápido
    void videoSpeed()
    {
        const QString path = makeVideo({.seconds = 2, .audio = false});
        Project p;
        const QUuid id = TE::addMedia(*MediaProbe::probe(path), p);
        TE::setSpeed(p, id, 2);
        // Em 0,5 s da timeline mostra o quadro de 1 s do arquivo: faixa em 320 × 30/60.
        const QImage bmp = render(p, Time::seconds(0.5));
        int bright = -1;
        for (int x = 0; x < bmp.width(); ++x)
            if (bmp.pixelColor(x, 45).green() > 200) {
                bright = x;
                break;
            }
        QVERIFY2(std::abs(bright - 158) <= 3, qPrintable(QString::number(bright)));
    }

    // Fundo desfocado preenche as barras com o próprio vídeo, mais escuro
    void blurBackground()
    {
        Project p;
        p.canvas.aspect = AspectRatio::R9x16;
        p.canvas.background = CanvasBackground::blur(0.5);
        TE::addMedia(photoMaterial(QColor(0, 200, 0)), p);
        const QImage bmp = render(p, 0, QSize(180, 320));
        const QColor bar = color(bmp, 0.5, 0.95), center = color(bmp, 0.5, 0.5);
        QVERIFY2(bar.green() > 100 && bar.green() < center.green(), qPrintable(describe(bar)));
        QVERIFY(bar.red() < 20 && bar.blue() < 20);
    }

    // Miniatura dos filtros
    void effectPreview()
    {
        QImage image(40, 30, QImage::Format_RGB32);
        image.fill(QColor(230, 51, 51));
        const QImage mono = EffectPreview::filtered(image, FilterPreset::Mono);
        QCOMPARE(mono.size(), image.size());
        const QColor c = mono.pixelColor(20, 15);
        QVERIFY(std::abs(c.red() - c.green()) < 6 && std::abs(c.green() - c.blue()) < 6);
        QCOMPARE(EffectPreview::filtered(image, FilterPreset::None).pixelColor(20, 15), QColor(230, 51, 51));
    }
};

QTEST_MAIN(RenderTests)
#include "RenderTests.moc"
