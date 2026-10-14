// Mídia: suíte "Importação" (ModelTests.swift), MediaProbe, decodificador,
// cores na decodificação, miniaturas e "Forma de onda" (WaveformTests.swift).
#include "MediaProbe.h"
#include "TestMedia.h"
#include "Thumbnails.h"
#include "VideoDecoder.h"
#include "Waveform.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>

using namespace of;
using namespace of::test;

namespace {
const QColor red(220, 30, 30);
const QColor blue(30, 30, 220);

/// Coluna da faixa branca no quadro `frame` de `frames` (como no testFrame).
int barColumn(int width, int frame, int frames) { return width * frame / frames; }

/// Centro da faixa branca na linha do meio da metade de cima.
int brightestColumn(const QImage &image)
{
    const int y = image.height() / 4;
    int sum = 0, count = 0;
    for (int x = 0; x < image.width(); ++x)
        if (image.pixelColor(x, y).green() > 160) {
            sum += x;
            ++count;
        }
    return count ? int(std::lround(double(sum) / count)) : -1;
}
} // namespace

class MediaTests : public QObject
{
    Q_OBJECT

private slots:
    // Vídeo HDR (HEVC 10 bits BT.2100, como os do iPhone) → SDR, comparado com
    // o que o macOS mostra (qt/tests/tools/gerar-hdr.sh mediu os fixtures).
    void hdrToSdr_data()
    {
        QTest::addColumn<QString>("curve");
        QTest::newRow("HLG") << QStringLiteral("hlg");
        QTest::newRow("PQ") << QStringLiteral("pq");
    }

    void hdrToSdr()
    {
        QFETCH(QString, curve);
        QFile file(QStringLiteral(OPENFRAME_FIXTURES "/hdr.json"));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
        const QJsonArray patches = root[QStringLiteral("patches")].toArray();
        const QJsonObject measured = root[curve].toObject();
        const QJsonArray displayed = measured[QStringLiteral("displayed")].toArray();

        const QString path = QStringLiteral(OPENFRAME_FIXTURES "/") + measured[QStringLiteral("file")].toString();
        QString error;
        auto decoder = VideoDecoder::open(path, &error);
        QVERIFY2(decoder, qPrintable(error));
        const QImage frame = decoder->frameAt(Time::seconds(0.5));
        QVERIFY(!frame.isNull());

        double total = 0;
        int previousGray = -1;
        for (qsizetype i = 0; i < patches.size(); ++i) {
            const QJsonArray in = patches[i].toArray(), want = displayed[i].toArray();
            const QColor expected(want[0].toInt(), want[1].toInt(), want[2].toInt());
            const QColor got = test::pixel(frame, (double(i) + 0.5) / double(patches.size()), 0.5);
            const int diff = std::max({std::abs(got.red() - expected.red()), std::abs(got.green() - expected.green()),
                                       std::abs(got.blue() - expected.blue())});
            total += (std::abs(got.red() - expected.red()) + std::abs(got.green() - expected.green()) +
                      std::abs(got.blue() - expected.blue())) / 3.0;
            const bool gray = in[0] == in[1] && in[1] == in[2];
            // Cinzas: até 4 níveis. Cores: até 12; no PQ, as muito claras (sinal ≥ 180,
            // acima de ~700 nits) até 50, porque o macOS preserva mais a saturação
            // nos realces do que a curva na luminância.
            const int maxChannel = std::max({in[0].toInt(), in[1].toInt(), in[2].toInt()});
            const int tolerance = gray ? 4 : curve == u"pq" && maxChannel >= 180 ? 50 : 12;
            QVERIFY2(diff <= tolerance, qPrintable(QStringLiteral("faixa %1 (%2, %3, %4): sistema %5, nosso %6")
                                                       .arg(i)
                                                       .arg(in[0].toInt())
                                                       .arg(in[1].toInt())
                                                       .arg(in[2].toInt())
                                                       .arg(test::describe(expected), test::describe(got))));
            if (gray) {
                // Os tons de cinza sobem em ordem até saturar no branco (folga
                // para o ruído de croma do codec).
                QVERIFY(got.green() >= previousGray - 3);
                previousGray = std::max(previousGray, got.green());
            }
        }
        QVERIFY2(total / double(patches.size()) < 2, qPrintable(QString::number(total / double(patches.size()))));
    }

