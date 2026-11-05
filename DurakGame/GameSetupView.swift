import SwiftUI

/// Setup sheet reachable from "Play vs Bot" on ContentView: variant,
/// player count (2–6), bot difficulty, and throw-in mode — the same four
/// choices Android's unified `MenuScreen` exposes inline. Remembers the
/// last choice via `DurakGameOptions`.
struct GameSetupView: View {
    @ObservedObject private var lang = AppLang.shared
    @Binding var options: DurakGameOptions
    var onPlay: () -> Void

    private let felt = Color(red: 0.08, green: 0.18, blue: 0.12)
    private let burgundy = Color(red: 0.42, green: 0.09, blue: 0.13)
    private let gold = Color(red: 0.82, green: 0.68, blue: 0.33)
    private let cream = Color(red: 0.95, green: 0.92, blue: 0.84)

    var body: some View {
        NavigationStack {
            ZStack {
                felt.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        variantPicker
                        Text(variantHelp)
                            .font(.caption)
                            .foregroundStyle(cream.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)

                        playersPicker
                        levelPicker
                        throwAllPicker

                        Button(action: {
                            options.save()
                            onPlay()
                        }) {
                            Text(t("Play", "Играть"))
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(burgundy)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(t("New Game", "Новая игра"))
        }
        .preferredColorScheme(.dark)
    }

    private var variantPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Variant", "Вариант")).font(.subheadline.bold()).foregroundStyle(cream)
            Picker("", selection: $options.variant) {
                Text(t("Throw-in", "Подкидной")).tag(DurakVariant.podkidnoy)
                Text(t("Transfer", "Переводной")).tag(DurakVariant.perevodnoy)
            }
            .pickerStyle(.segmented)
        }
    }

    private var variantHelp: String {
        switch options.variant {
        case .podkidnoy:
            return t("Can't beat an attack? Take all the cards on the table into your hand. While any attack is undefended, other players may throw in more cards of a rank already on the table.", "Не можете отбиться — берёте все карты со стола себе в руку. Пока атака не отбита, остальные могут подкидывать карты того же достоинства, что уже на столе.")
        case .perevodnoy:
            return t("Same as throw-in, but before defending a single card you may transfer the whole table — if every card on it is the same rank — to the next player, who becomes the new defender.", "Как подкидной, но пока не отбили ни одной карты можно перевести весь стол — если все карты на нём одного достоинства — следующему игроку, который станет новым защищающимся.")
        }
    }

    private var playersPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Players", "Игроков")).font(.subheadline.bold()).foregroundStyle(cream)
            Picker("", selection: $options.players) {
                ForEach(2...6, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Difficulty", "Сложность")).font(.subheadline.bold()).foregroundStyle(cream)
            Picker("", selection: $options.botLevel) {
                Text(t("Easy", "Лёгкий")).tag(1)
                Text(t("Medium", "Средний")).tag(2)
                Text(t("Hard", "Сложный")).tag(3)
            }
            .pickerStyle(.segmented)
        }
    }

    private var throwAllPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Who can throw in", "Кто может подкидывать")).font(.subheadline.bold()).foregroundStyle(cream)
            Picker("", selection: $options.throwAll) {
                Text(t("Everyone", "Все")).tag(true)
                Text(t("Neighbors only", "Только соседи")).tag(false)
            }
            .pickerStyle(.segmented)
        }
    }
}

#Preview {
    GameSetupView(options: .constant(DurakGameOptions()), onPlay: {})
}
