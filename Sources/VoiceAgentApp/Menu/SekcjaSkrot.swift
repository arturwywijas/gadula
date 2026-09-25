import AppKit
import Carbon.HIToolbox
import VoiceAgentCore

// Znane ograniczenie ze snapshotu vlr-code/dictly, poza v1: klawisze F i dedykowany klawisz dyktowania
// nie bindują się czysto. Nie naprawiamy tego tutaj.

@MainActor
enum SekcjaSkrot: BudowniczySekcjiMenu {
    private static var monitorGlobal: Any?
    private static var monitorLocal: Any?
    private static var przechwytAktywny = false
    private static var przechwytModyfikatora = PrzechwytModyfikatora<KeyCombo.SoloModifier>()
    private static var komunikatPrzechwytu: String?
    private static let log = AppLogger(category: "Skrot")
    private static var limitPrzechwytu: DispatchWorkItem?
    private static var odswiezPoPrzechwycie: (() -> Void)?
    private static var ostatniaOdmowa: WerdyktSkrotu?

    // Po kliknięciu pozycji menu zdarzenie zamykające menu nie może wejść do przechwytywania.
    private static let opoznienieStartuPrzechwytu: TimeInterval = 0.3
    // Bez limitu monitor zostaje na zawsze i połyka klawisze.
    private static let limitCzasuPrzechwytu: TimeInterval = 5

    static func zbuduj(kontekst: KontekstMenu) -> [NSMenuItem] {
        let biezacy = KeyCombo.wczytaj(z: kontekst.magazyn)
        let item = NSMenuItem(title: "Skrót: \(biezacy.displayName)", action: nil, keyEquivalent: "")
        let podmenu = NSMenu()

        let stan = NSMenuItem(title: kontekst.bladSkrotu ?? komunikatPrzechwytu ?? "Bieżący: \(biezacy.displayName)", action: nil, keyEquivalent: "")
        stan.isEnabled = false
        podmenu.addItem(stan)

        let gotowe: [(String, KeyCombo)] = [
            ("Option+Space", .optionSpace),
            ("Control+Option+Space", .controlOptionSpace),
            ("Control+Option+Command+Space", .controlOptionCommandSpace),
            ("Fn (tylko klawiatura Apple)", .fnHotkey),
        ]
        for (tytul, skrot) in gotowe {
            let pozycja = NSMenuItem(title: tytul, action: nil, keyEquivalent: "")
            pozycja.state = biezacy.tenSamKlawisz(co: skrot) ? .on : .off
            kontekst.podepnij(pozycja) { ustaw(skrot, kontekst: kontekst) }
            podmenu.addItem(pozycja)
        }
        if !gotowe.contains(where: { biezacy.tenSamKlawisz(co: $0.1) }) {
            let wlasny = NSMenuItem(title: "Własny: \(biezacy.displayName)", action: nil, keyEquivalent: "")
            wlasny.state = .on
            podmenu.addItem(wlasny)
        }

        if przechwytAktywny {
            let nasluch = NSMenuItem(
                title: "Nasłuchuję kombinacji (Esc anuluje)",
                action: nil,
                keyEquivalent: ""
            )
            nasluch.isEnabled = false
            podmenu.addItem(nasluch)

            let anuluj = NSMenuItem(title: "Anuluj przechwytywanie", action: nil, keyEquivalent: "")
            kontekst.podepnij(anuluj) {
                zakonczPrzechwyt()
                kontekst.odswiez()
            }
            podmenu.addItem(anuluj)
        } else {
            let chwyt = NSMenuItem(title: "Przechwyć własną kombinację", action: nil, keyEquivalent: "")
            kontekst.podepnij(chwyt) {
                rozpocznijPrzechwyt(kontekst: kontekst)
            }
            podmenu.addItem(chwyt)
        }

        if biezacy.solo == .fn, !przechwytAktywny {
            let info = NSMenuItem(
                title: "Fn wymaga klawiatury Apple i Dostępności. Logitech nie przekazuje zgodnego Fn do macOS.",
                action: nil,
                keyEquivalent: ""
            )
            info.isEnabled = false
            podmenu.addItem(info)
        }

        if let odmowa = ostatniaOdmowa, !przechwytAktywny {
            dodajOdmowe(odmowa, do: podmenu, kontekst: kontekst)
        }

        item.submenu = podmenu
        let tryb = NSMenuItem(title: "Tryb: \(biezacy.tryb.etykieta)", action: nil, keyEquivalent: "")
        let tryby = NSMenu()
        for wybor in TrybSkrotu.allCases {
            let pozycja = NSMenuItem(title: wybor.etykieta, action: nil, keyEquivalent: "")
            pozycja.state = biezacy.tryb == wybor ? .on : .off
            kontekst.podepnij(pozycja) {
                var ustawienie = KeyCombo.wczytaj(z: kontekst.magazyn)
                let werdykt = ustawienie.wybierzTryb(wybor)
                ostatniaOdmowa = werdykt == .przyjeta ? nil : werdykt
                komunikatPrzechwytu = nil
                if werdykt == .przyjeta { ustawienie.zapisz(w: kontekst.magazyn) }
                kontekst.odswiez()
            }
            tryby.addItem(pozycja)
        }
        if biezacy.kind == .modifierOnly {
            let info = NSMenuItem(title: "Sam modyfikator wymaga przytrzymania. Fn wymaga klawiatury Apple.", action: nil, keyEquivalent: "")
            info.isEnabled = false
            tryby.addItem(info)
        }
        if let odmowa = ostatniaOdmowa { dodajOdmowe(odmowa, do: tryby, kontekst: kontekst) }
        tryb.submenu = tryby
        return [item, tryb]
    }

