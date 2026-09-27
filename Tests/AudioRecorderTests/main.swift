// autor: Codex, gadula-stabilnosc-20260927
// Test sprzętowy: korzysta z bieżącego wejścia, nie zapisuje ani nie transkrybuje głosu.
import AVFoundation
import Foundation

@main
enum ProbaMikrofonu {
    @MainActor static func main() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            print("SKIP: proces testowy nie ma uprawnienia do mikrofonu")
            exit(2)
        }
        let recorder = AudioRecorder()
        var przerwano = false
        recorder.onBrakDzwieku = { przerwano = true }
        recorder.onZmianaKonfiguracji = { czas in
            switch recorder.ocenZmianeKonfiguracji(czasZdarzenia: czas) {
            case .przeladuj:
                do { try recorder.przeladujPoZmianieKonfiguracji() }
                catch { przerwano = true; _ = recorder.stop() }
            case .limitProb, .odlaczone:
                przerwano = true
                _ = recorder.stop()
            case .bezZmiany, .ignorujWlasna: break
            }
        }
        do {
            let liczbaSesji = min(10, max(1, Int(CommandLine.arguments.dropFirst().first ?? "1") ?? 1))
            for numer in 1...liczbaSesji {
                przerwano = false
                try recorder.start()
                try await Task.sleep(for: .seconds(6))
                let samples = recorder.stop()
                let sukces = !przerwano && samples.count >= 16_000
                print("\(sukces ? "PASS" : "FAIL") mikrofon, sesja \(numer): \(samples.count) próbek, przerwano=\(przerwano)")
                if !sukces { exit(1) }
            }
            exit(0)
        } catch {
            print("FAIL mikrofon: start nieudany (\(type(of: error)))")
            exit(1)
        }
    }
}
