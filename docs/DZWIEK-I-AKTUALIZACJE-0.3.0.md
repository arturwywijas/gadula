# Dźwięk i aktualizacje Gaduły 0.3.0

autor: Codex, gadula-dzwiek-aktualizacje-20260927

27.09.2026. Raport implementacji i testów. Zaakceptowane przez komisję, 27.09.2026: poprawność, zgodność i jakość; trzy niezależne recenzje PASS.

## Zmiany dla użytkownika

- W menu jest domyślnie włączone „Ściszaj dźwięk podczas dyktowania”. Gaduła zmniejsza poziom wyjścia do 35% poprzedniej wartości przez około 0,4 s. Po zakończeniu mikrofonu przywraca go przez około 0,65 s, także po anulowaniu lub błędzie. To regulacja dźwięku wyjściowego Maca, więc obejmuje również film w przeglądarce i inne aplikacje, nie tylko muzykę. Ręczna zmiana poziomu ma pierwszeństwo.
- Po nagraniu Gaduła zwalnia silnik audio. Na testowanych słuchawkach Philips TAT1500 odtwarzanie wraca z profilu rozmowy (16 kHz, mono) do profilu muzycznego (44,1 kHz). Samo zatrzymanie nagrania w 0.2.0 pozostawiało silnik i jego zasoby wejścia w pamięci, utrzymując gorszą jakość dźwięku.
- Sparkle 2.10.0 sprawdza dostępność aktualizacji, pobiera je w tle i instaluje przy zamknięciu aplikacji. Gaduła pokazuje strzałkę przy ikonie oraz informację o dostępnej wersji w menu. „Sprawdź aktualizacje…” pozwala sprawdzić i zainstalować wersję od razu. Odznaczenie opcji „Aktualizuj automatycznie” wyłącza automatyczne sprawdzanie i pobieranie. Gotowa wcześniej aktualizacja może zostać zainstalowana przy zamknięciu.
- Aktualizator nie kończy sesji dyktowania: zamknięcie aplikacji czeka na zakończenie nagrania i wstawienia tekstu, a w tym czasie nie można rozpocząć nowej sesji.

## Przyczyna i dowód naprawy Bluetooth

Przed zmianą, po zamknięciu Gaduły, słuchawki odtwarzały w 44,1 kHz. Test uruchomił rzeczywisty `AudioRecorder`, zebrał 77 824 próbki i zatrzymał nagranie. Cztery sekundy później wyjście nadal pracowało w 16 kHz. Test zakończył się FAIL.

Poprawka usuwa obserwator konfiguracji, tap, silnik i konwerter po stop oraz po nieudanym starcie. Nowy silnik powstaje dopiero przy kolejnym starcie. Zmiana formatu wewnątrz jednej sesji nadal zachowuje jej PCM i obecny silnik. Nie ma ręcznego przepinania AUHAL.

Po zmianie trzy sesje po 6 s zebrały po 94 208 próbek; każda wróciła do 44,1 kHz w kontroli po 4 s. Osobny test pięciu sesji bez przerwy między stop i start zebrał 94 208, a następnie cztery razy 77 824 próbek, bez błędu startu. Test łączący ściszanie i mikrofon przeszedł trzy razy: po 94 208 próbek, powrót do 44,1 kHz i identyczny poprzedni poziom głośności. Testy nie zapisują ani nie transkrybują nagrywanego głosu.

## Ściszanie i odporność na błędy

Stan jest przypisany do UID wyjścia oraz jego kanałów, a nie do zmiennego numeru urządzenia. Głośność kanałów jest zachowana osobno. Identyfikator ma stabilny zapis; zmienna kolejność kluczy JSON nie może udawać zmiany urządzenia. Adapter normalizuje żądany poziom konwersjami scalar → dB → scalar kontrolki CoreAudio. Gdy wyjście nie udostępnia potrzebnej regulacji lub konwersji, funkcja go nie zmienia.

Zapis CoreAudio może być asynchroniczny. Dziennik przechowuje poprzednią i oczekującą wartość, a potwierdzenie nie opiera się na starym odczycie. Odrzucony zapis ani błąd dziennika nie przerywają prób przywrócenia głośności. Testy obejmują również nową sesję rozpoczętą przed wykonaniem poprzedniej zmiany i urządzenie zaokrąglające do 128 poziomów.

Dziennik głośności jest zapisywany atomowo lokalnie w `~/Library/Application Support/Gadula/glosnosc.json`. Nie zawiera nagrań ani transkryptów. Nowe ściszenie wymaga skutecznego zapisu. Po nieoczekiwanym zakończeniu procesu poziom jest odzyskiwany przy następnym uruchomieniu Gaduły, o ile użytkownik nie zmienił go ręcznie. Przy normalnym zamykaniu aplikacja zleca przywrócenie bez animacji; dziennik pozostaje do potwierdzenia. Po odłączeniu urządzenia Gaduła czeka na jego powrót; po wybudzeniu wznawia odzyskiwanie.

