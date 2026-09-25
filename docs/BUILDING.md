# Budowanie i testowanie Gaduły

## Wymagania

Potrzebny jest macOS oraz toolchain Swift zgodny ze Swift 6 i projektem używającym `swift-tools-version: 6.0`. SDK macOS musi obsługiwać cel minimalny zadeklarowany w `Package.swift`. Jeśli zależności SwiftPM nie ma w lokalnej pamięci podręcznej, SwiftPM pobierze ją z sieci.

Polecenia uruchamiaj z katalogu głównego repozytorium.

## Kompilacja

Zbuduj plik wykonywalny aplikacji:

```sh
swift build --product Gadula
```

To polecenie nie tworzy kompletnego pakietu `.app`.

## Testy

Uruchom oba cele testowe zadeklarowane w pakiecie:

```sh
swift run VoiceAgentCoreTests
swift run AudioTapGuardTests
```

`VoiceAgentCoreTests` to wykonywalny harness obejmujący 98 przypadków logiki rdzenia. `AudioTapGuardTests` sprawdza osłonę Objective-C, która zamienia wyjątek z instalacji tapu audio w kontrolowany wynik.

`Tests/AudioReconfigurationTests/main.swift` nie jest celem pakietu SwiftPM. Plik deklaruje zastępcze typy aplikacji, potrzebne do testu adaptera audio, i nie można go dołączyć jako zwykłego celu bez konfliktu ze źródłami produkcyjnymi. Nie uruchamia się go poleceniem `swift run`.

Te harnessy nie sprawdzają nagrywania przez rzeczywisty mikrofon, działania skrótów na fizycznej klawiaturze ani zachowania okien i menu na ekranie.

## Logi systemowe

Trwałe wpisy aplikacji można odczytać przez Unified Logging:

```sh
log show --last 5m --style compact --predicate 'process == "Gadula" AND subsystem == "com.arturwywijas.gadula"'
```

## Złożenie aplikacji `.app`

Skrypt `packaging/zloz-bundel.sh` buduje produkt w trybie release, składa `dist/Gaduła.app`, kopiuje do niego zasoby SwiftPM i podpisuje wynik. Domyślnym trybem jest podpis ad hoc, który nie wymaga certyfikatu i nie oznacza notaryzacji.

Skrypt nie zamyka działającej aplikacji. Jeśli Gaduła działa z docelowej ścieżki `dist/Gaduła.app`, skrypt zatrzyma się z komunikatem; zamknij tę instancję ręcznie przed kolejnym uruchomieniem.

Dostępne tryby podpisu:

```sh
TRYB_PODPISU=adhoc packaging/zloz-bundel.sh
TRYB_PODPISU=lokalny TOZSAMOSC_PODPISU='<nazwa lub odcisk SHA-1 istniejącej tożsamości>' packaging/zloz-bundel.sh
TRYB_PODPISU=developer-id TOZSAMOSC_PODPISU='<nazwa lub odcisk SHA-1 istniejącej tożsamości>' packaging/zloz-bundel.sh
```

Tryby `lokalny` i `developer-id` wymagają jawnego wskazania istniejącej tożsamości. Jej nazwy i odciski SHA-1 można odczytać poleceniem `security find-identity -v -p codesigning`. Tryb `developer-id` akceptuje tylko tożsamość certyfikatu Developer ID Application. Skrypt nie wybiera automatycznie żadnego certyfikatu. Porównanie wymagań pierwszego podpisu zapisuje poza repozytorium, osobno dla odcisku wybranej tożsamości.

Podpis ad hoc i lokalny służą do lokalnej budowy lub testów. Podpis Developer ID sam w sobie nie potwierdza ukończonej notaryzacji.

## Osobny proces wydania

Wydanie przez Developer ID wymaga własnego certyfikatu Developer ID Application. Notaryzacja Apple wymaga ponadto własnego konta Apple Developer oraz własnego profilu notarytool zapisanego w pęku kluczy. Repozytorium nie zawiera danych konta ani profilu.

Po świadomym przygotowaniu aplikacji podpisanej Developer ID można uruchomić `packaging/notaryzuj.sh`. Skrypt pakuje aplikację do `dist/Gadula.zip` i wysyła ten plik do Apple jako nośnik zgłoszenia, czeka na wynik notaryzacji, zszywa bilet z aplikacją, wykonuje lokalne kontrole i odtwarza ZIP. Do czasu zmiany tego skryptu ZIP pozostaje potrzebny do wysłania aplikacji do notaryzacji; DMG można potem wybrać jako plik dystrybucyjny. Nazwę profilu przekazuje się przez `PROFIL_NOTARYZACJI`. Nie uruchamiaj tego kroku jako części zwykłej kompilacji lub testów.

## Obraz instalacyjny DMG

Po zakończeniu `packaging/notaryzuj.sh` można utworzyć obraz instalacyjny z gotowej, podpisanej i zszytej aplikacji:

```sh
TOZSAMOSC_PODPISU='<nazwa lub odcisk SHA-1 tożsamości Developer ID Application>' packaging/zloz-dmg.sh
```

Skrypt odczytuje wersję z `CFBundleShortVersionString` i tworzy `dist/Gadula-<wersja>.dmg`. Podpisuje obraz wskazaną jawnie tożsamością Developer ID Application. `NOTARYZUJ_DMG` domyślnie wynosi `0`; ustaw `NOTARYZUJ_DMG=1` oraz `PROFIL_NOTARYZACJI` na profil zapisany w pęku kluczy, aby osobno wysłać DMG do Apple, zszyć bilet i sprawdzić wynik przez Gatekeepera. Ten krok wymaga własnego konta Apple Developer i profilu notarytool. Bez tej opcji skrypt nie wysyła danych do Apple.

Domyślnie skrypt steruje Finderem, aby zapisać położenie aplikacji i skrótu do folderu Aplikacje, duże ikony oraz tło okna. macOS może poprosić o jednorazowe zezwolenie na sterowanie Finderem. Ustaw `BEZ_UKLADU_OKNA=1`, aby pominąć ten krok, na przykład podczas lokalnego testu bez zgody Automatyzacji. Wygenerowane tła znajdują się w repozytorium w `packaging/dmg/`. Można je odtworzyć poleceniem `swift packaging/dmg/generuj-tlo.swift packaging/dmg`; generator przyjmuje wyłącznie katalog wyjściowy.
