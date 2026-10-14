# App OpenFrame (QML). Os arquivos QML ficam todos em qml/ e entram no módulo
# "OpenFrame" na raiz (alias pelo nome do arquivo), para se enxergarem sem import.
# Multimedia: o núcleo linka (som do Player); o alvo precisa ser visível aqui,
# onde o executável é finalizado.
find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 QuickDialogs2 Multimedia)

qt_add_executable(OpenFrame WIN32 MACOSX_BUNDLE
    main.cpp
)

set_target_properties(OpenFrame PROPERTIES
    OUTPUT_NAME OpenFrame
    MACOSX_BUNDLE_GUI_IDENTIFIER app.openframe.qt
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
)

file(GLOB OPENFRAME_QML CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" qml/*.qml qml/*.js)
foreach(file IN LISTS OPENFRAME_QML)
    get_filename_component(name "${file}" NAME)
    set_source_files_properties("${file}" PROPERTIES QT_RESOURCE_ALIAS "${name}")
endforeach()
set_source_files_properties(qml/Theme.qml qml/Icons.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

set(OPENFRAME_FONTS
    fonts/Inter-ExtraLight.ttf
    fonts/Inter-Light.ttf
    fonts/Inter-Regular.ttf
    fonts/Inter-Medium.ttf
    fonts/lucide.ttf
)

qt_add_qml_module(OpenFrame
    URI OpenFrame
    VERSION 1.0
    QML_FILES ${OPENFRAME_QML}
    SOURCES
        CoreBridge.h CoreBridge.cpp
        EditorModel.h EditorModel.cpp
        FilterPreviews.h FilterPreviews.cpp
        KeyedListModel.h KeyedListModel.cpp
        MediaCache.h MediaCache.cpp
        PaintedItems.h PaintedItems.cpp
        Snapshot.h Snapshot.cpp
        TextPresets.h TextPresets.cpp
    RESOURCES
        ${OPENFRAME_FONTS}
        icons/openframe-256.png
)

target_compile_definitions(OpenFrame PRIVATE OPENFRAME_VERSION="${PROJECT_VERSION}")
target_link_libraries(OpenFrame PRIVATE
    openframe_core
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Concurrent
)

# Ícone e versão do executável no Windows.
if(WIN32)
    get_filename_component(OPENFRAME_ICO "${CMAKE_CURRENT_SOURCE_DIR}/../../packaging/windows/OpenFrame.ico" ABSOLUTE)
    configure_file(../../packaging/windows/OpenFrame.rc.in "${CMAKE_CURRENT_BINARY_DIR}/OpenFrame.rc" @ONLY)
    target_sources(OpenFrame PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/OpenFrame.rc")
endif()

include(GNUInstallDirs)
install(TARGETS OpenFrame
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
