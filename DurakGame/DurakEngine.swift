import Foundation

enum DurakPlayer: String, Codable, Equatable {
    case white // human
    case black // bot
}

enum CardSuit: String, CaseIterable, Equatable, Hashable {
    case spades, hearts, diamonds, clubs

    var symbol: String {
        switch self {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        case .clubs: return "♣"
        }
    }

    var isRed: Bool { self == .hearts || self == .diamonds }
}

enum CardRank: Int, CaseIterable, Equatable, Hashable, Comparable {
    case six = 6, seven, eight, nine, ten, jack, queen, king, ace

    static func < (lhs: CardRank, rhs: CardRank) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .ten: return "10"
        case .jack: return "В"
        case .queen: return "Д"
        case .king: return "К"
        case .ace: return "Т"
        }
    }
}

struct DurakCard: Equatable, Hashable, Identifiable {
    var suit: CardSuit
    var rank: CardRank
    var id: String { "\(rank.rawValue)-\(suit.rawValue)" }
}

/// Подкидной дурак (throw-in Durak), 2 players (you vs. a bot), 36-card deck
/// (6 through Ace), 6 cards dealt each. The attacker opens with a card; the
/// defender must beat each attack (higher card of the same suit, or any trump
/// over a non-trump) or take every card on the table into their hand. While
/// any attack remains undefended the attacker may throw in more cards
/// matching a rank already on the table, up to 6 cards or the defender's
/// starting hand size for the round, whichever is smaller. If the defender
/// beats everything and the attacker stops, the table is discarded, both
/// draw back up to 6 (attacker first), and the defender becomes the new
/// attacker. If the defender takes, only the attacker redraws and the same
/// two keep their roles. Once the deck is empty, the first player to empty
/// their hand is safe; the other is left "the fool."
final class DurakEngine: ObservableObject {
    @Published var deck: [DurakCard] = []
    @Published var trumpCard: DurakCard!
    @Published var hands: [DurakPlayer: [DurakCard]] = [:]
    @Published var tableAttack: [DurakCard] = []
    @Published var tableDefense: [DurakCard?] = []
    @Published var attacker: DurakPlayer = .white
    @Published var defender: DurakPlayer = .black
    @Published var discardCount: Int = 0
    @Published var winner: DurakPlayer? = nil
    @Published var loser: DurakPlayer? = nil
    @Published var isDraw: Bool = false
    @Published var selectedCard: DurakCard? = nil
    @Published var statusMessage: String = ""
    /// Bumped on every state-changing action so the view can re-trigger the bot.
    @Published var moveCount: Int = 0

    var trumpSuit: CardSuit { trumpCard.suit }
    private var roundLimit: Int = 6

    init() {
        reset()
    }

    func reset() {
        var full: [DurakCard] = []
        for suit in CardSuit.allCases {
            for rank in CardRank.allCases {
                full.append(DurakCard(suit: suit, rank: rank))
            }
        }
        full.shuffle()

        let white = Array(full.prefix(6))
        full.removeFirst(6)
        let black = Array(full.prefix(6))
        full.removeFirst(6)

        let trump = full.first!
        full.removeFirst()
        full.append(trump)

        deck = full
        trumpCard = trump
        hands = [.white: white, .black: black]
        tableAttack = []
        tableDefense = []
        discardCount = 0
        winner = nil
        loser = nil
        isDraw = false
        selectedCard = nil
        statusMessage = ""
        roundLimit = 6

        func lowestTrump(_ hand: [DurakCard]) -> Int? {
            hand.filter { $0.suit == trump.suit }.map { $0.rank.rawValue }.min()
        }
        let w = lowestTrump(white)
        let b = lowestTrump(black)
        if let w, let b {
            attacker = w <= b ? .white : .black
        } else if w != nil {
            attacker = .white
        } else if b != nil {
            attacker = .black
        } else {
            attacker = .white
        }
        defender = attacker == .white ? .black : .white
        moveCount += 1
    }

    private func beats(_ defense: DurakCard, _ attack: DurakCard) -> Bool {
        if defense.suit == attack.suit { return defense.rank > attack.rank }
        if defense.suit == trumpSuit && attack.suit != trumpSuit { return true }
        return false
    }

    var tableRanks: Set<CardRank> {
        Set(tableAttack.map { $0.rank } + tableDefense.compactMap { $0?.rank })
    }

    var awaitingDefense: Bool { tableDefense.contains { $0 == nil } }
    var canEndRound: Bool { !tableAttack.isEmpty && !awaitingDefense }
    var earliestUndefendedIndex: Int? { tableDefense.firstIndex { $0 == nil } }

    func isValidAttackCard(_ card: DurakCard) -> Bool {
        if tableAttack.isEmpty { return true }
        return tableRanks.contains(card.rank) && tableAttack.count < roundLimit
    }

    func isValidDefenseCard(_ card: DurakCard) -> Bool {
        guard let index = earliestUndefendedIndex else { return false }
        return beats(card, tableAttack[index])
    }

