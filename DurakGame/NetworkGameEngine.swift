import Foundation
import MultipeerConnectivity

// MARK: - Online multiplayer: host-authoritative wrapper around the real
// `Durak`/`DurakMatch` engine (same pattern already proven for this
// portfolio's Domino online play).
//
// The HOST's `NetworkGameEngine` is the only instance that ever calls a
// mutating `Durak.*` function or rolls its `rng` — it broadcasts the
// resulting `DurakMatch` state as an `OnlineSnapshot` after every change.
// Every guest's `NetworkGameEngine` is a pure mirror: it rebuilds a local
// `DurakMatch` from each snapshot purely so it can reuse the exact same
// read-only helpers (`Durak.pending`, `Durak.canThrow`, …) that
// `LocalGameEngine`/`LocalGameView` already use for display, and it sends
// small `OnlinePlayIntent`s back to the host whenever it is that guest's
// own seat's turn. The host re-validates every intent via the real engine
// before ever applying it — a guest can never mutate the match directly.
//
// Unlike Android's per-seat masked `TView`, every seat's hand is included
// in the broadcast snapshot (simpler, and identical to how this portfolio's
// Domino online port already works) — `NetworkGameView` simply never
// renders another seat's cards face-up, exactly like `LocalGameView`
// already never reveals a bot's hand.
//
// Up to `players - 1` guests can fill real seats; any seats still empty
// when the host starts are filled by bots — matching Android's
// `startHostGame(guests)` (seats 1..k = guests, the rest = bots) exactly,
// unlike this portfolio's Domino online mode which requires every seat to
// be a real player.

struct NetCard: Codable { let suit: Int; let rank: Int }
struct NetTPair: Codable { let attack: NetCard; let defense: NetCard? }

/// Included with every broadcast so a guest can always resolve which seat
/// is its own by matching its own device name against `seatNames` —
/// `seatNames[0]` is always the host, `seatNames[1...]` are the guests in
/// join order, and any remaining seats are bots.
struct OnlineStart: Codable {
    let variant: String
    let throwAll: Bool
    let seatNames: [String]
    let botSeats: [Bool]
}

/// Enough of `DurakMatch` for a guest to mirror the host's state and
/// render it with the same code `LocalGameView` uses.
struct OnlineSnapshot: Codable {
    let hands: [[NetCard]]
    let deckCount: Int
    let trumpCard: NetCard
    let table: [NetTPair]
    let attacker: Int
    let defender: Int
    let defStart: Int
    let out: [Bool]
    let finish: [Int]
    let taking: Bool
    let passed: [Int]
    let firstBout: Bool
    let bout: Int
    let over: Bool
    let loser: Int
    let stalled: Bool
    let discardCount: Int
    /// `match.lastEvent`/`evSeq` at broadcast time, so a guest's mirrored
    /// `DurakMatch` can show the same speech bubble as the host — see
    /// `DurakEvent` in `DurakEngine.swift`. Optional only for forward
    /// compatibility with any snapshot saved before this was added.
    let lastEventKind: String?
    let lastEventSeat: Int?
    let evSeq: Int
}

/// A guest's requested action for its own seat; the host re-validates this
/// against the live `DurakMatch` before ever applying it.
struct OnlinePlayIntent: Codable {
    let seat: Int
    let action: String // "lead" | "throwIn" | "defend" | "take" | "pass" | "transfer"
    let card: NetCard?
    let attackIndex: Int?
}

/// One wire message. Host → guests carries `start` + `snapshot`; guest →
/// host carries `intent`.
struct OnlineMessage: Codable {
    var start: OnlineStart? = nil
    var snapshot: OnlineSnapshot? = nil
    var intent: OnlinePlayIntent? = nil
}

private extension DurakCard {
    var net: NetCard { NetCard(suit: suit.rawValue, rank: rank) }
    init(_ n: NetCard) { self.init(suit: DurakSuit(rawValue: n.suit) ?? .spades, rank: n.rank) }
}

