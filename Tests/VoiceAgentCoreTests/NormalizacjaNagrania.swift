import VoiceAgentCore

enum TestyNormalizacjiNagrania {
    static func mowa(skala: Float = 1) -> [Float] {
        (0..<100).flatMap { ramka -> [Float] in
            let poziom: Float = ramka < 20 ? 0 : [0.002, 0.006, 0.012, 0.02][ramka % 4] * skala
            return (0..<320).map { $0 % 2 == 0 ? poziom : -poziom }
        }
    }
    static func ramki(_ poziomy: [Float]) -> [Float] {
        poziomy.flatMap { poziom in (0..<320).map { $0 % 2 == 0 ? poziom : -poziom } }
    }
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [
            ("FN19: glosna mowa pozostaje bez zmian", {
                let pcm = mowa(skala: 30)
                let wynik = NormalizacjaNagrania.przygotuj(pcm)
                try expectEqual(wynik.wzmocnienie, 1)
                try expectEqual(wynik.pcm, pcm)
            }),
            ("FN19: cisza nie jest wzmacniana", {
                let wynik = NormalizacjaNagrania.przygotuj([Float](repeating: 0, count: 16_000))
                try expectEqual(wynik.wzmocnienie, 1)
                try expectEqual(wynik.po.rms, 0)
                try expectEqual(wynik.po.szczyt, 0)
            }),
            ("FN19: stacjonarny szum nie jest wzmacniany do mowy", {
                var stan: UInt64 = 17
                let pcm: [Float] = (0..<32_000).map { _ in
                    stan = stan &* 6364136223846793005 &+ 1
                    return (Float(stan >> 40) / Float(1 << 24) * 2 - 1) * 0.002
                }
                let wynik = NormalizacjaNagrania.przygotuj(pcm)
                try expectEqual(wynik.wzmocnienie, 1)
                try expectEqual(wynik.pcm, pcm)
            }),
            ("FN19: pojedynczy trzask nie blokuje wzmocnienia reszty", {
                let spokojne = mowa(skala: 0.3)
                var zTrzaskiem = spokojne
                zTrzaskiem[13_000] = 0.99
                let przed = NormalizacjaNagrania.przygotuj(spokojne)
                let po = NormalizacjaNagrania.przygotuj(zTrzaskiem)
                try expectEqual(po.wzmocnienie, przed.wzmocnienie)
                try expectEqual(po.odpornyRMS, przed.odpornyRMS)
                try expectEqual(po.odpornySzczyt, przed.odpornySzczyt)
                try expectEqual(po.wzmocnienie > 1, true)
                try expectEqual(po.pcm[14_000], przed.pcm[14_000])
                try expectEqual(po.po.szczyt <= 0.95, true)
                try expectEqual(po.ograniczoneProbki, 1)
            }),
            ("FN19: sam trzask w ciszy nie uruchamia wzmocnienia", {
                var pcm = [Float](repeating: 0, count: 32_000)
                pcm[1000] = 0.9
                try expectEqual(NormalizacjaNagrania.przygotuj(pcm).wzmocnienie, 1)
            }),
            ("FN19: sygnal ponizej podlogi energii nie jest pompowany", {
                let wynik = NormalizacjaNagrania.przygotuj(mowa(skala: 0.001))
                try expectEqual(wynik.wzmocnienie, 1)
                try expectEqual(wynik.powod, .brakEnergii)
            }),
            ("FN19: pusty PCM i niefinitywne probki sa bezpieczne", {
                try expectEqual(NormalizacjaNagrania.przygotuj([]).pcm, [])
                let wynik = NormalizacjaNagrania.przygotuj([.nan, .infinity, -.infinity])
                try expectEqual(wynik.pcm, [0, 0, 0])
                try expectEqual(wynik.po.rms, 0)
            }),
            ("FN19: progi przepuszczaja nagranie Artura i zachowuja granice", {
                try expectEqual(ProgiSesji.dopuszczaNagranie(czas: 2.30, szczyt: 0.2336), true)
                try expectEqual(ProgiSesji.dopuszczaNagranie(czas: 0.3, szczyt: 0.005), true)
                try expectEqual(ProgiSesji.dopuszczaNagranie(czas: 0.299, szczyt: 0.5), false)
                try expectEqual(ProgiSesji.dopuszczaNagranie(czas: 1, szczyt: 0.0049), false)
                try expectEqual(ProgiSesji.dopuszczaNagranie(czas: .nan, szczyt: 0.1), false)
            }),
            ("FN19: VAD dopiero powyzej okna a ponowienia sa ograniczone", {
                try expectEqual(ParametryRozpoznawania.uzyjVAD(liczbaProbek: 36_864, okno: 480_000), false)
                try expectEqual(ParametryRozpoznawania.uzyjVAD(liczbaProbek: 480_000, okno: 480_000), false)
                try expectEqual(ParametryRozpoznawania.uzyjVAD(liczbaProbek: 480_001, okno: 480_000), true)
                try expectEqual(ParametryRozpoznawania.liczbaPonowien, 3)
            }),
            ("FN20: mowa wymagajaca ponad 12 dobija dokladnie do nowego sufitu", {
                let wynik = NormalizacjaNagrania.przygotuj(mowa(skala: 0.3))
                try expectEqual(0.08 / wynik.odpornyRMS > 12, true)
                try expectEqual(0.95 / Double(wynik.odpornySzczyt) > 12, true)
                try expectEqual(abs(wynik.wzmocnienie - 12) < 0.0001, true)
                try expectEqual(wynik.po.rms > wynik.przed.rms, true)
                try expectEqual(wynik.po.szczyt <= 0.95, true)
            }),
            ("FN20: potrzeba miedzy 6 i 12 zachowuje wzmocnienie okolo 9", {
                let wynik = NormalizacjaNagrania.przygotuj(mowa(skala: 0.75))
                try expectEqual(wynik.wzmocnienie > 6 && wynik.wzmocnienie < 12, true)
                try expectEqual(abs(Double(wynik.wzmocnienie) - 8.888_888_9) < 0.001, true)
                try expectEqual(0.95 / Double(wynik.odpornySzczyt) > 12, true)
            }),
            ("FN20: bardzo cicha mowa dochodzi do celu z zapasem ogranicznika", {
                let pcm = ramki((0..<40).map { [0.006, 0.01, 0.014, 0.018][$0 % 4] })
                let wynik = NormalizacjaNagrania.przygotuj(pcm)
                try expectEqual(wynik.wzmocnienie > 1 && wynik.wzmocnienie <= 12, true)
                try expectEqual(abs(wynik.pcm[3 * 320 + 100] - 0.08) < 0.001, true)
                try expectEqual(wynik.po.szczyt <= 0.95, true)
            }),
            ("FN20: szum przez kilka ramek nie włącza wzmocnienia", {
                let pcm = ramki([0.001, 0.001, 0.001, 0.001, 0.004, 0.004, 0.004, 0.004, 0.004, 0.004])
                let wynik = NormalizacjaNagrania.przygotuj(pcm)
                try expectEqual(wynik.wzmocnienie, 1)
                try expectEqual(wynik.pcm, pcm)
            }),
            ("FN20: krótka prawdziwa wypowiedź przechodzi bez odrzucenia", {
                let pcm = ramki([0, 0, 0.01, 0.01, 0.01, 0.01, 0.01])
                let wynik = NormalizacjaNagrania.przygotuj(pcm)
                try expectEqual(wynik.wzmocnienie, 1)
                try expectEqual(wynik.pcm.count, pcm.count)
                try expectEqual(wynik.pcm, pcm)
            }),
            ("FN20: ogranicznik pilnuje szczytu bez wspolczynnika ponizej jednego", {
                let pcm = ramki([0.99, 0.99, 0.99, 0.99, 0.99, 0.99, 0.99, 0.99])
                let wynik = NormalizacjaNagrania.przygotuj(pcm)
                try expectEqual(wynik.wzmocnienie >= 1, true)
                try expectEqual(wynik.po.szczyt <= 0.95, true)
            }),
            ("FN20: niski poziom wejscia ostrzega ponizej minus 12 dB", {
                try expectEqual(PoziomWejsciaMikrofonu.ostrzez(db: -16.49), true)
                try expectEqual(PoziomWejsciaMikrofonu.ostrzez(db: -12.01), true)
                try expectEqual(PoziomWejsciaMikrofonu.ostrzez(db: -12), false)
                try expectEqual(PoziomWejsciaMikrofonu.ostrzez(db: -8), false)
                try expectEqual(PoziomWejsciaMikrofonu.ostrzez(db: nil), false)
                try expectEqual(PoziomWejsciaMikrofonu.ostrzez(db: .nan), false)
            }),
        ]
    }
}
