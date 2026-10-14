// Porte da suíte "Configurações de exportação" (ModelTests.swift).
#include "ExportSettings.h"
#include "TestSupport.h"

using namespace of;
using namespace of::test;

class ExportSettingsTests : public QObject
{
    Q_OBJECT

    static Project project(double seconds, AspectRatio aspect = AspectRatio::R16x9)
    {
        Project p;
        p.canvas.aspect = aspect;
        TimelineEditor::addMedia(video(seconds, QStringLiteral("a.mov")), p);
        return p;
    }

private slots:
    // Resolução segue a proporção do canvas
    void outputSize()
    {
        ExportSettings s;
        s.resolution = ResolutionPreset::P2160;
        QCOMPARE(s.outputSize(project(1)), QSize(3840, 2160));
        QCOMPARE(s.outputSize(project(1, AspectRatio::R9x16)), QSize(2160, 3840));
        s.resolution = ResolutionPreset::Custom;
        s.customWidth = 1001;
        s.customHeight = 501;
        QCOMPARE(s.outputSize(project(1)), QSize(1000, 500));
    }

    // Qualidade escala o bitrate; HEVC usa menos que H.264
    void bitratePresets()
    {
        const QSize size(1920, 1080);
        ExportSettings s;
        s.bitrateMode = BitrateMode::Lower;
        const qint64 lower = s.videoBitrate(size, Time::second);
        s.bitrateMode = BitrateMode::Recommended;
        const qint64 recommended = s.videoBitrate(size, Time::second);
        s.bitrateMode = BitrateMode::Higher;
        const qint64 higher = s.videoBitrate(size, Time::second);
        QVERIFY(lower < recommended && recommended < higher);
        QVERIFY(std::abs(recommended - 6'220'800) < 1000); // 1920×1080×30×0,1

        s.bitrateMode = BitrateMode::Recommended;
        s.codec = VideoCodec::Hevc;
        QVERIFY(s.videoBitrate(size, Time::second) < recommended);

        s.frameRate = FrameRate::Fps60;
        s.codec = VideoCodec::H264;
        QCOMPARE(s.videoBitrate(size, Time::second), recommended * 2);
    }

    // Tamanho alvo determina o bitrate
    void targetSize()
    {
        ExportSettings s;
        s.bitrateMode = BitrateMode::TargetSize;
        s.targetMegabytes = 30;
        s.audioKbps = 128;
        const Project p = project(60);
        // 30 MB em 60 s = 4 Mbps no total, menos 128 kbps de áudio.
        QCOMPARE(s.videoBitrate(s.outputSize(p), p.duration()), 4'000'000 - 128'000);
        const double estimate = double(s.estimatedBytes(p));
        QVERIFY(std::abs(estimate - 30'000'000) / 30'000'000 < 0.02);
    }

    // Bitrate personalizado e estimativa de tamanho
    void customBitrate()
    {
        ExportSettings s;
        s.bitrateMode = BitrateMode::Custom;
        s.customMbps = 8;
        s.audioEnabled = false;
        const Project p = project(10);
        QCOMPARE(s.videoBitrate(s.outputSize(p), p.duration()), 8'000'000);
        QVERIFY(std::abs(s.estimatedBytes(p) - 10'100'000) < 1000);
        // Só áudio: a estimativa ignora o vídeo.
        s.container = ContainerFormat::M4a;
        s.audioEnabled = true;
        QCOMPARE(s.estimatedBytes(p), qint64(192'000.0 * 10 / 8 * 1.01));
    }

    // Validação recusa combinações impossíveis
    void validation()
    {
        const Project p = project(2);
        ExportSettings s;
        QVERIFY(!s.validationError(p));
        s.resolution = ResolutionPreset::P4320;
        QVERIFY(s.validationError(p)); // 8K em H.264
        QVERIFY(s.validationError(p)->startsWith(QStringLiteral("H.264 suporta até 4096 px")));
        s.codec = VideoCodec::Hevc;
        QVERIFY(!s.validationError(p));
        s.codec = VideoCodec::ProRes422;
        QVERIFY(s.validationError(p)); // ProRes em MP4
        s.container = ContainerFormat::Mov;
        QVERIFY(!s.validationError(p));
        QVERIFY(ExportSettings().validationError(Project()));
        ExportSettings m4a;
        m4a.container = ContainerFormat::M4a;
        m4a.audioEnabled = false;
        QCOMPARE(m4a.validationError(p), std::optional(QStringLiteral("Ative o áudio para exportar M4A.")));
        ExportSettings tiny;
        tiny.resolution = ResolutionPreset::Custom;
        tiny.customWidth = 8;
        QCOMPARE(tiny.validationError(p), std::optional(QStringLiteral("Resolução muito pequena.")));
    }

    // Durações de quadro exatas para taxas NTSC
    void frameRates()
    {
        QVERIFY(std::abs(fpsValue(FrameRate::Fps29_97) - 29.97) < 0.001);
        QVERIFY(std::abs(fpsValue(FrameRate::Fps23_976) - 23.976) < 0.001);
        QCOMPARE(fpsValue(FrameRate::Fps120), 120.0);
        QCOMPARE(frameDuration(FrameRate::Fps59_94), (Rational{1001, 60000}));
        ExportSettings s;
        QCOMPARE(s.keyframeDistance(), 60);
        s.frameRate = FrameRate::Fps29_97;
        s.keyframeInterval = 0.01;
        QCOMPARE(s.keyframeDistance(), 1);
    }

    // Tamanho formatado como o ByteCountFormatter do macOS (valores medidos no Swift)
    void fileSizes()
    {
        const QLocale pt(QLocale::Portuguese, QLocale::Brazil);
        const QList<std::pair<qint64, QString>> cases{
            {0, "Zero KB"},          {1, "1 byte"},           {999, "999 bytes"},     {1000, "1 KB"},
            {12'345, "12 KB"},       {999'499, "999 KB"},     {999'500, "1 MB"},      {1'500'000, "1,5 MB"},
            {12'000'000, "12 MB"},   {12'345'678, "12,3 MB"}, {123'456'789, "123,5 MB"}, {999'949'999, "999,9 MB"},
            {999'950'000, "1 GB"},   {1'005'000'000, "1,01 GB"}, {1'234'567'890, "1,23 GB"}, {1'999'999'999, "2 GB"},
            {12'345'678'901, "12,35 GB"}, {1'234'567'890'123, "1,23 TB"}};
        for (const auto &[bytes, expected] : cases)
            QCOMPARE(formattedFileSize(bytes, pt), expected);
    }

    void labels()
    {
        QCOMPARE(label(ResolutionPreset::P1440), QStringLiteral("2K"));
        QCOMPARE(label(FrameRate::Fps23_976), QStringLiteral("23,976 fps"));
        QCOMPARE(label(VideoCodec::Hevc), QStringLiteral("HEVC (H.265)"));
        QCOMPARE(label(ContainerFormat::M4a), QStringLiteral("M4A (só áudio)"));
        QCOMPARE(label(BitrateMode::TargetSize), QStringLiteral("Tamanho de arquivo alvo"));
        QCOMPARE(fileExtension(ContainerFormat::Mov), QStringLiteral("mov"));
        QCOMPARE(allCases<FrameRate>().size(), 9);
    }
};

QTEST_GUILESS_MAIN(ExportSettingsTests)
#include "ExportSettingsTests.moc"
