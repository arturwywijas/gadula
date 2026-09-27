// autor: Codex, gadula-dzwiek-aktualizacje-20260927
import Foundation

@MainActor
public protocol SterowanieGlosnoscia: AnyObject {
    var domyslneWyjscie: String? { get }
    func odczytaj(_ id: String) -> [Float]?
    func dopasuj(_ id: String, poziomy: [Float]) -> [Float]?
    @discardableResult func ustaw(_ id: String, poziomy: [Float]) -> Bool
}

/// Dziennik pozwala odtworzyć głośność po ponownym uruchomieniu aplikacji.
public struct SladGlosnosci: Codable, Sendable {
    public let id: String
    public let pierwotne: [Float]
    public var ostatnie: [Float]
    public var planowane: [Float]?
    public var poprzednioPlanowane: [Float]?
    public var przywroceniePrzyjete: Bool?
    public var zapisPrzyjety: Bool?
}

/// Zegar jest podawany z zewnątrz, więc ten sam kod obsługuje timer i testy.
@MainActor
public final class SciszanieDzwieku {
    private let wyjscie: any SterowanieGlosnoscia
    private let zapisz: ([SladGlosnosci]) -> Bool
    private var slady: [String: SladGlosnosci]
    private var aktywne: String?
    private var pominiete = Set<String>()
    private var nagrywa = false
    private var od: [Float] = []
    private var poczatek = 0.0
    private var koniec = 0.0
    public var wymagaKrokow: Bool { nagrywa || aktywne != nil || !slady.isEmpty }

    public init(wyjscie: any SterowanieGlosnoscia, zapisane: [SladGlosnosci] = [], zapisz: @escaping ([SladGlosnosci]) -> Bool = { _ in true }) {
        self.wyjscie = wyjscie
        self.zapisz = zapisz
        slady = Dictionary(zapisane.map { ($0.id, $0) }, uniquingKeysWith: { _, nowe in nowe })
    }

    public func rozpocznij(czas: Double) {
        guard !nagrywa else { return }
        // Szybki kolejny start nie może uznać częściowo przywróconej głośności za oryginał.
        nagrywa = true
        pominiete.removeAll()
        wybierz(czas: czas)
    }

    public func zakoncz(czas: Double) {
        guard nagrywa else { return }
        nagrywa = false
        if let aktywne, let teraz = wyjscie.odczytaj(aktywne) {
            od = teraz; poczatek = czas; koniec = czas + 0.65
        }
    }

    /// Zamykanie aplikacji lub sen nie może zostawić muzyki ściszonej.
    public func przywrocNatychmiast() {
        nagrywa = false; aktywne = nil
        for id in Array(slady.keys) { przywroc(id) }
    }

    public func krok(czas: Double) {
        if nagrywa, aktywne != wyjscie.domyslneWyjscie { wybierz(czas: czas) }
        for id in Array(slady.keys) where id != aktywne { przywroc(id) }
        guard let id = aktywne, let slad = slady[id] else { return }
        guard let teraz = wyjscie.odczytaj(id) else {
            // Odłączone wyjście zachowuje dziennik do czasu ponownego pojawienia się.
            aktywne = nil
            return
        }
        guard pasuje(teraz, slad) else {
            // Zmiana użytkownika wygrywa, również podczas płynnego powrotu.
            slady[id] = nil; aktywne = nil; pominiete.insert(id); utrwal()
            return
        }
        // Nawet niepotwierdzony lub odrzucony zapis nie może blokować końca.
        if !nagrywa, czas >= koniec {
            przywroc(id)
            aktywne = nil
            return
        }
        // HAL potwierdza zmianę później. Nie kolejkować następnego zapisu,
        // dopóki poprzedni nie jest widoczny w odczycie.
        if let planowane = slad.planowane {
            guard blisko(teraz, planowane), slad.zapisPrzyjety == true || !blisko(teraz, slad.ostatnie) else { return }
            var potwierdzony = slad
            potwierdzony.ostatnie = teraz; potwierdzony.planowane = nil; potwierdzony.poprzednioPlanowane = nil
            slady[id] = potwierdzony; utrwal()
        }
        let t = min(1, max(0, (czas - poczatek) / max(0.001, koniec - poczatek)))
        let postep = Float(t * t * (3 - 2 * t))
        let cel = nagrywa ? slad.pierwotne.map { $0 * 0.35 } : slad.pierwotne
        let nowe = t >= 1 ? cel : zip(od, cel).map { $0 + ($1 - $0) * postep }
        if let kanoniczne = wyjscie.dopasuj(id, poziomy: nowe), !blisko(teraz, kanoniczne, tolerancja: 0.00001) { zapiszPoziom(id, kanoniczne) }
        if !nagrywa, t >= 1 {
            // Usuwamy ślad tylko po potwierdzonym odtworzeniu.
            if let odczyt = wyjscie.odczytaj(id), blisko(odczyt, cel) { slady[id] = nil; utrwal() }
            aktywne = nil
        }
    }

