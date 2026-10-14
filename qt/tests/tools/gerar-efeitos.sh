#!/bin/bash
# Mede os efeitos do núcleo Swift (Core Image) e grava qt/tests/fixtures/efeitos.json,
# a referência dos testes de render da versão Qt. Só roda no macOS.
set -euo pipefail
cd "$(dirname "$0")/../../.."
BUILD=.build/efeitos
mkdir -p "$BUILD"
swiftc -O -o "$BUILD/openframe-efeitos" \
  $(find Sources/OpenFrameCore -name '*.swift') qt/tests/tools/efeitos/main.swift
"$BUILD/openframe-efeitos" qt/tests/fixtures/efeitos.json
