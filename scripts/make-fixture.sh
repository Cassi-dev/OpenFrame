#!/bin/bash
# Gera os projetos de referência que a versão multiplataforma (qt/) usa nos testes
# de compatibilidade do formato .openframe.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=.build/fixture
mkdir -p "$BUILD" qt/tests/fixtures
swiftc -O -o "$BUILD/openframe-fixture" \
  $(find Sources/OpenFrameCore -name '*.swift') scripts/fixture/main.swift
"$BUILD/openframe-fixture" qt/tests/fixtures/completo.openframe
