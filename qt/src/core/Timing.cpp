#include "Timing.h"

namespace of::Time {

QString format(Micros t)
{
    const double total = std::max(0.0, double(t) / 1'000'000);
    const int whole = int(total);
    const int hours = whole / 3600;
    const int minutes = (whole % 3600) / 60;
    const int secs = whole % 60;
    const int centis = int((total - std::floor(total)) * 100);
    if (hours > 0)
        return QString::asprintf("%d:%02d:%02d.%02d", hours, minutes, secs, centis);
    return QString::asprintf("%02d:%02d.%02d", minutes, secs, centis);
}

} // namespace of::Time
