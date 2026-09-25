public enum ParametryRozpoznawania {
    /// Do czterech prób (temperatury 0; 0,2; 0,4; 0,6), tylko przy porażce kryteriów dekodera.
    /// Mniej niż domyślne pięć ponowień WhisperKit, bez dojścia do temperatury 1,0.
    public static let liczbaPonowien = 3

    public static func uzyjVAD(liczbaProbek: Int, okno: Int) -> Bool {
        okno > 0 && liczbaProbek > okno
    }
}
