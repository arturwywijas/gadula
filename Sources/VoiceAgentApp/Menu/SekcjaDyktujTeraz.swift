import AppKit

enum SekcjaDyktujTeraz: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(title: "Dyktuj teraz", action: nil, keyEquivalent: "")
        kontekst.podepnij(item, kontekst.dyktuj)
        return [item]
    }
}
