import SwiftUI
import Combine

final class AppLang: ObservableObject {
    static let shared = AppLang()
    @Published var isRussian: Bool {
        didSet { UserDefaults.standard.set(isRussian, forKey: "appIsRussian") }
    }
    private init() {
        isRussian = UserDefaults.standard.object(forKey: "appIsRussian") as? Bool ?? false
    }
}

func t(_ en: String, _ ru: String) -> String {
    AppLang.shared.isRussian ? ru : en
}
