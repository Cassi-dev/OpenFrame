#include "ImageEffects.h"

#include "FilterModels.h"

#include <array>
#include <cmath>

namespace of::ImageEffects {

namespace {

// Pesos de luminância do Core Image (CIColorControls).
constexpr float lumR = 0.2125f, lumG = 0.7154f, lumB = 0.0721f;

struct RGB {
    float r, g, b;
};

using Matrix3 = std::array<std::array<double, 3>, 3>;

/// Aplica `fn` às cores sem pré-multiplicação de cada pixel, em paralelo.
template <typename Fn>
void forEachColor(LinearImage &img, Fn fn)
{
    parallelFor(img.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            Pixel *row = img.row(y);
            for (int x = 0; x < img.width(); ++x) {
                Pixel &p = row[x];
                if (p.a <= 0)
                    continue;
                const float inv = p.a >= 1 ? 1 : 1 / p.a;
                RGB c{p.r * inv, p.g * inv, p.b * inv};
                c = fn(c, x, y);
                p.r = c.r * p.a, p.g = c.g * p.a, p.b = c.b * p.a;
            }
        }
    });
}

RGB colorControls(RGB c, float saturation, float brightness, float contrast)
{
    const float l = c.r * lumR + c.g * lumG + c.b * lumB;
    c = {l + (c.r - l) * saturation, l + (c.g - l) * saturation, l + (c.b - l) * saturation};
    c = {c.r + brightness, c.g + brightness, c.b + brightness};
    return {(c.r - 0.5f) * contrast + 0.5f, (c.g - 0.5f) * contrast + 0.5f, (c.b - 0.5f) * contrast + 0.5f};
}

RGB apply(const Matrix3 &m, RGB c)
{
    return {float(m[0][0] * c.r + m[0][1] * c.g + m[0][2] * c.b),
            float(m[1][0] * c.r + m[1][1] * c.g + m[1][2] * c.b),
            float(m[2][0] * c.r + m[2][1] * c.g + m[2][2] * c.b)};
}

Matrix3 multiply(const Matrix3 &a, const Matrix3 &b)
{
    Matrix3 r{};
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j)
            for (int k = 0; k < 3; ++k)
                r[size_t(i)][size_t(j)] += a[size_t(i)][size_t(k)] * b[size_t(k)][size_t(j)];
    return r;
}

