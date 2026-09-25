# Jak działa Gaduła

Szczegółowy opis działania Gaduły 0.1.0. Instalację i skrót opisuje [README](../README.md).

## Skrót i tryb

Menu **Skrót** zawiera Option+Space, Control+Option+Space, Control+Option+Command+Space, Fn i możliwość przechwycenia własnej kombinacji. Menu **Tryb** ma dwa wybory:

- **Przełącznik**: naciśnij, mów, naciśnij ponownie.
- **Przytrzymanie**: trzymaj, mów, puść.

Każda kombinacja obsługuje oba tryby. Sam modyfikator wymaga przytrzymania. **Fn jest przeznaczony wyłącznie dla klawiatury Apple**; Logitech nie przekazuje zgodnego Fn do macOS. Połączenie Fn z przełącznikiem jest odrzucane z komunikatem w menu. Dla Fn potrzebna jest Dostępność; ustaw też systemową akcję „Naciśnięcie klawisza Fn” na „Nic nie rób”, aby uniknąć jej uruchamiania. Option+Space korzysta z osobnego mechanizmu skrótów i nie wymaga Dostępności do samego nasłuchu.

Wybór zapisuje się i obowiązuje od następnej sesji bez restartu. Dotychczasowe zapisane ustawienia pozostają zachowane. Inne aplikacje mogą zajmować tę samą kombinację. Błąd rejestracji lub upływ czasu przechwytywania jest widoczny w menu. Samotny prawy Option jest odrzucany, ponieważ na polskim układzie służy do wpisywania ogonków.

Przy połączeniu klawiatury przez Bluetooth skrót może reagować zauważalnie wolniej niż przez odbiornik USB Bolt. Nie oznacza to, że zmiana połączenia rozwiązuje problem naciśnięć bez efektu.

## Uprawnienia, mikrofon i wklejanie

| Uprawnienie | Zastosowanie |
|---|---|
| Mikrofon | Nagrywanie głosu. System pyta przy pierwszej próbie nagrania wymagającej zgody, a nie przy każdym pierwszym użyciu skrótu. Przed gotowością modelu próba może zakończyć się bez pytania. |
| Dostępność | Symulowanie Cmd-V oraz nasłuch samego modyfikatora, np. Fn. |

Monitorowanie wprowadzania (Input Monitoring) nie jest tu przedstawiane jako obowiązkowa zgoda. Nie potwierdzono przypadku, w którym trzeba ją nadać dla tej aplikacji.

Wybór mikrofonu w menu zmienia **systemowe domyślne wejście dla całego Maca**, także dla innych aplikacji. Poprzednie wejście nie jest przywracane po sesji. Odmowa dostępu do mikrofonu kończy próbę nagrania komunikatem w menu z możliwością przejścia do ustawień.

Po rozpoczęciu nagrywania aplikacja próbuje odczytać poziom wejścia mikrofonu. Jeśli odczyt jest dostępny i wynosi mniej niż **−12 dB**, menu pokazuje wartość i wskazówkę, jak podnieść poziom w Ustawieniach systemowych → Dźwięk → Wejście. Aplikacja tylko odczytuje poziom i sama nie zmienia systemowej głośności wejścia.

Automatyczne wstawianie jest próbą wysłania Cmd-V. Wymaga Dostępności i aktywnego edytowalnego pola, a aplikacja nie potwierdza, czy program docelowy odczytał tekst. W tej ścieżce po około 0,4 sekundy przywraca poprzedni tekst schowka; zgodność z każdym programem docelowym nie została sprawdzona.

Gdy brakuje Dostępności, po udanym nagraniu i transkrypcji tekst pozostaje w schowku, a menu pokazuje **Wciśnij Cmd-V**. Ta ścieżka wymaga działającego sposobu rozpoczęcia nagrania, np. kombinacji Option+Space; nie jest gwarancją działania Fn bez uprawnienia. Aplikacja nie wykrywa ręcznego wklejenia i w tej ścieżce nie przywraca poprzedniej zawartości schowka.

Przed rozpoznaniem aplikacja wyrównuje poziom próbek. Cel 0,08 dotyczy mediany RMS aktywnych ramek 20 ms; wzmocnienie nie przekracza 12. Ograniczenie szczytu korzysta z 85. percentyla szczytów aktywnych ramek, a końcowy ogranicznik utrzymuje próbki w zakresie ±0,95. Wzmocnienie wymaga co najmniej ośmiu aktywnych ramek, czyli łącznie 160 ms aktywności; krótsza aktywność, w tym krótki szum, pozostaje bez wzmocnienia. Są to reguły przetwarzania sygnału, nie potwierdzenie poprawy jakości rozpoznawania. Wyników jakości nie zmierzono.

## Model i prywatność

Transkrypcja odbywa się lokalnie. Aplikacja nie ma kont użytkowników ani telemetrii; w kodzie nie ma ścieżki wysyłania nagranego dźwięku do usługi rozpoznawania mowy.

