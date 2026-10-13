# OpenCut

Editor de vídeo para macOS inspirado no CapCut, escrito em Swift com SwiftUI,
AVFoundation e Core Image. A arquitetura e o conjunto de funcionalidades foram
levantados por engenharia reversa do CapCut para Mac com o REA (ver
[docs/REFERENCIA-REA.md](docs/REFERENCIA-REA.md)); o código é original — nada do
binário, das bibliotecas ou dos recursos da ByteDance foi reaproveitado.

## Funcionalidades

**Edição**
- Importar vídeos, fotos e áudios (botão ou arrastar e soltar)
- Timeline com faixa principal magnética, sobreposições (picture-in-picture), textos e áudios
- Mover, reordenar, aparar pelas bordas, dividir (⌘B), duplicar (⌘D), apagar (⌫), com ímã
- Velocidade de 0,1× a 10× (áudio com tom preservado)
- Desfazer/refazer ilimitado (⌘Z / ⇧⌘Z)
- Canvas 16:9, 9:16, 1:1, 4:3, 3:4, 21:9, 4:5 ou original, com fundo preto, colorido ou desfocado

**Visual**
- Transformar: escala, posição, rotação e opacidade
- Ajustar: brilho, contraste, saturação, exposição, temperatura, tint, realces, sombras, hue, nitidez, vinheta, desbotar e granulado
- 14 filtros com intensidade e miniaturas de pré-visualização
- 10 efeitos: desfoque, pixelizar, glitch RGB, espelho, tremor, flash, pulso de zoom, caleidoscópio, quadrinhos e contornos neon
- Animações de entrada e saída: esmaecer, zooms, deslizar (4 direções), girar e máquina de escrever (texto)
- 9 transições: dissolver, escurecer, clarear, cortinas, empurrar e zoom com desfoque

**Texto e legendas**
- Fonte, tamanho, negrito/itálico, alinhamento, cor, contorno, fundo, sombra, posição, escala e rotação
- Estilos prontos (clássico, contorno, destaque, neon)
- Importar e exportar legendas SRT

**Áudio**
- Faixas de música, volume, fade de entrada/saída, silenciar faixa
- Crossfade automático nas transições da faixa principal

**Exportação**
- Resolução: 480p, 720p, 1080p, 2K, 4K, 8K ou personalizada (largura × altura)
- Taxa de quadros: 23,976 / 24 / 25 / 29,97 / 30 / 50 / 59,94 / 60 / 120 fps
- Codificador: H.264, HEVC ou Apple ProRes 422
- Formato: MP4, MOV ou M4A (só áudio)
- Qualidade: mais baixa, recomendada, mais alta, bitrate personalizado (Mbps) ou tamanho de arquivo alvo (MB)
- Intervalo de quadros-chave, bitrate e taxa de amostragem do áudio
- Resumo ao vivo com dimensões, bitrate e tamanho estimado; progresso, tempo restante e cancelamento

## Requisitos

- macOS 14 ou superior (Apple Silicon ou Intel)
- Swift 6 (as Command Line Tools bastam; o Xcode não é necessário)

## Uso

```bash
./scripts/make-app.sh          # gera build/OpenCut.app (release)
open build/OpenCut.app

swift run OpenCut              # ou rode direto, em modo debug
./scripts/test.sh              # roda os 44 testes
./scripts/make-demo.sh         # cria ~/Desktop/OpenCut Demo/Demo.opencut com mídia de exemplo
./scripts/make-demo.sh --export  # ...e também renderiza Demo.mp4
```

Para abrir um projeto pela linha de comando: `OpenCut -open caminho/projeto.opencut`.
Com o app empacotado, arquivos `.opencut` também abrem com duplo clique.

## Arquitetura

```
Sources/
  OpenCutCore/              biblioteca sem interface (testável)
    Model/                  Project, Track, Segment, Material — tempo em microssegundos
    Timeline/               TimelineEditor: operações puras (dividir, aparar, mover, ripple…)
    Render/                 FrameRenderer (Core Image), compositor AVFoundation,
                            CompositionBuilder, efeitos, animações, transições, texto
    Export/                 ExportSettings (cálculos de bitrate/tamanho) e Exporter
    Media/                  leitura de mídia e legendas SRT
  OpenCut/                  app SwiftUI
    EditorModel.swift       estado, desfazer por snapshot, preview com AVPlayer
    Views/                  mídia, preview, timeline, inspetor, exportação
Tests/OpenCutCoreTests/     44 testes (Swift Testing), incluindo exportações reais
scripts/                    empacotar, testar e gerar demo
```

Como funciona:

1. O projeto é um valor (`struct Project`). Cada edição gera uma nova versão;
   desfazer é voltar à versão anterior.
2. O `CompositionBuilder` transforma o projeto numa `AVMutableComposition`. Cada
   faixa de vídeo vira até duas faixas da composição (A/B), para que clipes
   sobrepostos numa transição sejam decodificados ao mesmo tempo. Uma faixa preta
   de preenchimento cobre a timeline inteira.
3. O `OpenCutCompositor` (um `AVVideoCompositing` customizado) recebe os quadros
   decodificados e o `FrameRenderer` desenha cada quadro com Core Image: fundo,
   clipes com ajustes, filtros, efeitos e animações, transições e textos.
4. O mesmo compositor serve ao preview (`AVPlayer`) e à exportação
   (`AVAssetReader` → `AVAssetWriter`), então o que se vê é o que se exporta.
5. Mudanças que só afetam a imagem (sliders de ajuste, filtros) atualizam o plano
   de render sem remontar a composição, o que deixa o preview responsivo.

## Ferramenta de depuração

`OPENCUT_SNAPSHOT_DIR=/tmp/snaps .build/debug/OpenCut -open projeto.opencut`
percorre algumas telas, salva capturas das janelas e um quadro do preview, e
fecha o app. Útil para verificar a interface sem permissão de gravação de tela.

## Limitações conhecidas

- Sem os recursos de IA do CapCut (legendas automáticas, remoção de fundo,
  vozes etc.), que dependem de modelos e serviços proprietários.
- Volume limitado a 100% (limite do `AVAudioMix`).
- A timeline não rola sozinha para acompanhar o cursor durante a reprodução.
- Formas de onda de áudio não são desenhadas; a faixa mostra só a linha de volume.
