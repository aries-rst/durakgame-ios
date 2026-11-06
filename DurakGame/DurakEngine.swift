import Foundation

// MARK: - N-player (2–6 seat) Durak engine — Подкидной (throw-in) / Переводной
// (transfer) дурак.
//
// Faithful Swift port of the Android Kotlin engine (`DurakEngine.kt`'s rules:
// `newGame`/`beats`/`nextActive`/`limit`/`throwers`/`canThrow`/`canTransfer`/
// `pending`/`resolve`). Kept intentionally close to that structure — free
// functions operating on a mutable state object — so the rules stay
// bug-for-bug compatible, exactly like this portfolio's Domino engine port.
// Types are prefixed `Durak` to avoid colliding with any other game's types.
//
// 36-card deck (6 through Ace, no 2–5), suits spades/clubs/hearts/diamonds.
// The attacker opens with a card; while any attack on the table is
// undefended the other active seats may throw in more cards matching a
// rank already on the table (up to `limit()`, and never more undefended
// attacks than the defender could possibly still cover). The defender must
// beat every attack (same suit & higher rank, or any trump over a
// non-trump) or declare they're taking everything into their hand. In
// переводной, before defending a single card the defender may instead
// "transfer" the whole table — if every attack card on it shares one rank —
// to the next active seat, which becomes the new defender. Once a bout
// resolves, hands refill to 6 from the deck (attacker-relative order, the
// defender last); a seat left empty when the deck is spent is "out" (safe).
// The last seat still holding cards once everyone else is out is the fool.

// MARK: - Cards

enum DurakSuit: Int, CaseIterable, Codable, Hashable {
    case spades = 0, clubs = 1, hearts = 2, diamonds = 3

    var symbol: String {
        switch self {
        case .spades: return "♠"
        case .clubs: return "♣"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        }
    }

    var isRed: Bool { self == .hearts || self == .diamonds }
}

struct DurakCard: Equatable, Hashable, Identifiable, Codable {
    var suit: DurakSuit
    var rank: Int // 6...14 (J=11, Q=12, K=13, A=14)

    /// Matches the Kotlin engine's `Card.id = s*100+r` exactly.
    var id: Int { suit.rawValue * 100 + rank }

    var label: String {
        switch rank {
        case 6...10: return "\(rank)"
        case 11: return t("J", "В")
        case 12: return t("Q", "Д")
        case 13: return t("K", "К")
        case 14: return t("A", "Т")
        default: return "\(rank)"
        }
    }

    static let allRanks = Array(6...14)

    static func fullDeck() -> [DurakCard] {
        var out: [DurakCard] = []
        for s in DurakSuit.allCases {
            for r in allRanks { out.append(DurakCard(suit: s, rank: r)) }
        }
        return out
    }
}

/// One attack card on the table, with its defending card once (if) played.
struct DurakTPair: Codable, Hashable {
    var attack: DurakCard
    var defense: DurakCard?
}

enum DurakVariant: String, Codable, CaseIterable {
    case podkidnoy  // throw-in: any thrower may add matching-rank cards
    case perevodnoy // transfer: defender may redirect the whole table once, undefended
}

enum DurakPendingKind: String, Codable {
    case lead     // table empty: attacker must open
    case defend   // an attack is undefended: defender must beat it, transfer, or take
    case throwIn  // table has an undefended attack and a thrower (not yet all passed) may add to it
    case resolve  // everything defended (or taking) and no one can/will throw in more
}

struct DurakPending: Equatable {
    var kind: DurakPendingKind
    var seat: Int
}

/// A seedable xorshift64* RNG, mirroring this portfolio's Domino/Nardy
/// engines so shuffle/bot behaviour can be made deterministic for testing.
final class SeededGenerator {
    private var state: UInt64

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform integer in [0, bound).
    func nextInt(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(next() % UInt64(bound))
    }

    /// Uniform double in [0, 1).
    func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0) // 2^-53
    }
}

/// Mutable match state. Kept as a class so the `Durak` engine functions can
/// mutate it in place, exactly like the Kotlin `DState` does.
/// The last thing that happened in a match, for speech bubbles — a literal
/// port of Android's `Ev` class. `kind` is one of lead|throw|defend|take|
/// pass|transfer|took|beaten, matching Android's event-type strings exactly
/// so UI code can switch on them the same way `GameController.onView` does.
struct DurakEvent {
    var kind: String
    var seat: Int
    var card: DurakCard? = nil
}

