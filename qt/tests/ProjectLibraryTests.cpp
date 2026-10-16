// Porte da suíte "Biblioteca de projetos" (ProjectLibraryTests.swift).
#include "ProjectLibrary.h"
#include "ProjectStore.h"
#include "TestSupport.h"

#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>

using namespace of;

class ProjectLibraryTests : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;
    std::unique_ptr<ProjectLibrary> m_library;

    ProjectLibrary &library() { return *m_library; }

private slots:
    // Cada teste começa com uma biblioteca vazia, apagando de vez (sem Lixeira).
    void init()
    {
        const QString root = m_dir.filePath(QUuid::createUuid().toString(QUuid::WithoutBraces));
        m_library = std::make_unique<ProjectLibrary>(root, false);
    }

    // Criar dá nomes em sequência e grava o formato
    void createNames()
    {
        const auto a = library().create(AspectRatio::R9x16);
        const auto b = library().create();
        QVERIFY(a && b);
        QCOMPARE(a->entry.name, QStringLiteral("Projeto 1"));
        QCOMPARE(b->entry.name, QStringLiteral("Projeto 2"));
        QCOMPARE(a->entry.aspect, AspectRatio::R9x16);
        QCOMPARE(library().load(a->entry.id)->canvas.aspect, AspectRatio::R9x16);
        QSet<QUuid> listed;
        for (const auto &e : library().list())
            listed.insert(e.id);
        QCOMPARE(listed, (QSet<QUuid>{a->entry.id, b->entry.id}));
        // Mesmo layout do Swift: <raiz>/<UUID maiúsculo>/project.openframe.
        QVERIFY(QFile::exists(library().root() + u'/' + ProjectStore::uuidString(a->entry.id) + u"/project.openframe"));
        QCOMPARE(a->entry.projectPath(), library().folder(a->entry.id) + u"/project.openframe");
    }

    // Lista do mais recente ao mais antigo
    void sortedByModification()
    {
        const ProjectEntry old = library().create()->entry;
        const ProjectEntry recent = library().create()->entry;
        // O QFileInfo dá a data em milissegundos: o "recente" fica um minuto no
        // passado para não empatar com a gravação logo abaixo.
        const auto age = [](const QString &path, int seconds) {
            QFile file(path);
            return file.open(QIODevice::ReadWrite) &&
                   file.setFileTime(QDateTime::currentDateTime().addSecs(-seconds), QFileDevice::FileModificationTime);
        };
        QVERIFY(age(old.projectPath(), 3600));
        QVERIFY(age(recent.projectPath(), 60));
        auto list = library().list();
        QCOMPARE(list.size(), 2);
        QCOMPARE(list[0].id, recent.id);
        QCOMPARE(list[1].id, old.id);
        // Gravar de novo o antigo o traz para o topo.
        QVERIFY(library().save(*library().load(old.id), old.id));
        QCOMPARE(library().list().first().id, old.id);
    }

    // Salvar e abrir preservam o projeto
    void saveLoad()
    {
        auto created = library().create();
        QVERIFY(created);
        created->project.materials.append(test::photo(10, 10, QStringLiteral("x.png")));
        QVERIFY(library().save(created->project, created->entry.id));
        QVERIFY(*library().load(created->entry.id) == created->project);
    }

    // Renomear, duplicar e apagar
    void renameDuplicateDelete()
    {
        const ProjectEntry entry = library().create()->entry;
        QVERIFY(library().rename(entry.id, QStringLiteral("  Viagem  ")));
        QCOMPARE(library().entry(entry.id)->name, QStringLiteral("Viagem"));
        QVERIFY(library().rename(entry.id, QStringLiteral("   ")));
        QCOMPARE(library().entry(entry.id)->name, QStringLiteral("Viagem"));
        QVERIFY(!library().entry(entry.id)->thumbnailModified);

        QVERIFY(library().writeThumbnail(QByteArray("\x01\x02\x03", 3), entry.id));
        const auto copy = library().duplicate(entry.id);
        QVERIFY(copy);
        QCOMPARE(copy->name, QStringLiteral("Viagem (cópia)"));
        QVERIFY(copy->thumbnailModified);
        QCOMPARE(library().duplicate(entry.id)->name, QStringLiteral("Viagem (cópia 2)"));

        QVERIFY(library().remove(entry.id));
        QVERIFY(!library().entry(entry.id));
        QCOMPARE(library().list().size(), 2);
    }

    // Importar um .openframe de fora uma vez só
    void importOnce()
    {
        Project outside;
        outside.name = QStringLiteral("Sem título");
        const QString path = m_dir.filePath(QStringLiteral("Clipe da praia.openframe"));
        QVERIFY(ProjectStore::save(outside, path));

        const auto first = library().importProject(path);
        QVERIFY(first);
        QCOMPARE(first->name, QStringLiteral("Clipe da praia"));
        const auto again = library().importProject(path);
        QVERIFY(again);
        QCOMPARE(again->id, first->id);
        QCOMPARE(library().list().size(), 1);
        // A cópia de um importado não herda a origem: importar de novo continua abrindo o primeiro.
        library().duplicate(first->id);
        QCOMPARE(library().importProject(path)->id, first->id);
        QVERIFY(!library().importProject(m_dir.filePath(QStringLiteral("não existe.openframe"))));
    }

    // Pastas estranhas são ignoradas
    void ignoresJunk()
    {
        QVERIFY(library().create());
        QVERIFY(QDir().mkpath(library().root() + QStringLiteral("/lixo")));
        QVERIFY(QDir().mkpath(library().folder(QUuid::createUuid())));
        QCOMPARE(library().list().size(), 1);
    }

    // "Projeto N" continua do maior número usado
    void nextNameSkipsGaps()
    {
        const auto a = library().create();
        library().rename(a->entry.id, QStringLiteral("Projeto 7"));
        const auto b = library().create();
        library().rename(b->entry.id, QStringLiteral("Projeto x"));
        QCOMPARE(library().nextName(), QStringLiteral("Projeto 8"));
    }

    // A raiz padrão fica na pasta de vídeos do usuário
    void defaultRoot()
    {
#if defined(OPENFRAME_ANDROID)
        QCOMPARE(ProjectLibrary::defaultRoot(),
                 QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + u"/Projetos");
#else
        QCOMPARE(ProjectLibrary::defaultRoot(),
                 QStandardPaths::writableLocation(QStandardPaths::MoviesLocation) + u"/OpenFrame/Projetos");
#endif
    }
};

QTEST_GUILESS_MAIN(ProjectLibraryTests)
#include "ProjectLibraryTests.moc"
