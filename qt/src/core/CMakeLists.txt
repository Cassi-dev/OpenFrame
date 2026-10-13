# Núcleo sem interface: modelo, timeline, mídia (FFmpeg), render e exportação.
add_library(openframe_core STATIC
    Timing.h Timing.cpp
    Enums.h
    Effects.h Effects.cpp
)
target_include_directories(openframe_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(openframe_core PUBLIC Qt6::Core Qt6::Gui Qt6::Concurrent)