    private func wybierz(czas: Double) {
        let id = wyjscie.domyslneWyjscie
        if let stare = aktywne, stare != id { przywroc(stare) }
        aktywne = nil
        guard let id, !pominiete.contains(id), let teraz = wyjscie.odczytaj(id),
              !teraz.isEmpty, teraz.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return }
        if let slad = slady[id], !pasuje(teraz, slad) {
            slady[id] = nil; pominiete.insert(id); utrwal(); return
        }
        if slady[id] == nil {
            slady[id] = SladGlosnosci(id: id, pierwotne: teraz, ostatnie: teraz)
            guard utrwal() else { slady[id] = nil; pominiete.insert(id); return }
        }
        aktywne = id; od = teraz; poczatek = czas; koniec = czas + 0.4
    }

    private func przywroc(_ id: String) {
        guard let slad = slady[id], let teraz = wyjscie.odczytaj(id) else { return }
        guard pasuje(teraz, slad) else { slady[id] = nil; utrwal(); return }
        // Odczyt oryginału sprzed wykonania asynchronicznego duck nie jest
        // potwierdzeniem restore. Potrzeba przyjętego zapisu i kolejnego odczytu.
        if blisko(teraz, slad.pierwotne), slad.planowane == nil ||
            (slad.przywroceniePrzyjete == true && slad.planowane.map { blisko($0, slad.pierwotne) } == true) {
            slady[id] = nil; utrwal(); return
        }
        zapiszPoziom(id, slad.pierwotne)
    }

    private func zapiszPoziom(_ id: String, _ zadane: [Float]) {
        guard let poprzedni = slady[id] else { return }
        let powrot = zadane == poprzedni.pierwotne
        guard let nowe = powrot ? zadane : wyjscie.dopasuj(id, poziomy: zadane), nowe.count == zadane.count else { return }
        var slad = poprzedni
        if slad.planowane != nowe { slad.poprzednioPlanowane = slad.planowane }
        slad.planowane = nowe; slad.przywroceniePrzyjete = false; slad.zapisPrzyjety = false; slady[id] = slad
        guard utrwal() || blisko(nowe, slad.pierwotne, tolerancja: 0.00001) else {
            slady[id] = poprzedni
            return
        }
        let przyjete = wyjscie.ustaw(id, poziomy: nowe)
        slad.zapisPrzyjety = przyjete
        slad.przywroceniePrzyjete = przyjete && blisko(nowe, slad.pierwotne)
        slady[id] = slad; utrwal()
    }
    private func pasuje(_ teraz: [Float], _ slad: SladGlosnosci) -> Bool {
        guard teraz.count == slad.ostatnie.count else { return false }
        return teraz.indices.allSatisfy { i in
            let plan = slad.planowane.flatMap { $0.count == teraz.count ? $0[i] : nil }
            let wczesniej = slad.poprzednioPlanowane.flatMap { $0.count == teraz.count ? $0[i] : nil }
            return teraz[i].isFinite && (abs(teraz[i] - slad.ostatnie[i]) <= 0.0001 || plan.map { abs(teraz[i] - $0) <= 0.0001 } == true || wczesniej.map { abs(teraz[i] - $0) <= 0.0001 } == true)
        }
    }
    private func blisko(_ a: [Float], _ b: [Float], tolerancja: Float = 0.0001) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.isFinite && $1.isFinite && abs($0 - $1) <= tolerancja }
    }
    @discardableResult private func utrwal() -> Bool { zapisz(Array(slady.values)) }
}
