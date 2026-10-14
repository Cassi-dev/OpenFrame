#include "Motion.h"

#include <cmath>

namespace of {

namespace {

/// `progress` vai de 0 (invisível) a 1 (posição final).
void apply(AnimationKind kind, double p, bool exiting, AnimationState &st)
{
    const double hidden = 1 - p;
    // Na saída, "deslizar ←" continua indo para a esquerda.
    const double direction = exiting ? -1 : 1;
    switch (kind) {
    case AnimationKind::Fade: st.alpha *= p; break;
    case AnimationKind::ZoomIn:
        st.scale *= 0.5 + 0.5 * p;
        st.alpha *= p;
        break;
    case AnimationKind::ZoomOut:
        st.scale *= 1.5 - 0.5 * p;
        st.alpha *= p;
        break;
    case AnimationKind::SlideLeft: st.dx += hidden * 1.2 * direction; break;
    case AnimationKind::SlideRight: st.dx -= hidden * 1.2 * direction; break;
    case AnimationKind::SlideUp: st.dy -= hidden * 1.2 * direction; break;
    case AnimationKind::SlideDown: st.dy += hidden * 1.2 * direction; break;
    case AnimationKind::Spin:
        st.rotation += hidden * 360;
        st.scale *= std::max(p, 0.001);
        break;
    case AnimationKind::Typewriter: st.reveal = std::min(st.reveal, p); break;
    }
}

/// Mistura linear (o CIDissolveTransition), em luz linear e pré-multiplicada.
LinearImage dissolve(const LinearImage &a, const LinearImage &b, double t)
{
    LinearImage out(a.width(), a.height());
    const float u = float(std::clamp(t, 0.0, 1.0)), v = 1 - u;
    parallelFor(out.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            const Pixel *pa = a.row(y), *pb = b.row(y);
            Pixel *po = out.row(y);
            for (int x = 0; x < out.width(); ++x)
                po[x] = {pa[x].r * v + pb[x].r * u, pa[x].g * v + pb[x].g * u, pa[x].b * v + pb[x].b * u,
                         pa[x].a * v + pb[x].a * u};
        }
    });
    return out;
}

LinearImage over(const LinearImage &top, const LinearImage &bottom)
{
    LinearImage out = bottom;
    out.drawAt(top, 0, 0);
    return out;
}

} // namespace

AnimationState Animations::state(const Segment &seg, Micros local)
{
    AnimationState st;
    const Micros duration = seg.targetDuration();
    if (seg.animationIn && seg.animationIn->duration > 0 && local < seg.animationIn->duration)
        apply(seg.animationIn->kind, ease(double(local) / double(seg.animationIn->duration)), false, st);
    if (seg.animationOut && seg.animationOut->duration > 0 && local > duration - seg.animationOut->duration)
        apply(seg.animationOut->kind, ease(double(duration - local) / double(seg.animationOut->duration)), true, st);
    return st;
}

double Animations::ease(double p)
{
    const double x = std::clamp(p, 0.0, 1.0);
    return 1 - std::pow(1 - x, 3);
}

LinearImage Transitions::apply(TransitionKind kind, const LinearImage &a, const LinearImage &b, double raw, double k)
{
    const double p = std::clamp(raw, 0.0, 1.0);
    const int w = a.width(), h = a.height();
    switch (kind) {
    case TransitionKind::Dissolve: return dissolve(a, b, p);
    case TransitionKind::FadeBlack:
    case TransitionKind::FadeWhite: {
        const float c = kind == TransitionKind::FadeBlack ? 0 : 1;
        const LinearImage color(w, h, Pixel{c, c, c, 1});
        return p < 0.5 ? dissolve(over(a, color), color, p * 2) : dissolve(color, over(b, color), p * 2 - 1);
    }
    case TransitionKind::WipeLeft:
    case TransitionKind::WipeRight: {
        // A nova imagem aparece numa faixa que cresce da direita (←) ou da esquerda (→).
        LinearImage out = a;
        const int cut = int(std::lround(w * p));
        const int from = kind == TransitionKind::WipeLeft ? w - cut : 0;
        LinearImage strip(cut, h);
        for (int y = 0; y < h; ++y)
            std::copy(b.row(y) + from, b.row(y) + from + cut, strip.row(y));
        out.drawAt(strip, from, 0);
        return out;
    }
    case TransitionKind::SlideLeft:
    case TransitionKind::SlideRight: {
        const double eased = Animations::ease(p);
        const double dir = kind == TransitionKind::SlideLeft ? 1 : -1;
        LinearImage out(w, h);
        out.drawAt(a, int(std::lround(-dir * w * eased)), 0);
        out.drawAt(b, int(std::lround(dir * w * (1 - eased))), 0);
        return out;
    }
    case TransitionKind::Zoom: {
        const double s = 1 + 0.6 * p;
        LinearImage zoomed(w, h);
        QTransform t;
        t.translate(w / 2.0, h / 2.0);
        t.scale(s, s);
        t.translate(-w / 2.0, -h / 2.0);
        zoomed.draw(a, t);
        return dissolve(zoomed, b, p);
    }
    case TransitionKind::Blur: {
        LinearImage mixed = dissolve(a, b, p);
        const double sigma = std::sin(p * M_PI) * 22 * k;
        if (sigma > 0.5)
            mixed.blur(sigma);
        return mixed;
    }
    }
    return dissolve(a, b, p);
}

} // namespace of
