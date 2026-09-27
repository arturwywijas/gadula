import AppKit

enum SekcjaMikrofon: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(title: "Mikrofon", action: nil, keyEquivalent: "")
        let podmenu = NSMenu()
        let wybrany = kontekst.magazyn.string(klucz: KluczMikrofonu.uid, domyslna: "")

        let nazwaSystemowego = AudioDeviceManager.defaultInputDeviceID().flatMap { AudioDeviceManager.name(for: $0) } ?? "brak wejścia"
        let systemowy = NSMenuItem(title: "Systemowy domyślny: \(nazwaSystemowego)", action: nil, keyEquivalent: "")
        systemowy.state = wybrany.isEmpty ? .on : .off
        kontekst.podepnij(systemowy) {
            kontekst.magazyn.ustaw("", klucz: KluczMikrofonu.uid)
            kontekst.odswiez()
        }
        podmenu.addItem(systemowy)

        if !wybrany.isEmpty, AudioDeviceManager.deviceID(forUID: wybrany) == nil {
            let informacja = NSMenuItem(title: "Wybrany mikrofon odłączony. Użyję systemowego.", action: nil, keyEquivalent: "")
            informacja.isEnabled = false
            podmenu.addItem(informacja)
        }

        for urzadzenie in AudioDeviceManager.inputDevices() {
            let pozycja = NSMenuItem(title: urzadzenie.name, action: nil, keyEquivalent: "")
            pozycja.state = wybrany == urzadzenie.uid ? .on : .off
            let uid = urzadzenie.uid
            kontekst.podepnij(pozycja) {
                kontekst.magazyn.ustaw(uid, klucz: KluczMikrofonu.uid)
                kontekst.odswiez()
            }
            podmenu.addItem(pozycja)
        }

        item.submenu = podmenu
        return [item]
    }
}
