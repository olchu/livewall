import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "com.ochurkin.LiveWall.settings"

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