Matrix3 inverse(const Matrix3 &m)
{
    const double a = m[0][0], b = m[0][1], c = m[0][2], d = m[1][0], e = m[1][1], f = m[1][2], g = m[2][0],
                 h = m[2][1], i = m[2][2];
    const double det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    return {{{(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det},
             {(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det},
             {(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det}}};
}

// MARK: - Temperatura e tom (CITemperatureAndTint)

/// Ponto do lugar de Planck no diagrama uv (CIE 1960), aproximação de Krystek.
std::array<double, 2> planckUV(double t)
{
    const double u = (0.860117757 + 1.54118254e-4 * t + 1.28641212e-7 * t * t) /
                     (1 + 8.42420235e-4 * t + 7.08145163e-7 * t * t);
    const double v = (0.317398726 + 4.22806245e-5 * t + 4.20481691e-8 * t * t) /
                     (1 - 2.89741816e-5 * t + 1.61456053e-7 * t * t);
    return {u, v};
}

/// Branco (XYZ, Y = 1) da temperatura `t` deslocado por `tint` na normal ao lugar de Planck.
std::array<double, 3> whitePoint(double t, double tint)
{
    // Escala do tom ajustada às medições do Core Image.
    constexpr double tintScale = -1.0 / 3117.8;
    const auto p = planckUV(t), p0 = planckUV(t - 1), p1 = planckUV(t + 1);
    double nu = -(p1[1] - p0[1]), nv = p1[0] - p0[0];
    const double len = std::hypot(nu, nv);
    nu /= len, nv /= len;
    const double u = p[0] + nu * tint * tintScale, v = p[1] + nv * tint * tintScale;
    const double x = 3 * u / (2 * u - 8 * v + 4), y = 2 * v / (2 * u - 8 * v + 4);
    return {x / y, 1, (1 - x - y) / y};
}

/// Adaptação cromática de Bradford do branco de 6500 K para o branco alvo, em RGB linear.
Matrix3 temperatureMatrix(double temperature, double tint)
{
    static const Matrix3 rgbToXyz{{{0.4124564, 0.3575761, 0.1804375},
                                   {0.2126729, 0.7151522, 0.0721750},
                                   {0.0193339, 0.1191920, 0.9503041}}};
    static const Matrix3 bradford{{{0.8951, 0.2664, -0.1614}, {-0.7502, 1.7135, 0.0367}, {0.0389, -0.0685, 1.0296}}};
    const auto src = whitePoint(6500, 0), dst = whitePoint(temperature, tint);
    Matrix3 scale{};
    for (int i = 0; i < 3; ++i) {
        const double s = bradford[size_t(i)][0] * src[0] + bradford[size_t(i)][1] * src[1] + bradford[size_t(i)][2] * src[2];
        const double d = bradford[size_t(i)][0] * dst[0] + bradford[size_t(i)][1] * dst[1] + bradford[size_t(i)][2] * dst[2];
        scale[size_t(i)][size_t(i)] = d / s;
    }
    return multiply(inverse(rgbToXyz), multiply(inverse(bradford), multiply(scale, multiply(bradford, rgbToXyz))));
}

// MARK: - Curva de tons (CIToneCurve: spline cúbica natural, em sRGB)

struct ToneCurve {
    std::array<float, 1025> table{};

    ToneCurve(const std::array<double, 5> &ys)
    {
        constexpr std::array<double, 5> xs{0, 0.25, 0.5, 0.75, 1};
        // Spline natural: segundas derivadas nas pontas = 0.
        std::array<double, 5> m{};
        const double h = 0.25;
        // Sistema tridiagonal para m1..m3.
        std::array<double, 3> rhs{}, diag{4, 4, 4};
        for (int i = 1; i <= 3; ++i)
            rhs[size_t(i - 1)] = 6 / (h * h) * (ys[size_t(i + 1)] - 2 * ys[size_t(i)] + ys[size_t(i - 1)]);
        // Eliminação (coeficientes fora da diagonal = 1).
        for (int i = 1; i < 3; ++i) {
            const double w = 1 / diag[size_t(i - 1)];
            diag[size_t(i)] -= w;
            rhs[size_t(i)] -= w * rhs[size_t(i - 1)];
        }
        m[3] = rhs[2] / diag[2];
        m[2] = (rhs[1] - m[3]) / diag[1];
        m[1] = (rhs[0] - m[2]) / diag[0];
        for (size_t i = 0; i < table.size(); ++i) {
            const double x = double(i) / 1024;
            const int s = std::min(3, int(x / h));
            const double a = xs[size_t(s) + 1] - x, b = x - xs[size_t(s)];
            table[i] = float(m[size_t(s)] * a * a * a / (6 * h) + m[size_t(s) + 1] * b * b * b / (6 * h) +
                             (ys[size_t(s)] / h - m[size_t(s)] * h / 6) * a +
                             (ys[size_t(s) + 1] / h - m[size_t(s) + 1] * h / 6) * b);
        }
    }

    float operator()(float v) const
    {
        const float x = std::clamp(v, 0.0f, 1.0f) * 1024;
        const int i = std::min(int(x), 1023);
        return table[size_t(i)] + (table[size_t(i) + 1] - table[size_t(i)]) * (x - float(i));
    }
};

// MARK: - Matiz (CIHueAdjust: rotação com luminância constante, em luz linear)

Matrix3 hueMatrix(double angle)
{
    const double c = std::cos(angle), s = std::sin(angle);
    return {{{0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928},
             {0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283},
             {0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072}}};
}

// MARK: - Passos espaciais

/// Nitidez na luminância (CISharpenLuminance): máscara de nitidez.
void sharpen(LinearImage &img, double sharpness, double radius)
{
    LinearImage blurred = img;
    blurred.blur(radius);
    parallelFor(img.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            Pixel *row = img.row(y);
            const Pixel *soft = blurred.row(y);
            for (int x = 0; x < img.width(); ++x) {
                const float l = row[x].r * lumR + row[x].g * lumG + row[x].b * lumB;
                const float ls = soft[x].r * lumR + soft[x].g * lumG + soft[x].b * lumB;
                const float d = float(sharpness) * (l - ls);
                row[x].r += d * row[x].a, row[x].g += d * row[x].a, row[x].b += d * row[x].a;
            }
        }
    });
}

/// Vinheta (CIVignetteEffect com queda 0,6), em sRGB; forma medida no Core Image.
void vignette(LinearImage &img, double intensity)
{
    const double cx = img.width() / 2.0, cy = img.height() / 2.0;
    const double radius = std::max(img.width(), img.height()) * 0.55;
    forEachColor(img, [&](RGB c, int x, int y) {
        const double d = std::hypot(x + 0.5 - cx, y + 0.5 - cy) / radius;
        const double g = 1 - std::pow(std::cos(std::min(d * 1.0146, M_PI / 2)), 1.1611);
        const float f = float(1 - intensity * g);
        return RGB{toLinear(toSrgb(c.r) * f), toLinear(toSrgb(c.g) * f), toLinear(toSrgb(c.b) * f)};
    });
}

/// Ruído determinístico em 0…1 por pixel.
float noise(int x, int y)
{
    uint32_t h = uint32_t(x) * 374761393u + uint32_t(y) * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    return float((h ^ (h >> 16)) & 0xffffff) / float(0xffffff);
}

/// Granulado: ruído cinza semitransparente, deslocado a cada quadro.
void grain(LinearImage &img, double amount, double time)
{
    const double frame = std::round(time * 30);
    const int ox = int(std::fmod(frame * 137, 997)), oy = int(std::fmod(frame * 71, 991));
    const float alpha = float(amount * 0.25);
    parallelFor(img.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            Pixel *row = img.row(y);
            for (int x = 0; x < img.width(); ++x) {
                const float n = noise(x + ox, y + oy) * alpha;
                Pixel &p = row[x];
                const float k = 1 - alpha;
                p = {n + p.r * k, n + p.g * k, n + p.b * k, alpha + p.a * k};
            }
        }
    });
}

