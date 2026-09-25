import Foundation

public func przygotujTekstDoWstawienia(_ tekst: String) -> String {
    tekst.trimmingCharacters(in: .whitespacesAndNewlines)
}
