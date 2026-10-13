# Contexto completo da sessão

Este arquivo reúne tudo o que foi feito e descoberto na sessão que deu origem ao
OpenFrame: a engenharia reversa do CapCut com o REA, a configuração do ambiente,
a análise do agente de IA e a construção do editor. Serve para retomar o
trabalho em outra sessão sem perder nada.

**Nome:** o projeto começou como OpenCut e foi renomeado para **OpenFrame**,
porque já existe outro OpenCut. Pastas, alvos, tipos, extensão (`.openframe`),
bundle id (`app.openframe.editor`) e a variável `OPENFRAME_SNAPSHOT_DIR` seguem
o nome novo. Os dois primeiros commits ainda usam o nome antigo.

Data da sessão: 12/10/2026. Máquina: macOS (Darwin 25.6, arm64, 16 GB de RAM),
só com Command Line Tools (sem Xcode), Swift 6.3.3.

---

## 1. Linha do tempo

1. **Pedido inicial:** usar o REA para descompilar `/Applications/CapCut.app` e
   entender como ele funciona.
2. **Análise estática do CapCut** (seção 3): os símbolos não foram removidos do
   binário, e isso revelou a arquitetura inteira.
3. **Instalação do Ghidra** e configuração do REA (seção 2).
4. **Aprofundamento no agente de IA** do CapCut, com 4 funções decompiladas
   (seção 4).
5. **Reconstrução:** um editor próprio, o OpenFrame, com as funcionalidades
   básicas e uma exportação configurável (seções 5 a 9).

---

## 2. Ambiente e configuração

### REA
- Servidor MCP registrado em `~/.claude.json` → `mcpServers.rea`
  (`npx -y rea-agents@6.4.0 mcp`).
