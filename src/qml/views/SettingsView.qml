import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "settingsView"
    property StackView stackView: null
    property bool warpDisclosureAccepted: false
    property string networkProtectionNotice: ""
    property string playbackHardwareNotice: ""
    property string selectedProtectionProfileId: ""
    property int importProviderIndex: 0
    property int importProviderPresetIndex: 0
    property int importForwardedPortProtocolIndex: 0
    property int importForwardedPortSourceIndex: 0

    function parseList(text) {
        return text.split(/\\s*,\\s*/).filter(function(item) { return item.length > 0 })
    }

    function listValue(objectValue, snakeKey, camelKey) {
        if (!objectValue) {
            return []
        }
        var value = objectValue[snakeKey]
        if (value === undefined && camelKey !== "") {
            value = objectValue[camelKey]
        }
        return value === undefined || value === null ? [] : value
    }

    function fieldValue(objectValue, snakeKey, camelKey) {
        if (!objectValue) {
            return ""
        }
        var value = objectValue[camelKey]
        if (value === undefined && snakeKey !== "") {
            value = objectValue[snakeKey]
        }
        return value === undefined || value === null ? "" : value
    }

    function managerPreferenceState() {
        var value = apiClient.mediaManagerPreferences.preferences
        if (value === undefined || value === null) {
            value = apiClient.mediaManagerPreferences.preferencesState
        }
        return value || {}
    }

    function managerProvidersFor(type) {
        var providers = listValue(apiClient.mediaManagerPreferences, type + "_providers", type + "Providers")
        var options = [{ label: "Auto-select", value: "" }]
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var label = provider.label
            if (label === undefined || label === "") {
                label = provider.instance_name !== undefined ? provider.instance_name : provider.instanceName
            }
            var providerId = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            options.push({ label: label, value: String(providerId || "") })
        }
        return options
    }

    function sourceProvidersFor(type) {
        var providers = listValue(apiClient.mediaManagerPreferences, type + "_source_providers", type + "SourceProviders")
        if (providers.length === 0) {
            if (type === "movie") {
                providers = listValue(apiClient.mediaManagerPreferences, "movies_source_candidates", "movieSourceProviders")
            } else if (type === "series") {
                providers = listValue(apiClient.mediaManagerPreferences, "tv_source_candidates", "seriesSourceProviders")
            } else {
                providers = listValue(apiClient.mediaManagerPreferences, "anime_source_candidates", "animeSourceProviders")
            }
        }
        var options = [{ label: "Auto-select", value: "" }]
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var label = provider.label
            if (label === undefined || label === "") {
                label = provider.instance_name !== undefined ? provider.instance_name : provider.instanceName
            }
            var providerId = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            options.push({ label: label, value: String(providerId || "") })
        }
        return options
    }

    function suiteRouteValue() {
        return "suite:default"
    }

    function suiteRouteLabel() {
        return "Elixir Extension Suite"
    }

    function routeValue(kind, providerId) {
        var id = String(providerId || "")
        if (kind === "suite") {
            return suiteRouteValue()
        }
        return id === "" ? "" : (kind + ":" + id)
    }

    function routeKind(value) {
        var text = String(value || "")
        var index = text.indexOf(":")
        return index > 0 ? text.substring(0, index) : ""
    }

    function routeProviderId(value) {
        var text = String(value || "")
        var index = text.indexOf(":")
        return index > 0 ? text.substring(index + 1) : ""
    }

    function routeOptionsFor(type) {
        var options = [{ label: "Auto-select", value: "" }]
        if (hasSourceSuiteFor(type)) {
            options.push({ label: suiteRouteLabel(), value: suiteRouteValue() })
        }
        var managers = managerProvidersFor(type)
        for (var j = 1; j < managers.length; ++j) {
            options.push({ label: managers[j].label, value: routeValue("manager", managers[j].value) })
        }
        return options
    }

    function sourceOptionExists(type, providerId) {
        var id = String(providerId || "")
        if (id === "") {
            return false
        }
        var sources = sourceProvidersFor(type)
        for (var i = 1; i < sources.length; ++i) {
            if (String(sources[i].value || "") === id) {
                return true
            }
        }
        return false
    }

    function hasSourceSuiteFor(type) {
        return sourceProvidersFor(type).length > 1
    }

    function suiteBackingSourceProviderFor(type) {
        var source = sourcePreferenceFor(type)
        if (sourceOptionExists(type, source)) {
            return source
        }
        var sources = sourceProvidersFor(type)
        return sources.length > 1 ? String(sources[1].value || "") : ""
    }

    function managerPreferenceFor(type) {
        var pref = managerPreferenceState()
        if (type === "movie") {
            return String(pref.movie_provider_id || pref.movieProviderId || "")
        }
        if (type === "series") {
            return String(pref.series_provider_id || pref.seriesProviderId || "")
        }
        return String(pref.anime_provider_id || pref.animeProviderId || "")
    }

    function sourcePreferenceFor(type) {
        var pref = managerPreferenceState()
        if (type === "movie") {
            return String(pref.movie_source_provider_id || pref.movieSourceProviderId || "")
        }
        if (type === "series") {
            return String(pref.series_source_provider_id || pref.seriesSourceProviderId || "")
        }
        return String(pref.anime_source_provider_id || pref.animeSourceProviderId || "")
    }

    function routePreferenceFor(type) {
        var source = sourcePreferenceFor(type)
        if (sourceOptionExists(type, source)) {
            return suiteRouteValue()
        }
        var manager = managerPreferenceFor(type)
        if (manager !== "") {
            return routeValue("manager", manager)
        }
        return ""
    }

    function languagePreferenceState() {
        var pref = managerPreferenceState()
        var value = pref.languagePreference || pref.language_preference || ({})
        return value || {}
    }

    function languagePreferenceMode() {
        return String(languagePreferenceState().mode || "off")
    }

    function languagePreferenceModeIndex() {
        var mode = languagePreferenceMode()
        if (mode === "prefer") {
            return 1
        }
        if (mode === "require_review") {
            return 2
        }
        return 0
    }

    function languagePreferenceRule(kind) {
        var pref = languagePreferenceState()
        var value = pref[kind] || ({})
        return value || {}
    }

    function languageRuleHasAudio(kind, language, defaultValue) {
        var values = languagePreferenceRule(kind).audio || []
        if (!values || values.length === 0) {
            return defaultValue
        }
        var needle = String(language || "").toLowerCase()
        for (var i = 0; i < values.length; ++i) {
            if (String(values[i] || "").toLowerCase() === needle) {
                return true
            }
        }
        return false
    }

    function languageRuleHasProfile(kind, profile, defaultValue) {
        var values = languagePreferenceRule(kind).profiles || []
        if (!values || values.length === 0) {
            return defaultValue
        }
        var needle = String(profile || "").toLowerCase()
        for (var i = 0; i < values.length; ++i) {
            if (String(values[i] || "").toLowerCase() === needle) {
                return true
            }
        }
        return false
    }

    function languagePreferenceForSave() {
        var modeValues = ["off", "prefer", "require_review"]
        var mode = modeValues[Math.max(0, Math.min(languageModeCombo.currentIndex, modeValues.length - 1))]
        var movieAudio = movieEnglishAudioCheck.checked ? ["en"] : []
        var tvAudio = seriesEnglishAudioCheck.checked ? ["en"] : []
        var animeProfiles = []
        if (animeJaEnSubsCheck.checked) {
            animeProfiles.push("ja_audio_en_subs")
        }
        if (animeDualAudioCheck.checked) {
            animeProfiles.push("dual_audio")
        }
        if (animeEnglishAudioCheck.checked) {
            animeProfiles.push("en_audio")
        }
        return {
            mode: mode,
            movie: { audio: movieAudio },
            tv: { audio: tvAudio },
            anime: { profiles: animeProfiles },
            unknownLanguage: mode === "require_review" ? "require_review" : "allow_lower_priority"
        }
    }

    function streamHttpEgressPolicy() {
        var pref = managerPreferenceState()
        return String(pref.streamHttpEgressPolicy || pref.stream_http_egress_policy || "auto_http_only")
    }

    function streamHttpEgressPolicyIndex() {
        var policy = streamHttpEgressPolicy()
        if (policy === "always_protected") {
            return 1
        }
        if (policy === "direct_only") {
            return 2
        }
        return 0
    }

    function saveStreamHttpEgressPolicy() {
        var policy = streamEgressCombo.currentValue !== undefined
                   ? String(streamEgressCombo.currentValue)
                   : "auto_http_only"
        apiClient.updateStreamHttpEgressPolicy(policy)
    }

    function sourceSuiteProviders() {
        return listValue(apiClient.mediaManagerPreferences, "source_suite_providers", "sourceSuiteProviders")
    }

    function sourceSuiteProviderCapability(provider) {
        return String(fieldValue(provider, "capability", "capability") || "")
    }

    function sourceSuiteProviderLane(provider) {
        return sourceSuiteProviderCapability(provider) === "acquisition.stream_candidate_provider"
               ? "stream"
               : "release"
    }

    function sourceSuiteProviderLaneLabel(provider) {
        return sourceSuiteProviderLane(provider) === "stream" ? "stream source" : "release source"
    }

    function sourceSuiteProviderSummaryText() {
        var providers = sourceSuiteProviders()
        if (providers.length === 0) {
            return "No suite providers are installed or registered."
        }
        var releaseCount = 0
        var streamCount = 0
        var moduleCount = 0
        var healthyModules = 0
        var enabledModules = 0
        for (var i = 0; i < providers.length; ++i) {
            if (sourceSuiteProviderLane(providers[i]) === "stream") {
                streamCount += 1
            } else {
                releaseCount += 1
            }
            var modules = sourceSuiteProviderModules(providers[i])
            moduleCount += modules.length
            for (var j = 0; j < modules.length; ++j) {
                if (fieldValue(modules[j], "enabled", "enabled") === true) {
                    enabledModules += 1
                }
                if (String(fieldValue(modules[j], "health_state", "healthState") || "") === "healthy") {
                    healthyModules += 1
                }
            }
        }
        var parts = []
        parts.push(releaseCount + " release " + (releaseCount === 1 ? "provider" : "providers"))
        parts.push(streamCount + " stream " + (streamCount === 1 ? "provider" : "providers"))
        if (moduleCount > 0) {
            parts.push(healthyModules + " healthy / " + enabledModules + " enabled source modules")
        }
        return parts.join(" | ")
    }

    function sourceSuiteProviderLabel(provider) {
        var label = fieldValue(provider, "label", "label")
        if (label !== "") {
            return String(label)
        }
        var instanceName = fieldValue(provider, "instance_name", "instanceName")
        var implementation = fieldValue(provider, "implementation", "implementation")
        if (instanceName !== "" && implementation !== "") {
            return String(instanceName) + " (" + String(implementation) + ")"
        }
        return String(instanceName || fieldValue(provider, "provider_id", "providerId") || "Provider")
    }

    function sourceSuiteMediaLabel(provider) {
        var values = listValue(provider, "media_types", "mediaTypes")
        if (!values || values.length === 0) {
            return "media: unknown"
        }
        return "media: " + values.join(", ")
    }

    function sourceSuiteProviderHealth(provider) {
        return String(fieldValue(provider, "health_state", "healthState") || "unknown")
    }

    function sourceSuiteProviderEnabled(provider) {
        return fieldValue(provider, "enabled", "enabled") === true
    }

    function sourceSuiteProviderLastError(provider) {
        return String(fieldValue(provider, "last_error", "lastError") || "")
    }

    function sourceSuiteProviderModules(provider) {
        return listValue(provider, "source_modules", "sourceModules")
    }

    function sourceSuiteProviderModuleSummary(provider) {
        var modules = sourceSuiteProviderModules(provider)
        if (!modules || modules.length === 0) {
            return ""
        }
        var enabled = 0
        var healthy = 0
        for (var i = 0; i < modules.length; i++) {
            if (fieldValue(modules[i], "enabled", "enabled") === true) {
                enabled += 1
            }
            if (String(fieldValue(modules[i], "health_state", "healthState") || "") === "healthy") {
                healthy += 1
            }
        }
        return "modules: " + healthy + " healthy / " + enabled + " enabled"
    }

    function sourceSuiteProviderModuleDetail(provider) {
        var modules = sourceSuiteProviderModules(provider)
        if (!modules || modules.length === 0) {
            return ""
        }
        var labels = []
        for (var i = 0; i < modules.length && i < 4; i++) {
            var module = modules[i]
            var name = String(fieldValue(module, "name", "name") ||
                              fieldValue(module, "id", "id") || "Source")
            var health = String(fieldValue(module, "health_state", "healthState") || "unknown")
            labels.push(name + " (" + health + ")")
        }
        if (modules.length > labels.length) {
            labels.push("+" + (modules.length - labels.length))
        }
        return "Modules: " + labels.join(", ")
    }

    function sourceSuiteModuleLabel(module) {
        return String(fieldValue(module, "name", "name") ||
                      fieldValue(module, "id", "id") ||
                      "Source module")
    }

    function sourceSuiteModuleTypeLabel(module) {
        var value = String(fieldValue(module, "module_type", "moduleType") || "")
        return value === "" ? "source" : value.replace(/_/g, " ")
    }

    function sourceSuiteModuleHealth(module) {
        return String(fieldValue(module, "health_state", "healthState") || "unknown")
    }

    function sourceSuiteModuleEnabled(module) {
        return fieldValue(module, "enabled", "enabled") === true
    }

    function sourceSuiteModuleLastError(module) {
        return String(fieldValue(module, "last_error", "lastError") ||
                      fieldValue(module, "unsupported_reason", "unsupportedReason") ||
                      "")
    }

    function sourceSuiteModuleBorderColor(module) {
        var health = sourceSuiteModuleHealth(module)
        if (!sourceSuiteModuleEnabled(module)) {
            return Theme.border
        }
        if (health === "healthy") {
            return Theme.accentSuccess
        }
        if (health === "missing_account" || health === "unsupported" || health === "unhealthy") {
            return Theme.accent
        }
        return Theme.border
    }

    function sourceSuiteProviderInstanceId(provider) {
        return String(fieldValue(provider, "instance_id", "instanceId") || "")
    }

    function valueOrDash(value) {
        if (value === undefined || value === null || String(value).trim() === "") {
            return "-"
        }
        return String(value)
    }

    function titleLabel(value) {
        var text = String(value || "").replace(/_/g, " ").replace(/-/g, " ")
        if (text === "") {
            return "Unknown"
        }
        return text.charAt(0).toUpperCase() + text.slice(1)
    }

    function playbackHardwareReadiness() {
        return apiClient.playbackHardwareReadiness || {}
    }

    function playbackHardwareCapabilities() {
        var readiness = root.playbackHardwareReadiness()
        return readiness.capabilities || {}
    }

    function playbackHardwareRecords() {
        var readiness = root.playbackHardwareReadiness()
        return readiness.records || []
    }

    function playbackHardwareWarnings() {
        return apiClient.playbackHardwareWarnings || []
    }

    function playbackHardwareAvailableApis() {
        var capabilities = root.playbackHardwareCapabilities()
        return capabilities.available_apis || capabilities.availableApis || []
    }

    function playbackHardwareRecordKey(record) {
        return root.valueOrDash(record.api) + " | " + root.valueOrDash(record.gpu_model || record.gpuModel)
    }

    function playbackHardwareStatusLabel(status) {
        return root.titleLabel(status)
    }

    function playbackHardwareStatusColor(status) {
        if (status === "available") {
            return Theme.accentSuccess
        }
        if (status === "disabled_by_config" || status === "not_applicable") {
            return Theme.textMuted
        }
        if (status === "driver_too_old" || status === "driver_runtime_incompatible" ||
                status === "ffmpeg_missing_support" || status === "permission_denied") {
            return Theme.accent
        }
        return Theme.accentDanger
    }

    function playbackHardwareMessage(item) {
        var code = String(item.user_message_code || item.userMessageCode || "")
        if (code === "hardware_acceleration_available") {
            return "Hardware acceleration is ready on this accelerator."
        }
        if (code === "hardware_acceleration_disabled") {
            return "Hardware acceleration is disabled in server configuration."
        }
        if (code === "nvidia_driver_update_required") {
            return "Update the NVIDIA driver on this server, then let Elixir refresh hardware readiness."
        }
        if (code === "amd_driver_update_required") {
            return "Update the AMD graphics driver on this server, then let Elixir refresh hardware readiness."
        }
        if (code === "hardware_driver_update_required") {
            return "Update the graphics driver on this server, then let Elixir refresh hardware readiness."
        }
        if (code === "ffmpeg_hardware_support_missing") {
            return "The server FFmpeg build does not include the required hardware encoder or decoder."
        }
        if (code === "linux_render_device_permission_denied" || code === "hardware_device_permission_denied") {
            return "The server cannot access the hardware device. Check render-device permissions for the Elixir service account."
        }
        if (code === "hardware_acceleration_unsupported_gpu") {
            return "This GPU does not expose a supported hardware video path."
        }
        if (code === "hardware_device_busy") {
            return "The hardware encoder is busy or has reached its session limit."
        }
        if (code === "hardware_probe_timeout") {
            return "The hardware probe timed out. Elixir will use software until the next successful readiness refresh."
        }
        if (code === "hardware_acceleration_not_applicable") {
            return "This accelerator does not apply to the current OS and GPU combination."
        }
        var reason = String(item.status_reason || item.statusReason || "")
        return reason === "" ? "Hardware readiness has not reported a detailed reason." : root.titleLabel(reason)
    }

    function playbackHardwareSummary() {
        var readiness = root.playbackHardwareReadiness()
        if (apiClient.playbackHardwareLoading && !readiness.host_fingerprint && !readiness.hostFingerprint) {
            return "Checking server hardware acceleration."
        }
        if (readiness.enabled === false) {
            return "Hardware acceleration is disabled on this server."
        }
        var records = root.playbackHardwareRecords()
        if (records.length === 0) {
            return "Hardware readiness has not completed yet. Playback will use software until checks finish."
        }
        var warnings = root.playbackHardwareWarnings()
        if (warnings.length > 0) {
            return root.playbackHardwareMessage(warnings[0])
        }
        var available = root.playbackHardwareAvailableApis()
        if (available.length > 0) {
            return "Hardware acceleration ready: " + available.join(", ") + "."
        }
        return "No hardware accelerator is currently available. Playback will use software."
    }

    function refreshPlaybackHardware() {
        root.playbackHardwareNotice = ""
        apiClient.refreshPlaybackHardwareStatus(false)
    }

    function portForwardingLabel(value) {
        var mode = String(value || "")
        if (mode === "unsupported") {
            return "No forwarded port"
        }
        if (mode === "provider_api") {
            return "Provider API"
        }
        return root.titleLabel(mode)
    }

    function activeProtectionProfile() {
        var status = apiClient.networkProtectionStatus || {}
        return status.activeProfile || status.active_profile || {}
    }

    function protectionBlocker() {
        var status = apiClient.networkProtectionStatus || {}
        return status.blocker || {}
    }

    function protectionChecks() {
        var status = apiClient.networkProtectionStatus || {}
        return status.checks || []
    }

    function protectedAppsLabel() {
        var status = apiClient.networkProtectionStatus || {}
        var apps = status.protectedApps || status.protected_apps || []
        if (!apps || apps.length === 0) {
            return "None"
        }
        return apps.join(", ")
    }

    function torrentReachability() {
        var status = apiClient.networkProtectionStatus || {}
        return status.torrentReachability || status.torrent_reachability || {}
    }

    function torrentReachabilityDetail() {
        var reachability = root.torrentReachability()
        var port = reachability.forwardedPort || reachability.forwarded_port || null
        if (port && port.port !== undefined && port.port !== null) {
            var protocol = root.valueOrDash(port.protocol || "tcp").toUpperCase()
            return "Forwarded " + protocol + " port " + port.port + " is observed for torrent reachability."
        }
        return reachability.detail || ""
    }

    function listenPortSyncDetail() {
        var plan = apiClient.networkProtectionListenPortSyncPlan || {}
        if (plan.targetPort !== undefined && plan.targetPort !== null) {
            return "qBittorrent listen-port sync target: " + plan.targetPort + ". " + (plan.detail || "")
        }
        return plan.detail || ""
    }

    function listenPortSyncReady() {
        var plan = apiClient.networkProtectionListenPortSyncPlan || {}
        return String(plan.status || "") === "ready" && plan.targetPort !== undefined && plan.targetPort !== null
    }

    function providerPresets() {
        var catalog = apiClient.networkProtectionProviderPresets || {}
        return catalog.presets || []
    }

    function presetMethods(preset) {
        return root.listValue(preset || {}, "import_methods", "importMethods")
    }

    function presetHasMethod(preset, method) {
        var methods = root.presetMethods(preset)
        for (var i = 0; i < methods.length; ++i) {
            if (String(methods[i]) === method) {
                return true
            }
        }
        return false
    }

    function presetSupportsWireGuard(preset) {
        return root.presetHasMethod(preset, "wireguard_conf") ||
               root.presetHasMethod(preset, "paste_conf") ||
               root.presetHasMethod(preset, "upload_conf")
    }

    function presetSupportsOpenVpn(preset) {
        return root.presetHasMethod(preset, "openvpn_conf") ||
               root.presetHasMethod(preset, "upload_ovpn")
    }

    function importPresetOptions() {
        var presets = root.providerPresets()
        var options = []
        for (var i = 0; i < presets.length; ++i) {
            var preset = presets[i]
            if (!root.presetSupportsWireGuard(preset) && !root.presetSupportsOpenVpn(preset)) {
                continue
            }
            var forwarding = preset.portForwarding || preset.port_forwarding || "unknown"
            options.push({
                label: root.valueOrDash(preset.name) + " (" + root.portForwardingLabel(forwarding) + ")",
                value: String(preset.id || ""),
                preset: preset
            })
        }
        if (options.length === 0) {
            options.push({
                label: "Custom WireGuard (Manual)",
                value: "custom-wireguard",
                preset: {
                    id: "custom-wireguard",
                    name: "Custom WireGuard",
                    provider: "custom",
                    importMethods: ["paste_conf"],
                    portForwarding: "manual",
                    notes: []
                }
            })
            options.push({
                label: "Custom OpenVPN (Manual)",
                value: "custom-openvpn",
                preset: {
                    id: "custom-openvpn",
                    name: "Custom OpenVPN",
                    provider: "custom",
                    importMethods: ["upload_ovpn"],
                    portForwarding: "manual",
                    notes: []
                }
            })
        }
        return options
    }

    function selectedImportPreset() {
        var options = root.importPresetOptions()
        if (root.importProviderPresetIndex >= 0 && root.importProviderPresetIndex < options.length) {
            return options[root.importProviderPresetIndex].preset || {}
        }
        return {}
    }

    function selectedImportProvider() {
        var preset = root.selectedImportPreset()
        return String(preset.provider || "")
    }

    function selectedImportForwardingMode() {
        var preset = root.selectedImportPreset()
        return String(preset.portForwarding || preset.port_forwarding || "")
    }

    function importForwardedPortEnabled() {
        var mode = root.selectedImportForwardingMode()
        return mode === "manual" || mode === "provider_api"
    }

    function importForwardedPortValue() {
        if (!root.importForwardedPortEnabled()) {
            return 0
        }
        var raw = parseInt(importForwardedPort.text, 10)
        if (isNaN(raw) || raw <= 0 || raw > 65535) {
            return 0
        }
        return raw
    }

    function selectedForwardedPortProtocol() {
        return root.importForwardedPortProtocolIndex === 1 ? "udp" : "tcp"
    }

    function selectedForwardedPortSource() {
        return root.importForwardedPortSourceIndex === 1 ? "provider_api" : "manual"
    }

    function importKindSupported(index) {
        var preset = root.selectedImportPreset()
        if (Object.keys(preset).length === 0) {
            return true
        }
        return index === 0 ? root.presetSupportsWireGuard(preset) : root.presetSupportsOpenVpn(preset)
    }

    function applyImportPresetSelection() {
        var preset = root.selectedImportPreset()
        if (Object.keys(preset).length === 0) {
            return
        }
        if (!root.importKindSupported(root.importProviderIndex)) {
            root.importProviderIndex = root.presetSupportsWireGuard(preset) ? 0 : 1
        }
        root.importForwardedPortSourceIndex = root.selectedImportForwardingMode() === "provider_api" ? 1 : 0
    }

    function importPresetDetail() {
        var preset = root.selectedImportPreset()
        if (Object.keys(preset).length === 0) {
            return ""
        }
        var notes = preset.notes || []
        var text = root.valueOrDash(preset.name) + ": " + root.portForwardingLabel(root.selectedImportForwardingMode())
        if (notes.length > 0) {
            text += ". " + notes[0]
        }
        return text
    }

    function protectionProfiles() {
        var catalog = apiClient.networkProtectionProfiles || {}
        return catalog.profiles || []
    }

    function protectionProfileOptions() {
        var profiles = root.protectionProfiles()
        var options = []
        for (var i = 0; i < profiles.length; ++i) {
            var profile = profiles[i]
            options.push({
                label: root.valueOrDash(profile.name) + " (" + root.titleLabel(profile.kind) + ")",
                value: String(profile.id || "")
            })
        }
        if (options.length === 0) {
            var active = root.activeProtectionProfile()
            if (active.id !== undefined && String(active.id) !== "") {
                options.push({
                    label: root.valueOrDash(active.name) + " (" + root.titleLabel(active.kind) + ")",
                    value: String(active.id)
                })
            }
        }
        return options
    }

    function selectedProtectionTargetId() {
        if (providerSwitchCombo.currentValue !== undefined && String(providerSwitchCombo.currentValue) !== "") {
            return String(providerSwitchCombo.currentValue)
        }
        return root.selectedProtectionProfileId
    }

    function warpDiagnosticChecks() {
        var diagnostics = apiClient.networkProtectionWarpDiagnostics || {}
        return diagnostics.checks || []
    }

    function networkEvents() {
        var diagnostics = apiClient.networkProtectionWarpDiagnostics || {}
        return diagnostics.recentEvents || diagnostics.recent_events || []
    }

    function importChecks() {
        var result = apiClient.networkProtectionImportResult || {}
        return result.checks || []
    }

    function routeRecords() {
        var routes = apiClient.downloadBrokerRoutes || {}
        return routes.routes || []
    }

    function routeLabel(route) {
        var owner = root.routeOwnerLabel(route)
        var role = root.titleLabel(route.role)
        var binding = root.titleLabel(route.bindingKind || route.binding_kind)
        var selected = route.selectedProviderId || route.selected_provider_id || ""
        var suffix = route.inherited ? " inherited" : ""
        if (selected !== "") {
            return owner + " " + role + ": " + binding + suffix + " selected"
        }
        return owner + " " + role + ": " + binding + suffix
    }

    function routeOwnerId(route) {
        return String(route.ownerId || route.owner_id || "default")
    }

    function routeOwnerLabel(route) {
        var ownerId = root.routeOwnerId(route)
        if (ownerId === "default") {
            return "Default"
        }
        return root.valueOrDash(route.ownerLabel || route.owner_label || ownerId)
    }

    function routeProviderLabel(route) {
        var providerKind = route.selectedProviderKind || route.selected_provider_kind || ""
        var extensionId = route.selectedExtensionId || route.selected_extension_id || ""
        if (extensionId !== "") {
            return root.titleLabel(providerKind) + " via " + extensionId
        }
        return root.titleLabel(providerKind)
    }

    function routeChecks(route) {
        return route.checks || []
    }

    function routeCanUseManaged(route) {
        var role = String(route.role || "")
        return role === "torrent" || role === "usenet"
    }

    function routeCanUseDebrid(route) {
        return String(route.role || "") === "debrid_resolver"
    }

    function reachabilityToneColor(state) {
        if (state === "forwarded_port") {
            return Theme.accent
        }
        if (state === "no_forwarded_port" || state === "unknown") {
            return "#E6B85C"
        }
        return Theme.textPrimary
    }

    function protectionToneColor(state) {
        if (state === "blocked") {
            return "#D96B6B"
        }
        if (state === "direct" || state === "externally_managed") {
            return "#E6B85C"
        }
        return Theme.accent
    }

    function refreshNetworkProtection() {
        apiClient.fetchNetworkProtectionStatus()
        apiClient.fetchNetworkProtectionProfiles()
        apiClient.fetchNetworkProtectionWarpDisclosure()
        apiClient.fetchNetworkProtectionWarpDiagnostics()
        apiClient.fetchNetworkProtectionProviderPresets()
        apiClient.fetchNetworkProtectionListenPortSyncPlan()
        apiClient.fetchDownloadBrokerRoutes()
    }

    function optionIndexForValue(options, value) {
        var needle = String(value || "")
        for (var i = 0; i < options.length; ++i) {
            if (String(options[i].value || "") === needle) {
                return i
            }
        }
        return 0
    }

    function saveManagerPreferences() {
        var movieRoute = movieRouteCombo.currentValue !== undefined ? String(movieRouteCombo.currentValue) : ""
        var seriesRoute = seriesRouteCombo.currentValue !== undefined ? String(seriesRouteCombo.currentValue) : ""
        var animeRoute = animeRouteCombo.currentValue !== undefined ? String(animeRouteCombo.currentValue) : ""
        apiClient.updateManagerPreferences(
                    routeKind(movieRoute) === "manager" ? routeProviderId(movieRoute) : "",
                    routeKind(seriesRoute) === "manager" ? routeProviderId(seriesRoute) : "",
                    routeKind(animeRoute) === "manager" ? routeProviderId(animeRoute) : "",
                    routeKind(movieRoute) === "suite" ? suiteBackingSourceProviderFor("movie")
                        : (routeKind(movieRoute) === "source" ? routeProviderId(movieRoute) : ""),
                    routeKind(seriesRoute) === "suite" ? suiteBackingSourceProviderFor("series")
                        : (routeKind(seriesRoute) === "source" ? routeProviderId(seriesRoute) : ""),
                    routeKind(animeRoute) === "suite" ? suiteBackingSourceProviderFor("anime")
                        : (routeKind(animeRoute) === "source" ? routeProviderId(animeRoute) : ""),
                    root.languagePreferenceForSave())
    }

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchExtensionsCatalog()
            apiClient.fetchManagerPreferences()
            root.refreshNetworkProtection()
            root.refreshPlaybackHardware()
        }
    }

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchExtensionsCatalog()
                apiClient.fetchManagerPreferences()
                root.refreshNetworkProtection()
                root.refreshPlaybackHardware()
            }
        }

        function onNetworkProtectionChanged() {
            var warp = apiClient.networkProtectionWarpProfile || {}
            var blocker = warp.blocker || {}
            if (blocker.code !== undefined && blocker.code !== "") {
                root.networkProtectionNotice = blocker.detail || blocker.title || ""
            }
            var result = apiClient.networkProtectionSwitchResult || {}
            var resultBlocker = result.blocker || {}
            if (resultBlocker.code !== undefined && resultBlocker.code !== "") {
                root.networkProtectionNotice = resultBlocker.detail || resultBlocker.title || ""
            }
            var imported = apiClient.networkProtectionImportResult || {}
            var importBlocker = imported.blocker || {}
            if (importBlocker.code !== undefined && importBlocker.code !== "") {
                root.networkProtectionNotice = importBlocker.detail || importBlocker.title || ""
            } else if (imported.profile !== undefined && imported.profile.id !== undefined) {
                root.networkProtectionNotice = "Imported " + root.valueOrDash(imported.profile.name) + "."
                root.selectedProtectionProfileId = String(imported.profile.id || "")
            }
        }

        function onRequestFailed(endpoint, error) {
            if (endpoint.indexOf("/api/v1/network/protection") === 0 ||
                    endpoint.indexOf("/api/v1/download-broker/routes") === 0) {
                root.networkProtectionNotice = error
            } else if (endpoint.indexOf("/api/v1/playback/hardware") === 0) {
                root.playbackHardwareNotice = error
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Theme.spacingXLarge * 2
        clip: true

        ColumnLayout {
            id: contentColumn
            x: Theme.spacingXLarge
            y: Theme.spacingXLarge
            width: Math.max(0, parent.width - Theme.spacingXLarge * 2)
            spacing: Theme.spacingLarge

            Label {
                text: "Settings"
                color: Theme.textPrimary
                font.pixelSize: 24
                font.family: Theme.fontDisplay
            }

            Rectangle {
                id: card
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: cardContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: cardContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                Label {
                    text: "Server"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                TextField {
                    text: sessionManager.baseUrl
                    placeholderText: "http://192.168.1.10:44301"
                    onTextChanged: sessionManager.baseUrl = text
                }

                Label {
                    text: "Network profile"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    model: ["auto", "lan", "wan"]
                    currentIndex: model.indexOf(sessionManager.networkType)
                    onActivated: sessionManager.networkType = model[index]
                }

                Label {
                    text: "Control plane URL"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    text: sessionManager.registryUrl
                    placeholderText: "https://control.elixir.media"
                    onTextChanged: sessionManager.registryUrl = text
                }

                Label {
                    text: controlPlaneClient.authToken !== "" ? "Control plane authenticated" : "Control plane not signed in"
                    color: controlPlaneClient.authToken !== "" ? Theme.accent : Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Discovery"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                RowLayout {
                    spacing: Theme.spacingSmall

                    Button {
                        text: "Refresh LAN"
                        onClicked: serverDiscovery.refreshMdns()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Refresh registry"
                        enabled: controlPlaneClient.authToken !== ""
                        onClicked: serverDiscovery.refreshRegistry()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Probe"
                        onClicked: serverDiscovery.probeAll()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 260
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Local servers"
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                        }

                        Repeater {
                            model: serverDiscovery.mdnsModel
                            delegate: ServerListItem {
                                Layout.fillWidth: true
                                name: model.name
                                source: model.source
                                status: model.status
                                lastSeenAt: model.lastSeenAt
                                selectedEndpoint: model.selectedEndpoint
                                selectedNetwork: model.selectedNetwork
                                selectedReachable: model.selectedReachable
                                onUseRequested: function(endpoint, network) {
                                    sessionManager.baseUrl = endpoint
                                    if (network !== "") {
                                        sessionManager.networkType = network
                                    }
                                    sessionManager.clearAuth()
                                    if (root.stackView) {
                                        root.stackView.clear()
                                        root.stackView.push(Qt.resolvedUrl("ConnectServerView.qml"), { stackView: root.stackView })
                                    }
                                }
                            }
                        }

                        Label {
                            text: "No local servers yet."
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: serverDiscovery.mdnsModel.count === 0
                        }

                        Rectangle {
                            height: 1
                            color: Theme.border
                            Layout.fillWidth: true
                        }

                        Label {
                            text: "Registry servers"
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                        }

                        Label {
                            text: controlPlaneClient.authToken === "" ? "Sign in to the control plane to load registry servers." : ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: controlPlaneClient.authToken === ""
                        }

                        Repeater {
                            model: serverDiscovery.registryModel
                            delegate: ServerListItem {
                                Layout.fillWidth: true
                                name: model.name
                                source: model.source
                                status: model.status
                                lastSeenAt: model.lastSeenAt
                                selectedEndpoint: model.selectedEndpoint
                                selectedNetwork: model.selectedNetwork
                                selectedReachable: model.selectedReachable
                                onUseRequested: function(endpoint, network) {
                                    sessionManager.baseUrl = endpoint
                                    if (network !== "") {
                                        sessionManager.networkType = network
                                    }
                                    sessionManager.clearAuth()
                                    if (root.stackView) {
                                        root.stackView.clear()
                                        root.stackView.push(Qt.resolvedUrl("ConnectServerView.qml"), { stackView: root.stackView })
                                    }
                                }
                            }
                        }

                        Label {
                            text: "No registry servers yet."
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: serverDiscovery.registryModel.count === 0
                        }
                    }
                }

                InlineToast {
                    text: serverDiscovery.statusMessage
                    autoClear: false
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontBody
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Network Protection"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Theme.spacingLarge
                    rowSpacing: Theme.spacingSmall

                    Label {
                        text: "Download protection"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: root.titleLabel(apiClient.networkProtectionStatus.state)
                        color: root.protectionToneColor(apiClient.networkProtectionStatus.state)
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        font.weight: Font.DemiBold
                    }

                    Label {
                        text: "Profile"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: root.valueOrDash(root.activeProtectionProfile().name)
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: "Mode"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: root.titleLabel(apiClient.networkProtectionStatus.mode)
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: "Protected apps"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: root.protectedAppsLabel()
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "Torrent reachability"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: root.titleLabel(root.torrentReachability().state)
                        color: root.reachabilityToneColor(root.torrentReachability().state)
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Label {
                    text: root.torrentReachabilityDetail()
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
                    visible: text !== ""
                    Layout.fillWidth: true
                }

                Label {
                    text: root.listenPortSyncDetail()
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
                    visible: text !== ""
                    Layout.fillWidth: true
                }

                Button {
                    text: "Sync qB listen port"
                    visible: root.listenPortSyncReady()
                    enabled: apiClient.authToken !== "" && root.listenPortSyncReady() && !apiClient.networkProtectionLoading
                    onClicked: apiClient.applyNetworkProtectionListenPortSync()
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.enabled ? Theme.accent : Theme.backgroundCardRaised
                        border.color: parent.enabled ? "transparent" : Theme.border
                    }
                    contentItem: Label {
                        text: parent.text
                        color: parent.enabled ? "#17120A" : Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Label {
                    text: root.protectionBlocker().detail || ""
                    color: "#D96B6B"
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
                    visible: text !== ""
                    Layout.fillWidth: true
                }

                Label {
                    text: root.networkProtectionNotice
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
                    visible: text !== ""
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Button {
                        text: "Refresh status"
                        enabled: apiClient.authToken !== "" && !apiClient.networkProtectionLoading
                        onClicked: root.refreshNetworkProtection()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    BusyIndicator {
                        running: apiClient.networkProtectionLoading
                        visible: running
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                    }
                }

                Label {
                    text: "First-run choice"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Theme.spacingSmall
                    rowSpacing: Theme.spacingSmall

                    Button {
                        text: "Protected downloads"
                        enabled: apiClient.authToken !== "" && root.warpDisclosureAccepted && !apiClient.networkProtectionLoading
                        Layout.fillWidth: true
                        onClicked: {
                            root.networkProtectionNotice = ""
                            apiClient.applyFirstRunDownloadSetup("protected_downloads", true)
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: parent.enabled ? Theme.accent : Theme.backgroundCardRaised
                            border.color: parent.enabled ? "transparent" : Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: parent.enabled ? "#17120A" : Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Existing stack"
                        enabled: apiClient.authToken !== "" && !apiClient.networkProtectionLoading
                        Layout.fillWidth: true
                        onClicked: {
                            root.networkProtectionNotice = "Elixir will use external download clients and will not manage downloader VPN for this stack."
                            apiClient.applyFirstRunDownloadSetup("existing_stack", false)
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Custom VPN"
                        enabled: apiClient.authToken !== "" && !apiClient.networkProtectionLoading
                        Layout.fillWidth: true
                        onClicked: {
                            root.networkProtectionNotice = "Paste a WireGuard or OpenVPN profile below, then switch provider."
                            apiClient.applyFirstRunDownloadSetup("custom_vpn", false)
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: parent.enabled ? Theme.textPrimary : Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Skip downloads"
                        enabled: apiClient.authToken !== "" && !apiClient.networkProtectionLoading
                        Layout.fillWidth: true
                        onClicked: {
                            root.networkProtectionNotice = "Elixir will leave downloads unconfigured for now and keep playback/direct streaming separate."
                            apiClient.applyFirstRunDownloadSetup("skip_downloads", false)
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: parent.enabled ? Theme.textPrimary : Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                CheckBox {
                    id: warpDisclosureCheck
                    text: (apiClient.networkProtectionWarpDisclosure.requiredAcceptance || "I understand that WARP is a Cloudflare-powered best-effort downloader protection mode.")
                    checked: root.warpDisclosureAccepted
                    onToggled: root.warpDisclosureAccepted = checked
                    contentItem: Label {
                        text: parent.text
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                        leftPadding: warpDisclosureCheck.indicator.width + warpDisclosureCheck.spacing
                    }
                    Layout.fillWidth: true
                }

                Label {
                    text: "WARP protects privacy for managed downloader egress, but it does not provide torrent port forwarding or guarantee swarm reachability."
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Label {
                    text: "Stream download egress"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Theme.spacingSmall
                    rowSpacing: Theme.spacingSmall

                    Label {
                        text: "HTTP stream downloads"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: streamEgressCombo
                        Layout.fillWidth: true
                        model: [
                            { label: "Auto-protect HTTP", value: "auto_http_only" },
                            { label: "Protect all streams", value: "always_protected" },
                            { label: "Reject HTTP", value: "direct_only" }
                        ]
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.streamHttpEgressPolicyIndex()
                        onActivated: root.saveStreamHttpEgressPolicy()
                    }
                }

                Label {
                    text: "This applies only while acquisition materializes stream-source downloads. Imported-file playback and direct HTTPS debrid downloads keep their normal paths."
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Label {
                    text: "Acquisition routing"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                Repeater {
                    model: root.routeRecords()
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: root.routeLabel(modelData)
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Label {
                            text: root.routeProviderLabel(modelData)
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                            visible: (modelData.selectedProviderId || modelData.selected_provider_id || "") !== ""
                            Layout.fillWidth: true
                        }

                        Label {
                            text: {
                                var category = modelData.category || modelData.downloadCategory || ""
                                var path = modelData.downloadPath || modelData.download_path || ""
                                if (category !== "" && path !== "") {
                                    return "Category " + category + " -> " + path
                                }
                                if (category !== "") {
                                    return "Category " + category
                                }
                                return path
                            }
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                            visible: text !== ""
                            Layout.fillWidth: true
                        }

                        Label {
                            text: modelData.blocker || ""
                            color: "#D96B6B"
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                            visible: text !== ""
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: root.routeChecks(modelData)
                            delegate: Label {
                                text: modelData.detail || modelData.code || ""
                                color: modelData.status === "fail" ? "#D96B6B"
                                       : modelData.status === "warn" ? "#E6B85C"
                                       : Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                wrapMode: Text.WordWrap
                                visible: modelData.status === "fail" || modelData.status === "warn"
                                Layout.fillWidth: true
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Button {
                                text: "Protected local"
                                visible: root.routeCanUseManaged(modelData)
                                enabled: apiClient.authToken !== ""
                                onClicked: apiClient.updateDownloadBrokerRouteForOwner(modelData.logicalId || modelData.logical_id, "managed_protected", root.routeOwnerId(modelData))
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.backgroundCardRaised
                                    border.color: Theme.border
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: Theme.textPrimary
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Button {
                                text: "External"
                                visible: root.routeCanUseManaged(modelData)
                                enabled: apiClient.authToken !== ""
                                onClicked: apiClient.updateDownloadBrokerRouteForOwner(modelData.logicalId || modelData.logical_id, "external", root.routeOwnerId(modelData))
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.backgroundCardRaised
                                    border.color: Theme.border
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: Theme.textPrimary
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Button {
                                text: "Debrid"
                                visible: root.routeCanUseDebrid(modelData)
                                enabled: apiClient.authToken !== ""
                                onClicked: apiClient.updateDownloadBrokerRouteForOwner(modelData.logicalId || modelData.logical_id, "debrid", root.routeOwnerId(modelData))
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.backgroundCardRaised
                                    border.color: Theme.border
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: Theme.textPrimary
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Button {
                        text: "Protected local"
                        enabled: apiClient.authToken !== ""
                        onClicked: apiClient.updateDownloadBrokerRoute("downloaders.torrent.default", "managed_protected")
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "External stack"
                        enabled: apiClient.authToken !== ""
                        onClicked: {
                            apiClient.updateDownloadBrokerRoute("downloaders.torrent.default", "external")
                            apiClient.updateDownloadBrokerRoute("downloaders.usenet.default", "external")
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Debrid"
                        enabled: apiClient.authToken !== ""
                        onClicked: apiClient.updateDownloadBrokerRoute("acquisition.debrid.default", "debrid")
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Label {
                    text: "Change provider"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    ComboBox {
                        id: providerSwitchCombo
                        Layout.preferredWidth: 360
                        model: root.protectionProfileOptions()
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.optionIndexForValue(root.protectionProfileOptions(), root.selectedProtectionProfileId)
                        enabled: apiClient.authToken !== "" && root.protectionProfileOptions().length > 0
                        onActivated: root.selectedProtectionProfileId = String(currentValue || "")
                    }

                    Button {
                        text: "Switch provider"
                        enabled: apiClient.authToken !== "" &&
                                 root.selectedProtectionTargetId() !== "" &&
                                 !apiClient.networkProtectionLoading
                        onClicked: apiClient.switchNetworkProtectionProfile(root.selectedProtectionTargetId(), true)
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: parent.enabled ? Theme.textPrimary : Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Label {
                    text: "Import provider"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Theme.spacingLarge
                    rowSpacing: Theme.spacingSmall

                    Label {
                        text: "Preset"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: importProviderPresetCombo
                        Layout.fillWidth: true
                        model: root.importPresetOptions()
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: Math.min(root.importProviderPresetIndex, Math.max(0, root.importPresetOptions().length - 1))
                        onActivated: {
                            root.importProviderPresetIndex = index
                            root.applyImportPresetSelection()
                        }
                    }

                    Label {
                        text: root.importPresetDetail()
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                        visible: text !== ""
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "Type"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: importProviderCombo
                        Layout.fillWidth: true
                        model: [
                            { label: "WireGuard", value: "wireguard" },
                            { label: "OpenVPN", value: "openvpn" }
                        ]
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.importProviderIndex
                        onActivated: {
                            if (root.importKindSupported(index)) {
                                root.importProviderIndex = index
                            } else {
                                root.networkProtectionNotice = "Selected preset does not support " + model[index].label + " import."
                                root.applyImportPresetSelection()
                            }
                        }
                    }

                    Label {
                        text: "Name"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    TextField {
                        id: importProfileName
                        Layout.fillWidth: true
                        placeholderText: root.importProviderIndex === 0 ? "Imported WireGuard" : "Imported OpenVPN"
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    Label {
                        text: "Username"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: root.importProviderIndex === 1
                    }

                    TextField {
                        id: importOpenVpnUsername
                        Layout.fillWidth: true
                        visible: root.importProviderIndex === 1
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    Label {
                        text: "Password"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: root.importProviderIndex === 1
                    }

                    TextField {
                        id: importOpenVpnPassword
                        Layout.fillWidth: true
                        visible: root.importProviderIndex === 1
                        echoMode: TextInput.Password
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    Label {
                        text: "Forwarded port"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    TextField {
                        id: importForwardedPort
                        Layout.fillWidth: true
                        enabled: root.importForwardedPortEnabled()
                        placeholderText: root.importForwardedPortEnabled() ? "Optional" : "No forwarded port"
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator {
                            bottom: 1
                            top: 65535
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    Label {
                        text: "Port protocol"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: root.importForwardedPortEnabled()
                    }

                    ComboBox {
                        id: importForwardedPortProtocolCombo
                        Layout.fillWidth: true
                        visible: root.importForwardedPortEnabled()
                        model: [
                            { label: "TCP", value: "tcp" },
                            { label: "UDP", value: "udp" }
                        ]
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.importForwardedPortProtocolIndex
                        onActivated: root.importForwardedPortProtocolIndex = index
                    }

                    Label {
                        text: "Port source"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: root.importForwardedPortEnabled()
                    }

                    ComboBox {
                        id: importForwardedPortSourceCombo
                        Layout.fillWidth: true
                        visible: root.importForwardedPortEnabled()
                        model: [
                            { label: "Manual", value: "manual" },
                            { label: "Provider API", value: "provider_api" }
                        ]
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.importForwardedPortSourceIndex
                        onActivated: root.importForwardedPortSourceIndex = index
                    }
                }

                TextArea {
                    id: importConfigText
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    placeholderText: root.importProviderIndex === 0 ? "Paste wg0.conf" : "Paste .ovpn"
                    wrapMode: TextEdit.NoWrap
                    color: Theme.textPrimary
                    selectedTextColor: "#17120A"
                    selectionColor: Theme.accent
                    font.family: "Menlo"
                    font.pixelSize: 11
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Button {
                        text: "Import profile"
                        enabled: apiClient.authToken !== "" &&
                                 importConfigText.text.trim() !== "" &&
                                 root.importKindSupported(root.importProviderIndex) &&
                                 !apiClient.networkProtectionLoading
                        onClicked: {
                            var provider = root.selectedImportProvider()
                            var forwardedPort = root.importForwardedPortValue()
                            var forwardedProtocol = root.selectedForwardedPortProtocol()
                            var forwardedSource = root.selectedForwardedPortSource()
                            if (root.importProviderIndex === 0) {
                                apiClient.importWireGuardProfileWithOptions(importProfileName.text, importConfigText.text, provider, forwardedPort, forwardedProtocol, forwardedSource)
                            } else {
                                apiClient.importOpenVpnProfileWithOptions(importProfileName.text, importConfigText.text, importOpenVpnUsername.text, importOpenVpnPassword.text, provider, forwardedPort, forwardedProtocol, forwardedSource)
                            }
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: parent.enabled ? Theme.accent : Theme.backgroundCardRaised
                            border.color: parent.enabled ? "transparent" : Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: parent.enabled ? "#17120A" : Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Reset WARP"
                        enabled: apiClient.authToken !== "" && !apiClient.networkProtectionLoading
                        onClicked: apiClient.resetCloudflareWarpProfile(true)
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: parent.enabled ? Theme.textPrimary : Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Repeater {
                    model: root.importChecks()
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: root.titleLabel(modelData.status)
                            color: modelData.status === "fail" ? "#D96B6B"
                                   : modelData.status === "warn" ? "#E6B85C"
                                   : Theme.accent
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            Layout.preferredWidth: 112
                        }

                        Label {
                            text: modelData.detail || modelData.code || ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                Label {
                    text: "Provider presets"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                    visible: root.providerPresets().length > 0
                }

                Repeater {
                    model: root.providerPresets()
                    delegate: Label {
                        text: root.valueOrDash(modelData.name) + ": " + root.portForwardingLabel(modelData.portForwarding || modelData.port_forwarding)
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                        visible: index < 5
                        Layout.fillWidth: true
                    }
                }

                Label {
                    text: "Diagnostics"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                    visible: root.protectionChecks().length > 0
                }

                Repeater {
                    model: root.protectionChecks()
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: root.titleLabel(modelData.status)
                            color: modelData.status === "fail" ? "#D96B6B"
                                   : modelData.status === "warn" ? "#E6B85C"
                                   : Theme.accent
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            Layout.preferredWidth: 84
                        }

                        Label {
                            text: modelData.detail || modelData.code || ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                Repeater {
                    model: root.warpDiagnosticChecks()
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "WARP " + root.titleLabel(modelData.status)
                            color: modelData.status === "fail" ? "#D96B6B"
                                   : modelData.status === "warn" ? "#E6B85C"
                                   : Theme.accent
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            Layout.preferredWidth: 112
                        }

                        Label {
                            text: modelData.detail || modelData.code || ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                Repeater {
                    model: root.networkEvents()
                    delegate: Label {
                        text: root.titleLabel(modelData.operation) + ": " + root.titleLabel(modelData.status)
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                        visible: index < 6
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Extensions"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                RowLayout {
                    spacing: Theme.spacingSmall

                    Button {
                        text: "Refresh extensions"
                        enabled: apiClient.authToken !== ""
                        onClicked: apiClient.refreshExtensionsCatalog()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Open advanced extension settings"
                        enabled: apiClient.authToken !== "" && root.stackView !== null
                        onClicked: root.stackView.push(Qt.resolvedUrl("AdvancedExtensionsView.qml"), { stackView: root.stackView })
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Label {
                    text: apiClient.extensionsLastRefreshSuccessAt !== ""
                          ? "Last refresh success: " + apiClient.extensionsLastRefreshSuccessAt
                          : "Last refresh success: never"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                Label {
                    text: apiClient.extensionsLastRefreshError !== ""
                          ? "Last refresh error: " + apiClient.extensionsLastRefreshError
                          : "Last refresh error: none"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Find Media Routing"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                Label {
                    text: "Movie"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: movieRouteCombo
                    model: root.routeOptionsFor("movie")
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndexForValue(model, root.routePreferenceFor("movie"))
                    onActivated: root.saveManagerPreferences()
                }

                Label {
                    text: "Series"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: seriesRouteCombo
                    model: root.routeOptionsFor("series")
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndexForValue(model, root.routePreferenceFor("series"))
                    onActivated: root.saveManagerPreferences()
                }

                Label {
                    text: "Anime"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: animeRouteCombo
                    model: root.routeOptionsFor("anime")
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndexForValue(model, root.routePreferenceFor("anime"))
                    onActivated: root.saveManagerPreferences()
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Language preference"
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.family: Theme.fontDisplay
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Theme.spacingLarge
                    rowSpacing: Theme.spacingSmall

                    Label {
                        text: "Mode"
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: languageModeCombo
                        Layout.fillWidth: true
                        model: [
                            { label: "Off", value: "off" },
                            { label: "Prefer", value: "prefer" },
                            { label: "Require review", value: "require_review" }
                        ]
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.languagePreferenceModeIndex()
                        onActivated: root.saveManagerPreferences()
                    }

                    CheckBox {
                        id: movieEnglishAudioCheck
                        text: "Movie English audio"
                        checked: root.languageRuleHasAudio("movie", "en", true)
                        onToggled: root.saveManagerPreferences()
                        Layout.columnSpan: 2
                    }

                    CheckBox {
                        id: seriesEnglishAudioCheck
                        text: "Series English audio"
                        checked: root.languageRuleHasAudio("tv", "en", true)
                        onToggled: root.saveManagerPreferences()
                        Layout.columnSpan: 2
                    }

                    CheckBox {
                        id: animeJaEnSubsCheck
                        text: "Anime Japanese audio with English subtitles"
                        checked: root.languageRuleHasProfile("anime", "ja_audio_en_subs", true)
                        onToggled: root.saveManagerPreferences()
                        Layout.columnSpan: 2
                    }

                    CheckBox {
                        id: animeDualAudioCheck
                        text: "Anime dual audio"
                        checked: root.languageRuleHasProfile("anime", "dual_audio", true)
                        onToggled: root.saveManagerPreferences()
                        Layout.columnSpan: 2
                    }

                    CheckBox {
                        id: animeEnglishAudioCheck
                        text: "Anime English dub"
                        checked: root.languageRuleHasProfile("anime", "en_audio", false)
                        onToggled: root.saveManagerPreferences()
                        Layout.columnSpan: 2
                    }
                }

                Label {
                    text: "Elixir Extension Suite"
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.family: Theme.fontDisplay
                }

                Label {
                    text: root.sourceSuiteProviderSummaryText()
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Repeater {
                    model: root.sourceSuiteProviders()

                    delegate: Rectangle {
                        id: suiteProviderCard
                        required property var modelData
                        readonly property var providerData: modelData
                        Layout.fillWidth: true
                        radius: Theme.radiusMedium
                        color: Theme.backgroundCardRaised
                        border.color: root.sourceSuiteProviderEnabled(providerData)
                                      ? (root.sourceSuiteProviderHealth(providerData) === "healthy"
                                         ? Theme.accentSuccess
                                         : Theme.accent)
                                      : Theme.border
                        implicitHeight: suiteProviderRow.implicitHeight + Theme.spacingMedium * 2

                        RowLayout {
                            id: suiteProviderRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingMedium

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall

                                Label {
                                    Layout.fillWidth: true
                                    text: root.sourceSuiteProviderLabel(suiteProviderCard.providerData)
                                    color: Theme.textPrimary
                                    font.pixelSize: 13
                                    font.family: Theme.fontDisplay
                                    elide: Text.ElideRight
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall
                                    PillTag { text: root.sourceSuiteProviderLaneLabel(suiteProviderCard.providerData) }
                                    PillTag { text: root.sourceSuiteProviderEnabled(suiteProviderCard.providerData) ? "enabled" : "disabled" }
                                    PillTag { text: "health: " + root.sourceSuiteProviderHealth(suiteProviderCard.providerData) }
                                    PillTag { text: root.sourceSuiteMediaLabel(suiteProviderCard.providerData) }
                                    PillTag {
                                        visible: root.sourceSuiteProviderModuleSummary(suiteProviderCard.providerData) !== ""
                                        text: root.sourceSuiteProviderModuleSummary(suiteProviderCard.providerData)
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: root.sourceSuiteProviderLastError(suiteProviderCard.providerData) !== ""
                                          ? ("Last error: " + root.sourceSuiteProviderLastError(suiteProviderCard.providerData))
                                          : "Last error: none"
                                    color: root.sourceSuiteProviderLastError(suiteProviderCard.providerData) !== ""
                                           ? Theme.textSecondary
                                           : Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    visible: root.sourceSuiteProviderModules(suiteProviderCard.providerData).length > 0

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.sourceSuiteProviderLane(suiteProviderCard.providerData) === "stream"
                                              ? "Stream source modules"
                                              : "Source modules"
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                    }

                                    Repeater {
                                        model: root.sourceSuiteProviderModules(suiteProviderCard.providerData)

                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            radius: Theme.radiusSmall
                                            color: Theme.backgroundCard
                                            border.color: root.sourceSuiteModuleBorderColor(modelData)
                                            implicitHeight: moduleColumn.implicitHeight + 8

                                            ColumnLayout {
                                                id: moduleColumn
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 4
                                                spacing: 3

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Theme.spacingSmall

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: root.sourceSuiteModuleLabel(modelData)
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 11
                                                        font.family: Theme.fontBody
                                                        elide: Text.ElideRight
                                                    }

                                                    PillTag { text: root.sourceSuiteModuleEnabled(modelData) ? "enabled" : "disabled" }
                                                    PillTag { text: root.sourceSuiteModuleTypeLabel(modelData) }
                                                    PillTag { text: root.sourceSuiteModuleHealth(modelData) }
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    visible: root.sourceSuiteModuleLastError(modelData) !== ""
                                                    text: root.sourceSuiteModuleLastError(modelData)
                                                    color: Theme.textMuted
                                                    font.pixelSize: 10
                                                    font.family: Theme.fontBody
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    visible: root.sourceSuiteProviderModuleDetail(suiteProviderCard.providerData) !== ""
                                             && root.sourceSuiteProviderModules(suiteProviderCard.providerData).length === 0
                                    text: root.sourceSuiteProviderModuleDetail(suiteProviderCard.providerData)
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Button {
                                text: root.sourceSuiteProviderEnabled(suiteProviderCard.providerData) ? "Disable" : "Enable"
                                enabled: apiClient.authToken !== "" &&
                                         root.sourceSuiteProviderInstanceId(suiteProviderCard.providerData) !== ""
                                onClicked: apiClient.setExtensionInstanceEnabled(
                                               root.sourceSuiteProviderInstanceId(suiteProviderCard.providerData),
                                               !root.sourceSuiteProviderEnabled(suiteProviderCard.providerData))
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.backgroundCard
                                    border.color: Theme.border
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: parent.enabled ? Theme.textPrimary : Theme.textDisabled
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMedium

                    Label {
                        Layout.fillWidth: true
                        text: "Server hardware acceleration"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Button {
                        id: hardwareRefreshButton
                        text: apiClient.playbackHardwareLoading ? "Checking" : "Refresh"
                        enabled: apiClient.authToken !== "" && !apiClient.playbackHardwareLoading
                        onClicked: root.refreshPlaybackHardware()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: hardwareRefreshButton.text
                            color: hardwareRefreshButton.enabled ? Theme.textPrimary : Theme.textDisabled
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.radiusMedium
                    color: Theme.backgroundCardRaised
                    border.color: root.playbackHardwareWarnings().length > 0 ? Theme.accent : Theme.border
                    implicitHeight: hardwareColumn.implicitHeight + Theme.spacingMedium * 2

                    ColumnLayout {
                        id: hardwareColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingMedium
                        spacing: Theme.spacingSmall

                        Label {
                            Layout.fillWidth: true
                            text: root.playbackHardwareSummary()
                            color: root.playbackHardwareWarnings().length > 0 ? Theme.accent : Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: root.playbackHardwareNotice !== ""
                            text: root.playbackHardwareNotice
                            color: Theme.accentDanger
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall
                            PillTag {
                                text: (root.playbackHardwareReadiness().enabled === false) ? "disabled" :
                                      ((root.playbackHardwareReadiness().warmed === true) ? "ready" : "warming")
                            }
                            PillTag { text: "warnings: " + root.playbackHardwareWarnings().length }
                            PillTag {
                                visible: root.playbackHardwareAvailableApis().length > 0
                                text: "apis: " + root.playbackHardwareAvailableApis().join(", ")
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: root.playbackHardwareRecords().length === 0
                            text: apiClient.playbackHardwareLoading ? "Waiting for readiness results." : "No readiness records are available yet."
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: root.playbackHardwareRecords()

                            delegate: Rectangle {
                                id: hardwareRecordCard
                                required property var modelData
                                readonly property var hardwareRecord: modelData
                                Layout.fillWidth: true
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCard
                                border.color: root.playbackHardwareStatusColor(hardwareRecordCard.hardwareRecord.status)
                                implicitHeight: hardwareRecordColumn.implicitHeight + Theme.spacingSmall * 2

                                ColumnLayout {
                                    id: hardwareRecordColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.spacingSmall
                                    spacing: 5

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.playbackHardwareRecordKey(hardwareRecordCard.hardwareRecord)
                                            color: Theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: Theme.fontBody
                                            elide: Text.ElideRight
                                        }

                                        Label {
                                            text: root.playbackHardwareStatusLabel(hardwareRecordCard.hardwareRecord.status)
                                            color: root.playbackHardwareStatusColor(hardwareRecordCard.hardwareRecord.status)
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall
                                        PillTag { text: "api: " + root.valueOrDash(hardwareRecordCard.hardwareRecord.api) }
                                        PillTag {
                                            visible: root.valueOrDash(hardwareRecordCard.hardwareRecord.gpu_vendor || hardwareRecordCard.hardwareRecord.gpuVendor) !== "-"
                                            text: "vendor: " + root.valueOrDash(hardwareRecordCard.hardwareRecord.gpu_vendor || hardwareRecordCard.hardwareRecord.gpuVendor)
                                        }
                                        PillTag {
                                            visible: root.valueOrDash(hardwareRecordCard.hardwareRecord.gpu_driver_version || hardwareRecordCard.hardwareRecord.gpuDriverVersion) !== "-"
                                            text: "driver: " + root.valueOrDash(hardwareRecordCard.hardwareRecord.gpu_driver_version || hardwareRecordCard.hardwareRecord.gpuDriverVersion)
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.playbackHardwareMessage(hardwareRecordCard.hardwareRecord)
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Playback profile"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                Label {
                    text: "Quality"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: qualityModeCombo
                    property var modeValues: ["original", "automatic", "fixed"]
                    model: ["Original", "Automatic", "Fixed"]
                    currentIndex: Math.max(0, modeValues.indexOf(sessionManager.playbackQualityMode))
                    onActivated: sessionManager.playbackQualityMode = modeValues[index]
                }

                Label {
                    text: "Max resolution"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: resolutionCombo
                    model: ["720p", "1080p", "1440p", "2160p", "unlimited"]
                    currentIndex: model.indexOf(sessionManager.playbackMaxResolution)
                    onActivated: sessionManager.playbackMaxResolution = model[index]
                }

                Label {
                    text: "Max bitrate (bps, 0 unlimited)"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    id: bitrateField
                    inputMethodHints: Qt.ImhDigitsOnly
                    text: sessionManager.playbackMaxBitrateBps.toString()
                    onEditingFinished: {
                        var value = parseInt(text)
                        if (!isNaN(value)) {
                            sessionManager.playbackMaxBitrateBps = value
                        }
                    }
                }

                Label {
                    text: "Supported containers"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    id: containersField
                    placeholderText: "mkv, mp4"
                    Binding {
                        target: containersField
                        property: "text"
                        value: sessionManager.playbackSupportedContainers.join(", ")
                        when: !containersField.activeFocus
                    }
                    onEditingFinished: sessionManager.playbackSupportedContainers = parseList(text)
                }

                Label {
                    text: "Supported video codecs"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    id: videoCodecsField
                    placeholderText: "h264, hevc"
                    Binding {
                        target: videoCodecsField
                        property: "text"
                        value: sessionManager.playbackSupportedVideoCodecs.join(", ")
                        when: !videoCodecsField.activeFocus
                    }
                    onEditingFinished: sessionManager.playbackSupportedVideoCodecs = parseList(text)
                }

                Label {
                    text: "Supported audio codecs"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    id: audioCodecsField
                    placeholderText: "aac, ac3"
                    Binding {
                        target: audioCodecsField
                        property: "text"
                        value: sessionManager.playbackSupportedAudioCodecs.join(", ")
                        when: !audioCodecsField.activeFocus
                    }
                    onEditingFinished: sessionManager.playbackSupportedAudioCodecs = parseList(text)
                }

                RowLayout {
                    spacing: Theme.spacingMedium

                    Button {
                        text: "Clear auth"
                        onClicked: sessionManager.clearAuth()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Clear control plane auth"
                        onClicked: sessionManager.clearControlPlaneAuth()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Back"
                        onClicked: {
                            if (root.stackView) {
                                root.stackView.pop()
                            }
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCard
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
}
