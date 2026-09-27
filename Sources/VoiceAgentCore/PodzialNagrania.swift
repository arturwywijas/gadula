// autor: Codex, gadula-dyktowanie-20260927
import Foundation

/// Rozłączne, przylegające fragmenty PCM 16 kHz. Pauzy wyznaczają cięcia;
/// żadna próbka (również ciszy) nie jest usuwana. Bez pauzy czekamy na stop.
public struct PodzialNagrania: Sendable {
    private var bufor: [Float] = []
    private var skan = 0
    private var cisza = 0
    private var oczekujacaGranica: Int?
    private var bylaAktywnaRamka = false
    public init() {}
    public mutating func przyjmij(_ pcm: [Float]) -> [[Float]] {
        bufor.append(contentsOf: pcm)
        var fragmenty: [[Float]] = []
        let ramka = 320
        while skan + ramka <= bufor.count {
            var energia: Float = 0
            for i in skan..<(skan + ramka) { energia += bufor[i] * bufor[i] }
            let rms = sqrt(energia / Float(ramka))
            let aktywnaRamka = rms >= 0.0001
            if aktywnaRamka { bylaAktywnaRamka = true }
            cisza = aktywnaRamka ? 0 : cisza + ramka
            skan += ramka
            if bylaAktywnaRamka && skan >= 64_000 && cisza >= 9_600 && oczekujacaGranica == nil {
                oczekujacaGranica = skan - 4_800
            }
            // Końcowa pauza pozostaje przy zdaniu. Sam ogon ciszy mógłby
            // dostać od modelu zmyślony tekst. Nie usuwamy żadnych próbek.
            if aktywnaRamka, let granica = oczekujacaGranica {
                fragmenty.append(Array(bufor[..<granica]))
                bufor.removeFirst(granica)
                skan = 0
                cisza = 0
                oczekujacaGranica = nil
                bylaAktywnaRamka = false
            }
        }
        return fragmenty
    }
    public mutating func zakoncz() -> [Float] {
        defer { bufor = []; skan = 0; cisza = 0; oczekujacaGranica = nil; bylaAktywnaRamka = false }
        return bufor
    }
}
