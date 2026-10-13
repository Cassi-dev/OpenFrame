import Foundation

/// Salva e abre projetos `.opencut` (JSON legível, no espírito do
/// `draft_content.json` do CapCut).
public enum ProjectStore {
    public static let fileExtension = "opencut"

    public static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    public static func decode(_ data: Data) throws -> Project {
        try JSONDecoder().decode(Project.self, from: data)
    }

    public static func save(_ project: Project, to url: URL) throws {
        try encode(project).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> Project {
        try decode(Data(contentsOf: url))
    }
}
