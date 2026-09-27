#!/usr/bin/env zsh
# Składa Gaduła.app do projects/voice-agent/dist i podpisuje go.
#
# TRYB_PODPISU przyjmuje adhoc, lokalny albo developer-id. Domyślnie używa
# podpisu ad hoc. Tryby lokalny i developer-id wymagają jawnej tożsamości
# podanej przez TOZSAMOSC_PODPISU.
#
# Podpis jest ostatnim krokiem pakowania. Nie uruchamiaj później codesign z
# myślnikiem jako tożsamością, bo zmieniłoby to tożsamość podpisu.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
REPO="${0:A:h:h}"
APP="$REPO/dist/Gaduła.app"
BINARNY="$APP/Contents/MacOS/Gadula"
TRYB_PODPISU="${TRYB_PODPISU:-adhoc}"
TOZSAMOSC_PODPISU="${TOZSAMOSC_PODPISU:-}"
IDENTYFIKATOR_TOZSAMOSCI=""
NAZWA_TOZSAMOSCI=""
WYMAGANIE_DEVELOPER_ID='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'

blad() {
  print -u2 -- "BŁĄD: $1"
  exit 2
}

znajdzUruchomioneGadula() {
  ps -ww -axo pid=,command= | awk -v bin="$BINARNY" '
    {
      linia = $0
      sub(/^[[:space:]]*/, "", linia)
      pid = linia
      sub(/[[:space:]].*$/, "", pid)
      sub(/^[0-9]+[[:space:]]+/, "", linia)
      if (index(linia, bin) == 1) {
        separator = substr(linia, length(bin) + 1, 1)
        if (separator == "" || separator == " ") print pid
      }
    }'
}

sprawdzCzyGadulaDziala() {
  URUCHOMIONE_PID="$(znajdzUruchomioneGadula)"
  if [[ -n "$URUCHOMIONE_PID" ]]; then
    blad "Gaduła działa już z tej ścieżki (PID: ${URUCHOMIONE_PID//$'\n'/, }). Zamknij ją ręcznie przed złożeniem aplikacji."
  fi
}

case "$TRYB_PODPISU" in
  adhoc)
    if [[ -n "$TOZSAMOSC_PODPISU" ]]; then
      blad "TRYB_PODPISU=adhoc nie używa TOZSAMOSC_PODPISU."
    fi
    ;;
  lokalny|developer-id)
    [[ -n "$TOZSAMOSC_PODPISU" ]] || blad "Ustaw jawnie TOZSAMOSC_PODPISU dla trybu $TRYB_PODPISU."

    # Zbieramy wynik bez grep w potoku, więc brak certyfikatów nie przerywa
    # skryptu przez set -e i pipefail.
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

    dopasowanie="${trafienia[1]}"
    IDENTYFIKATOR_TOZSAMOSCI="${dopasowanie%%|*}"
    NAZWA_TOZSAMOSCI="${dopasowanie#*|}"
    if [[ "$TRYB_PODPISU" == "developer-id" && "$NAZWA_TOZSAMOSCI" != *"Developer ID Application"* ]]; then
      blad "TRYB_PODPISU=developer-id wymaga tożsamości Developer ID Application."
    fi
    ;;
  *)
    blad "Nieznany TRYB_PODPISU: $TRYB_PODPISU. Użyj adhoc, lokalny albo developer-id."
    ;;
esac

sprawdzCzyGadulaDziala

echo "== 1. Build release =="
cd "$REPO"
KATALOG_BUDOWY="${KATALOG_BUDOWY:-$REPO/.build}"
swift build --scratch-path "$KATALOG_BUDOWY" -c release --product Gadula
PRODUKTY="$(swift build --scratch-path "$KATALOG_BUDOWY" -c release --show-bin-path)"
[[ -x "$PRODUKTY/Gadula" ]] || blad "Brak pliku wykonywalnego w $PRODUKTY."

echo "== 2. Złożenie bundla =="
sprawdzCzyGadulaDziala
if [[ -d "$APP" ]]; then
  mkdir -p "$REPO/dist/_archiwum"
  KOPIA="$(mktemp -d "$REPO/dist/_archiwum/bundle.XXXXXX")"
  ditto -c -k --keepParent "$APP" "$KOPIA/poprzedni-bundel.zip"
  mv "$APP" "$KOPIA/Gadula.app-zachowana"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUKTY/Gadula" "$APP/Contents/MacOS/Gadula"
