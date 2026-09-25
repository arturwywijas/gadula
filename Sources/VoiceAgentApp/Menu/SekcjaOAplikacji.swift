import AppKit

enum SekcjaOAplikacji: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(title: "O aplikacji", action: nil, keyEquivalent: "")
        let podmenu = NSMenu()

        let nazwa = NSMenuItem(title: "Gaduła", action: nil, keyEquivalent: "")
        nazwa.isEnabled = false
        podmenu.addItem(nazwa)

        let wersja = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "dev"
        let wersjaItem = NSMenuItem(title: "Wersja \(wersja)", action: nil, keyEquivalent: "")
        wersjaItem.isEnabled = false
        podmenu.addItem(wersjaItem)

        let licencje = NSMenuItem(title: "Licencje", action: nil, keyEquivalent: "")
        kontekst.podepnij(licencje) {
            guard let url = urlLicencji() else { return }
            NSWorkspace.shared.open(url)
        }
        podmenu.addItem(licencje)

        item.submenu = podmenu
        return [item]
    }

    private static func urlLicencji() -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md") {
            return url
        }
        #endif
        return Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md")
    }
}