W próbie fizycznego wyjścia: `[0.6116619, 0.611662]` → około `[0.21408165, 0.2140817]` → `[0.6116619, 0.611662]`. To poziomy skalarne kontrolki, nie pomiar głośności akustycznej w dB.

## Aktualizacje, prywatność i wydawanie

Feed i paczki są na GitHubie. Automatyczne sprawdzanie oznacza połączenia z GitHub nawet wtedy, gdy nie trwa dyktowanie; domyślny harmonogram Sparkle sprawdza aktualizacje raz dziennie. Profilowanie systemu jest wyłączone. Rozpoznawanie mowy pozostaje lokalne, aktualizator nie otrzymuje nagrań ani tekstu. Wyłączenie aktualizacji automatycznych nie zmienia sposobu pobierania modeli z Hugging Face.

Feed oraz archiwum mają podpis Ed25519. Archiwum jest weryfikowane przed rozpakowaniem. Podpis feedu jest wymagany bez wyjątku czasowego. Aplikacja i pomocniki Sparkle są podpisane Developer ID; paczka aplikacji i DMG wymagają notaryzacji. Prywatny klucz aktualizacji pozostaje w Pęku kluczy, publiczny jest w Info.plist. Nie dodano własnego serwera.

Przygotowanie kolejnego wydania:

1. Zwiększyć `CFBundleVersion` oraz wersję produktu w `packaging/Info.plist`.
2. Zbudować, podpisać i notaryzować aplikację dotychczasowymi skryptami.
3. Uruchomić `packaging/przygotuj-aktualizacje.sh` ze wskazaniem katalogu budowy i konta klucza Sparkle. Skrypt przygotowuje ZIP i podpisany `appcast.xml`, niczego nie publikuje.
4. Opublikować niezmienne archiwum ZIP jako zasób wydania. Dopiero potem umieścić podpisany `appcast.xml` w głównej gałęzi repozytorium publicznego. Nie edytować podpisanego feedu po wygenerowaniu.
5. Zachować DMG dla nowych instalacji. Istniejący mechanizm aktualizacji zastępuje aplikację pod dotychczasową ścieżką.

Wersja 0.2.0 nie zawiera aktualizatora. Jej użytkownicy muszą jednorazowo zainstalować 0.3.0 dotychczasową metodą. Następne wydania mogą już przychodzić przez Sparkle.

## Weryfikacja i ograniczenia

- Rdzeń: 154 testy PASS, w tym opóźnione zapisy, błędy HAL i dziennika, mała ręczna zmiana, zmiana wyjścia, ponowne podłączenie i odzyskanie po restarcie.
- Dotychczasowe testy aplikacji i adaptera: 9 + 4 PASS.
- Sprzęt: opisane wyżej próby rzeczywistego mikrofonu i wyjścia Bluetooth. Nie jest to deklaracja zgodności ze wszystkimi słuchawkami, HDMI, AirPlay czy interfejsami USB.
- Instalacja przez Sparkle: PASS. Lokalny serwer podał podpisany feed i ZIP z finalną notaryzowaną aplikacją. Osobny sterownik testowy zainstalował ją w kopii oznaczonej wcześniej jako build 3. Kontrola potwierdziła build 4, poprawny pełny podpis i identyczność pliku wykonywalnego z wydaniem. Test dotyczył zewnętrznej, nieuruchomionej kopii; nie sprawdzał standardowego okna Sparkle, ponownego uruchomienia ani instalacji w trakcie rzeczywistego dyktowania.
- Zmieniony podpis feedu: PASS. Sparkle odrzucił zmodyfikowaną listę wersji z `SUSparkleErrorDomain` 1000 i przyczyną 3002 (podpis), a kopia aplikacji pozostała w buildzie 3. Test wymaga tego dokładnego błędu, więc awaria sieci nie może go zaliczyć.
- Finalna aplikacja ma akceptację Apple Notary Service (`a7fb54ae-e8bd-4cc1-bd17-02af74611374`), zszyty bilet i pozytywną ocenę Gatekeepera. Obraz DMG również został zaakceptowany (`d4b84765-0554-4d44-afc0-6c039e720201`), zszyty i sprawdzony.
- Nagłe zabicie procesu może pozostawić ściszenie do ponownego uruchomienia aplikacji. Dziennik umożliwia wtedy odzyskanie; nie dodano osobnego stale działającego procesu nadzorującego.
- Inna aplikacja korzystająca z mikrofonu Bluetooth może nadal utrzymywać profil rozmowy. Gaduła zwalnia własne zasoby; nie zatrzymuje innych aplikacji.

Źródła techniczne: [Sparkle: konfiguracja](https://sparkle-project.org/documentation/customization/), [Sparkle: delegate i instalacja](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html), [Apple: jakość dźwięku Bluetooth podczas używania mikrofonu](https://support.apple.com/en-ie/102217). Zachowanie asynchronicznych zapisów i konwersji głośności sprawdzone również w nagłówkach CoreAudio lokalnego SDK macOS.
