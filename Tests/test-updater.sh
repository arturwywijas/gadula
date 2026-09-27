#!/bin/bash
# autor: Codex, gadula-dzwiek-aktualizacje-20260927
# Pełny test Sparkle na kopii .app. Nie zmienia /Applications ani feedu publicznego.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TOZSAMOSC_PODPISU:?Podaj istniejącą tożsamość Developer ID}"
build_dir="${KATALOG_BUDOWY:-$PWD/.build}"
sparkle="$build_dir/artifacts/sparkle/Sparkle"
source_app="$PWD/dist/Gaduła.app"
xcrun stapler validate "$source_app"
mkdir -p .build/update-test
run_dir="$(mktemp -d "$PWD/.build/update-test/run.XXXXXX")"
mkdir -p "$run_dir/feed" "$run_dir/installed" "$run_dir/Probe.app/Contents/MacOS" "$run_dir/Probe.app/Contents/Frameworks"
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi
  lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$lsreg" -u "$run_dir/Probe.app" >/dev/null 2>&1 || true
  "$lsreg" -u "$run_dir/installed/Gaduła.app" >/dev/null 2>&1 || true
  # Zachowujemy artefakty do audytu, ale bez rozszerzeń rejestrowanych jako aplikacje.
  [[ ! -d "$run_dir/Probe.app" ]] || mv "$run_dir/Probe.app" "$run_dir/Probe.app-zachowana"
  [[ ! -d "$run_dir/installed/Gaduła.app" ]] || mv "$run_dir/installed/Gaduła.app" "$run_dir/installed/Gadula.app-zachowana"
}
trap cleanup EXIT
python3 -u Tests/UpdaterTests/serve.py "$run_dir/feed" "$run_dir/port" > "$run_dir/http.log" 2>&1 &
server_pid=$!
for attempt in {1..50}; do [[ -f "$run_dir/port" ]] && break; sleep 0.1; done
feed_url="http://127.0.0.1:$(cat "$run_dir/port")/"
ditto "$source_app" "$run_dir/installed/Gaduła.app"
python3 - "$run_dir" <<'PY'
import pathlib, plistlib, sys, uuid
root=pathlib.Path(sys.argv[1]); app=root/'installed/Gaduła.app/Contents/Info.plist'
data=plistlib.loads(app.read_bytes()); data['CFBundleVersion']='3'; data['CFBundleShortVersionString']='0.2.99'
data['SUDefaultsDomain']='com.arturwywijas.gadula.updatertest.'+uuid.uuid4().hex
data['SUEnableAutomaticChecks']=False
app.write_bytes(plistlib.dumps(data))
probe=dict(CFBundleIdentifier='com.arturwywijas.gadula.updateprobe', CFBundleExecutable='Probe', CFBundleName='Gaduła: test aktualizacji', CFBundleVersion='1', CFBundlePackageType='APPL', LSUIElement=True)
(root/'Probe.app/Contents/Info.plist').write_bytes(plistlib.dumps(probe))
PY
codesign --force --sign "$TOZSAMOSC_PODPISU" --options runtime --timestamp --entitlements packaging/Gadula.entitlements "$run_dir/installed/Gaduła.app"
ditto "$source_app/Contents/Frameworks/Sparkle.framework" "$run_dir/Probe.app/Contents/Frameworks/Sparkle.framework"
swiftc -swift-version 6 -parse-as-library -F "$sparkle/Sparkle.xcframework/macos-arm64_x86_64" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks Tests/UpdaterTests/main.swift -o "$run_dir/Probe.app/Contents/MacOS/Probe"
# Helper jest lokalnym harness'em z tą samą tożsamością co wydanie.
codesign --force --sign "$TOZSAMOSC_PODPISU" --options runtime --timestamp "$run_dir/Probe.app"
ditto -c -k --keepParent "$source_app" "$run_dir/feed/Gadula-0.3.0.zip"
"$sparkle/bin/generate_appcast" --account com.arturwywijas.gadula --download-url-prefix "$feed_url" --maximum-deltas 0 "$run_dir/feed"
if [[ "${TEST_ZLY_PODPIS:-0}" == 1 ]]; then
  python3 - "$run_dir/feed/appcast.xml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);p.write_bytes(p.read_bytes().replace(b'0.3.0', b'9.9.9'))
PY
  set +e
  "$run_dir/Probe.app/Contents/MacOS/Probe" "$run_dir/installed/Gaduła.app" "${feed_url}appcast.xml" > "$run_dir/result.log" 2>&1
  result=$?
  set -e
  cat "$run_dir/result.log"
  [[ "$result" == 4 ]]
  rg -q 'ODRZUCONO domain=SUSparkleErrorDomain code=1000 underlying=3002' "$run_dir/result.log"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$run_dir/installed/Gaduła.app/Contents/Info.plist")" == 3 ]]
  echo 'PASS: uszkodzony podpis feedu odrzucony, stara aplikacja zachowana'
else
  "$run_dir/Probe.app/Contents/MacOS/Probe" "$run_dir/installed/Gaduła.app" "${feed_url}appcast.xml" > "$run_dir/result.log" 2>&1
  cat "$run_dir/result.log"
  # Sparkle kończy proces źródłowy przed podmianą; czekamy na cały podpisany bundel.
  for attempt in {1..100}; do
    if cmp -s "$source_app/Contents/MacOS/Gadula" "$run_dir/installed/Gaduła.app/Contents/MacOS/Gadula" && codesign --verify --deep --strict "$run_dir/installed/Gaduła.app" 2>/dev/null; then break; fi
    sleep 0.1
  done
  sleep 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$run_dir/installed/Gaduła.app/Contents/Info.plist")" == 4 ]]
  codesign --verify --deep --strict "$run_dir/installed/Gaduła.app"
  cmp "$source_app/Contents/MacOS/Gadula" "$run_dir/installed/Gaduła.app/Contents/MacOS/Gadula"
  echo "PASS: pobranie, podpisy, instalacja i identyczność pliku wykonywalnego"
fi
echo "Raport: $run_dir"
