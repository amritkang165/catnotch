import Carbon.HIToolbox

/// A system wide shortcut. Carbon hot keys need no Accessibility permission.
@MainActor
final class GlobalShortcut {
    private static var action: (() -> Void)?

    /// Cmd+Option+, runs `action`. If another app already owns it, this only logs a warning.
    init(action: @escaping () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalShortcut.action?() }
            return noErr
        }, 1, &spec, nil, nil)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_Comma), UInt32(cmdKey | optionKey),
                                         EventHotKeyID(signature: OSType(0x434E5348) /* CNSH */, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { print("[shortcut] Cmd+Option+, is taken (status \(status)); Settings has no shortcut this launch") }
    }
}
