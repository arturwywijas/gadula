#!/bin/bash
# autor: Codex, gadula-dyktowanie-20260927
# Podaj wyłącznie syntetyczne pliki CAF mono Float32 16 kHz. Raport zawiera ich tekst.
set -euo pipefail
cd "$(dirname "$0")/.."
products="${GADULA_PRODUCTS_PATH:-$PWD/.build/out/Products/Release}"
bench="$PWD/.build/transcription-benchmark"
mkdir -p "$bench"
if [[ ! -f "$products/WhisperKit.o" ]]; then
  echo 'Najpierw zbuduj release; ustaw GADULA_PRODUCTS_PATH na katalog produktów.' >&2
  exit 1
fi
swiftc -O -swift-version 6 -parse-as-library -I "$products" \
  Tests/TranscriptionBenchmark/main.swift \
  Sources/VoiceAgentApp/LokalnaTranskrypcja.swift Sources/VoiceAgentApp/KatalogModelu.swift \
  Sources/VoiceAgentApp/WagiModeluNaDysku.swift Sources/VoiceAgentApp/Snapshot/AppLogger.swift \
  Sources/VoiceAgentApp/Snapshot/Transcription/*.swift \
  "$products/VoiceAgentCore.o" "$products/WhisperKit.o" "$products/ArgmaxCore.o" \
  -o "$bench/compare"
"$bench/compare" "$@"
