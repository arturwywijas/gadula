// Testuje produkcyjny MikrofonAudioCapturing bez silnika, mikrofonu i okien.
import Foundation
import VoiceAgentCore

final class PamiecMagazynKluczy: MagazynKluczy {
    func object(forKey key: String) -> Any? { nil }
    func set(_ value: Any?, forKey key: String) {}
}

struct AppLogger {
    init(category: String) {}
    func info(_ tekst: @autoclosure () -> String) {}
    func notice(_ tekst: @autoclosure () -> String) {}
    func error(_ tekst: @autoclosure () -> String) {}
}

@MainActor
protocol WskaznikNagrywania: AnyObject {
    func rozpocznij()
    func zakoncz()
    func przyjmij(szczyt: Float, czas: Double)
}
@MainActor
final class LicznikWskaznika: WskaznikNagrywania {
    var pokazania = 0
    var ukrycia = 0
    func rozpocznij() { pokazania += 1 }
    func zakoncz() { ukrycia += 1 }
    func przyjmij(szczyt: Float, czas: Double) {}
}

enum AudioDeviceManager {
    static func defaultInputDeviceID() -> UInt32? { 1 }
    static func deviceID(forUID: String) -> UInt32? { 1 }
    static func name(for: UInt32) -> String? { "syntetyczny" }
}
enum PotwierdzenieWejsciaAudio {
    static func ustaw(_ id: UInt32) async -> PotwierdzenieZmianyAudio.Wynik { .kontynuuj(urzadzenie: id, powod: .hal) }
}

@MainActor
final class AudioRecorder {
    nonisolated static let targetSampleRate: Double = 16_000
    static weak var ostatni: AudioRecorder?
    enum State { case idle, recording }
    var state: State = .idle
    var onPoziom: ((Float, Double) -> Void)?
    var onZatrzymanie: (() -> Void)?
    var onLimitCzasu: (([Float]) -> Void)?
    var onZmianaKonfiguracji: ((Double) -> Void)?
    var ochrona = OchronaRekonfiguracjiAudio()
    var czas: Double = 0
    var przeladowania = 0
    init() { Self.ostatni = self }
    func start() throws {
        state = .recording
        ochrona.rozpocznijPrzebudowe()
        ochrona.zakonczPrzebudowe(czas: 0)
    }
    func stop() -> [Float] {
        guard state == .recording else { return [] }
        state = .idle
        onZatrzymanie?()
        return []
    }
    func ocenZmianeKonfiguracji(czasZdarzenia: Double) -> OchronaRekonfiguracjiAudio.Decyzja {
        czas = czasZdarzenia
        return ochrona.ocen(czasZdarzenia: czas, nagrywa: state == .recording, istnieje: true, wymaga: true)
    }
    func przeladujPoZmianieKonfiguracji() throws {
        przeladowania += 1
        ochrona.rozpocznijPrzebudowe()
        ochrona.zakonczPrzebudowe(czas: czas)
    }
}

final class BezSTT: Transcribing {
    func modelGotowy() async -> Bool { true }
    func transcribe(nagranie: Nagranie, jezyk: String) async throws -> Transkrypt { fatalError("Limit rekonfiguracji nie transkrybuje") }
}
final class BezWstawienia: TextInserting {
    func insert(tekst: String) async -> WynikWstawienia { fatalError("Limit rekonfiguracji nie wstawia") }
}
final class Zgody: PermissionChecking {
    var mikrofon: Bool { true }
}

@main
struct Proba {
    @MainActor static func main() async throws {
        let wskaznik = LicznikWskaznika()
        let audio = MikrofonAudioCapturing(magazyn: MagazynUstawien(zrodlo: PamiecMagazynKluczy()), wskaznik: wskaznik)
        let k = KoordynatorDyktowania(audio: audio, transcribing: BezSTT(), inserting: BezWstawienia(), permissions: Zgody())
        audio.podlacz(koordynator: k)
        await k.handleWyzwalacz()
        let recorder = AudioRecorder.ostatni!
        recorder.onZmianaKonfiguracji?(0.6)
        assert(recorder.przeladowania == 0)
        recorder.onZmianaKonfiguracji?(2)
        recorder.onZmianaKonfiguracji?(2.6)
        recorder.onZmianaKonfiguracji?(4)
        assert(recorder.przeladowania == 2)
        assert(wskaznik.pokazania == 1 && wskaznik.ukrycia == 0)
        recorder.onZmianaKonfiguracji?(6)
        for _ in 0..<100 where k.stan != .bezczynny { await Task.yield() }
        assert(recorder.state == .idle && k.stan == .bezczynny)
        assert(k.ostatniKomunikat?.contains("dwóch próbach") == true)
        assert(wskaznik.pokazania == 1 && wskaznik.ukrycia == 1)
        print("PASS adapter: wlasne zdarzenie ignorowane, dwa reload bez migania, limit zatrzymuje z komunikatem")
    }
}
