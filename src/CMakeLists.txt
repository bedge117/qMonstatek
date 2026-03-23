add_subdirectory(backend)

# Main executable
qt_add_executable(qmonstatek WIN32
    main.cpp
)

set_target_properties(qmonstatek PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# QML module
qt_add_qml_module(qmonstatek
    URI QMonstatek
    VERSION 1.0
    QML_FILES
        qml/main.qml
        qml/components/Sidebar.qml
        qml/components/StatusBar.qml
        qml/components/DeviceSelector.qml
        qml/components/VirtualButtonPad.qml
        qml/components/MonoDisplay.qml
        qml/views/DeviceInfoView.qml
        qml/views/ScreenMirrorView.qml
        qml/views/FileManagerView.qml
        qml/views/FirmwareUpdateView.qml
        qml/views/Esp32UpdateView.qml
        qml/views/DualBootView.qml
        qml/views/DebugTerminalView.qml
        qml/views/PowerView.qml
        qml/views/SettingsView.qml
        qml/views/AboutView.qml
        qml/views/DfuFlashView.qml
        qml/views/SwdRecoveryView.qml
)

# App resources (icons, images)
qt_add_resources(qmonstatek "app_resources"
    PREFIX "/"
    BASE resources
    FILES
        resources/icons/app_icon.png
        resources/icons/qmonstatek.ico
)

target_link_libraries(qmonstatek PRIVATE
    qmonstatek_backend
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)

# Windows application icon
if(WIN32)
    target_sources(qmonstatek PRIVATE resources/app.rc)
endif()

# Install rules
install(TARGETS qmonstatek
    RUNTIME DESTINATION bin
    BUNDLE DESTINATION .
)
