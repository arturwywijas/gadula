public enum StylWskaznikaNagrywania: String, CaseIterable, Sendable {
    case slupki
    case iskry
    case nicSwiatla

    public static let klucz = "wskaznik.styl"

    public static func wczytaj(z magazyn: MagazynUstawien) -> Self {
        let zapis = magazyn.string(klucz: klucz, domyslna: "")
        if let styl = Self(rawValue: zapis) { return styl }
        // Brak ustawienia w starszej wersji oraz nieznana wartosc maja ten sam domyslny styl.
        Self.iskry.zapisz(w: magazyn)
        return .iskry
    }

    public func zapisz(w magazyn: MagazynUstawien) {
        magazyn.ustaw(rawValue, klucz: Self.klucz)
    }
}
