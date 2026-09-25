import AppKit

enum SekcjaMikrofon: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(title: "Mikrofon", action: nil, keyEquivalent: "")
        let podmenu = NSMenu()
        let wybrany = kontekst.magazyn.string(klucz: KluczMikrofonu.uid, domyslna: "")

        let systemowy = NSMenuItem(title: "Systemowy domyślny", action: nil, keyEquivalent: "")
        systemowy.state = wybrany.isEmpty ? .on : .off
        kontekst.podepnij(systemowy) {
            kontekst.magazyn.ustaw("", klucz: KluczMikrofonu.uid)
            kontekst.odswiez()
        }
        podmenu.addItem(systemowy)

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
