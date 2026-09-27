#!/usr/bin/env zsh
# autor: Codex, gadula-dzwiek-aktualizacje-20260927
# Przygotowuje podpisany feed i ZIP. Nie publikuje niczego w sieci.
set -euo pipefail
REPO="${0:A:h:h}"
APP="$REPO/dist/Gaduła.app"
WERSJA=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD_DIR="${KATALOG_BUDOWY:-$REPO/.build}"
NARZEDZIA="$BUILD_DIR/artifacts/sparkle/Sparkle/bin"
KONTO="${KONTO_SPARKLE:-com.arturwywijas.gadula}"
FEED_DIR="$REPO/dist/aktualizacje"
PREFIKS="${ADRES_AKTUALIZACJI:-https://github.com/arturwywijas/gadula/releases/download/v$WERSJA/}"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
mkdir -p "$FEED_DIR"
# Każdy build ma nowy numer. Nie zastępuj już opublikowanego archiwum.
[[ ! -e "$FEED_DIR/Gadula-$WERSJA.zip" ]] || { print -u2 'Archiwum już istnieje. Zachowaj poprzedni katalog przed ponownym wydaniem.'; exit 2; }
ditto -c -k --keepParent "$APP" "$FEED_DIR/Gadula-$WERSJA.zip"
"$NARZEDZIA/generate_appcast" --account "$KONTO" --download-url-prefix "$PREFIKS" --maximum-deltas 0 "$FEED_DIR"
shasum -a 256 "$FEED_DIR/Gadula-$WERSJA.zip"
echo 'Gotowe: ZIP jako zasób wydania, appcast.xml do repozytorium. Feed publikuj po archiwum.'
