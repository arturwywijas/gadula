public enum OcenaKonfiguracjiAudio {
    public enum Wybor: Equatable { case bezZmiany, ustawWybrane, powrotDoSystemowego }

    public static func wybor(zapisanyUID: Bool, wybrane: UInt32?, domyslne: UInt32?) -> Wybor {
        guard zapisanyUID else { return .bezZmiany }
        guard let wybrane else { return .powrotDoSystemowego }
        return wybrane == domyslne ? .bezZmiany : .ustawWybrane
    }

    public static func zgodnyFormat(tapHz: Double, tapKanaly: UInt32,
                                     sprzetHz: Double, sprzetKanaly: UInt32) -> Bool {
        tapHz.isFinite && tapHz > 0 && tapKanaly > 0
            && tapHz == sprzetHz && tapKanaly == sprzetKanaly
    }
}
