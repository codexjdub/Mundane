import AppKit

/// Keys the panel responds to while it is open.
enum PanelKey {
    case dismiss, prev, next, today, nextView

    /// Only bare keys act. Without this, cmd-left paged the calendar and
    /// shift-tab cycled the view — behaviour that was deliberately cut.
    ///
    /// Note the mask lists the four intent modifiers rather than using
    /// `.deviceIndependentFlagsMask`: arrow keys always carry `.function` and
    /// `.numericPad`, so requiring *no* flags at all would disable them.
    init?(event: NSEvent) {
        let intent: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(intent).isEmpty else { return nil }
        self.init(keyCode: event.keyCode)
    }

    init?(keyCode: UInt16) {
        switch keyCode {
        case 53:  self = .dismiss   // esc
        case 123: self = .prev      // ←
        case 124: self = .next      // →
        case 49:  self = .today     // space
        case 48:  self = .nextView  // tab
        default:  return nil
        }
    }
}
