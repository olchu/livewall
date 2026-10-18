import Foundation
import ServiceManagement

final class LoginItemManager {
    static let shared = LoginItemManager()

    private init() {}

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    /// Toggle the login item, then re-sync the persisted setting from the real
    /// status — on failure too, so the UI never shows a state that didn't apply.
    func setEnabled(_ enabled: Bool, syncing settings: SettingsStore) throws {
        defer { syncSettingsState(settings) }
        try setEnabled(enabled)
    }

    @discardableResult
    func syncSettingsState(_ settings: SettingsStore = .shared) -> Bool {
        let enabled = isEnabled
        if settings.settings.startAtLogin != enabled {
            settings.settings.startAtLogin = enabled
        }
        return enabled
    }
}
