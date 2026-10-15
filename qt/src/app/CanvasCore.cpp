#include "CanvasCore.h"

#include "TimelineEditor.h"

#include <algorithm>
#include <cmath>

namespace of::CanvasCore {

#ifdef OF_HAS_CANVAS_LAYOUT

QList<ElementBox> boxes(const Project &project, Micros time)
{
    return CanvasLayout::boxes(project, time);
}

std::array<QPointF, 4> corners(const ElementBox &box, double aspect)
{
    const auto pts = CanvasLayout::corners(box, aspect);
    return {pts[0], pts[1], pts[2], pts[3]};
}

std::optional<QUuid> hitTest(QPointF point, const QList<ElementBox> &boxes, double aspect)
{
    return CanvasLayout::hitTest(point, boxes, aspect);
}

SnappedMove snapMove(const ElementBox &box, QPointF proposed, const QList<ElementBox> &others, double aspect,
                     QSizeF threshold)
{
    const auto snapped = Snapping::snapMove(box, proposed, others, aspect, threshold);
    return {snapped.center, snapped.guides};
}

double snapRotation(double degrees)
{
    return Snapping::snapRotation(degrees).degrees;
}

void setPlacement(Project &p, const QUuid &id, QPointF center, double scale, double rotation)
{
    TimelineEditor::setPlacement(p, id, center, scale, rotation);
}

void setTextWidth(Project &p, const QUuid &id, double maxWidth)
{
    TimelineEditor::setTextWidth(p, id, maxWidth);
}

bool isInAutoCaptions(const Project &p, const QUuid &id)
{
    const auto loc = p.locate(id);
    return loc && p.tracks[loc->track].isAutoCaptions;
}

#else

// MARK: - Provisório (sai com a etapa 1 do núcleo)

QList<ElementBox> boxes(const Project &project, Micros time)
{
    // Caixas falsas, só para desenhar e testar o gesto: mídia 16:9 no canvas
    // inteiro e texto numa faixa fixa. O núcleo mede de verdade.
    QList<ElementBox> result;
    for (const TrackKind kind : {TrackKind::Video, TrackKind::Text})
        for (const Track &track : project.tracks) {
            if (track.kind != kind || track.hidden)
                continue;
            for (const Segment &seg : track.segments) {
                if (!seg.targetRange().contains(time))
                    continue;
                if (seg.text) {
                    const TextStyle &s = seg.text->style;
                    result.append({seg.id, true, QPointF(s.x, s.y), QSizeF(std::min(s.maxWidth, 0.6) * 2, 0.16),
                                   s.scale, s.rotation});
                } else if (const Material *m = project.material(seg.materialId); m && m->isVisual()) {
                    const Transform &t = seg.transform;
                    result.append({seg.id, false, QPointF(t.x, t.y), QSizeF(2, 2), t.scale, t.rotation});
                }
            }
        }
    return result;
}

std::array<QPointF, 4> corners(const ElementBox &box, double aspect)
{
    const double halfW = box.size.width() * box.scale * aspect / 2, halfH = box.size.height() * box.scale / 2;
    const double a = -box.rotation * M_PI / 180;
    std::array<QPointF, 4> out;
    const std::array<QPointF, 4> local{QPointF(-halfW, halfH), QPointF(halfW, halfH), QPointF(halfW, -halfH),
                                       QPointF(-halfW, -halfH)};
    for (size_t i = 0; i < 4; ++i)
        out[i] = box.center + QPointF((local[i].x() * std::cos(a) - local[i].y() * std::sin(a)) / aspect,
                                      local[i].x() * std::sin(a) + local[i].y() * std::cos(a));
    return out;
}

std::optional<QUuid> hitTest(QPointF point, const QList<ElementBox> &boxes, double aspect)
{
    for (auto it = boxes.crbegin(); it != boxes.crend(); ++it) {
        const auto c = corners(*it, aspect);
        bool inside = true;
        for (size_t i = 0; i < 4 && inside; ++i) {
            const QPointF a = c[i], b = c[(i + 1) % 4];
            inside = (b.x() - a.x()) * (point.y() - a.y()) - (b.y() - a.y()) * (point.x() - a.x()) <= 0;
        }
        if (inside)
            return it->id;
    }
    return std::nullopt;
}

SnappedMove snapMove(const ElementBox &, QPointF proposed, const QList<ElementBox> &, double, QSizeF)
{
    return {proposed, {}};
}

double snapRotation(double degrees)
{
    return degrees;
}

void setPlacement(Project &p, const QUuid &id, QPointF center, double scale, double rotation)
{
    TimelineEditor::update(p, id, [&](Segment &s) {
        if (s.text) {
            s.text->style.x = center.x();
            s.text->style.y = center.y();
            s.text->style.scale = scale;
            s.text->style.rotation = rotation;
        } else {
            s.transform.x = center.x();
            s.transform.y = center.y();
            s.transform.scale = scale;
            s.transform.rotation = rotation;
        }
    });
}

void setTextWidth(Project &p, const QUuid &id, double maxWidth)
{
    TimelineEditor::update(p, id, [&](Segment &s) {
        if (s.text)
            s.text->style.maxWidth = std::clamp(maxWidth, minTextWidth, maxTextWidth);
    });
}

bool isInAutoCaptions(const Project &, const QUuid &)
{
    return false;
}

#endif

} // namespace of::CanvasCore
