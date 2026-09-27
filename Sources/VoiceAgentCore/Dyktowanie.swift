public struct Nagranie: Equatable, Sendable {
    public let pcm: [Float]
    public let czasTrwania: Double
    public let szczytowaGlosnosc: Float

    public init(pcm: [Float], czasTrwania: Double, szczytowaGlosnosc: Float) {
        self.pcm = pcm
        self.czasTrwania = czasTrwania
        self.szczytowaGlosnosc = szczytowaGlosnosc
    }
}

public struct Transkrypt: Equatable, Sendable {
    public let tekst: String
    public let surowyTekst: String

    public init(tekst: String, surowyTekst: String? = nil) {
        self.tekst = tekst
        self.surowyTekst = surowyTekst ?? tekst
    }
}

public enum WynikWstawienia: Equatable, Sendable {
    case wstawione
    case wyslanoWklejenie
    case tylkoSchowek
    case nieudane
}

public enum StanSesji: Equatable, Sendable {
    case bezczynny
    case nagrywanie
    case transkrypcja
    case wstawianie
}

public enum SygnalZajetosciPTT {
    public static func wymagany(gdy stan: StanSesji) -> Bool {
        stan != .bezczynny
    }
}

public enum StanIkony: Equatable, Sendable {
    case bezczynny
    case nagrywa
    case przetwarza
    case blad
}

@MainActor
public protocol AudioCapturing: AnyObject {
    var poProbkach: (([Float]) -> Void)? { get set }
    func start() async throws
    func stop() async -> Nagranie
}

extension AudioCapturing {
    public var poProbkach: (([Float]) -> Void)? { get { nil } set {} }
}

public enum BladTranskrypcji: Error, Equatable {
    case modelNiegotowy
    case nieudana
    case zaDlugaWypowiedz
}

@MainActor
public protocol Transcribing: AnyObject {
    func rozpocznijSesje()
    func przyjmijProbki(_ pcm: [Float])
    func anulujSesje()
    func transcribe(nagranie: Nagranie, jezyk: String) async throws -> Transkrypt
    func modelGotowy() async -> Bool
}

extension Transcribing {
    public func rozpocznijSesje() {}
    public func przyjmijProbki(_ pcm: [Float]) {}
    public func anulujSesje() {}
}

@MainActor
public protocol TextInserting: AnyObject {
    func insert(tekst: String) async -> WynikWstawienia
}

@MainActor
public protocol PermissionChecking: AnyObject {
    var mikrofon: Bool { get }
    func poprosOMikrofon() async -> Bool
    func otworzPanelMikrofonu()
}

extension PermissionChecking {
    public func poprosOMikrofon() async -> Bool { mikrofon }
    public func otworzPanelMikrofonu() {}
}

@MainActor
public final class KoordynatorDyktowania {
    public var poZmianieGotowosci: ((GotowoscDyktowania) -> Void)?
    public private(set) var gotowosc: GotowoscDyktowania = .ukryta {
        didSet { if oldValue != gotowosc { poZmianieGotowosci?(gotowosc) } }
    }
    public func mikrofonOdbieraDzwiek() {
        guard stan == .nagrywanie, !zatrzymuje else { return }
        gotowosc = .gotowa
    }
    public private(set) var ostatniSurowyTranskrypt: String?
    private var sesja: UInt64 = 0
    private var rozpoczyna = false
    private var zatrzymuje = false
    private var konczy = false
    /// Powiadomienie obejmuje również limit audio i odłączenie mikrofonu.
    /// Odbiorca UI powinien zaplanować odświeżenie na swoim aktorze.
    public var poZakonczeniuSesji: (() -> Void)?
    public private(set) var stan: StanSesji = .bezczynny {
        didSet {
            if oldValue != .bezczynny && stan == .bezczynny {
                gotowosc = pokazujeBlad ? .blad : .ukryta
                poZakonczeniuSesji?()
            }
        }
    }
    public private(set) var poziomWejsciaMikrofonuDb: Float?
    public private(set) var ostatniWynikWstawienia: WynikWstawienia?

    /// Przechowuje ostatni odczyt sprzętowy; brak wartości usuwa poprzednie ostrzeżenie.
    public func odnotujPoziomWejscia(db: Float?) {
        poziomWejsciaMikrofonuDb = db.flatMap { $0.isFinite ? $0 : nil }
    }
    public private(set) var ostatniKomunikat: String?
    public private(set) var pokazujeBlad = false

    public var stanIkony: StanIkony {
        if pokazujeBlad { return .blad }
        switch stan {
        case .bezczynny:
            return .bezczynny
        case .nagrywanie:
            return .nagrywa
        case .transkrypcja, .wstawianie:
            return .przetwarza
        }
    }

    private let audio: AudioCapturing
    private let transcribing: Transcribing
    private let inserting: TextInserting
    private let permissions: PermissionChecking

    public init(
        audio: AudioCapturing,
        transcribing: Transcribing,
        inserting: TextInserting,
        permissions: PermissionChecking
    ) {
        self.audio = audio
        self.transcribing = transcribing
        self.inserting = inserting
        self.permissions = permissions
        audio.poProbkach = { [weak self] pcm in
            guard let self, self.stan == .nagrywanie else { return }
            self.transcribing.przyjmijProbki(pcm)
        }
    }

