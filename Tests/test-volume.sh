#!/bin/bash
# autor: Codex, gadula-dzwiek-aktualizacje-20260927
# Test sprzętowy: ścisza bieżące wyjście na mniej niż sekundę i przywraca poziom.
set -euo pipefail
cd "$(dirname "$0")/.."
test_build="$PWD/.build/volume-test"
mkdir -p "$test_build"
swiftc -swift-version 6 -emit-library -emit-module -module-name VoiceAgentCore Sources/VoiceAgentCore/*.swift -o "$test_build/libVoiceAgentCore.dylib" -emit-module-path "$test_build/VoiceAgentCore.swiftmodule"
swiftc -swift-version 6 -parse-as-library -I "$test_build" -L "$test_build" -lVoiceAgentCore -Xlinker -rpath -Xlinker "$test_build" Sources/VoiceAgentApp/GlosnoscSystemowa.swift Sources/VoiceAgentApp/Snapshot/Audio/AudioDeviceManager.swift Sources/VoiceAgentApp/Snapshot/AppLogger.swift Tests/OutputVolumeTests/main.swift -o "$test_build/VolumeTest"
"$test_build/VolumeTest"