final class DurakMatch {
    let n: Int
    let variant: DurakVariant
    let throwAll: Bool

    var hands: [[DurakCard]]
    var deck: [DurakCard]
    var trumpCard: DurakCard
    var trump: DurakSuit { trumpCard.suit }

    var table: [DurakTPair] = []
    var attacker: Int
    var defender: Int = 0
    /// The defender's hand size at the moment they became defender this
    /// bout — caps how many cards can ever land on the table this bout.
    var defStart: Int = 0

    /// true once a seat has safely emptied its hand (deck spent); such a
    /// seat is skipped by `nextActive` and can never attack/defend again.
    var out: [Bool]
    /// Seats in the order they went `out`, i.e. the order they finished.
    var finish: [Int] = []

    var taking: Bool = false
    /// Throwers who have already declined to add to the table this bout.
    var passed: Set<Int> = []
    /// True only for the very first bout of the whole match — caps the
    /// table at 5 cards during it (6 thereafter), per Android's exact rule.
    var firstBout: Bool = true
    var bout: Int = 0

    var over: Bool = false
    /// The seat left holding cards when everyone else is out (-1 = draw/no fool).
    var loser: Int = -1
    /// Set if the 200-bout safety cap was hit — treated as a draw.
    var stalled: Bool = false

    var discardCount: Int = 0

    /// The last action taken and who took it, for speech-bubble feedback —
    /// a literal port of Android's `DState.last: Ev?`.
    var lastEvent: DurakEvent? = nil
    /// Bumped on every action so a view can tell a brand-new event from one
    /// it already reacted to, exactly like Android's `TView.evSeq`.
    var evSeq: Int = 0

    init(n: Int, variant: DurakVariant, throwAll: Bool, hands: [[DurakCard]], deck: [DurakCard], trumpCard: DurakCard, attacker: Int) {
        self.n = n
        self.variant = variant
        self.throwAll = throwAll
        self.hands = hands
        self.deck = deck
        self.trumpCard = trumpCard
        self.attacker = attacker
        self.out = Array(repeating: false, count: n)
    }
}

enum Durak {
    static let minPlayers = 2
    static let maxPlayers = 6

    // MARK: - Setup

    /// Shuffles a fresh 36-card deck, peeks (does not remove) the trump
    /// card from the bottom, deals 6 cards per seat round-robin from the
    /// front for 6 rounds (which, at n=6, exhausts the deck including the
    /// trump card itself — matching Android exactly), then finds whoever
    /// holds the single lowest-ranked trump across all hands as the first
    /// attacker (random if nobody holds one).
    static func newGame(n: Int, variant: DurakVariant, throwAll: Bool, rnd: SeededGenerator = SeededGenerator()) -> DurakMatch {
        let clampedN = min(max(n, minPlayers), maxPlayers)
        var deck = DurakCard.fullDeck()
        if deck.count > 1 {
            for i in stride(from: deck.count - 1, through: 1, by: -1) {
                let j = rnd.nextInt(i + 1)
                deck.swapAt(i, j)
            }
        }
        let trumpCard = deck.last!

        var hands: [[DurakCard]] = Array(repeating: [], count: clampedN)
        for _ in 0..<6 {
            for p in 0..<clampedN {
                if deck.isEmpty { break }
                hands[p].append(deck.removeFirst())
            }
        }

        var attacker = -1
        var bestRank = Int.max
        for p in 0..<clampedN {
            for c in hands[p] where c.suit == trumpCard.suit {
                if c.rank < bestRank {
                    bestRank = c.rank
                    attacker = p
                }
            }
        }
        if attacker == -1 {
            attacker = rnd.nextInt(clampedN)
        }

        let m = DurakMatch(n: clampedN, variant: variant, throwAll: throwAll, hands: hands, deck: deck, trumpCard: trumpCard, attacker: attacker)
        m.defender = nextActive(m, attacker)
        m.defStart = m.hands[m.defender].count
        return m
    }

    // MARK: - Core queries

    static func beats(_ defense: DurakCard, _ attack: DurakCard, _ trump: DurakSuit) -> Bool {
        if defense.suit == attack.suit { return defense.rank > attack.rank }
        if defense.suit == trump && attack.suit != trump { return true }
        return false
    }

