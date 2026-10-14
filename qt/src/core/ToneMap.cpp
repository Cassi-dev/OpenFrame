#include "ToneMap.h"

#include "LinearImage.h"

#include <array>
#include <cmath>
#include <vector>

namespace of::ToneMap {

namespace {

constexpr double hlgGamma = 0.85;
/// Branco de referência (BT.2408) e pico suposto da fonte PQ, em nits.
constexpr double referenceWhite = 203;
constexpr double pqSourcePeak = 1000;

double hlgInverse(double e)
{
    constexpr double a = 0.17883277, b = 0.28466892, c = 0.55991073;
    return e <= 0.5 ? e * e / 3 : (std::exp((e - c) / a) + b) / 12;
}

constexpr double m1 = 2610.0 / 16384, m2 = 2523.0 / 4096 * 128;
constexpr double c1 = 3424.0 / 4096, c2 = 2413.0 / 4096 * 32, c3 = 2392.0 / 4096 * 32;

/// Sinal PQ (0…1) → nits.
double pqToNits(double e)
{
    const double p = std::pow(std::clamp(e, 0.0, 1.0), 1 / m2);
    return 10000 * std::pow(std::max(p - c1, 0.0) / (c2 - c3 * p), 1 / m1);
}

/// Nits → sinal PQ (0…1).
double nitsToPq(double nits)
{
    const double y = std::pow(std::max(nits, 0.0) / 10000, m1);
    return std::pow((c1 + c2 * y) / (1 + c3 * y), m2);
}

/// EETF do BT.2390: comprime de `pqSourcePeak` para `referenceWhite` com um
/// joelho (spline de Hermite) no domínio PQ; abaixo do joelho, identidade.
struct Eetf {
    double sourceMax = nitsToPq(pqSourcePeak);
    double maxLum = nitsToPq(referenceWhite) / sourceMax;
    double knee = 1.5 * maxLum - 0.5;
    double kneeNits = pqToNits(knee * sourceMax);

    double operator()(double nits) const
    {
        if (nits <= kneeNits)
            return nits;
        const double e = std::min(nitsToPq(nits) / sourceMax, 1.0);
        const double t = (e - knee) / (1 - knee), t2 = t * t, t3 = t2 * t;
        const double mapped = (2 * t3 - 3 * t2 + 1) * knee + (t3 - 2 * t2 + t) * (1 - knee) + (-2 * t3 + 3 * t2) * maxLum;
        return pqToNits(mapped * sourceMax);
    }
};

/// Sinal de 16 bits → luz linear (HLG: 1 = pico; PQ: 1 = branco de referência).
const std::vector<float> &signalTable(Transfer transfer)
{
    static const auto build = [](Transfer t) {
        std::vector<float> table(65536);
        for (int i = 0; i < 65536; ++i) {
            const double e = i / 65535.0;
            table[size_t(i)] = float(t == Transfer::Hlg ? hlgInverse(e) : pqToNits(e) / referenceWhite);
        }
        return table;
    };
    static const std::vector<float> hlg = build(Transfer::Hlg), pq = build(Transfer::Pq);
    return transfer == Transfer::Hlg ? hlg : pq;
}

/// Luz linear 0…1 → sRGB 8 bits (tabela fina o bastante para o começo da curva).
const std::array<uint8_t, 16385> &srgbTable()
{
    static const std::array<uint8_t, 16385> table = [] {
        std::array<uint8_t, 16385> t{};
        for (size_t i = 0; i < t.size(); ++i) {
            const double x = double(i) / 16384;
            const double v = x <= 0.0031308 ? 12.92 * x : 1.055 * std::pow(x, 1 / 2.4) - 0.055;
            t[i] = uint8_t(std::lround(std::clamp(v, 0.0, 1.0) * 255));
        }
        return t;
    }();
    return table;
}

/// Primárias BT.2020 → BT.709 em luz linear.
constexpr float toRec709[3][3] = {{1.660491f, -0.587641f, -0.072850f},
                                  {-0.124550f, 1.132900f, -0.008349f},
                                  {-0.018151f, -0.100579f, 1.118730f}};

} // namespace

QImage toSdr(const QImage &rgb2020, Transfer transfer)
{
    if (transfer == Transfer::Sdr)
        return rgb2020.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    const QImage src = rgb2020.convertToFormat(QImage::Format_RGBA64);
    QImage out(src.size(), QImage::Format_ARGB32_Premultiplied);
    const std::vector<float> &signal = signalTable(transfer);
    const auto &srgb = srgbTable();
    static const Eetf eetf;
    const auto encode = [&](float v) { return int(srgb[size_t(std::lround(std::clamp(v, 0.0f, 1.0f) * 16384))]); };
    parallelFor(src.height(), [&](int y0, int y1) {
        for (int y = y0; y < y1; ++y) {
            const auto *in = reinterpret_cast<const quint16 *>(src.constScanLine(y));
            auto *dst = reinterpret_cast<QRgb *>(out.scanLine(y));
            for (int x = 0; x < src.width(); ++x) {
                float c[3] = {signal[in[x * 4]], signal[in[x * 4 + 1]], signal[in[x * 4 + 2]]};
                float gain;
                if (transfer == Transfer::Hlg) {
                    const float m = std::max({c[0], c[1], c[2]});
                    gain = m > 0 ? float(std::pow(double(m), hlgGamma - 1)) : 0;
                } else {
                    const double lum = 0.2627 * c[0] + 0.6780 * c[1] + 0.0593 * c[2];
                    gain = lum > 0 ? float(eetf(lum * referenceWhite) / referenceWhite / lum) : 0;
                }
                float o[3];
                for (int i = 0; i < 3; ++i)
                    o[i] = gain * (toRec709[i][0] * c[0] + toRec709[i][1] * c[1] + toRec709[i][2] * c[2]);
                dst[x] = qRgb(encode(o[0]), encode(o[1]), encode(o[2]));
            }
        }
    });
    return out;
}

} // namespace of::ToneMap
