import Foundation

public protocol MagazynKluczy: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

public final class MagazynUstawien: @unchecked Sendable {
    private let zrodlo: MagazynKluczy

    public init(zrodlo: MagazynKluczy) {
        self.zrodlo = zrodlo
    }

    public func string(klucz: String, domyslna: String) -> String {
        (zrodlo.object(forKey: klucz) as? String) ?? domyslna
    }

    public func ustaw(_ wartosc: String, klucz: String) {
        zrodlo.set(wartosc, forKey: klucz)
    }

    public func ustaw(_ wartosc: Bool, klucz: String) {
        zrodlo.set(wartosc, forKey: klucz)
    }
}

extension UserDefaults: MagazynKluczy {}