final class NetworkGameEngine: ObservableObject {
    @Published private(set) var version: Int = 0
    @Published private(set) var toastMessage: String? = nil
    /// Set once the transport reports the connection dropped; the view
    /// should offer the player a way back to the menu.
    @Published private(set) var connectionLost: Bool = false
    /// Seat → speech-bubble text, same as `LocalGameEngine.bubbles`. Carried
    /// over the wire via `OnlineSnapshot.lastEventKind`/`lastEventSeat` so a
    /// guest sees the same bubble the host does. A burst of bot/resolve
    /// steps between two broadcasts only shows the *last* one's bubble
    /// (broadcasting is batched for network efficiency — see
    /// `runResolveAndBots`), unlike the always-one-at-a-time local game.
    @Published private(set) var bubbles: [Int: String] = [:]

    private(set) var match: DurakMatch
    let mySeat: Int
    let isHost: Bool
    /// Fixed for the lifetime of one match: index 0 is the host, 1... are
    /// the guests in join order, and the rest (if any) are bots.
    let seatNames: [String]
    let botSeats: [Bool]

    private let multiplayer: MultiplayerManager
    private let rng = SeededGenerator()
    private var botTimer: Timer? = nil
    private var lastProcessedEvSeq: Int = -1

    var selectedCard: DurakCard? = nil

    /// - Parameters:
    ///   - isHost: true to actually run the match (seat 0); false to mirror
    ///     one being run elsewhere.
    ///   - seatNames: seat 0 = host's display name, 1... = guests in join
    ///     order, remaining = bots. On the guest side this comes from the
    ///     host's `OnlineStart`; on the host side the caller builds it from
    ///     `MultiplayerManager` + however many bots fill out the table.
    init(multiplayer: MultiplayerManager, isHost: Bool, variant: DurakVariant, throwAll: Bool, seatNames: [String], botSeats: [Bool]) {
        self.multiplayer = multiplayer
        self.isHost = isHost
        self.seatNames = seatNames
        self.botSeats = botSeats
        let n = seatNames.count

        if isHost {
            mySeat = 0
            match = Durak.newGame(n: n, variant: variant, throwAll: throwAll, rnd: rng)
        } else {
            mySeat = max(0, seatNames.firstIndex(of: multiplayer.myDisplayName) ?? 0)
            // Placeholder until the first snapshot arrives via `ingestInitial`.
            match = Durak.newGame(n: n, variant: variant, throwAll: throwAll, rnd: rng)
        }

        multiplayer.onReceive = { [weak self] data in self?.handleIncoming(data) }
        multiplayer.onStateChange = { [weak self] connected in
            guard let self = self, !connected else { return }
            DispatchQueue.main.async {
                self.connectionLost = true
                self.version += 1
            }
        }

        if isHost {
            broadcast()
            startBotLoop()
        }
    }

    deinit { botTimer?.invalidate() }

    /// Applies a message that arrived *before* this engine existed (the
    /// very first broadcast, which is what a guest uses to construct the
    /// engine in the first place) — the lobby screen calls this once right
    /// after creating a guest-side engine so that first snapshot isn't lost.
    func ingestInitial(_ msg: OnlineMessage) {
        guard !isHost, let snap = msg.snapshot else { return }
        applySnapshot(snap)
    }

    // MARK: - My actions (identical calls whether I'm the host or a guest)

