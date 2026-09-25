// Pochodzi ze snapshotu vlr-code/dictly (MIT).
import AppKit
import Carbon.HIToolbox

/// System-wide hotkey listener. Uses **Carbon `RegisterEventHotKey`** — the same API
/// every other macOS hotkey app uses (Alfred, Raycast, BetterTouchTool, KeyboardShortcuts,
/// Sindre Sorhus's HotKey, …). The OS itself owns the hotkey registration and calls our
/// handler, so the **Carbon (key-combo) path needs no Accessibility / Input Monitoring
/// permission** — the user just picks a key in settings and it works.
///
/// Carbon emits both `kEventHotKeyPressed` and `kEventHotKeyReleased`, so push-to-talk
/// (hold to record / release to transcribe) is supported out of the box.
///
/// Modifier-only hotkeys (Fn alone, right Option…) aren't representable as Carbon hotkeys,
/// so for those we fall back to a global `flagsChanged` `NSEvent` monitor. Unlike Carbon,
/// macOS only delivers global key-event monitors to apps trusted for **Accessibility** —
/// so a modifier-only hotkey silently does nothing until the user grants that access.
@MainActor
final class HotkeyManager {

    private static let log = AppLogger(category: "Hotkey")

    private(set) var bladRejestracji: String?

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var combo: KeyCombo = .defaultHotkey
    private var hotKeyRef: EventHotKeyRef?
    private var modifierMonitor: Any?
    private var modifierLocalMonitor: Any?
    private var isHeld = false

    /// Registry mapping a Carbon hotkey id → its `HotkeyManager`. Carbon handlers are
    /// `@convention(c)`, so they can't capture `self`; we look it up from the id passed
    /// in the event payload.
    nonisolated(unsafe) private static var registry: [UInt32: WeakBox] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    /// The Carbon event handler is installed ONCE on the app event target and shared
    /// by every `HotkeyManager` instance. Installing it per instance makes the second
    /// hotkey's `InstallEventHandler` fail with `eventHandlerAlreadyInstalledErr`
    /// (-9866), so that hotkey never fires. Events route to the right instance via
    /// `registry`, keyed on the hotkey id.
    nonisolated(unsafe) private static var sharedHandlerRef: EventHandlerRef?
    private final class WeakBox { weak var manager: HotkeyManager?; init(_ m: HotkeyManager) { manager = m } }
    private var hotKeyID: UInt32 = 0

    func update(combo: KeyCombo) {
        // No-op when nothing changed. Re-registering while the key is held
        // would swallow the upcoming release and leave recording running.
        guard combo != self.combo else { return }
        self.combo = combo
        isHeld = false
        // Re-install with the new combo if we were already running.
        if isRunning {
            stop()
            start()
        }
    }

    /// Whether this hotkey is currently installed (Carbon hotkey or modifier monitor).
    var isRunning: Bool { hotKeyRef != nil || modifierMonitor != nil || modifierLocalMonitor != nil }

    func start() {
        stop()
        bladRejestracji = nil
        Self.log.notice("FN09 selected kind=\(self.combo.kind.rawValue) solo=\(String(describing: self.combo.solo)) keyCode=\(String(describing: self.combo.keyCode)) modifiers=\(self.combo.modifierFlags) axTrusted=\(PermissionsChecker.isAccessibilityGranted) listenEventAccess=\(CGPreflightListenEventAccess())")
        switch combo.kind {
        case .keyCombo:
            installCarbonHotkey()
        case .modifierOnly:
            installModifierMonitor()
        }
        Self.log.notice("FN08 registration mode=\(self.combo.kind.rawValue) combo=\(self.combo.displayName) pushToTalk=\(self.combo.isPushToTalk) running=\(self.isRunning) carbonHotKeyID=\(self.hotKeyID) globalMonitor=\(self.modifierMonitor != nil) localMonitor=\(self.modifierLocalMonitor != nil) deviceID=unavailable")
    }

