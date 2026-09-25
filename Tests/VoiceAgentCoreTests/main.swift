import VoiceAgentCore

final class AtrapaAudioPotemRzuca: AudioCapturing {
    var rzucPrzyStarcie = false

    func start() async throws {
        if rzucPrzyStarcie { throw BladTestowy.start }
    }

    func stop() async -> Nagranie {
        Nagranie(pcm: [0], czasTrwania: 1, szczytowaGlosnosc: 0.5)
    }
}

enum BladTestowy: Error { case start }

final class AtrapaTranskrypcjaModelNiegotowy: Transcribing {
    func modelGotowy() async -> Bool { true }

    func transcribe(nagranie _: Nagranie, jezyk _: String) async throws -> Transkrypt {
        throw BladTranskrypcji.modelNiegotowy
    }
}

final class AtrapaAudioZNagraniem: AudioCapturing {
    let nagranie: Nagranie
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(czasTrwania: Double, szczytowaGlosnosc: Float, pcm: [Float] = [0]) {
        nagranie = Nagranie(pcm: pcm, czasTrwania: czasTrwania, szczytowaGlosnosc: szczytowaGlosnosc)
    }

    func start() async throws { startCount += 1 }

    func stop() async -> Nagranie {
        stopCount += 1
        return nagranie
    }
}

final class AtrapaTranscribingLicznik: Transcribing {
    let tekst: String
    private(set) var wywolania = 0

    init(tekst: String) { self.tekst = tekst }

    func modelGotowy() async -> Bool { true }

    func transcribe(nagranie _: Nagranie, jezyk _: String) async throws -> Transkrypt {
        wywolania += 1
        return Transkrypt(tekst: tekst)
    }
}

final class AtrapaTranskrypcjaNieudana: Transcribing {
    var rzuc = true

    func modelGotowy() async -> Bool { true }

    func transcribe(nagranie _: Nagranie, jezyk _: String) async throws -> Transkrypt {
        if rzuc { throw BladTranskrypcji.nieudana }
        return Transkrypt(tekst: "druga sesja")
    }
}

final class AtrapaTranscribingWstrzymana: Transcribing, @unchecked Sendable {
    private var kontynuacja: CheckedContinuation<Transkrypt, Never>?

    func modelGotowy() async -> Bool { true }

    func transcribe(nagranie _: Nagranie, jezyk _: String) async throws -> Transkrypt {
        await withCheckedContinuation { kontynuacja = $0 }
    }

    func wznow(_ tekst: String) {
        kontynuacja?.resume(returning: Transkrypt(tekst: tekst))
        kontynuacja = nil
    }
}

final class AtrapaModelNiegotowyPrzedSesja: Transcribing {
    func modelGotowy() async -> Bool { false }

    func transcribe(nagranie _: Nagranie, jezyk _: String) async throws -> Transkrypt {
        Transkrypt(tekst: "nie powinno")
    }
}

final class AudioZawieszoneStop: AudioCapturing {
    private var bramka: CheckedContinuation<Nagranie, Never>?
    private var zatrzymania = 0
    func start() async throws {}
    func stop() async -> Nagranie {
        zatrzymania += 1
        if zatrzymania == 1 { return await withCheckedContinuation { bramka = $0 } }
        return Self.probka
    }
    func czekajNaStop() async { while bramka == nil { await Task.yield() } }
    func wznow() { bramka?.resume(returning: Self.probka); bramka = nil }
    private static var probka: Nagranie { Nagranie(pcm: [0.5], czasTrwania: 1, szczytowaGlosnosc: 0.5) }
}