    private static func dodajOdmowe(
        _ werdykt: WerdyktSkrotu,
        do podmenu: NSMenu,
        kontekst: KontekstMenu
    ) {
        let powod: String
        switch werdykt {
        case .modyfikatorWymagaPrzytrzymania:
            powod = "Sam modyfikator wymaga przytrzymania. Najpierw zmień tryb lub wybierz kombinację."
        case .przyjeta:
            return
        case .odrzucPraweOption:
            powod = OcenaSkrotu.wyjasnieniePraweOption
        case .brakUprawnieniaModyfikatora:
            powod = "Odmowa: wariant z samym modyfikatorem wymaga Dostępności."
        }
        let powodItem = NSMenuItem(title: powod, action: nil, keyEquivalent: "")
        powodItem.isEnabled = false
        podmenu.addItem(powodItem)

        if werdykt == .brakUprawnieniaModyfikatora {
            let panel = NSMenuItem(title: "Otwórz Dostępność w Ustawieniach", action: nil, keyEquivalent: "")
            kontekst.podepnij(panel) {
                PermissionsChecker.openAccessibilitySettings()
            }
            podmenu.addItem(panel)
        }
    }

    private static func ustaw(_ combo: KeyCombo, kontekst: KontekstMenu) {
        zakonczPrzechwyt()
        komunikatPrzechwytu = nil
        var ustawienie = KeyCombo.wczytaj(z: kontekst.magazyn)
        let werdykt = ustawienie.wybierzKlawisz(combo, accessibility: PermissionsChecker.isAccessibilityGranted)
        log.notice("FN09 capture validation kind=\(combo.kind.rawValue) keyCode=\(String(describing: combo.keyCode)) modifiers=\(combo.modifierFlags) verdict=\(String(describing: werdykt))")
        switch werdykt {
        case .przyjeta:
            ostatniaOdmowa = nil
            ustawienie.zapisz(w: kontekst.magazyn)
        case .odrzucPraweOption, .brakUprawnieniaModyfikatora, .modyfikatorWymagaPrzytrzymania:
            ostatniaOdmowa = werdykt
        }
        kontekst.odswiez()
    }

    private static func rozpocznijPrzechwyt(kontekst: KontekstMenu) {
        zakonczPrzechwyt()
        przechwytAktywny = true
        komunikatPrzechwytu = nil
        log.notice("FN09 capture start timeoutSeconds=5")
        ostatniaOdmowa = nil
        odswiezPoPrzechwycie = kontekst.odswiez
        kontekst.odswiez()
        DispatchQueue.main.asyncAfter(deadline: .now() + opoznienieStartuPrzechwytu) { [kontekst] in
            guard przechwytAktywny else { return }
            let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
            monitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
                AppLogger(category: "Skrot").notice("FN09 capture event monitor=global type=\(event.type.rawValue) modifiers=\(event.modifierFlags.rawValue)")
                let type = event.type
                let keyCode = event.keyCode
                let flags = event.modifierFlags
                DispatchQueue.main.async {
                    obsluzPrzechwyt(type: type, keyCode: keyCode, flags: flags, kontekst: kontekst)
                }
            }
            monitorLocal = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
                guard przechwytAktywny else { return event }
                log.notice("FN09 capture event monitor=local type=\(event.type.rawValue) modifiers=\(event.modifierFlags.rawValue)")
                obsluzPrzechwyt(
                    type: event.type,
                    keyCode: event.keyCode,
                    flags: event.modifierFlags,
                    kontekst: kontekst
                )
                return nil
            }
            log.notice("FN09 capture monitors global=\(monitorGlobal != nil) local=\(monitorLocal != nil)")
            let limit = DispatchWorkItem {
                guard przechwytAktywny else { return }
                log.notice("FN09 capture timeout")
                komunikatPrzechwytu = "Upłynął czas przechwytywania. Skrót nie został zmieniony."
                let odswiez = odswiezPoPrzechwycie
                zakonczPrzechwyt()
                odswiez?()
            }
            limitPrzechwytu = limit
            DispatchQueue.main.asyncAfter(deadline: .now() + limitCzasuPrzechwytu, execute: limit)
        }
    }

    private static func obsluzPrzechwyt(
        type: NSEvent.EventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        kontekst: KontekstMenu
    ) {
        guard przechwytAktywny else { return }
        if type == .keyDown {
            if Int(keyCode) == kVK_Escape {
                zakonczPrzechwyt()
                kontekst.odswiez()
                return
            }
            zakonczPrzechwyt()
            ustaw(.combo(keyCode: keyCode, modifiers: flags), kontekst: kontekst)
            return
        }
        guard type == .flagsChanged else { return }

        if KeyCombo.SoloModifier.fn.isPressed(flags: flags) {
            zakonczPrzechwyt()
            ustaw(.fnHotkey, kontekst: kontekst)
            return
        }

        let solo = KeyCombo.SoloModifier.allCases.first { $0 != .fn && $0.isPressed(flags: flags) }
        guard let wybrany = przechwytModyfikatora.zmiana(solo) else { return }
        ustaw(
            KeyCombo(kind: .modifierOnly, solo: wybrany, keyCode: nil, modifierFlags: 0),
            kontekst: kontekst
        )
    }

    private static func zakonczPrzechwyt() {
        przechwytModyfikatora.anuluj()
        limitPrzechwytu?.cancel()
        limitPrzechwytu = nil
        if let monitorGlobal {
            NSEvent.removeMonitor(monitorGlobal)
            self.monitorGlobal = nil
        }
        if let monitorLocal {
            NSEvent.removeMonitor(monitorLocal)
            self.monitorLocal = nil
        }
        przechwytAktywny = false
        odswiezPoPrzechwycie = nil
    }
}
