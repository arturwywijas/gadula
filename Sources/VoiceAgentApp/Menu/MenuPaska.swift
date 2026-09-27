import AppKit

enum MenuPaska {
    @MainActor
    static func zbuduj(kontekst: KontekstMenu) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let sekcje: [[NSMenuItem]] = [
            SekcjaStan.zbuduj(kontekst: kontekst),
            SekcjaDyktujTeraz.zbuduj(kontekst: kontekst),
            [NSMenuItem.separator()],
            SekcjaSkrot.zbuduj(kontekst: kontekst),
            SekcjaTekst.zbuduj(kontekst: kontekst),
            SekcjaModel.zbuduj(kontekst: kontekst),
            SekcjaDzwiek.zbuduj(kontekst: kontekst),
            SekcjaMikrofon.zbuduj(kontekst: kontekst),
            SekcjaWskaznik.zbuduj(kontekst: kontekst),
            SekcjaAutostart.zbuduj(kontekst: kontekst),
            SekcjaUprawnienia.zbuduj(kontekst: kontekst),
            [NSMenuItem.separator()],
            SekcjaAktualizacje.zbuduj(kontekst: kontekst),
            SekcjaOAplikacji.zbuduj(kontekst: kontekst),
            SekcjaZakoncz.zbuduj(kontekst: kontekst),
        ]
        for pozycje in sekcje {
            for pozycja in pozycje {
                menu.addItem(pozycja)
            }
        }
        return menu
    }
}
