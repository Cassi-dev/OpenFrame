# Localiza o FFmpeg e cria o alvo FFmpeg::FFmpeg.
# - macOS/Linux: pkg-config (Homebrew, apt).
# - Windows: FFMPEG_ROOT apontando para um build "shared" com include/ e lib/.
set(_of_ffmpeg_libs avformat avcodec avfilter avutil swscale swresample)

if(NOT TARGET FFmpeg::FFmpeg)
    if(FFMPEG_ROOT OR DEFINED ENV{FFMPEG_ROOT})
        if(NOT FFMPEG_ROOT)
            set(FFMPEG_ROOT "$ENV{FFMPEG_ROOT}")
        endif()
        find_path(FFMPEG_INCLUDE_DIR libavcodec/avcodec.h PATHS "${FFMPEG_ROOT}/include" NO_DEFAULT_PATH REQUIRED)
        add_library(FFmpeg::FFmpeg INTERFACE IMPORTED)
        target_include_directories(FFmpeg::FFmpeg INTERFACE "${FFMPEG_INCLUDE_DIR}")
        foreach(lib ${_of_ffmpeg_libs})
            find_library(FFMPEG_${lib}_LIBRARY NAMES ${lib} PATHS "${FFMPEG_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
            target_link_libraries(FFmpeg::FFmpeg INTERFACE "${FFMPEG_${lib}_LIBRARY}")
        endforeach()
    else()
        find_package(PkgConfig REQUIRED)
        pkg_check_modules(FFMPEG REQUIRED IMPORTED_TARGET
            libavformat libavcodec libavfilter libavutil libswscale libswresample)
        add_library(FFmpeg::FFmpeg INTERFACE IMPORTED)
        target_link_libraries(FFmpeg::FFmpeg INTERFACE PkgConfig::FFMPEG)
    endif()
endif()
