#!/usr/bin/env zsh
# Tworzy, podpisuje i opcjonalnie notaryzuje obraz instalacyjny Gaduły.
# Uruchamiaj po packaging/notaryzuj.sh, na aplikacji z zszytym biletem.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}
REPO="${0:A:h:h}"
APP="$REPO/dist/Gaduła.app"
ZASOBY_DMG="$REPO/packaging/dmg"
NAZWA_WOLUMINU="Gaduła"
TOZSAMOSC_PODPISU="${TOZSAMOSC_PODPISU:-}"
PROFIL_NOTARYZACJI="${PROFIL_NOTARYZACJI:-}"
NOTARYZUJ_DMG="${NOTARYZUJ_DMG:-0}"
BEZ_UKLADU_OKNA="${BEZ_UKLADU_OKNA:-0}"
WYMAGANIE_DEVELOPER_ID='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
PUNKT_MONTOWANIA=""
PUNKT_ROBOCZY=""
ATTACH_NIEZWERYFIKOWANY=0

blad() {
  print -u2 -- "BŁĄD: $1"
  exit 2
}

znajdzPunktMontowania() {
  local indeks=0 kandydat
  while true; do
    /usr/libexec/PlistBuddy -c "Print :system-entities:${indeks}" "$PLIK_ATTACH" >/dev/null 2>&1 || return 1
    kandydat="$(/usr/libexec/PlistBuddy -c "Print :system-entities:${indeks}:mount-point" "$PLIK_ATTACH" 2>/dev/null || true)"
    if [[ -n "$kandydat" ]]; then
      print -r -- "$kandydat"
      return 0
    fi
    (( indeks += 1 ))
  done
}

punktJestZamontowany() {
  local punkt="$1"
  [[ -d "$punkt" ]] || return 1

  local katalogNadrzedny urzadzeniePunktu urzadzenieNadrzednego
  katalogNadrzedny="$(dirname "$punkt")" || return 2
  [[ -d "$katalogNadrzedny" ]] || return 2
  urzadzeniePunktu="$(stat -f %d "$punkt" 2>/dev/null)" || return 2
  urzadzenieNadrzednego="$(stat -f %d "$katalogNadrzedny" 2>/dev/null)" || return 2
  [[ -n "$urzadzeniePunktu" && -n "$urzadzenieNadrzednego" ]] || return 2
  [[ "$urzadzeniePunktu" != "$urzadzenieNadrzednego" ]]
}

case "$NOTARYZUJ_DMG" in
  0|1) ;;
  *) blad "NOTARYZUJ_DMG przyjmuje 0 albo 1." ;;
esac
case "$BEZ_UKLADU_OKNA" in
  0|1) ;;
  *) blad "BEZ_UKLADU_OKNA przyjmuje 0 albo 1." ;;
esac

[[ -d "$APP" ]] || blad "Brak $APP. Najpierw przygotuj i notaryzuj aplikację."
[[ -n "$TOZSAMOSC_PODPISU" ]] || blad "Ustaw jawnie TOZSAMOSC_PODPISU na nazwę lub odcisk SHA-1 istniejącej tożsamości Developer ID Application."
[[ -f "$ZASOBY_DMG/tlo-instalatora.png" && -f "$ZASOBY_DMG/tlo-instalatora@2x.png" ]] || blad "Brakuje wygenerowanych teł w packaging/dmg."
[[ -f "$ZASOBY_DMG/uklad-okna.applescript" ]] || blad "Brakuje pliku układu okna w packaging/dmg."
if [[ "$NOTARYZUJ_DMG" == 1 && -z "$PROFIL_NOTARYZACJI" ]]; then
  blad "Dla NOTARYZUJ_DMG=1 ustaw PROFIL_NOTARYZACJI zapisany w pęku kluczy."
fi

WERSJA=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null) \
  || blad "Nie można odczytać CFBundleShortVersionString z Info.plist aplikacji."
[[ "$WERSJA" == [0-9]* && "$WERSJA" != *[^A-Za-z0-9._+-]* ]] || blad "Nieprawidłowa wersja aplikacji: $WERSJA."

