add_library(qmonstatek_backend STATIC
    # Protocol
    protocol/crc16.cpp
    protocol/rpc_frame.cpp

    # Transport
    transport/abstract_transport.cpp
    transport/serial_transport.cpp
    transport/tcp_transport.cpp
    transport/wifi_transport.cpp
    transport/network_worker.cpp
    transport/device_discovery.cpp
    transport/mdns_discovery.cpp

    # Device
    device/m1_device.cpp
    device/screen_buffer.cpp
    device/screen_canvas.cpp
    device/log_model.cpp
    ui_settings.cpp

    # Updater
    updater/github_checker.cpp
    updater/self_updater.cpp
    updater/tool_paths.cpp
    updater/dfu_flasher.cpp
    updater/swd_recovery.cpp
)

target_include_directories(qmonstatek_backend PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(qmonstatek_backend PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::SerialPort
    Qt6::Network
)
