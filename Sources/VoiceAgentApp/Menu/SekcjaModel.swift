import AppKit
import VoiceAgentCore

enum SekcjaModel: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let katalog = KatalogModelu.wspolny
        katalog.odswiez = kontekst.odswiez
        let wybrany = kontekst.magazyn.string(klucz: KluczModelu.id, domyslna: KluczModelu.domyslny)

        let item = NSMenuItem(title: katalog.tytulSekcji(), action: nil, keyEquivalent: "")
        let podmenu = NSMenu()

        for wariant in WariantModelu.allCases {
            let pozycja = NSMenuItem(title: wariant.etykieta, action: nil, keyEquivalent: "")
            pozycja.state = wybrany == wariant.rawValue ? .on : .off
            let id = wariant.rawValue
            kontekst.podepnij(pozycja) {
                kontekst.magazyn.ustaw(id, klucz: KluczModelu.id)
                katalog.uruchomDla(id: id)
                kontekst.odswiez()
            }
            podmenu.addItem(pozycja)
        }

        switch kontekst.stanPrzygotowaniaModelu {
        case .przygotowuje:
            let przygotowuje = NSMenuItem(title: "Przygotowywanie modelu…", action: nil, keyEquivalent: "")
            przygotowuje.isEnabled = false
            podmenu.addItem(przygotowuje)
        case .blad:
            let blad = NSMenuItem(title: "Nie udało się przygotować modelu.", action: nil, keyEquivalent: "")
            blad.isEnabled = false
            podmenu.addItem(blad)
        case .niegotowy, .gotowy:
            break
        }

        switch katalog.stan {
        case .pobieranie(let postep):
            let procent = max(0, min(100, Int((postep * 100).rounded())))
            let postepItem = NSMenuItem(
                title: "Pobieranie wag \(procent)%",
                action: nil,
                keyEquivalent: ""
            )
            postepItem.isEnabled = false
            podmenu.addItem(postepItem)
        case .przerwane:
            let stan = NSMenuItem(
                title: "Pobieranie przerwane (brak sieci). Można ponowić.",
                action: nil,
                keyEquivalent: ""
            )
            stan.isEnabled = false
            podmenu.addItem(stan)
            let ponow = NSMenuItem(title: "Ponów pobieranie", action: nil, keyEquivalent: "")
            kontekst.podepnij(ponow) {
                katalog.ponow(id: wybrany)
            }
            podmenu.addItem(ponow)
        case .niepobrany:
            let brak = NSMenuItem(title: "model niegotowy", action: nil, keyEquivalent: "")
            brak.isEnabled = false
            podmenu.addItem(brak)
            let pobierz = NSMenuItem(title: "Pobierz model", action: nil, keyEquivalent: "")
            kontekst.podepnij(pobierz) {
                katalog.uruchomDla(id: wybrany)
            }
            podmenu.addItem(pobierz)
        case .gotowy:
            let ponow = NSMenuItem(title: "Pobierz ponownie", action: nil, keyEquivalent: "")
            kontekst.podepnij(ponow) {
                katalog.ponow(id: wybrany)
            }
            podmenu.addItem(ponow)
        }

        item.submenu = podmenu
        item.isEnabled = kontekst.moznaZmienicModel
        return [item]
    }
}
