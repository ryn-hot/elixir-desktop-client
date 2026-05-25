import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import Elixir 1.0

ColumnLayout {
    id: root
    spacing: Theme.spacingMedium

    property string selectedReleaseId: ""
    property var fileSelections: ({})
    property var coverageMappings: ({})
    property bool detailInitialized: false
    property string rejectReason: ""
    property string rejectNote: ""
    property string retryReason: ""
    property string selectedRouteLogicalId: ""
    property bool retryClearSuppression: false

    function reviewRows() {
        return apiClient.acquisitionReviewReleases || []
    }

    function releaseFromSummary(summary) {
        return (summary && summary.release) ? summary.release : ({})
    }

    function releaseId(release) {
        return String((release && (release.releaseId || release.release_id)) || "")
    }

    function detail() {
        return apiClient.acquisitionReviewDetail || ({})
    }

    function detailRelease() {
        var d = detail()
        return d.release || ({})
    }

    function detailMatchesSelection() {
        var id = releaseId(detailRelease())
        return selectedReleaseId !== "" && id === selectedReleaseId
    }

    function filesForDetail() {
        var d = detail()
        return d.files || []
    }

    function coverageForDetail() {
        var d = detail()
        return d.coverage || []
    }

    function targetRowsForCoverage() {
        var d = apiClient.acquisitionSubscriptionCoverage || ({})
        return d.targets || []
    }

    function statusText(value) {
        var raw = String(value || "").replace(/_/g, " ")
        if (raw === "") return "Unknown"
        return raw.charAt(0).toUpperCase() + raw.slice(1)
    }

    function displayText(value, context) {
        var text = String(value || "")
        if (text === "") return ""
        if (context === "Debrid account" && text === "Add account") {
            return "Add debrid account"
        }
        text = text.split("Real-Debrid API token is not configured").join("Add debrid account")
        text = text.split("Real Debrid API token is not configured").join("Add debrid account")
        if (text === "Direct HTTPS debrid") {
            return "Direct HTTPS debrid download"
        }
        return text
    }

    function debridServiceName(value) {
        var raw = String(value || "")
        var normalized = raw.toLowerCase()
        if (normalized === "real_debrid" || normalized === "real-debrid" || normalized === "real debrid") {
            return "Real-Debrid"
        }
        if (normalized === "torbox") return "TorBox"
        if (normalized === "all_debrid" || normalized === "alldebrid" || normalized === "all-debrid") {
            return "AllDebrid"
        }
        if (normalized === "premiumize") return "Premiumize"
        return raw === "" ? "" : raw
    }

    function debridEvidenceForDetail() {
        var evidence = root.detail().evidence || ({})
        return evidence.debridRuntime || evidence.debridFailure ||
               evidence.debridSelection || evidence.debridStaging ||
               evidence.debridDownload || ({})
    }

    function debridEvidenceRows() {
        var evidence = debridEvidenceForDetail()
        var rows = []
        var service = String(evidence.providerName || "")
        if (service === "") {
            service = debridServiceName(evidence.providerImplementation)
        }
        if (service !== "") {
            rows.push({ label: "Service", value: service })
        }
        if (evidence.providerImplementation) {
            var implementation = debridServiceName(evidence.providerImplementation)
            if (implementation !== "" && implementation !== service) {
                rows.push({ label: "Implementation", value: implementation })
            }
        }
        if (evidence.remoteStatus) {
            rows.push({ label: "Remote", value: statusText(evidence.remoteStatus) })
        }
        if (evidence.status) {
            rows.push({ label: "State", value: statusText(evidence.status) })
        }
        if (evidence.fallbackState) {
            rows.push({ label: "Fallback", value: statusText(evidence.fallbackState) })
        }
        if (evidence.failureClass) {
            rows.push({ label: "Failure", value: statusText(evidence.failureClass) })
        }
        if (evidence.selectedFileCount !== undefined) {
            rows.push({ label: "Selected files", value: String(evidence.selectedFileCount) })
        }
        if (evidence.skippedFileCount !== undefined) {
            rows.push({ label: "Skipped files", value: String(evidence.skippedFileCount) })
        }
        return rows
    }

    function routeLabel(route) {
        var value = String(route || "")
        if (value.indexOf("debrid") >= 0) {
            return "Direct HTTPS debrid download"
        }
        if (value.indexOf("torrent") >= 0) {
            return "Torrent via protected downloader egress"
        }
        if (value.indexOf("usenet") >= 0) {
            return "Managed usenet route"
        }
        return value === "" ? "Route pending" : value
    }

    function routeDetail(route) {
        var value = String(route || "")
        if (value.indexOf("debrid") >= 0) {
            return "Downloaded over direct HTTPS through the active debrid service. The selected service is shown as provider evidence when available."
        }
        if (value.indexOf("torrent") >= 0) {
            return "Submitted through the torrent broker. Managed qBittorrent uses protected downloader egress; this does not imply port forwarding."
        }
        if (value.indexOf("usenet") >= 0) {
            return "Submitted through the managed usenet broker."
        }
        return "Route evidence is stored with the release plan."
    }

    function evidenceForDetail() {
        return root.detail().evidence || ({})
    }

    function sourceCandidateEvidence() {
        var evidence = evidenceForDetail()
        return evidence.sourceCandidate || evidence.selectedCandidate || ({})
    }

    function resolverEvidence() {
        return evidenceForDetail().resolverEvidence || ({})
    }

    function routePolicyEvidence() {
        return evidenceForDetail().routePolicy || ({})
    }

    function targetScopeEvidence() {
        return evidenceForDetail().targetScope || ({})
    }

    function sourceCandidateRows() {
        var candidate = sourceCandidateEvidence()
        var rows = []
        var title = String(candidate.releaseTitle || candidate.title || "")
        if (title !== "") rows.push({ label: "Release", value: title })
        var sourceKind = String(candidate.sourceKind || candidate.source_kind || "")
        if (sourceKind !== "") rows.push({ label: "Source", value: root.statusText(sourceKind) })
        var quality = String(candidate.quality || "")
        if (quality !== "") rows.push({ label: "Quality", value: quality })
        var language = String(candidate.language || "")
        if (language !== "") rows.push({ label: "Language", value: language })
        if (candidate.sizeBytes !== undefined && candidate.sizeBytes !== null) {
            rows.push({ label: "Size", value: root.formatBytes(candidate.sizeBytes) })
        }
        if (candidate.seeders !== undefined && candidate.seeders !== null) {
            rows.push({ label: "Seeders", value: String(candidate.seeders) })
        }
        if (candidate.trackerCount !== undefined && candidate.trackerCount !== null) {
            rows.push({ label: "Trackers", value: String(candidate.trackerCount) })
        }
        if (candidate.cachedDebrid !== undefined && candidate.cachedDebrid !== null) {
            rows.push({ label: "Debrid cache", value: candidate.cachedDebrid ? "Cached hint" : "No cache hint" })
        }
        var hash = String(candidate.infoHash || candidate.info_hash || "")
        if (hash !== "") {
            rows.push({ label: "Info hash", value: hash.slice(0, 12) })
        }
        return rows
    }

    function resolverWarningRows() {
        var resolver = resolverEvidence()
        var warnings = []
        var codes = resolver.rejectionCodes || resolver.rejection_codes || []
        for (var i = 0; i < codes.length; ++i) {
            warnings.push(root.statusText(String(codes[i])))
        }
        if (resolver.reason) {
            warnings.push(root.displayText(resolver.reason, "reason"))
        }
        var unique = []
        var seen = {}
        for (var j = 0; j < warnings.length; ++j) {
            var value = String(warnings[j] || "").trim()
            if (value !== "" && seen[value] === undefined) {
                seen[value] = true
                unique.push(value)
            }
        }
        return unique
    }

    function routeChoices() {
        var policy = routePolicyEvidence()
        var candidate = sourceCandidateEvidence()
        var routes = []
        function addRoute(route) {
            var value = String(route || "").trim()
            if (value === "" || value === "debrid_first" || value === "torrent_first") return
            for (var i = 0; i < routes.length; ++i) {
                if (routes[i] === value) return
            }
            routes.push(value)
        }
        addRoute(root.detailRelease().selectedRouteLogicalId)
        addRoute(candidate.defaultRoute || candidate.default_route)
        var allowed = policy.allowedRoutes || policy.allowed_routes || []
        for (var i = 0; i < allowed.length; ++i) addRoute(allowed[i])
        var supported = candidate.supportedRoutes || candidate.supported_routes || []
        for (var j = 0; j < supported.length; ++j) addRoute(supported[j])
        var choices = []
        for (var r = 0; r < routes.length; ++r) {
            choices.push({ label: root.routeLabel(routes[r]), id: routes[r] })
        }
        return choices
    }

    function selectedReviewRoute() {
        var selected = String(selectedRouteLogicalId || "").trim()
        if (selected !== "") return selected
        var choices = routeChoices()
        return choices.length > 0 ? String(choices[0].id || "") : ""
    }

    function routeChoiceIndex() {
        var choices = routeChoices()
        var route = selectedReviewRoute()
        for (var i = 0; i < choices.length; ++i) {
            if (String(choices[i].id || "") === route) return i
        }
        return 0
    }

    function targetScopeSummaryRows() {
        var scope = targetScopeEvidence()
        var rows = []
        var mediaType = String(scope.mediaType || scope.media_type || root.detailRelease().mediaType || "")
        if (mediaType !== "") rows.push({ label: "Media", value: root.statusText(mediaType) })
        var targets = scope.targets || []
        if (targets.length > 0) rows.push({ label: "Targets", value: String(targets.length) })
        var targetKeys = scope.targetKeys || scope.target_keys || []
        if (targetKeys.length > 0) rows.push({ label: "Slots", value: targetKeys.slice(0, 8).join(", ") + (targetKeys.length > 8 ? " +" + (targetKeys.length - 8) : "") })
        if (scope.seasonNumber !== undefined && scope.seasonNumber !== null) {
            rows.push({ label: "Season", value: String(scope.seasonNumber) })
        }
        var episodes = scope.episodeNumbers || scope.episode_numbers || []
        if (episodes.length > 0) {
            rows.push({ label: "Episodes", value: episodes.slice(0, 10).join(", ") + (episodes.length > 10 ? " +" + (episodes.length - 10) : "") })
        }
        return rows
    }

    function reviewQueueSummaryRows() {
        var rows = root.reviewRows()
        var candidateCount = rows.length
        var targetCount = 0
        var stagedCount = 0
        var selectedCount = 0
        for (var i = 0; i < rows.length; ++i) {
            var summary = rows[i] || ({})
            var counts = summary.counts || ({})
            targetCount += Number(counts.reviewRequiredCoverageCount || counts.coverageCount || 0)
            var release = root.releaseFromSummary(summary)
            var state = String(release.state || "")
            if (state === "staging" || state === "submitted" || state === "downloading" || state === "materializing") {
                stagedCount += 1
            }
            selectedCount += Number(counts.selectedCoverageCount || 0)
        }
        return [
            { label: "Candidates", value: String(candidateCount) },
            { label: "Targets", value: String(targetCount) },
            { label: "Staged", value: String(stagedCount) },
            { label: "Mapped", value: String(selectedCount) }
        ]
    }

    function reviewCoverageRows() {
        var rows = coverageForDetail()
        var result = []
        for (var i = 0; i < rows.length; ++i) {
            var coverage = rows[i].coverage || ({})
            if (String(coverage.state || "") !== "rejected") {
                result.push(rows[i])
            }
        }
        return result
    }

    function unmappedTargetCount() {
        if (filesForDetail().length === 0) return 0
        var rows = reviewCoverageRows()
        var count = 0
        for (var i = 0; i < rows.length; ++i) {
            var target = rows[i].target || ({})
            var coverage = rows[i].coverage || ({})
            var targetId = String(target.targetId || coverage.targetId || "")
            var fileId = String(coverageMappings[targetId] || rows[i].releaseFileId || coverage.releaseFileId || "")
            if (targetId !== "" && (fileId === "" || fileSelections[fileId] !== true)) {
                count += 1
            }
        }
        return count
    }

    function approvalReady() {
        if (!detailMatchesSelection() || apiClient.acquisitionReviewLoading) return false
        if (selectedReviewRoute() === "") return false
        if (filesForDetail().length === 0) return true
        return selectedReleaseFileIds().length > 0 && unmappedTargetCount() === 0
    }

    function approveButtonText() {
        return filesForDetail().length === 0 ? "Approve candidate" : "Use selected files"
    }

    function badgeColor(state) {
        var value = String(state || "").toLowerCase()
        if (value === "review_required" || value === "failed" || value === "cancelled" || value === "blocked" || value === "rejected") {
            return Theme.accentDangerSoft
        }
        if (value === "ready" || value === "completed" || value === "approved" || value === "imported") {
            return Theme.accentSuccessSoft
        }
        if (value === "downloading" || value === "materializing" || value === "submitted" || value === "staging") {
            return Theme.accentSoft
        }
        return Theme.backgroundCardRaised
    }

    function badgeBorder(state) {
        var value = String(state || "").toLowerCase()
        if (value === "review_required" || value === "failed" || value === "cancelled" || value === "blocked" || value === "rejected") {
            return Theme.accentDanger
        }
        if (value === "ready" || value === "completed" || value === "approved" || value === "imported") {
            return Theme.accentSuccess
        }
        if (value === "downloading" || value === "materializing" || value === "submitted" || value === "staging") {
            return Theme.accent
        }
        return Theme.border
    }

    function fileLabel(file) {
        var parts = []
        var path = String((file && file.path) || (file && file.basename) || "File")
        parts.push(path)
        var parsed = (file && file.parsed) || ({})
        if (parsed.quality) parts.push(String(parsed.quality))
        if (file && file.sizeBytes) parts.push(formatBytes(file.sizeBytes))
        return parts.join("  |  ")
    }

    function targetLabel(target) {
        if (!target) return "Target"
        var title = String(target.title || target.targetKey || "Target")
        var season = target.seasonNumber
        var episode = target.episodeNumber
        if (season !== undefined && season !== null && episode !== undefined && episode !== null) {
            return "S" + pad2(season) + "E" + pad2(episode) + "  " + title
        }
        if (target.absoluteEpisodeNumber !== undefined && target.absoluteEpisodeNumber !== null) {
            return "EP " + target.absoluteEpisodeNumber + "  " + title
        }
        return title
    }

    function pad2(value) {
        var n = Number(value)
        if (!isFinite(n)) return String(value)
        return n < 10 ? "0" + n : String(n)
    }

    function formatBytes(value) {
        if (value === undefined || value === null || Number(value) <= 0) return ""
        var units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var amount = Number(value)
        var unit = 0
        while (amount >= 1024 && unit < units.length - 1) {
            amount /= 1024
            unit += 1
        }
        return amount.toFixed(amount >= 100 || unit === 0 ? 0 : 1) + " " + units[unit]
    }

    function reviewReasonText() {
        var reasons = []
        var d = detail()
        var rel = d.release || ({})
        if (rel.stateReason) reasons.push(String(rel.stateReason))
        var evidence = d.evidence || ({})
        var policies = [evidence.priorityPolicy || ({}), evidence.manualReview || ({})]
        for (var p = 0; p < policies.length; ++p) {
            var policyReasons = policies[p].reviewReasons || []
            for (var i = 0; i < policyReasons.length; ++i) {
                reasons.push(String(policyReasons[i]))
            }
            if (policies[p].reason) {
                reasons.push(String(policies[p].reason))
            }
        }
        var routeDecision = (evidence.schedulerDispatch || ({})).routeDecision || evidence.routeDecision || ({})
        var routeBlockers = routeDecision.blockers || []
        for (var b = 0; b < routeBlockers.length; ++b) {
            if (routeBlockers[b].detail) {
                reasons.push(String(routeBlockers[b].detail))
            } else if (routeBlockers[b].reason) {
                reasons.push(String(routeBlockers[b].reason))
            }
        }
        var files = d.files || []
        for (var f = 0; f < files.length; ++f) {
            var fileReasons = files[f].reviewReasons || []
            for (var r = 0; r < fileReasons.length; ++r) {
                reasons.push(String(fileReasons[r]))
            }
        }
        var unique = []
        var seen = {}
        for (var j = 0; j < reasons.length; ++j) {
            var reason = String(reasons[j] || "").trim()
            if (reason !== "" && seen[reason] === undefined) {
                seen[reason] = true
                unique.push(displayText(reason, "reason"))
            }
        }
        return unique.join(" | ")
    }

    function importRunsForDetail() {
        var d = detail()
        return d.imports || []
    }

    function animeVerificationForDetail() {
        var d = detail()
        return d.animeVerification || ({})
    }

    function importSummaryText(summary) {
        var value = summary || ({})
        if (!value.runCount || Number(value.runCount) <= 0) {
            return ""
        }
        var parts = []
        if (value.latestState) {
            parts.push("Import: " + statusText(value.latestState))
        }
        if (value.importedFileLinkCount !== undefined) {
            parts.push(String(value.importedFileLinkCount || 0) + " imported")
        }
        if (value.pendingFileLinkCount > 0) {
            parts.push(String(value.pendingFileLinkCount) + " pending")
        }
        if (value.blockedFileLinkCount > 0) {
            parts.push(String(value.blockedFileLinkCount) + " blocked")
        }
        if (value.latestMismatchClass) {
            parts.push(String(value.latestMismatchClass).replace(/_/g, " "))
        }
        return parts.join(" | ")
    }

    function importRunLine(review) {
        var run = (review && review.run) || ({})
        var parts = [statusText(run.state)]
        if (run.routeLogicalId) parts.push(routeLabel(run.routeLogicalId))
        if (run.downloadId) parts.push("Download " + run.downloadId)
        if (run.remoteReleaseId) parts.push("Remote " + run.remoteReleaseId)
        if (run.retryCount > 0) parts.push("Retries " + run.retryCount)
        return displayText(parts.join(" | "), "import")
    }

    function importFileLine(fileReview) {
        var link = (fileReview && fileReview.link) || ({})
        var parts = []
        if (link.localPath) parts.push(String(link.localPath))
        if (link.mediaFileId) parts.push("Media " + link.mediaFileId)
        if (link.movieId) parts.push("Movie " + link.movieId)
        if (link.episodeId) parts.push("Episode " + link.episodeId)
        if (link.verificationState) parts.push("Verification " + statusText(link.verificationState))
        if (link.mismatchClass) parts.push(String(link.mismatchClass).replace(/_/g, " "))
        if (link.stateReason) parts.push(displayText(link.stateReason, "reason"))
        var hash = (fileReview && fileReview.fileHash) || ({})
        if (hash.ed2k) parts.push("ED2K " + String(hash.ed2k).slice(0, 12))
        if (hash.hashStatus) parts.push("Hash " + statusText(hash.hashStatus))
        return parts.join(" | ")
    }

    function animeVerificationSummaryText() {
        var verification = animeVerificationForDetail()
        var hashes = verification.fileHashes || []
        var attempts = verification.matchAttempts || []
        var mismatches = verification.mismatches || []
        var parts = []
        if (hashes.length > 0) parts.push(hashes.length + " hash" + (hashes.length === 1 ? "" : "es"))
        if (attempts.length > 0) parts.push(attempts.length + " match attempt" + (attempts.length === 1 ? "" : "s"))
        if (mismatches.length > 0) parts.push(mismatches.length + " mismatch" + (mismatches.length === 1 ? "" : "es"))
        return parts.join(" | ")
    }

    function compactJson(value) {
        if (value === undefined || value === null) {
            return ""
        }
        var text = JSON.stringify(value)
        if (text === undefined) {
            return ""
        }
        return text.length > 260 ? text.slice(0, 257) + "..." : text
    }

    function fileIdsInCoverage() {
        var ids = {}
        var rows = coverageForDetail()
        for (var i = 0; i < rows.length; ++i) {
            var coverage = rows[i].coverage || ({})
            var id = String(rows[i].releaseFileId || coverage.releaseFileId || "")
            if (id !== "" && String(coverage.state || "") !== "rejected") {
                ids[id] = true
            }
        }
        return ids
    }

    function initializeDetailState() {
        if (!detailMatchesSelection() || detailInitialized) {
            return
        }
        var selections = {}
        var mappings = {}
        var coveredIds = fileIdsInCoverage()
        var files = filesForDetail()
        for (var i = 0; i < files.length; ++i) {
            var id = String(files[i].releaseFileId || "")
            if (id === "") continue
            if (files[i].selected === true) {
                selections[id] = true
            } else if (files[i].selected === false) {
                selections[id] = false
            } else {
                selections[id] = coveredIds[id] === true
            }
        }
        var rows = coverageForDetail()
        for (var j = 0; j < rows.length; ++j) {
            var target = rows[j].target || ({})
            var targetId = String(target.targetId || (rows[j].coverage && rows[j].coverage.targetId) || "")
            var releaseFileId = String(rows[j].releaseFileId || (rows[j].coverage && rows[j].coverage.releaseFileId) || "")
            if (targetId !== "" && releaseFileId !== "") {
                mappings[targetId] = releaseFileId
            }
        }
        fileSelections = selections
        coverageMappings = mappings
        selectedRouteLogicalId = selectedReviewRoute()
        detailInitialized = true
    }

    function openReview(summary) {
        var rel = releaseFromSummary(summary)
        var id = releaseId(rel)
        if (id === "") return
        openReleaseId(id, String(rel.subscriptionId || rel.subscription_id || ""))
    }

    function openReleaseId(releaseId, subscriptionId) {
        var id = String(releaseId || "")
        if (id === "") return
        selectedReleaseId = id
        detailInitialized = false
        fileSelections = ({})
        coverageMappings = ({})
        rejectReason = ""
        rejectNote = ""
        retryReason = ""
        retryClearSuppression = false
        selectedRouteLogicalId = ""
        apiClient.fetchAcquisitionRelease(id)
        var subId = String(subscriptionId || "")
        if (subId !== "") {
            apiClient.fetchAcquisitionSubscriptionCoverage(subId)
        }
    }

    function setFileSelected(fileId, selected) {
        var next = {}
        for (var key in fileSelections) next[key] = fileSelections[key]
        next[String(fileId)] = selected
        fileSelections = next
        if (selected === false) {
            var nextMappings = {}
            for (var targetKey in coverageMappings) {
                if (coverageMappings[targetKey] !== String(fileId)) {
                    nextMappings[targetKey] = coverageMappings[targetKey]
                }
            }
            coverageMappings = nextMappings
        }
    }

    function setTargetMapping(targetId, fileId) {
        var next = {}
        for (var key in coverageMappings) next[key] = coverageMappings[key]
        if (String(fileId || "") === "") {
            delete next[String(targetId)]
        } else {
            next[String(targetId)] = String(fileId)
            setFileSelected(fileId, true)
        }
        coverageMappings = next
    }

    function selectedReleaseFileIds() {
        var ids = []
        for (var key in fileSelections) {
            if (fileSelections[key] === true) ids.push(key)
        }
        return ids
    }

    function skippedReleaseFileIds() {
        var ids = []
        var files = filesForDetail()
        for (var i = 0; i < files.length; ++i) {
            var id = String(files[i].releaseFileId || "")
            if (id !== "" && fileSelections[id] !== true) {
                ids.push(id)
            }
        }
        return ids
    }

    function manualMappings() {
        var mappings = []
        var rows = coverageForDetail()
        for (var i = 0; i < rows.length; ++i) {
            var target = rows[i].target || ({})
            var targetId = String(target.targetId || (rows[i].coverage && rows[i].coverage.targetId) || "")
            var fileId = String(coverageMappings[targetId] || "")
            if (targetId !== "" && fileId !== "" && fileSelections[fileId] === true) {
                mappings.push({
                    targetId: targetId,
                    releaseFileId: fileId,
                    coverageKind: "manual_override",
                    confidence: "high",
                    reason: "Approved in acquisition review."
                })
            }
        }
        return mappings
    }

    function approveSelected() {
        var selected = selectedReleaseFileIds()
        if (filesForDetail().length > 0 && selected.length === 0) {
            reviewToast.show("Select at least one file before approving this release.")
            return
        }
        if (unmappedTargetCount() > 0) {
            reviewToast.show("Map every target before approving this release.")
            return
        }
        var route = selectedReviewRoute()
        if (route === "") {
            reviewToast.show("Choose an acquisition route before approving this release.")
            return
        }
        apiClient.approveAcquisitionRelease(selectedReleaseId, {
            routeLogicalId: route,
            selectedReleaseFileIds: selected,
            skippedReleaseFileIds: skippedReleaseFileIds(),
            mappings: manualMappings(),
            reason: "Approved from the Elixir acquisition review UI."
        })
    }

    function inspectSelected() {
        var route = selectedReviewRoute()
        if (route === "") {
            reviewToast.show("Choose an acquisition route before inspecting this release.")
            return
        }
        apiClient.inspectAcquisitionRelease(selectedReleaseId, {
            routeLogicalId: route,
            reason: "Inspect files before manual approval."
        })
    }

    function rejectRelease() {
        var reason = rejectReason.trim()
        if (reason === "") {
            reviewToast.show("Enter a rejection reason before rejecting this release.")
            return
        }
        apiClient.rejectAcquisitionRelease(selectedReleaseId, {
            reason: reason,
            note: rejectNote.trim(),
            targetPolicy: "pending"
        })
    }

    function retryRelease(mode) {
        apiClient.retryAcquisitionRelease(selectedReleaseId, {
            mode: mode,
            reason: retryReason.trim(),
            clearSuppression: mode === "source_discovery" && retryClearSuppression
        })
    }

    function fileChoiceModel() {
        var choices = [{ label: "Unmapped", id: "" }]
        var files = filesForDetail()
        for (var i = 0; i < files.length; ++i) {
            if (files[i].selectable === false) continue
            choices.push({
                label: String(files[i].basename || files[i].path || files[i].releaseFileId),
                id: String(files[i].releaseFileId || "")
            })
        }
        return choices
    }

    function choiceIndexForFile(fileId) {
        var choices = fileChoiceModel()
        var id = String(fileId || "")
        for (var i = 0; i < choices.length; ++i) {
            if (String(choices[i].id || "") === id) return i
        }
        return 0
    }

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchAcquisitionReleases("review_required", "", 50)
        }
    }

    Connections {
        target: apiClient
        function onAcquisitionReviewDetailChanged() {
            root.initializeDetailState()
            var rel = root.detailRelease()
            if (rel.subscriptionId) {
                apiClient.fetchAcquisitionSubscriptionCoverage(String(rel.subscriptionId))
            }
        }
        function onMediaAcquisitionChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchAcquisitionReleases("review_required", "", 50)
                if (root.selectedReleaseId !== "") {
                    apiClient.fetchAcquisitionRelease(root.selectedReleaseId)
                }
            }
        }
        function onAcquisitionReviewActionCompleted(releaseId, action, detail) {
            reviewToast.show(root.statusText(action) + " saved. Downloader data was preserved.")
            if (action === "approve" || action === "reject") {
                root.selectedReleaseId = String(releaseId)
            }
        }
        function onRequestFailed(endpoint, error) {
            if (String(endpoint).indexOf("/api/v1/acquisition/releases") === 0 ||
                    String(endpoint).indexOf("/api/v1/acquisition/subscriptions") === 0) {
                reviewToast.show(String(error || "Acquisition review request failed."))
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusLarge
        color: Theme.backgroundCard
        border.color: Theme.border
        implicitHeight: reviewContent.implicitHeight + Theme.spacingLarge * 2

        ColumnLayout {
            id: reviewContent
            anchors.fill: parent
            anchors.margins: Theme.spacingLarge
            spacing: Theme.spacingMedium

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        Layout.fillWidth: true
                        text: "Release review"
                        color: Theme.textPrimary
                        font.pixelSize: 17
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        Layout.fillWidth: true
                        text: {
                            var count = root.reviewRows().length
                            if (count > 0) return count + " candidate releases need review before acquisition continues."
                            return "Elixir found no unresolved acquisition candidates that need manual review."
                        }
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                    }
                }

                Button {
                    id: refreshReviewButton
                    text: apiClient.acquisitionReviewLoading ? "Loading" : "Refresh"
                    enabled: !apiClient.acquisitionReviewLoading
                    onClicked: apiClient.fetchAcquisitionReleases("review_required", "", 50)
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                    }
                    contentItem: Label {
                        text: refreshReviewButton.text
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            InlineToast {
                id: reviewToast
                Layout.fillWidth: true
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8
                visible: root.reviewRows().length > 0

                Repeater {
                    model: root.reviewQueueSummaryRows()

                    delegate: Rectangle {
                        required property var modelData
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        implicitHeight: 26
                        implicitWidth: reviewSummaryText.implicitWidth + 16

                        Label {
                            id: reviewSummaryText
                            anchors.centerIn: parent
                            text: modelData.label + ": " + modelData.value
                            color: Theme.textSecondary
                            font.pixelSize: 10
                            font.family: Theme.fontBody
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusSmall
                color: Theme.backgroundCardRaised
                border.color: Theme.border
                visible: root.reviewRows().length === 0 && root.selectedReleaseId === ""
                implicitHeight: noReviewText.implicitHeight + 20

                Label {
                    id: noReviewText
                    anchors.fill: parent
                    anchors.margins: 10
                    text: "No releases currently require manual review."
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
                }
            }

            Repeater {
                model: root.reviewRows()

                delegate: Rectangle {
                    id: reviewRow
                    required property var modelData
                    readonly property var release: root.releaseFromSummary(modelData)
                    readonly property var counts: modelData.counts || ({})
                    readonly property string rid: root.releaseId(release)
                    Layout.fillWidth: true
                    radius: Theme.radiusSmall
                    color: root.selectedReleaseId === rid ? Theme.surfaceHover : Theme.backgroundCardRaised
                    border.color: root.badgeBorder(modelData.reviewStatus || release.state)
                    implicitHeight: rowContent.implicitHeight + 16

                    ColumnLayout {
                        id: rowContent
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Label {
                                    Layout.fillWidth: true
                                    text: String(release.releaseTitle || release.title || "Release")
                                    color: Theme.textPrimary
                                    font.pixelSize: 13
                                    font.family: Theme.fontBody
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.WordWrap
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: root.routeLabel(release.selectedRouteLogicalId) + " | " +
                                          root.statusText(release.confidence) + " | " +
                                          root.statusText(release.resolverKind) + " | " +
                                          String(counts.reviewRequiredCoverageCount || 0) + " coverage rows need review"
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: {
                                        var evidence = modelData.evidence || ({})
                                        var candidate = evidence.sourceCandidate || evidence.selectedCandidate || ({})
                                        var parts = []
                                        if (candidate.quality) parts.push(String(candidate.quality))
                                        if (candidate.language) parts.push(String(candidate.language))
                                        if (candidate.seeders !== undefined && candidate.seeders !== null) parts.push("Seeders " + candidate.seeders)
                                        if (candidate.trackerCount !== undefined && candidate.trackerCount !== null) parts.push("Trackers " + candidate.trackerCount)
                                        if (candidate.cachedDebrid !== undefined && candidate.cachedDebrid !== null) parts.push(candidate.cachedDebrid ? "Cached hint" : "No cache hint")
                                        return parts.join(" | ")
                                    }
                                    visible: text !== ""
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: root.importSummaryText(modelData.importSummary)
                                    visible: text !== ""
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Rectangle {
                                radius: Theme.radiusSmall
                                color: root.badgeColor(modelData.reviewStatus || release.state)
                                border.color: root.badgeBorder(modelData.reviewStatus || release.state)
                                implicitWidth: reviewStateLabel.implicitWidth + 12
                                implicitHeight: reviewStateLabel.implicitHeight + 5

                                Label {
                                    id: reviewStateLabel
                                    anchors.centerIn: parent
                                    text: root.statusText(modelData.reviewStatus || release.state)
                                    color: Theme.textPrimary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                }
                            }

                            Button {
                                id: openReviewButton
                                text: root.selectedReleaseId === reviewRow.rid ? "Open" : "Review"
                                onClicked: root.openReview(modelData)
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.accent
                                    border.color: Theme.accent
                                }
                                contentItem: Label {
                                    text: openReviewButton.text
                                    color: "#111111"
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusMedium
                color: Theme.panelSoft
                border.color: Theme.border
                visible: root.detailMatchesSelection()
                implicitHeight: detailContent.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: detailContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Label {
                                Layout.fillWidth: true
                                text: String(root.detailRelease().releaseTitle || root.detailRelease().title || "Release detail")
                                color: Theme.textPrimary
                                font.pixelSize: 16
                                font.family: Theme.fontDisplay
                                wrapMode: Text.WordWrap
                            }

                            Label {
                                Layout.fillWidth: true
                                text: root.routeLabel(root.detailRelease().selectedRouteLogicalId) + " - " +
                                      root.routeDetail(root.detailRelease().selectedRouteLogicalId)
                                color: Theme.textSecondary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            radius: Theme.radiusSmall
                            color: root.badgeColor(root.detailRelease().state)
                            border.color: root.badgeBorder(root.detailRelease().state)
                            implicitWidth: detailStateLabel.implicitWidth + 14
                            implicitHeight: detailStateLabel.implicitHeight + 6

                            Label {
                                id: detailStateLabel
                                anchors.centerIn: parent
                                text: root.statusText(root.detailRelease().state)
                                color: Theme.textPrimary
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        implicitHeight: routeReviewContent.implicitHeight + 16

                        RowLayout {
                            id: routeReviewContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: Theme.spacingMedium

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    Layout.fillWidth: true
                                    text: "Acquisition route"
                                    color: Theme.textPrimary
                                    font.pixelSize: 13
                                    font.family: Theme.fontBody
                                    font.weight: Font.DemiBold
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: root.routeDetail(root.selectedReviewRoute())
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                }
                            }

                            ComboBox {
                                Layout.preferredWidth: 300
                                model: root.routeChoices()
                                textRole: "label"
                                valueRole: "id"
                                currentIndex: root.routeChoiceIndex()
                                enabled: root.routeChoices().length > 1 && !apiClient.acquisitionReviewLoading
                                onActivated: function(index) {
                                    var choices = root.routeChoices()
                                    var choice = choices[index] || ({})
                                    root.selectedRouteLogicalId = String(choice.id || "")
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "Kind", value: root.statusText(root.detailRelease().releaseKind) },
                                { label: "Resolver", value: root.statusText(root.detailRelease().resolverKind) },
                                { label: "Files", value: String((root.detail().counts || {}).fileCount || 0) },
                                { label: "Selected", value: String(root.selectedReleaseFileIds().length) },
                                { label: "Coverage", value: String((root.detail().counts || {}).coverageCount || 0) },
                                { label: "Imports", value: String(root.importRunsForDetail().length) }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                implicitHeight: 26
                                implicitWidth: metricText.implicitWidth + 16
                                Label {
                                    id: metricText
                                    anchors.centerIn: parent
                                    text: modelData.label + ": " + modelData.value
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        visible: root.sourceCandidateRows().length > 0
                        implicitHeight: sourceCandidateContent.implicitHeight + 16

                        ColumnLayout {
                            id: sourceCandidateContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 7

                            Label {
                                Layout.fillWidth: true
                                text: "Source candidate"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                font.weight: Font.DemiBold
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.sourceCandidateRows()

                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: Theme.radiusSmall
                                        color: Theme.panelSoft
                                        border.color: Theme.border
                                        implicitHeight: 24
                                        implicitWidth: sourceCandidateText.implicitWidth + 14

                                        Label {
                                            id: sourceCandidateText
                                            anchors.centerIn: parent
                                            text: String(modelData.label + ": " + modelData.value)
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        visible: root.targetScopeSummaryRows().length > 0
                        implicitHeight: targetScopeContent.implicitHeight + 16

                        ColumnLayout {
                            id: targetScopeContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 7

                            Label {
                                Layout.fillWidth: true
                                text: "Target scope"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                font.weight: Font.DemiBold
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.targetScopeSummaryRows()

                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: Theme.radiusSmall
                                        color: Theme.panelSoft
                                        border.color: Theme.border
                                        implicitHeight: 24
                                        implicitWidth: targetScopeText.implicitWidth + 14

                                        Label {
                                            id: targetScopeText
                                            anchors.centerIn: parent
                                            text: String(modelData.label + ": " + modelData.value)
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.accentDangerSoft
                        border.color: Theme.accentDanger
                        visible: root.resolverWarningRows().length > 0
                        implicitHeight: resolverWarningContent.implicitHeight + 16

                        ColumnLayout {
                            id: resolverWarningContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 7

                            Label {
                                Layout.fillWidth: true
                                text: "Resolver warnings"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                font.weight: Font.DemiBold
                            }

                            Label {
                                Layout.fillWidth: true
                                text: "Elixir found this release, but could not safely match it automatically."
                                color: Theme.textSecondary
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                                wrapMode: Text.WordWrap
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.resolverWarningRows()

                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: Theme.radiusSmall
                                        color: Theme.panelSoft
                                        border.color: Theme.accentDanger
                                        implicitHeight: 24
                                        implicitWidth: resolverWarningText.implicitWidth + 14

                                        Label {
                                            id: resolverWarningText
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        visible: root.debridEvidenceRows().length > 0
                        implicitHeight: debridEvidenceContent.implicitHeight + 16

                        ColumnLayout {
                            id: debridEvidenceContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 7

                            Label {
                                Layout.fillWidth: true
                                text: "Debrid evidence"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                font.weight: Font.DemiBold
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.debridEvidenceRows()

                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: Theme.radiusSmall
                                        color: Theme.panelSoft
                                        border.color: Theme.border
                                        implicitHeight: 24
                                        implicitWidth: debridEvidenceText.implicitWidth + 14

                                        Label {
                                            id: debridEvidenceText
                                            anchors.centerIn: parent
                                            text: String(modelData.label + ": " + modelData.value)
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.accentDangerSoft
                        border.color: Theme.accentDanger
                        visible: root.reviewReasonText() !== ""
                        implicitHeight: reasonText.implicitHeight + 16

                        Label {
                            id: reasonText
                            anchors.fill: parent
                            anchors.margins: 8
                            text: root.reviewReasonText()
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        visible: root.importRunsForDetail().length > 0
                        implicitHeight: importStateContent.implicitHeight + 16

                        ColumnLayout {
                            id: importStateContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                text: "Import state"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: root.importRunsForDetail()

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property var run: modelData.run || ({})
                                    Layout.fillWidth: true
                                    radius: Theme.radiusSmall
                                    color: Theme.panelSoft
                                    border.color: root.badgeBorder(run.state)
                                    implicitHeight: importRunContent.implicitHeight + 12

                                    ColumnLayout {
                                        id: importRunContent
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 5

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.importRunLine(modelData)
                                            color: Theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.WordWrap
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.displayText(run.stateReason || run.mismatchClass || "", "reason")
                                            visible: text !== ""
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                            wrapMode: Text.WordWrap
                                        }

                                        Repeater {
                                            model: modelData.fileLinks || []

                                            delegate: Label {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                text: root.importFileLine(modelData)
                                                visible: text !== ""
                                                color: Theme.textSecondary
                                                font.pixelSize: 10
                                                font.family: Theme.fontBody
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: (root.animeVerificationForDetail().mismatches || []).length > 0
                                      ? Theme.accentDanger
                                      : Theme.border
                        visible: root.animeVerificationSummaryText() !== ""
                        implicitHeight: animeVerificationContent.implicitHeight + 16

                        ColumnLayout {
                            id: animeVerificationContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 7

                            Label {
                                Layout.fillWidth: true
                                text: "Anime verification"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                font.weight: Font.DemiBold
                            }

                            Label {
                                Layout.fillWidth: true
                                text: root.animeVerificationSummaryText()
                                color: Theme.textSecondary
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: (root.animeVerificationForDetail().mismatches || [])

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    radius: Theme.radiusSmall
                                    color: Theme.accentDangerSoft
                                    border.color: Theme.accentDanger
                                    implicitHeight: mismatchContent.implicitHeight + 12

                                    ColumnLayout {
                                        id: mismatchContent
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 4

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.statusText(modelData.state) + " | " +
                                                  root.statusText(modelData.confidence) +
                                                  (modelData.reason ? " | " + modelData.reason : "")
                                            color: Theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.WordWrap
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: "Planned: " + root.compactJson(modelData.plannedTarget)
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                            wrapMode: Text.WordWrap
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: "Verified: " + root.compactJson(modelData.verifiedIdentity)
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "Files"
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.family: Theme.fontBody
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        visible: root.filesForDetail().length === 0
                        implicitHeight: noFilesContent.implicitHeight + 16

                        RowLayout {
                            id: noFilesContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: Theme.spacingMedium

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    Layout.fillWidth: true
                                    text: "Files have not been inspected yet."
                                    color: Theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: Theme.fontBody
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.WordWrap
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: "Stage this release through the selected route to fetch provider metadata before mapping files."
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Button {
                                id: inspectEmptyFilesButton
                                text: "Inspect files"
                                enabled: !apiClient.acquisitionReviewLoading && root.selectedReviewRoute() !== ""
                                onClicked: root.inspectSelected()
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: inspectEmptyFilesButton.enabled ? Theme.accent : Theme.backgroundCardRaised
                                    border.color: inspectEmptyFilesButton.enabled ? Theme.accent : Theme.border
                                }
                                contentItem: Label {
                                    text: inspectEmptyFilesButton.text
                                    color: inspectEmptyFilesButton.enabled ? "#111111" : Theme.textDisabled
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    Repeater {
                        model: root.filesForDetail()

                        delegate: Rectangle {
                            required property var modelData
                            readonly property string fileId: String(modelData.releaseFileId || "")
                            Layout.fillWidth: true
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: root.fileSelections[fileId] === true ? Theme.accentSuccess : Theme.border
                            implicitHeight: fileRow.implicitHeight + 12

                            RowLayout {
                                id: fileRow
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 8

                                CheckBox {
                                    checked: root.fileSelections[fileId] === true
                                    enabled: modelData.selectable !== false
                                    onToggled: root.setFileSelected(fileId, checked)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.fileLabel(modelData)
                                        color: Theme.textPrimary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: {
                                            var parsed = modelData.parsed || ({})
                                            var parts = []
                                            if (parsed.seasonNumber !== undefined && parsed.episodeNumber !== undefined) {
                                                parts.push("S" + root.pad2(parsed.seasonNumber) + "E" + root.pad2(parsed.episodeNumber))
                                            }
                                            if (parsed.releaseGroup) parts.push("Group: " + parsed.releaseGroup)
                                            if (modelData.providerFileId) parts.push("Provider file: " + modelData.providerFileId)
                                            if (modelData.selectable === false) parts.push("Not selectable")
                                            return parts.join(" | ")
                                        }
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "Target coverage"
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.family: Theme.fontBody
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: root.coverageForDetail()

                        delegate: Rectangle {
                            required property var modelData
                            readonly property var target: modelData.target || ({})
                            readonly property var coverage: modelData.coverage || ({})
                            readonly property string targetId: String(target.targetId || coverage.targetId || "")
                            Layout.fillWidth: true
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: root.badgeBorder(coverage.state)
                            implicitHeight: coverageRow.implicitHeight + 12

                            RowLayout {
                                id: coverageRow
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.targetLabel(target)
                                        color: Theme.textPrimary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.statusText(coverage.coverageKind) + " | " +
                                              root.statusText(coverage.confidence) + " | " +
                                              root.statusText(coverage.state) +
                                              (coverage.reason ? " | " + root.displayText(coverage.reason, "reason") : "")
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                ComboBox {
                                    Layout.preferredWidth: 260
                                    visible: root.filesForDetail().length > 0
                                    model: root.fileChoiceModel()
                                    textRole: "label"
                                    valueRole: "id"
                                    currentIndex: root.choiceIndexForFile(root.coverageMappings[targetId] || modelData.releaseFileId || coverage.releaseFileId || "")
                                    onActivated: function(index) {
                                        var choice = root.fileChoiceModel()[index]
                                        root.setTargetMapping(targetId, choice ? choice.id : "")
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.accentDangerSoft
                        border.color: Theme.accentDanger
                        visible: root.unmappedTargetCount() > 0
                        implicitHeight: unmappedTargetText.implicitHeight + 16

                        Label {
                            id: unmappedTargetText
                            anchors.fill: parent
                            anchors.margins: 8
                            text: root.unmappedTargetCount() + " targets still need file mappings before approval."
                            color: Theme.textPrimary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        visible: (root.detail().evidence || {}).schedulerDispatch !== undefined
                        implicitHeight: diagnosticsText.implicitHeight + 16

                        Label {
                            id: diagnosticsText
                            anchors.fill: parent
                            anchors.margins: 8
                            text: {
                                var evidence = root.detail().evidence || ({})
                                var dispatch = evidence.schedulerDispatch || ({})
                                var plan = dispatch.selectedPlanScore || ({})
                                var route = dispatch.routeDecision || ({})
                                var parts = []
                                if (dispatch.groupKey) parts.push("Group: " + dispatch.groupKey)
                                if (route.selectedRouteLogicalId) parts.push("Route: " + root.routeLabel(route.selectedRouteLogicalId))
                                if (plan.coveredTargetCount !== undefined) parts.push("Targets: " + plan.coveredTargetCount)
                                if (plan.overfetchCount !== undefined) parts.push("Overfetch: " + plan.overfetchCount)
                                return parts.join(" | ")
                            }
                            color: Theme.textSecondary
                            font.pixelSize: 10
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Button {
                            id: approveReviewButton
                            text: root.approveButtonText()
                            enabled: root.approvalReady()
                            onClicked: root.approveSelected()
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: approveReviewButton.enabled ? Theme.accentSuccess : Theme.backgroundCardRaised
                                border.color: approveReviewButton.enabled ? Theme.accentSuccess : Theme.border
                            }
                            contentItem: Label {
                                text: approveReviewButton.text
                                color: approveReviewButton.enabled ? "#08140D" : Theme.textDisabled
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            id: inspectReviewButton
                            text: "Inspect files"
                            enabled: !apiClient.acquisitionReviewLoading && root.selectedReviewRoute() !== ""
                            onClicked: root.inspectSelected()
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: inspectReviewButton.enabled ? Theme.accent : Theme.border
                            }
                            contentItem: Label {
                                text: inspectReviewButton.text
                                color: inspectReviewButton.enabled ? Theme.textPrimary : Theme.textDisabled
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            id: retryInspectionButton
                            text: "Retry staged release"
                            visible: root.filesForDetail().length > 0 || root.importRunsForDetail().length > 0
                            enabled: !apiClient.acquisitionReviewLoading
                            onClicked: root.retryRelease("same_release")
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: retryInspectionButton.text
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            id: retryImportButton
                            text: "Retry import"
                            visible: root.importRunsForDetail().length > 0
                            enabled: !apiClient.acquisitionReviewLoading
                            onClicked: root.retryRelease("import")
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: retryImportButton.text
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            id: retryVerificationButton
                            text: "Retry verification"
                            visible: root.animeVerificationSummaryText() !== ""
                            enabled: !apiClient.acquisitionReviewLoading
                            onClicked: root.retryRelease("verification")
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: retryVerificationButton.text
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            id: searchAnotherButton
                            text: "Search another"
                            enabled: !apiClient.acquisitionReviewLoading
                            onClicked: root.retryRelease("source_discovery")
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: searchAnotherButton.text
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        CheckBox {
                            id: clearSuppressionCheck
                            checked: root.retryClearSuppression
                            onToggled: root.retryClearSuppression = checked
                        }

                        Label {
                            Layout.fillWidth: true
                            text: "Allow rejected fingerprints to be considered again on the next source search."
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }
                    }

                    TextArea {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 58
                        placeholderText: "Rejection reason"
                        text: root.rejectReason
                        onTextChanged: root.rejectReason = text
                        wrapMode: TextArea.Wrap
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textMuted
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "Optional note"
                        text: root.rejectNote
                        onTextChanged: root.rejectNote = text
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textMuted
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
                            id: rejectReleaseButton
                            text: "Reject release"
                            enabled: !apiClient.acquisitionReviewLoading
                            onClicked: root.rejectRelease()
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.accentDangerSoft
                                border.color: Theme.accentDanger
                            }
                            contentItem: Label {
                                text: rejectReleaseButton.text
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: "Rejecting blocks or requeues targets according to policy and does not delete qBittorrent, NZBGet, or debrid data."
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