// MARK: - Filtros

RGB evaluate(const filtermodels::Model &model, RGB in)
{
    RGB x = in;
    if (!model.linearInput)
        x = {toSrgb(std::clamp(in.r, 0.0f, 1.0f)), toSrgb(std::clamp(in.g, 0.0f, 1.0f)), toSrgb(std::clamp(in.b, 0.0f, 1.0f))};
    else
        x = {std::clamp(in.r, 0.0f, 1.0f), std::clamp(in.g, 0.0f, 1.0f), std::clamp(in.b, 0.0f, 1.0f)};
    const float f[10] = {x.r, x.g, x.b, 1, x.r * x.r, x.g * x.g, x.b * x.b, x.r * x.g, x.r * x.b, x.g * x.b};
    const int terms = model.order >= 2 ? 10 : 4;
    float out[3];
    for (int c = 0; c < 3; ++c) {
        float y = 0;
        for (int i = 0; i < terms; ++i)
            y += model.m[c][i] * f[i];
        const float t = std::clamp(y, 0.0f, 1.0f) * 16;
        const int i = std::min(int(t), 15);
        out[c] = toLinear(model.curve[c][i] + (model.curve[c][i + 1] - model.curve[c][i]) * (t - float(i)));
    }
    return {out[0], out[1], out[2]};
}

/// Vibração (CIVibrance): satura mais as cores pouco saturadas. Forma ajustada às medições.
RGB vibrance(RGB c, float amount)
{
    const float mx = std::max({c.r, c.g, c.b}), mn = std::min({c.r, c.g, c.b});
    const float sat = mx > 1e-6f ? std::clamp((mx - mn) / mx, 0.0f, 1.0f) : 0;
    const float s = 1 + amount * 1.184f * std::pow(1 - sat, 0.75f);
    const float l = c.r * lumR + c.g * lumG + c.b * lumB;
    return {l + (c.r - l) * s, l + (c.g - l) * s, l + (c.b - l) * s};
}

void model(LinearImage &img, const filtermodels::Model &m)
{
    forEachColor(img, [&](RGB c, int, int) { return evaluate(m, c); });
}

