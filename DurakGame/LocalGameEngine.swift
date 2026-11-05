import Foundation

/// Drives one local vs-bot `DurakMatch` (2–6 seats, human always seat 0) and
/// exposes it to SwiftUI. `DurakMatch` is a reference type mutated in place
/// by the `Durak` engine functions, so this wrapper bumps a `@Published`
/// counter after every mutation to trigger a redraw — views read
/// `engine.match` directly, exactly like this portfolio's `LocalGameEngine`
/// for Domino.
final class LocalGameEngine: ObservableObject {
    @Published private(set) var version: Int = 0
    @Published private(set) var toastMessage: String? = nil

    private(set) var match: DurakMatch
    let humanSeat = 0
    private let rng = SeededGenerator()
    private var botLevels: [Int]
    private let botLevel: Int

    var selectedCard: DurakCard? = nil
    var hintCard: DurakCard? = nil

    init(variant: DurakVariant, players: Int, botLevel: Int, throwAll: Bool) {
        let m = Durak.newGame(n: players, variant: variant, throwAll: throwAll, rnd: rng)
        self.match = m
        self.botLevel = botLevel
        self.botLevels = Array(repeating: botLevel, count: m.n)
        runBotsIfNeeded()
    }

    private func bump() { version += 1 }

    func isBot(_ p: Int) -> Bool { p != humanSeat }

    var pending: DurakPending { Durak.pending(match) }

    // MARK: - Human actions

    /// A single tap on a hand card does whatever is legal for the human's
    /// current role: lead, throw in, or defend the earliest open attack.
    func humanTapCard(_ card: DurakCard) {
        let w = pending
        guard w.seat == humanSeat else { return }
        switch w.kind {
        case .lead:
            Durak.lead(match, humanSeat, card)
        case .throwIn:
            guard Durak.canThrow(match, humanSeat, card) else {
                showToast(t("That card doesn't match the table", "Эта карта не подходит к столу"))
                return
            }
            Durak.throwIn(match, humanSeat, card)
        case .defend:
            guard let idx = match.table.firstIndex(where: { $0.defense == nil }) else { return }
            if Durak.beats(card, match.table[idx].attack, match.trump) {
                Durak.defend(match, humanSeat, idx, card)
            } else if match.variant == .perevodnoy, Durak.canTransfer(match, card) {
                Durak.transfer(match, humanSeat, card)
            } else {
                showToast(t("That card doesn't beat it", "Эта карта не бьёт"))
                return
            }
        case .resolve:
            return
        }
        selectedCard = nil
        hintCard = nil
        bump()
        runBotsIfNeeded()
    }

    func humanTake() {
        guard Durak.take(match, humanSeat) else { return }
        bump()
        runBotsIfNeeded()
    }

    func humanPass() {
        let w = pending
        guard w.kind == .throwIn, w.seat == humanSeat else { return }
        Durak.pass(match, humanSeat)
        bump()
        runBotsIfNeeded()
    }

    func requestHint() {
        guard pending.seat == humanSeat else { return }
        hintCard = Durak.hint(match, humanSeat)
        bump()
    }

    func rematch(variant: DurakVariant, players: Int, botLevel: Int, throwAll: Bool) {
        let fresh = Durak.newGame(n: players, variant: variant, throwAll: throwAll, rnd: rng)
        match = fresh
        botLevels = Array(repeating: botLevel, count: fresh.n)
        selectedCard = nil
        hintCard = nil
        bump()
        runBotsIfNeeded()
    }

    private func showToast(_ message: String) {
        toastMessage = message
        bump()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.toastMessage = nil
        }
    }

    // MARK: - Bot stepping

    private func runBotsIfNeeded(delay: Double = 0.55) {
        let w = Durak.pending(match)
        guard !match.over, w.kind == .resolve || isBot(w.seat) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            let stepped = Durak.botStep(self.match, isBot: self.isBot, level: { self.botLevels[$0] }, rnd: self.rng)
            guard stepped else { return }
            self.bump()
            self.runBotsIfNeeded()
        }
    }
}
