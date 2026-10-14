#include "PaintedItems.h"

#include "MediaCache.h"

#include <QFont>
#include <QPainter>
#include <QPainterPath>
#include <cmath>

namespace of {

namespace {

/// Retângulo com um raio por canto (sentido horário a partir do canto superior esquerdo).
QPainterPath roundedRect(const QRectF &r, qreal tl, qreal tr, qreal br, qreal bl)
{
    QPainterPath p;
    p.moveTo(r.left() + tl, r.top());
    p.lineTo(r.right() - tr, r.top());
    p.arcTo(QRectF(r.right() - 2 * tr, r.top(), 2 * tr, 2 * tr), 90, -90);
    p.lineTo(r.right(), r.bottom() - br);
    p.arcTo(QRectF(r.right() - 2 * br, r.bottom() - 2 * br, 2 * br, 2 * br), 0, -90);
    p.lineTo(r.left() + bl, r.bottom());
    p.arcTo(QRectF(r.left(), r.bottom() - 2 * bl, 2 * bl, 2 * bl), 270, -90);
    p.lineTo(r.left(), r.top() + tl);
    p.arcTo(QRectF(r.left(), r.top(), 2 * tl, 2 * tl), 180, -90);
    p.closeSubpath();
    return p;
}

QFont interFont(qreal pixelSize, QFont::Weight weight, bool mono)
{
    QFont font(QStringLiteral("Inter"));
    font.setPixelSize(int(std::round(pixelSize)));
    font.setWeight(weight);
    if (mono)
        font.setFeature(QFont::Tag("tnum"), 1);
    return font;
}

void connectCache(QQuickPaintedItem *item, const QString *materialId)
{
    QObject::connect(MediaCache::instance(), &MediaCache::changed, item, [item, materialId](const QString &id) {
        if (id == *materialId)
            item->update();
    });
}

} // namespace

// MARK: - LogoMark

LogoMark::LogoMark(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &LogoMark::colorsChanged, this, [this] { update(); });
}

void LogoMark::paint(QPainter *painter)
{
    const qreal side = std::min(width(), height());
    if (side <= 0)
        return;
    const bool small = side <= 32;
    // Lado externo, vão central, folga entre as peças e raios (fora/dentro).
    const qreal outerSide = small ? 220 : 204, hole = small ? 56 : 60, gap = small ? 22 : 12;
    const qreal outer = 30, inner = small ? 6 : 8;
    const qreal a = outerSide / 2, b = hole / 2, g = gap / 2;
    // Topo (o quadro aceso), direita, base e esquerda: (x0, y0, x1, y1).
    const qreal boxes[4][4] = {{-a, -a, b, -b}, {b, -a, a, b}, {-b, b, a, a}, {-a, -b, -b, a}};

    painter->setRenderHint(QPainter::Antialiasing);
    painter->translate((width() - side) / 2, (height() - side) / 2);
    painter->scale(side / 256, side / 256);
    painter->setPen(Qt::NoPen);
    for (int i = 0; i < 4; ++i) {
        const auto &box = boxes[i];
        const QRectF r(128 + box[0] + g, 128 + box[1] + g, box[2] - box[0] - gap, box[3] - box[1] - gap);
        // O canto de fora de cada peça é mais redondo: 0 = sup. esq., 1 = sup. dir., 2 = inf. dir., 3 = inf. esq.
        auto radius = [&](int corner) { return corner == i ? outer : inner; };
        painter->setBrush(i == 0 ? m_litColor : m_frameColor);
        painter->drawPath(roundedRect(r, radius(0), radius(1), radius(2), radius(3)));
    }
}

// MARK: - NeedleHead

NeedleHead::NeedleHead(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &NeedleHead::changed, this, [this] { update(); });
}

