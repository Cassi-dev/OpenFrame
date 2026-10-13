#include "FilterPreviews.h"

#include "CoreBridge.h"
#include "MediaCache.h"

namespace of {

FilterPreviews::FilterPreviews() : QQuickImageProvider(QQuickImageProvider::Image, ForceAsynchronousImageLoading) {}

QImage FilterPreviews::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QString material = id.section('/', 0, 0);
    const auto preset = enumFromKey<FilterPreset>(id.section('/', 1, 1)).value_or(FilterPreset::None);
    const QList<QImage> thumbnails = MediaCache::instance()->thumbnails(material);
    QImage image;
    if (!thumbnails.isEmpty()) {
        QImage base = thumbnails.first().scaled(160, 160, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        image = preset == FilterPreset::None ? base : Bridge::filterPreview(base, preset);
    }
    if (!image.isNull() && requestedSize.isValid())
        image = image.scaled(requestedSize, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    if (size)
        *size = image.size();
    return image;
}

} // namespace of