    // OPENFRAME_KEEP_MEDIA=1 guarda os arquivos gerados para inspeção.
    void cleanupTestCase()
    {
        if (qEnvironmentVariableIsEmpty("OPENFRAME_KEEP_MEDIA"))
            QDir(mediaDirectory()).removeRecursively();
    }

    // Aceita vídeos, fotos e áudios, inclusive .MOV em maiúsculas
    void supportedExtensions()
    {
        for (const char *name : {"a.mov", "IMG_7565.MOV", "a.mp4", "a.M4V", "a.m4a", "a.mp3", "a.wav", "a.png", "a.JPG",
                                 "a.heic"})
            QVERIFY2(MediaProbe::isSupported(QStringLiteral("/tmp/") + QLatin1StringView(name)), name);
        for (const char *name : {"a.txt", "a.srt", "a.openframe", "sem-extensao"})
            QVERIFY2(!MediaProbe::isSupported(QStringLiteral("/tmp/") + QLatin1StringView(name)), name);
    }

    // .MOV de iPhone vira vídeo, com dimensões, duração e áudio
    void probeUppercaseMov()
    {
        const QString src = makeVideo({.seconds = 0.5});
        const QString upper = src.chopped(3) + u"MOV";
        QVERIFY(QFile::rename(src, upper));
        QString error;
        const auto m = MediaProbe::probe(upper, &error);
        QVERIFY2(m, qPrintable(error));
        QCOMPARE(m->kind, MaterialKind::Video);
        QCOMPARE(m->width, 320);
        QCOMPARE(m->height, 180);
        QVERIFY(m->hasAudio);
        QVERIFY2(std::abs(m->duration - 500'000) < 50'000, qPrintable(QString::number(m->duration)));
        QCOMPARE(m->name, QFileInfo(upper).fileName());
        QCOMPARE(m->path, upper);
    }

    // Vídeo gravado de lado: as dimensões já vêm giradas
    void probeRotatedVideo()
    {
        const auto m = MediaProbe::probe(makeVideo({.seconds = 0.2, .audio = false, .rotation = 90}));
        QVERIFY(m);
        QCOMPARE(QSize(m->width, m->height), QSize(180, 320));
        QVERIFY(!m->hasAudio);
    }

    // Foto com orientação EXIF 6 (90°) troca largura e altura
    void probeOrientedPhoto()
    {
        const QString path =
            makeImage(QStringLiteral("jpg"), 400, 300, red, blue, QImageIOHandler::TransformationRotate90);
        const auto m = MediaProbe::probe(path);
        QVERIFY(m);
        QCOMPARE(m->kind, MaterialKind::Photo);
        QCOMPARE(QSize(m->width, m->height), QSize(300, 400));
        QCOMPARE(m->duration, 0);
        // A imagem carregada já vem de pé: o topo vermelho foi para a direita.
        const QImage image = Images::load(path);
        QCOMPARE(image.size(), QSize(300, 400));
        QCOMPARE(image.format(), QImage::Format_ARGB32_Premultiplied);
        QVERIFY2(near(pixel(image, 0.8, 0.5), red, 12), qPrintable(describe(pixel(image, 0.8, 0.5))));
        QVERIFY2(near(pixel(image, 0.2, 0.5), blue, 12), qPrintable(describe(pixel(image, 0.2, 0.5))));
        QCOMPARE(Images::load(path, 100).size(), QSize(75, 100));
    }

    void probeAudio()
    {
        const auto m = MediaProbe::probe(makeAudio(1));
        QVERIFY(m);
        QCOMPARE(m->kind, MaterialKind::Audio);
        QVERIFY(m->hasAudio);
        QCOMPARE(m->width, 0);
        QVERIFY2(std::abs(m->duration - Time::second) < 50'000, qPrintable(QString::number(m->duration)));
    }

    void probeErrors()
    {
        const QString junk = tempPath(QStringLiteral("mp4"));
        QFile file(junk);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("isto não é um vídeo");
        file.close();
        QString error;
        QVERIFY(!MediaProbe::probe(junk, &error));
        QCOMPARE(error, QStringLiteral("Não foi possível ler: ") + QFileInfo(junk).fileName());
        QVERIFY(!MediaProbe::probe(QStringLiteral("/tmp/notas.txt"), &error));
        QCOMPARE(error, QStringLiteral("Formato não suportado: notas.txt"));
    }

    // Busca precisa: cada instante mostra o quadro certo, em qualquer ordem
    void decoderSeeksExactly()
    {
        const VideoOptions o{.seconds = 2, .audio = false};
        const QString path = makeVideo(o);
        auto decoder = VideoDecoder::open(path);
        QVERIFY(decoder);
        QCOMPARE(decoder->displaySize(), QSize(320, 180));
        const int frames = 60;
        for (const int f : {37, 3, 59, 0, 30, 31, 12}) {
            // No início do quadro, no meio e logo antes do seguinte.
            for (const Micros offset : {Micros(0), Micros(16'000), Micros(33'000)}) {
                const Micros t = Time::round(f * 1e6 / 30) + offset;
                const QImage image = decoder->frameAt(t);
                QVERIFY(!image.isNull());
                const int expected = barColumn(o.width, f, frames);
                const int found = brightestColumn(image);
                QVERIFY2(std::abs(found - expected) <= 2,
                         qPrintable(QStringLiteral("quadro %1 (+%2 µs): faixa em %3, esperada em %4")
                                        .arg(f).arg(offset).arg(found).arg(expected)));
                QCOMPARE(decoder->lastFrameTime(), Time::round(f * 1e6 / 30));
            }
        }
        // Além do fim fica o último quadro.
        QVERIFY(std::abs(brightestColumn(decoder->frameAt(5 * Time::second)) - barColumn(o.width, 59, frames)) <= 2);
    }

    // Reprodução em sequência decodifica para a frente, sem buscar a cada quadro
    void decoderSequentialReadsWithoutSeeking()
    {
        auto decoder = VideoDecoder::open(makeVideo({.seconds = 2, .audio = false}));
        QVERIFY(decoder);
        for (int f = 0; f < 60; ++f)
            QVERIFY(std::abs(brightestColumn(decoder->frameAt(Time::round(f * 1e6 / 30))) - barColumn(320, f, 60)) <= 2);
        QCOMPARE(decoder->seekCount(), 1);
        // Pedir de novo o mesmo instante não decodifica nada.
        decoder->frameAt(Time::round(59 * 1e6 / 30));
        QCOMPARE(decoder->seekCount(), 1);
    }

    // Cores na decodificação: matriz e intervalo do arquivo; sem marca, 709 em HD e 601 em SD
    void decoderColors_data()
    {
        QTest::addColumn<int>("width");
        QTest::addColumn<int>("height");
        QTest::addColumn<int>("matrix");
        QTest::addColumn<bool>("tagged");
        QTest::addColumn<bool>("fullRange");
        QTest::addColumn<int>("codec");
        const int bt709 = int(MediaWriter::Matrix::BT709), bt601 = int(MediaWriter::Matrix::BT601);
        const int h264 = int(VideoCodec::H264);
        QTest::newRow("709 marcado") << 320 << 180 << bt709 << true << false << h264;
        QTest::newRow("601 marcado") << 320 << 180 << bt601 << true << false << h264;
        QTest::newRow("709 intervalo cheio") << 320 << 180 << bt709 << true << true << h264;
        QTest::newRow("HD sem marca = 709") << 1280 << 720 << bt709 << false << false << h264;
        QTest::newRow("SD sem marca = 601") << 640 << 480 << bt601 << false << false << h264;
        QTest::newRow("HEVC 709") << 320 << 180 << bt709 << true << false << int(VideoCodec::Hevc);
        QTest::newRow("ProRes 709") << 320 << 180 << bt709 << true << false << int(VideoCodec::ProRes422);
    }

    void decoderColors()
    {
        QFETCH(int, width);
        QFETCH(int, height);
        QFETCH(int, matrix);
        QFETCH(bool, tagged);
        QFETCH(bool, fullRange);
        QFETCH(int, codec);
        // Cores saturadas: com a matriz errada o vermelho erra por dezenas de níveis.
        const QList<QColor> colors{red, blue, QColor(40, 200, 90), QColor(128, 128, 128), QColor(16, 16, 16)};
        for (const QColor &color : colors) {
            VideoOptions o;
            o.width = width;
            o.height = height;
            o.seconds = 0.1;
            o.audio = false;
            o.matrix = MediaWriter::Matrix(matrix);
            o.tagged = tagged;
            o.fullRange = fullRange;
            o.codec = VideoCodec(codec);
            o.top = o.bottom = color;
            o.bar = false;
            o.extension = codec == int(VideoCodec::ProRes422) ? QStringLiteral("mov") : QStringLiteral("mp4");
            auto decoder = VideoDecoder::open(makeVideo(o));
            QVERIFY(decoder);
            const QColor got = pixel(decoder->frameAt(0), 0.5, 0.5);
            QVERIFY2(near(got, color, 4), qPrintable(describe(got) + u" ≠ " + describe(color)));
        }
    }

    // Vídeo girado sai de pé; o tamanho máximo vale para a imagem girada
    void decoderRotation()
    {
        auto decoder = VideoDecoder::open(makeVideo({.seconds = 0.2, .audio = false, .rotation = 90, .bar = false}));
        QVERIFY(decoder);
        QCOMPARE(decoder->displaySize(), QSize(180, 320));
        const QImage image = decoder->frameAt(0);
        QCOMPARE(image.size(), QSize(180, 320));
        // Girado 90° no sentido horário: o topo vermelho fica à direita.
        QVERIFY2(near(pixel(image, 0.8, 0.5), red, 6), qPrintable(describe(pixel(image, 0.8, 0.5))));
        QVERIFY2(near(pixel(image, 0.2, 0.5), blue, 6), qPrintable(describe(pixel(image, 0.2, 0.5))));
        QCOMPARE(decoder->frameAt(0, QSize(90, 90)).size(), QSize(51, 90));
    }

    // Cada segmento tem o seu decodificador
    void decoderCachePerSegment()
    {
        const QString path = makeVideo({.seconds = 2, .audio = false});
        DecoderCache cache(4);
        const QUuid a = QUuid::createUuid(), b = QUuid::createUuid();
        for (int f = 0; f < 10; ++f) {
            QVERIFY(std::abs(brightestColumn(cache.frame(a, path, Time::round(f * 1e6 / 30))) - barColumn(320, f, 60)) <= 2);
            QVERIFY(std::abs(brightestColumn(cache.frame(b, path, Time::round((f + 40) * 1e6 / 30))) -
                             barColumn(320, f + 40, 60)) <= 2);
        }
        QVERIFY(cache.frame(QUuid::createUuid(), QStringLiteral("/tmp/nao-existe.mov"), 0).isNull());
    }

    void thumbnails()
    {
        const QString path = makeVideo({.seconds = 2, .audio = false});
        const auto video = MediaProbe::probe(path);
        QVERIFY(video);
        const auto frames = Thumbnails::frames(*video, 4, 100);
        QCOMPARE(frames.size(), 4);
        QCOMPARE(frames[0].size(), QSize(100, 56));
        // Quadros em (i + 0,5)/4 da duração: 0,25 s, 0,75 s…
        QVERIFY(std::abs(brightestColumn(frames[1]) - barColumn(100, 22, 60)) <= 2);

        const auto photo = MediaProbe::probe(makeImage(QStringLiteral("png"), 400, 300, red, blue));
        QVERIFY(photo);
        const auto one = Thumbnails::frames(*photo, 10, 240);
        QCOMPARE(one.size(), 1);
        QCOMPARE(one[0].size(), QSize(240, 180));
        QVERIFY(Thumbnails::frames(*MediaProbe::probe(makeAudio(0.5))).isEmpty());
    }

    // Um pico por intervalo, normalizado
    void waveformPeaks()
    {
        const auto peaks = Waveform::peaks(makeVideo({.seconds = 2, .audio = true}), 20);
        // 2 s a 20 picos/s; o AAC pode acrescentar alguns quadros de silêncio.
        QVERIFY2(peaks.size() >= 40 && peaks.size() <= 44, qPrintable(QString::number(peaks.size())));
        QCOMPARE(*std::max_element(peaks.cbegin(), peaks.cend()), 1.0f);
        // Seno de amplitude constante: o meio do arquivo fica perto do topo.
        for (int i = 10; i < 30; ++i)
            QVERIFY2(peaks[i] > 0.8f, qPrintable(QString::number(peaks[i])));
    }

    // Vídeo sem áudio não tem picos
    void waveformSilentVideo() { QVERIFY(Waveform::peaks(makeVideo({.seconds = 1, .audio = false})).isEmpty()); }
};

QTEST_GUILESS_MAIN(MediaTests)
#include "MediaTests.moc"
