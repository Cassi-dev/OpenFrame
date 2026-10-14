// Porte da suíte "Legendas" (ModelTests.swift).
#include "Subtitles.h"
#include "TestSupport.h"

using namespace of;

namespace {
const QString sample = QStringLiteral("1\n"
                                      "00:00:01,000 --> 00:00:03,500\n"
                                      "Primeira linha\n"
                                      "\n"
                                      "2\n"
                                      "00:00:04,250 --> 00:00:06,000 X1:10 X2:20\n"
                                      "Duas\n"
                                      "linhas\n"
                                      "\n"
                                      "lixo sem horário");
}

class SubtitleTests : public QObject
{
    Q_OBJECT

private slots:
    void parses()
    {
        const auto cues = SRT::parse(sample);
        QCOMPARE(cues.size(), 2);
        QCOMPARE(cues[0], (SubtitleCue{1'000'000, 3'500'000, QStringLiteral("Primeira linha")}));
        QCOMPARE(cues[1].start, 4'250'000);
        QCOMPARE(cues[1].text, QStringLiteral("Duas\nlinhas"));
    }

    void roundTrips() { QCOMPARE(SRT::parse(SRT::serialize(SRT::parse(sample))), SRT::parse(sample)); }

    void importsAsTextTrack()
    {
        Project p;
        SRT::importCues(SRT::parse(sample), p);
        const Track &track = p.tracks.last();
        QCOMPARE(track.kind, TrackKind::Text);
        QCOMPARE(track.segments.size(), 2);
        QCOMPARE(SRT::cues(p), SRT::parse(sample));
    }

    // Windows (CRLF), BOM, ponto decimal, blocos fora de ordem e tempos inválidos
    void tolerantInput()
    {
        const QString crlf = QStringLiteral("﻿2\r\n00:00:05.500 --> 00:00:06.000\r\nDepois\r\n\r\n"
                                            "1\r\n00:00:01,000 --> 00:00:02,000\r\nAntes\r\n\r\n"
                                            "3\r\n00:00:09,000 --> 00:00:08,000\r\nAo contrário\r\n\r\n"
                                            "4\r\n00:00:10,000 --> 00:00:11,000\r\n   \r\n");
        const auto cues = SRT::parse(crlf);
        QCOMPARE(cues.size(), 2);
        QCOMPARE(cues[0].text, QStringLiteral("Antes"));
        QCOMPARE(cues[1].start, 5'500'000);
        QCOMPARE(SRT::parseTimestamp(QStringLiteral(" 01:02:03,004 ")), std::optional<Micros>(3'723'004'000));
        QVERIFY(!SRT::parseTimestamp(QStringLiteral("02:03,004")));
    }

    void serializes()
    {
        const QList<SubtitleCue> cues{{0, 1'500'000, QStringLiteral("Oi")}, {3'723'004'999, 3'724'000'000, QStringLiteral("Tchau")}};
        QCOMPARE(SRT::serialize(cues), QStringLiteral("1\n00:00:00,000 --> 00:00:01,500\nOi\n\n"
                                                      "2\n01:02:03,004 --> 01:02:04,000\nTchau\n"));
        QCOMPARE(SRT::timestamp(-5), QStringLiteral("00:00:00,000"));
    }

    // Faixas de texto ocultas não exportam; legendas curtas ganham a duração mínima
    void cuesFromProject()
    {
        Project p;
        SRT::importCues({{0, 10, QStringLiteral("curta")}}, p);
        QCOMPARE(p.tracks.last().segments[0].targetDuration(), TimelineEditor::minDuration);
        QCOMPARE(SRT::cues(p).size(), 1);
        p.tracks.last().hidden = true;
        QVERIFY(SRT::cues(p).isEmpty());
        SRT::importCues({}, p);
        QCOMPARE(p.tracks.size(), 2);
    }
};

QTEST_GUILESS_MAIN(SubtitleTests)
#include "SubtitleTests.moc"
