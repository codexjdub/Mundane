import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var clock: Clock!
    private var settings: Settings!
    private var state: ViewState!
    private var statusItem: StatusItemController!
    private var panel: MundanePanel!
    private var hotkeys: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        clock = Clock()
        settings = Settings()
        state = ViewState(clock: clock, settings: settings)
        statusItem = StatusItemController(style: settings.dateStyle, date: clock.today)
        clock.onDayChange = { [weak self] in
            guard let self else { return }
            statusItem.update(date: clock.today)
        }

        applyTheme()

        panel = MundanePanel(state: state)
        panel.delegate = self

        hotkeys = HotkeyManager()
        hotkeys.onTrigger = { [weak self] in self?.togglePanel() }
        if !hotkeys.register(settings.hotkey) {
            // Another app owns it now. Drop it rather than advertising a
            // shortcut in the menu that will never fire.
            settings.hotkey = nil
        }

        if let button = statusItem.item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        if ProcessInfo.processInfo.environment["MUNDANE_SELFTEST"] != nil {
            runSelfTest()
        }
    }

    /// Drives a real open-and-switch sequence and reports where the panel lands,
    /// so positioning can be checked without a human clicking.
    private func runSelfTest() {
        selfTesting = true
        let modes: [ViewMode] = [.month, .threeMonths, .year, .month]
        var step = 0
        func emit(_ s: String) {
            FileHandle.standardError.write(s.data(using: .utf8)!)
            if let path = ProcessInfo.processInfo.environment["MUNDANE_SELFTEST_LOG"] {
                if let h = FileHandle(forWritingAtPath: path) {
                    h.seekToEndOfFile(); h.write(s.data(using: .utf8)!); try? h.close()
                } else {
                    try? s.write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
        }
        func report(_ label: String) {
            let visible = NSScreen.main?.visibleFrame ?? .zero
            let f = panel.frame
            let cardL = f.minX + Layout.stampMargin
            let cardR = f.maxX - Layout.stampMargin
            let seal = cardR + Sizing(settings.size).hankoOverhang
            // isVisible is part of the assertion: these numbers are meaningless
            // for a window that was ordered out.
            let ok = panel.isVisible && cardL >= visible.minX && seal <= visible.maxX
            emit(String(
                format: "%-12@ window %.0f…%.0f  card %.0f…%.0f  seal %.0f  screen %.0f…%.0f  %@\n",
                label as NSString, f.minX, f.maxX, cardL, cardR, seal,
                visible.minX, visible.maxX,
                (ok ? "ON SCREEN" : (panel.isVisible ? "*** OFF SCREEN ***"
                                                      : "*** NOT VISIBLE ***")) as NSString))
        }
        func next() {
            guard step < modes.count else {
                if let button = statusItem.item.button, let window = button.window {
                    emit(String(format: "menu bar item %.0f pt for \"%@\"\n",
                                window.frame.width, button.title as NSString))
                }
                // HOLD keeps the panel on screen so memory can be measured with it open
                if ProcessInfo.processInfo.environment["MUNDANE_SELFTEST_HOLD"] == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
                }
                return
            }
            let mode = modes[step]; step += 1
            if step == 2 {
                exerciseKeyboard()
                // exerciseKeyboard ends on esc, which orders the panel out. Without
                // this the remaining positioning reports measure a hidden window
                // and "ON SCREEN" means nothing.
                if let button = statusItem.item.button { panel.show(under: button) }
            }
            if step == 1, let button = statusItem.item.button {
                state.goToToday(); panel.show(under: button)
            }
            state.mode = mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                report(String(describing: mode)); next()
            }
        }
        let s = SMAppService.mainApp.status
        let name: String
        switch s {
        case .notRegistered:    name = "notRegistered"
        case .enabled:          name = "enabled"
        case .requiresApproval: name = "requiresApproval"
        case .notFound:         name = "notFound"
        @unknown default:       name = "unknown(\(s.rawValue))"
        }
        emit("launch-at-login status: \(name)  bundle=\(Bundle.main.bundleURL.path)\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next() }
    }

    /// Sends real key events through the window, so the responder path is tested
    /// rather than just the handler.
    private func exerciseKeyboard() {
        let cal = MonthMeta.calendar
        func press(_ code: UInt16) {
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                           modifierFlags: [], timestamp: 0,
                                           windowNumber: panel.windowNumber, context: nil,
                                           characters: "", charactersIgnoringModifiers: "",
                                           isARepeat: false, keyCode: code) else { return }
            panel.sendEvent(e)
        }
        func line(_ label: String, _ ok: Bool) {
            FileHandle.standardError.write("  key \(label): \(ok ? "ok" : "FAIL")\n"
                .data(using: .utf8)!)
        }
        state.goToToday()
        let start = state.anchor

        press(124)   // →
        line("→ pages forward", cal.compare(state.anchor, to: start, toGranularity: .month) == .orderedDescending)
        press(123)   // ←
        line("← pages back", cal.isDate(state.anchor, equalTo: start, toGranularity: .month))
        press(49)    // space
        line("space returns to today", state.isShowingToday)
        let startMode = state.mode
        press(48)    // tab
        line("tab moves to the next view", state.mode != startMode)
        press(48); press(48)
        line("tab wraps back around", state.mode == startMode)

        press(53)    // esc
        line("esc closes the panel", !panel.isVisible)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu { showMenu(from: sender) } else { togglePanel() }
    }

    /// When the panel was last hidden, used to tell a genuine "open" click from
    /// the second half of a "close" click.
    private var hiddenAt: Date?

    /// True for the length of a self-test run. The panel normally hides the
    /// moment it loses key, which is right for a person and wrong for a test:
    /// any app that came forward mid-run hid it and failed that step at random,
    /// and could make "esc closes the panel" pass on a panel that was already
    /// gone. The run sends its key events straight to the panel, so nothing in
    /// it needs the panel to be key.
    private var selfTesting = false

    private func togglePanel() {
        // Clicking the status item makes the panel resign key during mouse-down,
        // and the action fires on mouse-up — so by the time we get here the panel
        // has already been hidden by windowDidResignKey. Without this window, the
        // click that should close the panel reopens it and it can never be closed
        // from the icon.
        let justHidden = Date().timeIntervalSince(hiddenAt ?? .distantPast) < 0.25
        guard !panel.isVisible, !justHidden else {
            hidePanel()
            return
        }
        guard let button = statusItem.item.button else { return }
        state.goToToday()              // always open on the current period
        panel.show(under: button)
    }

    private func hidePanel() {
        guard panel.isVisible else { return }   // idempotent: esc also re-enters here
        panel.orderOut(nil)
        hiddenAt = Date()
    }

    // Dismiss when the user clicks away.
    func windowDidResignKey(_ notification: Notification) {
        // Only our panel. Nothing else is delegated to us today, but an alert or
        // a future window would otherwise hide the calendar behind the user's back.
        guard notification.object as? NSWindow === panel, !selfTesting else { return }
        hidePanel()
    }

    // MARK: - Right-click menu

    /// One builder for the three option submenus. They were the same eleven
    /// lines three times, so any fix to checkmark handling or item order had to
    /// be made three times or it silently applied to only one menu.
    private func optionSubmenu<T>(_ title: String, current: T,
                                  label: (T) -> String,
                                  action: Selector) -> NSMenuItem
        where T: CaseIterable & RawRepresentable & Equatable, T.RawValue == String {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for option in T.allCases {
            let item = NSMenuItem(title: label(option), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == current ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    /// The matching unwrap, also written out three times before.
    private func selection<T: RawRepresentable>(_ sender: NSMenuItem) -> T?
        where T.RawValue == String {
        (sender.representedObject as? String).flatMap(T.init(rawValue:))
    }

    private func showMenu(from button: NSStatusBarButton) {
        hidePanel()
        let menu = NSMenu()

        menu.addItem(optionSubmenu("Menu Bar Format", current: settings.dateStyle,
                                   // rendered with today's date, so the menu
                                   // previews exactly what you would get
                                   label: { $0.string(for: self.clock.today) },
                                   action: #selector(selectStyle(_:))))

        let life = NSMenuItem(title: "Life Progress\u{2026}",
                              action: #selector(editLifeProgress(_:)),
                              keyEquivalent: "")
        life.target = self
        life.state = settings.birthYear == nil ? .off : .on
        menu.addItem(life)

        let shortcutTitle = settings.hotkey.map { "Keyboard Shortcut (\($0.display))\u{2026}" }
            ?? "Keyboard Shortcut\u{2026}"
        let shortcut = NSMenuItem(title: shortcutTitle,
                                  action: #selector(editHotkey(_:)), keyEquivalent: "")
        shortcut.target = self
        menu.addItem(shortcut)

        menu.addItem(optionSubmenu("Size", current: settings.size,
                                   label: \.label, action: #selector(selectSize(_:))))

        menu.addItem(optionSubmenu("Theme", current: settings.theme,
                                   label: \.label, action: #selector(selectTheme(_:))))

        let login = NSMenuItem(title: settings.launchAtLoginNeedsApproval
                                   ? "Launch at Login (needs approval)"
                                   : "Launch at Login",
                               action: #selector(toggleLaunchAtLogin(_:)),
                               keyEquivalent: "")
        login.target = self
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mundane",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 5),
                   in: button)
    }

    @objc private func editLifeProgress(_ sender: NSMenuItem) {
        let thisYear = MonthMeta.calendar.component(.year, from: clock.today)

        let alert = NSAlert()
        alert.messageText = "Life progress"
        alert.informativeText = "Enter your birth year. The bar assumes a span of "
            + "\(LifeProgress.assumedSpan) years."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "\(thisYear - 30)"
        if let year = settings.birthYear { field.stringValue = String(year) }
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Turn Off")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate()
        alert.window.initialFirstResponder = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let typed = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard let year = Int(typed),
                  LifeProgress(birthYear: year, on: clock.today) != nil else {
                present(title: "That doesn't look like a birth year",
                        body: "Enter a year between \(LifeProgress.earliestYear) "
                            + "and \(thisYear).")
                return
            }
            settings.birthYear = year
        case .alertSecondButtonReturn:
            settings.birthYear = nil
        default:
            break
        }
    }

    private func applyTheme() {
        // Setting it on NSApp rather than the panel so menus and alerts follow too.
        NSApp.appearance = settings.theme.appearance
    }

    @objc private func editHotkey(_ sender: NSMenuItem) {
        let previous = settings.hotkey
        // Release the installed hotkey first. Otherwise pressing your current
        // combo in the recorder fires the shortcut underneath the modal — the
        // panel opens over the alert and nothing is captured.
        hotkeys.register(nil)

        let alert = NSAlert()
        alert.messageText = "Keyboard shortcut"
        alert.informativeText = "Press the keys you want to use for opening Mundane. "
            + "A modifier is required. Press delete to clear it."
        let recorder = HotkeyRecorderView(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        recorder.combo = settings.hotkey
        alert.accessoryView = recorder
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate()
        alert.window.initialFirstResponder = recorder
        guard alert.runModal() == .alertFirstButtonReturn else {
            hotkeys.register(previous)     // cancelled — put the old one back
            return
        }

        guard hotkeys.register(recorder.combo) else {
            hotkeys.register(previous)
            present(title: "That shortcut isn't available",
                    body: "\(recorder.combo?.display ?? "It") is already used by "
                        + "macOS or another app. Your previous shortcut is unchanged.")
            return
        }
        settings.hotkey = recorder.combo
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let option: SizeOption = selection(sender) else { return }
        settings.size = option
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let theme: Theme = selection(sender) else { return }
        settings.theme = theme
        applyTheme()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enabling = !settings.launchAtLogin
        do {
            let status = try settings.setLaunchAtLogin(enabling)
            if enabling, status == .requiresApproval { promptForLoginApproval() }
        } catch {
            present(title: enabling ? "Couldn't enable launch at login"
                                    : "Couldn't disable launch at login",
                    body: error.localizedDescription)
        }
    }

    private func promptForLoginApproval() {
        let alert = NSAlert()
        alert.messageText = "Approval needed"
        alert.informativeText = "macOS needs you to allow Mundane under Login Items "
            + "before it will start automatically."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func present(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let style: DateStyle = selection(sender) else { return }
        settings.dateStyle = style
        statusItem.style = style
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
