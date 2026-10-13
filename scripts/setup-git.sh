#!/bin/bash
# Ativa os hooks versionados em .githooks (rode uma vez após clonar).
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "Hooks ativados: $(git config core.hooksPath)"
