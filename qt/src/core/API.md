# API do núcleo (`openframe_core`)

Índice para quem usa o núcleo (app QML, CI). Os detalhes ficam nos cabeçalhos.
Tudo no namespace `of`; tempo em `Micros` (microssegundos, `qint64`).

## Etapa 1: modelo e edição

| Cabeçalho | O que tem |
|---|---|
| `Timing.h` | `Micros`, `Time::second/seconds()/toSeconds()/round()/format()`, `TimeRange` |
| `Enums.h` | `enumKey(e)` / `enumFromKey<E>(s)` (o `rawValue` do JSON), `allCases<E>()` para menus |
| `Effects.h` | `RGBA`, `Transform`, `Adjust`, `FilterPreset`/`FilterSetting`, `VideoEffect`, `SegmentAnimation`, `Transition`, `TextStyle`, `TextContent`, `displayName(...)` |
| `Project.h` | `Material`, `Segment` (`targetDuration/targetEnd/targetRange`, `Segment::makeText`), `Track`, `AspectRatio` (`label`, `ratio`), `CanvasBackground` (`black()/color()/blur()`), `Canvas`, `Project` (`duration`, `material`, `mainTrackIndex`, `locate`, `segment`, `aspectValue`, `canvasSize`) |
| `ProjectStore.h` | `encode/decode/save/load`, `toJson/fromJson`, `uuidString`, `fileExtension`; JSON igual ao do Swift |
| `TimelineEditor.h` | as operações do Swift sobre `Project&` (`addMedia`, `addOverlay`, `insertMedia`, `addText`, `split`, `remove`, `duplicate`, `move`, `reorderMain`, `resolveOverlap`, `canMove`, `moveToTrack`, `trimStart`, `trimEnd`, `setSpeed`, `update`, `snapPoints`, `snap`, `snapMove`) |
| `Subtitles.h` | `SubtitleCue`, `SRT::parse/serialize/importCues/cues` |
| `ExportSettings.h` | `ResolutionPreset`, `FrameRate` (`frameDuration` racional, `fpsValue`), `VideoCodec`, `ContainerFormat`, `BitrateMode` (todos com `label`), `ExportSettings` (`outputSize`, `videoBitrate`, `estimatedBytes`, `validationError`, `keyframeDistance`), `formattedFileSize` |
| `ProjectLibrary.h` | `ProjectEntry`, `ProjectLibrary` (`list`, `entry`, `create`, `save`, `load`, `rename`, `duplicate`, `remove`, `importProject`, `writeThumbnail`, `nextName`, `defaultRoot`) |
| `FontCatalog.h` | `FontCatalog::families/faces` (precisa de `QGuiApplication`) |

## Etapa 2: mídia (FFmpeg)

| Cabeçalho | O que tem |
|---|---|
| `MediaProbe.h` | `MediaProbe::isSupported/isImageExtension/isAudioExtension`, `MediaProbe::probe(path, QString*) -> optional<Material>` (erros "Formato não suportado: x" e "Não foi possível ler: x"); `Images::load(path, maxSide=0, QString*)`: foto orientada (EXIF), sRGB, pré-multiplicada |
| `VideoDecoder.h` | `VideoDecoder::open(path, QString*) -> unique_ptr`; `frameAt(t, maxSize={})` com busca exata e leitura sequencial, `displaySize`, `duration`, `lastFrameTime`; `DecoderCache(capacity)` com `frame(segmentId, path, t, maxSize)` e `clear()` (thread-safe) |
| `Thumbnails.h` | `Thumbnails::frames(material, count=10, maxSide=240)` |
| `Waveform.h` | `Waveform::peaks(path, perSecond=50, QString*)`: picos normalizados (0…1) |
| `MediaWriter.h` | `MediaWriter::create(path, optional<Video>, optional<Audio>, QString*)`; `writeVideo(QImage, index)`, `writeAudio(interleaved, frames)`, `finish(QString*)`, `abort()`. H.264, HEVC (hvc1), ProRes 422, AAC; contêiner pela extensão (MP4, MOV, M4A) |

Cores: matriz e intervalo do arquivo; sem marca, BT.709 em HD e BT.601 em SD.
Rotação da trilha e EXIF já aplicados nos quadros.

## Etapa 3: render na CPU e texto

| Cabeçalho | O que tem |
|---|---|
| `Renderer.h` | `Renderer::shared().render(project, t, size) -> QImage` (thread-safe; o tamanho define a escala, efeitos usam altura/1080), `clearCaches()`; `EffectPreview::filtered(image, preset)` para as miniaturas da aba de filtros |
| `TextRenderer.h` | `TextRenderer::shared().image(content, canvas, reveal=1)`, `TextRenderer::cased(text, textCase)` (precisa de `QGuiApplication`) |