    @discardableResult
    func attack(_ card: DurakCard, by player: DurakPlayer) -> Bool {
        guard player == attacker, winner == nil, isDraw == false else { return false }
        guard hands[player]?.contains(card) == true else { return false }
        if tableAttack.isEmpty {
            roundLimit = min(6, hands[defender]?.count ?? 6)
        }
        guard isValidAttackCard(card) else { return false }

        hands[player]?.removeAll { $0 == card }
        tableAttack.append(card)
        tableDefense.append(nil)
        if player == .white { selectedCard = nil }
        moveCount += 1
        return true
    }

    @discardableResult
    func defend(_ card: DurakCard, by player: DurakPlayer) -> Bool {
        guard player == defender, winner == nil, isDraw == false else { return false }
        guard let index = earliestUndefendedIndex else { return false }
        guard hands[player]?.contains(card) == true, beats(card, tableAttack[index]) else { return false }

        hands[player]?.removeAll { $0 == card }
        tableDefense[index] = card
        if player == .white { selectedCard = nil }
        moveCount += 1
        return true
    }

    func take(by player: DurakPlayer) {
        guard player == defender, winner == nil, isDraw == false else { return }
        var picked = tableAttack
        picked.append(contentsOf: tableDefense.compactMap { $0 })
        hands[defender, default: []].append(contentsOf: picked)
        tableAttack = []
        tableDefense = []
        selectedCard = nil
        statusMessage = ""

        drawUpTo6(attacker)
        // Defender keeps their enlarged hand and does not redraw.
        checkGameEnd()
        moveCount += 1
    }

    func endRoundSuccessfully() {
        guard attacker == .white || attacker == .black, canEndRound else { return }
        discardCount += tableAttack.count + tableDefense.compactMap { $0 }.count
        tableAttack = []
        tableDefense = []
        selectedCard = nil

        drawUpTo6(attacker)
        drawUpTo6(defender)

        let newAttacker = defender
        let newDefender = attacker
        attacker = newAttacker
        defender = newDefender

        checkGameEnd()
        moveCount += 1
    }

    private func drawUpTo6(_ player: DurakPlayer) {
        while (hands[player]?.count ?? 0) < 6, !deck.isEmpty {
            hands[player, default: []].append(deck.removeFirst())
        }
    }

    private func checkGameEnd() {
        guard deck.isEmpty else { return }
        let whiteEmpty = hands[.white]?.isEmpty ?? true
        let blackEmpty = hands[.black]?.isEmpty ?? true
        if whiteEmpty && blackEmpty {
            isDraw = true
            statusMessage = "Ничья — колода закончилась одновременно с обеими руками."
        } else if whiteEmpty {
            winner = .white
            loser = .black
            statusMessage = "Вы вышли! Бот остался дураком."
        } else if blackEmpty {
            winner = .black
            loser = .white
            statusMessage = "Бот вышел. Вы — дурак!"
        }
    }

    func tapHandCard(_ card: DurakCard) {
        guard winner == nil, !isDraw else { return }
        if attacker == .white, isValidAttackCard(card) {
            attack(card, by: .white)
        } else if defender == .white, isValidDefenseCard(card) {
            defend(card, by: .white)
        }
    }
}

// MARK: - Simple AI (Black)

extension DurakEngine {
    /// Performs exactly one bot action if it is currently the bot's turn to
    /// act, then returns. Called again after every state change so a bot
    /// attack/defense sequence unfolds one step at a time.
    func botActIfNeeded() {
        guard winner == nil, !isDraw else { return }

        if defender == .black, awaitingDefense {
            botDefend()
        } else if attacker == .black, !awaitingDefense {
            botAttackOrEnd()
        }
    }

    private func botDefend() {
        guard let index = earliestUndefendedIndex, let hand = hands[.black] else { return }
        let options = hand.filter { beats($0, tableAttack[index]) }
        if let choice = options.min(by: { a, b in
            if (a.suit == trumpSuit) != (b.suit == trumpSuit) { return b.suit == trumpSuit }
            return a.rank < b.rank
        }) {
            defend(choice, by: .black)
        } else {
            take(by: .black)
        }
    }

    private func botAttackOrEnd() {
        guard let hand = hands[.black] else { return }
        if tableAttack.isEmpty {
            // Opening the round: lead with the lowest non-trump card.
            let nonTrump = hand.filter { $0.suit != trumpSuit }.min { $0.rank < $1.rank }
            let fallback = hand.min { $0.rank < $1.rank }
            if let card = nonTrump ?? fallback {
                attack(card, by: .black)
            }
            return
        }
        guard canEndRound else { return }
        let throwables = hand.filter { isValidAttackCard($0) }
        if let card = throwables.min(by: { a, b in
            if (a.suit == trumpSuit) != (b.suit == trumpSuit) { return b.suit == trumpSuit }
            return a.rank < b.rank
        }) {
            attack(card, by: .black)
        } else {
            endRoundSuccessfully()
        }
    }
}
