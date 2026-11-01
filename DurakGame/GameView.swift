import SwiftUI

struct DealPayload: Codable {
    var deck: [DurakCard]
    var trumpCard: DurakCard
    var whiteHand: [DurakCard]
    var blackHand: [DurakCard]
    var tableAttack: [DurakCard]
    var tableDefense: [DurakCard?]
    var attacker: DurakPlayer
    var defender: DurakPlayer
    var discardCount: Int
    var winner: DurakPlayer?
    var loser: DurakPlayer?
    var isDraw: Bool
    var statusMessage: String
}

enum DurakActionKind: String, Codable {
    case play, take, endRound
}

struct DurakAction: Codable {
    var kind: DurakActionKind
    var card: DurakCard? = nil
}

struct NetMessage: Codable {
    var action: DurakAction? = nil
    var deal: DealPayload? = nil
}

struct GameView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject private var lang = AppLang.shared
    @StateObject private var engine = DurakEngine()
    @Environment(\.dismiss) private var dismiss

    var multiplayer: MultiplayerManager? = nil
    var localColor: DurakPlayer = .white

    private let felt = Color(red: 0.08, green: 0.18, blue: 0.12)
    private let burgundy = Color(red: 0.42, green: 0.09, blue: 0.13)
    private let gold = Color(red: 0.82, green: 0.68, blue: 0.33)
    private let cream = Color(red: 0.95, green: 0.92, blue: 0.84)
    private let cardBack = Color(red: 0.30, green: 0.07, blue: 0.10)

    private var activeColor: DurakPlayer { multiplayer != nil ? localColor : .white }
    private var opponentColor: DurakPlayer { activeColor == .white ? .black : .white }

    var body: some View {
        ZStack {
            felt.ignoresSafeArea()
            VStack(spacing: 10) {
                header
                botRow
                Spacer(minLength: 2)
                tableView
                Spacer(minLength: 2)
                actionBar
                handRow
            }
            .padding(.top, 8)
        }
        .onChange(of: engine.moveCount) { _ in
            scheduleBotIfNeeded()
        }
        .onAppear {
            setupMultiplayerReceiver()
            scheduleBotIfNeeded()
        }
        .alert(
            t("Game Over", "Игра окончена"),
            isPresented: Binding(get: { engine.winner != nil || engine.isDraw }, set: { _ in })
        ) {
            Button(t("New Game", "Новая игра")) { resetGame() }
            Button(t("Menu", "В меню")) { dismiss() }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertMessage: String {
        guard multiplayer != nil else {
            return engine.statusMessage.isEmpty ? t("Game over.", "Игра завершена.") : engine.statusMessage
        }
        if engine.isDraw {
            return t("A draw — the deck ran out with both hands empty at the same time.", "Ничья — колода закончилась одновременно с обеими руками.")
        }
        guard let winner = engine.winner else {
            return t("Game over.", "Игра завершена.")
        }
        return winner == localColor ? t("You're out! Your opponent is the fool.", "Вы вышли! Соперник остался дураком.") : t("Your opponent is out. You're the fool!", "Соперник вышел. Вы — дурак!")
    }

    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                Text(engine.trumpSuit.symbol)
                    .foregroundStyle(engine.trumpSuit.isRed ? .red : cream)
                Text(t("trump", "козырь"))
                    .font(.caption)
                    .foregroundStyle(cream.opacity(0.7))
            }
            Spacer()
            Text("\(t("Deck", "Колода")): \(engine.deck.count)")
                .font(.caption)
                .foregroundStyle(gold)
            Spacer()
            Text("\(t("Discarded", "Бито")): \(engine.discardCount)")
                .font(.caption)
                .foregroundStyle(cream.opacity(0.6))
        }
        .padding(.horizontal, 16)
    }

    private var botRow: some View {
        HStack(spacing: 4) {
            Text(opponentLabel)
                .font(.caption)
                .foregroundStyle(gold)
            Spacer()
            HStack(spacing: -22) {
                ForEach(0..<(engine.hands[opponentColor]?.count ?? 0), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(cardBack)
                        .frame(width: 34, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(gold.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var opponentLabel: String {
        let verb = engine.attacker == opponentColor ? t("attacking", "атакует") : t("defending", "защищается")
        return multiplayer != nil ? "\(t("Opponent", "Соперник")) \(verb)" : "\(t("Bot", "Бот")) \(verb)"
    }

    private var tableView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if engine.tableAttack.isEmpty {
                    Text(engine.attacker == activeColor ? t("Choose a card to attack with", "Выберите карту для атаки") : (multiplayer != nil ? t("Opponent is attacking…", "Соперник сейчас атакует…") : t("Bot is attacking…", "Бот сейчас атакует…")))
                        .font(.footnote)
                        .foregroundStyle(cream.opacity(0.5))
                        .padding(.horizontal, 16)
                } else {
                    ForEach(Array(engine.tableAttack.enumerated()), id: \.offset) { i, attackCard in
                        ZStack(alignment: .bottomTrailing) {
                            cardView(attackCard)
                            if let defCard = engine.tableDefense[i] {
                                cardView(defCard)
                                    .offset(x: 10, y: 10)
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

    private var actionBar: some View {
        HStack(spacing: 12) {
            if engine.attacker == activeColor, engine.canEndRound {
                Button(t("Done", "Бито")) { handleEndRound() }
                    .buttonStyle(.borderedProminent)
                    .tint(gold)
            }
            if engine.defender == activeColor, engine.awaitingDefense {
                Button(t("Take", "Беру")) { handleTake() }
                    .buttonStyle(.borderedProminent)
                    .tint(burgundy)
            }
            Spacer()
            if multiplayer == nil || localColor == .white {
                Button {
                    resetGame()
                } label: {
                    Label(t("New Game", "Новая игра"), systemImage: "arrow.counterclockwise")
                }
                .font(.caption)
            }
            if let mp = multiplayer {
                Text(multiplayerStatusText(mp))
                    .font(.caption2)
                    .foregroundStyle(cream.opacity(0.5))
            }
        }
        .foregroundStyle(cream)
        .padding(.horizontal, 16)
    }

    private func multiplayerStatusText(_ mp: MultiplayerManager) -> String {
        if case .connected(let name) = mp.state {
            return "\(t("Connected", "Подключено")): \(name)"
        }
        return t("Connection lost", "Соединение прервано")
    }

    private var handRow: some View {
        VStack(spacing: 6) {
            Text(t("Your cards", "Ваши карты"))
                .font(.caption)
                .foregroundStyle(cream.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(engine.hands[activeColor] ?? []) { card in
                        let playable = isPlayable(card)
                        cardView(card)
                            .opacity(playable ? 1 : 0.4)
                            .scaleEffect(engine.selectedCard == card ? 1.08 : 1)
                            .onTapGesture { handleTapCard(card) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(burgundy.opacity(0.15))
    }

    private func isPlayable(_ card: DurakCard) -> Bool {
        if engine.attacker == activeColor { return engine.isValidAttackCard(card) }
        if engine.defender == activeColor { return engine.isValidDefenseCard(card) }
        return false
    }

    private func cardView(_ card: DurakCard) -> some View {
        VStack(spacing: 2) {
            Text(card.rank.label)
                .font(.system(size: 15, weight: .bold))
            Text(card.suit.symbol)
                .font(.system(size: 15))
        }
        .foregroundStyle(card.suit.isRed ? .red : .black)
        .frame(width: 42, height: 58)
        .background(cream)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(card.suit == engine.trumpSuit ? gold : Color.black.opacity(0.3),
                        lineWidth: card.suit == engine.trumpSuit ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    private func scheduleBotIfNeeded() {
        guard multiplayer == nil else { return }
        guard engine.winner == nil, !engine.isDraw else { return }
        let botShouldAct = (engine.defender == .black && engine.awaitingDefense)
            || (engine.attacker == .black && !engine.awaitingDefense)
        guard botShouldAct else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            engine.botActIfNeeded()
        }
    }

    private func handleTapCard(_ card: DurakCard) {
        guard multiplayer != nil else {
            engine.tapHandCard(card)
            return
        }
        if localColor == .white {
            engine.humanTapCard(card, color: .white)
            sendCurrentDeal()
        } else {
            multiplayer?.send(NetMessage(action: DurakAction(kind: .play, card: card)))
        }
    }

    private func handleTake() {
        guard multiplayer != nil else {
            engine.take(by: .white)
            return
        }
        if localColor == .white {
            engine.take(by: .white)
            sendCurrentDeal()
        } else {
            multiplayer?.send(NetMessage(action: DurakAction(kind: .take)))
        }
    }

    private func handleEndRound() {
        guard multiplayer != nil else {
            engine.endRoundSuccessfully()
            return
        }
        if localColor == .white {
            engine.endRoundSuccessfully()
            sendCurrentDeal()
        } else {
            multiplayer?.send(NetMessage(action: DurakAction(kind: .endRound)))
        }
    }

    private func resetGame() {
        if multiplayer != nil {
            guard localColor == .white else { return }
            engine.reset()
            sendCurrentDeal()
        } else {
            engine.reset()
        }
    }

    private func sendCurrentDeal() {
        let deal = DealPayload(
            deck: engine.deck,
            trumpCard: engine.trumpCard,
            whiteHand: engine.hands[.white] ?? [],
            blackHand: engine.hands[.black] ?? [],
            tableAttack: engine.tableAttack,
            tableDefense: engine.tableDefense,
            attacker: engine.attacker,
            defender: engine.defender,
            discardCount: engine.discardCount,
            winner: engine.winner,
            loser: engine.loser,
            isDraw: engine.isDraw,
            statusMessage: engine.statusMessage
        )
        multiplayer?.send(NetMessage(deal: deal))
    }

    private func setupMultiplayerReceiver() {
        guard let mp = multiplayer else { return }
        if localColor == .white {
            // Host already dealt and shuffled the real game in engine's init();
            // broadcast it so the guest mirrors the exact same hands/table/deck.
            sendCurrentDeal()
        }
        mp.onReceive = { data in
            guard let msg = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
            DispatchQueue.main.async {
                if let deal = msg.deal {
                    engine.applyDeal(
                        deck: deal.deck,
                        trumpCard: deal.trumpCard,
                        whiteHand: deal.whiteHand,
                        blackHand: deal.blackHand,
                        tableAttack: deal.tableAttack,
                        tableDefense: deal.tableDefense,
                        attacker: deal.attacker,
                        defender: deal.defender,
                        discardCount: deal.discardCount,
                        winner: deal.winner,
                        loser: deal.loser,
                        isDraw: deal.isDraw,
                        statusMessage: deal.statusMessage
                    )
                } else if let action = msg.action, localColor == .white {
                    // Host applies an action requested by the guest (always
                    // black), then rebroadcasts the resulting authoritative state.
                    switch action.kind {
                    case .play:
                        if let card = action.card {
                            engine.humanTapCard(card, color: .black)
                        }
                    case .take:
                        engine.take(by: .black)
                    case .endRound:
                        engine.endRoundSuccessfully()
                    }
                    sendCurrentDeal()
                }
            }
        }
    }
}

struct PremiumView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject private var lang = AppLang.shared
    @Environment(\.dismiss) private var dismiss

    private let gold = Color(red: 0.82, green: 0.68, blue: 0.33)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(gold)
                    .padding(.top, 24)

                Text(t("Durak Premium", "Дурак Premium"))
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    featureRow(t("No ads", "Без рекламы"))
                    featureRow(t("Local Wi-Fi/Bluetooth multiplayer", "Локальный мультиплеер по Wi-Fi/Bluetooth"))
                    featureRow(t("One-time purchase — yours forever", "Разовая покупка — навсегда"))
                }
                .padding(.horizontal, 24)

                if store.isPremium {
                    Label(t("Premium is already active", "Premium уже активен"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await store.purchasePremium() }
                    } label: {
                        Text("\(t("Buy for", "Купить за")) \(store.priceText)")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(gold)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)

                    Button(t("Restore Purchases", "Восстановить покупки")) {
                        Task { await store.restorePurchases() }
                    }
                    .font(.footnote)
                }

                if let err = store.purchaseErrorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Close", "Закрыть")) { dismiss() }
                }
            }
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text)
        }
    }
}

#Preview {
    GameView(store: StoreManager())
}
