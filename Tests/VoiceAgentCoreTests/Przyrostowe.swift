// autor: Codex, gadula-dyktowanie-20260927
import VoiceAgentCore

@MainActor
enum TestyPrzyrostowe {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [("podział: długa pauza nie tworzy fragmentów samej ciszy", {
            var podzial = PodzialNagrania()
            let pcm = [Float](repeating: 0.1, count: 64_000) + [Float](repeating: 0.00005, count: 160_000) + [Float](repeating: 0.1, count: 16_000)
            var fragmenty = podzial.przyjmij(pcm)
            fragmenty.append(podzial.zakoncz())
            try expectEqual(fragmenty.filter { !$0.contains(where: { abs($0) >= 0.0001 }) }.count, 0)
            try expectEqual(fragmenty.flatMap { $0 }, pcm)
        }), ("podział: końcowa pauza pozostaje przy wypowiedzi", {
            var podzial = PodzialNagrania()
            let pcm = [Float](repeating: 0.1, count: 70_000) + [Float](repeating: 0.00005, count: 20_000)
            try expectEqual(podzial.przyjmij(pcm).count, 0)
            try expectEqual(podzial.zakoncz(), pcm)
        }), ("sesja: puste STT nie usuwa poprzedniego wyniku", {
            let stt = ZmiennyWynik()
            let k = KoordynatorDyktowania(audio: AtrapaAudioCapturing(), transcribing: stt, inserting: AtrapaTextInserting(), permissions: AtrapaPermissionChecking(mikrofon: true))
            await k.handleWyzwalacz(); await k.handleWyzwalacz()
            stt.tekst = "   "
            await k.handleWyzwalacz(); await k.handleWyzwalacz()
            try expectEqual(k.ostatniSurowyTranskrypt, "Zachowaj ten tekst.")
        }), ("sesja: zgoda mikrofonu poprzedza końcowe przygotowanie modelu", {
            let stt = ModelPoZgodzie()
            let zgoda = ZgodaPrzedModelem(stt: stt)
            let k = KoordynatorDyktowania(audio: AudioZeStrumieniem(), transcribing: stt, inserting: AtrapaTextInserting(), permissions: zgoda)
            await k.handleWyzwalacz()
            try expectEqual(stt.zgodaPodczasPrzygotowania, true)
            await k.anuluj()
        }), ("sesja: anulowanie nie odbiera poprzedniego surowego tekstu", {
            let k = KoordynatorDyktowania(audio: AtrapaAudioCapturing(), transcribing: AtrapaTranscribing(tekst: "Pierwszy wynik."), inserting: AtrapaTextInserting(), permissions: AtrapaPermissionChecking(mikrofon: true))
            await k.handleWyzwalacz(); await k.handleWyzwalacz()
            try expectEqual(k.ostatniSurowyTranskrypt, "Pierwszy wynik.")
            await k.handleWyzwalacz(); await k.anuluj()
            try expectEqual(k.ostatniSurowyTranskrypt, "Pierwszy wynik.")
        }), ("strumień: cicha końcówka pozostaje w danych", {
            var odebrane: [Float] = []
            let silnik = TranskrypcjaPrzyrostowa { pcm in odebrane.append(contentsOf: pcm); return "tekst" }
            let ciszej = (0..<12_000).map { $0.isMultiple(of: 2) ? Float(0.0009) : Float(-0.0006) }
            let pcm = [Float](repeating: 0.1, count: 70_000) + [Float](repeating: 0, count: 12_000) + ciszej
            silnik.rozpocznij(); silnik.przyjmij(pcm)
            _ = try await silnik.zakoncz(caleNagranie: pcm)
            try expectEqual(odebrane, pcm)
        }), ("strumień: anulowanie dociera do aktywnego zadania pod kolejką", {
            var wywolania = 0
            var anulowanoAktywne = false
            let silnik = TranskrypcjaPrzyrostowa { _ in
                wywolania += 1
                if wywolania == 1 {
                    do { try await Task.sleep(for: .milliseconds(300)) }
                    catch { anulowanoAktywne = true; throw error }
                }
                return "nowy"
            }
            let fragment = [Float](repeating: 0.1, count: 70_000) + [Float](repeating: 0, count: 12_000)
            silnik.rozpocznij(); silnik.przyjmij(fragment + fragment)
            for _ in 0..<30 { await Task.yield() }
            try expectEqual(wywolania, 1)
            silnik.anuluj(); silnik.rozpocznij(); silnik.przyjmij([0.3])
            try expectEqual(try await silnik.zakoncz(caleNagranie: [0.3]), "nowy")
            try expectEqual(anulowanoAktywne, true)
        }), ("gotowość: start nie oznacza gotowego mikrofonu", {
            let audio = AudioZeStrumieniem()
            let k = KoordynatorDyktowania(audio: audio, transcribing: STTZeStrumieniem(), inserting: AtrapaTextInserting(), permissions: AtrapaPermissionChecking(mikrofon: true))
            var stany: [GotowoscDyktowania] = []
            k.poZmianieGotowosci = { stany.append($0) }
            await k.handleWyzwalacz()
            try expectEqual(stany, [.model, .mikrofon])
            try expectEqual(k.gotowosc, .mikrofon)
            k.mikrofonOdbieraDzwiek()
            try expectEqual(k.gotowosc, .gotowa)
            await k.anuluj()
            k.mikrofonOdbieraDzwiek()
            try expectEqual(k.gotowosc, .ukryta)
        }), ("strumień: pracuje przed stop, nie gubi próbek i zachowuje powtórzenia", {
            var odebrane: [[Float]] = []
            let silnik = TranskrypcjaPrzyrostowa { pcm in odebrane.append(pcm); return "Tak." }
            let pcm = [Float](repeating: 0.1, count: 70_111) + [Float](repeating: 0, count: 12_000) + [Float](repeating: 0.2, count: 7_111)
            silnik.rozpocznij()
            for start in stride(from: 0, to: pcm.count, by: 4096) { silnik.przyjmij(Array(pcm[start..<min(pcm.count, start+4096)])) }
            for _ in 0..<20 { await Task.yield() }
            try expectEqual(odebrane.count, 1)
            try expectEqual(try await silnik.zakoncz(caleNagranie: pcm), "Tak. Tak.")
            try expectEqual(odebrane.flatMap { $0 }, pcm)
        }), ("strumień: brak pauz i krótka końcówka pozostają w całości", {
            var otrzymane: [Float] = []
            let silnik = TranskrypcjaPrzyrostowa { pcm in otrzymane = pcm; return "ciągła mowa" }
            let pcm = [Float](repeating: 0.1, count: 480_777)
            silnik.rozpocznij(); silnik.przyjmij(pcm)
            _ = try await silnik.zakoncz(caleNagranie: pcm)
            try expectEqual(otrzymane, pcm)
        }), ("strumień: błąd fragmentu zastępuje całością, bez podwójnego tekstu", {
            var wywolania = 0
            let silnik = TranskrypcjaPrzyrostowa { pcm in
                wywolania += 1
                if wywolania == 1 { throw BladTestowy.start }
                try expectEqual(pcm.count, 100_000)
                return "pełne nagranie"
            }
            let pcm = [Float](repeating: 0.1, count: 70_000) + [Float](repeating: 0, count: 30_000)
            silnik.rozpocznij(); silnik.przyjmij(pcm)
            try expectEqual(try await silnik.zakoncz(caleNagranie: pcm), "pełne nagranie")
            try expectEqual(wywolania, 2)
        }), ("strumień: opóźniona stara sesja nie wchodzi w nową", {
            var wznow: CheckedContinuation<Void, Never>?
            var aktywne = 0
            var maksimum = 0
            var wywolania = 0
            let silnik = TranskrypcjaPrzyrostowa { _ in
                aktywne += 1; maksimum = max(maksimum, aktywne); wywolania += 1
                let nr = wywolania
                if nr == 1 { await withCheckedContinuation { wznow = $0 } }
                aktywne -= 1
                return nr == 1 ? "stary" : "nowy"
            }
            let pcm = [Float](repeating: 0.1, count: 70_000) + [Float](repeating: 0, count: 12_000) + [Float](repeating: 0.1, count: 640)
            silnik.rozpocznij(); silnik.przyjmij(pcm)
            for _ in 0..<20 { await Task.yield() }
            try expectEqual(wywolania, 1)
            silnik.anuluj(); silnik.rozpocznij()
            let nowe: [Float] = [0.2, 0.3]
            silnik.przyjmij(nowe)
            let wynik = Task { try await silnik.zakoncz(caleNagranie: nowe) }
            for _ in 0..<20 { await Task.yield() }
            try expectEqual(wywolania, 1)
            wznow?.resume()
            try expectEqual(try await wynik.value, "nowy")
            try expectEqual(maksimum, 1)
        }), ("strumień: anulowany fallback nie dekoduje równolegle z nową sesją", {
            var wznow: CheckedContinuation<Void, Never>?
            var aktywne = 0
            var maksimum = 0
            var wywolania = 0
            let silnik = TranskrypcjaPrzyrostowa { _ in
                wywolania += 1
                if wywolania == 1 { throw BladTestowy.start }
                aktywne += 1; maksimum = max(maksimum, aktywne)
                let nr = wywolania
                if nr == 2 { await withCheckedContinuation { wznow = $0 } }
                aktywne -= 1
                return nr == 2 ? "stary fallback" : "nowy"
            }
            let pcm = [Float](repeating: 0.1, count: 70_000) + [Float](repeating: 0, count: 12_000) + [Float](repeating: 0.1, count: 640)
            silnik.rozpocznij(); silnik.przyjmij(pcm)
            let stary = Task { try await silnik.zakoncz(caleNagranie: pcm) }
            for _ in 0..<50 { await Task.yield() }
            try expectEqual(wywolania, 2)
            silnik.anuluj(); silnik.rozpocznij(); silnik.przyjmij([0.2])
            let nowy = Task { try await silnik.zakoncz(caleNagranie: [0.2]) }
            for _ in 0..<30 { await Task.yield() }
            wznow?.resume()
            _ = await stary.result
            try expectEqual(try await nowy.value, "nowy")
            try expectEqual(maksimum, 1)
        }), ("koordynator: próbki trafiają do STT podczas nagrywania", {
            let audio = AudioZeStrumieniem()
            let stt = STTZeStrumieniem()
            let k = KoordynatorDyktowania(audio: audio, transcribing: stt, inserting: AtrapaTextInserting(), permissions: AtrapaPermissionChecking(mikrofon:true))
            await k.handleWyzwalacz()
            audio.poProbkach?([0.1, 0.2])
            try expectEqual(stt.rozpoczecia, 1)
            try expectEqual(stt.probki, [0.1, 0.2])
            await k.anuluj()
            try expectEqual(stt.anulowania, 1)
        })]
    }
}
@MainActor final class AudioZeStrumieniem: AudioCapturing {
    var poProbkach: (([Float]) -> Void)?
    func start() async throws {}
    func stop() async -> Nagranie { Nagranie(pcm: [], czasTrwania: 0, szczytowaGlosnosc: 0) }
}
@MainActor final class STTZeStrumieniem: Transcribing {
    var probki: [Float] = []
    var rozpoczecia = 0
    var anulowania = 0
    func rozpocznijSesje() { rozpoczecia += 1 }
    func przyjmijProbki(_ pcm: [Float]) { probki.append(contentsOf: pcm) }
    func anulujSesje() { anulowania += 1 }
    func modelGotowy() async -> Bool { true }
    func transcribe(nagranie: Nagranie, jezyk: String) async throws -> Transkrypt { Transkrypt(tekst:"test") }
}

@MainActor final class ModelPoZgodzie: Transcribing {
    var zgoda = false
    var zgodaPodczasPrzygotowania = false
    func modelGotowy() async -> Bool { zgodaPodczasPrzygotowania = zgoda; return true }
    func transcribe(nagranie: Nagranie, jezyk: String) async throws -> Transkrypt { Transkrypt(tekst: "") }
}
@MainActor final class ZgodaPrzedModelem: PermissionChecking {
    let stt: ModelPoZgodzie
    init(stt: ModelPoZgodzie) { self.stt = stt }
    var mikrofon: Bool { false }
    func poprosOMikrofon() async -> Bool { stt.zgoda = true; return true }
}

@MainActor final class ZmiennyWynik: Transcribing {
    var tekst = "Zachowaj ten tekst."
    func modelGotowy() async -> Bool { true }
    func transcribe(nagranie: Nagranie, jezyk: String) async throws -> Transkrypt { Transkrypt(tekst: tekst) }
}
