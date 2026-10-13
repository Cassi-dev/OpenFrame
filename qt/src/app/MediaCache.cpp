#include "MediaCache.h"

namespace of {

MediaCache *MediaCache::instance()
{
    static MediaCache cache;
    return &cache;
}

QList<QImage> MediaCache::thumbnails(const QString &id) const
{
    QMutexLocker lock(&m_mutex);
    return m_thumbnails.value(id);
}

QVector<float> MediaCache::peaks(const QString &id) const
{
    QMutexLocker lock(&m_mutex);
    return m_peaks.value(id);
}

bool MediaCache::hasThumbnails(const QString &id) const
{
    QMutexLocker lock(&m_mutex);
    return m_thumbnails.contains(id);
}

bool MediaCache::hasPeaks(const QString &id) const
{
    QMutexLocker lock(&m_mutex);
    return m_peaks.contains(id);
}

void MediaCache::setThumbnails(const QString &id, const QList<QImage> &images)
{
    {
        QMutexLocker lock(&m_mutex);
        m_thumbnails.insert(id, images);
    }
    emit changed(id);
}

void MediaCache::setPeaks(const QString &id, const QVector<float> &peaks)
{
    {
        QMutexLocker lock(&m_mutex);
        m_peaks.insert(id, peaks);
    }
    emit changed(id);
}

void MediaCache::remove(const QString &id)
{
    {
        QMutexLocker lock(&m_mutex);
        m_thumbnails.remove(id);
        m_peaks.remove(id);
    }
    emit changed(id);
}

void MediaCache::clear()
{
    QStringList ids;
    {
        QMutexLocker lock(&m_mutex);
        ids = m_thumbnails.keys() + m_peaks.keys();
        m_thumbnails.clear();
        m_peaks.clear();
    }
    for (const auto &id : ids)
        emit changed(id);
}

void MediaCache::setPreviewFrame(const QImage &frame)
{
    m_frame = frame;
    emit previewFrameChanged();
}

} // namespace of
