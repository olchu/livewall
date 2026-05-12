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

    @discardableResult
    func syncSettingsState(_ settings: SettingsStore = .shared) -> Bool {
        let enabled = isEnabled
        if settings.settings.startAtLogin != enabled {
            settings.settings.startAtLogin = enabled
        }
        return enabled
    }
}
