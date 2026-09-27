# Gaduła 0.2.0: rozpoznawanie, tekst i gotowość mikrofonu

autor: Codex, gadula-dyktowanie-20260927
Data: 27.09.2026
Status: zaakceptowane przez komisję, 27.09.2026. Niezależne recenzje: poprawność audio i sesji, zgodność i prywatność, jakość UX i dokumentacji. Wszystkie uwagi blokujące zamknięte.

## Co się zmienia

- Po skrócie od razu pojawia się żółty komunikat przygotowania. Zielone **Możesz mówić** wymaga pierwszych próbek z mikrofonu. Czerwony stan wskazuje błąd, którego opis jest w menu. Tekst i symbol uzupełniają kolor. Nagrywanie nie działa stale w tle.
- Słownik własnych nazw podpowiada modelowi ich pisownię. Edycja jest w pozycji **Słownik nazw…** w głównym menu aplikacji. Lista ma limit i jest zapisywana lokalnie. Nie jest to trenowanie modelu ani automatyczne zbieranie poprawek.
- Tryb **Uporządkowany tekst** porządkuje odstępy, dzieli dłuższą wypowiedź na akapity i obsługuje jawne komendy akapitu, wiersza i punktu. Nie używa dodatkowego modelu do przepisywania wypowiedzi. **Wierny zapis** pozostaje domyślny. Ostatni niepusty wynik przed formatowaniem można skopiować z menu do zamknięcia aplikacji lub następnego prawidłowego wyniku.
- Zakończone fragmenty są rozpoznawane już w trakcie nagrania, gdy mowa wraca po pauzie. Mikrofon pozostaje jeden, dekoder pracuje kolejno. Anulowanie nie przenosi tekstu do nowej sesji. Błąd fragmentu uruchamia rozpoznanie całego zachowanego nagrania.

## Znalezione przyczyny błędów

W 0.1.1 biblioteka miała domyślny margines jednej sekundy. Nagranie krótsze niż ten margines mogło w ogóle nie wejść do dekodera. Testowe **„Tak.” trwające 0,623 s dawało pusty wynik dwukrotnie**. Margines wynosi teraz zero, również w rzeczywistej próbie rozgrzania modelu.

W trakcie budowy przyrostowego rozpoznawania test wykrył niepożądane dekodowanie samego cichego ogona, który prowokował dopisanie „Dziękuję”. Podział czeka teraz na powrót mowy. Końcowa pauza zostaje przy ostatnim zdaniu, bez usuwania próbek i bez filtrowania słowa „Dziękuję” z tekstu.

Próba rozpoznania całości bez podziału wykryła też brak zdania przecinającego granicę 30 sekund. Całościowy przebieg korzysta teraz z tego samego podziału na pauzach. Jeśli długi fragment nie ma pauz, dekoder używa znaczników czasu do przechodzenia między oknami. Domyślny mechanizm VAD biblioteki nie jest używany do równoległego rozpoznawania fragmentów.

Dodatkowa próba szybkiej mowy (23,872 s, 220 słów/min) z pełnym słownikiem wykazała wyczerpanie wspólnego kontekstu tokenów: wynik urywał się w połowie słowa, przed końcową negacją. Sama zmiana znaczników czasu nie wystarczyła. Teraz aplikacja wykrywa osiągnięcie limitu w każdym oknie i ponawia cały fragment bez słownika. Jeśli również to nie wystarcza, pokazuje błąd z prośbą o krótsze fragmenty, zamiast wklejać oczywiście urwany wynik. Nazwy w takiej powtórce mogą być rozpoznane gorzej, a oczekiwanie trwa dłużej. Podpowiedź mieści się w rzeczywistym limicie biblioteki i nie jest ucinana w połowie nazwy.

Poprawiono dodatkowo izolację anulowanego dekodowania awaryjnego, przekazywanie anulowania do aktywnego zadania pod kolejką, ochronę modelu przed zmianą podczas sesji, komendy wewnątrz cytatów, puste punkty, limit słownika i zachowanie poprzedniego tekstu po pustej próbie.

Problemy sprzętowe, schowek, dwie kopie aplikacji i poprzednie poprawki opisuje [diagnoza 0.1.1](DIAGNOZA-2026-09-27.md).

## Wykonane pomiary

Apple M5, 16 GB, macOS 27.0, model `large-v3-turbo`, syntetyczny polski głos macOS Zosia, 165 słów/min, mono 16 kHz. Każda pozycja ma dwa przebiegi. Czas oznacza oczekiwanie na wynik STT **po zatrzymaniu nagrania**; nie obejmuje wklejenia do innej aplikacji. Nowy tryb przyrostowy otrzymywał próbki w tempie rzeczywistego nagrania. Baza to kod 0.1.1 z `c07862c`.

