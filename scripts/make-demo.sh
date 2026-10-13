#!/bin/bash
# Gera mídia de exemplo e um projeto Demo.openframe.
# Uso: scripts/make-demo.sh [pasta-de-saída] [--export]   (padrão: ~/Desktop/OpenFrame Demo)
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=.build/demo
mkdir -p "$BUILD"
# Compila o gerador junto com o código do núcleo (um único módulo).
swiftc -O -o "$BUILD/openframe-demo" \
  $(find Sources/OpenFrameCore -name '*.swift') scripts/demo/main.swift
"$BUILD/openframe-demo" "$@"
