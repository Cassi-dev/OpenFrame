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
| `ProjectStore.h` | `encode/decode/save/load`, `toJson/fromJson`, `uuidString`, `fileExtension`; JSON igual ao do Swift, com os campos de motion e legendas (ver abaixo); tipo de animação desconhecido (versão futura) abre como `fade` e loop desconhecido é descartado |
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
Rotação da trilha e EXIF já aplicados nos quadros. Vídeo HDR (BT.2100 HLG ou PQ,
como os do iPhone) sai convertido para SDR como o macOS mostra (ver
`ToneMap.h`); cinzas a até 3 níveis do macOS, cores comuns a até 12.

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

## Motion e legendas, etapa 1: modelo, JSON, geometria, edição e montagem das legendas

Porte do que entrou no Mac depois da v0.5.0, com os mesmos nomes e números do núcleo Swift. O render novo
(animações por unidade, loops, revelações, ênfase desenhada por palavra) vem na etapa 2; a transcrição real, na 3.

| Cabeçalho | O que tem |
|---|---|
| `Color.h` | `RGBA` (saiu do `Effects.h`, que continua incluindo) |
| `Captions.h` | `CaptionWord{text,start,end}` (relativo ao segmento), `HighlightMode` (current/progressive), `WordReveal` (none/rise/dim/fill/type, com `displayName`), `WordHighlight{color,scale,backgroundEnabled,backgroundColor,mode,reveal,dimOpacity}`, `WordEmphasis{words,fontName,fontFace,scale,color?}`, `TranscribedWord{text,start,end,probability}` (tempos da timeline) |
| `Effects.h` | `AnimationKind` com os 17 tipos (`isTextOnly`), `LoopKind`/`LoopAnimation{kind,period,intensity}`, `TextStyle::balanceLines/fitLines` e `maxWidthMin/maxWidthMax` (0,1…3), `TextContent::words/highlight/emphasis` (opcionais), `TextContent::wordsOf(text)` (separa por espaço, inclusive U+00A0 e `\n`) e `activeHighlight()` (vazio se a contagem não bate). `TextContent(text, style = {})` tem construtor |
| `Project.h` | `Segment::animationLoop`, `Track::isAutoCaptions` |
| `ProjectStore.h` | grava e lê tudo isso como o Swift: `animationLoop`, `words`, `highlight`, `emphasis` e `isAutoCaptions` só quando existem (`isAutoCaptions` só quando verdadeiro), `balanceLines`/`fitLines` sempre. No destaque e na ênfase, campo ausente fica com o padrão e `mode`/`reveal` desconhecido vira o padrão |
| `CanvasLayout.h` | `ElementBox{id,isText,center:QPointF,size:QSizeF,scale,rotation}`; `CanvasLayout::boxes(project, t)` (vídeo/foto das faixas visíveis, depois os textos), `fitSize`, `hitTest(point, boxes, aspect) -> optional<QUuid>`, `corners(box, aspect) -> QList<QPointF>` (sup. esq., sup. dir., inf. dir., inf. esq.), `bounds(box, aspect) -> QRectF` (y para cima: `top()` é o menor y); `SnapGuide{axis,position,kind}`; `Snapping::snapMove(box, proposed, others, aspect, threshold:QSizeF) -> MoveResult{center, guides}`, `Snapping::snapRotation(degrees, threshold = 4) -> RotationResult{degrees, snapped}`, `Snapping::safeMargin` (0,9). Coordenadas normalizadas (-1…1, y para cima) |
| `TimelineEditor.h` | `setPlacement(p, id, center:QPointF, scale, rotation)` (estilo no texto, `transform` no visual; escala mínima 0,01), `setTextWidth(p, id, maxWidth)` (limitada a 0,1…3, ignora NaN/infinito; numa faixa automática vale para todos os textos dela). `freeTrack` pula a faixa automática; `split` e `trimStart` mantêm as palavras no mesmo instante da timeline |
| `TextRenderer.h` | `boxSize(content, canvas) -> optional<QSizeF>` (caixa do texto + fundo, com palavra-chave, `fitLines` e `balanceLines`; bate com o Swift a até 2 px), `lineWidth(text, style, fontPx)`, `lineTexts(content, canvas)`. A imagem estática já usa o mesmo layout (palavra-chave na fonte e na cor dela, linhas ajustadas e equilibradas) |
| `CaptionPresets.h` | `CaptionLayout` (phrases/highlight/punch/stacked), `CaptionPresetGroup`, `CaptionPreset` (os 10 visuais) com `displayName`, `detail`, `group`, `layout`, `usesAccent`; `presetFor(layout)` |
| `CaptionBuilder.h` | `CaptionCue{text,start,end,words}`; `CaptionBuilder::cues(words, preset, aspect = 16/9)` e `cues(words, layout, aspect)`; `apply(cues, preset, accent?, project, replacing, range?) -> QUuid` e `apply(cues, layout, style?, ...)`; `defaultStyle(preset)` e `defaultStyle(preset, aspect)`; `keywords(cue)`, `highlight`, `emphasis`, `animate`, `normalized`, `limits`, `Measure`; constantes `glue` (U+00A0), `minDuration`, `closeGap`, `pause`, `forcedBreak`. Mede com o `TextRenderer`: precisa de `QGuiApplication` |
| `WhisperModels.h` | `WhisperModel` (base/small/turbo) com `displayName` ("Rápido", "Equilibrado", "Máxima precisão"), `fileName`, `byteSize`, `downloadUrl`, `sha256`; `recommendedModel()` = small (só CPU nesta versão). `ModelStore` (QObject): `shared()`, `defaultDirectory()` (`AppLocalDataLocation/Models` ou `OPENFRAME_MODELS_DIR`), `path`, `isInstalled`, `remove`, `download`/`cancel`/`isDownloading` com os sinais `downloadProgress(model, fraction)` e `downloadFinished(model, ok, error)` |
| `Transcriber.h` | `TranscriptionProgress{phase,fraction,overall}` (`make`; a mistura pesa 10%), `TranscriptionSource` (`timeline()`, `of(id)`), `TranscriptionError` e `message(...)`; `Transcriber` (QObject, como o `Exporter`): `start(project, source, model, language = "")`, `cancel()`, `isRunning()`, sinais `progress(TranscriptionProgress)` e `finished(ok, words, error)` (cancelado = ok falso e erro vazio); estáticos `sourceRange`, `mixProject`, `languages()`, `fakeWords(range)` |

Provisório nesta etapa:
- `Animations::state`: o foco esmaece crescendo de 1,08 a 1; as 7 animações por letra/palavra/linha esmaecem o
  texto inteiro; os loops ainda não aparecem no render.
- `ModelStore::download` termina com o erro "O download dos modelos ainda não está disponível nesta versão.".
- `Transcriber`: com `OPENFRAME_FAKE_TRANSCRIPTION=1`, palavras falsas pelo trecho (~0,8 s de progresso falso);
  sem ela, "modelo não instalado" ou "motor indisponível".
- Diferença do Swift que fica: sem o etiquetador gramatical do macOS, a palavra-chave é escolhida pelo tamanho, pelo
  fim de frase, pelas listas de palavras funcionais e fracas, e os advérbios em "-mente" perdem peso; no empate, a
  mais adiante. Em textos comuns, escolhe o mesmo substantivo longo que o Mac; pode divergir quando um verbo e um
  substantivo têm o mesmo tamanho.
- Fontes: as do Mac (Helvetica Neue, Menlo, Didot, Condensed Black) caem para a Inter fora do Mac; o mapeamento
  para fontes distribuíveis entra na etapa 2.