cp "$REPO/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$REPO/packaging/ikona/Gadula.icns" "$APP/Contents/Resources/Gadula.icns"
setopt local_options null_glob
for zasob in "$PRODUKTY"/*.bundle; do
  cp -R "$zasob" "$APP/Contents/Resources/"
  echo "zasoby: ${zasob:t}"
done

# Sparkle jest biblioteką dynamiczną. Kopia zachowuje symlinki frameworka.
SPARKLE="$KATALOG_BUDOWY/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE" ]] || blad "Brak frameworka Sparkle po rozwiązaniu zależności."
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# SPM dodaje rpath dla narzędzia CLI; bundel potrzebuje własnego Frameworks.
install_name_tool -add_rpath '@executable_path/../Frameworks' "$BINARNY"

echo "== 3. Podpis =="
# Podpis od środka na zewnątrz, z zachowaniem wymaganych uprawnień pomocników.
PODPIS="${IDENTYFIKATOR_TOZSAMOSCI:--}"
OPCJE_PODPISU=(--timestamp=none)
if [[ "$TRYB_PODPISU" == developer-id ]]; then OPCJE_PODPISU=(--options runtime --timestamp); fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for czesc in "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
             "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
             "$FRAMEWORK/Versions/B/Autoupdate" \
             "$FRAMEWORK/Versions/B/Updater.app" \
             "$FRAMEWORK"; do
  codesign --force --sign "$PODPIS" "${OPCJE_PODPISU[@]}" --preserve-metadata=entitlements "$czesc"
done

case "$TRYB_PODPISU" in
  adhoc)
    codesign --force --sign - --timestamp=none "$APP"
    echo "podpisano ad hoc; ten tryb nie tworzy wydania notaryzowanego"
    ;;
  lokalny)
    codesign --force --sign "$IDENTYFIKATOR_TOZSAMOSCI" --timestamp=none --identifier com.arturwywijas.gadula "$APP"
    echo "podpisano lokalną tożsamością: $NAZWA_TOZSAMOSCI"
    ;;
  developer-id)
    codesign --force --sign "$IDENTYFIKATOR_TOZSAMOSCI" --options runtime --timestamp --entitlements "$REPO/packaging/Gadula.entitlements" --identifier com.arturwywijas.gadula "$APP"
    ;;
esac

echo "== 4. Kontrola =="
codesign --verify --strict --verbose=2 "$APP"
if [[ "$TRYB_PODPISU" == "developer-id" ]]; then
  if ! codesign --verify --strict --verbose=2 --test-requirement "=$WYMAGANIE_DEVELOPER_ID" "$APP"; then
    blad "Podpis nie spełnia wymagania Apple Developer ID Application: poprawny łańcuch Apple i rozszerzenie certyfikatu Developer ID."
  fi
  echo "zweryfikowano certyfikat Apple Developer ID Application: $NAZWA_TOZSAMOSCI"
  echo "sam podpis nie oznacza ukończonej notaryzacji"
fi
codesign -dv --verbose=4 "$APP" 2>&1 | sed -n -e '/^Identifier=/p' -e '/^CandidateCDHash sha256=/p' -e '/^flags=/p'
echo "wymaganie kodu:"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^.*designated => /  /p'

if [[ "$TRYB_PODPISU" != "adhoc" ]]; then
  # Stan porównawczy pozostaje poza repo i jest rozdzielony dla każdej
  # konkretnej tożsamości certyfikatu.
  KATALOG_PODPISU="$HOME/Library/Application Support/GadulaSigning"
  PLIK_DR="$KATALOG_PODPISU/$IDENTYFIKATOR_TOZSAMOSCI.first-build.dr"
  if [[ ! -f "$PLIK_DR" ]]; then
    mkdir -p "$KATALOG_PODPISU"
    codesign -d -r- "$APP" 2>&1 | sed -n 's/^.*designated => //p' > "$PLIK_DR"
    echo "zapisano wymaganie pierwszego podpisu dla wybranej tożsamości poza repo"
  else
    WYMAGANIE_PIERWSZEGO_PODPISU="$(cat "$PLIK_DR")"
    if codesign --verify --strict --test-requirement "=$WYMAGANIE_PIERWSZEGO_PODPISU" "$APP" 2>/dev/null; then
      echo "podpis zgodny z pierwszym buildem tej tożsamości"
    else
      echo "UWAGA: podpis różni się od pierwszego builda; zgody systemowe mogą wygasnąć"
    fi
  fi
fi

echo "== GOTOWE =="
echo "open '$APP'"
echo "Do lokalnych testów służy podpis ad hoc lub lokalny; standardowe wydanie poza App Store wymaga Developer ID i ukończonej notaryzacji."
