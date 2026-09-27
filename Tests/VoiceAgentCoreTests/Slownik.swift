// autor: Codex, gadula-dyktowanie-20260927
import VoiceAgentCore
import Foundation

enum TestySlownika {
    @MainActor static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [("słownik: podpowiedź nie urywa nazw w połowie", {
            let slownik = SlownikDyktowania("Gaduła\nBardzo długa nazwa\nUnity")
            try expectEqual(slownik.podpowiedz(limit: 12, koszt: { $0.count }), "Gaduła.")
            try expectEqual(slownik.podpowiedz(limit: 2, koszt: { $0.count }), "")
        }), ("słownik: czyści puste i duplikaty bez zmiany nazw", {
            try expectEqual(SlownikDyktowania("  Gaduła \n\nGADUŁA\nFrankentools\nNode.js").nazwy, ["Gaduła", "Frankentools", "Node.js"])
        }), ("słownik: dokładnie 1000 znaków nie gubi ostatniej nazwy", {
            let nazwy = (0..<13).map { String(format: "%02d", $0) + String(repeating: "a", count: 74) }
            let tekst = nazwy.joined(separator: "\n")
            try expectEqual(tekst.count, 1000)
            try expectEqual(SlownikDyktowania(tekst).nazwy, nazwy)
        })]
    }
}
