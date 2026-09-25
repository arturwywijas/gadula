import AppKit
import ServiceManagement

enum SekcjaAutostart: BudowniczySekcjiMenu {
    private static let cel = CelAutostartu()

    static func zbuduj(kontekst _: KontekstMenu) -> [NSMenuItem] {
        let item = NSMenuItem(
            title: "Uruchamiaj przy logowaniu",
            action: #selector(CelAutostartu.przelacz(_:)),
            keyEquivalent: ""
        )
        item.target = cel
        item.state = CelAutostartu.jestZarejestrowany ? .on : .off
        return [item]
    }
}

@MainActor
private final class CelAutostartu: NSObject, NSMenuItemValidation {
    @objc nonisolated func przelacz(_ sender: NSMenuItem) {
        nonisolated(unsafe) let item = sender
        Task { @MainActor in self.wykonajPrzelaczenie(item) }
    }

    @MainActor
    private func wykonajPrzelaczenie(_ sender: NSMenuItem) {
        let usluga = SMAppService.mainApp
        do {
            if Self.jestZarejestrowany {
                try usluga.unregister()
            } else {
                try usluga.register()
            }
        } catch {
            AppLogger(category: "Autostart").error(
                "Rejestracja autostartu nie powiodła się: \(error.localizedDescription)"
            )
        }
        sender.state = Self.jestZarejestrowany ? .on : .off
    }

    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Wejście AppKit nie sprawdza wykonawcy Swift. Odczyt i UI dopiero w zadaniu.
        nonisolated(unsafe) let item = menuItem
        Task { @MainActor in
            item.state = Self.jestZarejestrowany ? .on : .off
        }
        return true
    }

    static var jestZarejestrowany: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            true
        default:
            false
        }
    }
}