    public func handleWyzwalacz() async {
        guard !konczy else { return }
        switch stan {
        case .bezczynny:
            guard !rozpoczyna else { return }
            sesja &+= 1
            let id = sesja
            rozpoczyna = true
            defer { if sesja == id { rozpoczyna = false } }
            pokazujeBlad = false
            gotowosc = .model
            if !permissions.mikrofon {
                let granted = await permissions.poprosOMikrofon()
                guard sesja == id else { return }
                if !granted {
                    permissions.otworzPanelMikrofonu()
                    oznaczBlad("Brak zgody na mikrofon. Otwórz Ustawienia systemowe, Prywatność i bezpieczeństwo, Mikrofon.")
                    return
                }
            }
            let gotowy = await transcribing.modelGotowy()
            guard sesja == id else { return }
            if !gotowy {
                oznaczBlad("Model niegotowy.")
                return
            }
            gotowosc = .mikrofon
            do {
                transcribing.rozpocznijSesje()
                stan = .nagrywanie
                try await audio.start()
                guard sesja == id, stan == .nagrywanie, !zatrzymuje else { return }
            } catch {
                guard sesja == id, stan == .nagrywanie, !zatrzymuje else { return }
                oznaczBlad("Mikrofon niedostępny.")
            }
        case .nagrywanie:
            await zakonczNagrywanie()
        case .transkrypcja, .wstawianie:
            break
        }
    }

    public func zakonczNagrywanie() async {
        guard stan == .nagrywanie, !konczy, !zatrzymuje else { return }
        let id = sesja
        zatrzymuje = true
        defer { if sesja == id { zatrzymuje = false } }
        let nagranie = await audio.stop()
        guard sesja == id else { return }
        if nagranie.pcm.isEmpty {
            oznaczBlad("Mikrofon nie dostarczył dźwięku. Sprawdź urządzenie wejściowe.")
            return
        }
        if !ProgiSesji.dopuszczaNagranie(czas: nagranie.czasTrwania, szczyt: nagranie.szczytowaGlosnosc) {
            zakonczPustaSesje()
            return
        }
        gotowosc = .przetwarzanie
        stan = .transkrypcja
        do {
            let transkrypt = try await transcribing.transcribe(nagranie: nagranie, jezyk: "pl")
            guard sesja == id else { return }
            if !ProgiSesji.transkryptJestPusty(transkrypt.surowyTekst) {
                ostatniSurowyTranskrypt = transkrypt.surowyTekst
            }
            let tekst = przygotujTekstDoWstawienia(transkrypt.tekst)
            if ProgiSesji.transkryptJestPusty(tekst) {
                zakonczPustaSesje()
                return
            }
            stan = .wstawianie
            let wynik = await inserting.insert(tekst: tekst)
            guard sesja == id else { return }
            ostatniWynikWstawienia = wynik
            switch wynik {
            case .tylkoSchowek:
                ostatniKomunikat = "wciśnij Cmd-V"
                pokazujeBlad = true
                stan = .bezczynny
            case .nieudane:
                ostatniKomunikat = "Nie udało się zachować tekstu w schowku."
                pokazujeBlad = true
                stan = .bezczynny
            case .wyslanoWklejenie:
                ostatniKomunikat = "Tekst jest w schowku. Jeśli nie został wklejony, wciśnij Cmd-V."
                pokazujeBlad = false
                stan = .bezczynny
            case .wstawione:
                ostatniKomunikat = nil
                pokazujeBlad = false
                stan = .bezczynny
            }
        } catch BladTranskrypcji.zaDlugaWypowiedz {
            guard sesja == id else { return }
            oznaczBlad("Za długa wypowiedź bez pauz. Spróbuj dyktować krótszymi fragmentami.")
        } catch BladTranskrypcji.modelNiegotowy {
            guard sesja == id else { return }
            oznaczBlad("Model niegotowy.")
        } catch {
            guard sesja == id else { return }
            oznaczBlad("Nie udało się rozpoznać.")
        }
    }

    public func anuluj() async {
        guard !konczy, stan == .nagrywanie || rozpoczyna else { return }
        uniewaznijSesje()
        let id = sesja
        konczy = true
        defer { if sesja == id { konczy = false } }
        _ = await audio.stop()
        guard sesja == id else { return }
        ostatniWynikWstawienia = nil
        ostatniKomunikat = nil
        pokazujeBlad = false
        stan = .bezczynny
        gotowosc = .ukryta
    }

    public func wyczyscIkoneBledu() {
        pokazujeBlad = false
    }

    public func przerwij(komunikat: String) async {
        guard !konczy else { return }
        let zatrzymajAudio = stan == .nagrywanie || rozpoczyna
        uniewaznijSesje()
        let id = sesja
        konczy = true
        defer { if sesja == id { konczy = false } }
        if zatrzymajAudio {
            _ = await audio.stop()
            guard sesja == id else { return }
        }
        ostatniWynikWstawienia = nil
        ostatniKomunikat = komunikat
        pokazujeBlad = true
        gotowosc = .blad
        stan = .bezczynny
    }

    private func uniewaznijSesje() {
        transcribing.anulujSesje()
        sesja &+= 1
        rozpoczyna = false
        zatrzymuje = false
    }

    private func zakonczPustaSesje() {
        transcribing.anulujSesje()
        ostatniWynikWstawienia = nil
        ostatniKomunikat = nil
        pokazujeBlad = false
        stan = .bezczynny
    }

    private func oznaczBlad(_ komunikat: String) {
        transcribing.anulujSesje()
        ostatniWynikWstawienia = nil
        ostatniKomunikat = komunikat
        pokazujeBlad = true
        gotowosc = .blad
        stan = .bezczynny
    }
}
