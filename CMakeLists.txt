cmake_minimum_required(VERSION 3.21)

project(elixir-client VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network)
find_package(MpvQt REQUIRED)
include(CheckIncludeFileCXX)

qt_standard_project_setup()

set(SOURCES
    src/main.cpp
    src/backend/ApiClient.cpp
    src/backend/ControlPlaneClient.cpp
    src/backend/LibraryModel.cpp
    src/backend/MpvItem.cpp
    src/backend/PlayerController.cpp
    src/backend/ServerDiscovery.cpp
    src/backend/ServerListModel.cpp
    src/backend/SessionManager.cpp
    resources/qml.qrc
)

qt_add_executable(elixir-client ${SOURCES})

target_include_directories(elixir-client PRIVATE src)

target_link_libraries(elixir-client
    PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    MpvQt::MpvQt
)

if(APPLE)
    target_compile_definitions(elixir-client PRIVATE ELIXIR_HAS_DNSSD=1)
else()
    check_include_file_cxx(dns_sd.h ELIXIR_HAS_DNSSD_HEADER)
    if(ELIXIR_HAS_DNSSD_HEADER)
        find_library(DNSSD_LIBRARY dns_sd)
        if(DNSSD_LIBRARY)
            target_compile_definitions(elixir-client PRIVATE ELIXIR_HAS_DNSSD=1)
            target_link_libraries(elixir-client PRIVATE ${DNSSD_LIBRARY})
            if(WIN32)
                target_link_libraries(elixir-client PRIVATE ws2_32)
            endif()
        endif()
    endif()
endif()

set_target_properties(elixir-client PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)
