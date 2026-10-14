// Catálogo de fontes (equivalente ao FontCatalog Swift, sobre o QFontDatabase).
#include "FontCatalog.h"

#include <QFontDatabase>
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
            QVERIFY2(FontCatalog::naturalCompare(families[i - 1], families[i]) <= 0,
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

    void naturalOrder_data()
    {
        QTest::addColumn<QString>("a");
        QTest::addColumn<QString>("b");
        QTest::addColumn<int>("expected");
        QTest::newRow("número pelo valor") << QStringLiteral("Font 2") << QStringLiteral("Font 10") << -1;
        QTest::newRow("sem diferenciar maiúsculas") << QStringLiteral("arial") << QStringLiteral("Arial") << 0;
        QTest::newRow("maiúscula não vem antes") << QStringLiteral("a") << QStringLiteral("B") << -1;
        QTest::newRow("letra a letra") << QStringLiteral("Abc") << QStringLiteral("abd") << -1;
        QTest::newRow("x9 < x10") << QStringLiteral("x9") << QStringLiteral("x10") << -1;
        QTest::newRow("x10 < x10a") << QStringLiteral("x10") << QStringLiteral("x10a") << -1;
        QTest::newRow("zeros à esquerda") << QStringLiteral("v007") << QStringLiteral("v7") << 0;
        QTest::newRow("número longo") << QStringLiteral("n99999999999999999999") << QStringLiteral("n100000000000000000000") << -1;
        QTest::newRow("vazio primeiro") << QString() << QStringLiteral("a") << -1;
        QTest::newRow("prefixo primeiro") << QStringLiteral("Noto") << QStringLiteral("Noto Sans") << -1;
        QTest::newRow("acentos") << QStringLiteral("Élan") << QStringLiteral("élan") << 0;
        QTest::newRow("número antes de letra") << QStringLiteral("Font 9") << QStringLiteral("Font A") << -1;
    }

    void naturalOrder()
    {
        QFETCH(QString, a);
        QFETCH(QString, b);
        QFETCH(int, expected);
        QCOMPARE(FontCatalog::naturalCompare(a, b), expected);
        QCOMPARE(FontCatalog::naturalCompare(b, a), -expected);
    }

    void naturalOrderIsStrictWeak()
    {
        // Antissimetria e transitividade (inclusive da equivalência) numa amostra
        // com números, maiúsculas, zeros à esquerda e as famílias instaladas.
        QStringList names{QStringLiteral("Font 2"), QStringLiteral("font 10"), QStringLiteral("Font 010"),
                          QStringLiteral("Font"),   QStringLiteral("FONT 2"),  QStringLiteral("Font A"),
                          QStringLiteral("x9y"),    QStringLiteral("x09Y"),    QStringLiteral(" lead"),
                          QStringLiteral("0"),      QStringLiteral("00"),      QStringLiteral("a0b"),
                          QStringLiteral("Ünïcode"), QString()};
        const QStringList installed = FontCatalog::families();
        names += installed.mid(0, 40);
        const auto sign = [](int v) { return (v > 0) - (v < 0); };
        for (const QString &a : names)
            for (const QString &b : names) {
                const int ab = FontCatalog::naturalCompare(a, b);
                QVERIFY2(sign(ab) == -sign(FontCatalog::naturalCompare(b, a)), qPrintable(a + u" / " + b));
                for (const QString &c : names) {
                    const int bc = FontCatalog::naturalCompare(b, c), ac = FontCatalog::naturalCompare(a, c);
                    if (ab < 0 && bc < 0)
                        QVERIFY2(ac < 0, qPrintable(a + u" < " + b + u" < " + c));
                    if (ab == 0 && bc == 0)
                        QVERIFY2(ac == 0, qPrintable(a + u" = " + b + u" = " + c));
                }
            }
    }

    void unknownFamilyHasNoFaces() { QVERIFY(FontCatalog::faces(QStringLiteral("Família Que Não Existe 123")).isEmpty()); }
};

QTEST_MAIN(FontCatalogTests)
#include "FontCatalogTests.moc"
