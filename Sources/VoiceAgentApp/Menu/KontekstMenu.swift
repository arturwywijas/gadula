import AppKit
import VoiceAgentCore

final class PudelkoAkcji: NSObject {
    let wykonaj: () -> Void

    init(_ wykonaj: @escaping () -> Void) {
        self.wykonaj = wykonaj
    }
}

@MainActor
final class CelAkcjiMenu: NSObject {
    @objc nonisolated func wykonajZPozycji(_ sender: NSMenuItem) {
        // AppKit przekazuje pozycję z main; poza zadaniem nie odczytujemy obiektu UI.
        nonisolated(unsafe) let item = sender
        Task { @MainActor in self.wykonaj(item) }
    }

    private func wykonaj(_ sender: NSMenuItem) {
        guard let pudelko = sender.representedObject as? PudelkoAkcji else { return }
        pudelko.wykonaj()
    }
}

@MainActor
struct KontekstMenu {
    let etykietaStanu: String
    let stanPrzygotowaniaModelu: StanPrzygotowaniaModelu
    let poziomWejsciaMikrofonuDb: Float?
    let bladSkrotu: String?
    let cel: CelAkcjiMenu
    let magazyn: MagazynUstawien
    let odswiez: () -> Void
    let dyktuj: () -> Void
    let zakoncz: () -> Void

    func podepnij(_ item: NSMenuItem, _ wykonaj: @escaping () -> Void) {
        item.action = #selector(CelAkcjiMenu.wykonajZPozycji(_:))
        item.target = cel
        item.representedObject = PudelkoAkcji(wykonaj)
    }
}

@MainActor
protocol BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem]
}
