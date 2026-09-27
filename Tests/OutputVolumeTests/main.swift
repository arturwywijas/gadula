// autor: Codex, gadula-dzwiek-aktualizacje-20260927
import Foundation
import VoiceAgentCore

@main enum ProbaGlosnosci {
    @MainActor static func main() async {
        let glosniki = GlosnoscSystemowa()
        guard let id = glosniki.domyslneWyjscie, let przed = glosniki.odczytaj(id) else {
            print("SKIP: wyjście nie udostępnia regulacji głośności"); exit(2)
        }
        guard (0..<30).allSatisfy({ _ in glosniki.domyslneWyjscie == id }) else {
            print("FAIL: niestabilna tożsamość tego samego wyjścia"); exit(1)
        }
        let s = SciszanieDzwieku(wyjscie: glosniki)
        defer { s.przywrocNatychmiast() }
        let start = ProcessInfo.processInfo.systemUptime
        s.rozpocznij(czas: start)
        for _ in 0..<20 { s.krok(czas: ProcessInfo.processInfo.systemUptime); try? await Task.sleep(for: .milliseconds(40)) }
        let podczas = glosniki.odczytaj(id) ?? []
        s.zakoncz(czas: ProcessInfo.processInfo.systemUptime)
        for _ in 0..<25 { s.krok(czas: ProcessInfo.processInfo.systemUptime); try? await Task.sleep(for: .milliseconds(40)) }
        let po = glosniki.odczytaj(id) ?? []
        let sciszono = przed.count == podczas.count && zip(przed, podczas).allSatisfy { abs($0 * 0.35 - $1) < 0.02 }
        let odtworzono = przed.count == po.count && zip(przed, po).allSatisfy { abs($0 - $1) < 0.012 }
        print("Głośność przed=\(przed), podczas=\(podczas), po=\(po)")
        print("\(sciszono && odtworzono ? "PASS" : "FAIL") fizyczne ściszanie i odtwarzanie głośności")
        if !sciszono || !odtworzono { s.przywrocNatychmiast(); exit(1) }
    }
}