    func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if hotKeyID != 0 {
            Self.registry.removeValue(forKey: hotKeyID)
            hotKeyID = 0
        }
        if let m = modifierMonitor { NSEvent.removeMonitor(m); modifierMonitor = nil }
        if let m = modifierLocalMonitor { NSEvent.removeMonitor(m); modifierLocalMonitor = nil }
        isHeld = false
    }

    // MARK: - Carbon hotkey path

    private func installCarbonHotkey() {
        guard let keyCode = combo.keyCode else { return }

        // Generate a unique 32-bit id and remember the back-pointer.
        let id: UInt32 = {
            Self.nextID &+= 1
            return Self.nextID
        }()
        hotKeyID = id
        Self.registry[id] = WeakBox(self)

        // Translate NSEvent modifiers to Carbon's mask.
        let nsModifiers = NSEvent.ModifierFlags(rawValue: combo.modifierFlags)
        var carbonModifiers: UInt32 = 0
        if nsModifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if nsModifiers.contains(.option)  { carbonModifiers |= UInt32(optionKey) }
        if nsModifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if nsModifiers.contains(.shift)   { carbonModifiers |= UInt32(shiftKey) }

        // Carbon delivers BOTH press and release events for any hotkey we register.
        let signature: OSType = 0x44_43_54_4C  // "DCTL" — arbitrary 4cc unique to us
        let hkID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        Self.log.notice("FN08 RegisterEventHotKey status=\(regStatus) refPresent=\(ref != nil) hotKeyID=\(id) keyCode=\(keyCode) carbonModifiers=\(carbonModifiers)")
        guard regStatus == noErr, ref != nil else {
            bladRejestracji = "Skrót nieaktywny: błąd rejestracji Carbon (\(regStatus))."
            Self.log.error("RegisterEventHotKey failed with OSStatus \(regStatus)")
            return
        }
        hotKeyRef = ref

        // Install the process-wide handler once (shared across all hotkeys/instances).
        guard Self.installSharedCarbonHandlerIfNeeded() else {
            bladRejestracji = "Skrót nieaktywny: nie udało się zainstalować obsługi Carbon."
            UnregisterEventHotKey(ref!)
            hotKeyRef = nil
            Self.registry.removeValue(forKey: id)
            hotKeyID = 0
            return
        }
    }

    /// Installs the single Carbon hot-key event handler on the app event target the
    /// first time any hotkey is registered; later calls are no-ops. Returns whether
    /// the handler is in place. See `sharedHandlerRef` for why this must be global.
    @discardableResult
    private static func installSharedCarbonHandlerIfNeeded() -> Bool {
        if sharedHandlerRef != nil { return true }
        var eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased))
        ]
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            eventSpecs.count, &eventSpecs,
            nil,
            &handlerRef
        )
        log.notice("FN09 InstallEventHandler status=\(status) refPresent=\(handlerRef != nil)")
        guard status == noErr else {
            log.error("InstallEventHandler failed with OSStatus \(status)")
            return false
        }
        sharedHandlerRef = handlerRef
        return true
    }

    fileprivate func dispatchCarbonEvent(kind: UInt32) {
        Self.log.notice("FN09 Carbon match hotKeyID=\(self.hotKeyID) kind=\(kind) heldBefore=\(self.isHeld)")
        if Int(kind) == kEventHotKeyPressed {
            guard !isHeld else { return }
            isHeld = true
            Self.log.notice("FN09 callback onPress combo=\(self.combo.displayName)")
            onPress?()
        } else if Int(kind) == kEventHotKeyReleased {
            guard isHeld else { return }
            isHeld = false
            Self.log.notice("FN09 callback onRelease combo=\(self.combo.displayName)")
            onRelease?()
        }
    }

    // MARK: - Modifier-only path
    //
    // Carbon doesn't know how to register a "modifier alone" as a hotkey, so for Fn /
    // right Option / right Shift we keep a global `NSEvent` flagsChanged monitor. macOS
    // only delivers global key-event monitors (flagsChanged included) to apps trusted for
    // Accessibility — so this global path is dead until the user grants Accessibility. The
    // local monitor still fires while Gaduła is frontmost, but global capture needs the grant.

    private func installModifierMonitor() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged]
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let flags = event.modifierFlags
            DispatchQueue.main.async {
                self?.handleModifierFlags(flags)
            }
        }
        modifierLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleModifierFlags(event.modifierFlags)
            return event
        }
        Self.log.notice("FN08 modifier waiting active=\(self.isRunning) expected=\(self.combo.displayName) globalMonitor=\(self.modifierMonitor != nil) localMonitor=\(self.modifierLocalMonitor != nil) deviceID=unavailable")
    }

    private func handleModifierFlags(_ flags: NSEvent.ModifierFlags) {
        guard combo.solo != nil else { return }
        let pressed = combo.isPressed(flags: flags)
        if pressed && !isHeld {
            isHeld = true
            Self.log.notice("FN09 callback onPress combo=\(self.combo.displayName)")
            onPress?()
        } else if !pressed && isHeld {
            isHeld = false
            Self.log.notice("FN09 callback onRelease combo=\(self.combo.displayName)")
            onRelease?()
        }
    }

    // MARK: - Carbon → Swift bridge

    fileprivate static func lookup(id: UInt32) -> HotkeyManager? {
        registry[id]?.manager
    }
}

/// C-callable Carbon event handler. Looks up our HotkeyManager via the hotkey id, then
/// dispatches into Swift on the main actor. Carbon already delivers on the main thread
/// (we attach to `GetApplicationEventTarget`), but we hop through `DispatchQueue.main`
/// to satisfy the actor boundary cleanly.
private let carbonHotKeyHandler:
    @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus
= { _, event, _ in
    guard let event else { return noErr }
    var hkID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    AppLogger(category: "Hotkey").notice("FN08 Carbon received kind=\(GetEventKind(event)) parameterStatus=\(status) hotKeyID=\(hkID.id) signature=\(hkID.signature) deviceID=unavailable")
    guard status == noErr else { return status }
    let kind = GetEventKind(event)
    let id = hkID.id
    DispatchQueue.main.async {
        HotkeyManager.lookup(id: id)?.dispatchCarbonEvent(kind: kind)
    }
    return noErr
}
