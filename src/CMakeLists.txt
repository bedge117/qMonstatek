add_subdirectory(backend)

# Main executable
if(WIN32)
    qt_add_executable(qmonstatek WIN32 main.cpp)
elseif(APPLE)
    qt_add_executable(qmonstatek MACOSX_BUNDLE main.cpp)
else()
    qt_add_executable(qmonstatek main.cpp)
endif()

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
        qml/components/M1DeviceSkin.qml
        qml/components/WelcomeView.qml
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
        resources/images/enter_dfu.png
        resources/images/reboot_device.png
        resources/images/swd_recovery.png
        resources/firmware/M1_Recovery_C3.1.0_wCRC.bin
)

target_link_libraries(qmonstatek PRIVATE
    qmonstatek_backend
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)

# Platform-specific resources
if(WIN32)
    target_sources(qmonstatek PRIVATE resources/app.rc)
elseif(APPLE)
    set(MACOSX_BUNDLE_ICON_FILE qmonstatek.icns)
    set(ICON_FILE "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/qmonstatek.icns")
    if(EXISTS "${ICON_FILE}")
        set_source_files_properties("${ICON_FILE}" PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources")
        target_sources(qmonstatek PRIVATE "${ICON_FILE}")
    endif()
    set_target_properties(qmonstatek PROPERTIES
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.monstatek.qmonstatek"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_BUNDLE_NAME "qMonstatek")
endif()

# Install rules
install(TARGETS qmonstatek
    RUNTIME DESTINATION bin
    BUNDLE DESTINATION .
)
