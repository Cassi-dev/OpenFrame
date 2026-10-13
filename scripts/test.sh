#!/bin/bash
# Roda os testes. Com só as Command Line Tools (sem Xcode), o framework
# Swift Testing fica fora do caminho padrão e precisa ser indicado.
set -euo pipefail
cd "$(dirname "$0")/.."
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
EXTRA=()
if [ -d "$FW/Testing.framework" ] && ! xcode-select -p | grep -q Xcode.app; then
  EXTRA=(-Xswiftc -F -Xswiftc "$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB")
fi
exec swift test "${EXTRA[@]}" "$@"
