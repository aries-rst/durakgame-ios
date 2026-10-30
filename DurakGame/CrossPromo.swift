import SwiftUI

/// ARESTI Labs cross-promotion: a filtered "Больше игр" list of every other
/// app in the family, each linking out to its own App Store page. The
/// running app is excluded automatically by comparing against its own
/// bundle identifier — this file is byte-for-byte identical across all 7
/// apps (MyFamilyTree, MyOffice, ChessPuzzleDaily, Checkers, Nardy, Domino,
/// Durak), mirroring the Android portfolio's CrossPromo.kt pattern.
struct CrossPromoEntry: Identifiable {
    let id: String          // bundle identifier, doubles as self-exclusion key
    let name: String
    let subtitle: String
    let systemImage: String
    let appleID: Int        // numeric App Store Connect app id

    var storeURL: URL { URL(string: "https://apps.apple.com/app/id\(appleID)")! }
}

enum CrossPromoCatalog {
    static let allApps: [CrossPromoEntry] = [
        CrossPromoEntry(id: "com.aries-rst.myfamilytree.app", name: "My Family Tree", subtitle: "Генеалогическое древо", systemImage: "person.3.sequence.fill", appleID: 6812227993),
        CrossPromoEntry(id: "com.aries-rst.myoffice.app", name: "MyOffice", subtitle: "Оргструктура компании", systemImage: "building.2.fill", appleID: 6812275191),
        CrossPromoEntry(id: "com.aries-rst.chesspuzzledaily.app", name: "Шахматная задача дня", subtitle: "Головоломка каждый день", systemImage: "crown.fill", appleID: 6823191045),
        CrossPromoEntry(id: "com.aries-rst.checkersgame.app", name: "Checkers Club", subtitle: "Русские шашки", systemImage: "circle.grid.cross.fill", appleID: 6828566267),
        CrossPromoEntry(id: "com.aries-rst.nardygame.app", name: "Silk Road Backgammon", subtitle: "Длинные нарды", systemImage: "dice.fill", appleID: 6828567134),
        CrossPromoEntry(id: "com.aries-rst.dominogame.app", name: "Domino Yard", subtitle: "Классическое домино", systemImage: "square.grid.2x2.fill", appleID: 6828567655),
        CrossPromoEntry(id: "com.aries-rst.durakgame.app", name: "Дурак", subtitle: "Подкидной, 36 карт", systemImage: "suit.spade.fill", appleID: 6828567846),
    ]

    /// Every app except the one currently running (matched by its own Bundle ID).
    static var others: [CrossPromoEntry] {
        let myID = Bundle.main.bundleIdentifier ?? ""
        return allApps.filter { $0.id != myID }
    }
}

struct CrossPromoSection: View {
    let accent: Color
    let textColor: Color
    let cardFill: Color

    var body: some View {
        if !CrossPromoCatalog.others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Больше игр ARESTI Labs")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(textColor.opacity(0.7))
                    .padding(.horizontal, 4)

                VStack(spacing: 8) {
                    ForEach(CrossPromoCatalog.others) { app in
                        Link(destination: app.storeURL) {
                            HStack(spacing: 12) {
                                Image(systemName: app.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(textColor)
                                    Text(app.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(textColor.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(accent.opacity(0.8))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(cardFill)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }
}