/// Mistura `filtered` sobre `original` com peso `t` (CIDissolveTransition).
void mix(LinearImage &filtered, const LinearImage &original, float t)
{
    parallelFor(filtered.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            Pixel *f = filtered.row(y);
            const Pixel *o = original.row(y);
            for (int x = 0; x < filtered.width(); ++x)
                f[x] = {o[x].r + (f[x].r - o[x].r) * t, o[x].g + (f[x].g - o[x].g) * t, o[x].b + (f[x].b - o[x].b) * t,
                        o[x].a + (f[x].a - o[x].a) * t};
        }
    });
}

// MARK: - Efeitos espaciais

void pixelate(LinearImage &img, double scale)
{
    const LinearImage src = img;
    const int h = img.height();
    // Blocos alinhados ao canto inferior esquerdo (a origem do Core Image).
    parallelFor(h, [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            const double up = h - (y + 0.5);
            const double cy = h - (std::floor(up / scale) * scale + scale / 2);
            for (int x = 0; x < img.width(); ++x) {
                const double cx = std::floor((x + 0.5) / scale) * scale + scale / 2;
                img.at(x, y) = src.sample(float(cx), float(cy), true);
            }
        }
    });
}

void rgbSplit(LinearImage &img, double offset)
{
    // Cada canal mantém o alfa original; a soma satura o alfa em 1.
    const LinearImage src = img;
    parallelFor(img.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y)
            for (int x = 0; x < img.width(); ++x) {
                const Pixel red = src.sample(float(x + 0.5 - offset), float(y + 0.5), false);
                const Pixel green = src.at(x, y);
                const Pixel blue = src.sample(float(x + 0.5 + offset), float(y + 0.5), false);
                img.at(x, y) = {red.r, green.g, blue.b, std::min(1.0f, red.a + green.a + blue.a)};
            }
    });
}

void mirror(LinearImage &img)
{
    const int w = img.width();
    for (int y = 0; y < img.height(); ++y) {
        Pixel *row = img.row(y);
        for (int x = (w + 1) / 2; x < w; ++x)
            row[x] = row[w - 1 - x];
    }
}

void kaleidoscope(LinearImage &img, int count, double angle)
{
    const LinearImage src = img;
    const double cx = img.width() / 2.0, cy = img.height() / 2.0;
    const double wedge = 2 * M_PI / std::max(1, count);
    parallelFor(img.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y)
            for (int x = 0; x < img.width(); ++x) {
                // Coordenadas com y para cima, como no Core Image.
                const double dx = x + 0.5 - cx, dy = cy - (y + 0.5);
                const double r = std::hypot(dx, dy);
                double a = std::fmod(std::atan2(dy, dx) - angle, wedge);
                if (a < 0)
                    a += wedge;
                if (a > wedge / 2)
                    a = wedge - a;
                a += angle;
                img.at(x, y) = src.sample(float(cx + r * std::cos(a)), float(cy - r * std::sin(a)), true);
            }
    });
}

/// Magnitude do gradiente (Sobel) por canal.
LinearImage sobel(const LinearImage &src, float gain)
{
    LinearImage out(src.width(), src.height());
    const int w = src.width(), h = src.height();
    parallelFor(h, [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y)
            for (int x = 0; x < w; ++x) {
                const auto p = [&](int dx, int dy) -> const Pixel & {
                    return src.at(std::clamp(x + dx, 0, w - 1), std::clamp(y + dy, 0, h - 1));
                };
                const auto channel = [&](float Pixel::*c) {
                    const float gx = -(p(-1, -1).*c) - 2 * (p(-1, 0).*c) - (p(-1, 1).*c) + (p(1, -1).*c) +
                                     2 * (p(1, 0).*c) + (p(1, 1).*c);
                    const float gy = -(p(-1, -1).*c) - 2 * (p(0, -1).*c) - (p(1, -1).*c) + (p(-1, 1).*c) +
                                     2 * (p(0, 1).*c) + (p(1, 1).*c);
                    return std::sqrt(gx * gx + gy * gy) * gain;
                };
                out.at(x, y) = {channel(&Pixel::r), channel(&Pixel::g), channel(&Pixel::b), src.at(x, y).a};
            }
    });
    return out;
}

