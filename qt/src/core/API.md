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

Convenções:
- Enums são `enum class` em PascalCase (`AspectRatio::R9x16`, `TrackKind::Text`).
- O `throws` do Swift virou `std::optional`/`bool` com `QString *error` opcional.
- `TimelineEditor.delete` do Swift chama-se `remove` (palavra reservada em C++).
- Projeto novo (`Project{}`) já vem com a faixa principal, como no Swift.
