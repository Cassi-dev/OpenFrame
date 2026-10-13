#!/bin/bash
# Gera mídia de exemplo e um projeto Demo.opencut.
# Uso: scripts/make-demo.sh [pasta-de-saída] [--export]   (padrão: ~/Desktop/OpenCut Demo)
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=.build/demo
mkdir -p "$BUILD"
# Compila o gerador junto com o código do núcleo (um único módulo).
swiftc -O -o "$BUILD/opencut-demo" \
  $(find Sources/OpenCutCore -name '*.swift') scripts/demo/main.swift
"$BUILD/opencut-demo" "$@"
