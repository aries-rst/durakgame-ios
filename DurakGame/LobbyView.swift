import SwiftUI
import MultipeerConnectivity

struct MultiplayerLobbyView: View {
    @ObservedObject var store: StoreManager
    @StateObject private var multiplayer = MultiplayerManager(serviceType: "ar-durak")
    @State private var myColor: DurakPlayer = .white
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
                VStack(spacing: 20) {
                    Image(systemName: "wifi")
                        .font(.system(size: 40))
                        .foregroundStyle(gold)
                        .padding(.top, 20)

                    Text("Игра по сети")
                        .font(.title2.bold())
                        .foregroundStyle(cream)

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(cream.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if multiplayer.role == .none {
                        VStack(spacing: 14) {
                            Button {
                                myColor = .white
                                multiplayer.startHosting()
                            } label: {
                                lobbyButtonLabel("Создать игру", system: "antenna.radiowaves.left.and.right")
                            }
                            Button {
                                myColor = .black
                                multiplayer.startBrowsing()
                            } label: {
                                lobbyButtonLabel("Найти игру рядом", system: "magnifyingglass")
                            }
                        }
                        .padding(.horizontal, 32)
                    }

                    if multiplayer.role == .guest {
                        List(multiplayer.availablePeers, id: \.self) { peer in
                            Button {
                                multiplayer.invite(peer)
                            } label: {
                                HStack {
                                    Image(systemName: "iphone")
                                    Text(peer.displayName)
                                    Spacer()
                                    Text("Пригласить").font(.caption)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxHeight: 240)
                        .scrollContentBackground(.hidden)
                    }

                    if multiplayer.role != .none {
                        Button("Отмена") {
                            multiplayer.stop()
                        }
                        .font(.footnote)
                        .foregroundStyle(cream.opacity(0.6))
                    }

                    if let err = multiplayer.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }

                    Spacer()
                }
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        multiplayer.stop()
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $startGame) {
                GameView(store: store, multiplayer: multiplayer, localColor: myColor)
            }
            .onChange(of: multiplayer.state) { state in
                if case .connected = state {
                    startGame = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }

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

    private var statusText: String {
        switch multiplayer.state {
        case .idle:
            return "Создайте игру, чтобы вас нашёл соперник рядом, либо найдите уже созданную игру. Нужны Wi-Fi или Bluetooth."
        case .hosting:
            return "Ожидание соперника… Другой игрок должен открыть эту игру и нажать «Найти игру рядом»."
        case .browsing:
            return multiplayer.availablePeers.isEmpty ? "Поиск игр рядом…" : "Выберите игру из списка."
        case .connecting:
            return "Подключение…"
        case .connected(let name):
            return "Подключено к \(name). Начинаем игру…"
        }
    }
}
