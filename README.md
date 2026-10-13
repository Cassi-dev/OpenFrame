<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/png/openframe-lockup-horizontal-color-on-dark-1600.png">
    <img alt="OpenFrame" src="assets/brand/png/openframe-lockup-horizontal-color-on-light-1600.png" width="420">
  </picture>
</p>

<p align="center">
  <strong>Editor de vídeo nativo para Mac. Leve, offline e com controle total da exportação.</strong>
</p>

<p align="center">
  <a href="https://github.com/talescavalcanti/OpenFrame/releases/latest"><img alt="Baixar para macOS" src="https://img.shields.io/badge/Baixar_para_macOS-.dmg-00C2CC?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>

<p align="center">
  <a href="https://github.com/talescavalcanti/OpenFrame/releases/latest"><img alt="Versão" src="https://img.shields.io/github/v/release/talescavalcanti/OpenFrame?label=vers%C3%A3o&color=17171C"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-17171C">
  <img alt="Apple Silicon e Intel" src="https://img.shields.io/badge/Apple_Silicon_%2B_Intel-universal-17171C">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-17171C?logo=swift&logoColor=white">
</p>

<p align="center">
  <img alt="O editor do OpenFrame: biblioteca de mídia, preview, inspetor e timeline com faixas de texto, sobreposição, vídeo e áudio" src="docs/images/openframe-editor.png" width="900">
</p>

---

## A proposta

Editar um vídeo curto não devia exigir um app de vários gigabytes, uma conta ou
uma conexão com a internet. O **OpenFrame** é um editor de vídeo feito do zero
para o Mac, em Swift, com a experiência dos editores populares de timeline
(faixas, clipes, texto, transições, efeitos) e nada além do necessário:

- **Nativo e leve.** Usa AVFoundation e Core Image, os mesmos motores do macOS.
  O instalador tem cerca de 3 MB; o app de referência que inspirou o projeto passa de 2,6 GB.
- **Seu material fica com você.** Não há conta, nuvem nem telemetria: o app não
  faz nenhuma chamada de rede. Tudo roda localmente, inclusive sem internet.
- **Sem marca d'água e sem assinatura.** O que você exporta é só seu.
- **Exportação sob controle.** Resolução, fps, codificador, bitrate ou tamanho
  de arquivo alvo, com estimativa ao vivo antes de exportar.
- **O que se vê é o que se exporta.** O preview e a exportação usam o mesmo
  compositor, e as cores originais de vídeos e fotos são preservadas.

O conjunto de funcionalidades foi levantado estudando o CapCut para Mac por
engenharia reversa (análise estática, com o [REA](docs/REFERENCIA-REA.md)). O
código do OpenFrame é original: nada do binário, das bibliotecas ou dos recursos
da ByteDance foi reaproveitado.

## Baixar e instalar

