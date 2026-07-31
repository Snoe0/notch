import ServiceManagement

/// Thin wrapper over SMAppService so the menu does not import ServiceManagement.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Notch: could not change login item — \(error.localizedDescription)")
        }
    }
}
