import AppKit
import Foundation
import Observation
import ServiceManagement

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    /// nil means "inherit", which is what makes System follow the OS.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }
}

/// Persisted preferences. Small enough that UserDefaults is the whole story.
@Observable
final class Settings {
    private static let dateStyleKey = "dateStyle"
    private static let themeKey = "theme"
    private static let birthYearKey = "birthYear"
    private static let sizeKey = "size"
    private static let hotkeyKey = "hotkey"

    var dateStyle: DateStyle {
        didSet {
            guard dateStyle != oldValue else { return }
            UserDefaults.standard.set(dateStyle.rawValue, forKey: Self.dateStyleKey)
        }
    }

    var theme: Theme {
        didSet {
            guard theme != oldValue else { return }
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
        }
    }

    /// nil means the life bar is off. There is no separate on/off flag — having a
    /// birth year is what enables it.
    var birthYear: Int? {
        didSet {
            guard birthYear != oldValue else { return }
            if let birthYear {
                UserDefaults.standard.set(birthYear, forKey: Self.birthYearKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.birthYearKey)
            }
        }
    }

    var size: SizeOption {
        didSet {
            guard size != oldValue else { return }
            UserDefaults.standard.set(size.rawValue, forKey: Self.sizeKey)
        }
    }

    var hotkey: HotkeyCombo? {
        didSet {
            guard hotkey != oldValue else { return }
            if let hotkey, let data = try? JSONEncoder().encode(hotkey) {
                UserDefaults.standard.set(data, forKey: Self.hotkeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.hotkeyKey)
            }
        }
    }

    init() {
        let storedHotkey = UserDefaults.standard.data(forKey: Self.hotkeyKey)
        hotkey = storedHotkey.flatMap { try? JSONDecoder().decode(HotkeyCombo.self, from: $0) }
        let storedSize = UserDefaults.standard.string(forKey: Self.sizeKey)
        size = storedSize.flatMap(SizeOption.init(rawValue:)) ?? .medium
        // Validate through LifeProgress itself, so the load path can't accept a
        // year the write path rejects — that left the menu item ticked with no
        // bar rendered and no way to diagnose it.
        let storedBirthYear = UserDefaults.standard.integer(forKey: Self.birthYearKey)
        birthYear = LifeProgress(birthYear: storedBirthYear, on: Date()) != nil
            ? storedBirthYear : nil
        let style = UserDefaults.standard.string(forKey: Self.dateStyleKey)
        dateStyle = style.flatMap(DateStyle.init(rawValue:)) ?? .monthDot
        let stored = UserDefaults.standard.string(forKey: Self.themeKey)
        theme = stored.flatMap(Theme.init(rawValue:)) ?? .system
    }

    /// Deliberately not mirrored into UserDefaults: the system owns this state and
    /// the user can change it from System Settings behind our back, so asking
    /// SMAppService every time is the only way to stay truthful.
    ///
    /// This is also why the app is signed with a stable certificate rather than
    /// ad-hoc — ad-hoc re-signing changes identity on every build, and the
    /// registration is tied to that identity.
    /// Registered counts as on, including while macOS is still waiting for the
    /// user to approve it. Treating `.requiresApproval` as off meant the toggle
    /// tried to register an already-registered service — which throws — and left
    /// no path to `unregister()`, so the user could neither tick the box nor
    /// remove the login item from inside the app.
    var launchAtLogin: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    var launchAtLoginNeedsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Returns the resulting status, so the caller can tell the user when macOS
    /// wants approval before the change takes effect.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) throws -> SMAppService.Status {
        let service = SMAppService.mainApp
        if enabled { try service.register() } else { try service.unregister() }
        return service.status
    }
}