| Próba | 0.1.1 | 0.2.0, przyrostowo |
|---|---|---|
| „Tak.”, 0,623 s | pusty tekst w obu próbach | „Tak.” w obu próbach, 0,858–0,859 s |
| Siedem części, 36,544 s, pauzy 1 s | 2,375–2,424 s po stop | 1,009–1,022 s po stop; wszystkie części i końcowa negacja zachowane |
| Nazwy, 8,384 s | 1,041 s; m.in. „Artur Wywija”, „Frankentholz” | 1,233–1,279 s; „Artur Wywijas”, „Frankentools”, „Unity”, „Super Hierarchy” z podpowiedzią |
| Idealna cisza, 5 s | nie mierzono tą samą próbą | pusty wynik, bez dopisywania słownika |

W długiej próbie oczekiwanie skróciło się o około 58%. To mały zestaw regresyjny, nie ogólny benchmark jakości polskiego dyktowania ani pomiar głosu Artura. Model zapisał szósty punkt jako „6. Zapisanie…”, zamiast dosłownego „Szósty punkt to zapisanie…”. **Rozpoznawanie nadal nie jest bezbłędne.** Słownik poprawił te konkretne nazwy, ale nie gwarantuje każdej nazwy w każdej wypowiedzi.

Koszt tej zmiany: więcej pracy może być wykonywane podczas nagrywania. Całościowe rozpoznanie nową ścieżką tego samego długiego pliku trwało 7,142–7,277 s. Jest to także ścieżka awaryjna, więc przy błędzie fragmentu oczekiwanie może być dłuższe. Krótka wypowiedź bez pauz nie korzysta ze skrócenia oczekiwania. Zużycia energii nie zmierzono.

Nie deklarujemy przyspieszenia zimnego startu. Pierwsze uruchomienia modeli w eksperymentach były silnie zależne od pamięci podręcznej i przygotowania Core ML. Porównywalne kolejne uruchomienia wynosiły około 1,56 s dla starego programu i 1,75 s dla nowego. Nowy wskaźnik pokazuje to oczekiwanie uczciwie.

[Surowe wyniki prób syntetycznych](testy/dyktowanie-0.2.0.json). Polecenia i generator próbek: [BUILDING.md](BUILDING.md).

## Kontrola i granice

- 136 testów rdzenia: PASS, w tym brak utraty/dublowania PCM, cicha końcówka, anulowanie, serializacja awaryjnego STT, gotowość po danych i formatowanie.
- 9 testów zachowania aplikacji oraz 4 sprawdzenia adaptera audio: PASS.
- Ochrona tapu audio przed wyjątkiem Objective-C: PASS.
- Trzy kolejne nagrania po 6 sekund na tym samym rzeczywistym rejestratorze: PASS; otrzymano 81 920, 94 208 i 98 304 próbek. Dźwięk nie był zapisywany ani transkrybowany.
- Walidator 28 wyników prawdziwego WhisperKit: PASS, w obu trybach i dwóch powtórzeniach. Kontroluje kompletność treści, nazwy, krótkie słowo, ciszę i brak dopisku po ostatnim zdaniu. Cztery przebiegi zachowały końcowe „Nie.” ściszone do 0,4% amplitudy po głośnym zdaniu i pauzie. Kolejne cztery zachowały treść po 10 sekundach niezerowej ciszy. Ostatnie cztery zachowały całą szybką wypowiedź z pełnym słownikiem; ponowienie kosztowało łącznie 4,585–4,810 s po stop.
- Trzy rendery produkcyjnego widoku (przygotowanie, gotowość, błąd) obejrzane przez wykonawcę i niezależnego recenzenta. Czytelne napisy, brak obcięcia i rozróżnianie stanów bez samego koloru.

Testy nie potwierdzają działania każdej klawiatury, Fn, autostartu po ponownym logowaniu ani wklejania do każdego programu. Minimalny macOS 14 pozostaje deklaracją projektu; test wykonano na macOS 27. Zielony stan potwierdza przepływ próbek, ale nie zastępuje sprawdzenia, czy wybrano właściwy mikrofon i czy głos jest słyszalny. Nie mierzono całego ruchu sieciowego. Nagrania nie są wysyłane do usługi STT, a nowy słownik i formatowanie działają lokalnie.


## Gotowe wydanie

Aplikacja 0.2.0, build 3 oraz instalator DMG są podpisane Developer ID, przyjęte przez usługę notaryzacji Apple i mają dołączony bilet. `stapler validate` oraz odpowiednia ocena `spctl` zakończyły się powodzeniem. Plik wykonywalny w DMG jest identyczny z plikiem zainstalowanym w `/Applications/Gaduła.app`.

Na Macu Artura włączono **Uporządkowany tekst** i lokalny słownik nazw, zachowując kopię wcześniejszej aplikacji oraz ustawień poza repozytorium. Publiczna wersja nadal startuje z wiernym zapisem. Nowy proces zarejestrował Option+Space bez błędu. Automatyczne naciśnięcie w narzędziu sterującym oknem trafiło do Findera, dlatego nie zaliczamy tej próby jako testu fizycznego globalnego skrótu. Kontrolę gotowości opieramy na testach przepływu PCM, rzeczywistych próbach mikrofonu i renderach produkcyjnego widoku.

SHA-256 `Gadula-0.2.0.dmg`: `243d25382ae9a93910404ac60636d18628d0cf66576645f219f6a300b6868199`.
