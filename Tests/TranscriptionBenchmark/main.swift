// autor: Codex, gadula-dyktowanie-20260927
// Wyłącznie jawne, syntetyczne pliki testowe; nigdy mikrofon ani zapis wypowiedzi użytkownika.
import Foundation
import AVFoundation
import VoiceAgentCore

final class UstawieniaProby: MagazynKluczy {
    var wartosci: [String: Any] = ["model": "large-v3-turbo"]
    func object(forKey key: String) -> Any? { wartosci[key] }
    func set(_ value: Any?, forKey key: String) { wartosci[key] = value }
}
@main enum PorownanieSTT {
    @MainActor static func main() async throws {
        let dane = UstawieniaProby()
        let stt = LokalnaTranskrypcja(magazyn: MagazynUstawien(zrodlo: dane))
        let start = Date()
        guard await stt.modelGotowy() else { fatalError("Model niedostępny") }
        print("PREPARE seconds=\(Date().timeIntervalSince(start))")
        for path in CommandLine.arguments.dropFirst() {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { fatalError("Wymagane mono 16 kHz Float32") }
            try file.read(into: buffer)
            let pcm = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            for tryb in ["batch", "stream"] {
                dane.wartosci[SlownikDyktowania.klucz] = "Gaduła\nArtur Wywijas\nFrankentools\nUnity\nSuper Hierarchy"
                if URL(fileURLWithPath: path).lastPathComponent == "gesta.caf" {
                    dane.wartosci[SlownikDyktowania.klucz] = Array(1...40).map { "Nazwa projektu numer \($0)" }.joined(separator: "\n")
                }
                dane.wartosci[TrybTekstu.klucz] = TrybTekstu.wierny.rawValue
                for proba in 1...2 {
                    stt.rozpocznijSesje()
                    let poczatek = ContinuousClock.now
                    if tryb == "stream" {
                        for offset in stride(from: 0, to: pcm.count, by: 4096) {
                            let koniec = min(offset + 4096, pcm.count)
                            stt.przyjmijProbki(Array(pcm[offset..<koniec]))
                            try await Task.sleep(until: poczatek.advanced(by: .seconds(Double(koniec) / 16_000)), clock: .continuous)
                        }
                    }
                    let stop = Date()
                    let wynik = try await stt.transcribe(nagranie: Nagranie(pcm: pcm, czasTrwania: Double(pcm.count)/16_000, szczytowaGlosnosc: pcm.map(abs).max() ?? 0), jezyk: "pl")
                    let wiersz: [String:Any] = ["file": URL(fileURLWithPath:path).lastPathComponent, "mode": tryb, "attempt": proba, "audio":Double(pcm.count)/16_000,"afterStop":Date().timeIntervalSince(stop),"text":wynik.surowyTekst]
                    print(String(data:try JSONSerialization.data(withJSONObject:wiersz, options:[.sortedKeys]),encoding:.utf8)!)
                }
            }
        }
    }
}
