import QtQuick
import QtQuick.Controls
import QtTest
import "../../src/qml/views" as Views

TestCase {
    id: testCase
    name: "LivePlayer"
    when: windowShown

    readonly property string providerId: "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d"
    readonly property string itemKey: "lvk1.item.fixture-key-value"
    readonly property string streamKey: "lvk1.stream.fixture-key-value"

    Window {
        id: testWindow
        width: 1280
        height: 720
        visible: true
        Item { id: host; anchors.fill: parent }
    }

    QtObject {
        id: controller
        property string state: "idle"
        property bool seekable: false
        property bool recovering: false
        property int reconnectAttempt: 0
        property int reconnectSecondsRemaining: 0
        property int windowSeconds: 0
        property real distanceFromLiveEdge: 0
        property var audioTracks: []
        property var subtitleTracks: []
        property var availableSources: [{"sourceKey": "lvk1.source.primaryfixture", "label": "Primary", "quality": "1080p"}]
        property var preferredAudioTrack: ({})
        property var preferredSubtitleTrack: ({})
        property string selectedSourceKey: "lvk1.source.primaryfixture"
        property string selectedSourceLabel: "Primary"
        property string selectedSourceQuality: "1080p"
        property string errorCode: ""
        property string failureMessage: ""
        property bool failureRetryable: false
        property string statusText: "Live"
        property int attachCalls: 0
        property int startCalls: 0
        property int stopCalls: 0
        property int routeExitedCalls: 0
        property int observeCalls: 0
        property int cancelRecoveryCalls: 0
        property int retryRecoveryCalls: 0
        property int selectTrackCalls: 0
        property int switchSourceCalls: 0
        property var attachedTarget: null
        property var lastStart: ({})
        property var lastObservation: ({})
        property var lastTrackSelection: ({})
        property string lastSourceKey: ""

        function attachPlayer(target) {
            attachCalls += 1
            attachedTarget = target
            return true
        }
        function start(provider, item, stream, title, endUtc) {
            startCalls += 1
            lastStart = {"provider": provider, "item": item, "stream": stream,
                         "title": title, "endUtc": endUtc}
        }
        function stop() { stopCalls += 1 }
        function routeExited() { routeExitedCalls += 1 }
        function cancelRecovery() { cancelRecoveryCalls += 1 }
        function retryRecoveryNow() { retryRecoveryCalls += 1 }
        function selectTrack(type, trackId) {
            selectTrackCalls += 1
            lastTrackSelection = {"type": type, "trackId": trackId}
        }
        function switchSource(sourceKey) {
            switchSourceCalls += 1
            lastSourceKey = sourceKey
        }
        function clampWindowPosition(seconds) {
            return Math.max(0, Math.min(windowSeconds, Number(seconds)))
        }
        function seekDeltaForWindowPosition(seconds) {
            var position = clampWindowPosition(seconds)
            return Math.max(0, Math.min(windowSeconds, distanceFromLiveEdge))
                    - (windowSeconds - position)
        }
        function observeMpv(observation) {
            observeCalls += 1
            lastObservation = observation
            audioTracks = observation.audioTracks
            subtitleTracks = observation.subtitleTracks
            distanceFromLiveEdge = observation.distanceFromLiveEdgeSeconds
        }
    }

    QtObject {
        id: liveModel
        property bool itemLoading: false
        property var providers: [{"providerId": testCase.providerId, "name": "Fixture Sports"}]
        property var lastError: ({})
        property var selectedItem: ({
            "title": "Championship Final",
            "status": "live",
            "endsAtUtc": new Date("2026-07-12T23:00:00Z"),
            "badges": [], "facts": [], "poster": null, "background": null
        })
        property var selectedStreams: [{
            "streamOptionKey": testCase.streamKey,
            "label": "Primary", "quality": "1080p", "language": "en",
            "protocolHint": "hls"
        }]
        property int loadItemCalls: 0
        function loadItem(provider, item) { loadItemCalls += 1 }
        function cancelItemRequest() {}
    }

    Component {
        id: fakeSurfaceComponent
        Item {
            property var values: ({
                "core-idle": false,
                "paused-for-cache": false,
                "pause": false,
                "eof-reached": false,
                "time-pos": 90,
                "duration": 100,
                "demuxer-cache-time": 100,
                "aid": "1",
                "sid": "2",
                "track-list": [
                    {"type": "audio", "id": 1, "lang": "en", "title": "Main", "selected": true},
                    {"type": "audio", "id": 3, "lang": "es", "title": "Spanish"},
                    {"type": "sub", "id": 2, "lang": "en", "title": "English", "selected": true}
                ]
            })
            property var setCalls: []
            property var commands: []
            function getProperty(name) { return values[name] }
            function setPropertyAsync(name, value) {
                setCalls = setCalls.concat([{"name": name, "value": value}])
                var next = Object.assign({}, values)
                next[name] = value
                values = next
            }
            function commandAsync(command) { commands = commands.concat([command]) }
        }
    }

    Component { id: playerComponent; Views.LivePlayerView {} }
    Component { id: detailsComponent; Views.LiveDetailsView {} }

    SignalSpy { id: streamSpy; signalName: "streamRequested" }

    function resetController() {
        controller.state = "idle"
        controller.seekable = false
        controller.recovering = false
        controller.reconnectAttempt = 0
        controller.reconnectSecondsRemaining = 0
        controller.windowSeconds = 0
        controller.distanceFromLiveEdge = 0
        controller.audioTracks = []
        controller.subtitleTracks = []
        controller.availableSources = [{"sourceKey": "lvk1.source.primaryfixture", "label": "Primary", "quality": "1080p"}]
        controller.preferredAudioTrack = ({})
        controller.preferredSubtitleTrack = ({})
        controller.selectedSourceKey = "lvk1.source.primaryfixture"
        controller.errorCode = ""
        controller.failureMessage = ""
        controller.failureRetryable = false
        controller.attachCalls = 0
        controller.startCalls = 0
        controller.stopCalls = 0
        controller.routeExitedCalls = 0
        controller.observeCalls = 0
        controller.cancelRecoveryCalls = 0
        controller.retryRecoveryCalls = 0
        controller.selectTrackCalls = 0
        controller.switchSourceCalls = 0
        controller.attachedTarget = null
        controller.lastStart = ({})
        controller.lastObservation = ({})
        controller.lastTrackSelection = ({})
        controller.lastSourceKey = ""
        liveModel.loadItemCalls = 0
        streamSpy.target = null
        streamSpy.clear()
    }

    function init() { resetController() }

    function createPlayer(width, height) {
        return createTemporaryObject(playerComponent, host, {
            "width": width,
            "height": height,
            "playerController": controller,
            "providerId": providerId,
            "itemKey": itemKey,
            "streamOptionKey": streamKey,
            "eventTitle": "Championship Final",
            "expectedEndUtc": new Date("2026-07-12T23:00:00Z"),
            "liveModel": liveModel,
            "playbackSurfaceComponent": fakeSurfaceComponent
        })
    }

    function test_start_observation_and_track_contract() {
        controller.state = "playing"
        controller.seekable = true
        controller.windowSeconds = 120
        var view = createPlayer(1280, 720)
        verify(view)
        tryCompare(controller, "startCalls", 1)
        compare(controller.attachCalls, 1)
        compare(controller.lastStart.provider, providerId)
        compare(controller.lastStart.item, itemKey)
        compare(controller.lastStart.stream, streamKey)

        view.samplePlayback()
        compare(controller.observeCalls, 1)
        compare(controller.lastObservation.distanceFromLiveEdgeSeconds, 10)
        compare(controller.lastObservation.audioTracks.length, 2)
        compare(controller.lastObservation.audioTracks[0].label, "EN / Main")
        compare(controller.lastObservation.subtitleTracks.length, 1)
        compare(controller.lastObservation.audioTrackId, "1")
        compare(controller.lastObservation.subtitleTrackId, "2")
        compare(controller.lastObservation.error, "")
        compare(findChild(view, "liveWindowSlider").visible, true)
        view.destroy()
        wait(0)
        compare(controller.routeExitedCalls, 1)
    }

    function test_dvr_controls_and_route_cleanup_are_live_native() {
        controller.state = "playing"
        controller.seekable = true
        controller.windowSeconds = 120
        controller.distanceFromLiveEdge = 10
        controller.audioTracks = [
            {"id": "1", "label": "English"}, {"id": "3", "label": "Spanish"}
        ]
        controller.subtitleTracks = [{"id": "2", "label": "English"}]
        var view = createPlayer(1280, 720)
        verify(view)
        tryCompare(controller, "startCalls", 1)
        var surface = view.playbackSurface

        mouseClick(findChild(view, "livePauseButton"))
        compare(surface.setCalls[surface.setCalls.length - 1].name, "pause")
        compare(surface.setCalls[surface.setCalls.length - 1].value, true)

        mouseClick(findChild(view, "liveGoLiveButton"))
        compare(surface.commands.length, 1)
        compare(surface.commands[0][0], "seek")
        compare(surface.commands[0][1], 100)

        var audio = findChild(view, "liveAudioTracks")
        verify(audio.visible)
        audio.activated(1)
        compare(surface.setCalls[surface.setCalls.length - 1].name, "aid")
        compare(surface.setCalls[surface.setCalls.length - 1].value, "3")
        compare(controller.lastTrackSelection.type, "audio")
        compare(controller.lastTrackSelection.trackId, "3")

        view.exitRoute(false)
        compare(controller.routeExitedCalls, 1)
        view.destroy()
        wait(0)
        compare(controller.routeExitedCalls, 1)
        compare(controller.stopCalls, 0)
    }

    function test_c30_preferences_source_switch_and_seek_clamp() {
        controller.state = "playing"
        controller.seekable = true
        controller.windowSeconds = 120
        controller.distanceFromLiveEdge = 10
        controller.availableSources = [
            {"sourceKey": "lvk1.source.primaryfixture", "label": "Primary", "quality": "1080p"},
            {"sourceKey": "lvk1.source.backupfixture0", "label": "Backup", "quality": "720p"}
        ]
        controller.preferredAudioTrack = {"trackId": "legacy-audio", "language": "es", "title": "Spanish"}
        controller.preferredSubtitleTrack = {"trackId": "no", "language": "", "title": ""}
        var view = createPlayer(1280, 720)
        verify(view)
        tryCompare(controller, "startCalls", 1)
        var surface = view.playbackSurface

        view.samplePlayback()
        compare(controller.selectTrackCalls, 2)
        compare(surface.setCalls[0].name, "aid")
        compare(surface.setCalls[0].value, "3")
        compare(surface.setCalls[1].name, "sid")
        compare(surface.setCalls[1].value, "no")

        var sources = findChild(view, "liveSourceChoices")
        verify(sources.visible)
        sources.activated(1)
        compare(controller.switchSourceCalls, 1)
        compare(controller.lastSourceKey, "lvk1.source.backupfixture0")

        view.seekWithinWindow(-50)
        compare(surface.commands[surface.commands.length - 1][0], "seek")
        compare(surface.commands[surface.commands.length - 1][1], -110)
        compare(surface.commands[surface.commands.length - 1][2], "relative")
        view.seekWithinWindow(500)
        compare(surface.commands[surface.commands.length - 1][1], 10)

        var next = Object.assign({}, surface.values)
        next["track-list"] = [
            {"type": "audio", "id": 1, "lang": "en", "title": "Main", "selected": true}
        ]
        next["aid"] = "1"
        surface.values = next
        view.samplePlayback()
        compare(controller.audioTracks.length, 1)
        compare(controller.selectTrackCalls, 2)
    }

    function test_non_seekable_and_terminal_states_have_no_finite_progress() {
        controller.state = "playing"
        var view = createPlayer(800, 600)
        verify(view)
        tryCompare(controller, "startCalls", 1)
        compare(findChild(view, "livePauseButton").enabled, false)
        compare(findChild(view, "liveWindowSlider").visible, false)
        compare(findChild(view, "liveGoLiveButton").visible, false)

        controller.state = "ended"
        tryCompare(findChild(view, "livePlayerStateText"), "text", "Event ended")
        compare(findChild(view, "livePlayerControls").visible, false)
        view.destroy()
        wait(0)
    }

    function test_terminal_failure_uses_server_message_and_action() {
        controller.state = "failed"
        controller.errorCode = "LIVE_STREAM_UNAVAILABLE"
        controller.failureMessage = "The requested Live source is not currently eligible."
        controller.failureRetryable = false
        var view = createPlayer(800, 600)
        verify(view)
        tryCompare(controller, "startCalls", 1)

        var message = findChild(view, "livePlayerFailureMessage")
        var retry = findChild(view, "livePlayerRetry")
        var reload = findChild(view, "livePlayerReloadEvent")
        compare(message.visible, true)
        compare(message.text, controller.failureMessage)
        compare(retry.visible, false)
        compare(reload.visible, true)

        mouseClick(reload)
        compare(liveModel.loadItemCalls, 1)
        compare(controller.routeExitedCalls, 1)
        view.destroy()
        wait(0)

        controller.state = "failed"
        controller.errorCode = "LIVE_PROVIDER_UNAVAILABLE"
        controller.failureMessage = "The Live provider is unavailable."
        controller.failureRetryable = true
        var retryableView = createPlayer(800, 600)
        verify(retryableView)
        tryCompare(controller, "startCalls", 2)
        retry = findChild(retryableView, "livePlayerRetry")
        reload = findChild(retryableView, "livePlayerReloadEvent")
        compare(retry.visible, true)
        compare(reload.visible, false)
        mouseClick(retry)
        compare(controller.startCalls, 3)
    }

    function test_stream_option_is_a_play_command() {
        var details = createTemporaryObject(detailsComponent, host, {
            "width": 900,
            "height": 700,
            "liveModel": liveModel,
            "playerController": controller,
            "providerId": providerId,
            "itemKey": itemKey
        })
        verify(details)
        streamSpy.target = details
        var streamButton = findChild(details, "liveStreamOption")
        tryVerify(function() { return streamButton && streamButton.enabled })
        streamButton.clicked()
        compare(streamSpy.count, 1)
        compare(streamSpy.signalArguments[0][0], providerId)
        compare(streamSpy.signalArguments[0][1], itemKey)
        compare(streamSpy.signalArguments[0][2], streamKey)
    }

    function test_compact_controls_stay_inside_view_data() {
        return [
            {"tag": "compact", "width": 360, "height": 640},
            {"tag": "desktop", "width": 1280, "height": 720},
            {"tag": "4k", "width": 3840, "height": 2160}
        ]
    }

    function test_compact_controls_stay_inside_view(data) {
        controller.state = "playing"
        controller.seekable = true
        controller.windowSeconds = 120
        controller.distanceFromLiveEdge = 12
        var view = createPlayer(data.width, data.height)
        verify(view)
        var controls = findChild(view, "livePlayerControls")
        var stop = findChild(view, "liveStopButton")
        verify(controls.width <= view.width)
        verify(stop.x + stop.width <= controls.width + 1)
        compare(findChild(view, "liveVolume").visible, data.width >= 700)
        compare(findChild(view, "liveFullscreenButton").visible, data.width >= 520)
    }

    function test_recovery_countdown_actions_and_compact_geometry() {
        controller.state = "reconnecting"
        controller.recovering = true
        controller.reconnectAttempt = 2
        controller.reconnectSecondsRemaining = 3
        controller.statusText = "Reconnecting"
        var view = createPlayer(360, 640)
        verify(view)
        tryCompare(controller, "startCalls", 1)

        var countdown = findChild(view, "liveReconnectCountdown")
        var retryNow = findChild(view, "liveRecoveryRetryNow")
        var cancel = findChild(view, "liveRecoveryCancel")
        compare(countdown.text, "Retrying in 3s")
        compare(retryNow.visible, true)
        compare(cancel.visible, true)
        compare(findChild(view, "livePlayerControls").visible, false)
        verify(cancel.x + cancel.width <= view.width + 1)

        mouseClick(retryNow)
        compare(controller.retryRecoveryCalls, 1)
        controller.state = "refreshing"
        controller.reconnectSecondsRemaining = 0
        controller.statusText = "Refreshing stream"
        tryCompare(retryNow, "visible", false)
        mouseClick(cancel)
        compare(controller.cancelRecoveryCalls, 1)
    }

}
