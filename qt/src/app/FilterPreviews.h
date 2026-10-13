#pragma once

#include <QQuickImageProvider>

namespace of {

/// `image://filters/<material>/<filtro>`: a primeira miniatura do material com
/// o filtro aplicado, para os cartões da aba Filtros.
class FilterPreviews : public QQuickImageProvider
{
public:
    FilterPreviews();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};

} // namespace of
