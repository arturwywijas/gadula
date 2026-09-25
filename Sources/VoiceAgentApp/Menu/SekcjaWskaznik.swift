import AppKit
import VoiceAgentCore

enum SekcjaWskaznik: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(title: "Wskaźnik nagrywania", action: nil, keyEquivalent: "")
        let podmenu = NSMenu()
        let wybrany = StylWskaznikaNagrywania.wczytaj(z: kontekst.magazyn)
        for styl in StylWskaznikaNagrywania.allCases {
            let tytul: String
            switch styl {
            case .slupki: tytul = "Słupki"
            case .iskry: tytul = "Iskry"
            case .nicSwiatla: tytul = "Nić światła"
            }
            let pozycja = NSMenuItem(title: tytul, action: nil, keyEquivalent: "")
            pozycja.state = styl == wybrany ? .on : .off
            kontekst.podepnij(pozycja) {
                styl.zapisz(w: kontekst.magazyn)
                kontekst.odswiez()
            }
            podmenu.addItem(pozycja)
        }
        item.submenu = podmenu
        return [item]
    }
}
