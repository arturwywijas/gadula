import AppKit

enum SekcjaUprawnienia: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let micOK = PermissionsChecker.microphoneStatus == .authorized
        let axOK = PermissionsChecker.isAccessibilityGranted
        let combo = KeyCombo.wczytaj(z: kontekst.magazyn)
        let axDoSkrotu = combo.kind == .modifierOnly

        let skrotMic = micOK ? "Mikrofon OK" : "Mikrofon brak"
        let skrotAX = axOK ? "Dostępność OK" : "Dostępność brak"
        let item = NSMenuItem(
            title: "Uprawnienia: \(skrotAX), \(skrotMic)",
            action: nil,
            keyEquivalent: ""
        )
        let podmenu = NSMenu()

        if micOK {
            let wiersz = NSMenuItem(title: "Mikrofon: OK", action: nil, keyEquivalent: "")
            wiersz.isEnabled = false
            podmenu.addItem(wiersz)
        } else {
            let wiersz = NSMenuItem(title: "Mikrofon: brak (nagranie nie startuje)", action: nil, keyEquivalent: "")
            kontekst.podepnij(wiersz) {
                PermissionsChecker.openMicrophoneSettings()
            }
            podmenu.addItem(wiersz)
        }

        if axOK {
            let wiersz = NSMenuItem(title: "Dostępność: OK", action: nil, keyEquivalent: "")
            wiersz.isEnabled = false
            podmenu.addItem(wiersz)
        } else {
            let powod = axDoSkrotu
                ? "Dostępność: brak (Fn milczy, wstawianie tylko schowek)"
                : "Dostępność: brak (wstawianie tylko schowek)"
            let wiersz = NSMenuItem(title: powod, action: nil, keyEquivalent: "")
            kontekst.podepnij(wiersz) {
                PermissionsChecker.openAccessibilitySettings()
            }
            podmenu.addItem(wiersz)
        }

        item.submenu = podmenu
        return [item]
    }
}