    /// Bot/hint heuristic: higher is "more valuable to keep."
    static func value(_ c: DurakCard, _ trump: DurakSuit) -> Int {
        c.rank + (c.suit == trump ? 20 : 0)
    }

    /// Next active (not-out) seat clockwise from `p`, wrapping.
    static func nextActive(_ m: DurakMatch, _ p: Int) -> Int {
        var i = (p + 1) % m.n
        var steps = 0
        while m.out[i] && steps < m.n {
            i = (i + 1) % m.n
            steps += 1
        }
        return i
    }

    static func ranksOnTable(_ m: DurakMatch) -> Set<Int> {
        var s = Set<Int>()
        for pair in m.table {
            s.insert(pair.attack.rank)
            if let d = pair.defense { s.insert(d.rank) }
        }
        return s
    }

    static func undefended(_ m: DurakMatch) -> Int {
        m.table.filter { $0.defense == nil }.count
    }

    /// Table cap for the current bout: 5 cards during the match's very
    /// first bout, 6 thereafter — always further capped by the defender's
    /// hand size at the start of their turn.
    static func limit(_ m: DurakMatch) -> Int {
        min(m.firstBout ? 5 : 6, m.defStart)
    }

    /// Ordered list of seats allowed to throw in this bout: starting at the
    /// attacker, walking clockwise, skipping the defender and any out
    /// seat; restricted to just the attacker and the defender's other
    /// neighbor when `throwAll` is off (neighbors-only mode).
    static func throwers(_ m: DurakMatch) -> [Int] {
        var list: [Int] = []
        var i = m.attacker
        var steps = 0
        while steps < m.n {
            if i != m.defender && !m.out[i] {
                list.append(i)
            }
            i = (i + 1) % m.n
            steps += 1
        }
        if !m.throwAll {
            let nd = nextActive(m, m.defender)
            list = list.filter { $0 == m.attacker || $0 == nd }
        }
        return list
    }

    /// Can seat `p` throw card `c` into the table right now?
    static func canThrow(_ m: DurakMatch, _ p: Int, _ c: DurakCard) -> Bool {
        guard throwers(m).contains(p) else { return false }
        guard ranksOnTable(m).contains(c.rank) else { return false }
        guard m.table.count < limit(m) else { return false }
        guard undefended(m) < m.hands[m.defender].count else { return false }
        return true
    }

    /// Переводной only: the defender may transfer the whole table (every
    /// attack card on it sharing `c`'s rank, and nothing defended yet) to
    /// the next active seat by playing a card of that same rank, provided
    /// that seat has enough cards to receive the table plus the transfer card.
    static func canTransfer(_ m: DurakMatch, _ c: DurakCard) -> Bool {
        guard m.variant == .perevodnoy else { return false }
        guard !m.table.isEmpty else { return false }
        guard m.table.allSatisfy({ $0.defense == nil }) else { return false }
        guard m.table.allSatisfy({ $0.attack.rank == c.rank }) else { return false }
        let nd = nextActive(m, m.defender)
        guard m.hands[nd].count >= m.table.count + 1 else { return false }
        return true
    }

    /// What needs to happen next, and whose turn it is to do it.
    static func pending(_ m: DurakMatch) -> DurakPending {
        if m.over { return DurakPending(kind: .resolve, seat: -1) }
        if m.table.isEmpty {
            return DurakPending(kind: .lead, seat: m.attacker)
        }
        if undefended(m) > 0 && !m.taking {
            return DurakPending(kind: .defend, seat: m.defender)
        }
        for j in throwers(m) {
            if m.passed.contains(j) { continue }
            if m.hands[j].contains(where: { canThrow(m, j, $0) }) {
                return DurakPending(kind: .throwIn, seat: j)
            }
        }
        return DurakPending(kind: .resolve, seat: -1)
    }

    // MARK: - Actions

    @discardableResult
    static func lead(_ m: DurakMatch, _ p: Int, _ c: DurakCard) -> Bool {
        let w = pending(m)
        guard w.kind == .lead, w.seat == p else { return false }
        guard let idx = m.hands[p].firstIndex(of: c) else { return false }
        m.hands[p].remove(at: idx)
        m.table.append(DurakTPair(attack: c, defense: nil))
        m.lastEvent = DurakEvent(kind: "lead", seat: p, card: c)
        m.evSeq += 1
        return true
    }

