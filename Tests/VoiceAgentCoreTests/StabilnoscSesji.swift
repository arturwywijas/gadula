import VoiceAgentCore

@MainActor
private final class Bramka<Value: Sendable> {
    private var kontynuacja: CheckedContinuation<Value, Never>?
    func czekaj() async -> Value { await withCheckedContinuation { kontynuacja = $0 } }
    func czekajNaZawieszenie() async { while kontynuacja == nil { await Task.yield() } }
    func wznow(_ wynik: Value) { kontynuacja?.resume(returning: wynik); kontynuacja = nil }
}

private final class AudioStartOczekujacy: AudioCapturing {
    let bramka = Bramka<Bool>()
    func start() async throws {
        if !(await bramka.czekaj()) { throw BladTestowy.start }
    }
    func stop() async -> Nagranie { Nagranie(pcm: [], czasTrwania: 0, szczytowaGlosnosc: 0) }
}

private final class TranskrypcjaOczekujaca: Transcribing {
    let bramka = Bramka<Transkrypt>()
    func modelGotowy() async -> Bool { true }
    func transcribe(nagranie: Nagranie, jezyk: String) async throws -> Transkrypt { await bramka.czekaj() }
}

private final class WstawianieOczekujace: TextInserting {
    let bramka = Bramka<WynikWstawienia>()
    func insert(tekst: String) async -> WynikWstawienia { await bramka.czekaj() }
}

private final class GotowoscOczekujaca: Transcribing {
    let bramka = Bramka<Bool>()
    func modelGotowy() async -> Bool { await bramka.czekaj() }
    func transcribe(nagranie: Nagranie, jezyk: String) async throws -> Transkrypt { Transkrypt(tekst: "test") }
}

private final class ZgodaOczekujaca: PermissionChecking {
    let bramka = Bramka<Bool>()
    var mikrofon: Bool { false }
    func poprosOMikrofon() async -> Bool { await bramka.czekaj() }
}

