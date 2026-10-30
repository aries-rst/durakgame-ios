import SwiftUI

struct ContentView: View {
    @StateObject private var store = StoreManager()
    @State private var showGame = false
    @State private var showPremium = false

    private let felt = Color(red: 0.08, green: 0.18, blue: 0.12)
    private let burgundy = Color(red: 0.42, green: 0.09, blue: 0.13)
    private let gold = Color(red: 0.82, green: 0.68, blue: 0.33)
    private let cream = Color(red: 0.95, green: 0.92, blue: 0.84)

    var body: some View {
        NavigationStack {
            ZStack {
                felt.ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "suit.spade.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(gold)
                        Text("ДУРАК")
                            .font(.system(size: 36, weight: .heavy, design: .serif))
                            .foregroundStyle(cream)
                            .tracking(6)
                        Text("Подкидной, 36 карт")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(gold.opacity(0.85))
                    }

                    VStack(spacing: 14) {
                        Button {
                            showGame = true
                        } label: {
                            menuLabel("Играть с ботом", system: "person.2.fill")
                        }

                        Button {
                            showPremium = true
                        } label: {
                            menuLabel(store.isPremium ? "Premium активен" : "Premium — \(store.priceText)", system: store.isPremium ? "crown.fill" : "crown")
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    Text(store.isPremium ? "Реклама отключена · Локальный мультиплеер открыт" : "Бесплатная версия · с рекламой")
                        .font(.footnote)
                        .foregroundStyle(cream.opacity(0.6))
                        .padding(.bottom, 24)
                }
            }
            .navigationDestination(isPresented: $showGame) {
                GameView(store: store)
            }
            .sheet(isPresented: $showPremium) {
                PremiumView(store: store)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func menuLabel(_ text: String, system: String) -> some View {
        HStack {
            Image(systemName: system)
            Text(text)
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
        }
        .foregroundStyle(cream)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(burgundy.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(gold.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

#Preview {
    ContentView()
}
