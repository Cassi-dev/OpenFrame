# Referência: o que o REA revelou do CapCut e onde isso está no OpenFrame

Alvo analisado: `/Applications/CapCut.app` — CapCut 9.5.0 (build 286) para Mac,
`com.lemon.lvoverseas`, universal (x86_64 + arm64). Análise estática apenas;
nenhuma execução do CapCut foi observada. As evidências do REA estão
identificadas pelos IDs registrados na sessão de análise.

## Regra de reconstrução

O OpenFrame reimplementa **comportamentos** observados, não código. Nada foi
copiado do binário, das bibliotecas (`libVECreator`, `libvideoeditor`,
`libcccreator`…), dos modelos de IA ou dos recursos (fontes, efeitos, ícones).

## Arquitetura do CapCut (evidência) → decisão no OpenFrame

| CapCut (observado) | Evidência | OpenFrame |
|---|---|---|
| Launcher fino que carrega `libVECreator.dylib` e chama `_entryPoint` | `inspect_macho` `ev_71396aa7…`; strings `dlopen`/`dlsym` | App SwiftUI único; núcleo separado em `OpenFrameCore` |
| Interface em Qt 6.2.2 + QML, padrão MVVM (`*ViewModel`) | dependências Mach-O; símbolos | SwiftUI + `@Observable` (`EditorModel`) |
| Projeto em pasta com `draft_content.json`, `draft_meta_info.json` | strings do `libVECreator` | `Project` em JSON (`.openframe`), mesma divisão materiais/faixas/segmentos |
| Tempos do draft em microssegundos (`start`/`duration`) | formato do draft | `Micros` (`Int64`) e `TimeRange` |
| Materiais: `transitions`, `speeds`, `canvas_color`, `canvas_blur`, `audio_fades`, `material_animations`, `video_effects` | strings | `Transition`, `speed`, `CanvasBackground.color/.blur`, `fadeIn/fadeOut`, `SegmentAnimation`, `VideoEffect` |
| Faixa principal magnética e sobreposições | símbolos `MainTimeLine*`, `TimeLine` | `Track.isMain` + `TimelineEditor.relayoutMain` |
| Painel "Ajustar" (`brightness`, `contrast`, `saturation`, `highlight`, `shadow`, `sharpen`, `vignetting`, `fade`, `particle`, `temperature`, `tone`) | `Resources/DefaultAdjustBundle`, strings | `Adjust` + `ImageEffects.adjust` |
| Motor de render próprio (`vesdk`, `AmazingEngine`, `libAGFX`) | símbolos de `libcccreator`/`libAGFX` | Core Image + compositor AVFoundation |
| Fila de inicialização (`LaunchTaskScheduler`: rede, CEF, QML, algoritmos, editor) | caminhos de fonte embutidos | Inicialização simples no `EditorModel` |

## Exportação (o foco pedido) — `ExportViewModel`

Membros encontrados no `libVECreator` (`ExportViewModel::…`):
`resolutionList`, `isCustomResolution`, `frameRateList`, `bitrateList`,
`customBitrate`, `isCustomBitrate`, `isVBR`, `maximumBitrate`, `encoder`,
`isProResEncoder`, `formatList`, `colorSpace`, `isExportAudio`,
`getEstimatedInformation`, `calculatedExportFileInformation`, `exportSubtitleFinished`.

Valores presentes nas strings: `480p`, `720p`, `1080p`, `2K`, `4K`, `8K`;
`23.976`/`24`/`25`/`29.97`/`30`/`50`/`59.94`/`60`/`120 fps`.

| CapCut | OpenFrame (`ExportSettings`) |
|---|---|
| `resolutionList` + `isCustomResolution` | `ResolutionPreset` (480p…8K) + `.custom` (largura × altura) |
| `frameRateList` | `FrameRate` com durações exatas NTSC (1001/30000 etc.) |
| `bitrateList` (mais baixa / recomendada / mais alta) + `customBitrate` | `BitrateMode` `.lower/.recommended/.higher/.custom` |
| `getEstimatedInformation` | `estimatedBytes(for:)` e modo `.targetSize` (bitrate a partir do tamanho desejado) |
| `encoder`, `isProResEncoder`, aviso de HEVC | `VideoCodec` H.264 / HEVC / ProRes 422 + `validationError` (8K exige HEVC/ProRes; ProRes exige MOV) |
| `formatList` | `ContainerFormat` MP4 / MOV / M4A |
| `isExportAudio` / `AudioExportViewModel` | `audioEnabled`, `audioKbps`, `audioSampleRate`; exportação só de áudio em M4A |
| `exportSubtitleFinished` | Exportar legendas SRT |

## Fora do escopo

- **Agente de IA** (`libdeepagents_capi`, runtime Go com Eino, 60 ferramentas de
  edição, API `/agent_edit_api/*`): depende de serviços da ByteDance.
- **Recursos de IA locais** (`Resources/models`: recorte, rosto, cabelo, detecção
  de cortes, interpolação): modelos proprietários.
- **Telemetria, nuvem, assinaturas e compras** (`libTracking`, `draft_cloud`,
  `Commerce/VipBiz`).
- **Marca d'água invisível e C2PA** (`invisible_watermark`, `libtt_c2pa_sdk`).

## Incógnitas que não afetaram a reconstrução

- As fórmulas exatas de bitrate do CapCut (`calcBitrate`) não foram decompiladas;
  o OpenFrame usa bits por pixel por quadro (H.264 0,1; HEVC 0,065) multiplicados
  por 0,55 / 1 / 1,8 para os três níveis.
- A curva de cada ajuste e filtro do CapCut não é conhecida; os do OpenFrame são
  equivalentes visuais aproximados, implementados com filtros do Core Image.
