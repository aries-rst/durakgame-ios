import SwiftUI

// Tavern-card palette — burgundy felt, gold suit filigree.
// Distinct from Checkers (dark wood/brass), Nardy (ochre/copper/turquoise)
// and Domino (poster red/mustard/ink).
enum TavernPalette {
    static let burgundy = Color(red: 0.35, green: 0.05, blue: 0.10)
    static let gold = Color(red: 0.82, green: 0.68, blue: 0.25)
    static let cream = Color(red: 0.93, green: 0.88, blue: 0.80)
    static let shadow = Color(red: 0.10, green: 0.04, blue: 0.05)
}

struct ContentView: View {
    var body: some View {
        ZStack {
            TavernPalette.shadow.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("ДУРАК")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(TavernPalette.gold)
                Text("Турнир на выбывание · до 6 игроков")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(TavernPalette.cream.opacity(0.8))
                RoundedRectangle(cornerRadius: 12)
                    .fill(TavernPalette.burgundy)
                    .frame(width: 220, height: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(TavernPalette.gold, lineWidth: 3)
                    )
                    .overlay(Text("Board scaffold").foregroundStyle(TavernPalette.cream.opacity(0.5)))
            }
        }
    }
}

#Preview {
    ContentView()
}
