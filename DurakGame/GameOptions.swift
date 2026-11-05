import Foundation

/// Local vs-bot game setup, persisted between launches (mirrors Android's
/// `GameOpts` / `Store.loadOpts`/`saveOpts`).
struct DurakGameOptions: Codable, Equatable {
    var variant: DurakVariant = .podkidnoy
    var players: Int = 3
    var botLevel: Int = 2 // 1 easy, 2 medium, 3 hard
    var throwAll: Bool = true // true = anyone may throw in; false = neighbors-only

    private static let key = "durak.localGameOptions.v1"

    static func load() -> DurakGameOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let opts = try? JSONDecoder().decode(DurakGameOptions.self, from: data) else {
            return DurakGameOptions()
        }
        return opts
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
