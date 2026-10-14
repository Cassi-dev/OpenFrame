#!/bin/bash
# Gera os vídeos HDR de teste (HLG e PQ) e mede a conversão para SDR do macOS:
# qt/tests/fixtures/hdr-hlg.mov, hdr-pq.mov e hdr.json. Só roda no macOS.
set -euo pipefail
cd "$(dirname "$0")/../../.."
BUILD=.build/hdr
mkdir -p "$BUILD"
swiftc -O -o "$BUILD/openframe-hdr" qt/tests/tools/hdr/main.swift
"$BUILD/openframe-hdr" qt/tests/fixtures
