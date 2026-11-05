import SwiftUI

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

