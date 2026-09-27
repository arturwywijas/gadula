// autor: Codex, gadula-stabilnosc-20260927
import AppKit
import ApplicationServices
import VoiceAgentCore

final class SchowekTextInserting: TextInserting {
    private let board: NSPasteboard
    private let maDostep: @MainActor () -> Bool
    private let wklej: @MainActor () -> Bool

    init(schowek: NSPasteboard = .general,
         maDostep: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
         wklej: @escaping @MainActor () -> Bool = { SchowekTextInserting.postCommandV() }) {
        self.board = schowek
        self.maDostep = maDostep
        self.wklej = wklej
    }

    func insert(tekst: String) async -> WynikWstawienia {
        board.clearContents()
        guard board.setString(tekst, forType: .string) else { return .nieudane }
        guard maDostep(), wklej() else { return .tylkoSchowek }
        // Cmd-V nie potwierdza odczytu schowka. Transkrypt zostaje do ręcznego
        // wklejenia, a kolejne kopiowanie użytkownika nie jest nigdy cofane.
        return .wyslanoWklejenie
    }

    static func postCommandV() -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