    @discardableResult
    static func throwIn(_ m: DurakMatch, _ p: Int, _ c: DurakCard) -> Bool {
        let w = pending(m)
        guard w.kind == .throwIn, w.seat == p else { return false }
        guard canThrow(m, p, c) else { return false }
        guard let idx = m.hands[p].firstIndex(of: c) else { return false }
        m.hands[p].remove(at: idx)
        m.table.append(DurakTPair(attack: c, defense: nil))
        m.lastEvent = DurakEvent(kind: "throw", seat: p, card: c)
        m.evSeq += 1
        return true
    }

    /// The current thrower declines to add anything more this bout.
    @discardableResult
    static func pass(_ m: DurakMatch, _ p: Int) -> Bool {
        let w = pending(m)
        guard w.kind == .throwIn, w.seat == p else { return false }
        m.passed.insert(p)
        m.lastEvent = DurakEvent(kind: "pass", seat: p)
        m.evSeq += 1
        return true
    }

    @discardableResult
    static func defend(_ m: DurakMatch, _ p: Int, _ attackIndex: Int, _ c: DurakCard) -> Bool {
        let w = pending(m)
        guard w.kind == .defend, w.seat == p else { return false }
        guard attackIndex >= 0, attackIndex < m.table.count else { return false }
        guard m.table[attackIndex].defense == nil else { return false }
        guard beats(c, m.table[attackIndex].attack, m.trump) else { return false }
        guard let idx = m.hands[p].firstIndex(of: c) else { return false }
        m.hands[p].remove(at: idx)
        m.table[attackIndex].defense = c
        m.lastEvent = DurakEvent(kind: "defend", seat: p, card: c)
        m.evSeq += 1
        return true
    }

    /// The defender gives up on beating the table and takes everything
    /// into their hand (resolved once throwing-in has settled).
    @discardableResult
    static func take(_ m: DurakMatch, _ p: Int) -> Bool {
        guard p == m.defender, !m.table.isEmpty, !m.taking else { return false }
        m.taking = true
        m.lastEvent = DurakEvent(kind: "take", seat: p)
        m.evSeq += 1
        return true
    }

    /// Переводной: instead of defending, redirect the whole (still
    /// undefended) table to the next seat, who becomes the new defender.
    @discardableResult
    static func transfer(_ m: DurakMatch, _ p: Int, _ c: DurakCard) -> Bool {
        guard p == m.defender else { return false }
        guard canTransfer(m, c) else { return false }
        guard let idx = m.hands[p].firstIndex(of: c) else { return false }
        m.hands[p].remove(at: idx)
        m.table.append(DurakTPair(attack: c, defense: nil))
        let nd = nextActive(m, m.defender)
        m.lastEvent = DurakEvent(kind: "transfer", seat: p, card: c)
        m.evSeq += 1
        m.attacker = m.defender
        m.defender = nd
        m.defStart = m.hands[m.defender].count
        return true
    }

    /// Ends the current bout: collects the table (to the defender's hand if
    /// taking, else to the discard pile), refills hands to 6 (attacker-
    /// relative order, defender last), retires any seat left empty once the
    /// deck is spent, then hands off to the next attacker/defender — or
    /// ends the match if at most one seat is still in it.
    @discardableResult
    static func resolve(_ m: DurakMatch) -> Bool {
        guard pending(m).kind == .resolve, !m.over else { return false }

        let took = m.taking
        let allCards = m.table.flatMap { pair -> [DurakCard] in
            var c = [pair.attack]
            if let d = pair.defense { c.append(d) }
            return c
        }
        if took {
            m.hands[m.defender].append(contentsOf: allCards)
        } else {
            m.discardCount += allCards.count
        }
        let oldDefender = m.defender
        m.table = []

        var order: [Int] = []
        var i = m.attacker
        var steps = 0
        while steps < m.n {
            if i != oldDefender && !m.out[i] {
                order.append(i)
            }
            i = (i + 1) % m.n
            steps += 1
        }
        if !m.out[oldDefender] {
            order.append(oldDefender)
        }
        for seat in order {
            while m.hands[seat].count < 6 && !m.deck.isEmpty {
                m.hands[seat].append(m.deck.removeFirst())
            }
        }

        if m.deck.isEmpty {
            for seat in 0..<m.n where !m.out[seat] && m.hands[seat].isEmpty {
                m.out[seat] = true
                m.finish.append(seat)
            }
        }

        m.lastEvent = DurakEvent(kind: took ? "took" : "beaten", seat: oldDefender)
        m.evSeq += 1
        m.firstBout = false
        m.bout += 1
        m.passed = []
        m.taking = false

        if m.bout >= 200 {
            m.over = true
            m.loser = -1
            m.stalled = true
            return true
        }

        let activeSeats = (0..<m.n).filter { !m.out[$0] }
        if activeSeats.count <= 1 {
            m.over = true
            m.loser = activeSeats.first ?? -1
            return true
        }

        let newAttacker = (took || m.out[oldDefender]) ? nextActive(m, oldDefender) : oldDefender
        let newDefender = nextActive(m, newAttacker)
        m.attacker = newAttacker
        m.defender = newDefender
        m.defStart = m.hands[newDefender].count
        return true
    }

