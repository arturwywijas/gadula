import AppKit

enum SekcjaZakoncz: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(title: "Zakończ", action: nil, keyEquivalent: "q")
        kontekst.podepnij(item, kontekst.zakoncz)
        return [item]
    }
}