Para o app:
- `render` não é estático: use `Renderer::shared()` (ou uma instância própria,
  que tem seus próprios caches de decodificadores).
- A saída é sRGB 8 bits opaca (`Format_ARGB32_Premultiplied`).
- Miniatura do projeto: `render` em 1/3 da duração (até 2 s), lado menor 360,
  gravada pelo app com `ProjectLibrary::writeThumbnail`.

Internos (não usar no app): `LinearImage`, `ImageEffects`, `Motion`
(`Animations`, `Transitions`), `FilterModels`.

Diferenças em relação ao Swift:
- Tudo é filtrado e composto em luz linear, como o Core Image; a saída usa a
  curva sRGB (o Swift grava com a 1,961 do macOS).
- Os filtros fotográficos (Mono, Noir, Tonal, Cromo, Desbotado, Instantânea,
  Processo, Transferência, Sépia) são aproximações ajustadas às cores medidas
  no Swift (erro médio de 0,2 a 8 níveis por canal; ver `FilterModels.h`).
- HDR (HLG/PQ) ainda não é convertido para SDR.

## Etapa 4: áudio e reprodução

| Cabeçalho | O que tem |
|---|---|
| `Player.h` | `Player` (QObject, thread principal): `setProject(p)` a cada edição, `setPreviewShortSide(720)`, `play()`, `pause()`, `seek(t)`, `time()`, `duration()`, `isPlaying()`, `setAudioEnabled(bool)`; sinais `frameReady(QImage)`, `timeChanged(Micros)` (~30 Hz tocando, e em `seek`/`pause`), `playingChanged(bool)`, `finished()` |
| `AudioMix.h` | `AudioMix::clips(project)` (o que soa, com as regras do Swift), `AudioMix::gain`, `AudioMixer` (48 kHz estéreo float, `seek`/`read`); base do Player e da exportação |

Para o app:
- `setProject` pode ser chamado a cada mudança: pausado, redesenha o quadro;
  o som só é refeito quando trechos, volume, fades ou velocidade mudam.
- `seek` é perseguido: no scrub, pode chamar à vontade; só o mais recente é
  desenhado depois do quadro em andamento.
- Tocando, a resolução cai sozinha (até 1/3 de `previewShortSide`) se o render
  não acompanhar; pausado, o quadro sai na resolução cheia.
- Ao chegar ao fim: `playingChanged(false)`, `timeChanged(duração)`, último
  quadro e `finished()`. `play()` no fim recomeça do zero.
- O som sai pelo `QAudioSink` (Qt Multimedia) numa thread própria. Sem
  dispositivo de som, toca mudo. Só usa `QAudioSink`/`QMediaDevices`: o
  plugin de mídia FFmpeg do Qt não é necessário.

## Etapa 5: exportação e miniatura

| Cabeçalho | O que tem |
|---|---|
| `Exporter.h` | `Exporter` (QObject): `start(project, settings, path)`, `cancel()`, `isRunning()`; sinais `progress(double)` (0…1, crescente, 1 no fim) e `finished(bool ok, QString error)` |
| `Renderer.h` | `ProjectThumbnail::image(project)` e `ProjectThumbnail::jpeg(project)` (quadro em 1/3 da duração, até 2 s, lado menor 360; JPEG qualidade 80) |

Para o app:
- `start` volta na hora; a exportação roda numa thread própria e os sinais
  chegam na thread do `Exporter`.
- Configuração inválida (`ExportSettings::validationError`) ou M4A sem som
  terminam com `finished(false, mensagem)`. Cancelado: `finished(false, "")`,
  e o arquivo parcial é apagado. Destruir o `Exporter` também cancela.
- Formato do arquivo: H.264 (x264 "medium"), HEVC (x265 "fast", tag hvc1) ou
  ProRes 422 (só MOV), com AAC na taxa escolhida (44,1 ou 48 kHz) e estéreo;
  bitrate, fps e quadros-chave do `ExportSettings`; marcas BT.709; índice no
  começo do arquivo (faststart). O som vai até o fim do vídeo (silêncio depois
  do último trecho).
- Miniatura: `library.writeThumbnail(ProjectThumbnail::jpeg(project), id)`
  depois de salvar (num `QtConcurrent::run`, para não travar a interface).

Convenções:
- Enums são `enum class` em PascalCase (`AspectRatio::R9x16`, `TrackKind::Text`).
- O `throws` do Swift virou `std::optional`/`bool` com `QString *error` opcional.
- `TimelineEditor.delete` do Swift chama-se `remove` (palavra reservada em C++).
- Projeto novo (`Project{}`) já vem com a faixa principal, como no Swift.
