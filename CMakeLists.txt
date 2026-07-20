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
include(CTest)

get_filename_component(MPVQT_PREFIX "${MpvQt_DIR}/../../.." ABSOLUTE)
find_path(
    MPVQT_INCLUDE_ROOT
    NAMES MpvQt/mpvabstractitem.h
    HINTS "${MPVQT_PREFIX}/include"
    REQUIRED)

option(
    ELIXIR_ALLOW_INSECURE_CREDENTIAL_STORAGE
    "Allow development-only plaintext refresh-token storage on platforms without a credential vault"
    OFF)
option(
    ELIXIR_ENABLE_CLIENT_COVERAGE
    "Instrument client unit-test targets and enable the elixir-client-coverage report target"
    OFF)

qt_standard_project_setup()

set(SOURCES
    src/main.cpp
    src/backend/ControlPlaneClient.cpp
    src/backend/LibraryModel.cpp
    src/backend/PlayerController.cpp
    src/backend/ServerDiscovery.cpp
    src/backend/ServerListModel.cpp
    resources/qml.qrc
)

add_library(elixir-client-auth STATIC
    src/backend/ApiClient.cpp
    src/backend/CredentialStore.cpp
    src/backend/SessionManager.cpp
)

target_include_directories(elixir-client-auth PUBLIC src)
target_link_libraries(elixir-client-auth PUBLIC Qt6::Core Qt6::Network)

add_library(elixir-client-live STATIC
    src/live/LiveApiClient.cpp
    src/live/LiveApiClient.h
    src/live/LiveCatalogModel.cpp
    src/live/LiveCatalogModel.h
    src/live/LiveQmlNetworkAccessManagerFactory.cpp
    src/live/LiveQmlNetworkAccessManagerFactory.h
    src/live/LiveTypes.cpp
    src/live/LiveTypes.h
)
target_include_directories(elixir-client-live PUBLIC src)
target_link_libraries(
    elixir-client-live
    PUBLIC elixir-client-auth Qt6::Core Qt6::Network Qt6::Qml)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(
        elixir-client-live
        PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion)
endif()

add_library(elixir-client-live-player STATIC
    src/backend/LivePlaybackTarget.h
    src/backend/LivePlayerController.cpp
    src/backend/LivePlayerController.h
    src/backend/MpvItem.cpp
    src/backend/MpvItem.h
)
target_include_directories(elixir-client-live-player PUBLIC src)
target_include_directories(
    elixir-client-live-player SYSTEM PRIVATE ${MPVQT_INCLUDE_ROOT})
target_link_libraries(
    elixir-client-live-player
    PUBLIC elixir-client-live Qt6::Core Qt6::Quick MpvQt::MpvQt)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(
        elixir-client-live-player
        PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion)
endif()

if(ELIXIR_ALLOW_INSECURE_CREDENTIAL_STORAGE)
    target_compile_definitions(
        elixir-client-auth
        PRIVATE $<$<CONFIG:Debug>:ELIXIR_ALLOW_INSECURE_CREDENTIAL_STORAGE=1>)
endif()

if(APPLE)
    find_library(SECURITY_FRAMEWORK Security REQUIRED)
    target_link_libraries(elixir-client-auth PRIVATE ${SECURITY_FRAMEWORK})
endif()

qt_add_executable(elixir-client ${SOURCES})

target_include_directories(elixir-client PRIVATE src)
target_include_directories(elixir-client SYSTEM PRIVATE ${MPVQT_INCLUDE_ROOT})

