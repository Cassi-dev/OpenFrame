#include "KeyedListModel.h"

#include <QSet>

namespace of {

namespace {
QString idOf(const QVariantMap &item) { return item.value(QStringLiteral("id")).toString(); }
} // namespace

KeyedListModel::KeyedListModel(const QList<QByteArray> &roles, QObject *parent)
    : QAbstractListModel(parent), m_roles(roles)
{
    if (!m_roles.contains("id"))
        m_roles.prepend("id");
}

int KeyedListModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant KeyedListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const int r = role - Qt::UserRole;
    if (r < 0 || r >= m_roles.size())
        return {};
    return m_items[index.row()].value(QString::fromLatin1(m_roles[r]));
}

QHash<int, QByteArray> KeyedListModel::roleNames() const
{
    QHash<int, QByteArray> names;
    // "id" não pode ser nome de propriedade no QML: o papel aparece como "uid".
    for (int i = 0; i < m_roles.size(); ++i)
        names.insert(Qt::UserRole + i, m_roles[i] == "id" ? QByteArray("uid") : m_roles[i]);
    return names;
}

QVariantMap KeyedListModel::get(int row) const
{
    return row >= 0 && row < m_items.size() ? m_items[row] : QVariantMap{};
}

int KeyedListModel::indexOf(const QString &id) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (idOf(m_items[i]) == id)
            return i;
    return -1;
}

void KeyedListModel::setItems(const QList<QVariantMap> &items)
{
    const int oldCount = int(m_items.size());

    // 1. Remove o que saiu (de trás para frente, para os índices não mudarem).
    QSet<QString> wanted;
    for (const auto &item : items)
        wanted.insert(idOf(item));
    for (int i = int(m_items.size()) - 1; i >= 0; --i) {
        if (!wanted.contains(idOf(m_items[i]))) {
            beginRemoveRows({}, i, i);
            m_items.removeAt(i);
            endRemoveRows();
        }
    }

    // 2. Na ordem nova: atualiza no lugar, move ou insere.
    for (int i = 0; i < items.size(); ++i) {
        const QString id = idOf(items[i]);
        if (i < m_items.size() && idOf(m_items[i]) == id) {
            if (m_items[i] != items[i]) {
                QList<int> changed;
                for (int r = 0; r < m_roles.size(); ++r) {
                    const QString key = QString::fromLatin1(m_roles[r]);
                    if (m_items[i].value(key) != items[i].value(key))
                        changed.append(Qt::UserRole + r);
                }
                m_items[i] = items[i];
                emit dataChanged(index(i), index(i), changed);
            }
            continue;
        }
        int found = -1;
        for (int j = i + 1; j < m_items.size(); ++j) {
            if (idOf(m_items[j]) == id) {
                found = j;
                break;
            }
        }
        if (found >= 0) {
            beginMoveRows({}, found, found, {}, i);
            m_items.move(found, i);
            endMoveRows();
            if (m_items[i] != items[i]) {
                m_items[i] = items[i];
                emit dataChanged(index(i), index(i));
            }
        } else {
            beginInsertRows({}, i, i);
            m_items.insert(i, items[i]);
            endInsertRows();
        }
    }

    if (oldCount != m_items.size())
        emit countChanged();
}

} // namespace of
