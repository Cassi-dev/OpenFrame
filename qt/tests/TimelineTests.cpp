// Porte da suíte "Timeline" (Tests/OpenFrameCoreTests/TimelineEditorTests.swift).
#include "TestSupport.h"

using namespace of;
using namespace of::test;
namespace TE = of::TimelineEditor;

class TimelineTests : public QObject
{
    Q_OBJECT

    /// Faixa principal com clipes das durações dadas, sem transições.
    static std::pair<Project, QList<QUuid>> mainProject(const QList<double> &seconds)
    {
        Project p;
        QList<QUuid> out;
        for (int i = 0; i < seconds.size(); ++i)
            out.append(TE::addMedia(video(seconds[i], QStringLiteral("%1.mov").arg(i)), p));
        return {p, out};
    }

private slots:
    // Clipes visuais entram encostados na faixa principal
    void appendsToMainTrack()
    {
        Project p;
        TE::addMedia(video(4), p);
        TE::addMedia(video(2, QStringLiteral("b.mov")), p);
        TE::addMedia(photo(), p);

        const auto &segs = mainSegments(p);
        QCOMPARE(segs.size(), 3);
        QCOMPARE(segs[0].targetStart, 0);
        QCOMPARE(segs[1].targetStart, Time::seconds(4));
        QCOMPARE(segs[2].targetStart, Time::seconds(6));
        QCOMPARE(segs[2].targetDuration(), TE::defaultPhotoDuration);
        QCOMPARE(p.duration(), Time::seconds(9));
        QCOMPARE(p.materials.size(), 3);
    }

    // Dividir mantém o conteúdo contínuo
    void split()
    {
        Project p;
        const QUuid id = TE::addMedia(video(10), p);
        const auto rightId = TE::split(p, id, Time::seconds(4));
        QVERIFY(rightId);

        const auto &segs = mainSegments(p);
        QCOMPARE(segs.size(), 2);
        QCOMPARE(segs[0].source, (TimeRange{0, Time::seconds(4)}));
        QCOMPARE(segs[1].id, *rightId);
        QCOMPARE(segs[1].source, (TimeRange{Time::seconds(4), Time::seconds(6)}));
        QCOMPARE(segs[1].targetStart, Time::seconds(4));
    }

    // Dividir com velocidade converte para o tempo do arquivo
    void splitWithSpeed()
    {
        Project p;
        const QUuid id = TE::addMedia(video(10), p);
        TE::setSpeed(p, id, 2); // 5 s na timeline
        QCOMPARE(p.duration(), Time::seconds(5));
        QVERIFY(TE::split(p, id, Time::seconds(1)));
        const auto &segs = mainSegments(p);
        QCOMPARE(segs[0].source.duration, Time::seconds(2));
        QCOMPARE(segs[1].source.start, Time::seconds(2));
        QCOMPARE(segs[1].targetDuration(), Time::seconds(4));
    }

