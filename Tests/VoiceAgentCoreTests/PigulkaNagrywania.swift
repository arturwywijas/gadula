import VoiceAgentCore

enum TestyPigulkiNagrywania {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [
            ("pigulka: najnowszy poziom bez kolejki, najwyzej 20 Hz", {
                var stan = StanPigulkiNagrywania()
                stan.przyjmij(szczyt: 1, czas: 0)
                try expectEqual(stan.odswiez(czas: 0), false)
                stan.rozpocznij(czas: 0)
                stan.przyjmij(szczyt: 0.1, czas: 0)
                try expectEqual(stan.odswiez(czas: 0), true)
                let pierwszy = stan.poziom
                try expectEqual(pierwszy > 0 && pierwszy < 1, true)
                stan.przyjmij(szczyt: 1, czas: 0.01)
                stan.przyjmij(szczyt: 0, czas: 0.02)
                stan.przyjmij(szczyt: 1, czas: 0.015)
                try expectEqual(stan.odswiez(czas: 0.049), false)
                try expectEqual(stan.poziom, pierwszy)
                try expectEqual(stan.odswiez(czas: 0.051), true)
                try expectEqual(stan.poziom > 0 && stan.poziom < pierwszy, true)
            }),
            ("pigulka: stop i restart odrzucaja stare poziomy oraz stare ukrycie", {
                var stan = StanPigulkiNagrywania()
                stan.rozpocznij(czas: 1)
                stan.przyjmij(szczyt: 1, czas: 1)
                _ = stan.odswiez(czas: 1)
                let koniec = stan.zakoncz()
                try expectEqual(stan.nagrywa, false)
                try expectEqual(stan.poziom, 0)
                stan.przyjmij(szczyt: 1, czas: 2)
                try expectEqual(stan.odswiez(czas: 2), false)
                try expectEqual(stan.moznaUkryc(rewizja: koniec), true)
                stan.rozpocznij(czas: 2)
                stan.przyjmij(szczyt: 1, czas: 1.9)
                try expectEqual(stan.moznaUkryc(rewizja: koniec), false)
                _ = stan.odswiez(czas: 2)
                try expectEqual(stan.poziom, 0)
            }),
            ("pigulka: wygladzanie, zanik starej probki i nieprawidlowe wartosci", {
                var stan = StanPigulkiNagrywania()
                stan.rozpocznij(czas: 0)
                stan.przyjmij(szczyt: 20, czas: 0)
                _ = stan.odswiez(czas: 0)
                let glosno = stan.poziom
                try expectEqual(glosno > 0 && glosno <= 1, true)
                _ = stan.odswiez(czas: 0.3)
                try expectEqual(stan.poziom < glosno && stan.poziom > 0, true)
                for i in 1...40 { _ = stan.odswiez(czas: 0.3 + Double(i) * 0.06) }
                try expectEqual(stan.poziom, 0)
                for (i, wartosc) in [Float.nan, .infinity, -1].enumerated() {
                    let czas = 4 + Double(i)
                    stan.przyjmij(szczyt: wartosc, czas: czas)
                    _ = stan.odswiez(czas: czas)
                    try expectEqual(stan.poziom, 0)
                }
                try expectEqual(stan.odswiez(czas: .nan), false)
            }),
        ]
    }
}
