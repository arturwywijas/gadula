#!/bin/bash
# autor: Codex, gadula-stabilnosc-20260927
# Jawny test sprzętowy. Sześć sekund z bieżącego mikrofonu, bez zapisu audio.
set -euo pipefail
cd "$(dirname "$0")/.."
test_build="$PWD/.build/microphone-test"
mkdir -p "$test_build/AudioTapGuard"
swiftc -swift-version 6 -emit-library -emit-module -module-name VoiceAgentCore \
  Sources/VoiceAgentCore/*.swift -o "$test_build/libVoiceAgentCore.dylib" \
  -emit-module-path "$test_build/VoiceAgentCore.swiftmodule"
cp Sources/AudioTapGuard/include/AudioTapGuard.h "$test_build/AudioTapGuard/"
cat > "$test_build/AudioTapGuard/module.modulemap" <<'MAP'
module AudioTapGuard { header "AudioTapGuard.h" export * }
MAP
clang -fobjc-arc -c Sources/AudioTapGuard/AudioTapGuard.m \
  -I Sources/AudioTapGuard/include -o "$test_build/AudioTapGuard.o"
swiftc -swift-version 6 -parse-as-library -I "$test_build" -I "$test_build/AudioTapGuard" \
  -L "$test_build" -lVoiceAgentCore -Xlinker -rpath -Xlinker "$test_build" \
  Sources/VoiceAgentApp/Snapshot/Audio/AudioRecorder.swift \
  Sources/VoiceAgentApp/GlosnoscSystemowa.swift \
  Sources/VoiceAgentApp/Snapshot/Audio/KopiaBuforaAudio.swift \
  Sources/VoiceAgentApp/Snapshot/Audio/AudioDeviceManager.swift \
  Sources/VoiceAgentApp/Snapshot/AppLogger.swift \
  "$test_build/AudioTapGuard.o" Tests/AudioRecorderTests/main.swift \
  -o "$test_build/MicrophoneTest"
"$test_build/MicrophoneTest" "$@"
