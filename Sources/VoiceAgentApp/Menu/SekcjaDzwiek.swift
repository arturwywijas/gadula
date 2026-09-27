// autor: Codex, gadula-dzwiek-aktualizacje-20260927
import AppKit

enum SekcjaDzwiek: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(title: "Ściszaj dźwięk podczas dyktowania", action: nil, keyEquivalent: "")
        item.state = kontekst.dzwiek.wlaczone ? .on : .off
        kontekst.podepnij(item) { kontekst.dzwiek.przelacz(); kontekst.odswiez() }
        return [item]
    }
}
