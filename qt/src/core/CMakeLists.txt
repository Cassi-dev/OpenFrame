# Núcleo sem interface: modelo, timeline, mídia (FFmpeg), render e exportação.
add_library(openframe_core STATIC
    Timing.h Timing.cpp
    Enums.h
    Color.h
    Captions.h
    Effects.h Effects.cpp
    Project.h Project.cpp
    ProjectStore.h ProjectStore.cpp
    TimelineEditor.h TimelineEditor.cpp
    CanvasLayout.h CanvasLayout.cpp
    CaptionPresets.h CaptionPresets.cpp
    CaptionBuilder.h CaptionBuilder.cpp
    WhisperModels.h WhisperModels.cpp
    Transcriber.h Transcriber.cpp
    Subtitles.h Subtitles.cpp
    ExportSettings.h ExportSettings.cpp
    ProjectLibrary.h ProjectLibrary.cpp
    FontCatalog.h FontCatalog.cpp
    FFmpeg.h FFmpeg.cpp
    MediaProbe.h MediaProbe.cpp
    VideoDecoder.h VideoDecoder.cpp
    ToneMap.h ToneMap.cpp
    Thumbnails.h Thumbnails.cpp
    Waveform.h Waveform.cpp
    MediaWriter.h MediaWriter.cpp
    LinearImage.h LinearImage.cpp
    FilterModels.h FilterModels.cpp
    ImageEffects.h ImageEffects.cpp
    Motion.h Motion.cpp
    TextRenderer.h TextRenderer.cpp
    Renderer.h Renderer.cpp
    AudioMix.h AudioMix.cpp
    Player.h Player.cpp
    Exporter.h Exporter.cpp
)
target_include_directories(openframe_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(openframe_core PUBLIC Qt6::Core Qt6::Gui Qt6::Concurrent)

# Saída de som do Player (QAudioSink).
find_package(Qt6 REQUIRED COMPONENTS Multimedia)
target_link_libraries(openframe_core PRIVATE Qt6::Multimedia)

include(FFmpeg)
target_link_libraries(openframe_core PRIVATE FFmpeg::FFmpeg)