    // Não divide perto demais das bordas
    void splitRejectsEdges()
    {
        Project p;
        const QUuid id = TE::addMedia(video(3), p);
        QVERIFY(!TE::split(p, id, 10'000));
        QVERIFY(!TE::split(p, id, Time::seconds(3) - 10'000));
    }

    // Dividir texto e foto não desloca a origem; a direita perde entrada e a esquerda a saída
    void splitClearsInnerEffects()
    {
        Project p;
        const QUuid photoId = TE::addMedia(photo(), p);
        TE::update(p, photoId, [](Segment &s) {
            s.fadeIn = s.fadeOut = 100'000;
            s.animationIn = SegmentAnimation{AnimationKind::Fade};
            s.animationOut = SegmentAnimation{AnimationKind::Spin};
            s.transition = Transition{TransitionKind::Zoom};
        });
        const auto right = TE::split(p, photoId, Time::seconds(1));
        QVERIFY(right);
        const Segment left = *p.segment(photoId), r = *p.segment(*right);
        QCOMPARE(r.source.start, 0);
        QVERIFY(!left.transition && !left.animationOut && left.fadeOut == 0);
        QVERIFY(left.animationIn && left.fadeIn == 100'000);
        QVERIFY(!r.animationIn && r.fadeIn == 0);
        QVERIFY(r.animationOut && r.transition);

        const QUuid t = TE::addText(text(QStringLiteral("A")), p, 0);
        const auto t2 = TE::split(p, t, Time::seconds(1));
        QVERIFY(t2);
        QCOMPARE(p.segment(*t2)->source, (TimeRange{0, Time::seconds(2)}));
        QCOMPARE(p.segment(*t2)->targetStart, Time::seconds(1));
    }

    // Apagar na faixa principal fecha o buraco (ripple)
    void deleteRipples()
    {
        Project p;
        const QUuid a = TE::addMedia(video(3), p);
        TE::addMedia(video(2, QStringLiteral("b.mov")), p);
        TE::remove(p, a);
        QCOMPARE(mainSegments(p).size(), 1);
        QCOMPARE(mainSegments(p)[0].targetStart, 0);
        QCOMPARE(p.duration(), Time::seconds(2));
    }

    // Aparar respeita os limites do arquivo
    void trimClamps()
    {
        Project p;
        const QUuid id = TE::addMedia(video(5), p);
        TE::trimEnd(p, id, Time::seconds(20));
        QCOMPARE(p.segment(id)->source.duration, Time::seconds(5));

        TE::trimStart(p, id, Time::seconds(2));
        const Segment s = *p.segment(id);
        QCOMPARE(s.source.start, Time::seconds(2));
        QCOMPARE(s.source.duration, Time::seconds(3));
        QCOMPARE(s.targetStart, 0); // faixa principal continua encostada no início

        TE::trimStart(p, id, -Time::seconds(10));
        QCOMPARE(p.segment(id)->source.start, 0);
    }

    // Aparar fora da faixa principal não passa do zero nem do mínimo
    void trimOverlayLimits()
    {
        Project p;
        TE::addMedia(video(10), p);
        const QUuid o = TE::addOverlay(video(5, QStringLiteral("o.mov")), p, Time::seconds(1));
        TE::trimStart(p, o, Time::seconds(3));
        QCOMPARE(p.segment(o)->targetStart, Time::seconds(3));
        QCOMPARE(p.segment(o)->source.start, Time::seconds(2));
        // Voltar além do início do arquivo para no início do arquivo.
        TE::trimStart(p, o, 0);
        QCOMPARE(p.segment(o)->source.start, 0);
        QCOMPARE(p.segment(o)->targetStart, Time::seconds(1));
        // Encurtar além do fim deixa a duração mínima.
        TE::trimStart(p, o, Time::seconds(9));
        QCOMPARE(p.segment(o)->targetDuration(), TE::minDuration);
        TE::trimEnd(p, o, 0);
        QCOMPARE(p.segment(o)->targetDuration(), TE::minDuration);
    }

    // Fotos podem ser esticadas sem limite
    void photoTrim()
    {
        Project p;
        const QUuid id = TE::addMedia(photo(), p);
        TE::trimEnd(p, id, Time::seconds(12));
        QCOMPARE(p.segment(id)->targetDuration(), Time::seconds(12));
        QCOMPARE(p.segment(id)->source.start, 0);
    }

    // Transição sobrepõe os clipes vizinhos
    void transitionOverlap()
    {
        Project p;
        const QUuid a = TE::addMedia(video(4), p);
        TE::addMedia(video(4, QStringLiteral("b.mov")), p);
        TE::update(p, a, [](Segment &s) { s.transition = Transition{TransitionKind::Dissolve, Time::seconds(1)}; });
        QCOMPARE(mainSegments(p)[1].targetStart, Time::seconds(3));
        QCOMPARE(p.duration(), Time::seconds(7));

        // Transição maior que metade do clipe é limitada.
        TE::update(p, a, [](Segment &s) { s.transition->duration = Time::seconds(10); });
        QCOMPARE(mainSegments(p)[1].targetStart, Time::seconds(2));
    }

    // Velocidade fica entre 0,1× e 10× e arredonda a duração como o Swift
    void speedLimitsAndRounding()
    {
        Project p;
        const QUuid id = TE::addMedia(video(1), p);
        TE::setSpeed(p, id, 50);
        QCOMPARE(p.segment(id)->speed, 10.0);
        TE::setSpeed(p, id, 0.01);
        QCOMPARE(p.segment(id)->speed, 0.1);
        TE::setSpeed(p, id, 3);
        QCOMPARE(p.segment(id)->targetDuration(), 333'333); // 1 000 000 / 3 = 333 333,3…
        Segment half(std::nullopt, {0, 5}, 0);
        half.speed = 2;
        QCOMPARE(half.targetDuration(), 3); // 2,5 arredonda para longe do zero
    }

    // Sobreposições e textos vão para faixas próprias sem colidir
    void overlayPlacement()
    {
        Project p;
        TE::addMedia(video(10), p);
        const QUuid o1 = TE::addOverlay(video(3, QStringLiteral("o1.mov")), p, Time::seconds(1));
        const QUuid o2 = TE::addOverlay(video(3, QStringLiteral("o2.mov")), p, Time::seconds(2));
        const QUuid o3 = TE::addOverlay(video(2, QStringLiteral("o3.mov")), p, Time::seconds(5));
        QCOMPARE(p.locate(o1)->track, p.locate(o3)->track);
        QVERIFY(p.locate(o1)->track != p.locate(o2)->track);
        QCOMPARE(p.segment(o1)->transform.scale, 0.5);

        const QUuid t = TE::addText(text(QStringLiteral("Olá")), p, Time::seconds(2));
        QCOMPARE(p.tracks[p.locate(t)->track].kind, TrackKind::Text);
    }

    // Áudio vai para faixa de áudio e cria outra se colidir
    void audioPlacement()
    {
        Project p;
        const QUuid a = TE::addMedia(audio(5), p, 0);
        const QUuid b = TE::addMedia(audio(5), p, Time::seconds(2));
        QCOMPARE(p.tracks[p.locate(a)->track].kind, TrackKind::Audio);
        QVERIFY(p.locate(a)->track != p.locate(b)->track);
    }

    // Reordenar a faixa principal pelo centro
    void reorder()
    {
        Project p;
        const QUuid a = TE::addMedia(video(2, QStringLiteral("a.mov")), p);
        const QUuid b = TE::addMedia(video(2, QStringLiteral("b.mov")), p);
        TE::reorderMain(p, a, Time::seconds(3.5));
        QCOMPARE(ids(mainSegments(p)), (QList<QUuid>{b, a}));
        QCOMPARE(mainSegments(p)[0].targetStart, 0);
        QCOMPARE(mainSegments(p)[1].targetStart, Time::seconds(2));
    }

    // Reordenar é simétrico: direita e esquerda trocam na mesma distância
    void reorderIsSymmetric()
    {
        // [2, 3, 5] arrastando o do meio para a direita espelha [5, 3, 2] para a esquerda.
        // Os centros ficam a 4 s: troca só depois disso, nos dois sentidos (empate não troca).
        for (int step = 0; step <= 40; ++step) {
            const double d = step * 0.25;
            auto right = mainProject({2, 3, 5});
            const Micros rightCenter = (Time::seconds(2) + Time::seconds(5)) / 2;
            TE::reorderMain(right.first, right.second[1], rightCenter + Time::seconds(d));
            auto left = mainProject({5, 3, 2});
            const Micros leftCenter = (Time::seconds(5) + Time::seconds(8)) / 2;
            TE::reorderMain(left.first, left.second[1], leftCenter - Time::seconds(d));

            const bool movedRight = ids(mainSegments(right.first)).indexOf(right.second[1]) != 1;
            const bool movedLeft = ids(mainSegments(left.first)).indexOf(left.second[1]) != 1;
            QVERIFY2(movedRight == movedLeft, qPrintable(QStringLiteral("d = %1 s").arg(d)));
            QVERIFY2(movedRight == (d > 4), qPrintable(QStringLiteral("d = %1 s").arg(d)));
        }
    }

    // Reordenar passa vários vizinhos com a mesma regra nos dois sentidos
    void reorderAcrossSeveral()
    {
        auto right = mainProject({2, 2, 2, 2, 2});
        TE::reorderMain(right.first, right.second[0], Time::seconds(1 + 6.5));
        const auto &r = right.second;
        QCOMPARE(ids(mainSegments(right.first)), (QList<QUuid>{r[1], r[2], r[3], r[0], r[4]}));
        auto left = mainProject({2, 2, 2, 2, 2});
        TE::reorderMain(left.first, left.second[4], Time::seconds(9 - 6.5));
        const auto &l = left.second;
        QCOMPARE(ids(mainSegments(left.first)), (QList<QUuid>{l[0], l[4], l[1], l[2], l[3]}));
    }

    // Ímã ao mover: a borda mais perto vence, nos dois sentidos
    void snapMoveIsSymmetric()
    {
        const Micros length = Time::seconds(20);
        const Micros threshold = Time::seconds(0.1);
        const Micros duration = Time::seconds(2);
        const QList<Micros> points{Time::seconds(5), Time::seconds(7.03), Time::seconds(12), Time::seconds(14.5)};
        QList<Micros> mirrored;
        for (const Micros pt : points)
            mirrored.append(length - pt);
        for (int step = 0; step <= 1400; ++step) {
            const Micros start = Time::seconds(step * 0.01);
            const Micros right = TE::snapMove(start, duration, points, threshold, true);
            const Micros left = TE::snapMove(length - start - duration, duration, mirrored, threshold, false);
            QVERIFY2(right + duration == length - left,
                     qPrintable(QStringLiteral("início %1 s").arg(Time::toSeconds(start))));
        }
        // Início a 0,04 s de um ponto e fim a 0,01 s de outro: o fim vence.
        QCOMPARE(TE::snapMove(Time::seconds(5.04), duration, points, threshold, false), Time::seconds(5.03));
    }

    // Mover para cima de outro clipe manda para nova faixa
    void resolveOverlap()
    {
        Project p;
        const QUuid a = TE::addText(text(QStringLiteral("A")), p, 0);
        const QUuid b = TE::addText(text(QStringLiteral("B")), p, Time::seconds(5));
        TE::move(p, b, Time::seconds(1));
        TE::resolveOverlap(p, b);
        QVERIFY(p.locate(a)->track != p.locate(b)->track);
        QCOMPARE(p.segment(b)->targetStart, Time::seconds(1));
    }

    // Faixas vazias somem, a principal fica
    void removesEmptyTracks()
    {
        Project p;
        const QUuid t = TE::addText(text(QStringLiteral("A")), p, 0);
        QCOMPARE(p.tracks.size(), 2);
        TE::remove(p, t);
        QCOMPARE(p.tracks.size(), 1);
        QVERIFY(p.tracks[0].isMain);
    }

    // Duplicar insere logo depois
    void duplicate()
    {
        Project p;
        const QUuid a = TE::addMedia(video(2), p);
        const auto copy = TE::duplicate(p, a);
        QVERIFY(copy);
        QCOMPARE(ids(mainSegments(p)), (QList<QUuid>{a, *copy}));
        QCOMPARE(p.duration(), Time::seconds(4));

        // Fora da principal, a cópia vai logo depois do fim do original.
        const QUuid t = TE::addText(text(QStringLiteral("A")), p, Time::seconds(1));
        const auto tc = TE::duplicate(p, t);
        QVERIFY(tc);
        QCOMPARE(p.segment(*tc)->targetStart, Time::seconds(4));
        QCOMPARE(p.locate(*tc)->track, p.locate(t)->track);
    }

    // Soltar na faixa principal insere na junção mais próxima
    void dropOnMain()
    {
        Project p;
        const QUuid a = TE::addMedia(video(4), p);
        const QUuid b = TE::addMedia(video(4, QStringLiteral("b.mov")), p);
        const int main = *p.mainTrackIndex();
        const QUuid c = TE::insertMedia(video(2, QStringLiteral("c.mov")), p, Time::seconds(3), main);
        QCOMPARE(ids(mainSegments(p)), (QList<QUuid>{a, c, b}));
        QCOMPARE(p.segment(c)->targetStart, Time::seconds(4));
        // Fora das faixas, o visual também vai para a principal.
        const QUuid d = TE::insertMedia(video(1, QStringLiteral("d.mov")), p, 0, std::nullopt);
        QCOMPARE(mainSegments(p).first().id, d);
    }

    // Soltar sobre sobreposição ou texto cria sobreposição no tempo
    void dropAsOverlay()
    {
        Project p;
        TE::addMedia(video(10), p);
        TE::addText(text(QStringLiteral("A")), p, 0);
        int textTrack = -1;
        for (int t = 0; t < p.tracks.size(); ++t)
            if (p.tracks[t].kind == TrackKind::Text)
                textTrack = t;
        const QUuid o = TE::insertMedia(video(2, QStringLiteral("o.mov")), p, Time::seconds(5), textTrack);
        const auto loc = *p.locate(o);
        QVERIFY(p.tracks[loc.track].kind == TrackKind::Video && !p.tracks[loc.track].isMain);
        QCOMPARE(p.segment(o)->targetStart, Time::seconds(5));
        // Na mesma faixa de sobreposição, se houver espaço.
        const QUuid o2 = TE::insertMedia(video(2, QStringLiteral("o2.mov")), p, 0, loc.track);
        QCOMPARE(p.locate(o2)->track, loc.track);
        // Colidindo, vai para outra faixa.
        const QUuid o3 = TE::insertMedia(video(2, QStringLiteral("o3.mov")), p, Time::seconds(6), loc.track);
        QVERIFY(p.locate(o3)->track != loc.track);
    }

    // Soltar áudio fica em faixa de áudio
    void dropAudio()
    {
        Project p;
        TE::addMedia(video(10), p);
        const QUuid s = TE::insertMedia(audio(3), p, Time::seconds(2), p.mainTrackIndex());
        const auto loc = *p.locate(s);
        QCOMPARE(p.tracks[loc.track].kind, TrackKind::Audio);
        QCOMPARE(p.segment(s)->targetStart, Time::seconds(2));
        const QUuid s2 = TE::insertMedia(audio(3), p, Time::seconds(6), loc.track);
        QCOMPARE(p.locate(s2)->track, loc.track);
    }

    // Mover entre faixas só para o mesmo tipo de mídia
    void canMoveBetweenTracks()
    {
        Project p;
        const QUuid v = TE::addMedia(video(4), p);
        const QUuid t = TE::addText(text(QStringLiteral("A")), p, 0);
        const QUuid o = TE::addOverlay(video(2, QStringLiteral("o.mov")), p, 0);
        const int textTrack = p.locate(t)->track, overlay = p.locate(o)->track;
        QVERIFY(TE::canMove(p, v, overlay));
        QVERIFY(!TE::canMove(p, v, textTrack));
        QVERIFY(!TE::canMove(p, v, *p.mainTrackIndex()));
    }

    // Mover uma sobreposição para a principal entra pela posição do centro
    void moveToMainTrack()
    {
        Project p;
        const QUuid a = TE::addMedia(video(4), p);
        const QUuid b = TE::addMedia(video(4, QStringLiteral("b.mov")), p);
        const QUuid o = TE::addOverlay(video(2, QStringLiteral("o.mov")), p, Time::seconds(2.5));
        TE::moveToTrack(p, o, *p.mainTrackIndex());
        QCOMPARE(ids(mainSegments(p)), (QList<QUuid>{a, o, b}));
        QCOMPARE(p.tracks.size(), 1); // a faixa de sobreposição ficou vazia e sumiu
    }

    // Ímã puxa para o ponto mais próximo dentro do limite
    void snapping()
    {
        const QList<Micros> points{0, 1'000'000, 2'000'000};
        QCOMPARE(TE::snap(1'030'000, points, 50'000), 1'000'000);
        QCOMPARE(TE::snap(1'300'000, points, 50'000), 1'300'000);

        Project p;
        const QUuid a = TE::addMedia(video(2), p);
        TE::addMedia(video(3, QStringLiteral("b.mov")), p);
        QCOMPARE(TE::snapPoints(p, a, {Time::seconds(9)}),
                 (QList<Micros>{0, Time::seconds(9), Time::seconds(2), Time::seconds(5)}));
    }
};

QTEST_GUILESS_MAIN(TimelineTests)
#include "TimelineTests.moc"
