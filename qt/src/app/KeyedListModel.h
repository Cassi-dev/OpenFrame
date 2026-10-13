#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace of {

/// Lista para o QML em que cada item é um QVariantMap com a chave "id" (no
/// QML, o papel se chama "uid").
/// `setItems` compara com a lista anterior pelo id: itens que continuam são
/// atualizados no lugar (dataChanged) ou movidos, em vez de recriados. Assim os
/// delegates sobrevivem às alterações do projeto, inclusive no meio de um
/// arraste (o MouseArea do clipe arrastado não é destruído).
class KeyedListModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit KeyedListModel(const QList<QByteArray> &roles, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return int(m_items.size()); }
    const QList<QVariantMap> &items() const { return m_items; }
    void setItems(const QList<QVariantMap> &items);

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE int indexOf(const QString &id) const;

signals:
    void countChanged();

private:
    QList<QByteArray> m_roles;
    QList<QVariantMap> m_items;
};

} // namespace of
