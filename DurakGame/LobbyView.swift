import SwiftUI
import MultipeerConnectivity
import Foundation

/// Online "Play Nearby" lobby. The host picks a variant, how many seats the
/// table has (2–6), the bot difficulty for any unfilled seats, and the
/// throw-in mode, then advertises a real game card (host name + variant +
/// target player count) instead of a bare device-name list; up to
/// `players - 1` guests can browse that list and join. Unlike this
/// portfolio's Domino online lobby (which requires every seat to be a real
/// player), the host can tap "Start Game" at any time — any seats still
/// empty are filled by bots, exactly matching Android's
/// `startHostGame(guests)` (seats 1..k = guests, the rest = bots). Once
/// started, `NetworkGameEngine` runs the real `Durak`/`DurakMatch` engine
/// host-authoritatively over the network (see that file for the snapshot +
/// intent protocol).
struct MultiplayerLobbyView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject private var lang = AppLang.shared
    @StateObject private var multiplayer = MultiplayerManager(serviceType: "ar-durak")

    private enum Stage: Equatable {
        case choose
        case hostSetup
        case hostRoom
        case browse
        case guestWaiting // invited / connecting / connected, waiting for the host to start
    }

    @State private var stage: Stage = .choose
    @State private var hostVariant: DurakVariant = .podkidnoy
    @State private var hostPlayers: Int = 3
    @State private var hostLevel: Int = 2
    @State private var hostThrowAll: Bool = true
    @State private var engine: NetworkGameEngine? = nil
    @State private var startGame = false

    @Environment(\.dismiss) private var dismiss

    private let felt = Color(red: 0.08, green: 0.18, blue: 0.12)
    private let burgundy = Color(red: 0.42, green: 0.09, blue: 0.13)
    private let gold = Color(red: 0.82, green: 0.68, blue: 0.33)
    private let cream = Color(red: 0.95, green: 0.92, blue: 0.84)

    var body: some View {
        NavigationStack {
            ZStack {
                felt.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header

                        Group {
                            switch stage {
                            case .choose: chooseSection
                            case .hostSetup: hostSetupSection
                            case .hostRoom: hostRoomSection
                            case .browse: browseSection
                            case .guestWaiting: guestWaitingSection
                            }
                        }

                        if let err = multiplayer.errorMessage {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Close", "Закрыть")) {
                        multiplayer.stop()
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $startGame) {
                if let engine = engine {
                    NetworkGameView(store: store, engine: engine, multiplayer: multiplayer)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.system(size: 40))
                .foregroundStyle(gold)
                .padding(.top, 10)
            Text(t("Online Game", "Игра по сети"))
                .font(.title2.bold())
                .foregroundStyle(cream)
        }
    }

    // MARK: - Choose

    private var chooseSection: some View {
        VStack(spacing: 14) {
            Text(t("Host a game so nearby players can find and join it, or find a game that's already been created. Wi-Fi or Bluetooth required.", "Создайте игру, чтобы её нашли игроки рядом, либо найдите уже созданную игру. Нужны Wi-Fi или Bluetooth."))
                .font(.subheadline)
                .foregroundStyle(cream.opacity(0.7))
                .multilineTextAlignment(.center)

            Button { stage = .hostSetup } label: {
                lobbyButtonLabel(t("Host a Game", "Создать игру"), system: "antenna.radiowaves.left.and.right")
            }
            Button {
                multiplayer.startBrowsing()
                stage = .browse
            } label: {
                lobbyButtonLabel(t("Find Nearby Games", "Найти игры рядом"), system: "magnifyingglass")
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Host setup (variant + players + level + throw-in, before advertising)

    private var hostSetupSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Choose how the table is set up. Other seats fill with nearby players as they join, or with bots once you start.", "Настройте стол. Остальные места заполнят игроки рядом по мере подключения, либо боты, когда вы начнёте игру."))
                .font(.caption)
                .foregroundStyle(cream.opacity(0.75))

            VStack(alignment: .leading, spacing: 8) {
                Text(t("Variant", "Вариант")).font(.subheadline.bold()).foregroundStyle(cream)
                Picker("", selection: $hostVariant) {
                    Text(t("Throw-in", "Подкидной")).tag(DurakVariant.podkidnoy)
                    Text(t("Transfer", "Переводной")).tag(DurakVariant.perevodnoy)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(t("Players", "Игроков")).font(.subheadline.bold()).foregroundStyle(cream)
                Picker("", selection: $hostPlayers) {
                    ForEach(2...6, id: \.self) { n in Text("\(n)").tag(n) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(t("Bot difficulty (for empty seats)", "Сложность ботов (для пустых мест)")).font(.subheadline.bold()).foregroundStyle(cream)
                Picker("", selection: $hostLevel) {
                    Text(t("Easy", "Лёгкий")).tag(1)
                    Text(t("Medium", "Средний")).tag(2)
                    Text(t("Hard", "Сложный")).tag(3)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(t("Who can throw in", "Кто может подкидывать")).font(.subheadline.bold()).foregroundStyle(cream)
                Picker("", selection: $hostThrowAll) {
                    Text(t("Everyone", "Все")).tag(true)
                    Text(t("Neighbors only", "Только соседи")).tag(false)
                }
                .pickerStyle(.segmented)
            }

            Button {
                let info: [String: String] = [
                    "host": multiplayer.myDisplayName,
                    "variant": hostVariant.rawValue,
                    "players": "\(hostPlayers)"
                ]
                multiplayer.startHosting(info: info)
                stage = .hostRoom
            } label: {
                Text(t("Start Hosting", "Начать поиск игроков"))
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(burgundy)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button(t("Back", "Назад")) { stage = .choose }
                .font(.footnote)
                .foregroundStyle(cream.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Host room (advertising, waiting for players — or starting with bots)

    private var hostRoomSection: some View {
        VStack(spacing: 16) {
            Text(t("Waiting for players (\(multiplayer.connectedPeers.count + 1)/\(hostPlayers))…", "Ждём игроков (\(multiplayer.connectedPeers.count + 1)/\(hostPlayers))…"))
                .font(.subheadline)
                .foregroundStyle(cream.opacity(0.8))

            VStack(spacing: 8) {
                seatCard(name: multiplayer.myDisplayName, label: t("Host (you)", "Хост (вы)"), filled: true)
                ForEach(1..<hostPlayers, id: \.self) { i in
                    if i - 1 < multiplayer.connectedPeers.count {
                        seatCard(name: multiplayer.connectedPeers[i - 1].displayName, label: t("Seat \(i)", "Место \(i)"), filled: true)
                    } else {
                        seatCard(name: t("Bot (if unfilled)", "Бот (если не займут)"), label: t("Seat \(i)", "Место \(i)"), filled: false)
                    }
                }
            }

            Button { startHostedGame() } label: {
                Text(t("Start Game", "Начать игру"))
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(burgundy)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button(t("Cancel", "Отмена")) {
                multiplayer.stop()
                stage = .choose
            }
            .font(.footnote)
            .foregroundStyle(cream.opacity(0.6))
        }
    }

    private func seatCard(name: String, label: String, filled: Bool) -> some View {
        HStack {
            Image(systemName: filled ? "person.fill" : "person.dashed")
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(label).font(.caption2)
            }
            Spacer()
        }
        .foregroundStyle(cream.opacity(filled ? 1 : 0.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(filled ? 0.5 : 0.2), lineWidth: 1))
        )
    }

    /// Host taps "Start Game": seats are the host (seat 0), every connected
    /// guest in join order (seat 1, 2, 3…), and — unlike Domino's online
    /// mode — any seats still empty are filled by bots, so starting never
    /// has to wait for a full room.
    private func startHostedGame() {
        let humanNames = [multiplayer.myDisplayName] + multiplayer.connectedPeers.map { $0.displayName }
        var seatNames: [String] = []
        var botSeats: [Bool] = []
        for i in 0..<hostPlayers {
            if i < humanNames.count {
                seatNames.append(humanNames[i])
                botSeats.append(false)
            } else {
                seatNames.append("\(t("Bot", "Бот")) \(i)")
                botSeats.append(true)
            }
        }
        let e = NetworkGameEngine(multiplayer: multiplayer, isHost: true, variant: hostVariant, throwAll: hostThrowAll, seatNames: seatNames, botSeats: botSeats)
        multiplayer.stopHostDiscovery()
        engine = e
        startGame = true
    }

    // MARK: - Browse (guest): a real game-card list, not a bare name list

    private var browseSection: some View {
        VStack(spacing: 14) {
            if multiplayer.availablePeers.isEmpty {
                Text(t("Searching for nearby games…", "Поиск игр рядом…"))
                    .font(.subheadline)
                    .foregroundStyle(cream.opacity(0.7))
            } else {
                VStack(spacing: 10) {
                    ForEach(multiplayer.availablePeers, id: \.self) { peer in
                        gameCard(peer)
                    }
                }
            }
            Button(t("Cancel", "Отмена")) {
                multiplayer.stop()
                stage = .choose
            }
            .font(.footnote)
            .foregroundStyle(cream.opacity(0.6))
        }
    }

    private func gameCard(_ peer: MCPeerID) -> some View {
        let info = multiplayer.discoveredGames[peer] ?? [:]
        let hostName = info["host"] ?? peer.displayName
        let variant = info["variant"]
        let players = info["players"]
        return Button {
            joinGame(peer)
        } label: {
            HStack {
                Image(systemName: "gamecontroller.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(hostName).font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        if let variant = variant { Text(variantLabel(variant)) }
                        if let players = players { Text("· \(t("\(players) players", "\(players) игроков"))") }
                    }
                    .font(.caption2)
                    .foregroundStyle(cream.opacity(0.6))
                }
                Spacer()
                Text(t("Join", "Войти")).font(.caption.weight(.semibold))
            }
            .foregroundStyle(cream)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.5), lineWidth: 1))
            )
        }
    }

    private func variantLabel(_ id: String) -> String {
        switch id {
        case DurakVariant.podkidnoy.rawValue: return t("Throw-in", "Подкидной")
        case DurakVariant.perevodnoy.rawValue: return t("Transfer", "Переводной")
        default: return id
        }
    }

    /// Guest taps a game card: before the match (and this guest's own
    /// `NetworkGameEngine`) exists, the lobby itself listens just long
    /// enough to catch the host's first broadcast (`OnlineMessage.start`),
    /// which is all it needs to build the engine and resolve this device's
    /// own seat — after that, the engine takes over `onReceive` itself.
    private func joinGame(_ peer: MCPeerID) {
        stage = .guestWaiting
        multiplayer.onReceive = { data in
            guard let msg = try? JSONDecoder().decode(OnlineMessage.self, from: data), let start = msg.start else { return }
            DispatchQueue.main.async {
                guard self.engine == nil else { return }
                let variant = DurakVariant(rawValue: start.variant) ?? .podkidnoy
                let e = NetworkGameEngine(multiplayer: multiplayer, isHost: false, variant: variant, throwAll: start.throwAll, seatNames: start.seatNames, botSeats: start.botSeats)
                e.ingestInitial(msg)
                self.engine = e
                self.startGame = true
            }
        }
        multiplayer.invite(peer)
    }

    // MARK: - Guest waiting room

    private var guestWaitingSection: some View {
        VStack(spacing: 14) {
            Text(guestStatusText)
                .font(.subheadline)
                .foregroundStyle(cream.opacity(0.7))
                .multilineTextAlignment(.center)
            Button(t("Cancel", "Отмена")) {
                multiplayer.stop()
                stage = .choose
            }
            .font(.footnote)
            .foregroundStyle(cream.opacity(0.6))
        }
    }

    private var guestStatusText: String {
        switch multiplayer.state {
        case .connecting:
            return t("Connecting…", "Подключение…")
        case .connected(let name):
            return t("Connected to \(name). Waiting for the host to start the game…", "Подключено к \(name). Ждём, когда хост начнёт игру…")
        default:
            return t("Connecting…", "Подключение…")
        }
    }

    // MARK: - Shared

    private func lobbyButtonLabel(_ text: String, system: String) -> some View {
        HStack {
            Image(systemName: system)
            Text(text).fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }
        .foregroundStyle(cream)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(gold.opacity(0.5), lineWidth: 1))
        )
    }
}
