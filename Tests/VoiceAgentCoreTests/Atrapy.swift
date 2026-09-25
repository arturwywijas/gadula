import VoiceAgentCore

final class AtrapaAudioCapturing: AudioCapturing {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() async {
        startCount += 1
    }

    func stop() async -> Nagranie {
        stopCount += 1
        return Nagranie(pcm: [0], czasTrwania: 1, szczytowaGlosnosc: 0.5)
    }
}

final class AtrapaTranscribing: Transcribing {
    let tekst: String

    init(tekst: String) {
        self.tekst = tekst
    }

    func modelGotowy() async -> Bool { true }

    func transcribe(nagranie _: Nagranie, jezyk _: String) async -> Transkrypt {
        Transkrypt(tekst: tekst)
    }
}

final class AtrapaTextInserting: TextInserting {
    private(set) var wstawienia: [String] = []
    var wynik: WynikWstawienia

    init(wynik: WynikWstawienia = .wstawione) {
        self.wynik = wynik
    }

    func insert(tekst: String) async -> WynikWstawienia {
        wstawienia.append(tekst)
        return wynik
    }
}

final class AtrapaPermissionChecking: PermissionChecking {
    var mikrofon: Bool

    init(mikrofon: Bool) {
        self.mikrofon = mikrofon
    }
}
