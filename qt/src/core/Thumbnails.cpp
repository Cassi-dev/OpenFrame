#include "Thumbnails.h"

#include "MediaProbe.h"
#include "VideoDecoder.h"

namespace of::Thumbnails {

QList<QImage> frames(const Material &m, int count, int maxSide)
{
    QList<QImage> images;
    if (m.kind == MaterialKind::Photo) {
        const QImage image = Images::load(m.path, maxSide);
        if (!image.isNull())
            images.append(image);
        return images;
    }
    if (m.kind != MaterialKind::Video || count <= 0)
        return images;
    const auto decoder = VideoDecoder::open(m.path);
    if (!decoder)
        return images;
    const Micros duration = m.duration > 0 ? m.duration : decoder->duration();
    for (int i = 0; i < count; ++i) {
        const Micros t = Time::round((i + 0.5) / count * double(duration));
        const QImage image = decoder->frameAt(t, QSize(maxSide, maxSide));
        if (!image.isNull())
            images.append(image);
    }
    return images;
}

} // namespace of::Thumbnails
