// Catálogo de fontes (equivalente ao FontCatalog Swift, sobre o QFontDatabase).
#include "FontCatalog.h"

#include <QFontDatabase>
#include <QRegularExpression>
#include <QTest>

using namespace of;

class FontCatalogTests : public QObject
{
    Q_OBJECT

private slots:
    void familiesAreSortedAndVisible()
    {
        const QStringList families = FontCatalog::families();
        QVERIFY(!families.isEmpty());
        for (const QString &f : families)
            QVERIFY2(!f.startsWith(u'.'), qPrintable(f));
        QCOMPARE(QStringList(families).removeDuplicates(), 0);
        for (qsizetype i = 1; i < families.size(); ++i)
            QVERIFY2(families[i - 1].compare(families[i], Qt::CaseInsensitive) <= 0 ||
                         families[i - 1].contains(QRegularExpression(QStringLiteral("\\d"))),
                     qPrintable(families[i - 1] + u" > " + families[i]));
    }

    void facesFromThinToBold()
    {
        // Uma família com vários pesos e itálicos, se houver.
        for (const QString &family : FontCatalog::families()) {
            const QStringList faces = FontCatalog::faces(family);
            if (faces.size() < 3)
                continue;
            int lastWeight = -1;
            bool seenItalic = false;
            for (const QString &face : faces) {
                const bool italic = QFontDatabase::italic(family, face);
                const int weight = QFontDatabase::weight(family, face);
                QVERIFY2(!seenItalic || italic, qPrintable(family + u'/' + face));
                if (italic && !seenItalic)
                    lastWeight = -1;
                seenItalic = seenItalic || italic;
                QVERIFY2(weight >= lastWeight, qPrintable(family + u'/' + face));
                lastWeight = weight;
            }
            return;
        }
        QSKIP("nenhuma família com três estilos instalada");
    }

    void unknownFamilyHasNoFaces() { QVERIFY(FontCatalog::faces(QStringLiteral("Família Que Não Existe 123")).isEmpty()); }
};

QTEST_MAIN(FontCatalogTests)
#include "FontCatalogTests.moc"