WhisperKit pobiera z Hugging Face zasoby rozpoznawania, w tym wagi modelu, konfigurację i tokenizer. Pobranie może być potrzebne przy pierwszym użyciu, ponowieniu lub zmianie modelu. Ładowanie tokenizera może skorzystać z sieci także wtedy, gdy wagi są już lokalnie. Praca bez sieci wymaga wcześniejszego pobrania wszystkich potrzebnych zasobów, nie tylko wag; pełnego ruchu sieciowego aplikacji nie zmierzono.

Źródłem modeli jest repozytorium `argmaxinc/whisperkit-coreml` w Hugging Face. Menu udostępnia warianty **large-v3-turbo** i **small**. Zasoby są pobierane poza aplikacją, m.in. do `~/Documents/huggingface/`. Łączne zajęcie dysku przez model, tokenizer i pamięć podręczną nie zostało zmierzone i zależy od wybranego modelu oraz pobranych zasobów.

## Wskaźnik nagrywania i autostart

Podczas nagrywania wskaźnik poziomu dźwięku pojawia się na dole ekranu. W menu **Wskaźnik nagrywania** są **Iskry** (domyślne), **Słupki** i **Nić światła**. Wybór zapisuje się i obowiązuje od następnego nagrania bez restartu.

Menu zawiera opcję **Uruchamiaj przy logowaniu**. Jej działania po ponownym zalogowaniu na złożonej aplikacji nie sprawdzono. Uruchomienie przez `swift run` nie zastępuje testu autostartu aplikacji `.app`.

## Zgodność i stan sprawdzenia

Manifest projektu deklaruje minimum **macOS 14**. Jest to deklaracja zgodności, nie wynik testu na macOS 14. Nie ustalono wersji macOS ani architektury, na których wykonano dotychczasowe uruchomienia. Działania na Macach z procesorem Intel nie sprawdzono. Gotowa aplikacja nie wymaga instalacji Swifta.

Testy automatyczne nie zastępują testów mikrofonu, klawiatur i interfejsu na urządzeniu.

## Podpis wydania

Wydanie **0.1.0** (build 1) jest udostępniane jako `Gadula-0.1.0.dmg`, podpisany certyfikatem **Developer ID Application**. Apple zaakceptowało notaryzację obrazu dysku (zgłoszenie `754f53e4-f749-4b44-9d24-3500ea8ce030`), a bilet został zszyty z DMG. Aplikacja wewnątrz obrazu była notaryzowana osobno. `spctl --assess` zwraca **accepted** ze źródłem **Notarized Developer ID**.

Po pobraniu możesz sprawdzić podpis DMG i porównać jego sumę z wartością podaną przy wydaniu. Po przeniesieniu aplikacji do folderu Aplikacje możesz też sprawdzić jej podpis i bilet:

```sh
spctl --assess --type open --context context:primary-signature "$HOME/Downloads/Gadula-0.1.0.dmg"
shasum -a 256 "$HOME/Downloads/Gadula-0.1.0.dmg"
spctl --assess --type execute --verbose=4 "/Applications/Gaduła.app"
xcrun stapler validate "/Applications/Gaduła.app"
xcrun stapler validate "$HOME/Downloads/Gadula-0.1.0.dmg"
```

Oczekiwana suma SHA-256 pliku `Gadula-0.1.0.dmg` to `e4aa6aa29d90b8f633589a6381b8766e41449917eee4d5bf95b84c030630cc79`. `spctl` i `shasum` są dostępne w każdym macOS. Polecenie `xcrun stapler validate` wymaga narzędzi deweloperskich Apple. Samodzielnie zbudowana kopia ze źródeł nie jest notaryzowana, dopóki ktoś nie przejdzie własnej notaryzacji.

## Budowanie ze źródeł

Wymagania toolchainu oraz instrukcja budowy pliku wykonywalnego, testów, składania aplikacji .app i przygotowania osobnego wydania znajdują się w [docs/BUILDING.md](BUILDING.md).

## Testy ze źródeł

Zestaw VoiceAgentCoreTests obejmuje **98 przypadków**. Osobny cel AudioTapGuardTests sprawdza ochronę instalacji tapu audio przed wyjątkiem Objective-C. Testy rdzenia używają atrap portów; nie sprawdzają rzeczywistego mikrofonu, klawiatury ani interfejsu na urządzeniu. Polecenia uruchomienia i zakres testów opisuje [docs/BUILDING.md](BUILDING.md).

## Licencje

Kod Gaduły: MIT, Copyright (c) 2026 Artur Wywijas, zgodnie z plikiem [LICENSE](../LICENSE).

[Noty oprogramowania osób trzecich](../THIRD-PARTY-NOTICES.md) obejmują dictly i WhisperKit na MIT oraz swift-transformers (Hugging Face), użyty przez WhisperKit, na Apache 2.0. Noty z pełnymi tekstami licencji są również zasobem aplikacji dostępnym przez **O aplikacji → Licencje**.
