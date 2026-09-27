// autor: Codex, gadula-dzwiek-aktualizacje-20260927
import AppKit

enum SekcjaAktualizacje: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let aktualizacje = kontekst.aktualizacje
        let tytul: String
        if let wersja = aktualizacje.dostepnaWersja {
            tytul = aktualizacje.pobrana ? "Zainstaluj Gadułę \(wersja)…" : "Dostępna Gaduła \(wersja)…"
        } else { tytul = "Sprawdź aktualizacje…" }
        let sprawdz = NSMenuItem(title: tytul, action: nil, keyEquivalent: "")
        sprawdz.isEnabled = aktualizacje.moznaSprawdzic
        kontekst.podepnij(sprawdz) { aktualizacje.sprawdz() }
        let automatyczne = NSMenuItem(title: "Aktualizuj automatycznie", action: nil, keyEquivalent: "")
        automatyczne.state = aktualizacje.automatyczne ? .on : .off
        kontekst.podepnij(automatyczne) { aktualizacje.przelaczAutomatyczne() }
        var wynik = [sprawdz, automatyczne]
        if aktualizacje.pobrana || aktualizacje.bladUruchomienia {
            let opis = NSMenuItem(title: aktualizacje.pobrana ? "Aktualizacja zainstaluje się przy zamknięciu Gaduły." : "Aktualizator niedostępny. Uruchom Gadułę ponownie.", action: nil, keyEquivalent: "")
            opis.isEnabled = false; wynik.append(opis)
        }
        return wynik
    }
}