target_link_libraries(elixir-client
    PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    elixir-client-auth
    elixir-client-live
    elixir-client-live-player
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

if(BUILD_TESTING)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test QuickTest)
    add_library(elixir-client-test-support STATIC
        tests/support/DeterministicScheduler.cpp
        tests/support/DeterministicScheduler.h
        tests/support/ScriptedNetworkAccessManager.cpp
        tests/support/ScriptedNetworkAccessManager.h
    )
    target_include_directories(elixir-client-test-support PUBLIC tests)
    target_link_libraries(elixir-client-test-support PUBLIC Qt6::Core Qt6::Network)

    qt_add_executable(elixir-client-foundation-tests
        tests/TestFoundationTests.cpp
    )
    qt_add_executable(elixir-client-qml-tests
        tests/QmlTestRunner.cpp
        resources/qml.qrc
    )
    qt_add_executable(elixir-auth-tests
        tests/AuthTransportTests.cpp
    )
    qt_add_executable(elixir-auth-real-server-tests
        tests/RealServerAuthTests.cpp
    )
    qt_add_executable(elixir-client-live-tests
        tests/LiveClientTests.cpp
    )
    qt_add_executable(elixir-client-live-real-server-tests
        tests/RealServerLiveTests.cpp
    )
    qt_add_executable(elixir-client-live-player-tests
        tests/LivePlayerTests.cpp
    )
    qt_add_executable(elixir-client-live-playback-real-server-tests
        tests/RealServerLivePlaybackTests.cpp
    )
    target_include_directories(elixir-auth-tests PRIVATE src)
    target_include_directories(elixir-auth-real-server-tests PRIVATE src)
    target_link_libraries(
        elixir-client-foundation-tests
        PRIVATE elixir-client-test-support Qt6::Test Qt6::Network)
    target_link_libraries(
        elixir-client-qml-tests
        PRIVATE Qt6::QuickTest Qt6::Quick Qt6::Qml Qt6::QuickControls2)
    target_compile_definitions(
        elixir-client-qml-tests
        PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/qml")
    target_link_libraries(elixir-auth-tests PRIVATE elixir-client-auth Qt6::Test Qt6::Network)
    target_link_libraries(
        elixir-auth-real-server-tests
        PRIVATE elixir-client-auth Qt6::Test Qt6::Network)
    target_link_libraries(
        elixir-client-live-tests
        PRIVATE elixir-client-live elixir-client-test-support Qt6::Test Qt6::Network)
    target_link_libraries(
        elixir-client-live-real-server-tests
        PRIVATE elixir-client-live Qt6::Test Qt6::Network)
    target_link_libraries(
        elixir-client-live-player-tests
        PRIVATE elixir-client-live-player elixir-client-test-support
                Qt6::Test Qt6::Network)
    target_link_libraries(
        elixir-client-live-playback-real-server-tests
        PRIVATE elixir-client-live-player Qt6::Test Qt6::Gui Qt6::Qml
                Qt6::Quick Qt6::Network)
    set_target_properties(
        elixir-client-foundation-tests
        elixir-client-qml-tests
        elixir-auth-tests
        elixir-auth-real-server-tests
        elixir-client-live-tests
        elixir-client-live-real-server-tests
        elixir-client-live-player-tests
        elixir-client-live-playback-real-server-tests
        PROPERTIES MACOSX_BUNDLE FALSE)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(
            elixir-client-test-support
            PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion)
    endif()

    add_test(NAME c10-foundation COMMAND elixir-client-foundation-tests)
    add_test(NAME c10-qml COMMAND elixir-client-qml-tests)
    add_test(NAME a13-auth-transport COMMAND elixir-auth-tests)
    add_test(NAME c11-live-client COMMAND elixir-client-live-tests)
    add_test(NAME c20-live-player COMMAND elixir-client-live-player-tests)
    add_test(
        NAME c22-live-recovery
        COMMAND elixir-client-live-player-tests
            c22RecoveryApiBuildsStrictRefreshAndManualFailoverRequests
            c22ControllerRefreshesThenFailsOverWithoutDuplicateActions
            c22ManualSourceSwitchRotatesPlaybackExactlyOnce
            c22ExpiryThresholdRefreshesBeforeHeartbeatMutation
            c22ExpectedEndAndExhaustionDoNotEnterRetryLoops
            c22RefreshFailureResyncsRevisionBeforeAutomaticFailover
            c22DeliveryModeEscalationResetsPerRouteRecoveryState
            c22ReconnectPolicyIsBoundedAndCancellationStopsReloads
            c22RouteExitDiscardsDelayedRecoveryReplyAndToken)
    add_test(
        NAME c30-live-player
        COMMAND elixir-client-live-player-tests
            c30SourcesTrackPreferencesAndDvrBoundsAreStrict)
    add_test(
        NAME c12-live-qml
        COMMAND elixir-client-qml-tests
            LiveBrowse::test_loading_empty_and_unavailable_states
            LiveBrowse::test_partial_stale_and_error_notice_states
            LiveBrowse::test_event_card_keyboard_accessibility_and_long_text
            LiveBrowse::test_live_vpn_policy_is_available_from_toolbar
            LiveBrowse::test_responsive_card_geometry
            LiveBrowse::test_extension_filter_types_render_native_controls
            LiveBrowse::test_malicious_metadata_is_rendered_as_plain_text
            LiveBrowse::test_theme_meets_normal_text_contrast
            LiveBrowse::test_details_loading_error_and_long_metadata
            Extensions::test_ready_live_provider_can_open_live)
    add_test(
        NAME c21-live-player-qml
        COMMAND elixir-client-qml-tests
            LivePlayer::test_start_observation_and_track_contract
            LivePlayer::test_dvr_controls_and_route_cleanup_are_live_native
            LivePlayer::test_non_seekable_and_terminal_states_have_no_finite_progress
            LivePlayer::test_terminal_failure_uses_server_message_and_action
            LivePlayer::test_stream_option_is_a_play_command
            LivePlayer::test_compact_controls_stay_inside_view)
    add_test(
        NAME c22-live-recovery-qml
        COMMAND elixir-client-qml-tests
            LivePlayer::test_recovery_countdown_actions_and_compact_geometry)
    add_test(
        NAME c30-live-player-qml
        COMMAND elixir-client-qml-tests
            LivePlayer::test_c30_preferences_source_switch_and_seek_clamp)
    add_test(
        NAME c31-live-admin-qml
        COMMAND elixir-client-qml-tests
            LiveAdmin::test_capability_and_owner_gates_are_exact
            LiveAdmin::test_mutations_require_confirmation_and_preserve_revisions
            LiveAdmin::test_destination_and_key_actions_are_bounded_and_secret_free)
    add_test(
        NAME n12-live-network-qml
        COMMAND elixir-client-qml-tests
            LiveNetworkSettings::test_capability_and_status_gate
            LiveNetworkSettings::test_fallback_visibility_and_cas_mutation
            LiveNetworkSettings::test_profile_scope_and_compact_accessibility)
    set_tests_properties(
        c10-foundation
        c10-qml
        a13-auth-transport
        c11-live-client
        c12-live-qml
        c21-live-player-qml
        c22-live-recovery
        c22-live-recovery-qml
        c30-live-player
        c30-live-player-qml
        c31-live-admin-qml
        n12-live-network-qml
        PROPERTIES TIMEOUT 30)
    set_tests_properties(
        c10-qml
        c12-live-qml
        c21-live-player-qml
        c22-live-recovery-qml
        c30-live-player-qml
        c31-live-admin-qml
        PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QSG_RHI_BACKEND=software;QT_FATAL_WARNINGS=1")
    set_tests_properties(c10-foundation c10-qml PROPERTIES LABELS "client;foundation")
    set_tests_properties(a13-auth-transport PROPERTIES LABELS "client;auth")
    set_tests_properties(c11-live-client PROPERTIES LABELS "client;live")
    set_tests_properties(c12-live-qml PROPERTIES LABELS "client;live;qml")
    set_tests_properties(c21-live-player-qml PROPERTIES LABELS "client;live;qml;player")
    set_tests_properties(c22-live-recovery PROPERTIES LABELS "client;live;player;recovery")
    set_tests_properties(c22-live-recovery-qml PROPERTIES LABELS "client;live;qml;player;recovery")
    set_tests_properties(c30-live-player PROPERTIES LABELS "client;live;player;advanced")
    set_tests_properties(c30-live-player-qml PROPERTIES LABELS "client;live;qml;player;advanced")
    set_tests_properties(c31-live-admin-qml PROPERTIES LABELS "client;live;qml;admin")

    if(ELIXIR_ENABLE_CLIENT_COVERAGE)
        if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
            message(FATAL_ERROR "ELIXIR_ENABLE_CLIENT_COVERAGE currently requires Clang/AppleClang")
        endif()
        find_program(LLVM_PROFDATA_EXECUTABLE NAMES llvm-profdata REQUIRED)
        find_program(LLVM_COV_EXECUTABLE NAMES llvm-cov REQUIRED)
        foreach(coverage_target IN ITEMS
            elixir-client-auth
            elixir-client-live
            elixir-client-test-support
            elixir-client-foundation-tests
            elixir-auth-tests
            elixir-client-live-tests)
            target_compile_options(
                ${coverage_target}
                PRIVATE -fprofile-instr-generate -fcoverage-mapping)
            target_link_options(${coverage_target} PRIVATE -fprofile-instr-generate)
        endforeach()
        add_custom_target(elixir-client-coverage
            COMMAND "${CMAKE_COMMAND}"
                "-DCTEST_COMMAND=${CMAKE_CTEST_COMMAND}"
                "-DCMAKE_COMMAND=${CMAKE_COMMAND}"
                "-DBUILD_DIR=${CMAKE_BINARY_DIR}"
                "-DPROFILE_DIR=${CMAKE_BINARY_DIR}/coverage"
                "-DLLVM_PROFDATA=${LLVM_PROFDATA_EXECUTABLE}"
                "-DLLVM_COV=${LLVM_COV_EXECUTABLE}"
                "-DCOVERAGE_BINARIES=$<TARGET_FILE:elixir-client-foundation-tests>|$<TARGET_FILE:elixir-auth-tests>|$<TARGET_FILE:elixir-client-live-tests>"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunCoverage.cmake"
            DEPENDS
                elixir-client-foundation-tests
                elixir-client-qml-tests
                elixir-auth-tests
                elixir-client-live-tests
            USES_TERMINAL
            VERBATIM)
    endif()
endif()
