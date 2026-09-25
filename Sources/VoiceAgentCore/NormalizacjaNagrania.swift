/// Normalizacja PCM 16 kHz. Heurystyka energii nie zastępuje rozpoznawania mowy.
public enum NormalizacjaNagrania {
    public enum Powod: String, Sendable { case brakEnergii, stalyPoziom, zaKrotkaAktywnosc, juzGlosny, wzmocniono }
    public struct Pomiar: Sendable { public let szczyt: Float; public let rms: Double }
    public struct Wynik: Sendable {
        public let pcm: [Float]
        public let przed: Pomiar
        public let po: Pomiar
        public let wzmocnienie: Float
        public let ograniczoneProbki: Int
        public let powod: Powod
        /// Mediana RMS aktywnych ramek 20 ms, używana jako poziom mowy.
        public let odpornyRMS: Double
        /// 85. percentyl szczytów aktywnych ramek 20 ms.
        public let odpornySzczyt: Float
    }

    private struct Ramka {
        let rms: Double
        let szczyt: Float
    }

    private static let minimalnaLiczbaAktywnychRamek = 8
    private static let epsilon = 0.001

    public static func przygotuj(_ pcm: [Float]) -> Wynik {
        let czyste = pcm.map { $0.isFinite ? $0 : 0 }
        let przed = zmierz(czyste)
        func bezZmiany(_ powod: Powod, odpornyRMS: Double = 0, odpornySzczyt: Float = 0) -> Wynik {
            var wynikPCM = czyste
            var ograniczone = 0
            if przed.szczyt > 0.95 {
                for indeks in wynikPCM.indices {
                    let probka = Double(wynikPCM[indeks])
                    if abs(probka) > 0.95 {
                        ograniczone += 1
                        wynikPCM[indeks] = Float(min(0.95, max(-0.95, probka)))
                    }
                }
            }
            let po = ograniczone == 0 ? przed : zmierz(wynikPCM)
            return Wynik(pcm: wynikPCM, przed: przed, po: po, wzmocnienie: 1, ograniczoneProbki: ograniczone,
                         powod: powod, odpornyRMS: odpornyRMS, odpornySzczyt: odpornySzczyt)
        }

        // Ramki 20 ms. RMS rozpoznaje energię, a szczyt ramki pozwala odrzucić pojedynczy trzask.
        var ramki: [Ramka] = []
        for start in stride(from: 0, to: czyste.count, by: 320) {
            let koniec = min(start + 320, czyste.count)
            var suma = 0.0
            var szczyt: Float = 0
            for i in start..<koniec {
                let probka = czyste[i]
                let x = Double(probka)
                suma += x * x
                szczyt = max(szczyt, abs(probka))
            }
            ramki.append(Ramka(rms: (suma / Double(koniec - start)).squareRoot(), szczyt: szczyt))
        }
        guard !ramki.isEmpty else { return bezZmiany(.brakEnergii) }

        let energie = ramki.map(\.rms).sorted()
        let tlo = energie[energie.count / 5]
        let poziom = energie[min(energie.count - 1, energie.count * 85 / 100)]
        guard poziom >= 0.0005 else { return bezZmiany(.brakEnergii) }
        // Stacjonarny szum nie może zostać podniesiony do docelowego poziomu mowy.
        guard poziom >= tlo * 2.5 else { return bezZmiany(.stalyPoziom) }

        let aktywne = ramki.filter { $0.rms >= max(0.0005, tlo * 2.5) }
        let aktywneRMS = aktywne.map(\.rms).sorted()
        let odpornyRMS = aktywneRMS.isEmpty ? 0 : aktywneRMS[aktywneRMS.count / 2]
        let aktywneSzczyty = aktywne.map { Double($0.szczyt) }.sorted()
        // Indeks floor(0.85 * (n - 1)) nie pozwala pojedynczemu największemu trzaskowi
        // sterować wzmocnieniem, również w krótkich nagraniach.
        let indeksSzczytu = aktywneSzczyty.isEmpty ? 0 : Int(Double(aktywneSzczyty.count - 1) * 0.85)
        let odpornySzczyt = aktywneSzczyty.isEmpty ? 0 : Float(aktywneSzczyty[indeksSzczytu])

        // Ta bramka steruje wyłącznie wzmocnieniem. Krótsze wypowiedzi zachowujemy bez zmian,
        // aby nadal mogły przejść do STT.
        guard aktywne.count >= minimalnaLiczbaAktywnychRamek else {
            return bezZmiany(.zaKrotkaAktywnosc, odpornyRMS: odpornyRMS, odpornySzczyt: odpornySzczyt)
        }

        let celRMS = max(1, 0.08 / max(odpornyRMS, epsilon))
        let limitSzczytu = 0.95 / max(Double(odpornySzczyt), epsilon)
        // Wzmocnienie nigdy nie ścisza. Ostateczny ogranicznik obsługuje sygnały już ponad sufitem.
        let gain = Float(max(1, min(12, celRMS, limitSzczytu)))
        var ograniczone = 0
        let wynik = czyste.map { probka -> Float in
            let x = Double(probka) * Double(gain)
            if abs(x) > 0.95 { ograniczone += 1 }
            return Float(min(0.95, max(-0.95, x)))
        }
        return Wynik(pcm: wynik, przed: przed, po: zmierz(wynik), wzmocnienie: gain,
                     ograniczoneProbki: ograniczone, powod: gain > 1 ? .wzmocniono : .juzGlosny,
                     odpornyRMS: odpornyRMS, odpornySzczyt: odpornySzczyt)
    }

    private static func zmierz(_ pcm: [Float]) -> Pomiar {
        var szczyt: Float = 0
        var suma = 0.0
        for probka in pcm {
            szczyt = max(szczyt, abs(probka))
            let x = Double(probka)
            suma += x * x
        }
        return Pomiar(szczyt: szczyt, rms: pcm.isEmpty ? 0 : (suma / Double(pcm.count)).squareRoot())
    }
}
