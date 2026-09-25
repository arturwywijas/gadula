import VoiceAgentCore

final class PamiecMagazynKluczy: MagazynKluczy {
    private var wartosci: [String: Any] = [:]

    func object(forKey key: String) -> Any? {
        wartosci[key]
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            wartosci[key] = value
        } else {
            wartosci.removeValue(forKey: key)
        }
    }
}
