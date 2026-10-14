#pragma once

#include <QString>
#include <QtGlobal>
#include <cmath>

namespace of {

/// Tempo em microssegundos, a mesma unidade dos campos `start`/`duration` do
/// draft do CapCut e da versão Swift.
using Micros = qint64;

namespace Time {
inline constexpr Micros second = 1'000'000;

/// Arredonda como o `.rounded()` do Swift (metade para longe do zero).
inline Micros round(double v) { return Micros(std::llround(v)); }

inline Micros seconds(double s) { return round(s * 1'000'000); }

inline double toSeconds(Micros t) { return double(t) / 1'000'000; }

/// Formata como `mm:ss.cc` (ou `h:mm:ss.cc` acima de uma hora).
QString format(Micros t);
} // namespace Time

struct TimeRange {
    Micros start = 0;
    Micros duration = 0;

    Micros end() const { return start + duration; }
    bool contains(Micros t) const { return t >= start && t < end(); }
    bool operator==(const TimeRange &) const = default;
};

} // namespace of
