import Foundation
import CoreGraphics
import ApplicationServices
import Carbon

/// Listen-only global keyboard monitor.
///
/// It exists solely to feed `KeystrokeWordCounter`. It never reads modifier
/// combinations for content, never runs while Secure Input is active, and the
/// captured characters are never retained beyond the counter's session buffer.
public final class KeystrokeMonitor {
    /// Receives normalized keystrokes. Called on the main thread.
    public var onInput: ((KeystrokeInput) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    public init() {}

    /// True while macOS Secure Input is active (e.g. a password field).
    public static var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }

    /// Keyboard events require Accessibility permission.
    public var isAvailable: Bool { AXIsProcessTrusted() }

    public var isCapturing: Bool { isRunning }

    public func start() {
        guard !isRunning else { return }
        guard isAvailable else {
            Log.permissions.debug("Keystroke word counting unavailable: Accessibility not granted")
            return
        }
        guard let tap = Self.createTap(userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.integrations.error("Failed to create keyboard event tap")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        Log.tracking.info("Keystroke word-count estimation enabled (in-memory only)")
    }

    public func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        case .keyDown:
            break
        default:
            return
        }

        // Never observe anything while a secure field (e.g. a password) is active.
        guard !Self.isSecureInputEnabled else { return }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case 51: // Delete (backspace)
            if flags.contains(.maskCommand) {
                onInput?(.deleteToLineStart)
            } else if flags.contains(.maskAlternate) {
                onInput?(.deleteWordBackward)
            } else {
                onInput?(.deleteBackward)
            }
        case 117: // Forward delete
            if flags.contains(.maskCommand) {
                onInput?(.deleteToLineEnd)
            } else if flags.contains(.maskAlternate) {
                onInput?(.deleteWordForward)
            } else {
                onInput?(.deleteForward)
            }
        default:
            // Ignore command/control shortcuts so menu commands are not counted as text.
            if flags.contains(.maskCommand) || flags.contains(.maskControl) { return }
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &characters)
            guard length > 0 else { return }
            let text = String(utf16CodeUnits: characters, count: length)
            guard !text.isEmpty else { return }
            if text == "\r" || text == "\n" {
                onInput?(.newline)
            } else {
                onInput?(.characters(text))
            }
        }
    }

    private static func createTap(userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        )
    }
}