void edges(LinearImage &img, double v)
{
    const LinearImage lines = sobel(img, float(1 + v * 9) / 4);
    const float darken = float(-0.25 * v);
    parallelFor(img.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y)
            for (int x = 0; x < img.width(); ++x) {
                Pixel &p = img.at(x, y);
                const Pixel &e = lines.at(x, y);
                const auto screen = [&](float base, float edge) {
                    const float b = std::max(0.0f, base + darken * p.a);
                    const float t = std::clamp(edge, 0.0f, p.a);
                    return b + t - b * t / std::max(p.a, 1e-6f);
                };
                p = {screen(p.r, e.r), screen(p.g, e.g), screen(p.b, e.b), p.a};
            }
    });
}

/// Quadrinhos: cores em poucos níveis e traço preto nas bordas.
void comic(LinearImage &img, double k)
{
    LinearImage soft = img;
    soft.blur(1.0 * k);
    const LinearImage lines = sobel(soft, 1);
    forEachColor(img, [&](RGB c, int x, int y) {
        const auto posterize = [](float v) { return toLinear(std::round(toSrgb(std::clamp(v, 0.0f, 1.0f)) * 4) / 4); };
        const Pixel &e = lines.at(x, y);
        const float edge = e.r * lumR + e.g * lumG + e.b * lumB;
        const float ink = std::clamp((edge - 0.12f) * 6, 0.0f, 1.0f);
        return RGB{posterize(c.r) * (1 - ink), posterize(c.g) * (1 - ink), posterize(c.b) * (1 - ink)};
    });
}

} // namespace

// MARK: - Ajustar

void adjust(LinearImage &img, const Adjust &a, double k, double time)
{
    if (a.isIdentity() || img.isNull())
        return;
    const bool controls = a.brightness != 0 || a.contrast != 0 || a.saturation != 0;
    const float saturation = float(std::max(0.0, 1 + a.saturation));
    const float bright = float(a.brightness * 0.25);
    const float contrast = float(1 + a.contrast * 0.5);
    const float exposure = float(std::pow(2.0, a.exposure * 1.5));
    const bool temperature = a.temperature != 0 || a.tint != 0;
    // Ponto neutro alvo mais baixo (em Kelvin) deixa a imagem mais quente.
    const Matrix3 white = temperature ? temperatureMatrix(6500 - a.temperature * 2500, -a.tint * 60) : Matrix3{};
    const bool tones = a.highlights != 0 || a.shadows != 0;
    const ToneCurve curve({0, 0.25 + a.shadows * 0.12, 0.5 + (a.shadows + a.highlights) * 0.03,
                           0.75 + a.highlights * 0.12, 1});
    const Matrix3 hue = hueMatrix(a.hue * M_PI);
    const float fadeScale = float(1 - a.fade * 0.3), fadeBias = float(a.fade * 0.15);

    forEachColor(img, [&](RGB c, int, int) {
        if (controls)
            c = colorControls(c, saturation, bright, contrast);
        if (a.exposure != 0)
            c = {c.r * exposure, c.g * exposure, c.b * exposure};
        if (temperature)
            c = apply(white, c);
        if (tones)
            c = {toLinear(curve(toSrgb(c.r))), toLinear(curve(toSrgb(c.g))), toLinear(curve(toSrgb(c.b)))};
        if (a.hue != 0)
            c = apply(hue, c);
        if (a.fade > 0)
            c = {c.r * fadeScale + fadeBias, c.g * fadeScale + fadeBias, c.b * fadeScale + fadeBias};
        return c;
    });
    if (a.sharpen > 0)
        sharpen(img, a.sharpen * 1.5, 1.5 * k);
    if (a.vignette > 0)
        vignette(img, a.vignette);
    if (a.grain > 0)
        grain(img, a.grain, time);
}

// MARK: - Filtros

