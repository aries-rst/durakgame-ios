import SwiftUI

struct GameView: View {
    @ObservedObject var store: StoreManager
    @StateObject private var engine = DurakEngine()
    @Environment(\.dismiss) private var dismiss

    private let felt = Color(red: 0.08, green: 0.18, blue: 0.12)
    private let burgundy = Color(red: 0.42, green: 0.09, blue: 0.13)
    private let gold = Color(red: 0.82, green: 0.68, blue: 0.33)
    private let cream = Color(red: 0.95, green: 0.92, blue: 0.84)
    private let cardBack = Color(red: 0.30, green: 0.07, blue: 0.10)

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
        .onAppear { scheduleBotIfNeeded() }
        .alert(
            "Игра окончена",
            isPresented: Binding(get: { engine.winner != nil || engine.isDraw }, set: { _ in })
        ) {
            Button("Новая игра") { engine.reset() }
            Button("В меню") { dismiss() }
        } message: {
            Text(engine.statusMessage.isEmpty ? "Игра завершена." : engine.statusMessage)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                Text(engine.trumpSuit.symbol)
                    .foregroundStyle(engine.trumpSuit.isRed ? .red : cream)
                Text("козырь")
                    .font(.caption)
                    .foregroundStyle(cream.opacity(0.7))
            }
            Spacer()
            Text("Колода: \(engine.deck.count)")
                .font(.caption)
                .foregroundStyle(gold)
            Spacer()
            Text("Бито: \(engine.discardCount)")
                .font(.caption)
                .foregroundStyle(cream.opacity(0.6))
        }
        .padding(.horizontal, 16)
    }

    private var botRow: some View {
        HStack(spacing: 4) {
            Text(engine.attacker == .black ? "Бот атакует" : "Бот защищается")
                .font(.caption)
                .foregroundStyle(gold)
            Spacer()
            HStack(spacing: -22) {
                ForEach(0..<(engine.hands[.black]?.count ?? 0), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(cardBack)
                        .frame(width: 34, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(gold.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var tableView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if engine.tableAttack.isEmpty {
                    Text(engine.attacker == .white ? "Выберите карту для атаки" : "Бот сейчас атакует…")
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
            if engine.attacker == .white, engine.canEndRound {
                Button("Бито") { engine.endRoundSuccessfully() }
                    .buttonStyle(.borderedProminent)
                    .tint(gold)
            }
            if engine.defender == .white, engine.awaitingDefense {
                Button("Беру") { engine.take(by: .white) }
                    .buttonStyle(.borderedProminent)
                    .tint(burgundy)
            }
            Spacer()
            Button {
                engine.reset()
            } label: {
                Label("Новая игра", systemImage: "arrow.counterclockwise")
            }
            .font(.caption)
        }
        .foregroundStyle(cream)
        .padding(.horizontal, 16)
    }

    private var handRow: some View {
        VStack(spacing: 6) {
            Text("Ваши карты")
                .font(.caption)
                .foregroundStyle(cream.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(engine.hands[.white] ?? []) { card in
                        let playable = isPlayable(card)
                        cardView(card)
                            .opacity(playable ? 1 : 0.4)
                            .scaleEffect(engine.selectedCard == card ? 1.08 : 1)
                            .onTapGesture { engine.tapHandCard(card) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(burgundy.opacity(0.15))
    }

    private func isPlayable(_ card: DurakCard) -> Bool {
        if engine.attacker == .white { return engine.isValidAttackCard(card) }
        if engine.defender == .white { return engine.isValidDefenseCard(card) }
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
        guard engine.winner == nil, !engine.isDraw else { return }
        let botShouldAct = (engine.defender == .black && engine.awaitingDefense)
            || (engine.attacker == .black && !engine.awaitingDefense)
        guard botShouldAct else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            engine.botActIfNeeded()
        }
    }
}

struct PremiumView: View {
    @ObservedObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    private let gold = Color(red: 0.82, green: 0.68, blue: 0.33)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(gold)
                    .padding(.top, 24)

                Text("Дурак Premium")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    featureRow("Без рекламы")
                    featureRow("Локальный мультиплеер по Wi-Fi/Bluetooth")
                    featureRow("Разовая покупка — навсегда")
                }
                .padding(.horizontal, 24)

                if store.isPremium {
                    Label("Premium уже активен", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await store.purchasePremium() }
                    } label: {
                        Text("Купить за \(store.priceText)")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(gold)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)

                    Button("Восстановить покупки") {
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
                    Button("Закрыть") { dismiss() }
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