TOZSAMOSCI="$(security find-identity -v -p codesigning 2>/dev/null || true)"
trafienia=()
while IFS= read -r wiersz; do
  [[ "$wiersz" == *") "* ]] || continue
  pozostale="${wiersz#*) }"
  hash="${pozostale%% *}"
  [[ "$pozostale" == *\"* ]] || continue
  nazwa="${pozostale#*\"}"
  nazwa="${nazwa%\"}"
  if [[ "$TOZSAMOSC_PODPISU" == "$hash" || "$TOZSAMOSC_PODPISU" == "$nazwa" ]]; then
    trafienia+=("$hash|$nazwa")
  fi
done <<< "$TOZSAMOSCI"

if (( ${#trafienia[@]} == 0 )); then
  blad "Tożsamość podpisu nie istnieje lub nie jest dostępna: $TOZSAMOSC_PODPISU."
fi
if (( ${#trafienia[@]} > 1 )); then
  blad "Tożsamość jest niejednoznaczna. Podaj jej odcisk SHA-1 w TOZSAMOSC_PODPISU."
fi
IDENTYFIKATOR_TOZSAMOSCI="${trafienia[1]%%|*}"
NAZWA_TOZSAMOSCI="${trafienia[1]#*|}"
[[ "$NAZWA_TOZSAMOSCI" == *"Developer ID Application"* ]] \
  || blad "Podana tożsamość nie jest certyfikatem Developer ID Application."

echo "== Kontrola aplikacji źródłowej =="
if ! codesign --verify --strict --verbose=2 --test-requirement "=$WYMAGANIE_DEVELOPER_ID" "$APP"; then
  blad "Aplikacja nie ma poprawnego podpisu Apple Developer ID Application."
fi
xcrun stapler validate "$APP"

mkdir -p "$REPO/dist"
KATALOG_ROBOCZY="$(mktemp -d "$REPO/dist/.zloz-dmg.XXXXXX")"
PUNKT_ROBOCZY=""
PLIK_ATTACH="$KATALOG_ROBOCZY/montowanie.plist"
OBRAZ_ROBOCZY="$KATALOG_ROBOCZY/Gadula-zapisywalny.dmg"
OBRAZ_PAKOWANY="$KATALOG_ROBOCZY/Gadula-$WERSJA.dmg"
OBRAZ_DOCELOWY="$REPO/dist/Gadula-$WERSJA.dmg"

sprzatanie() {
  local kod=$?
  local celDoOdlaczenia="${PUNKT_MONTOWANIA:-$PUNKT_ROBOCZY}"
  local zachowajKatalog=0
  local stanPunktu
  local fizycznyKatalogRoboczy="${KATALOG_ROBOCZY:A}"
  trap - EXIT INT TERM
  if [[ -d "$KATALOG_ROBOCZY" ]]; then
    if (( ATTACH_NIEZWERYFIKOWANY )) && [[ -z "$PUNKT_MONTOWANIA" ]]; then
      zachowajKatalog=1
      celDoOdlaczenia="nieustalony punkt montowania"
      print -u2 -- "BŁĄD: attach nie potwierdził wyniku, a punkt montowania nie jest znany."
    elif [[ -n "$PUNKT_MONTOWANIA" ]]; then
      if punktJestZamontowany "$PUNKT_MONTOWANIA"; then
        if ! hdiutil detach "$PUNKT_MONTOWANIA" -quiet >/dev/null 2>&1 \
          && ! hdiutil detach -force "$PUNKT_MONTOWANIA" -quiet >/dev/null 2>&1; then
          zachowajKatalog=1
        else
          if punktJestZamontowany "$PUNKT_MONTOWANIA"; then
            stanPunktu=0
          else
            stanPunktu=$?
          fi
          if (( stanPunktu == 0 )); then
            zachowajKatalog=1
          elif (( stanPunktu == 2 )); then
            zachowajKatalog=1
            print -u2 -- "BŁĄD: Nie można potwierdzić, czy punkt montowania został odłączony."
          fi
        fi
      else
        stanPunktu=$?
        if (( stanPunktu == 2 )); then
          zachowajKatalog=1
          print -u2 -- "BŁĄD: Nie można odczytać urządzenia punktu montowania."
        fi
      fi
    fi

    if [[ -n "$PUNKT_ROBOCZY" && -d "$PUNKT_ROBOCZY" ]] && (( ! zachowajKatalog )); then
      # To katalog osobny od obrazu. rmdir odmówi, jeśli jest zamontowany
      # albo nie jest pusty; punktu montowania nigdy nie usuwamy rekurencyjnie.
      if ! rmdir "$PUNKT_ROBOCZY"; then
        zachowajKatalog=1
        celDoOdlaczenia="$PUNKT_ROBOCZY"
        print -u2 -- "BŁĄD: Punkt montowania nie jest pusty lub nadal jest zamontowany."
      fi
    fi

    if [[ "$KATALOG_ROBOCZY" == /Volumes || "$KATALOG_ROBOCZY" == /Volumes/* \
      || "$fizycznyKatalogRoboczy" == /Volumes || "$fizycznyKatalogRoboczy" == /Volumes/* ]]; then
      zachowajKatalog=1
      print -u2 -- "BŁĄD: Odmowa rekurencyjnego usuwania katalogu pod /Volumes."
    fi
    if [[ -n "$PUNKT_ROBOCZY" && "$PUNKT_ROBOCZY" == "$KATALOG_ROBOCZY"/* ]]; then
      zachowajKatalog=1
      print -u2 -- "BŁĄD: Punkt montowania nie może być wewnątrz usuwanego katalogu roboczego."
    fi
    if [[ -n "$PUNKT_MONTOWANIA" && "$PUNKT_MONTOWANIA" == "$KATALOG_ROBOCZY"/* ]]; then
      zachowajKatalog=1
      print -u2 -- "BŁĄD: Aktywny punkt montowania znajduje się wewnątrz usuwanego katalogu roboczego."
    fi

    if (( zachowajKatalog )); then
      print -u2 -- "BŁĄD: Nie usuwam katalogu roboczego, bo obraz może nadal być podłączony."
      print -u2 -- "Zachowany katalog: $KATALOG_ROBOCZY"
      print -u2 -- "Punkt lub urządzenie do odłączenia: $celDoOdlaczenia"
      if [[ "$celDoOdlaczenia" == "nieustalony punkt montowania" ]]; then
        print -u2 -- "Sprawdź punkt poleceniem hdiutil info, a następnie odłącz go przez hdiutil detach."
      else
        print -u2 -- "Odłącz ręcznie poleceniem: hdiutil detach \"$celDoOdlaczenia\""
      fi
      if (( kod == 0 )); then
        kod=2
      fi
    else
      # Usuwanie jest bezpieczne dopiero po sprawdzeniu rzeczywistego stanu
      # hdiutil, niezależnie od wyniku attach i wartości dawniej używanej flagi.
      rm -rf "$KATALOG_ROBOCZY"
    fi
  fi
  exit "$kod"
}
trap sprzatanie EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ROZMIAR_APLIKACJI_KB="$(du -sk "$APP" | awk '{print $1}')"
ROZMIAR_OBRAZU_KB=$(( ROZMIAR_APLIKACJI_KB + ROZMIAR_APLIKACJI_KB / 4 + 32768 ))

echo "== Tworzenie obrazu zapisywalnego =="
hdiutil create -size "${ROZMIAR_OBRAZU_KB}k" -fs HFS+ -volname "$NAZWA_WOLUMINU" -type UDIF "$OBRAZ_ROBOCZY"
if [[ "$BEZ_UKLADU_OKNA" == 1 ]]; then
  PUNKT_ROBOCZY="$(mktemp -d "$REPO/dist/.zloz-dmg-montowanie.XXXXXX")"
  PUNKT_MONTOWANIA="$PUNKT_ROBOCZY"
  ATTACH_NIEZWERYFIKOWANY=1
  hdiutil attach -nobrowse -noverify -noautoopen -mountpoint "$PUNKT_MONTOWANIA" "$OBRAZ_ROBOCZY"
  ATTACH_NIEZWERYFIKOWANY=0
else
  # Bez -nobrowse obraz trafia do /Volumes i może być otwarty przez Finder.
  # Punkt montowania odczytujemy z plist, bo system może dodać sufiks przy
  # istniejącym woluminie o tej samej nazwie.
  ATTACH_NIEZWERYFIKOWANY=1
  hdiutil attach -plist -noverify -noautoopen "$OBRAZ_ROBOCZY" > "$PLIK_ATTACH"
  PUNKT_MONTOWANIA="$(znajdzPunktMontowania)" || blad "Nie udało się odczytać punktu montowania obrazu."
  [[ "$PUNKT_MONTOWANIA" == /Volumes/* && -d "$PUNKT_MONTOWANIA" ]] \
    || blad "Finderowy obraz nie został zamontowany w /Volumes: $PUNKT_MONTOWANIA."
  ATTACH_NIEZWERYFIKOWANY=0
  echo "widoczny punkt montowania: $PUNKT_MONTOWANIA"
fi

echo "== Kopiowanie aplikacji i tła =="
ditto "$APP" "$PUNKT_MONTOWANIA/Gaduła.app"
ln -s /Applications "$PUNKT_MONTOWANIA/Applications"
mkdir "$PUNKT_MONTOWANIA/.background"
cp "$ZASOBY_DMG/tlo-instalatora.png" "$PUNKT_MONTOWANIA/.background/tlo-instalatora.png"
cp "$ZASOBY_DMG/tlo-instalatora@2x.png" "$PUNKT_MONTOWANIA/.background/tlo-instalatora@2x.png"

if [[ "$BEZ_UKLADU_OKNA" == 1 ]]; then
  echo "pominięto układ Findera (BEZ_UKLADU_OKNA=1)"
else
  echo "== Ustawianie układu okna Findera =="
  if ! /usr/bin/osascript "$ZASOBY_DMG/uklad-okna.applescript" "$PUNKT_MONTOWANIA"; then
    blad "Finder nie ustawił układu okna. Obraz nie zostanie skonwertowany ani zapisany jako gotowy DMG."
  fi
  for proba in {1..10}; do
    [[ -f "$PUNKT_MONTOWANIA/.DS_Store" ]] && break
    sleep 1
  done
  [[ -f "$PUNKT_MONTOWANIA/.DS_Store" ]] \
    || blad "Finder zakończył układ, ale nie zapisał .DS_Store. Obraz nie zostanie wydany."
fi

echo "== Odłączanie obrazu roboczego =="
hdiutil detach "$PUNKT_MONTOWANIA" -quiet

echo "== Kompresja obrazu =="
hdiutil convert "$OBRAZ_ROBOCZY" -format UDZO -imagekey zlib-level=9 -o "$OBRAZ_PAKOWANY"

echo "== Podpisywanie obrazu =="
if [[ "$NOTARYZUJ_DMG" == 1 ]]; then
  codesign --force --sign "$IDENTYFIKATOR_TOZSAMOSCI" --timestamp "$OBRAZ_PAKOWANY"
else
  # W trybie lokalnego testu nie odpytujemy serwera znaczników czasu Apple.
  codesign --force --sign "$IDENTYFIKATOR_TOZSAMOSCI" --timestamp=none "$OBRAZ_PAKOWANY"
fi
if ! codesign --verify --strict --verbose=2 --test-requirement "=$WYMAGANIE_DEVELOPER_ID" "$OBRAZ_PAKOWANY"; then
  blad "Podpis DMG nie spełnia wymagania Apple Developer ID Application."
fi

if [[ "$NOTARYZUJ_DMG" == 1 ]]; then
  echo "== Jawna notaryzacja DMG =="
  xcrun notarytool submit "$OBRAZ_PAKOWANY" --keychain-profile "$PROFIL_NOTARYZACJI" --wait
  xcrun stapler staple "$OBRAZ_PAKOWANY"
  xcrun stapler validate "$OBRAZ_PAKOWANY"
  spctl --assess --type open --context context:primary-signature -vv "$OBRAZ_PAKOWANY"
fi

echo "== Weryfikacja obrazu =="
hdiutil verify "$OBRAZ_PAKOWANY"
mv -f "$OBRAZ_PAKOWANY" "$OBRAZ_DOCELOWY"
echo "gotowe: $OBRAZ_DOCELOWY"