    /// A single tap on a hand card does whatever is legal for my current
    /// role: lead, throw in, or defend/transfer the earliest open attack.
    func myTapCard(_ card: DurakCard) {
        let w = Durak.pending(match)
        guard w.seat == mySeat else { return }
        switch w.kind {
        case .lead:
            perform(action: "lead", card: card, attackIndex: nil)
        case .throwIn:
            guard Durak.canThrow(match, mySeat, card) else {
                showToast(t("That card doesn't match the table", "Эта карта не подходит к столу"))
                return
            }
            perform(action: "throwIn", card: card, attackIndex: nil)
        case .defend:
            guard let idx = match.table.firstIndex(where: { $0.defense == nil }) else { return }
            if Durak.beats(card, match.table[idx].attack, match.trump) {
                perform(action: "defend", card: card, attackIndex: idx)
            } else if match.variant == .perevodnoy, Durak.canTransfer(match, card) {
                perform(action: "transfer", card: card, attackIndex: nil)
            } else {
                showToast(t("That card doesn't beat it", "Эта карта не бьёт"))
                return
            }
        case .resolve:
            return
        }
        selectedCard = nil
    }

    func myTake() {
        perform(action: "take", card: nil, attackIndex: nil)
    }

    func myPass() {
        perform(action: "pass", card: nil, attackIndex: nil)
    }

    private func perform(action: String, card: DurakCard?, attackIndex: Int?) {
        if isHost {
            hostApply(seat: mySeat, action: action, card: card, attackIndex: attackIndex)
        } else {
            multiplayer.send(OnlineMessage(intent: OnlinePlayIntent(seat: mySeat, action: action, card: card?.net, attackIndex: attackIndex)))
        }
    }

    // MARK: - Host-only: rematch

    func hostRematch() {
        guard isHost else { return }
        let fresh = Durak.newGame(n: match.n, variant: match.variant, throwAll: match.throwAll, rnd: rng)
        match = fresh
        selectedCard = nil
        bumpAndBroadcast()
        startBotLoop()
    }

    // MARK: - Host: validate then apply any seat's action (local or remote)

    private func hostApply(seat: Int, action: String, card: DurakCard?, attackIndex: Int?) {
        guard isHost else { return }
        let w = Durak.pending(match)
        guard w.seat == seat else { return }
        var applied = false
        switch action {
        case "lead":
            if let card = card { applied = Durak.lead(match, seat, card) }
        case "throwIn":
            if let card = card { applied = Durak.throwIn(match, seat, card) }
        case "defend":
            if let card = card, let idx = attackIndex { applied = Durak.defend(match, seat, idx, card) }
        case "transfer":
            if let card = card { applied = Durak.transfer(match, seat, card) }
        case "take":
            applied = Durak.take(match, seat)
        case "pass":
            applied = Durak.pass(match, seat)
        default:
            return
        }
        guard applied else { return }
        bumpAndBroadcast()
        runResolveAndBots()
    }

    // MARK: - Host: bot loop (bot-filled seats only)