void NeedleHead::paint(QPainter *painter)
{
    const QRectF r = QRectF(0, 0, width(), height()).adjusted(m_glow, m_glow, -m_glow, 0);
    if (r.width() <= 0 || r.height() <= m_taper)
        return;
    const qreal body = r.height() - m_taper;
    const qreal radius = std::min<qreal>(5, body / 2);
    const qreal mid = r.center().x();
    QPainterPath p;
    p.moveTo(r.left() + radius, r.top());
    p.lineTo(r.right() - radius, r.top());
    p.arcTo(QRectF(r.right() - 2 * radius, r.top(), 2 * radius, 2 * radius), 90, -90);
    p.lineTo(r.right(), r.top() + body - radius);
    p.arcTo(QRectF(r.right() - 2 * radius, r.top() + body - 2 * radius, 2 * radius, 2 * radius), 0, -90);
    p.lineTo(mid + m_line / 2 + m_taper, r.top() + body);
    p.lineTo(mid + m_line / 2, r.bottom());
    p.lineTo(mid - m_line / 2, r.bottom());
    p.lineTo(mid - m_line / 2 - m_taper, r.top() + body);
    p.lineTo(r.left() + radius, r.top() + body);
    p.arcTo(QRectF(r.left(), r.top() + body - 2 * radius, 2 * radius, 2 * radius), 270, -90);
    p.lineTo(r.left(), r.top() + radius);
    p.arcTo(QRectF(r.left(), r.top(), 2 * radius, 2 * radius), 180, -90);
    p.closeSubpath();

    painter->setRenderHint(QPainter::Antialiasing);
    // Brilho: contornos cada vez mais largos e transparentes (sombra de raio ~6).
    for (int k = int(m_glow); k >= 1; --k) {
        QColor c = m_color;
        c.setAlphaF(0.05f);
        painter->setPen(QPen(c, 2.0 * k, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        painter->setBrush(Qt::NoBrush);
        painter->drawPath(p);
    }
    painter->setPen(Qt::NoPen);
    painter->setBrush(m_color);
    painter->drawPath(p);
}

// MARK: - DashedRect

DashedRect::DashedRect(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &DashedRect::changed, this, [this] { update(); });
}

void DashedRect::paint(QPainter *painter)
{
    const qreal half = m_lineWidth / 2;
    const QRectF r = QRectF(0, 0, width(), height()).adjusted(half, half, -half, -half);
    painter->setRenderHint(QPainter::Antialiasing);
    QPen pen(m_color, m_lineWidth);
    pen.setDashPattern({m_dash / m_lineWidth, m_gap / m_lineWidth});
    painter->setPen(pen);
    painter->setBrush(m_fill);
    painter->drawRoundedRect(r, m_radius, m_radius);
}

// MARK: - Régua

TimelineRuler::TimelineRuler(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &TimelineRuler::changed, this, [this] { update(); });
}

double TimelineRuler::majorStep(double zoom)
{
    static const double steps[] = {0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 14400};
    for (double s : steps)
        if (s * zoom >= 110)
            return s;
    return 14400;
}

QString TimelineRuler::label(double t, double step)
{
    if (t >= 3600) {
        const int s = int(t);
        return QString::asprintf("%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60);
    }
    const int minutes = int(t) / 60;
    const double seconds = t - minutes * 60;
    return step < 1 ? QString::asprintf("%02d:%04.1f", minutes, seconds)
                    : QString::asprintf("%02d:%02d", minutes, int(seconds));
}

void TimelineRuler::paint(QPainter *painter)
{
    const qreal w = width(), h = height();
    painter->setRenderHint(QPainter::Antialiasing);
    // Pílula do comprimento do conteúdo (o início e o fim são arredondados).
    const qreal pillH = h - 8;
    const QRectF pill(-m_offset, 4, std::max(m_contentWidth, w + m_offset), pillH);
    painter->setPen(Qt::NoPen);
    painter->setBrush(QColor::fromRgbF(0.082f, 0.082f, 0.082f));
    painter->drawRoundedRect(pill, pillH / 2, pillH / 2);

    if (m_zoom <= 0)
        return;
    const double major = majorStep(m_zoom);
    const double minor = major / 4;
    const double minorPx = minor * m_zoom;
    painter->setFont(interFont(10, QFont::Normal, true));
    const QColor labelColor = QColor::fromRgbF(1, 1, 1, 0.36f);
    const QColor tickColor = QColor::fromRgbF(1, 1, 1, 0.18f);
    const QFontMetricsF fm(painter->font());
    long long i = std::max<long long>(0, (long long)std::floor((m_offset - 80) / minorPx));
    for (; i * minorPx - m_offset <= w + 80; ++i) {
        const double t = std::round(double(i) * minor * 1000) / 1000;
        const qreal x = t * m_zoom - m_offset;
        if (i % 4 == 0) {
            const QString text = label(t, major);
            const qreal tw = fm.horizontalAdvance(text);
            const qreal tx = i == 0 ? x + 12 : x - tw / 2;
            painter->setPen(labelColor);
            painter->drawText(QRectF(tx, 0, tw + 2, h), Qt::AlignLeft | Qt::AlignVCenter, text);
        } else {
            painter->setPen(Qt::NoPen);
            painter->setBrush(tickColor);
            painter->drawRect(QRectF(x - 0.5, h / 2 - 2.5, 1, 5));
        }
    }
}

// MARK: - Forma de onda

WaveformView::WaveformView(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &WaveformView::changed, this, [this] { update(); });
    connect(MediaCache::instance(), &MediaCache::changed, this, [this](const QString &id) {
        if (id == m_materialId) {
            update();
            emit peaksChanged();
        }
    });
    connect(this, &WaveformView::changed, this, &WaveformView::peaksChanged);
}

bool WaveformView::hasPeaks() const
{
    return !MediaCache::instance()->peaks(m_materialId).isEmpty();
}

