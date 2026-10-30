import Foundation
import StoreKit

@MainActor
final class StoreManager: ObservableObject {
    static let premiumProductID = "com.ariesrst.durakgame.app.premium"

    @Published var isPremium: Bool = UserDefaults.standard.bool(forKey: "isPremium")
    @Published var products: [Product] = []
    @Published var isLoadingProducts = false
    @Published var purchaseErrorMessage: String? = nil

    private var updatesTask: Task<Void, Never>? = nil

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
        Task { await loadProducts() }
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: [Self.premiumProductID])
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func purchasePremium() async {
        guard let product = products.first(where: { $0.id == Self.premiumProductID }) else {
            await loadProducts()
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        if transaction.productID == Self.premiumProductID {
            setPremium(true)
        }
        await transaction.finish()
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.premiumProductID {
                setPremium(true)
            }
        }
    }

    private func setPremium(_ value: Bool) {
        isPremium = value
        UserDefaults.standard.set(value, forKey: "isPremium")
    }

    var priceText: String {
        products.first(where: { $0.id == Self.premiumProductID })?.displayPrice ?? "$1.99"
    }
}
