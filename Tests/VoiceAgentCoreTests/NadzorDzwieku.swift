// autor: Codex, gadula-stabilnosc-20260927
import VoiceAgentCore

@MainActor enum TestyNadzoruDzwieku {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [
            ("mikrofon bez PCM przestaje udawać nagrywanie po 4 sekundach", {
                var nadzor = NadzorDzwieku()
                nadzor.rozpocznij(czas: 10)
                try expectEqual(nadzor.brakDanych(czas: 13.9), false)
                try expectEqual(nadzor.brakDanych(czas: 14), true)
            }),
            ("mikrofon: cisza z próbkami jest poprawnym dźwiękiem, zanik PCM jest awarią", {
                var nadzor = NadzorDzwieku()
                nadzor.rozpocznij(czas: 10)
                nadzor.otrzymano(liczbaProbek: 16000, czas: 13)
                try expectEqual(nadzor.brakDanych(czas: 16.9), false)
                nadzor.otrzymano(liczbaProbek: 0, czas: 16.9)
                try expectEqual(nadzor.brakDanych(czas: 17), true)
                nadzor.zakoncz()
                try expectEqual(nadzor.brakDanych(czas: 100), false)
                nadzor.rozpocznij(czas: 200)
                try expectEqual(nadzor.brakDanych(czas: 201), false)
            })
        ]
    }
}
