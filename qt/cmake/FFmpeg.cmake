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

        # Procura os headers em múltiplos locais possíveis (layout padrão, ffmpeg-android-maker ou plano)
        find_path(FFMPEG_INCLUDE_DIR libavcodec/avcodec.h
            PATHS
                "${FFMPEG_ROOT}/include"
                "${FFMPEG_ROOT}/include/${ANDROID_ABI}"
                "${FFMPEG_ROOT}/${ANDROID_ABI}/include"
            NO_DEFAULT_PATH REQUIRED
        )
        add_library(FFmpeg::FFmpeg INTERFACE IMPORTED)
        target_include_directories(FFmpeg::FFmpeg INTERFACE "${FFMPEG_INCLUDE_DIR}")

        set(_of_android_libs "")
        foreach(lib ${_of_ffmpeg_libs})
            find_library(FFMPEG_${lib}_LIBRARY NAMES ${lib}
                PATHS
                    "${FFMPEG_ROOT}/lib"
                    "${FFMPEG_ROOT}/lib/${ANDROID_ABI}"
                    "${FFMPEG_ROOT}/${ANDROID_ABI}/lib"
                NO_DEFAULT_PATH REQUIRED
            )
            target_link_libraries(FFmpeg::FFmpeg INTERFACE "${FFMPEG_${lib}_LIBRARY}")
            list(APPEND _of_android_libs "${FFMPEG_${lib}_LIBRARY}")
        endforeach()
        set(OPENFRAME_ANDROID_FFMPEG_LIBS "${_of_android_libs}" CACHE INTERNAL "Android FFmpeg extra libs")

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
