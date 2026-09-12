import Foundation
import Carbon

/// Registers a system-wide keyboard shortcut using Carbon's hot-key API.
///
/// Unlike a global key-event monitor, `RegisterEventHotKey` does not require
/// Accessibility permission. Only the configured combination is delivered; no
/// other keystrokes are observed.
public final class GlobalHotkey {
    public var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    public private(set) var isRegistered = false

    private static let signature: OSType = 0x59414B49 // 'YAKI'

    public init() {}

    /// Registers (replacing any existing registration). Returns false if the
    /// combination is unavailable or already taken by the system.
    @discardableResult
    public func register(keyCode: UInt16, carbonModifiers: UInt32) -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onTrigger?() }
            return noErr
        }

        var handler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard installStatus == noErr, let handler else { return false }
        handlerRef = handler

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard registerStatus == noErr, let ref else {
            RemoveEventHandler(handler)
            handlerRef = nil
            return false
        }
        hotKeyRef = ref
        isRegistered = true
        return true
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        isRegistered = false
    }

    deinit { unregister() }
}
