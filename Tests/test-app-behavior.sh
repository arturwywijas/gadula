#!/bin/bash
# autor: Codex, gadula-stabilnosc-20260927
set -euo pipefail
cd "$(dirname "$0")/.."
test_build="$PWD/.build/app-behavior-test"
mkdir -p "$test_build"
swiftc -swift-version 6 -emit-library -emit-module -module-name VoiceAgentCore \
  Sources/VoiceAgentCore/*.swift -o "$test_build/libVoiceAgentCore.dylib" \
  -emit-module-path "$test_build/VoiceAgentCore.swiftmodule"
swiftc -swift-version 6 -parse-as-library -I "$test_build" -L "$test_build" -lVoiceAgentCore \
  -Xlinker -rpath -Xlinker "$test_build" \
  Sources/VoiceAgentApp/SchowekTextInserting.swift Sources/VoiceAgentApp/WagiModeluNaDysku.swift \
  Sources/VoiceAgentApp/BlokadaInstancji.swift Sources/VoiceAgentApp/Snapshot/Audio/KopiaBuforaAudio.swift \
  Sources/VoiceAgentApp/Snapshot/AppLogger.swift Tests/AppBehaviorTests/main.swift \
  -o "$test_build/AppBehaviorTests"
"$test_build/AppBehaviorTests" "$test_build/fixtures"
swiftc -swift-version 6 -parse-as-library -I "$test_build" -L "$test_build" -lVoiceAgentCore \
  -Xlinker -rpath -Xlinker "$test_build" \
  Sources/VoiceAgentApp/MikrofonAudioCapturing.swift Tests/AudioReconfigurationTests/main.swift \
  -o "$test_build/AudioReconfigurationTests"
"$test_build/AudioReconfigurationTests"
