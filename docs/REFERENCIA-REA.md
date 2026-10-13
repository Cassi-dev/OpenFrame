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

## Texto: modelo, painel e faixas de valores

**Como foi levantado.** O `libVECreator.dylib` (1,1 GB) não foi aberto no Ghidra.
A análise com o REA (Ghidra 12.1.4) usou a fatia arm64 do `liblyra_cli_client.dylib`
(19 MB no pacote, 9 MB na fatia, SHA-256 `1774e550…fee7f7dc`). Essa biblioteca é a
ferramenta de linha de comando que edita drafts e valida os campos de texto com
mensagens que dizem as faixas aceitas. Os nomes do painel e do draft foram
conferidos por fora do REA, com `nm`/`c++filt` e `strings` no `libVECreator` e
no `libvideoeditor`, no template `Resources/article_video/text_to_video_template.json`
e num rascunho que o próprio CapCut salvou nesta máquina (`draft_info.json`, só os
valores do material de texto).

| Evidência | O que mostra |
|---|---|
| REA `ev_908bc7c0…` | Patches `text_shadow` (`shadow_color/alpha/angle/distance/diffuse/enable`), `text_spacing` (`letter_spacing`, `line_spacing`), `text_underline`, `text_bold_italic`, `text_alignment` (`left/center/right/top/bottom`), `text_typesetting` (`horizontal/vertical`) |
| REA `ev_4d3852f0…` | `stroke.line_join` round/bevel/miter; `background_style` square/wrap; alfa em [0, 1]; `font_size` de 0 a 1000; raio e alfa do fundo em % |
| REA `ev_914742d5…` | Espaçamento entre letras e entre linhas em [-0,5, 5]; ângulo da sombra em [-180, 180]; distância em [0, 100]; difusão em [0, 0,1666]; `underline_width`/`underline_offset`; brilho (`glow_*`) |
| REA `ev_ac48e1af…` | Contorno como fração (ex.: 0,08); largura e altura do fundo como escala normalizada |
| `nm` no `libVECreator` | `TextEditSettingViewModel`/`TCTextPropertySettingViewModel`: `letterSpacing`, `lineSpacing`, `border*`, `frame*` (fundo: cor, alfa, `frameCircleAngle`, largura, altura, deslocamentos), `shadow*` (cor, alfa, `shadowSmoothing`, distância, ângulo), `hasUnderline`, `setTextCase`, `typeSetting`, `globalAlpha`/`textAlpha`, `curve*`, `light*`, `resetShadowToDefault` |
| draft salvo pelo CapCut | Padrões: `letter_spacing` 0, `line_spacing` 0,02, `shadow_alpha` 0,9, `shadow_angle` -45, `shadow_distance` 5, `shadow_smoothing` 0,45, `background_round_radius` 0, `background_width/height` 0,14, `underline_width` 0,05, `underline_offset` 0,22, `line_max_width` 0,82, `border_width` ≈ 0,032 |

| CapCut (observado) | OpenFrame (`TextStyle`, `TextRenderer`) |
|---|---|
| `letter_spacing`, `line_spacing` relativos ao tamanho | `letterSpacing`, `lineSpacing` em em; sliders de -0,5 a 2 e de -0,5 a 3 (o CapCut aceita até 5) |
| `border_width` + `border_color`; `line_join` arredondado | Contorno desenhado por fora da letra, a partir dos contornos dos glifos, com junção e ponta arredondadas; espessura até 20 % do tamanho |
| `shadow_color`, `shadow_alpha`, `shadow_angle`, `shadow_distance`, `shadow_smoothing` | `shadowColor` (o alfa é a opacidade), `shadowAngle` (graus, 0 = direita, -90 = baixo), `shadowDistance` e `shadowBlur` em em; uma sombra só para letras + contorno + sublinhado |
| Fundo: cor, alfa, raio, largura/altura | `backgroundColor` (alfa = opacidade), `backgroundRadius`, `backgroundPaddingX/Y` em em |
| `underline`, `underline_width` 0,05, `underline_offset` 0,22 | `underline`, com espessura de 0,05 em logo abaixo da linha de base |
| `text_alpha` / `global_alpha` | `opacity` do texto inteiro |
| `setTextCase` | `textCase`: normal, MAIÚSCULAS, minúsculas, Título |
| `bold_width`, `italic_degree` (negrito e itálico sintéticos) | Negrito e itálico da família; se ela não tiver, negrito sintético (traço de 0,03 em) e itálico sintético (12°) |
| `font_path` / `font_id`, fontes do catálogo online | Qualquer família instalada (`FontCatalog`) e o estilo dentro dela (`fontFace`: Light, Medium…) |

Projetos antigos abrem com os campos novos no padrão (`decodeIfPresent`). Os padrões
reproduzem o desenho anterior (sombra para baixo, desfoque de 0,15 em, opacidade 0,65;
fundo com raio de 0,18 em e margem de 0,21 em). Por isso, alguns diferem dos do CapCut.

**Ficou de fora:** texto curvo (`curve*`), brilho (`light*`/`glow_*`, que depende de
recursos baixados), texto vertical (`typesetting`), fundo "wrap" por linha
(`background_style` 2), estilos por trecho (rich text com `range`), modelos de texto
e efeitos de texto ("flower"), que são recursos da ByteDance.

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
- Unidades exatas do texto no CapCut: a evidência dá faixas e padrões, mas não diz
  se `shadow_distance` (0–100) e `border_width` são relativos ao tamanho da fonte ou
  ao canvas, nem como `shadow_smoothing` vira desfoque. As funções do
  `libVECreator` que aplicam esses valores não foram decompiladas. O OpenFrame usa
  frações do tamanho da fonte em tudo.