- Variáveis adicionadas por mim em `mcpServers.rea.env`:
  - `GHIDRA_INSTALL_DIR=/opt/homebrew/opt/ghidra/libexec`
  - `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
  - `REA_GHIDRA_STARTUP_TIMEOUT_MS=1800000` (30 min; o padrão de 330 s estourava)
- Backup feito antes da alteração: `~/.claude.json.bak-before-ghidra`.
- O servidor só lê a configuração ao reconectar (`/mcp` → reconectar `rea`).
  O usuário já reconectou.
- CLI equivalente: `npx -y rea-agents@6.4.0 <comando>` (`doctor`, `function`,
  `decompile`, `inspect-macho`…). Pelo CLI, cada chamada refaz a análise do
  Ghidra (~4–5 min por binário de 11 MB); pelo MCP, a sessão fica aberta.
- O Ghidra exige uma fatia thin do Mach-O: `lipo -thin arm64 X -output Y`.
- Memória salva: `~/.claude/projects/-Users-talescavalcanti/memory/rea-no-decompiler-provider.md`
  (diz que não havia decompilador; **está desatualizada**, porque agora o Ghidra
  está instalado e configurado).

### Instalado via Homebrew
- `ghidra` 12.1.4 (traz `openjdk@21` 21.0.12.1 e o decompilador nativo
  `mac_arm_64`). `rea doctor` passou nas 8 verificações do Ghidra.

### Limitações do ambiente
- **Sem Xcode:** só Command Line Tools. O SwiftPM compila apps SwiftUI normalmente.
- **Swift Testing** fica em `/Library/Developer/CommandLineTools/Library/Developer/Frameworks`,
  fora do caminho padrão. Por isso `scripts/test.sh` passa `-F` e `-rpath`.
- **Sem `ffmpeg`** e **sem `timeout`** (macOS).
- **Sem permissão de Gravação de Tela nem de Acessibilidade** para o terminal:
  `screencapture` e `osascript`/System Events falham. A solução foi fazer o app
  capturar as próprias janelas (`DebugSnapshot.swift`).

---

## 3. Engenharia reversa do CapCut (achados)

Alvo: CapCut 9.5.0 (build 286), `com.lemon.lvoverseas`, universal
x86_64 + arm64, 2,6 GB, versão da Mac App Store com sandbox, team `22MMUN2RN5`.
Apenas análise estática; nada foi executado.

Evidências REA: Mach-O `ev_71396aa795dc7d2cff2ecf8c2e8b6da002232b06eb9c2dd0d2e16bd87b77252f`,
assinatura `ev_9abfe5e45dda5c9bb85368810a6174a5702db7fb290c66a372851dbde5ac8eab`.

### Estrutura
- `Contents/MacOS/CapCut` (446 KB) é só um **launcher**: importa Qt e 8 funções
  do `libVECreator` (caminhos e versão). Strings `dlopen`/`dlsym`, `VECreator`,
  `.dylib` e `--time_perf=main:%lld-open:%lld-find_sym:%lld-call_entry:%lld`.
  O `libVECreator` exporta `_entryPoint`. Inferência: o launcher carrega a
  biblioteca, acha `_entryPoint` e chama.
- **`libVECreator.dylib` (1,1 GB)** é o núcleo do app, **sem símbolos
  removidos**: ~1,6 milhão de símbolos locais e 1.665 caminhos de fonte
  (`/Users/iOS_ttp_2_7_v_ielza/81067/CapCutPC/...`).
- Interface: Qt 6.2.2 + QML (MVVM com centenas de `*ViewModel`), Lynx (telas
  web da ByteDance) e Chromium Embedded Framework (CEF).
- Edição: `libvideoeditor` (namespace `lvve`, `draft_store`, clientes
  Video/Text/Audio). Renderização: `libcccreator` (`vesdk`, `AmazingEngine`)
  e `libAGFX` (Metal/GLSL/SPIR-V).
- IA local: `liblens`, `libbytenn` e 187 MB em `Resources/models` (matting,
  rosto, cabelo, profundidade, detecção de cortes, interpolação, marca d'água
  invisível).
- Rede: `libsscronet` (Cronet/TTNet). Telemetria: `libTracking` e
  `libIESAppLogger`. Proveniência: `libtt_c2pa_sdk` (C2PA).
- Processos auxiliares: `CapCut Helper` ×4 (CEF), `VEHelper`,
  `VECrashHandler` e um `CapCut.app` aninhado (`--process=tool`).
- Permissões (entitlements): sandbox, JIT, `disable-library-validation`,
  câmera, microfone, rede cliente/servidor.

### Árvore de código `CapCutPC/`
- `BizScene/EditorScene` (716 arquivos): Agent, FunctionPanel, Export,
  TimeLine, MaterialPanel, Player, DigitalHuman, Cover, TextEditor…
- `BizScene/HomeScene`, `BizScene/ToolScene` (AIShorts, ArticleVideo,
  MarketingVideo, AIWriter).
- `Capability/Algorithom` (clipflow_nodes/graphs, aigc, áudio, vídeo),
  `Capability/Editor` (`lyra_shell`, quadros, upgrade de draft, telemetria).
- `GlobalFramework/LaunchTaskScheduler`: inicialização em tarefas (log, rede,
  CEF, QML, sandbox, risco/spam, algoritmos, editor, `show_home_page`).
- `Commerce/VipBiz` e `Purchase` (assinatura).

### Formato do projeto
Cada rascunho é uma pasta com `draft_content.json` (a timeline),
`draft_meta_info.json`, `draft_virtual_store.json`, `draft_content.json.bak`,
`draft_agency_config.json`, `draft_biz_config.json`. A sincronização com a
nuvem usa diferenças (`cloud_draft_content.diff.json`). Os tempos são em
microssegundos. Materiais incluem `transitions`, `speeds`, `canvas_color`,
`canvas_blur`, `audio_fades`, `material_animations`, `video_effects`,
`stickers` e `beats`.

### Exportação (`ExportViewModel`)
Membros: `resolutionList`, `isCustomResolution`, `frameRateList`,
`bitrateList`, `customBitrate`, `isCustomBitrate`, `isVBR`,
`maximumBitrate`, `encoder`, `isProResEncoder`, `formatList`, `colorSpace`,
`isExportAudio`, `getEstimatedInformation`, `calculatedExportFileInformation`,
`exportSubtitleFinished`, `enableHDExport`, `superResolution*`.
Valores: 480p/720p/1080p/2K/4K/8K; 23,976/24/25/29,97/30/50/59,94/60/120 fps.

### Ajustes (`Resources/DefaultAdjustBundle`)
brightness, contrast, saturation, highlight, shadow, sharpen, vignetting, fade,
particle, light_sensation, hsl, black_white, combine_adjust, temperature/tone.

### Servidores
`*.capcutapi.com` (edit-api, feed-api, passport), `www.capcut.com`,
`dreamina.capcut.com`, `lumi-studio.byteintlapi.com`, `*.tiktokcdn.com`,
`*.bytevcloudapi.com`.

---

## 4. Agente de IA do CapCut

### Arquitetura
```
Processo principal (libVECreator)                 Processo do agente (DeepAgentsService)
  UI do chat (QML), AgentChannelRouter     Mojo IPC   libDeepAgentsService (C++, ponte)
    ├─ LocalAgentChannel  ─────────────────────────►    └─ abre libdeepagents_capi.dylib
    └─ NuroAgentChannel (socket → servidor)                (Go 1.25.11 + Eino, 112 MB)
  ContextManager (timeline → Markdown/JSON)
  ToolCallService (60 ferramentas de edição)
  ExecutionGateHostImpl (aprovação do plano)
  BrowserDeepAgentHostBridge::ModelGenerate