1. Baixe o **`OpenFrame-<versão>.dmg`** na [página da última versão](https://github.com/talescavalcanti/OpenFrame/releases/latest).
2. Abra o `.dmg` e arraste o **OpenFrame** para a pasta **Aplicativos**.
3. Abra o OpenFrame pela pasta Aplicativos ou pelo Launchpad.

**Na primeira abertura**, o macOS avisa que não pode verificar o app, porque ele
ainda não é notarizado pela Apple. Para liberar:

- vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o aviso sobre o
  OpenFrame e clique em **Abrir Mesmo Assim**; ou
- no Terminal: `xattr -dr com.apple.quarantine /Applications/OpenFrame.app`

Depois disso, ele abre normalmente. Requer **macOS 14 (Sonoma) ou superior**, em
Mac com Apple Silicon ou Intel.

## Funcionalidades

**Projetos**
- Tela inicial com todos os projetos: miniatura, duração, formato e data da última edição; busca por nome
- Novo projeto vazio ou num formato pronto: 16:9 (YouTube), 9:16 (Reels, TikTok, Shorts), 1:1 e 4:5
- Salvamento automático em `~/Movies/OpenFrame/Projetos`, sem janela de salvar
- Renomear, duplicar, mostrar no Finder e apagar (vai para o Lixo); abrir ou exportar arquivos `.openframe`

**Edição**
- Importar vídeos, fotos e áudios pelo botão ou arrastando arquivos para a janela
- Timeline com faixa principal magnética, sobreposições (picture-in-picture), textos e áudios
- Mover, reordenar, aparar pelas bordas, dividir (⌘B), duplicar (⌘D) e apagar (⌫), com ímã
- Arrastar mídia da biblioteca direto para a timeline, e clipes entre faixas
- Zoom da timeline com pinça, ⌘ + roda e "Ajustar à janela" (⇧Z); rolagem que acompanha a reprodução
- Velocidade de 0,1× a 10×, com o tom do áudio preservado
- Desfazer e refazer ilimitados (⌘Z / ⇧⌘Z)
- Canvas 16:9, 9:16, 1:1, 4:3, 3:4, 21:9, 4:5 ou original, com fundo preto, colorido ou desfocado

**Visual**
- Transformar: escala, posição, rotação e opacidade
- Ajustes: brilho, contraste, saturação, exposição, temperatura, tint, realces, sombras, matiz, nitidez, vinheta, desbotar e granulado
- 14 filtros com intensidade e miniaturas
- 10 efeitos: desfoque, pixelizar, glitch RGB, espelho, tremor, flash, pulso de zoom, caleidoscópio, quadrinhos e contornos neon
- Animações de entrada e saída: esmaecer, zooms, deslizar (4 direções), girar e máquina de escrever
- 9 transições: dissolver, escurecer, clarear, cortinas, empurrar e zoom com desfoque

**Texto e legendas**
- Família e estilo de fonte, tamanho, negrito, itálico, sublinhado e maiúsculas
- Espaçamento entre letras e entre linhas
- Contorno por fora da letra, sombra (cor, distância, ângulo e desfoque) e fundo com cantos arredondados
- Estilos prontos: clássico, contorno, destaque, neon, legenda, etiqueta, sombra dura e espaçado
- Importar e exportar legendas SRT

**Áudio**
- Faixas de música, volume, fade de entrada e de saída, silenciar faixa
- Forma de onda nos clipes e nas miniaturas da biblioteca
- Crossfade automático nas transições da faixa principal

**Exportação**
- Resolução: 480p, 720p, 1080p, 2K, 4K, 8K ou personalizada
- Taxa de quadros: 23,976 / 24 / 25 / 29,97 / 30 / 50 / 59,94 / 60 / 120 fps
- Codificador: H.264, HEVC ou Apple ProRes 422; formato MP4, MOV ou M4A (só áudio)
- Qualidade: mais baixa, recomendada, mais alta, bitrate personalizado (Mbps) ou tamanho de arquivo alvo (MB)
- Intervalo de quadros-chave, bitrate e taxa de amostragem do áudio
- Resumo ao vivo com dimensões, bitrate e tamanho estimado; progresso, tempo restante e cancelamento

## Limitações conhecidas

- Sem os recursos de IA do CapCut (legendas automáticas, remoção de fundo, vozes),
  que dependem de modelos e serviços proprietários.
- Projetos e exportação em SDR (Rec. 709). Vídeos HDR são convertidos para SDR.
- Volume limitado a 100% (limite do `AVAudioMix`).
- Ainda sem animação por keyframes nem exportação em GIF.

---

## Para desenvolvedores

### Compilar a partir do código

Precisa de Swift 6. As Command Line Tools bastam; o Xcode não é necessário.

```bash
git clone https://github.com/talescavalcanti/OpenFrame.git
cd OpenFrame
./scripts/setup-git.sh           # ativa o hook que protege main e develop

./scripts/make-app.sh            # build/OpenFrame.app (release, universal)
./scripts/make-dmg.sh            # ...e o instalador build/OpenFrame-<versão>.dmg
open build/OpenFrame.app

swift run OpenFrame              # modo debug
./scripts/test.sh                # testes (Swift Testing)
./scripts/make-demo.sh           # projeto de exemplo em ~/Desktop/OpenFrame Demo
./scripts/make-demo.sh --export  # ...e também renderiza Demo.mp4
```

Para abrir um projeto pela linha de comando: `OpenFrame -open caminho/projeto.openframe`.
Com o app instalado, arquivos `.openframe` abrem com duplo clique.

### Arquitetura

```
Sources/
  OpenFrameCore/            biblioteca sem interface (testável)
    Model/                  Project, Track, Segment, Material; tempo em microssegundos
    Timeline/               TimelineEditor: operações puras (dividir, aparar, mover, reordenar…)
    Render/                 FrameRenderer (Core Image), compositor AVFoundation,
                            CompositionBuilder, efeitos, animações, transições, texto
    Export/                 ExportSettings (bitrate e tamanho) e Exporter
    Media/                  leitura de mídia, forma de onda e legendas SRT
  OpenFrame/                app SwiftUI
    EditorModel.swift       estado, desfazer por snapshot, preview com AVPlayer
    Views/                  mídia, preview, timeline, inspetor, exportação
Tests/OpenFrameCoreTests/   testes, incluindo exportações reais e fidelidade de cor
scripts/                    empacotar, gerar o .dmg, testar e gerar o demo
assets/brand/               logo, ícone do app e guia da marca
```

Como funciona:

1. O projeto é um valor (`struct Project`). Cada edição gera uma nova versão, e
   desfazer é voltar à anterior.
2. O `CompositionBuilder` transforma o projeto numa `AVMutableComposition`. Cada
   faixa de vídeo vira até duas faixas da composição (A/B), para que clipes
   sobrepostos numa transição sejam decodificados ao mesmo tempo.
3. O `OpenFrameCompositor` (um `AVVideoCompositing` próprio) recebe os quadros
   decodificados, e o `FrameRenderer` desenha cada quadro com Core Image: fundo,
   clipes com ajustes, filtros, efeitos e animações, transições e textos.
4. O mesmo compositor serve ao preview (`AVPlayer`) e à exportação
   (`AVAssetReader` → `AVAssetWriter`), então o que se vê é o que se exporta.
5. Mudanças que só afetam a imagem (ajustes, filtros) atualizam o plano de render
   sem remontar a composição, o que deixa o preview responsivo.

### Versionamento

Gitflow: a `main` guarda só versões estáveis (tag `vX.Y.Z`, com o `.dmg` na
página de releases), a `develop` integra o trabalho, e cada funcionalidade ou
correção tem a própria branch (`feature/…`, `bugfix/…`, `release/…`, `hotfix/…`).
Detalhes e comandos em [docs/GITFLOW.md](docs/GITFLOW.md).

### Ferramenta de depuração

`OPENFRAME_SNAPSHOT_DIR=/tmp/snaps .build/debug/OpenFrame -open projeto.openframe`
percorre as telas principais, salva capturas das janelas e um quadro do preview,
e fecha o app. Serve para conferir a interface sem permissão de gravação de tela.

### Marca

Logo, ícone, paleta e regras de uso em [assets/brand](assets/brand/README.md).
