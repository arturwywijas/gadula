#!/bin/bash
# autor: Codex, gadula-stabilnosc-20260927
# Szybki harness rdzenia, bez pobierania lub budowania WhisperKit.
set -euo pipefail
cd "$(dirname "$0")/.."
test_build="$PWD/.build/core-test"
mkdir -p "$test_build"
swiftc -swift-version 6 -emit-library -emit-module -module-name VoiceAgentCore \
  Sources/VoiceAgentCore/*.swift -o "$test_build/libVoiceAgentCore.dylib" \
  -emit-module-path "$test_build/VoiceAgentCore.swiftmodule"
swiftc -swift-version 6 -I "$test_build" -L "$test_build" -lVoiceAgentCore \
  -Xlinker -rpath -Xlinker "$test_build" Tests/VoiceAgentCoreTests/*.swift -o "$test_build/CoreTests"
"$test_build/CoreTests"
