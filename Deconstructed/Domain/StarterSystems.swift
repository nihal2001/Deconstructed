import Foundation

/// The three standard systems. `Resources/StarterSystems.json` is the single source of truth:
/// the app reads it here and `scripts/generate_seed.py` turns it into the database seed.
enum StarterSystems {
    static let general = UUID(uuidString: "00000000-0000-4000-A000-000000000001")!
    static let fineDining = UUID(uuidString: "00000000-0000-4000-A000-000000000002")!
    static let fastCasual = UUID(uuidString: "00000000-0000-4000-A000-000000000003")!

    static let catalog: SystemCatalog = {
        guard let url = Bundle.main.url(forResource: "StarterSystems", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            assertionFailure("StarterSystems.json is missing or malformed")
            return SystemCatalog()
        }
        let published = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01
        var catalog = SystemCatalog()
        for entry in file.systems {
            catalog.systems.append(RankingSystem(
                id: entry.id, ownerID: nil, templateKey: entry.templateKey, forkedFromSystemID: nil,
                name: entry.name, summary: entry.summary, currentVersionID: entry.versionID,
                createdAt: published, updatedAt: published))
            catalog.versions.append(SystemVersion(
                id: entry.versionID, systemID: entry.id, number: 1,
                criteria: entry.criteria.map {
                    Criterion(id: $0.id, name: $0.name, guidance: $0.guidance, maxPoints: $0.maxPoints, levels: $0.levels)
                },
                publishedAt: published))
        }
        return catalog
    }()

    private struct File: Decodable {
        var systems: [Entry]
    }

    private struct Entry: Decodable {
        var id: UUID
        var versionID: UUID
        var templateKey: String
        var name: String
        var summary: String
        var criteria: [CriterionEntry]
    }

    private struct CriterionEntry: Decodable {
        var id: UUID
        var name: String
        var guidance: String
        var maxPoints: Int
        var levels: [ScoreLevel]
    }
}