void filter(LinearImage &img, const FilterSetting &setting)
{
    if (setting.preset == FilterPreset::None || setting.intensity <= 0 || img.isNull())
        return;
    const LinearImage original = setting.intensity < 1 ? img : LinearImage();
    switch (setting.preset) {
    case FilterPreset::None: return;
    case FilterPreset::Mono: model(img, filtermodels::mono); break;
    case FilterPreset::Noir: model(img, filtermodels::noir); break;
    case FilterPreset::Chrome: model(img, filtermodels::chrome); break;
    case FilterPreset::Fade: model(img, filtermodels::fade); break;
    case FilterPreset::Instant: model(img, filtermodels::instant); break;
    case FilterPreset::Process: model(img, filtermodels::process); break;
    case FilterPreset::Tonal: model(img, filtermodels::tonal); break;
    case FilterPreset::Transfer: model(img, filtermodels::transfer); break;
    case FilterPreset::Sepia: model(img, filtermodels::sepia); break;
    case FilterPreset::Vivid:
        forEachColor(img, [](RGB c, int, int) { return vibrance(colorControls(c, 1.35f, 0, 1.08f), 0.4f); });
        break;
    case FilterPreset::Warm: {
        Adjust a;
        a.temperature = 0.6;
        a.saturation = 0.1;
        adjust(img, a, 1, 0);
        break;
    }
    case FilterPreset::Cool: {
        Adjust a;
        a.temperature = -0.6;
        a.tint = 0.1;
        adjust(img, a, 1, 0);
        break;
    }
    case FilterPreset::Cinematic:
        // Sombras puxadas para o azul-esverdeado, tons de pele para o laranja.
        forEachColor(img, [](RGB c, int, int) {
            const RGB m{1.08f * c.r - 0.02f, c.g + 0.04f * c.b, 0.08f * c.g + 0.92f * c.b + 0.04f};
            return colorControls(m, 0.9f, 0, 1.12f);
        });
        break;
    case FilterPreset::Vintage: {
        const LinearImage before = img;
        model(img, filtermodels::sepia);
        mix(img, before, 0.45f);
        Adjust a;
        a.fade = 0.5;
        a.vignette = 0.6;
        adjust(img, a, 1, 0);
        break;
    }
    }
    if (setting.intensity < 1)
        mix(img, original, float(setting.intensity));
}

// MARK: - Efeitos

void effects(LinearImage &img, const QList<VideoEffect> &list, double k, double time)
{
    for (const VideoEffect &effect : list) {
        if (img.isNull())
            return;
        const double v = effect.intensity;
        switch (effect.kind) {
        case VideoEffectKind::Blur: img.blur(v * 25 * k); break;
        case VideoEffectKind::Pixelate: pixelate(img, std::max(2.0, v * 48 * k)); break;
        case VideoEffectKind::RgbSplit: {
            const double jitter = 0.6 + 0.4 * std::sin(time * 23) * std::sin(time * 7);
            rgbSplit(img, v * 18 * k * jitter);
            break;
        }
        case VideoEffectKind::Mirror: mirror(img); break;
        case VideoEffectKind::Flash: {
            const double phase = std::fmod(time * (1 + v * 3), 1.0);
            const float strength = float(std::max(0.0, 1 - phase * 4) * 0.85);
            if (strength > 0)
                forEachColor(img, [&](RGB c, int, int) { return RGB{c.r + strength, c.g + strength, c.b + strength}; });
            break;
        }
        case VideoEffectKind::Kaleidoscope: kaleidoscope(img, int(3 + v * 9), time * 0.3); break;
        case VideoEffectKind::Comic: comic(img, k); break;
        case VideoEffectKind::Edges: edges(img, v); break;
        case VideoEffectKind::Shake:
        case VideoEffectKind::ZoomPulse: break; // geométricos: ver `geometry`
        }
    }
}

Geometry geometry(const QList<VideoEffect> &list, double time)
{
    Geometry g;
    for (const VideoEffect &effect : list) {
        const double v = effect.intensity;
        switch (effect.kind) {
        case VideoEffectKind::Shake:
            g.dx += (std::sin(time * 41) + std::sin(time * 67) * 0.5) * v * 0.025;
            g.dy += (std::cos(time * 53) + std::sin(time * 29) * 0.5) * v * 0.025;
            g.scale *= 1 + v * 0.06; // evita bordas pretas durante o tremor
            break;
        case VideoEffectKind::ZoomPulse: g.scale *= 1 + v * 0.12 * (0.5 + 0.5 * std::sin(time * 2 * M_PI * 2)); break;
        default: break;
        }
    }
    return g;
}

void brightness(LinearImage &img, double amount)
{
    const float b = float(amount);
    forEachColor(img, [&](RGB c, int, int) { return RGB{c.r + b, c.g + b, c.b + b}; });
}

} // namespace of::ImageEffects
