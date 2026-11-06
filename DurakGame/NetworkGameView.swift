import SwiftUI
import MultipeerConnectivity

/// Online "Play Nearby" game screen, backed by `NetworkGameEngine` (the
/// real `Durak`/`DurakMatch` engine, host-authoritative over the network).
/// Visually mirrors `LocalGameView` (same table/hand rendering, same
/// palette) but seats are real connected players (plus any bots filling
/// out the table) instead of all-bot, and only the host can start a
/// rematch once the match ends — everyone else just waits for it.
struct NetworkGameView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject private var lang = AppLang.shared
    @ObservedObject var engine: NetworkGameEngine
    let multiplayer: MultiplayerManager
    @Environment(\.dismiss) private var dismiss

    private let felt = Color(red: 0.08, green: 0.18, blue: 0.12)
    private let burgundy = Color(red: 0.42, green: 0.09, blue: 0.13)
    private let gold = Color(red: 0.82, green: 0.68, blue: 0.33)
    private let cream = Color(red: 0.95, green: 0.92, blue: 0.84)

    var body: some View {
        ZStack {
            felt.ignoresSafeArea()
            VStack(spacing: 10) {
                topBar
                seatsRow
                tableView
                statusArea
                actionsRow
                Spacer(minLength: 2)
                handSection
            }
            .padding(.top, 8)
        }
        .sheet(isPresented: Binding(get: { engine.match.over }, set: { _ in })) {
            gameOverSheet
        }
        .alert(
            t("Connection Lost", "Соединение потеряно"),
            isPresented: Binding(get: { engine.connectionLost }, set: { _ in })
        ) {
            Button(t("Menu", "В меню")) { leave() }
        } message: {
            Text(t("A player disconnected.", "Игрок отключился."))
        }
        .navigationBarBackButtonHidden(true)
    }

    private func leave() {
        multiplayer.stop()
        dismiss()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: leave) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(cream.opacity(0.7))
                    .font(.title3)
            }
            Spacer()
            HStack(spacing: 4) {
                Text(engine.match.trump.symbol)
                    .foregroundStyle(engine.match.trump.isRed ? .red : cream)
                Text(t("trump", "козырь"))
                    .font(.caption)
                    .foregroundStyle(cream.opacity(0.7))
            }
            Spacer()
            VStack(spacing: 1) {
                Text("\(t("Deck", "Колода")): \(engine.match.deck.count)")
                    .font(.caption2).foregroundStyle(gold)
                Text("\(t("Discarded", "Бито")): \(engine.match.discardCount)")
                    .font(.caption2).foregroundStyle(cream.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Seats

    private var seatsRow: some View {
        let n = engine.match.n
        let order = n > 1 ? (1..<n).map { (engine.mySeat + $0) % n } : []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(order, id: \.self) { p in seatView(p) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func seatView(_ p: Int) -> some View {
        let m = engine.match
        let isTurn = Durak.pending(m).seat == p
        let count = m.hands[p].count
        let isOut = m.out[p]
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Text(avatarEmoji(p))
                    .font(.system(size: 26))
                    .padding(7)
                    .background(Circle().fill(burgundy.opacity(0.35)))
                    .overlay(Circle().stroke(isTurn ? gold : Color.clear, lineWidth: 3))
                    .opacity(isOut ? 0.4 : 1)
                if m.attacker == p {
                    roleTag("⚔️")
                } else if m.defender == p {
                    roleTag("🛡️")
                }
            }
            Text(seatName(p)).font(.caption2).foregroundStyle(cream).lineLimit(1)
            if isOut {
                Text(t("safe", "вышел")).font(.system(size: 9)).foregroundStyle(gold.opacity(0.8))
            } else {
                cardCountIndicator(count)
            }
        }
        .overlay(alignment: .top) {
            if let bubble = engine.bubbles[p] {
                speechBubble(bubble).offset(y: -34).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: engine.bubbles[p])
    }

    /// Mirrors `LocalGameView.speechBubble` — see `NetworkGameEngine.bubbles`.
    private func speechBubble(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(gold))
            .fixedSize()
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    private func roleTag(_ emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: 10))
            .padding(2)
            .background(Circle().fill(Color.black.opacity(0.5)))
            .offset(x: 6, y: -4)
    }

    private func avatarEmoji(_ p: Int) -> String {
        ["🙂", "🧔", "👩", "👳", "🧑‍🦱", "👴"][p % 6]
    }

    private func cardCountIndicator(_ count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<min(count, 10), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5).fill(cream.opacity(0.75)).frame(width: 4, height: 10)
            }
            if count > 10 {
                Text("+").font(.system(size: 9)).foregroundStyle(cream.opacity(0.75))
            }
        }
    }

    /// Seats are real connected players (plus any bots filling the table)
    /// here — show their device name rather than a generic "Bot N" where
    /// one was actually assigned.
    private func seatName(_ p: Int) -> String {
        if p == engine.mySeat { return t("You", "Вы") }
        guard p >= 0, p < engine.seatNames.count else { return "\(t("Player", "Игрок")) \(p)" }
        if p < engine.botSeats.count, engine.botSeats[p] { return "\(t("Bot", "Бот")) \(p)" }
        return engine.seatNames[p]
    }

    // MARK: - Table

    private var tableView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if engine.match.table.isEmpty {
                    Text(tableEmptyHint)
                        .font(.footnote)
                        .foregroundStyle(cream.opacity(0.5))
                        .padding(.horizontal, 16)
                } else {
                    ForEach(Array(engine.match.table.enumerated()), id: \.offset) { i, pair in
                        ZStack(alignment: .bottomTrailing) {
                            cardView(pair.attack)
                            if let defCard = pair.defense {
                                cardView(defCard).offset(x: 10, y: 10)
                            }
                        }
                        .frame(width: 66, height: 68)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 90)
        }
        .frame(height: 100)
        .background(burgundy.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private var tableEmptyHint: String {
        let w = Durak.pending(engine.match)
        if w.seat == engine.mySeat {
            return t("Choose a card to attack with", "Выберите карту для атаки")
        }
        return t("\(seatName(w.seat)) is attacking…", "\(seatName(w.seat)) сейчас атакует…")
    }

    // MARK: - Status / actions

    private var statusArea: some View {
        VStack(spacing: 4) {
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(gold)
                .multilineTextAlignment(.center)
            if let toast = engine.toastMessage {
                Text(toast).font(.caption).foregroundStyle(.red).transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: engine.toastMessage)
    }

    private var statusText: String {
        let w = Durak.pending(engine.match)
        if w.seat == engine.mySeat {
            switch w.kind {
            case .lead: return t("Your turn — lead an attack", "Ваш ход — атакуйте")
            case .throwIn: return t("You may throw in a matching card, or pass", "Можете подкинуть карту того же достоинства или пасовать")
            case .defend: return t("Defend, transfer, or take", "Отбивайтесь, переводите или берите")
            case .resolve: return ""
            }
        }
        if w.kind == .resolve { return t("Connecting…", "Подключение…") }
        return t("\(seatName(w.seat))'s turn…", "Ход: \(seatName(w.seat))…")
    }

    private var actionsRow: some View {
        let w = Durak.pending(engine.match)
        return HStack(spacing: 12) {
            if w.seat == engine.mySeat {
                if w.kind == .throwIn {
                    pillButton(t("Pass", "Пас"), system: "arrow.uturn.forward", tint: burgundy) { engine.myPass() }
                }
                if w.kind == .defend {
                    pillButton(t("Take", "Беру"), system: "hand.raised.fill", tint: burgundy) { engine.myTake() }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func pillButton(_ text: String, system: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: system)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(tint.opacity(0.22)))
                .overlay(Capsule().stroke(tint.opacity(0.7), lineWidth: 1))
                .foregroundStyle(cream)
        }
    }

    // MARK: - Hand

    private var sortedHand: [DurakCard] {
        let trump = engine.match.trump
        guard engine.mySeat < engine.match.hands.count else { return [] }
        return engine.match.hands[engine.mySeat].sorted { a, b in
            if (a.suit == trump) != (b.suit == trump) { return b.suit == trump }
            if a.suit != b.suit { return a.suit.rawValue < b.suit.rawValue }
            return a.rank < b.rank
        }
    }

    private func isPlayable(_ card: DurakCard) -> Bool {
        let w = Durak.pending(engine.match)
        guard w.seat == engine.mySeat else { return false }
        switch w.kind {
        case .lead: return true
        case .throwIn: return Durak.canThrow(engine.match, engine.mySeat, card)
        case .defend:
            guard let idx = engine.match.table.firstIndex(where: { $0.defense == nil }) else { return false }
            if Durak.beats(card, engine.match.table[idx].attack, engine.match.trump) { return true }
            return engine.match.variant == .perevodnoy && Durak.canTransfer(engine.match, card)
        case .resolve: return false
        }
    }

    private var hasPendingMine: Bool { Durak.pending(engine.match).seat == engine.mySeat }

    private var handSection: some View {
        VStack(spacing: 6) {
            Text(t("Your cards", "Ваши карты")).font(.caption).foregroundStyle(cream.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sortedHand) { card in handCardView(card) }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(burgundy.opacity(0.15))
    }

    private func handCardView(_ card: DurakCard) -> some View {
        let playable = isPlayable(card)
        return cardView(card)
            .opacity((playable || !hasPendingMine) ? 1 : 0.4)
            .scaleEffect(engine.selectedCard == card ? 1.08 : 1)
            .onTapGesture { engine.myTapCard(card) }
            .animation(.easeOut(duration: 0.15), value: engine.selectedCard)
    }

    private func cardView(_ card: DurakCard) -> some View {
        VStack(spacing: 2) {
            Text(card.label).font(.system(size: 15, weight: .bold))
            Text(card.suit.symbol).font(.system(size: 15))
        }
        .foregroundStyle(card.suit.isRed ? .red : .black)
        .frame(width: 42, height: 58)
        .background(cream)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(card.suit == engine.match.trump ? gold : Color.black.opacity(0.3),
                        lineWidth: card.suit == engine.match.trump ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    // MARK: - Game over

    private var gameOverSheet: some View {
        let m = engine.match
        let iAmFool = m.loser == engine.mySeat
        let isDraw = m.loser == -1
        return ZStack {
            felt.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(isDraw ? t("A Draw", "Ничья") : (iAmFool ? t("You're the Fool!", "Вы — дурак!") : t("Victory!", "Победа!")))
                    .font(.largeTitle.bold())
                    .foregroundStyle(isDraw ? cream : (iAmFool ? burgundy : gold))
                Text(gameOverSubtitle)
                    .font(.headline)
                    .foregroundStyle(cream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack(spacing: 16) {
                    if engine.isHost {
                        Button(t("Play again", "Ещё партия")) { engine.hostRematch() }
                            .fontWeight(.bold)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(burgundy)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(t("Waiting for the host to continue…", "Ждём, когда хост продолжит игру…"))
                            .font(.caption)
                            .foregroundStyle(cream.opacity(0.7))
                    }
                    Button(t("Menu", "В меню")) { leave() }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .foregroundStyle(cream)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cream.opacity(0.4), lineWidth: 1))
                }
            }
            .padding(28)
        }
        .presentationDetents([.medium])
    }

    private var gameOverSubtitle: String {
        let m = engine.match
        if m.stalled { return t("The deck ran out of patience — called as a draw.", "Партия затянулась — объявлена ничья.") }
        if m.loser == -1 { return t("Everyone emptied their hand at once.", "Все одновременно остались без карт.") }
        if m.loser == engine.mySeat { return t("Everyone else is out — you're left holding cards.", "Все остальные вышли — у вас остались карты.") }
        return t("\(seatName(m.loser)) is left holding the cards.", "\(seatName(m.loser)) остался с картами на руках.")
    }
}
