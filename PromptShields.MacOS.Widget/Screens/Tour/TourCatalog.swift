import Foundation
import os

/// Loads `Resources/Tours.json` at first access and indexes by tour id.
/// v2 swaps this for a dashboard-fetched catalogue; the lookup API stays
/// the same so the engine doesn't change.
enum TourCatalog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "TourCatalog"
    )

    nonisolated(unsafe) private static var cached: [String: Tour]?

    static func tour(id: String) -> Tour? {
        load()[id]
    }

    static func allTours() -> [Tour] {
        Array(load().values).sorted { $0.id < $1.id }
    }

    static func tours(triggeredBy trigger: TourTrigger) -> [Tour] {
        load().values.filter { $0.trigger == trigger }
    }

    // MARK: - Loader

    private static func load() -> [String: Tour] {
        if let cached { return cached }
        guard let url = Bundle.main.url(forResource: "Tours", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            logger.error("Tours.json missing from bundle — guided tours disabled")
            cached = [:]
            return [:]
        }
        do {
            let payload = try JSONDecoder().decode(TourCatalogPayload.self, from: data)
            let map = Dictionary(uniqueKeysWithValues: payload.tours.map { ($0.id, $0) })
            cached = map
            logger.debug("Loaded \(map.count) tours")
            return map
        } catch {
            logger.error("Tours.json decode failed: \(error.localizedDescription)")
            cached = [:]
            return [:]
        }
    }
}
