# Localiza o FFmpeg e cria o alvo FFmpeg::FFmpeg.
# - macOS/Linux: pkg-config (Homebrew, apt).
# - Windows: FFMPEG_ROOT apontando para um build "shared" com include/ e lib/.
# - Android: FFMPEG_ROOT (ou FFMPEG_ANDROID_ROOT) apontando para o build NDK da arquitetura (${ANDROID_ABI}).

set(_of_ffmpeg_libs avformat avcodec avfilter avutil swscale swresample)

if(NOT TARGET FFmpeg::FFmpeg)
    # Suporte específico a Android
    if(ANDROID)
        if(NOT FFMPEG_ROOT AND DEFINED ENV{FFMPEG_ROOT})
            set(FFMPEG_ROOT "$ENV{FFMPEG_ROOT}")
        endif()
        if(NOT FFMPEG_ROOT AND DEFINED ENV{FFMPEG_ANDROID_ROOT})
            set(FFMPEG_ROOT "$ENV{FFMPEG_ANDROID_ROOT}")
        endif()

        # Tenta subdiretório com a ABI (ex: arm64-v8a) ou raiz direta
        if(EXISTS "${FFMPEG_ROOT}/${ANDROID_ABI}")
            set(_ffmpeg_base "${FFMPEG_ROOT}/${ANDROID_ABI}")
        else()
            set(_ffmpeg_base "${FFMPEG_ROOT}")
        endif()

        find_path(FFMPEG_INCLUDE_DIR libavcodec/avcodec.h PATHS "${_ffmpeg_base}/include" "${FFMPEG_ROOT}/include" NO_DEFAULT_PATH REQUIRED)
        add_library(FFmpeg::FFmpeg INTERFACE IMPORTED)
        target_include_directories(FFmpeg::FFmpeg INTERFACE "${FFMPEG_INCLUDE_DIR}")

        set(OPENFRAME_ANDROID_FFMPEG_LIBS "")
        foreach(lib ${_of_ffmpeg_libs})
            find_library(FFMPEG_${lib}_LIBRARY NAMES ${lib} PATHS "${_ffmpeg_base}/lib" NO_DEFAULT_PATH REQUIRED)
            target_link_libraries(FFmpeg::FFmpeg INTERFACE "${FFMPEG_${lib}_LIBRARY}")
            list(APPEND OPENFRAME_ANDROID_FFMPEG_LIBS "${FFMPEG_${lib}_LIBRARY}")
        endforeach()
        set(OPENFRAME_ANDROID_FFMPEG_LIBS "${OPENFRAME_ANDROID_FFMPEG_LIBS}" PARENT_SCOPE)

    # Windows ou FFMPEG_ROOT explícito no Desktop
    elseif(FFMPEG_ROOT OR DEFINED ENV{FFMPEG_ROOT})
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
