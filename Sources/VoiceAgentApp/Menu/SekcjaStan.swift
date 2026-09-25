import AppKit
import VoiceAgentCore

enum SekcjaStan: BudowniczySekcjiMenu {
    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(title: kontekst.etykietaStanu, action: nil, keyEquivalent: "")
        item.isEnabled = false
        var pozycje = [item]
        if let db = kontekst.poziomWejsciaMikrofonuDb, PoziomWejsciaMikrofonu.ostrzez(db: db) {
            let wartosc = String(format: "%.1f", db).replacingOccurrences(of: ".", with: ",")
            let ostrzezenie = NSMenuItem(
                title: "Niski poziom mikrofonu: \(wartosc) dB. Podnieś w Ustawieniach systemowych > Dźwięk > Wejście.",
                action: nil,
                keyEquivalent: "")
            ostrzezenie.isEnabled = false
            pozycje.append(ostrzezenie)
        }
        return pozycje
    }
}
