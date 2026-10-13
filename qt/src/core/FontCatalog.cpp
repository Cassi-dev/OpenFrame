#include "FontCatalog.h"

#include <QCollator>
#include <QFontDatabase>
#include <QSet>
#include <algorithm>

namespace of::FontCatalog {

QStringList families()
{
    QStringList names;
    for (const QString &family : QFontDatabase::families())
        if (!family.startsWith(u'.') && !QFontDatabase::isPrivateFamily(family))
            names.append(family);
    // Como o `localizedStandardCompare` do Swift: sem diferenciar maiúsculas, números pelo valor.
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::stable_sort(names.begin(), names.end(), collator);
    names.removeDuplicates();
    return names;
}

QStringList faces(const QString &family)
{
    struct Face {
        QString name;
        int weight;
        bool italic;
    };
    QList<Face> faces;
    QSet<QString> seen;
    for (const QString &style : QFontDatabase::styles(family)) {
        if (seen.contains(style))
            continue;
        seen.insert(style);
        faces.append({style, QFontDatabase::weight(family, style), QFontDatabase::italic(family, style)});
    }
    std::stable_sort(faces.begin(), faces.end(), [](const Face &a, const Face &b) {
        return std::pair(a.italic ? 1 : 0, a.weight) < std::pair(b.italic ? 1 : 0, b.weight);
    });
    QStringList names;
    for (const auto &f : faces)
        names.append(f.name);
    return names;
}

} // namespace of::FontCatalog