void WaveformView::paint(QPainter *painter)
{
    const QVector<float> peaks = MediaCache::instance()->peaks(m_materialId);
    const qreal full = m_fullWidth > 0 ? m_fullWidth : width();
    if (peaks.isEmpty() || m_to <= m_from || full <= 0)
        return;
    const qreal stride = m_bar + m_gap;
    const int count = std::max(1, int(full / stride));
    const double pps = MediaCache::peaksPerSecond;
    const int n = int(peaks.size());
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);
    painter->setBrush(m_color);
    const int first = std::max(0, int(std::floor(m_offset / stride)) - 1);
    for (int i = first; i < count; ++i) {
        const qreal x = i * stride - m_offset;
        if (x > width())
            break;
        const double t0 = m_from + (m_to - m_from) * double(i) / count;
        const double t1 = m_from + (m_to - m_from) * double(i + 1) / count;
        const int a = std::min(n - 1, std::max(0, int(t0 * pps)));
        const int b = std::min(n, std::max(a + 1, int(t1 * pps)));
        float value = 0;
        for (int k = a; k < b; ++k)
            value = std::max(value, peaks[k]);
        const qreal barH = std::max<qreal>(1.5, value * height());
        painter->drawRoundedRect(QRectF(x, (height() - barH) / 2, m_bar, barH), m_bar / 2, m_bar / 2);
    }
}

// MARK: - Miniaturas do clipe

ThumbnailStrip::ThumbnailStrip(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &ThumbnailStrip::changed, this, [this] { update(); });
    connectCache(this, &m_materialId);
}

void ThumbnailStrip::paint(QPainter *painter)
{
    const QList<QImage> images = MediaCache::instance()->thumbnails(m_materialId);
    const qreal full = m_fullWidth > 0 ? m_fullWidth : width();
    if (images.isEmpty() || full <= 0 || height() <= 0)
        return;
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->setClipPath(roundedRect(QRectF(-m_offset, 0, full, height()), m_radius, m_radius, m_radius, m_radius));
    const qreal tile = std::max<qreal>(20, height() * (m_aspect > 0 ? m_aspect : 16.0 / 9));
    qreal x = std::floor(m_offset / tile) * tile;
    for (; x < full && x - m_offset < width(); x += tile) {
        int index = 0;
        if (m_video && m_materialDuration > 0) {
            const double fraction = (x + tile / 2) / std::max<qreal>(full, 1);
            const double sourceTime = m_sourceStart + fraction * m_sourceDuration;
            index = std::min(int(images.size()) - 1,
                             std::max(0, int(sourceTime / m_materialDuration * double(images.size()))));
        }
        painter->drawImage(QRectF(x - m_offset, 0, tile, height()), images[index]);
    }
}

// MARK: - Miniatura do material

MaterialThumb::MaterialThumb(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &MaterialThumb::changed, this, [this] {
        update();
        emit imagesChanged();
    });
    connect(MediaCache::instance(), &MediaCache::changed, this, [this](const QString &id) {
        if (id == m_materialId) {
            update();
            emit imagesChanged();
        }
    });
}

bool MaterialThumb::available() const
{
    return !MediaCache::instance()->thumbnails(m_materialId).isEmpty();
}

void MaterialThumb::paint(QPainter *painter)
{
    const QList<QImage> images = MediaCache::instance()->thumbnails(m_materialId);
    if (images.isEmpty())
        return;
    const QImage &image = images.first();
    const QRectF bounds(0, 0, width(), height());
    // Preenche cortando (aspect fill), centrado.
    const qreal scale = std::max(bounds.width() / image.width(), bounds.height() / image.height());
    const QSizeF size(image.width() * scale, image.height() * scale);
    const QRectF target((bounds.width() - size.width()) / 2, (bounds.height() - size.height()) / 2, size.width(),
                        size.height());
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->setClipPath(roundedRect(bounds, 9, 9, 9, 9));
    painter->drawImage(target, image);
}

// MARK: - Preview

PreviewFrame::PreviewFrame(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &PreviewFrame::changed, this, [this] { update(); });
    connect(MediaCache::instance(), &MediaCache::previewFrameChanged, this, [this] {
        update();
        emit frameChanged();
    });
}

bool PreviewFrame::hasFrame() const
{
    return !MediaCache::instance()->previewFrame().isNull();
}

void PreviewFrame::paint(QPainter *painter)
{
    const QRectF bounds(0, 0, width(), height());
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    const QPainterPath clip = roundedRect(bounds, m_radius, m_radius, m_radius, m_radius);
    painter->setClipPath(clip);
    painter->fillRect(bounds, Qt::black);
    const QImage frame = MediaCache::instance()->previewFrame();
    if (frame.isNull())
        return;
    const qreal scale = std::min(bounds.width() / frame.width(), bounds.height() / frame.height());
    const QSizeF size(frame.width() * scale, frame.height() * scale);
    painter->drawImage(QRectF((bounds.width() - size.width()) / 2, (bounds.height() - size.height()) / 2,
                              size.width(), size.height()),
                       frame);
}

} // namespace of
