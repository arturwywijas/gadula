#!/usr/bin/env zsh
# Wysyła Gaduła.app do notaryzacji Apple, zszywa bilet i sprawdza wynik.
#
# Warunki wstępne, jednorazowe:
#  1. W pęku kluczy jest własny certyfikat Developer ID Application.
#  2. W pęku kluczy zapisano profil notarytool. Jego nazwę przekazuje się przez
#     PROFIL_NOTARYZACJI. Poniżej znajduje się wyłącznie wzorzec konfiguracji:
#       xcrun notarytool store-credentials <nazwa-profilu> \
#         --apple-id <identyfikator-Apple> --team-id <identyfikator-zespolu> \
#         --password <haslo-aplikacyjne>
#
# Dane dostępowe należy wprowadzić we własnym środowisku. Nie wpisuj ich do repo.
# Uruchamiaj po złożeniu aplikacji podpisanej Developer ID, wyłącznie przy świadomym wydaniu.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}
REPO="${0:A:h:h}"
APP="$REPO/dist/Gaduła.app"
ARCHIWUM="$REPO/dist/Gadula.zip"
PROFIL="${PROFIL_NOTARYZACJI:-gadula-notary}"
WYMAGANIE_DEVELOPER_ID='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'

if [[ ! -d "$APP" ]]; then
  echo "Brak $APP. Najpierw uruchom packaging/zloz-bundel.sh." >&2
  exit 1
fi

echo "== 1. Sprawdzenie podpisu przed wysyłką =="
if ! codesign --verify --strict --verbose=2 --test-requirement "=$WYMAGANIE_DEVELOPER_ID" "$APP"; then
  echo "BŁĄD: podpis nie spełnia wymagania Apple Developer ID Application: poprawny łańcuch Apple i rozszerzenie certyfikatu Developer ID." >&2
  echo "Notaryzacja nie zostanie uruchomiona. Podpisz aplikację właściwym certyfikatem Developer ID." >&2
  exit 1
fi
echo "zweryfikowano certyfikat Apple Developer ID Application"
UPRAWNIENIA=$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)
if [[ "$UPRAWNIENIA" == *"audio-input"* ]]; then
  echo "uprawnienie do mikrofonu obecne"
else
  echo "BŁĄD: brak uprawnienia do mikrofonu przy hardened runtime." >&2
  exit 1
fi

echo "== 2. Archiwum do wysyłki =="
rm -f "$ARCHIWUM"
ditto -c -k --keepParent "$APP" "$ARCHIWUM"

echo "== 3. Notaryzacja, to trwa od kilku do kilkunastu minut =="
xcrun notarytool submit "$ARCHIWUM" --keychain-profile "$PROFIL" --wait

echo "== 4. Zszycie biletu z aplikacją =="
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "== 5. Kontrola Gatekeepera =="
spctl --assess --type execute -vv "$APP"

echo "== 6. Archiwum do publikacji =="
rm -f "$ARCHIWUM"
ditto -c -k --keepParent "$APP" "$ARCHIWUM"
echo "gotowe do wysłania na stronę: $ARCHIWUM"