```

- **`libdeepagents_capi`** é escrito em **Go** (c-shared). Os nomes das funções
  vêm da `pclntab`. Módulo próprio: `code.byted.org/cc-family-infra/carrier-agent-sdk/deepagents`.
  Dependências: `cloudwego/eino` (framework de agentes LLM da ByteDance),
  `stone_llm_gateway`, `volcengine-go-sdk`, `kitex`/`hertz`, `fornax_sdk`,
  `cozeloop-go`, `gonja` (templates Jinja), fork do `go-openai`.
- **Middlewares do SDK:** Planning (`write_todos`), SubAgent, Summarization,
  Memory, Skill (`activate_skill`, `SKILL.md`), Filesystem, Web, RepairJSON,
  PatchToolCalls.
- **Backends:** State, Filesystem, Sandbox.
- **Persistência:** SQLite via GORM (`agentthread.db`, `deepagent.db`) com chave
  derivada (`DeriveDBCipherKeyHex`) e retenção.
- **Rastreamento:** Fornax/CozeLoop. **RAG:** Volcano knowledge base.
- **Interfaces Mojo:** `DeepAgentService` (CreateAgent, CreateAgentWithHosts,
  RetrieveDeeplinks, Shutdown), `DeepAgent` (CreateSession, ExecuteSubagent,
  conversas), `DeepAgentSession` (Run/Stream/TokenStream/Abort/RewriteHistory/
  SetPromptInjections/SetThinkingOverride…), e os hosts que o processo
  principal implementa: `DeepAgentModelHost::ModelGenerate`,
  `DeepAgentToolHost::CallToolAsync/ListTools/ListToolsScoped`,
  `DeepAgentExecutionGateHost::HandleGateCheck`, `DeepAgentEventHost`,
  `DeepAgentFornaxTraceHost`, `DeepAgentToolCallContextHost`.
- **60 ferramentas** em `EditorScene/Agent/.../*_tool.cpp`, por exemplo:
  read_timeline, ripple_delete, ripple_move, remove_filler_word,
  subtitle_recognize, subtitle_translation, ai_generate_video/image,
  smart_highlight, audio_denoise, voice_separation, video_anti_shake,
  object_tracking, update_text_style, query_draft_content, player_seek…
- **API do servidor:** `/agent_edit_api/` com plan_generation,
  rough_cut_plan_generation, run_draft_modify_intent, run_model_classify,
  run_model_gate, query_skills, retrieve_tools, retrieve_deeplinks,
  copywriting, answer_faq, talking_head_script_generation, link_extract/pc,
  search/douyin e commerce/batch_precharge e report_usage (cobrança de créditos).
- **Prompts:** os específicos do CapCut não estão no binário, só os genéricos do
  SDK. Inferência: vêm do servidor (`GetPromptByKey`, `prompt_version`,
  `prompt_platform`).
- **ContextManager:** `getDraftMarkdownContext`, `getMiniDraftJsonContext`,
  `computeTimelineChangeSummary`. O modelo não vê o draft bruto.
- **Aprovação humana:** gates em `handleBeforeModelRequest`,
  `handleAfterModelOutputBeforeToolBatch` e `handleBeforeFinalModelOutput`;
  `onPlanReady`/`resumePlanGate`.

### Funções decompiladas (Ghidra via CLI do REA, `libDeepAgentsService` arm64)
| Função | Evidência | O que mostra |
|---|---|---|
| `_entryPoint` | `ev_18591d52075940367030c8214178e841e5479243ed1285a9cb688bb66e5a775f` | Init: QSettings, ByteLog, MMKV, settings, foundation, TTNet, `ConfigureDeepAgentsLoader`, chromium base, crash dumper, `RegisterService`, loop do Qt |
| `deepagents::shell::ConfigureDeepAgentsLoader` | `ev_da7be8d4d12f162764e77581ecce9225f041efed12aa296912805dfc080e0514` | Monta `<dir>/libdeepagents_capi.dylib` e chama `da_loader_configure` |
| `ToolHostRemoteAdapter::CallToolAsync` | `ev_769e5033199b76151981ad8d6b0fe9f877d2a4321d463eb651c6a15877882489` | Passa para a thread dona e envia por Mojo com um canal de retorno `ToolCallContextHost` |
| `HostBridgeHttpTransport::start_sscronet_request` | `ev_2de4f56d34c1c72442a2e8015ee07b68124d9f5982baadaa3d18aceb6c283bc6` | O HTTP do Go passa pelo TTNet/Cronet em C++ (URL, método, cabeçalhos, corpo, timeout) |

O pseudocódigo ficou em arquivos temporários da sessão
(`/private/tmp/claude-501/.../scratchpad/decompiled/`), que podem ser
apagados. Por ser código decompilado de software proprietário, não foi
copiado para este repositório.

### Pendências da análise
- Qual modelo responde e onde: `BrowserDeepAgentHostBridge::ModelGenerate` está
  dentro dos 1,1 GB do `libVECreator`, que não foram decompilados (horas de
  Ghidra e pesado para 16 GB de RAM).
- Divisão entre canal local e Nuro: lógica do `AgentChannelRouter` não lida.

---

## 5. OpenFrame: decisões do usuário

- **Stack:** Swift + AVFoundation (app nativo de macOS).
- **Escopo:** núcleo de edição, texto e legendas, áudio e transições. Ênfase em
  **exportação configurável** (tamanho, dimensões, qualidade, bitrate, fps) e
  "alguns outros efeitos do CapCut".
- **Compatibilidade com draft do CapCut:** não foi pedida.
- **Local:** `~/Desktop/opencut`.
- **Regra:** reconstrução de comportamento, sem copiar código, bibliotecas,
  modelos ou recursos da ByteDance.

---

## 6. OpenFrame: arquitetura

```
Package.swift            swift-tools 6.0, macOS 14, modo de linguagem Swift 5
Sources/OpenFrameCore/
  Model/Time.swift         Micros (Int64, µs), TimeRange, Time.format
  Model/Effects.swift      RGBA, Transform, Adjust, FilterPreset, VideoEffect,
                           SegmentAnimation, Transition, TextStyle, TextContent
  Model/Project.swift      Material, Segment, Track, AspectRatio, CanvasBackground,
                           Canvas, Project (aspectValue, canvasSize)
  Model/ProjectStore.swift JSON .openframe
  Timeline/TimelineEditor.swift  operações puras (addMedia/Overlay/Text, split,
                           delete, duplicate, move, reorderMain, resolveOverlap,
                           moveToTrack, trimStart/End, setSpeed, update, snap)
  Media/MediaProbe.swift   lê vídeo/foto/áudio → Material
  Media/Subtitles.swift    SRT parse/serialize/import/cues
  Render/ImageEffects.swift ajustes, filtros, efeitos, geometria de efeitos
  Render/Motion.swift      Animations (entrada/saída), Transitions
  Render/TextRenderer.swift Core Text → CIImage com cache
  Render/FrameRenderer.swift RenderPlan, PlanBox, render de um quadro
  Render/Compositor.swift  OpenFrameInstruction + OpenFrameCompositor (AVVideoCompositing)
  Render/CompositionBuilder.swift AVMutableComposition, faixas A/B, filler,
                           mix de áudio, StructureKey, FillerClip
  Render/EffectPreview.swift miniaturas de filtros
  Export/ExportSettings.swift resolução, fps, codec, formato, bitrate, estimativa,
                           validação, settings de AVAssetWriter
  Export/Exporter.swift    AVAssetReader → AVAssetWriter, progresso, cancelamento
Sources/OpenFrame/
  OpenFrameApp.swift         WindowGroup + menus (Arquivo, Desfazer, Clipe, Reprodução)
  EditorModel.swift        estado @Observable, undo por snapshot, gestos, preview,
                           importação, arquivos, monitor de teclado
  DebugSnapshot.swift      OPENFRAME_SNAPSHOT_DIR: captura as próprias janelas
  Views/Theme.swift        cores, ParamSlider, SectionHeader, typealias Material
  Views/ContentView.swift  layout + TopBar
  Views/MediaBinView.swift biblioteca de mídia
  Views/PreviewPanel.swift AVPlayerLayer + transporte
  Views/TimelineView.swift régua, faixas, segmentos, aparar, transições
  Views/InspectorView.swift abas Básico/Ajustar/Filtros/Efeitos/Animação/
                           Transição/Texto/Áudio + inspetor do projeto
  Views/ExportSheet.swift  janela de exportação
Tests/OpenFrameCoreTests/    TestMedia (gerador sintético), Timeline, Model,
                           Render, Export — 44 testes
scripts/                   test.sh, make-app.sh, make-demo.sh, demo/main.swift
docs/REFERENCIA-REA.md     CapCut (evidência) → OpenFrame (decisão)
README.md
```

### Mecanismos principais
- **Projeto como valor:** cada edição gera uma nova versão; desfazer é voltar à
  anterior (até 300 passos). Sliders agrupam alterações via `coalesce` (janela
  de 1 s). Gestos registram o desfazer uma vez, ao soltar (`gestureBase`).
- **Faixa principal magnética:** `relayoutMain` encosta os clipes; a transição
  sobrepõe o fim do clipe ao início do próximo
  (`min(duração, metade de cada clipe)`).
- **Composição:** cada faixa de vídeo vira faixas A/B na composição, para que
  clipes sobrepostos na transição sejam decodificados juntos. Uma faixa preta de
  preenchimento (`FillerClip`, 64×64, 1 s escalado) cobre toda a timeline, para
  o compositor rodar também em trechos só com foto ou texto. Vãos viram
  `insertEmptyTimeRange` explícito. A velocidade usa `scaleTimeRange`.
- **Compositor único:** o mesmo `OpenFrameCompositor` serve ao preview
  (`AVPlayer`) e à exportação (`AVAssetReaderVideoCompositionOutput`). Uma
  instrução cobre a timeline inteira e carrega um `PlanBox`.
- **Preview responsivo:** se a `StructureKey` (tempos, mídia, velocidade, volume,
  fades) não mudou, só atualiza o `PlanBox` e força o redesenho (recópia do
  `videoComposition` + seek). Senão, remonta a composição com debounce de
  40 ms. O seek é "perseguido", guardando só o pedido mais recente.
- **Render de um quadro:** fundo (preto, cor ou desfoque do clipe principal) →
  faixas de vídeo (orientação → ajustes → filtro → efeitos → encaixe "fit" ×
  transform × animação × geometria de efeito → opacidade; transição quando dois
  segmentos se sobrepõem) → textos.
- **Orientação** de vídeos em pé: a `preferredTransform` é mapeada para
  `CGImagePropertyOrientation` e aplicada com `.oriented()`.
- **Áudio:** `AVMutableAudioMixInputParameters` com volume, rampas de fade,
  crossfade nas transições da faixa principal e `audioTimePitchAlgorithm = .spectral`.
- **Exportação:** bitrate = pixels × fps × bits por pixel (H.264 0,1;
  HEVC 0,065; ProRes ~2,36 só para estimativa) × 0,55 / 1 / 1,8, ou Mbps
  personalizado, ou tamanho alvo (MB × 8e6 / duração − áudio). Limites: 100 kbps
  a 800 Mbps. Validação: H.264 até 4096 px no lado maior; ProRes só em MOV.
  Cor Rec.709. Leitor e gravador alimentam vídeo e áudio em filas paralelas.

---

## 7. OpenFrame: verificação

- `./scripts/test.sh` → **44 testes passando**, em 6 suítes: Timeline (15),
  Legendas (3), Projeto (2), Configurações de exportação (6), Renderização (11),
  Exportação (7).
- Os testes de exportação geram arquivos reais e conferem dimensões, fps, codec
  (HEVC, H.264, ProRes), duração, áudio a 48 kHz estéreo, progresso monotônico,
  conteúdo renderizado no arquivo, M4A sem vídeo, cancelamento que apaga o
  arquivo parcial e recusa de configurações inválidas.
- Interface conferida por capturas do próprio app (`DebugSnapshot`) e por um
  quadro extraído do `AVPlayerItemVideoOutput` (o preview renderiza).
- Demo exportado: `~/Desktop/OpenFrame Demo/Demo.mp4`, 1920×1080, 30 fps,
  ~10,9 s, renderizado em 1,8 s. Quadros conferidos: deslizar, dissolver,
  sobreposição, legenda e vinheta.
- **Não verificado por mim:** interações reais de mouse e teclado (arrastar,
  aparar, scrub, atalhos), porque faltam permissões de acessibilidade e de tela.
  A lógica está coberta pelos testes do `TimelineEditor`.

### Bugs encontrados e corrigidos
1. **Temperatura invertida:** `CITemperatureAndTint` exige um `inputTargetNeutral`
   menor para esquentar → `6500 - t*2500`.
2. **Glitch RGB vermelho:** canais G e B tinham alfa 0, e com pré-multiplicação a
   cor zerava → todos os canais com alfa 1.
3. **Testes travando:** o `AVAssetWriter` intercala trilhas e trava se o vídeo
   for escrito inteiro antes do áudio → `requestMediaDataWhenReady` em filas
   separadas (o `Exporter` já fazia isso).
4. **Conflito de nome `Material`:** o SwiftUI do macOS 26 também declara um →
   `typealias Material = OpenFrameCore.Material` no alvo do app.
5. **Janela não abria com arquivo no argv:** o AppKit trata caminhos soltos como
   documentos, e a cena `Window` não recebe eventos externos → `WindowGroup` +
   `.handlesExternalEvents(preferring: ["*"], allowing: ["*"])`, e a flag
   `-open caminho` lida via `UserDefaults`.
6. **Controles do preview cortados:** larguras fixas → `ZStack` com tempo à
   esquerda e transporte centralizado.

---

## 8. Como usar

```bash
cd ~/Desktop/opencut
./scripts/make-app.sh              # build/OpenFrame.app (release, assinatura ad-hoc)
open build/OpenFrame.app
swift run OpenFrame                  # modo debug
./scripts/test.sh                  # testes
./scripts/make-demo.sh [pasta] [--export]   # ~/Desktop/OpenFrame Demo
.build/debug/OpenFrame -open "~/Desktop/OpenFrame Demo/Demo.openframe"
OPENFRAME_SNAPSHOT_DIR=/tmp/snaps .build/debug/OpenFrame -open projeto.openframe
```
O modo de captura não fecha sozinho se a janela de exportação estiver aberta;
encerre com `pkill -f debug/OpenFrame`.

Git: repositório local em `~/Desktop/opencut`, sem remoto.
- `394d7db` Núcleo (ainda como OpenCut)
- `bec66a2` App SwiftUI, demo, empacotamento e documentação
- A renomeação para OpenFrame e este `CONTEXTO.md` ainda não foram commitados.

---

## 9. Pendências e próximos passos sugeridos

**OpenFrame**
- Teste manual das interações: arrastar entre faixas, aparar, scrub, atalhos,
  importar arrastando arquivos.
- Rolagem automática da timeline durante a reprodução.
- Forma de onda nas faixas de áudio.
- Volume acima de 100% (exigiria processamento de áudio próprio, já que o
  `AVAudioMix` limita a 1,0).
- Ícone do app; exportação em GIF (o CapCut tem `GifExportViewModel`).
- Leitura e gravação do `draft_content.json` do CapCut (exigiria levantar o
  schema; não foi pedida).
- Aviso remanescente de compilação: `NSEvent` não é `Sendable` no monitor de
  teclado (`EditorModel.installKeyMonitor`), inofensivo no modo Swift 5.

**Análise do CapCut**
- Decompilar `BrowserDeepAgentHostBridge::ModelGenerate` para descobrir qual
  modelo responde.
- Ler o `AgentChannelRouter` (divisão entre canal local e Nuro).
- Atualizar a memória `rea-no-decompiler-provider.md`: o Ghidra agora está
  configurado.