    private func startBotLoop() {
        botTimer?.invalidate()
        guard isHost else { return }
        botTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.botTick()
        }
    }

    private func botTick() {
        guard isHost, !match.over else { return }
        let w = Durak.pending(match)
        guard w.kind == .resolve || (w.seat >= 0 && w.seat < botSeats.count && botSeats[w.seat]) else { return }
        let stepped = Durak.botStep(match, isBot: { $0 < self.botSeats.count && self.botSeats[$0] }, level: { _ in 2 }, rnd: rng)
        guard stepped else { return }
        bumpAndBroadcast()
    }

    /// After a human/guest action, immediately resolve a settled bout (no
    /// one left to throw in) and let any bot seats take their turn right
    /// away rather than waiting for the next timer tick.
    private func runResolveAndBots() {
        guard isHost else { return }
        var guard_ = 0
        while !match.over, guard_ < 64 {
            let w = Durak.pending(match)
            let isBotTurn = w.kind == .resolve || (w.seat >= 0 && w.seat < botSeats.count && botSeats[w.seat])
            guard isBotTurn else { break }
            guard Durak.botStep(match, isBot: { $0 < self.botSeats.count && self.botSeats[$0] }, level: { _ in 2 }, rnd: rng) else { break }
            guard_ += 1
        }
        if guard_ > 0 { bumpAndBroadcast() }
    }

    // MARK: - Networking plumbing

    private func handleIncoming(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(OnlineMessage.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isHost {
                if let intent = msg.intent {
                    self.hostApply(seat: intent.seat, action: intent.action, card: intent.card.map(DurakCard.init), attackIndex: intent.attackIndex)
                }
            } else if let snap = msg.snapshot {
                self.applySnapshot(snap)
            }
        }
    }

    private func bumpAndBroadcast() {
        processEvent()
        version += 1
        if isHost { broadcast() }
    }

    /// Shows a speech bubble over the seat that just acted — mirrors
    /// `LocalGameEngine.processEvent()` exactly (same event kinds, same
    /// 1.4s duration); see that file for why lead/throw/defend get none.
    private func processEvent() {
        guard match.evSeq != lastProcessedEvSeq, let ev = match.lastEvent else { return }
        lastProcessedEvSeq = match.evSeq
        let text: String
        switch ev.kind {
        case "take": text = t("Take", "Беру")
        case "pass": text = t("Pass", "Пас")
        case "transfer": text = t("Transfer!", "Перевожу!")
        case "took": text = t("Took", "Взял")
        case "beaten": text = t("Done", "Бито")
        default: return
        }
        let seat = ev.seat
        bubbles[seat] = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self = self, self.bubbles[seat] == text else { return }
            self.bubbles[seat] = nil
        }
    }

    private func broadcast() {
        multiplayer.send(OnlineMessage(
            start: OnlineStart(variant: match.variant.rawValue, throwAll: match.throwAll, seatNames: seatNames, botSeats: botSeats),
            snapshot: makeSnapshot()
        ))
    }

    private func makeSnapshot() -> OnlineSnapshot {
        OnlineSnapshot(
            hands: match.hands.map { $0.map { $0.net } },
            deckCount: match.deck.count,
            trumpCard: match.trumpCard.net,
            table: match.table.map { NetTPair(attack: $0.attack.net, defense: $0.defense?.net) },
            attacker: match.attacker,
            defender: match.defender,
            defStart: match.defStart,
            out: match.out,
            finish: match.finish,
            taking: match.taking,
            passed: Array(match.passed),
            firstBout: match.firstBout,
            bout: match.bout,
            over: match.over,
            loser: match.loser,
            stalled: match.stalled,
            discardCount: match.discardCount,
            lastEventKind: match.lastEvent?.kind,
            lastEventSeat: match.lastEvent?.seat,
            evSeq: match.evSeq
        )
    }

    /// Rebuilds a mirrored `DurakMatch` from a received snapshot. The
    /// boneyard's actual cards are never shared (only a same-length
    /// placeholder, via `deckCount`) and the trump card is reused for every
    /// placeholder so `DurakSuit` stays valid.
    private func applySnapshot(_ s: OnlineSnapshot) {
        let trump = DurakCard(s.trumpCard)
        let placeholderDeck = Array(repeating: trump, count: s.deckCount)
        let m = DurakMatch(
            n: s.hands.count,
            variant: match.variant,
            throwAll: match.throwAll,
            hands: s.hands.map { $0.map(DurakCard.init) },
            deck: placeholderDeck,
            trumpCard: trump,
            attacker: s.attacker
        )
        m.defender = s.defender
        m.defStart = s.defStart
        m.table = s.table.map { DurakTPair(attack: DurakCard($0.attack), defense: $0.defense.map(DurakCard.init)) }
        m.out = s.out
        m.finish = s.finish
        m.taking = s.taking
        m.passed = Set(s.passed)
        m.firstBout = s.firstBout
        m.bout = s.bout
        m.over = s.over
        m.loser = s.loser
        m.stalled = s.stalled
        m.discardCount = s.discardCount
        if let kind = s.lastEventKind, let seat = s.lastEventSeat {
            m.lastEvent = DurakEvent(kind: kind, seat: seat)
        }
        m.evSeq = s.evSeq
        match = m
        processEvent()
        version += 1
    }

    private func showToast(_ message: String) {
        toastMessage = message
        version += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.toastMessage = nil
        }
    }
}