    // MARK: - Bot AI (3 levels) — a literal port of the Android engine's bot
    // (`botLead`/`botThrow`/`planDefence`/`botDefend`/`hint` in
    // `DurakEngine.kt`), not just "faithful in spirit": every probability,
    // threshold and tie-break below matches the Kotlin source, so the bot
    // plays identically to Android at the same level.

    /// One automatic step for a bot seat (or to resolve a settled bout);
    /// false when a human must act or the match has already ended.
    @discardableResult
    static func botStep(_ m: DurakMatch, isBot: (Int) -> Bool, level: (Int) -> Int, rnd: SeededGenerator) -> Bool {
        guard !m.over else { return false }
        let w = pending(m)
        if w.kind == .resolve {
            return resolve(m)
        }
        guard isBot(w.seat) else { return false }
        let lvl = level(w.seat)
        switch w.kind {
        case .lead:
            lead(m, w.seat, botLead(m, w.seat, lvl, rnd))
        case .throwIn:
            if let c = botThrow(m, w.seat, lvl, rnd) {
                throwIn(m, w.seat, c)
            } else {
                pass(m, w.seat)
            }
        case .defend:
            switch botDefend(m, lvl, rnd) {
            case .take: take(m, w.seat)
            case .transfer(let c): transfer(m, w.seat, c)
            case .defend(let c, let idx): defend(m, w.seat, idx, c)
            }
        case .resolve:
            return resolve(m)
        }
        return true
    }

    /// Android `botLead`: the cheapest card by value; level 1 sometimes
    /// leads completely at random; level 3 prefers a non-trump rank it
    /// holds a pair of (≤ jack) while the deck still has cards, to set up
    /// a throw-in later. Callers only invoke this when it is a bot's turn
    /// to open an empty table, so its hand is never empty (matches
    /// Android's non-null `Card` return).
    static func botLead(_ m: DurakMatch, _ p: Int, _ level: Int, _ rnd: SeededGenerator) -> DurakCard {
        let h = m.hands[p]
        let t = m.trump
        if level == 1 && rnd.nextDouble() < 0.4 {
            return h[rnd.nextInt(h.count)]
        }
        let sorted = h.sorted { value($0, t) < value($1, t) }
        if level == 3 && !m.deck.isEmpty {
            var cnt: [Int: Int] = [:]
            for c in h where c.suit != t { cnt[c.rank, default: 0] += 1 }
            if let pick = sorted.first(where: { $0.suit != t && (cnt[$0.rank] ?? 0) >= 2 && $0.rank <= 11 }) {
                return pick
            }
        }
        return sorted[0]
    }

    /// Android `botThrow`: level 1 is a coin flip on the cheapest legal
    /// card; level 2 withholds it 25% of the time once the deck is gone;
    /// otherwise the cheapest legal card is thrown unless it looks too
    /// costly to give up — trumps are never thrown except while taking,
    /// rank ≥ 13 is always withheld, and rank ≥ 11 is withheld early in
    /// the deck. Exact thresholds match Android's.
    static func botThrow(_ m: DurakMatch, _ p: Int, _ level: Int, _ rnd: SeededGenerator) -> DurakCard? {
        let t = m.trump
        let cand = m.hands[p].filter { canThrow(m, p, $0) }.sorted { value($0, t) < value($1, t) }
        guard let c = cand.first else { return nil }
        if level == 1 {
            return rnd.nextDouble() < 0.5 ? c : nil
        }
        if m.deck.isEmpty { return c }
        if m.taking {
            return (c.suit != t && c.rank <= (level == 3 ? 11 : 10)) ? c : nil
        }
        if c.suit == t { return nil }
        if c.rank >= 13 { return nil }
        if c.rank >= 11 && m.deck.count > 10 { return nil }
        return c
    }

