// autor: Codex, gadula-stabilnosc-20260927
// Test sprzętowy: korzysta z bieżącego wejścia, nie zapisuje ani nie transkrybuje głosu.
import AVFoundation
import CoreAudio
import VoiceAgentCore
import Foundation

@main
enum ProbaMikrofonu {
    @MainActor static func main() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            print("SKIP: proces testowy nie ma uprawnienia do mikrofonu")
            exit(2)
        }
        func outputRate() -> Double {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var id: AudioDeviceID = 0; var size: UInt32 = 4
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return 0 }
            address.mSelector = kAudioDevicePropertyNominalSampleRate
            var hz: Double = 0; size = 8
            _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &hz)
            return hz
        }
        let sprawdzPowrot = CommandLine.arguments.contains("--sprawdz-powrot")
        let przed = outputRate()
        print("Wyjście przed nagraniem: \(przed) Hz")
        let glosniki = GlosnoscSystemowa()
        let idWyjscia = glosniki.domyslneWyjscie
        let glosnoscPrzed = idWyjscia.flatMap { glosniki.odczytaj($0) }
        let sciszanie = SciszanieDzwieku(wyjscie: glosniki)
        let sciszaj = CommandLine.arguments.contains("--sciszaj")
        let zegar = Task { @MainActor in
            while !Task.isCancelled {
                sciszanie.krok(czas: ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        defer { zegar.cancel(); sciszanie.przywrocNatychmiast() }
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
                if sciszaj { sciszanie.rozpocznij(czas: ProcessInfo.processInfo.systemUptime) }
                try recorder.start()
                try await Task.sleep(for: .seconds(6))
                let samples = recorder.stop()
                if sciszaj { sciszanie.zakoncz(czas: ProcessInfo.processInfo.systemUptime) }
                let sukces = !przerwano && samples.count >= 16_000
                print("\(sukces ? "PASS" : "FAIL") mikrofon, sesja \(numer): \(samples.count) próbek, przerwano=\(przerwano)")
                if !sukces { sciszanie.przywrocNatychmiast(); exit(1) }
                if !CommandLine.arguments.contains("--szybko") { try await Task.sleep(for: .seconds(4)) }
                let po = outputRate()
                print("Wyjście po stop: \(po) Hz")
                if sciszaj, let idWyjscia, let glosnoscPrzed {
                    let glosnoscPo = glosniki.odczytaj(idWyjscia) ?? []
                    let poprawna = glosnoscPrzed.count == glosnoscPo.count && zip(glosnoscPrzed, glosnoscPo).allSatisfy { abs($0 - $1) < 0.0001 }
                    print("\(poprawna ? "PASS" : "FAIL") głośność: przed=\(glosnoscPrzed), po=\(glosnoscPo)")
                    if !poprawna { sciszanie.przywrocNatychmiast(); exit(1) }
                }
                if sprawdzPowrot && (przed < 44_100 || po < 44_100) {
                    print("FAIL: odtwarzanie Bluetooth nie wróciło do profilu muzycznego")
                    sciszanie.przywrocNatychmiast(); exit(1)
                }
            }
            exit(0)
        } catch {
            print("FAIL mikrofon: start nieudany (\(type(of: error)))")
            sciszanie.przywrocNatychmiast(); exit(1)
        }
    }
}
