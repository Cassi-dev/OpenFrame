import Foundation
import Testing
@testable import OpenFrameCore

@Suite("Biblioteca de projetos")
struct ProjectLibraryTests {
    let library = ProjectLibrary(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("OpenFrameLibrary-\(UUID().uuidString)", isDirectory: true),
                                 usesTrash: false)

    @Test("Criar dá nomes em sequência e grava o formato")
    func createNames() throws {
        let a = try library.create(aspect: .r9x16)
        let b = try library.create()
        #expect(a.entry.name == "Projeto 1")
        #expect(b.entry.name == "Projeto 2")
        #expect(a.entry.aspect == .r9x16)
        #expect(try library.load(a.entry.id).canvas.aspect == .r9x16)
        #expect(Set(library.list().map(\.id)) == [a.entry.id, b.entry.id])
    }

    @Test("Lista do mais recente ao mais antigo")
    func sortedByModification() throws {
        let old = try library.create().entry
        let new = try library.create().entry
        let past = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.projectURL.path)
        #expect(library.list().map(\.id) == [new.id, old.id])
        // Gravar de novo o antigo o traz para o topo.
        try library.save(try library.load(old.id), id: old.id)
        #expect(library.list().first?.id == old.id)
    }

    @Test("Salvar e abrir preservam o projeto")
    func saveLoad() throws {
        var (entry, project) = try library.create()
        project.materials.append(Material(kind: .photo, path: "/tmp/x.png", name: "x.png", duration: 0,
                                          width: 10, height: 10, hasAudio: false))
        try library.save(project, id: entry.id)
        #expect(try library.load(entry.id) == project)
    }

    @Test("Renomear, duplicar e apagar")
    func renameDuplicateDelete() throws {
        let entry = try library.create().entry
        try library.rename(entry.id, to: "  Viagem  ")
        #expect(library.entry(entry.id)?.name == "Viagem")
        try library.rename(entry.id, to: "   ")
        #expect(library.entry(entry.id)?.name == "Viagem")

        try library.writeThumbnail(Data([1, 2, 3]), id: entry.id)
        let copy = try library.duplicate(entry.id)
        #expect(copy.name == "Viagem (cópia)")
        #expect(copy.thumbnailModified != nil)
        #expect(try library.duplicate(entry.id).name == "Viagem (cópia 2)")

        try library.delete(entry.id)
        #expect(library.entry(entry.id) == nil)
        #expect(library.list().count == 2)
    }

    @Test("Importar um .openframe de fora uma vez só")
    func importOnce() throws {
        var outside = Project()
        outside.name = "Sem título"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Clipe da praia.openframe")
        try ProjectStore.save(outside, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try library.importProject(from: url)
        #expect(first.name == "Clipe da praia")
        let again = try library.importProject(from: url)
        #expect(again.id == first.id)
        #expect(library.list().count == 1)
    }

    @Test("Pastas estranhas são ignoradas")
    func ignoresJunk() throws {
        try library.create()
        try FileManager.default.createDirectory(at: library.root.appendingPathComponent("lixo"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.root.appendingPathComponent(UUID().uuidString),
                                                withIntermediateDirectories: true)
        #expect(library.list().count == 1)
    }
}
