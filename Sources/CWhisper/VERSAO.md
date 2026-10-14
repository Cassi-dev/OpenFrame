# whisper.cpp vendorizado

- Origem: https://github.com/ggml-org/whisper.cpp
- Versão: v1.9.5 (commit d1be6fde11ac6e0407606b4e42fe72d34add8037)
- Licença: MIT (LICENSE nesta pasta), compatível com a GPL do OpenFrame.
- Gerado por `scripts/vendorizar-whisper.sh`. Não edite à mão: rode o script de novo.
- Só entram os arquivos usados no Mac: whisper, ggml (base), CPU (com Accelerate), BLAS (Accelerate) e
  Metal, com os shaders embutidos em `ggml/src/ggml-metal/ggml-metal-embed.c`.
- Os arquivos de `ggml/src/ggml-cpu/arch` entram pelos envoltórios `arch-quants.c` e `arch-repack.cpp`.
