import SwiftUI

/// Local results vs. the bots, persisted in UserDefaults. `LocalGameEngine` records each finished
/// game once: a win when the player is not the "durak", a loss when they are, a draw when the last
/// cards ran out at the same time.
struct DurakStats: Codable {
    struct Row: Codable { var played = 0, won = 0, lost = 0, draws = 0 }
    var total = Row()
    var byVariant: [String: Row] = [:]
    var byPlayers: [Int: Row] = [:]

    private static let key = "durak.stats.v1"

    static func load() -> DurakStats {
        guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(DurakStats.self, from: d) else { return DurakStats() }
        return s
    }

    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) } }

    static func record(variant: DurakVariant, players: Int, result: Int) { // 1 win, 0 draw, -1 loss
        var s = load()
        func bump(_ r: inout Row) {
            r.played += 1
            if result > 0 { r.won += 1 } else if result < 0 { r.lost += 1 } else { r.draws += 1 }
        }
        bump(&s.total)
        var v = s.byVariant[variant.rawValue] ?? Row(); bump(&v); s.byVariant[variant.rawValue] = v
        var p = s.byPlayers[players] ?? Row(); bump(&p); s.byPlayers[players] = p
        s.save()
    }

    static func reset() { DurakStats().save() }
}

struct DurakStatsView: View {
    @ObservedObject private var lang = AppLang.shared
    @State private var stats = DurakStats.load()
    @State private var confirmReset = false

    private let felt = Color(red: 0.08, green: 0.20, blue: 0.14)
    private let burgundy = Color(red: 0.45, green: 0.10, blue: 0.14)
    private let gold = Color(red: 0.85, green: 0.68, blue: 0.30)
    private let cream = Color(red: 0.96, green: 0.93, blue: 0.85)

    var body: some View {
        ZStack {
            felt.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 10) {
                        tile(t("Played", "Сыграно"), "\(stats.total.played)")
                        tile(t("Won", "Побед"), "\(stats.total.won)")
                        tile(t("Win rate", "Процент"), stats.total.played == 0 ? "—" : "\(stats.total.won * 100 / stats.total.played)%")
                    }
                    HStack(spacing: 10) {
                        tile(t("Lost (durak)", "Проигрышей"), "\(stats.total.lost)")
                        tile(t("Draws", "Ничьих"), "\(stats.total.draws)")
                    }
                    section(t("By variant", "По вариантам"), [
                        (t("Throw-in", "Подкидной"), stats.byVariant[DurakVariant.podkidnoy.rawValue] ?? .init()),
                        (t("Transfer", "Переводной"), stats.byVariant[DurakVariant.perevodnoy.rawValue] ?? .init()),
                    ])
                    section(t("By number of players", "По числу игроков"), (2...6).map { n in
                        (t("\(n) players", n < 5 ? "\(n) игрока" : "\(n) игроков"), stats.byPlayers[n] ?? .init())
                    })
                    Button(role: .destructive) { confirmReset = true } label: {
                        Text(t("Reset statistics", "Сбросить статистику")).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .foregroundStyle(cream)
                    .background(RoundedRectangle(cornerRadius: 12).fill(burgundy.opacity(0.7)))
                }
                .padding(20)
            }
        }
        .navigationTitle(t("Statistics", "Статистика"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { stats = DurakStats.load() }
        .alert(t("Reset statistics?", "Сбросить статистику?"), isPresented: $confirmReset) {
            Button(t("Reset", "Сбросить"), role: .destructive) { DurakStats.reset(); stats = DurakStats.load() }
            Button(t("Cancel", "Отмена"), role: .cancel) {}
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(gold)
            Text(title).font(.caption).foregroundStyle(cream.opacity(0.75))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(burgundy.opacity(0.45)))
    }

    private func section(_ title: String, _ rows: [(String, DurakStats.Row)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(gold)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack {
                    Text(r.0).foregroundStyle(cream)
                    Spacer()
                    Text(t("\(r.1.played) played · \(r.1.won) won", "\(r.1.played) игр · \(r.1.won) побед"))
                        .foregroundStyle(cream.opacity(0.75)).font(.subheadline)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(burgundy.opacity(0.35)))
    }
}
