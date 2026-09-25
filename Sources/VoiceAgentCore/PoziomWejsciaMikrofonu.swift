/// Czysta decyzja o ostrzeżeniu dla odczytanego poziomu wejścia.
public enum PoziomWejsciaMikrofonu {
    public static let progOstrzezeniaDB: Float = -12

    public static func ostrzez(db: Float?) -> Bool {
        guard let db, db.isFinite else { return false }
        return db < progOstrzezeniaDB
    }
}
