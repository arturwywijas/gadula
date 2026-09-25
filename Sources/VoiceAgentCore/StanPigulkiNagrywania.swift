/// Stan prezentacji poziomu: bez zegara systemowego, audio i zaleznosci UI.
public struct StanPigulkiNagrywania {
    public private(set) var nagrywa = false
    public private(set) var poziom: Float = 0
    private var ostatniaAktualizacja: Double?
    private var rewizja: UInt64 = 0
    private var ostatniaProbka: (szczyt: Float, czas: Double)?
    private var poczatek: Double = 0

    public init() {}

    public mutating func rozpocznij(czas: Double) {
        poczatek = czas
        rewizja &+= 1
        nagrywa = true
        poziom = 0
        ostatniaAktualizacja = nil
        ostatniaProbka = nil
    }

    @discardableResult
    public mutating func zakoncz() -> UInt64 {
        rewizja &+= 1
        nagrywa = false
        poziom = 0
        ostatniaAktualizacja = nil
        ostatniaProbka = nil
        return rewizja
    }

    public func moznaUkryc(rewizja poprzednia: UInt64) -> Bool {
        !nagrywa && rewizja == poprzednia
    }

    public mutating func przyjmij(szczyt: Float, czas: Double) {
        guard nagrywa, czas.isFinite, czas >= poczatek else { return }
        if let ostatniaProbka, czas < ostatniaProbka.czas { return }
        ostatniaProbka = (szczyt.isFinite ? min(max(szczyt, 0), 1) : 0, czas)
    }

    /// Jeden najnowszy skalar, nigdy kolejka klatek. Stara probka zanika.
    public mutating func odswiez(czas: Double) -> Bool {
        guard nagrywa, czas.isFinite else { return false }
        if let ostatniaAktualizacja, czas - ostatniaAktualizacja < 0.05 { return false }
        ostatniaAktualizacja = czas
        let szczyt: Float
        if let ostatniaProbka, czas >= ostatniaProbka.czas, czas - ostatniaProbka.czas <= 0.2 {
            szczyt = ostatniaProbka.szczyt
        } else {
            szczyt = 0
        }
        let cel = min(max(szczyt * 4, 0), 1).squareRoot()
        let wspolczynnik: Float = cel > poziom ? 0.55 : 0.25
        poziom += (cel - poziom) * wspolczynnik
        if poziom < 0.001 { poziom = 0 }
        return true
    }
}
