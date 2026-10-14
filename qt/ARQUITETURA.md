# OpenFrame multiplataforma (Windows e Linux)

Versão do OpenFrame para Windows e Linux, em C++20 + Qt 6 (QML) + FFmpeg. O app
Swift (`Sources/`) continua sendo a versão do macOS; as duas abrem os mesmos
projetos `.openframe`. Licença do projeto: GPL-3.0-or-later (o app distribui
FFmpeg com x264/x265).

A versão Qt também compila no macOS, mas só para desenvolvimento: no Mac o app
distribuído é o Swift.

## Decisões

- **Stack:** C++20, Qt 6.8+ (local: 6.12 do Homebrew), FFmpeg 6.1+ (local: 9.0;
  CI: builds "gpl-shared" do BtbN). Usar só APIs presentes do FFmpeg 6.1 ao 9
  (`ch_layout`, `avcodec_send_*/receive_*`, `AV_FRAME_FLAG_KEY`…).
- **Comportamento de referência:** o núcleo Swift (`Sources/OpenFrameCore`). Cada
  regra (timeline magnética, transições, animações, efeitos, texto, exportação,
  bitrate, validação) é portada com os mesmos números e o mesmo resultado.
- **Formato:** o JSON tem que ser idêntico ao do Swift (chaves, enums em
  `rawValue`, UUID em maiúsculas, opcionais nulos omitidos, todos os campos
  gravados, `CanvasBackground` como `{"black":{}}`, `{"color":{"_0":{…}}}`,
  `{"blur":{"_0":0.6}}`). `scripts/make-fixture.sh` gera os projetos de
  referência em `qt/tests/fixtures/` pelo próprio código Swift; o teste de
  compatibilidade lê, grava de novo e compara.
- **Render:** primeira versão na CPU com `QImage` (pré-multiplicado), em paralelo
  com `QtConcurrent`. Funciona sem GPU (CI, VMs) e é testável. O mesmo
  renderizador serve ao preview e à exportação (como o `OpenFrameCompositor`).
  O preview pode renderizar em resolução reduzida. Uma GPU pode vir depois, atrás
  da mesma interface.
- **Cores:** decodificar com a matriz/intervalo do arquivo (709 por padrão em HD,
  nunca o 601 padrão do swscale) e exportar com as marcas BT.709. Teste de ida e
  volta como a suíte Cores do Swift.
- **Áudio:** FFmpeg decodifica e reamostra para 48 kHz estéreo; velocidade com
  `atempo` (sem mudar o tom); mixagem própria com volume, fades e crossfade nas
  transições da faixa principal; reprodução com `QAudioSink` (Qt Multimedia),
  que serve de relógio do preview.
- **Exportação:** H.264 (libx264), HEVC (libx265), ProRes 422 (prores_ks, só MOV),
  AAC; MP4/MOV/M4A. Mesmas opções e cálculos do `ExportSettings` Swift.
- **Biblioteca:** `QStandardPaths::MoviesLocation/OpenFrame/Projetos/<UUID>/`
  (`~/Videos` no Windows/Linux), mesmo layout do Swift; apagar usa
  `QFile::moveToTrash`.
- **Interface:** QML, o mesmo visual do app Swift (preto puro, painéis
  flutuantes, clipes cinza, ciano só no ativo, Inter no lugar da SF Pro, que não
  pode ser distribuída). Textos em português.

## Layout

```
qt/
  CMakeLists.txt          raiz (Qt, opções, subdiretórios)
  cmake/FFmpeg.cmake      FFmpeg::FFmpeg (pkg-config ou FFMPEG_ROOT no Windows)
  src/core/               openframe_core (biblioteca estática, sem QML)
  src/app/                executável OpenFrame (QML, modelo do editor)
  tests/                  Qt Test, uma suíte por arquivo; fixtures/
```

- Namespace `of`. Arquivos em PascalCase. **Não usar nomes que colidem com
  cabeçalhos do sistema sem diferenciar maiúsculas** (macOS e Windows):
  `Time.h` cobria o `<time.h>`, por isso `Timing.h`.
- Comentários e mensagens em português, como no Swift.

## Divisão do trabalho

- **Núcleo (`src/core/`, `tests/`):** agente 04.
- **App, CI e distribuição (`src/app/`, `.github/`, instaladores, `LICENSE`, README):** agente 05.
- Integração na `feature/multiplataforma`: agente 01.

## Compilar e testar

```bash
cmake -S qt -B build/qt -G Ninja -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt
cmake --build build/qt
ctest --test-dir build/qt --output-on-failure
```