await runTests([
    ("FN17: anulowanie zawieszonego stop nie wstawia tekstu", {
        let audio = AudioZawieszoneStop()
        let inserting = AtrapaTextInserting()
        let k = KoordynatorDyktowania(audio: audio, transcribing: AtrapaTranscribing(tekst: "syntetyczny"), inserting: inserting, permissions: AtrapaPermissionChecking(mikrofon: true))
        await k.handleWyzwalacz()
        let stop = Task { await k.zakonczNagrywanie() }
        await audio.czekajNaStop()
        await k.anuluj()
        try expectEqual(k.stan, .bezczynny)
        await audio.wznow()
        await stop.value
        try expectEqual(inserting.wstawienia, [])
        try expectEqual(k.stan, .bezczynny)
    }),
    ("przygotowanie tekstu: zwykły tekst, przycięte białe znaki, ogonki bez zmian", {
        try expectEqual(
            przygotujTekstDoWstawienia("  Zażółć gęślą jaźń  "),
            "Zażółć gęślą jaźń"
        )
    }),
    ("happy-path: skrót → nagranie → transkrypt → TextInserting dokładnie raz", {
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranscribing(tekst: "  Zażółć gęślą jaźń  "),
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(inserting.wstawienia, ["Zażółć gęślą jaźń"])
        try expectEqual(koordynator.stan, .bezczynny)
        try expectEqual(koordynator.ostatniWynikWstawienia, .wstawione)
    }),
    ("brak Accessibility: wynik tylko schowek, transkrypt nie ginie", {
        let inserting = AtrapaTextInserting(wynik: .tylkoSchowek)
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranscribing(tekst: "test"),
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.ostatniWynikWstawienia, .tylkoSchowek)
        try expectEqual(inserting.wstawienia, ["test"])
        try expectEqual(koordynator.ostatniKomunikat, "wciśnij Cmd-V")
    }),
    ("druga sesja po nadaniu Accessibility czyści komunikat", {
        let inserting = AtrapaTextInserting(wynik: .tylkoSchowek)
        let permissions = AtrapaPermissionChecking(mikrofon: true)
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranscribing(tekst: "raz"),
            inserting: inserting,
            permissions: permissions
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.ostatniKomunikat, "wciśnij Cmd-V")
        inserting.wynik = .wstawione
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.ostatniWynikWstawienia, .wstawione)
        try expectEqual(koordynator.ostatniKomunikat, nil as String?)
    }),
    ("nieudane z portu zostaje nieudane", {
        let inserting = AtrapaTextInserting(wynik: .nieudane)
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranscribing(tekst: "test"),
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.ostatniWynikWstawienia, .nieudane)
        try expectEqual(koordynator.ostatniKomunikat, nil as String?)
        try expectEqual(inserting.wstawienia, ["test"])
    }),
    ("magazyn: puste źródło daje wartości domyślne", {
        let magazyn = MagazynUstawien(zrodlo: PamiecMagazynKluczy())
        try expectEqual(magazyn.string(klucz: "model", domyslna: "large-v3-turbo"), "large-v3-turbo")
    }),
    ("magazyn: odczyt po zapisie", {
        let magazyn = MagazynUstawien(zrodlo: PamiecMagazynKluczy())
        magazyn.ustaw("small", klucz: "model")
        magazyn.ustaw(true, klucz: "autostart")
        try expectEqual(magazyn.string(klucz: "model", domyslna: "large-v3-turbo"), "small")
    }),
    ("magazyn: brak klucza nie powoduje błędu", {
        let magazyn = MagazynUstawien(zrodlo: PamiecMagazynKluczy())
        try expectEqual(magazyn.string(klucz: "nieistnieje", domyslna: "ok"), "ok")
    }),
    ("brak zgody na mikrofon: zero transkrypcji i zero wstawienia", {
        let audio = AtrapaAudioCapturing()
        let transcribing = AtrapaTranscribing(tekst: "nie powinno")
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: transcribing,
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: false)
        )
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.stan, .bezczynny)
        try expectEqual(audio.startCount, 0)
        try expectEqual(audio.stopCount, 0)
        try expectEqual(inserting.wstawienia, [String]())
        try expectEqual(koordynator.ostatniWynikWstawienia, nil as WynikWstawienia?)
        let komunikat = koordynator.ostatniKomunikat ?? ""
        if !komunikat.contains("mikrofon") {
            throw TestFailure.failed("oczekiwany komunikat o mikrofonie, jest: \(komunikat)")
        }
        await koordynator.handleWyzwalacz()
        try expectEqual(audio.startCount, 0)
        try expectEqual(inserting.wstawienia, [String]())
    }),
    ("odmowa mikrofonu czysci wynik poprzedniej sesji", {
        let inserting = AtrapaTextInserting(wynik: .tylkoSchowek)
        let permissions = AtrapaPermissionChecking(mikrofon: true)
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranscribing(tekst: "raz"),
            inserting: inserting,
            permissions: permissions
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.ostatniWynikWstawienia, .tylkoSchowek)

        permissions.mikrofon = false
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.ostatniWynikWstawienia, nil as WynikWstawienia?)
        try expectEqual(koordynator.stan, .bezczynny)
    }),
    ("blad startu audio czysci wynik poprzedniej sesji", {
        let audio = AtrapaAudioPotemRzuca()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: AtrapaTranscribing(tekst: "x"),
            inserting: AtrapaTextInserting(wynik: .wstawione),
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        audio.rzucPrzyStarcie = false
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.ostatniWynikWstawienia, .wstawione)

        audio.rzucPrzyStarcie = true
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.ostatniWynikWstawienia, nil as WynikWstawienia?)
        try expectEqual(koordynator.stan, .bezczynny)
    }),
    ("transkrypt trafia do wstawiania bez modyfikacji tresci", {
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranscribing(tekst: "Zażółć gęślą jaźń"),
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(inserting.wstawienia, ["Zażółć gęślą jaźń"])
    }),
    ("model niegotowy: sesja konczy sie komunikatem, zero wstawienia", {
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranskrypcjaModelNiegotowy(),
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.stan, .bezczynny)
        try expectEqual(inserting.wstawienia, [String]())
        try expectEqual(koordynator.ostatniWynikWstawienia, nil as WynikWstawienia?)
        let komunikat = koordynator.ostatniKomunikat ?? ""
        if !komunikat.contains("niegotowy") {
            throw TestFailure.failed("oczekiwany komunikat o modelu, jest: \(komunikat)")
        }
    }),
    ("cisza: zero wstawiania i brak komunikatu bledu", {
        let audio = AtrapaAudioZNagraniem(
            czasTrwania: 1,
            szczytowaGlosnosc: ProgiSesji.minimalnaSzczytowaGlosnosc / 2
        )
        let transcribing = AtrapaTranscribingLicznik(tekst: "nie powinno")
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: transcribing,
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(inserting.wstawienia, [String]())
        try expectEqual(koordynator.ostatniKomunikat, nil as String?)
        try expectEqual(koordynator.stan, .bezczynny)
    }),
    ("nagranie krotsze od progu: zero transkrypcji", {
        let audio = AtrapaAudioZNagraniem(
            czasTrwania: ProgiSesji.minimalnyCzasTrwania / 2,
            szczytowaGlosnosc: 0.5
        )
        let transcribing = AtrapaTranscribingLicznik(tekst: "nie powinno")
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: transcribing,
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(transcribing.wywolania, 0)
        try expectEqual(inserting.wstawienia, [String]())
        try expectEqual(koordynator.ostatniKomunikat, nil as String?)
        try expectEqual(koordynator.stan, .bezczynny)
    }),
    ("przekroczenie limitu: transkrypcja tego co juz jest", {
        let audio = AtrapaAudioZNagraniem(
            czasTrwania: ProgiSesji.maksymalnyCzasTrwania + 1,
            szczytowaGlosnosc: 0.5
        )
        let transcribing = AtrapaTranscribingLicznik(tekst: "długie")
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: transcribing,
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.zakonczNagrywanie()
        try expectEqual(transcribing.wywolania, 1)
        try expectEqual(inserting.wstawienia, ["długie"])
        try expectEqual(koordynator.stan, .bezczynny)
    }),
    ("pusty transkrypt i sama interpunkcja: zero wstawiania", {
        for tekst in ["", "   ", " ...!? "] {
            let audio = AtrapaAudioZNagraniem(czasTrwania: 1, szczytowaGlosnosc: 0.5)
            let transcribing = AtrapaTranscribingLicznik(tekst: tekst)
            let inserting = AtrapaTextInserting()
            let koordynator = KoordynatorDyktowania(
                audio: audio,
                transcribing: transcribing,
                inserting: inserting,
                permissions: AtrapaPermissionChecking(mikrofon: true)
            )
            await koordynator.handleWyzwalacz()
            await koordynator.handleWyzwalacz()
            try expectEqual(transcribing.wywolania, 1)
            try expectEqual(inserting.wstawienia, [String]())
            try expectEqual(koordynator.ostatniKomunikat, nil as String?)
            try expectEqual(koordynator.pokazujeBlad, false)
            try expectEqual(koordynator.stan, .bezczynny)
        }
    }),
    ("anulowanie: zero transkrypcji i zero wstawienia", {
        let audio = AtrapaAudioZNagraniem(czasTrwania: 1, szczytowaGlosnosc: 0.5)
        let transcribing = AtrapaTranscribingLicznik(tekst: "nie powinno")
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: transcribing,
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.anuluj()
        try expectEqual(transcribing.wywolania, 0)
        try expectEqual(inserting.wstawienia, [String]())
        try expectEqual(audio.stopCount, 1)
        try expectEqual(koordynator.stan, .bezczynny)
    }),
    ("wyjatek transkrypcji: bezczynny i druga sesja dziala", {
        let transcribing = AtrapaTranskrypcjaNieudana()
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: transcribing,
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.stan, .bezczynny)
        try expectEqual(inserting.wstawienia, [String]())
        let komunikat = koordynator.ostatniKomunikat ?? ""
        if !komunikat.contains("rozpoznać") {
            throw TestFailure.failed("oczekiwany komunikat o rozpoznaniu, jest: \(komunikat)")
        }
        transcribing.rzuc = false
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(inserting.wstawienia, ["druga sesja"])
        try expectEqual(koordynator.stan, .bezczynny)
    }),
    ("skrot w trakcie transkrypcji jest ignorowany", {
        let audio = AtrapaAudioZNagraniem(czasTrwania: 1, szczytowaGlosnosc: 0.5)
        let transcribing = AtrapaTranscribingWstrzymana()
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: transcribing,
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        let sesja = Task { await koordynator.handleWyzwalacz() }
        var czekano = 0
        while koordynator.stan != .transkrypcja, czekano < 1000 {
            czekano += 1
            await Task.yield()
        }
        try expectEqual(koordynator.stan, .transkrypcja)
        try expectEqual(audio.startCount, 1)
        await koordynator.handleWyzwalacz()
        try expectEqual(audio.startCount, 1)
        transcribing.wznow("ok")
        await sesja.value
        try expectEqual(inserting.wstawienia, ["ok"])
        try expectEqual(koordynator.stan, .bezczynny)
    }),
    ("model niegotowy przed nagraniem: zero startu audio", {
        let audio = AtrapaAudioZNagraniem(czasTrwania: 1, szczytowaGlosnosc: 0.5)
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: AtrapaModelNiegotowyPrzedSesja(),
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        try expectEqual(audio.startCount, 0)
        try expectEqual(inserting.wstawienia, [String]())
        try expectEqual(koordynator.stan, .bezczynny)
        let komunikat = koordynator.ostatniKomunikat ?? ""
        if !komunikat.contains("niegotowy") {
            throw TestFailure.failed("oczekiwany komunikat o modelu, jest: \(komunikat)")
        }
    }),
    ("po odmowie mikrofonu ikona pokazuje blad", {
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranscribing(tekst: "nie powinno"),
            inserting: AtrapaTextInserting(),
            permissions: AtrapaPermissionChecking(mikrofon: false)
        )
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.stanIkony, .blad)
    }),
    ("po wyczyscIkoneBledu ikona wraca do bezczynnego", {
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioCapturing(),
            transcribing: AtrapaTranscribing(tekst: "nie powinno"),
            inserting: AtrapaTextInserting(),
            permissions: AtrapaPermissionChecking(mikrofon: false)
        )
        await koordynator.handleWyzwalacz()
        koordynator.wyczyscIkoneBledu()
        try expectEqual(koordynator.stanIkony, .bezczynny)
    }),
    ("w trakcie nagrania ikona nagrywa, w trakcie transkrypcji przetwarza", {
        let transcribing = AtrapaTranscribingWstrzymana()
        let koordynator = KoordynatorDyktowania(
            audio: AtrapaAudioZNagraniem(czasTrwania: 1, szczytowaGlosnosc: 0.5),
            transcribing: transcribing,
            inserting: AtrapaTextInserting(),
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        try expectEqual(koordynator.stanIkony, .nagrywa)
        let sesja = Task { await koordynator.handleWyzwalacz() }
        var czekano = 0
        while koordynator.stan != .transkrypcja, czekano < 1000 {
            czekano += 1
            await Task.yield()
        }
        try expectEqual(koordynator.stanIkony, .przetwarza)
        transcribing.wznow("ok")
        await sesja.value
    }),
    ("zero buforow z silnika: blad i komunikat", {
        let audio = AtrapaAudioZNagraniem(czasTrwania: 0, szczytowaGlosnosc: 0, pcm: [])
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: AtrapaTranscribing(tekst: "nie powinno"),
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(inserting.wstawienia, [String]())
        try expectEqual(koordynator.pokazujeBlad, true)
        try expectEqual(koordynator.stan, .bezczynny)
        let komunikat = koordynator.ostatniKomunikat ?? ""
        if komunikat.isEmpty {
            throw TestFailure.failed("oczekiwany komunikat o braku dzwieku z mikrofonu")
        }
    }),
    ("cisza z buforami: dalej bez alarmu", {
        let audio = AtrapaAudioZNagraniem(
            czasTrwania: 1,
            szczytowaGlosnosc: ProgiSesji.minimalnaSzczytowaGlosnosc / 2,
            pcm: [0, 0, 0]
        )
        let inserting = AtrapaTextInserting()
        let koordynator = KoordynatorDyktowania(
            audio: audio,
            transcribing: AtrapaTranscribing(tekst: "nie powinno"),
            inserting: inserting,
            permissions: AtrapaPermissionChecking(mikrofon: true)
        )
        await koordynator.handleWyzwalacz()
        await koordynator.handleWyzwalacz()
        try expectEqual(inserting.wstawienia, [String]())
        try expectEqual(koordynator.ostatniKomunikat, nil as String?)
        try expectEqual(koordynator.pokazujeBlad, false)
        try expectEqual(koordynator.stan, .bezczynny)
    }),

])