    /// A full defence plan covering every currently-open attack, highest-
    /// value attack assigned first — matches Android `planDefence` exactly,
    /// including returning nil the instant any open attack has nothing
    /// left in hand to beat it (no partial plans, unlike an earlier
    /// version of this file).
    struct DurakDefencePlan {
        var moves: [(card: DurakCard, tableIndex: Int)]
        var cost: Int
        var trumps: Int
    }

    static func planDefence(_ m: DurakMatch) -> DurakDefencePlan? {
        let t = m.trump
        var hand = m.hands[m.defender]
        let open = m.table.enumerated()
            .filter { $0.element.defense == nil }
            .sorted { value($0.element.attack, t) > value($1.element.attack, t) }
        var moves: [(card: DurakCard, tableIndex: Int)] = []
        var cost = 0
        var trumps = 0
        for o in open {
            let attack = o.element.attack
            guard let choice = hand.filter({ beats($0, attack, t) }).min(by: { value($0, t) < value($1, t) }) else {
                return nil
            }
            if let idx = hand.firstIndex(of: choice) { hand.remove(at: idx) }
            moves.append((card: choice, tableIndex: o.offset))
            cost += value(choice, t)
            if choice.suit == t { trumps += 1 }
        }
        return DurakDefencePlan(moves: moves, cost: cost, trumps: trumps)
    }

    enum DurakDefendDecision {
        case defend(DurakCard, Int)
        case transfer(DurakCard)
        case take
    }

    /// Android `botDefend`: prefer a cheap transfer (переводной, level > 1)
    /// whenever the full defence plan is impossible, trump-heavy, more
    /// expensive than the transfer card by more than 8, or on a coin flip;
    /// otherwise follow the cheapest-first plan, but take instead when
    /// that plan would burn a big trump (or two+ trumps) on an otherwise-
    /// cheap table once the deck is running low.
    static func botDefend(_ m: DurakMatch, _ level: Int, _ rnd: SeededGenerator) -> DurakDefendDecision {
        let p = m.defender
        let t = m.trump
        let h = m.hands[p]
        let tr = h.filter { canTransfer(m, $0) }.sorted { value($0, t) < value($1, t) }
        let pl = planDefence(m)
        if let c = tr.first, level > 1 {
            let cheap = c.suit != t || (level == 3 && m.deck.isEmpty)
            if cheap {
                let shouldTransfer = pl == nil || pl!.trumps > 0 || pl!.cost > value(c, t) + 8 || rnd.nextDouble() < 0.5
                if shouldTransfer { return .transfer(c) }
            }
        }
        guard let plan = pl else {
            if let c = tr.first { return .transfer(c) }
            return .take
        }
        if level >= 2 && m.deck.count > 6 {
            let bigTrump = plan.moves.contains { $0.card.suit == t && $0.card.rank >= (level == 3 ? 12 : 13) }
            let onlyLow = m.table.allSatisfy { $0.attack.rank <= 9 && $0.attack.suit != t }
            if (bigTrump || plan.trumps >= 2) && onlyLow && h.count <= 6 {
                return .take
            }
        }
        let f = plan.moves[0]
        return .defend(f.card, f.tableIndex)
    }

    /// Best-effort suggestion for the hint button — always "hard"-level,
    /// matching Android `hint`'s own fixed-seed RNG (seed 1) so repeated
    /// hint requests on the same table state always suggest the same move.
    static func hint(_ m: DurakMatch, _ p: Int) -> DurakCard? {
        let w = pending(m)
        guard w.seat == p else { return nil }
        let rnd = SeededGenerator(seed: 1)
        switch w.kind {
        case .lead:
            return botLead(m, p, 3, rnd)
        case .throwIn:
            return botThrow(m, p, 3, rnd)
        case .defend:
            switch botDefend(m, 3, rnd) {
            case .take: return nil
            case .transfer(let c): return c
            case .defend(let c, _): return c
            }
        case .resolve:
            return nil
        }
    }
}
