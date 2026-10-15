#!/bin/bash
# Baixa o modelo Whisper usado nos testes de transcrição para ~/Library/Caches/OpenFrame-test-models.
# Os testes nunca baixam sozinhos: sem o modelo, eles são pulados com uma mensagem.
#
#   ./scripts/baixar-modelo-teste.sh          # base (148 MB), o padrão dos testes
#   ./scripts/baixar-modelo-teste.sh small    # outro modelo do catálogo (base, small, turbo)
set -euo pipefail

MODEL=${1:-base}
case "$MODEL" in
    base)  FILE=ggml-base.bin;                SHA=60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe ;;
    small) FILE=ggml-small.bin;               SHA=1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b ;;
    turbo) FILE=ggml-large-v3-turbo-q5_0.bin; SHA=394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2 ;;
    *) echo "Modelo desconhecido: $MODEL (use base, small ou turbo)" >&2; exit 1 ;;
esac

DIR="$HOME/Library/Caches/OpenFrame-test-models"
mkdir -p "$DIR"
if [ -f "$DIR/$FILE" ] && [ "$(shasum -a 256 "$DIR/$FILE" | cut -d' ' -f1)" = "$SHA" ]; then
    echo "Já existe: $DIR/$FILE"
    exit 0
fi
curl -L --fail --progress-bar -C - -o "$DIR/$FILE.partial" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$FILE"
GOT=$(shasum -a 256 "$DIR/$FILE.partial" | cut -d' ' -f1)
if [ "$GOT" != "$SHA" ]; then
    rm -f "$DIR/$FILE.partial"
    echo "sha256 não confere ($GOT); arquivo apagado." >&2
    exit 1
fi
mv "$DIR/$FILE.partial" "$DIR/$FILE"
echo "Pronto: $DIR/$FILE"
