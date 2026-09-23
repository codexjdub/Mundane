import AppKit
import Carbon.HIToolbox

/// A global shortcut, stored as a Carbon key code plus modifier mask.
///
/// `display` is captured at record time rather than derived later: turning a key
/// code back into a character means going through the current keyboard layout,
/// and storing what the user actually pressed is both simpler and more honest.
struct HotkeyCombo: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var mask: UInt32 = 0
        var label = ""
        if flags.contains(.control) { mask |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option)  { mask |= UInt32(optionKey);  label += "⌥" }
        if flags.contains(.shift)   { mask |= UInt32(shiftKey);   label += "⇧" }
        if flags.contains(.command) { mask |= UInt32(cmdKey);     label += "⌘" }

        // A bare key would swallow that key system-wide, so require a modifier.
        guard mask != 0 else { return nil }

        keyCode = UInt32(event.keyCode)
        modifiers = mask
        display = label + Self.keyLabel(for: event)
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, display }

    /// Re-applies the required-modifier rule on the way in. The synthesized
    /// decoder would happily accept `modifiers: 0`, which registers a bare key
    /// system-wide — exactly what `init?(event:)` refuses to build.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        modifiers = try container.decode(UInt32.self, forKey: .modifiers)
        display = try container.decode(String.self, forKey: .display)
        guard modifiers != 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .modifiers, in: container,
                debugDescription: "a hotkey must carry at least one modifier")
        }
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// Registers a system-wide hotkey.
///
/// Carbon's RegisterEventHotKey rather than NSEvent's global monitor: the monitor
/// needs Accessibility permission and sees every keystroke on the machine, which
/// is far more access than one shortcut warrants. This asks for nothing.
final class HotkeyManager {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() { installHandler() }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Returns false when the system refused the combo — typically because
    /// another app already owns it. The caller must not persist a combo that
    /// failed, or the menu advertises a shortcut that does nothing.
    @discardableResult
    func register(_ combo: HotkeyCombo?) -> Bool {
        unregister()
        guard let combo else { return true }

        let id = EventHotKeyID(signature: OSType(0x4D554E44), id: 1)   // 'MUND'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return false }
        hotKeyRef = ref
        return true
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    fileprivate func fire() { onTrigger?() }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}

private func hotkeyHandler(_ next: EventHandlerCallRef?,
                           _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire()
    return noErr
}

/// Captures the next keystroke. Plain AppKit — a SwiftUI recorder would need
/// @State, which Command Line Tools cannot compile.
final class HotkeyRecorderView: NSView {
    var combo: HotkeyCombo? { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 30) }

    override func keyDown(with event: NSEvent) {
        guard capture(event) else {
            // Let the alert have Return, Escape and Tab.
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Claim combos like ⌘Q so they are recorded rather than performed — but
        // only ones we can actually record. Returning true unconditionally ate
        // the alert's own Return and Escape equivalents, leaving the sheet
        // dismissable by mouse alone.
        guard window?.firstResponder === self else { return false }
        return capture(event)
    }

    /// True when the event was consumed as a shortcut (or as a clear).
    private func capture(_ event: NSEvent) -> Bool {
        if event.keyCode == 51 || event.keyCode == 117 {   // delete / fwd delete
            combo = nil
            return true
        }
        guard let captured = HotkeyCombo(event: event) else { return false }
        combo = captured
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                               xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill(); box.fill()
        (window?.firstResponder === self ? NSColor.controlAccentColor
                                         : NSColor.separatorColor).setStroke()
        box.lineWidth = window?.firstResponder === self ? 2 : 1
        box.stroke()

        let text = combo?.display ?? "Press a shortcut…"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: combo == nil ? NSColor.secondaryLabelColor : NSColor.labelColor]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: bounds.midX - size.width / 2,
                           y: bounds.midY - size.height / 2))
    }
}
