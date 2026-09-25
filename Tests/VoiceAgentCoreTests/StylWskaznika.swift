import VoiceAgentCore

enum TestyStyluWskaznika {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [
            ("styl wskaznika: pusty magazyn migruje na iskry", {
                let zrodlo = PamiecMagazynKluczy()
                let magazyn = MagazynUstawien(zrodlo: zrodlo)
                try expectEqual(StylWskaznikaNagrywania.wczytaj(z: magazyn), .iskry)
                try expectEqual(magazyn.string(klucz: StylWskaznikaNagrywania.klucz, domyslna: "brak"), "iskry")
            }),
            ("styl wskaznika: wybor kazdego stylu przetrwa nowy magazyn", {
                let zrodlo = PamiecMagazynKluczy()
                let pierwszy = MagazynUstawien(zrodlo: zrodlo)
                for styl in [StylWskaznikaNagrywania.slupki, .iskry, .nicSwiatla] {
                    styl.zapisz(w: pierwszy)
                    let drugi = MagazynUstawien(zrodlo: zrodlo)
                    try expectEqual(StylWskaznikaNagrywania.wczytaj(z: drugi), styl)
                }
            }),
            ("styl wskaznika: nieznana wartosc wraca do iskier", {
                let magazyn = MagazynUstawien(zrodlo: PamiecMagazynKluczy())
                magazyn.ustaw("nieznany", klucz: StylWskaznikaNagrywania.klucz)
                try expectEqual(StylWskaznikaNagrywania.wczytaj(z: magazyn), .iskry)
                try expectEqual(magazyn.string(klucz: StylWskaznikaNagrywania.klucz, domyslna: "brak"), "iskry")
            }),
        ]
    }
}
