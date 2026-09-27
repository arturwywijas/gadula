// autor: Codex, gadula-dyktowanie-20260927
import AppKit
import VoiceAgentCore

enum SekcjaTekst: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let wybrany = TrybTekstu.wczytaj(z: kontekst.magazyn)
        let tekst = NSMenuItem(title: "Tekst: \(wybrany.etykieta)", action: nil, keyEquivalent: "")
        let tryby = NSMenu()
        tryby.autoenablesItems = false
        for tryb in TrybTekstu.allCases {
            let item = NSMenuItem(title: tryb.etykieta, action: nil, keyEquivalent: "")
            item.state = tryb == wybrany ? .on : .off
            kontekst.podepnij(item) {
                kontekst.magazyn.ustaw(tryb.rawValue, klucz: TrybTekstu.klucz)
                kontekst.odswiez()
            }
            tryby.addItem(item)
        }
        let opis = NSMenuItem(title: "Komendy układu wypowiadaj osobno, np. „Nowy akapit”.", action: nil, keyEquivalent: "")
        opis.isEnabled = false
        tryby.addItem(opis)
        tryby.addItem(.separator())
        let surowy = NSMenuItem(title: "Kopiuj tekst przed formatowaniem", action: nil, keyEquivalent: "")
        surowy.isEnabled = kontekst.surowyTranskrypt() != nil
        kontekst.podepnij(surowy) {
            guard let wynik = kontekst.surowyTranskrypt() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(wynik, forType: .string)
        }
        tryby.addItem(surowy)
        tekst.submenu = tryby

        let slownik = NSMenuItem(title: "Słownik nazw…", action: nil, keyEquivalent: "")
        kontekst.podepnij(slownik) { edytujSlownik(kontekst: kontekst) }
        return [tekst, slownik]
    }

    private static func edytujSlownik(kontekst: KontekstMenu) {
        let alert = NSAlert()
        alert.messageText = "Słownik nazw"
        alert.informativeText = "Podaj nazwy, które Gaduła przekręca, po jednej w wierszu. Najważniejsze wpisz na początku; przy długiej liście model może pominąć końcowe nazwy. Lista zostaje na tym Macu. Maksymalnie 40 nazw i 1000 znaków."
        alert.addButton(withTitle: "Zapisz")
        alert.addButton(withTitle: "Anuluj")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 390, height: 170))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let edytor = NSTextView(frame: scroll.bounds)
        edytor.isRichText = false
        edytor.isAutomaticQuoteSubstitutionEnabled = false
        edytor.isAutomaticSpellingCorrectionEnabled = false
        edytor.font = .systemFont(ofSize: 14)
        edytor.autoresizingMask = [.width]
        edytor.string = SlownikDyktowania.wczytaj(z: kontekst.magazyn).tekst
        scroll.documentView = edytor
        alert.accessoryView = scroll
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = edytor
        while alert.runModal() == .alertFirstButtonReturn {
            let linie = edytor.string.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard linie.count <= SlownikDyktowania.limitNazw,
                  edytor.string.count <= SlownikDyktowania.limitZnakow,
                  linie.allSatisfy({ $0.count <= 80 }) else {
                alert.informativeText = "Lista jest za długa. Wpisz do 40 nazw, do 80 znaków w nazwie i do 1000 znaków łącznie."
                continue
            }
            let slownik = SlownikDyktowania(edytor.string)
            kontekst.magazyn.ustaw(slownik.tekst, klucz: SlownikDyktowania.klucz)
            kontekst.odswiez()
            break
        }
    }
}