@MainActor
enum TestyStabilnosciSesji {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [
            ("FN17: anulowanie oczekiwania na model nie uruchamia audio", {
                let model = GotowoscOczekujaca()
                let audio = AtrapaAudioZNagraniem(czasTrwania: 1, szczytowaGlosnosc: 0.5)
                let k = KoordynatorDyktowania(audio: audio, transcribing: model, inserting: AtrapaTextInserting(), permissions: zgody())
                let start = Task { await k.handleWyzwalacz() }
                await model.bramka.czekajNaZawieszenie()
                await k.anuluj()
                model.bramka.wznow(true)
                await start.value
                try expectEqual(audio.startCount, 0)
                try expectEqual(k.stan, .bezczynny)
            }),
            ("FN17: pozna zgoda na mikrofon nie uruchamia anulowanej sesji", {
                let permissions = ZgodaOczekujaca()
                let audio = AtrapaAudioZNagraniem(czasTrwania: 1, szczytowaGlosnosc: 0.5)
                let k = KoordynatorDyktowania(audio: audio, transcribing: AtrapaTranscribing(tekst: "test"), inserting: AtrapaTextInserting(), permissions: permissions)
                let start = Task { await k.handleWyzwalacz() }
                await permissions.bramka.czekajNaZawieszenie()
                await k.anuluj()
                permissions.bramka.wznow(true)
                await start.value
                try expectEqual(audio.startCount, 0)
                try expectEqual(k.stan, .bezczynny)
            }),
            ("FN17: start zakonczony po stop nie nadpisuje jego wyniku", {
                let audio = AudioStartOczekujacy()
                let k = koordynator(audio: audio)
                let start = Task { await k.handleWyzwalacz() }
                await audio.bramka.czekajNaZawieszenie()
                await k.zakonczNagrywanie()
                let komunikatStop = k.ostatniKomunikat
                audio.bramka.wznow(false)
                await start.value
                try expectEqual(k.stan, .bezczynny)
                try expectEqual(k.ostatniKomunikat, komunikatStop)
            }),
            ("FN17: pozny sukces startu po anulowaniu nie zmienia stanu", {
                let audio = AudioStartOczekujacy()
                let k = koordynator(audio: audio)
                let start = Task { await k.handleWyzwalacz() }
                await audio.bramka.czekajNaZawieszenie()
                await k.anuluj()
                await k.przerwij(komunikat: "nowszy stan")
                audio.bramka.wznow(true)
                await start.value
                try expectEqual(k.stan, .bezczynny)
                try expectEqual(k.ostatniKomunikat, "nowszy stan")
            }),
            ("FN17: pozny blad startu po anulowaniu nie pokazuje bledu", {
                let audio = AudioStartOczekujacy()
                let k = koordynator(audio: audio)
                let start = Task { await k.handleWyzwalacz() }
                await audio.bramka.czekajNaZawieszenie()
                await k.anuluj()
                audio.bramka.wznow(false)
                await start.value
                try expectEqual(k.stan, .bezczynny)
                try expectEqual(k.pokazujeBlad, false)
            }),
            ("FN17: wynik starej transkrypcji nie wstawia po przerwaniu", {
                let stt = TranskrypcjaOczekujaca()
                let tekst = AtrapaTextInserting()
                let k = KoordynatorDyktowania(audio: AtrapaAudioCapturing(), transcribing: stt, inserting: tekst, permissions: zgody())
                await k.handleWyzwalacz()
                let stop = Task { await k.zakonczNagrywanie() }
                await stt.bramka.czekajNaZawieszenie()
                await k.przerwij(komunikat: "przerwano")
                await k.handleWyzwalacz()
                stt.bramka.wznow(Transkrypt(tekst: "stara sesja"))
                await stop.value
                try expectEqual(tekst.wstawienia, [])
                try expectEqual(k.stan, .nagrywanie)
                await k.anuluj()
            }),
            ("FN17: stary wynik insert nie nadpisuje nowej sesji", {
                let tekst = WstawianieOczekujace()
                let k = KoordynatorDyktowania(audio: AtrapaAudioCapturing(), transcribing: AtrapaTranscribing(tekst: "test"), inserting: tekst, permissions: zgody())
                await k.handleWyzwalacz()
                let stop = Task { await k.zakonczNagrywanie() }
                await tekst.bramka.czekajNaZawieszenie()
                await k.przerwij(komunikat: "przerwano")
                await k.handleWyzwalacz()
                tekst.bramka.wznow(.tylkoSchowek)
                await stop.value
                try expectEqual(k.stan, .nagrywanie)
                try expectEqual(k.ostatniWynikWstawienia, nil)
                await k.anuluj()
            }),
            ("FN17: limit dziala bez zadnej probki PCM", {
                let limit = LimitCzasuNagrania()
                var wywolania = 0
                limit.rozpocznij(po: .milliseconds(5)) { wywolania += 1 }
                try await Task.sleep(for: .milliseconds(50))
                try expectEqual(wywolania, 1)
            }),
            ("FN17: stop usuwa limit i nie wywoluje zakonczenia", {
                let limit = LimitCzasuNagrania()
                var wywolania = 0
                limit.rozpocznij(po: .milliseconds(5)) { wywolania += 1 }
                limit.anuluj()
                try await Task.sleep(for: .milliseconds(50))
                try expectEqual(wywolania, 0)
            }),
            ("FN17: nowa sesja odrzuca limit poprzedniej", {
                let limit = LimitCzasuNagrania()
                var wyniki: [Int] = []
                limit.rozpocznij(po: .milliseconds(5)) { wyniki.append(1) }
                limit.rozpocznij(po: .milliseconds(5)) { wyniki.append(2) }
                try await Task.sleep(for: .milliseconds(50))
                try expectEqual(wyniki, [2])
            }),
        ]
    }
    private static func zgody() -> AtrapaPermissionChecking { AtrapaPermissionChecking(mikrofon: true) }
    private static func koordynator(audio: AudioCapturing) -> KoordynatorDyktowania {
        KoordynatorDyktowania(audio: audio, transcribing: AtrapaTranscribing(tekst: "test"), inserting: AtrapaTextInserting(), permissions: zgody())
    }
}
