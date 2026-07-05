#include "backend/PlayerController.h"

#include "backend/ApiClient.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantList>
#include <QStringList>
#include <QUrl>
#include <QUrlQuery>
#include <QDebug>
#include <QRegularExpression>
#include <QMetaType>
#include <cmath>
#include <QtGlobal>

namespace {
QString sanitizeUrlForLog(const QString &url) {
    if (url.isEmpty()) {
        return url;
    }
    QUrl parsed(url);
    parsed.setQuery(QString());
    parsed.setFragment(QString());
    return parsed.toString();
}

QString automationLogPath() {
    return qEnvironmentVariable("ELIXIR_PLAYBACK_AUTOMATION_LOG").trimmed();
}

QJsonObject jsonObjectFromVariantMap(const QVariantMap &map) {
    return QJsonObject::fromVariantMap(map);
}

void appendAutomationEvent(const QString &event, QVariantMap fields = {}) {
    const QString path = automationLogPath();
    if (path.isEmpty()) {
        return;
    }

    fields.insert(QStringLiteral("event"), event);
    fields.insert(
        QStringLiteral("timestamp"),
        QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    if (fields.contains(QStringLiteral("stream_url"))) {
        fields.insert(
            QStringLiteral("stream_url"),
            sanitizeUrlForLog(fields.value(QStringLiteral("stream_url")).toString()));
    }

    const QFileInfo info(path);
    if (!info.absolutePath().isEmpty()) {
        QDir().mkpath(info.absolutePath());
    }
    QFile file(path);
    if (!file.open(QIODevice::Append | QIODevice::Text)) {
        qWarning() << "Failed to open playback automation log" << path << file.errorString();
        return;
    }
    const QJsonDocument doc(jsonObjectFromVariantMap(fields));
    file.write(doc.toJson(QJsonDocument::Compact));
    file.write("\n");
}

QVariantMap variantMapValue(const QVariant &value) {
    if (value.canConvert<QVariantMap>()) {
        return value.toMap();
    }
    return {};
}

QVariantList variantListValue(const QVariant &value) {
    if (value.canConvert<QVariantList>()) {
        return value.toList();
    }
    return {};
}

QVariantMap mapFromKeys(const QVariantMap &source, const QStringList &keys) {
    for (const QString &key : keys) {
        const QVariantMap value = variantMapValue(source.value(key));
        if (!value.isEmpty()) {
            return value;
        }
    }
    return {};
}

QVariant valueFromKeys(const QVariantMap &source, const QStringList &keys) {
    for (const QString &key : keys) {
        const QVariant value = source.value(key);
        if (value.isValid() && !value.isNull()) {
            return value;
        }
    }
    return {};
}

QString firstReason(const QVariant &value) {
    const QVariantList reasons = variantListValue(value);
    for (const QVariant &reason : reasons) {
        const QString text = reason.toString().trimmed();
        if (!text.isEmpty()) {
            return text;
        }
    }
    return {};
}

QString formatBitrate(int bitrateBps) {
    if (bitrateBps <= 0) {
        return {};
    }
    if (bitrateBps >= 1'000'000) {
        const double mbps = static_cast<double>(bitrateBps) / 1'000'000.0;
        return QString::number(mbps, 'f', mbps >= 10.0 ? 0 : 1) + QStringLiteral(" Mbps");
    }
    return QString::number(qMax(1, bitrateBps / 1000)) + QStringLiteral(" kbps");
}

QString formatRungLabel(const QVariantMap &rung) {
    const QString label = rung.value("label").toString().trimmed();
    if (!label.isEmpty()) {
        return label;
    }

    QStringList parts;
    const int height = rung.value("height").toInt();
    if (height > 0) {
        parts.append(QString::number(height) + QStringLiteral("p"));
    }
    const int bitrate = rung.value("bandwidth_bps").toInt();
    const QString bitrateLabel = formatBitrate(bitrate);
    if (!bitrateLabel.isEmpty()) {
        parts.append(bitrateLabel);
    }
    return parts.join(QStringLiteral(" "));
}

QVariantMap rungFromLadder(const QVariantMap &ladder, const QString &id) {
    if (id.trimmed().isEmpty()) {
        return {};
    }
    const QVariantList rungs = variantListValue(ladder.value("rungs"));
    for (const QVariant &entry : rungs) {
        const QVariantMap rung = variantMapValue(entry);
        if (rung.value("id").toString() == id) {
            return rung;
        }
    }
    return {};
}

QVariantMap startingRungFromPlan(const QVariantMap &plan) {
    const QVariantMap ladder = variantMapValue(plan.value("adaptive_ladder"));
    return rungFromLadder(ladder, ladder.value("starting_rung_id").toString());
}

QVariantMap activeRungFromInfo(const QVariantMap &info) {
    QVariantMap active = variantMapValue(info.value("active_rung"));
    if (!active.isEmpty()) {
        return active;
    }

    const QVariantMap jobState = variantMapValue(info.value("job_state"));
    active = variantMapValue(jobState.value("active_rung"));
    if (!active.isEmpty()) {
        return active;
    }

    const QVariantMap plan = variantMapValue(info.value("playback_plan"));
    const QVariantMap ladder = variantMapValue(plan.value("adaptive_ladder"));
    QString activeId = ladder.value("active_rung_id").toString();
    if (activeId.isEmpty()) {
        activeId = ladder.value("starting_rung_id").toString();
    }
    active = rungFromLadder(ladder, activeId);
    if (!active.isEmpty()) {
        return active;
    }

    return startingRungFromPlan(plan);
}

QString redactSensitiveText(QString text) {
    static const QRegularExpression querySecret(
        QStringLiteral(
            "((?:[?&;]|\\b)(?:session|sid|token|access_token|x-plex-token)=)([^\\s&;\\\"']+)"),
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression bearerSecret(
        QStringLiteral("(Bearer\\s+)([^\\s\\\"']+)"),
        QRegularExpression::CaseInsensitiveOption);

    text.replace(querySecret, QStringLiteral("\\1[redacted]"));
    text.replace(bearerSecret, QStringLiteral("\\1[redacted]"));
    return text;
}

QVariant redactDiagnosticVariant(const QVariant &value) {
    if (value.canConvert<QVariantMap>()) {
        QVariantMap out;
        const QVariantMap map = value.toMap();
        for (auto it = map.cbegin(); it != map.cend(); ++it) {
            out.insert(it.key(), redactDiagnosticVariant(it.value()));
        }
        return out;
    }
    if (value.canConvert<QVariantList>()) {
        QVariantList out;
        const QVariantList list = value.toList();
        out.reserve(list.size());
        for (const QVariant &entry : list) {
            out.append(redactDiagnosticVariant(entry));
        }
        return out;
    }
    if (value.metaType().id() == QMetaType::QString) {
        return redactSensitiveText(value.toString());
    }
    return value;
}

QVariantMap redactDiagnosticMap(const QVariantMap &value) {
    return redactDiagnosticVariant(value).toMap();
}

QString formatTrackSelection(const QVariant &value, const QString &emptyLabel) {
    if (!value.isValid() || value.isNull()) {
        return emptyLabel;
    }
    if (value.canConvert<QVariantMap>()) {
        const QVariantMap map = value.toMap();
        QStringList parts;
        const QString label = map.value("label").toString().trimmed();
        const QString language = map.value("language", map.value("lang")).toString().trimmed();
        const QString title = map.value("title").toString().trimmed();
        const QString codec = map.value("codec").toString().trimmed();
        if (!label.isEmpty()) {
            parts.append(label);
        }
        if (!language.isEmpty()) {
            parts.append(language.toUpper());
        }
        if (!title.isEmpty()) {
            parts.append(title);
        }
        if (!codec.isEmpty()) {
            parts.append(codec);
        }
        if (!parts.isEmpty()) {
            return parts.join(QStringLiteral(" • "));
        }
        const QString id = map.value("id", map.value("index")).toString().trimmed();
        if (!id.isEmpty()) {
            return QStringLiteral("Stream %1").arg(id);
        }
        return emptyLabel;
    }

    bool numeric = false;
    const int index = value.toInt(&numeric);
    if (numeric) {
        return QStringLiteral("Stream %1").arg(index);
    }

    const QString text = value.toString().trimmed();
    return text.isEmpty() ? emptyLabel : text;
}

int retryBitrateFromMap(const QVariantMap &map) {
    const QVariantMap retry = mapFromKeys(map, {"retry", "retryPolicy"});
    const QVariantMap lowerQuality = mapFromKeys(retry, {"lower_quality", "lowerQuality"});
    const QVariant bitrate = valueFromKeys(lowerQuality, {"max_bitrate_bps", "maxBitrateBps"});
    const int bitrateBps = bitrate.toInt();
    if (bitrateBps > 0) {
        return bitrateBps;
    }

    const QVariantMap details = variantMapValue(map.value("details"));
    if (!details.isEmpty()) {
        return retryBitrateFromMap(details);
    }
    return 0;
}

double numberFromKeys(const QVariantMap &source, const QStringList &keys, double fallback = 0.0) {
    for (const QString &key : keys) {
        const QVariant value = source.value(key);
        if (!value.isValid() || value.isNull()) {
            continue;
        }
        bool ok = false;
        const double number = value.toDouble(&ok);
        if (ok && std::isfinite(number)) {
            return number;
        }
    }
    return fallback;
}

QString stringFromKeys(const QVariantMap &source, const QStringList &keys) {
    for (const QString &key : keys) {
        const QString value = source.value(key).toString().trimmed();
        if (!value.isEmpty()) {
            return value;
        }
    }
    return {};
}

QString segmentType(const QVariantMap &segment) {
    return stringFromKeys(segment, {"segment_type", "segmentType", "type"}).toLower();
}

QString segmentIdentity(const QVariantMap &segment) {
    const QString id = stringFromKeys(segment, {"id", "segment_id", "segmentId"});
    if (!id.isEmpty()) {
        return id;
    }
    return QStringLiteral("%1:%2:%3")
        .arg(segmentType(segment))
        .arg(numberFromKeys(segment, {"start_seconds", "startSeconds"}), 0, 'f', 3)
        .arg(numberFromKeys(segment, {"end_seconds", "endSeconds"}), 0, 'f', 3);
}

QString skipLabelForSegment(const QVariantMap &segment) {
    const QString type = segmentType(segment);
    if (type == QStringLiteral("intro")) {
        return QStringLiteral("Skip Intro");
    }
    if (type == QStringLiteral("recap")) {
        return QStringLiteral("Skip Recap");
    }
    if (type == QStringLiteral("preview")) {
        return QStringLiteral("Skip Preview");
    }
    if (type == QStringLiteral("credits")) {
        return QStringLiteral("Skip Credits");
    }
    if (type == QStringLiteral("outro")) {
        return QStringLiteral("Skip Outro");
    }
    return QStringLiteral("Skip");
}

bool segmentStatusAllowsSkip(const QVariantMap &segment) {
    const QString status = stringFromKeys(segment, {"status"}).toLower();
    return status.isEmpty() || status == QStringLiteral("active");
}

QString skipBehaviorForSegment(const QVariantMap &segment, const QVariantMap &preferences) {
    const QString type = segmentType(segment);
    QStringList keys;
    if (type == QStringLiteral("intro")) {
        keys = {QStringLiteral("skip_intro_behavior"), QStringLiteral("skipIntroBehavior")};
    } else if (type == QStringLiteral("recap")) {
        keys = {QStringLiteral("skip_recap_behavior"), QStringLiteral("skipRecapBehavior")};
    } else if (type == QStringLiteral("preview")) {
        keys = {QStringLiteral("skip_preview_behavior"), QStringLiteral("skipPreviewBehavior")};
    } else if (type == QStringLiteral("credits")) {
        keys = {QStringLiteral("skip_credits_behavior"), QStringLiteral("skipCreditsBehavior")};
    } else if (type == QStringLiteral("outro")) {
        keys = {QStringLiteral("skip_outro_behavior"), QStringLiteral("skipOutroBehavior")};
    } else {
        return QStringLiteral("prompt");
    }

    const QString value = stringFromKeys(preferences, keys).toLower().replace(u'-', u'_');
    if (value == QStringLiteral("disabled")
        || value == QStringLiteral("prompt")
        || value == QStringLiteral("auto")
        || value == QStringLiteral("ask_each_time")) {
        return value;
    }
    return QStringLiteral("prompt");
}

bool boolFromKeys(const QVariantMap &source, const QStringList &keys, bool fallback = false) {
    for (const QString &key : keys) {
        const QVariant value = source.value(key);
        if (!value.isValid() || value.isNull()) {
            continue;
        }
        return value.toBool();
    }
    return fallback;
}

int intFromKeys(const QVariantMap &source, const QStringList &keys, int fallback = 0) {
    for (const QString &key : keys) {
        const QVariant value = source.value(key);
        if (!value.isValid() || value.isNull()) {
            continue;
        }
        bool ok = false;
        const int number = value.toInt(&ok);
        if (ok) {
            return number;
        }
    }
    return fallback;
}

bool segmentCanTriggerUpNext(const QVariantMap &segment, double duration) {
    const QString type = segmentType(segment);
    if (type != QStringLiteral("credits") && type != QStringLiteral("outro")) {
        return false;
    }
    const double start = numberFromKeys(segment, {"start_seconds", "startSeconds"}, -1.0);
    if (!std::isfinite(start) || start < 0.0) {
        return false;
    }
    if (duration <= 0.0) {
        return true;
    }
    return start >= duration * 0.5 || start >= duration - 600.0;
}
} // namespace

PlayerController::PlayerController(QObject *parent)
    : QObject(parent) {}

void PlayerController::setApiClient(ApiClient *client) {
    if (m_apiClient == client) {
        return;
    }
    if (m_apiClient) {
        disconnect(m_apiClient, nullptr, this, nullptr);
    }
    m_apiClient = client;
    if (m_apiClient) {
        connect(
            m_apiClient,
            &ApiClient::seekCompleted,
            this,
            &PlayerController::handleSeekCompleted);
        connect(
            m_apiClient,
            &ApiClient::seekFailed,
            this,
            &PlayerController::handleSeekFailed);
        connect(
            m_apiClient,
            &ApiClient::playbackFailed,
            this,
            &PlayerController::applyPlaybackFailure);
    }
}

QString PlayerController::streamUrl() const {
    return m_streamUrl;
}

QString PlayerController::sessionId() const {
    return m_sessionId;
}

QString PlayerController::mode() const {
    return m_mode;
}

QString PlayerController::delivery() const {
    return m_delivery;
}

QString PlayerController::mediaFileId() const {
    return m_mediaFileId;
}

QString PlayerController::sessionState() const {
    return m_sessionState;
}

QString PlayerController::sessionError() const {
    return m_sessionError;
}

double PlayerController::duration() const {
    return m_duration;
}

double PlayerController::position() const {
    return m_seekOffset + m_localPosition;
}

double PlayerController::localPosition() const {
    return m_localPosition;
}

double PlayerController::seekOffset() const {
    return m_seekOffset;
}

bool PlayerController::paused() const {
    return m_paused;
}

bool PlayerController::active() const {
    return m_active;
}

bool PlayerController::serverSeekRequired() const {
    return m_serverSeekRequired;
}

QString PlayerController::qualityLabel() const {
    return m_qualityLabel;
}

QVariantMap PlayerController::activeRung() const {
    return m_activeRung;
}

QString PlayerController::decisionReason() const {
    return m_decisionReason;
}

QString PlayerController::selectedAudioTrack() const {
    return m_selectedAudioTrack;
}

QString PlayerController::selectedSubtitleTrack() const {
    return m_selectedSubtitleTrack;
}

QVariantMap PlayerController::planSummary() const {
    return m_planSummary;
}

QVariantMap PlayerController::jobState() const {
    return m_jobState;
}

QString PlayerController::ffmpegLogTail() const {
    return m_ffmpegLogTail;
}

QVariantMap PlayerController::lastStructuredError() const {
    return m_lastStructuredError;
}

bool PlayerController::retryAvailable() const {
    return m_sessionState == QStringLiteral("error") || !m_lastStructuredError.isEmpty();
}

bool PlayerController::lowerQualityRetryAvailable() const {
    return lowerQualityRetryBitrate() > 0;
}

QVariantList PlayerController::mediaSegments() const {
    return m_mediaSegments;
}

QVariantMap PlayerController::playbackState() const {
    return m_playbackState;
}

QVariantMap PlayerController::playbackPreferences() const {
    return m_playbackPreferences;
}

QVariantMap PlayerController::activeSkipSegment() const {
    return m_activeSkipSegment;
}

QString PlayerController::activeSkipLabel() const {
    if (m_activeSkipSegment.isEmpty()) {
        return {};
    }
    const QString behavior = skipBehaviorForSegment(m_activeSkipSegment, m_playbackPreferences);
    if (behavior == QStringLiteral("disabled") || behavior == QStringLiteral("auto")) {
        return {};
    }
    return skipLabelForSegment(m_activeSkipSegment);
}

QVariantMap PlayerController::upNext() const {
    return m_upNext;
}

bool PlayerController::upNextPromptVisible() const {
    return m_upNextPromptVisible;
}

int PlayerController::upNextCountdownRemaining() const {
    return m_upNextCountdownRemaining;
}

void PlayerController::beginPlayback(const QVariantMap &info) {
    const bool automaticUpNextStart = m_pendingAutomaticUpNextPlayback;
    m_pendingAutomaticUpNextPlayback = false;
    if (automaticUpNextStart) {
        m_autoplayConsecutiveCount += 1;
    } else {
        m_autoplayConsecutiveCount = 0;
    }

    const QString baseUrl = m_apiClient ? m_apiClient->baseUrl() : QString();
    const QString path = info.value("stream_url").toString();
    qInfo() << "Playback start"
            << "session" << info.value("session_id").toString()
            << "mode" << info.value("mode").toString()
            << "stream" << sanitizeUrlForLog(path)
            << "base" << baseUrl;
    setStreamUrl(buildStreamUrl(baseUrl, path));
    setSessionId(info.value("session_id").toString());
    setMode(info.value("mode").toString());
    setSessionState("active");
    setSessionError(QString());
    setLastStructuredError(QVariantMap());
    setDuration(info.value("duration_seconds").toDouble());
    setSeekOffsetInternal(info.value("logical_start_seconds").toDouble());
    setServerSeekRequired(info.value("server_seek_required").toBool());
    setPlaybackState(mapFromKeys(info, {"playback_state", "playbackState"}));
    setPlaybackPreferences(mapFromKeys(info, {"playback_preferences", "playbackPreferences"}));
    setUpNext(mapFromKeys(info, {"up_next", "upNext"}));
    setMediaSegments(variantListValue(valueFromKeys(info, {"segments", "media_segments", "mediaSegments"})));
    updatePlaybackDiagnostics(info);
    setLocalPositionInternal(0.0);
    setPaused(false);
    setActive(true);
    updateActiveSkipSegment();
    m_seekInFlight = false;
    m_pendingSeekSeconds = 0.0;
    m_pendingStreamUrl.clear();
    m_lastAutomationPositionEvent = -1.0;
    m_lastProgressReportPosition = -1.0;
    m_lastProgressReportMs = -1;
    appendAutomationEvent(QStringLiteral("playback_started"), {
        {QStringLiteral("session_id"), m_sessionId},
        {QStringLiteral("mode"), m_mode},
        {QStringLiteral("delivery"), m_delivery},
        {QStringLiteral("media_file_id"), m_mediaFileId},
        {QStringLiteral("stream_url"), m_streamUrl},
        {QStringLiteral("server_seek_required"), m_serverSeekRequired},
        {QStringLiteral("decision_reason"), m_decisionReason},
        {QStringLiteral("quality_label"), m_qualityLabel},
        {QStringLiteral("selected_audio_track"), m_selectedAudioTrack},
        {QStringLiteral("selected_subtitle_track"), m_selectedSubtitleTrack},
        {QStringLiteral("duration_seconds"), m_duration},
        {QStringLiteral("segment_count"), m_mediaSegments.size()},
        {QStringLiteral("automatic_up_next_start"), automaticUpNextStart},
        {QStringLiteral("autoplay_consecutive_count"), m_autoplayConsecutiveCount}
    });
}

void PlayerController::applyPlaybackFailure(const QVariantMap &error) {
    const QVariantMap safeError = redactDiagnosticMap(error);
    const QVariantMap details = variantMapValue(safeError.value("details"));
    QString message = safeError.value("message").toString().trimmed();
    if (message.isEmpty()) {
        message = safeError.value("rawText").toString().trimmed();
    }
    if (message.isEmpty()) {
        message = QStringLiteral("Playback failed.");
    }

    setLastStructuredError(safeError);
    setSessionState(QStringLiteral("error"));
    setSessionError(message);
    setActive(false);

    QString reason = safeError.value("reason").toString().trimmed();
    if (reason.isEmpty()) {
        reason = details.value("reason").toString().trimmed();
    }
    if (reason.isEmpty()) {
        reason = firstReason(details.value("reasons"));
    }
    if (!reason.isEmpty()) {
        setDecisionReason(reason);
    }

    const QVariantMap planSummary = mapFromKeys(details, {"plan_summary", "planSummary"});
    if (!planSummary.isEmpty()) {
        setPlanSummary(planSummary);
    }
    const QVariantMap jobSnapshot = mapFromKeys(details, {"job_snapshot", "jobSnapshot"});
    if (!jobSnapshot.isEmpty()) {
        setJobState(jobSnapshot);
    }
    const QString logTail = valueFromKeys(details, {"ffmpeg_log_tail", "ffmpegLogTail"})
                                .toString()
                                .trimmed();
    if (!logTail.isEmpty()) {
        setFfmpegLogTail(redactSensitiveText(logTail));
    }
    appendAutomationEvent(QStringLiteral("playback_failed"), {
        {QStringLiteral("session_id"), m_sessionId},
        {QStringLiteral("message"), message},
        {QStringLiteral("mode"), m_mode},
        {QStringLiteral("delivery"), m_delivery},
        {QStringLiteral("decision_reason"), m_decisionReason}
    });
}

void PlayerController::applySessionPoll(const QVariantMap &info) {
    if (m_sessionId.isEmpty()) {
        return;
    }
    const QString id = info.value("id").toString();
    if (!id.isEmpty() && id != m_sessionId) {
        return;
    }

    const QString state = info.value("state").toString();
    if (!state.isEmpty()) {
        if (state != m_sessionState) {
            qInfo() << "Session state update" << state;
        }
        setSessionState(state);
    }

    const QString error = info.value("error").toString();
    if (error != m_sessionError) {
        if (!error.isEmpty()) {
            qWarning() << "Session error" << error;
        }
        setSessionError(error);
    }

    const QString mode = info.value("mode").toString();
    if (!mode.isEmpty()) {
        setMode(mode);
    }

    if (info.contains("server_seek_required")) {
        setServerSeekRequired(info.value("server_seek_required").toBool());
    }

    if (m_duration <= 0.0) {
        const double polledDuration = info.value("duration_seconds").toDouble();
        if (polledDuration > 0.0) {
            setDuration(polledDuration);
        }
    }
    updatePlaybackDiagnostics(info);
}

void PlayerController::updateLocalPosition(double seconds) {
    if (!m_active) {
        return;
    }
    if (m_seekInFlight) {
        return;
    }
    if (!std::isfinite(seconds)) {
        return;
    }
    setLocalPositionInternal(seconds);
    updateActiveSkipSegment();
    updateUpNextState();
    maybeReportProgress();
    const double absoluteSeconds = position();
    if (m_lastAutomationPositionEvent < 0.0
        || std::fabs(absoluteSeconds - m_lastAutomationPositionEvent) >= 2.0) {
        m_lastAutomationPositionEvent = absoluteSeconds;
        appendAutomationEvent(QStringLiteral("position"), {
            {QStringLiteral("session_id"), m_sessionId},
            {QStringLiteral("position_seconds"), absoluteSeconds},
            {QStringLiteral("local_position_seconds"), m_localPosition},
            {QStringLiteral("seek_offset_seconds"), m_seekOffset},
            {QStringLiteral("paused"), m_paused}
        });
    }
}

void PlayerController::setPaused(bool paused) {
    if (m_paused == paused) {
        return;
    }
    m_paused = paused;
    emit pausedChanged();
    appendAutomationEvent(paused ? QStringLiteral("paused") : QStringLiteral("resumed"), {
        {QStringLiteral("session_id"), m_sessionId},
        {QStringLiteral("position_seconds"), position()}
    });
    updateUpNextState();
    maybeReportProgress(paused ? QStringLiteral("pause") : QStringLiteral("resume"), true);
}

void PlayerController::seek(double seconds) {
    if (!m_active || m_sessionId.isEmpty()) {
        return;
    }
    if (m_serverSeekRequired) {
        if (m_apiClient) {
            m_pendingSeekSeconds = seconds;
            m_pendingStreamUrl = cacheBustUrl(m_streamUrl);
            m_seekInFlight = true;
            qInfo() << "Seek request" << m_sessionId << seconds;
            appendAutomationEvent(QStringLiteral("seek_requested"), {
                {QStringLiteral("session_id"), m_sessionId},
                {QStringLiteral("position_seconds"), seconds},
                {QStringLiteral("server_seek_required"), true}
            });
            m_apiClient->seekPlayback(m_sessionId, seconds);
        }
        setSeekOffsetInternal(seconds);
        setLocalPositionInternal(0.0);
        updateActiveSkipSegment();
        updateUpNextState();
        maybeReportProgress(QStringLiteral("seek"), true);
        return;
    }
    setSeekOffsetInternal(0.0);
    setLocalPositionInternal(seconds);
    updateActiveSkipSegment();
    updateUpNextState();
    maybeReportProgress(QStringLiteral("seek"), true);
    appendAutomationEvent(QStringLiteral("seek_applied"), {
        {QStringLiteral("session_id"), m_sessionId},
        {QStringLiteral("position_seconds"), seconds},
        {QStringLiteral("server_seek_required"), false}
    });
}

void PlayerController::retrySamePlan() {
    if (!m_apiClient) {
        return;
    }
    releaseSessionBeforeRetry();
    setLastStructuredError(QVariantMap());
    setSessionError(QString());
    setSessionState(QStringLiteral("retrying"));
    m_apiClient->retryLastPlayback();
}

void PlayerController::retryFromCurrentPosition() {
    if (!m_apiClient) {
        return;
    }
    const double retryPosition = position();
    releaseSessionBeforeRetry();
    setLastStructuredError(QVariantMap());
    setSessionError(QString());
    setSessionState(QStringLiteral("retrying"));
    m_apiClient->retryLastPlaybackFrom(retryPosition);
}

void PlayerController::retryWithLowerQuality() {
    if (!m_apiClient) {
        return;
    }
    const int bitrateBps = lowerQualityRetryBitrate();
    if (bitrateBps <= 0) {
        return;
    }
    const double retryPosition = position();
    releaseSessionBeforeRetry();
    setLastStructuredError(QVariantMap());
    setSessionError(QString());
    setSessionState(QStringLiteral("retrying"));
    m_apiClient->retryLastPlaybackWithLowerQuality(retryPosition, bitrateBps);
}

void PlayerController::skipActiveSegment() {
    if (!m_active || m_activeSkipSegment.isEmpty()) {
        return;
    }
    const double target = numberFromKeys(m_activeSkipSegment, {"end_seconds", "endSeconds"}, -1.0);
    if (!std::isfinite(target) || target <= position()) {
        setActiveSkipSegment(QVariantMap());
        return;
    }
    const QString segmentId = segmentIdentity(m_activeSkipSegment);
    if (!segmentId.isEmpty()) {
        m_skippedSegmentIds.insert(segmentId);
    }
    const QString type = segmentType(m_activeSkipSegment);
    const QString behavior = skipBehaviorForSegment(m_activeSkipSegment, m_playbackPreferences);
    appendAutomationEvent(QStringLiteral("segment_skip_requested"), {
        {QStringLiteral("session_id"), m_sessionId},
        {QStringLiteral("segment_id"), segmentId},
        {QStringLiteral("segment_type"), type},
        {QStringLiteral("segment_behavior"), behavior},
        {QStringLiteral("position_seconds"), position()},
        {QStringLiteral("target_seconds"), target}
    });
    seek(target);
    if (m_apiClient) {
        m_apiClient->reportPlaybackProgress(
            m_sessionId,
            position(),
            m_duration,
            m_paused,
            QStringLiteral("segment_skip"),
            {
                {QStringLiteral("segmentType"), type},
                {QStringLiteral("segmentBehavior"), behavior},
            });
        m_lastProgressReportPosition = position();
        m_lastProgressReportMs = QDateTime::currentMSecsSinceEpoch();
    }
    updateActiveSkipSegment();
}

void PlayerController::cancelUpNextAutoplay() {
    if (!m_upNextPromptVisible && m_upNextAutoplayCancelled) {
        return;
    }
    m_upNextAutoplayCancelled = true;
    if (m_apiClient && !m_sessionId.isEmpty()) {
        m_apiClient->reportPlaybackProgress(
            m_sessionId,
            position(),
            m_duration,
            m_paused,
            QStringLiteral("autoplay_cancelled"));
    }
    appendAutomationEvent(QStringLiteral("up_next_cancelled"), {
        {QStringLiteral("session_id"), m_sessionId},
        {QStringLiteral("position_seconds"), position()},
        {QStringLiteral("autoplay_consecutive_count"), m_autoplayConsecutiveCount}
    });
    setUpNextPromptVisible(false);
    setUpNextCountdownRemaining(-1);
}

void PlayerController::playUpNextNow() {
    playUpNextInternal(false);
}

void PlayerController::tickUpNextCountdown() {
    if (!m_active || !m_upNextPromptVisible || m_paused || !canAutoplayUpNext()) {
        return;
    }
    if (m_upNextCountdownRemaining < 0) {
        return;
    }
    if (m_upNextCountdownRemaining <= 0) {
        playUpNextInternal(true);
        return;
    }
    setUpNextCountdownRemaining(m_upNextCountdownRemaining - 1);
    if (m_upNextCountdownRemaining <= 0) {
        playUpNextInternal(true);
    }
}

void PlayerController::endSession() {
    if (!m_sessionId.isEmpty()) {
        appendAutomationEvent(QStringLiteral("session_end_requested"), {
            {QStringLiteral("session_id"), m_sessionId},
            {QStringLiteral("position_seconds"), position()},
            {QStringLiteral("mode"), m_mode},
            {QStringLiteral("delivery"), m_delivery}
        });
    }
    if (m_apiClient && !m_sessionId.isEmpty()) {
        qInfo() << "Ending session" << m_sessionId;
        m_apiClient->endSession(m_sessionId, position(), m_duration, QStringLiteral("ended"));
    }
    reset();
}

void PlayerController::recordAutomationEvent(const QString &event, const QVariantMap &fields) {
    if (event.trimmed().isEmpty()) {
        return;
    }
    QVariantMap payload = fields;
    if (!m_sessionId.isEmpty() && !payload.contains(QStringLiteral("session_id"))) {
        payload.insert(QStringLiteral("session_id"), m_sessionId);
    }
    if (!payload.contains(QStringLiteral("position_seconds"))) {
        payload.insert(QStringLiteral("position_seconds"), position());
    }
    appendAutomationEvent(event, payload);
}

void PlayerController::reset() {
    setActive(false);
    setSessionId(QString());
    setMode(QString());
    setSessionState(QString());
    setSessionError(QString());
    setStreamUrl(QString());
    setDuration(0.0);
    setSeekOffsetInternal(0.0);
    setLocalPositionInternal(0.0);
    setServerSeekRequired(false);
    setQualityLabel(QString());
    setActiveRung(QVariantMap());
    setDecisionReason(QString());
    setDelivery(QString());
    setMediaFileId(QString());
    setSelectedAudioTrack(QString());
    setSelectedSubtitleTrack(QString());
    setPlanSummary(QVariantMap());
    setJobState(QVariantMap());
    setFfmpegLogTail(QString());
    setLastStructuredError(QVariantMap());
    setPlaybackState(QVariantMap());
    setPlaybackPreferences(QVariantMap());
    setUpNext(QVariantMap());
    setMediaSegments(QVariantList());
    setActiveSkipSegment(QVariantMap());
    setPaused(false);
    m_seekInFlight = false;
    m_pendingSeekSeconds = 0.0;
    m_pendingStreamUrl.clear();
    m_lastAutomationPositionEvent = -1.0;
    m_lastProgressReportPosition = -1.0;
    m_lastProgressReportMs = -1;
    m_upNextAutoplayCancelled = false;
    m_pendingAutomaticUpNextPlayback = false;
    m_autoplayConsecutiveCount = 0;
}

void PlayerController::setStreamUrl(const QString &value) {
    if (m_streamUrl == value) {
        return;
    }
    m_streamUrl = value;
    qInfo() << "Stream URL updated" << sanitizeUrlForLog(value);
    emit streamUrlChanged();
}

void PlayerController::setSessionId(const QString &value) {
    if (m_sessionId == value) {
        return;
    }
    m_sessionId = value;
    emit sessionIdChanged();
}

void PlayerController::setMode(const QString &value) {
    if (m_mode == value) {
        return;
    }
    m_mode = value;
    emit modeChanged();
}

void PlayerController::setDelivery(const QString &value) {
    if (m_delivery == value) {
        return;
    }
    m_delivery = value;
    emit diagnosticsChanged();
}

void PlayerController::setMediaFileId(const QString &value) {
    if (m_mediaFileId == value) {
        return;
    }
    m_mediaFileId = value;
    emit diagnosticsChanged();
}

void PlayerController::setSessionState(const QString &value) {
    if (m_sessionState == value) {
        return;
    }
    m_sessionState = value;
    emit sessionStateChanged();
    emit recoveryChanged();
}

void PlayerController::setSessionError(const QString &value) {
    if (m_sessionError == value) {
        return;
    }
    m_sessionError = value;
    emit sessionErrorChanged();
}

void PlayerController::setDuration(double value) {
    if (qFuzzyCompare(m_duration, value)) {
        return;
    }
    m_duration = value;
    emit durationChanged();
}

void PlayerController::setLocalPositionInternal(double value) {
    if (qFuzzyCompare(m_localPosition, value)) {
        return;
    }
    m_localPosition = value;
    emit localPositionChanged();
    emit positionChanged();
}

void PlayerController::setSeekOffsetInternal(double value) {
    if (qFuzzyCompare(m_seekOffset, value)) {
        return;
    }
    m_seekOffset = value;
    emit seekOffsetChanged();
    emit positionChanged();
}

void PlayerController::setActive(bool value) {
    if (m_active == value) {
        return;
    }
    m_active = value;
    emit activeChanged();
    updateUpNextState();
}

void PlayerController::setServerSeekRequired(bool value) {
    if (m_serverSeekRequired == value) {
        return;
    }
    m_serverSeekRequired = value;
    emit serverSeekRequiredChanged();
}

void PlayerController::setQualityLabel(const QString &value) {
    if (m_qualityLabel == value) {
        return;
    }
    m_qualityLabel = value;
    emit qualityChanged();
}

void PlayerController::setActiveRung(const QVariantMap &value) {
    if (m_activeRung == value) {
        return;
    }
    m_activeRung = value;
    emit qualityChanged();
}

void PlayerController::setDecisionReason(const QString &value) {
    if (m_decisionReason == value) {
        return;
    }
    m_decisionReason = value;
    emit decisionReasonChanged();
}

void PlayerController::setSelectedAudioTrack(const QString &value) {
    if (m_selectedAudioTrack == value) {
        return;
    }
    m_selectedAudioTrack = value;
    emit diagnosticsChanged();
}

void PlayerController::setSelectedSubtitleTrack(const QString &value) {
    if (m_selectedSubtitleTrack == value) {
        return;
    }
    m_selectedSubtitleTrack = value;
    emit diagnosticsChanged();
}

void PlayerController::setPlanSummary(const QVariantMap &value) {
    const QVariantMap safeValue = redactDiagnosticMap(value);
    if (m_planSummary == safeValue) {
        return;
    }
    m_planSummary = safeValue;
    emit diagnosticsChanged();
}

void PlayerController::setJobState(const QVariantMap &value) {
    const QVariantMap safeValue = redactDiagnosticMap(value);
    if (m_jobState == safeValue) {
        return;
    }
    m_jobState = safeValue;
    emit diagnosticsChanged();
}

void PlayerController::setFfmpegLogTail(const QString &value) {
    const QString safeValue = redactSensitiveText(value);
    if (m_ffmpegLogTail == safeValue) {
        return;
    }
    m_ffmpegLogTail = safeValue;
    emit diagnosticsChanged();
}

void PlayerController::setLastStructuredError(const QVariantMap &value) {
    const QVariantMap safeValue = redactDiagnosticMap(value);
    if (m_lastStructuredError == safeValue) {
        return;
    }
    m_lastStructuredError = safeValue;
    emit recoveryChanged();
}

void PlayerController::setPlaybackState(const QVariantMap &value) {
    if (m_playbackState == value) {
        return;
    }
    m_playbackState = value;
    emit mediaInteractionsChanged();
}

void PlayerController::setPlaybackPreferences(const QVariantMap &value) {
    if (m_playbackPreferences == value) {
        return;
    }
    m_playbackPreferences = value;
    emit mediaInteractionsChanged();
    emit activeSkipSegmentChanged();
    updateActiveSkipSegment();
    updateUpNextState();
}

void PlayerController::setMediaSegments(const QVariantList &value) {
    if (m_mediaSegments == value) {
        return;
    }
    m_mediaSegments = value;
    m_skippedSegmentIds.clear();
    emit mediaInteractionsChanged();
    updateActiveSkipSegment();
    updateUpNextState();
}

void PlayerController::setActiveSkipSegment(const QVariantMap &value) {
    if (m_activeSkipSegment == value) {
        return;
    }
    m_activeSkipSegment = value;
    emit activeSkipSegmentChanged();
}

void PlayerController::setUpNext(const QVariantMap &value) {
    if (m_upNext == value) {
        return;
    }
    m_upNext = value;
    m_upNextAutoplayCancelled = false;
    setUpNextPromptVisible(false);
    setUpNextCountdownRemaining(-1);
    emit upNextChanged();
    updateUpNextState();
}

void PlayerController::setUpNextPromptVisible(bool value) {
    if (m_upNextPromptVisible == value) {
        return;
    }
    m_upNextPromptVisible = value;
    emit upNextChanged();
}

void PlayerController::setUpNextCountdownRemaining(int value) {
    if (m_upNextCountdownRemaining == value) {
        return;
    }
    m_upNextCountdownRemaining = value;
    emit upNextChanged();
}

void PlayerController::updateActiveSkipSegment() {
    if (!m_active || m_mediaSegments.isEmpty()) {
        setActiveSkipSegment(QVariantMap());
        return;
    }
    const double current = position();
    if (!std::isfinite(current)) {
        setActiveSkipSegment(QVariantMap());
        return;
    }

    for (const QVariant &entry : m_mediaSegments) {
        const QVariantMap segment = variantMapValue(entry);
        if (segment.isEmpty() || !segmentStatusAllowsSkip(segment)) {
            continue;
        }
        const double start = numberFromKeys(segment, {"start_seconds", "startSeconds"}, -1.0);
        const double end = numberFromKeys(segment, {"end_seconds", "endSeconds"}, -1.0);
        if (!std::isfinite(start) || !std::isfinite(end) || end <= start) {
            continue;
        }
        const QString id = segmentIdentity(segment);
        if (!id.isEmpty() && m_skippedSegmentIds.contains(id)) {
            continue;
        }
        if (current >= start && current < end) {
            const QString behavior = skipBehaviorForSegment(segment, m_playbackPreferences);
            if (behavior == QStringLiteral("disabled")) {
                continue;
            }
            setActiveSkipSegment(segment);
            if (behavior == QStringLiteral("auto")) {
                skipActiveSegment();
            }
            return;
        }
    }

    setActiveSkipSegment(QVariantMap());
}

void PlayerController::updateUpNextState() {
    if (!m_active || !upNextAvailable() || m_upNextAutoplayCancelled) {
        setUpNextPromptVisible(false);
        setUpNextCountdownRemaining(-1);
        return;
    }
    const double current = position();
    const double trigger = upNextTriggerSeconds();
    if (!std::isfinite(current) || current < trigger) {
        setUpNextPromptVisible(false);
        setUpNextCountdownRemaining(-1);
        return;
    }

    const bool wasVisible = m_upNextPromptVisible;
    setUpNextPromptVisible(true);

    if (!canAutoplayUpNext()) {
        if (!wasVisible && boolFromKeys(m_playbackPreferences, {"autoplay_enabled", "autoplayEnabled"}, true)) {
            appendAutomationEvent(QStringLiteral("up_next_autoplay_blocked"), {
                {QStringLiteral("session_id"), m_sessionId},
                {QStringLiteral("position_seconds"), current},
                {QStringLiteral("autoplay_consecutive_count"), m_autoplayConsecutiveCount},
                {QStringLiteral("autoplay_max_consecutive"), intFromKeys(m_playbackPreferences, {"autoplay_max_consecutive", "autoplayMaxConsecutive"}, 3)}
            });
        }
        setUpNextCountdownRemaining(-1);
        return;
    }

    if (!wasVisible || m_upNextCountdownRemaining < 0) {
        const int countdown = configuredUpNextCountdownSeconds();
        setUpNextCountdownRemaining(countdown);
        appendAutomationEvent(QStringLiteral("up_next_countdown_started"), {
            {QStringLiteral("session_id"), m_sessionId},
            {QStringLiteral("position_seconds"), current},
            {QStringLiteral("countdown_seconds"), countdown},
            {QStringLiteral("episode_id"), stringFromKeys(m_upNext, {"episode_id", "episodeId"})},
            {QStringLiteral("media_item_id"), stringFromKeys(m_upNext, {"media_item_id", "mediaItemId"})},
            {QStringLiteral("autoplay_consecutive_count"), m_autoplayConsecutiveCount}
        });
        if (countdown <= 0) {
            playUpNextInternal(true);
        }
    }
}

void PlayerController::maybeReportProgress(const QString &eventType, bool force) {
    if (!m_apiClient || !m_active || m_sessionId.isEmpty()) {
        return;
    }
    const double current = position();
    if (!std::isfinite(current) || current < 0.0) {
        return;
    }

    QString event = eventType.trimmed();
    if (event.isEmpty()) {
        event = QStringLiteral("progress");
    }
    const bool milestone = event != QStringLiteral("progress");
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const bool elapsed = m_lastProgressReportMs < 0 || nowMs - m_lastProgressReportMs >= 10000;
    const bool moved =
        m_lastProgressReportPosition < 0.0 || std::fabs(current - m_lastProgressReportPosition) >= 15.0;
    if (!force && !milestone && (!elapsed || !moved)) {
        return;
    }

    m_apiClient->reportPlaybackProgress(m_sessionId, current, m_duration, m_paused, event);
    m_lastProgressReportPosition = current;
    m_lastProgressReportMs = nowMs;
}

void PlayerController::playUpNextInternal(bool automatic) {
    if (!m_apiClient || !m_active || !upNextAvailable()) {
        return;
    }
    if (automatic && !canAutoplayUpNext()) {
        updateUpNextState();
        return;
    }

    const QString mediaItemId = stringFromKeys(m_upNext, {"media_item_id", "mediaItemId", "series_id", "seriesId"});
    const QString episodeId = stringFromKeys(m_upNext, {"episode_id", "episodeId"});
    if (mediaItemId.isEmpty() || episodeId.isEmpty()) {
        return;
    }

    const QString previousSessionId = m_sessionId;
    const double previousPosition = position();
    const double previousDuration = m_duration;
    const QString eventType = automatic ? QStringLiteral("autoplay_next") : QStringLiteral("play_next");
    const int consecutiveBefore = m_autoplayConsecutiveCount;

    appendAutomationEvent(automatic ? QStringLiteral("up_next_autoplay_starting") : QStringLiteral("up_next_play_now"), {
        {QStringLiteral("session_id"), previousSessionId},
        {QStringLiteral("position_seconds"), previousPosition},
        {QStringLiteral("episode_id"), episodeId},
        {QStringLiteral("media_item_id"), mediaItemId},
        {QStringLiteral("autoplay_consecutive_count"), consecutiveBefore}
    });

    if (!previousSessionId.isEmpty()) {
        m_apiClient->endSession(previousSessionId, previousPosition, previousDuration, eventType);
    }

    reset();
    m_autoplayConsecutiveCount = automatic ? consecutiveBefore : 0;
    m_pendingAutomaticUpNextPlayback = automatic;
    m_apiClient->startEpisodePlayback(mediaItemId, episodeId);
}

void PlayerController::updatePlaybackDiagnostics(const QVariantMap &info) {
    QString mode = info.value("mode").toString();
    if (mode.isEmpty()) {
        mode = m_mode;
    }
    const QVariantMap plan = mapFromKeys(info, {"playback_plan", "playbackPlan"});
    QVariantMap planSummary = mapFromKeys(info, {"plan_summary", "planSummary"});
    const QVariantMap jobState = mapFromKeys(info, {
        "job_snapshot",
        "jobSnapshot",
        "job_state",
        "jobState",
    });
    if (planSummary.isEmpty()) {
        planSummary = plan;
    }

    QVariantMap activeRung = variantMapValue(info.value("active_rung"));
    if (activeRung.isEmpty()) {
        activeRung = variantMapValue(jobState.value("active_rung"));
    }
    if (activeRung.isEmpty()) {
        activeRung = variantMapValue(planSummary.value("active_rung"));
    }
    if (activeRung.isEmpty()) {
        activeRung = activeRungFromInfo(info);
    }
    QString qualityLabel = formatRungLabel(activeRung);

    if (qualityLabel.isEmpty()) {
        const bool adaptive = info.value("adaptive").toBool()
            || mode == QStringLiteral("adaptive_transcode")
            || planSummary.value("adaptive").toBool()
            || !variantMapValue(plan.value("adaptive_ladder")).isEmpty();
        if (adaptive) {
            qualityLabel = QStringLiteral("Automatic");
        } else if (mode == QStringLiteral("direct_play")) {
            qualityLabel = QStringLiteral("Original");
        } else if (mode == QStringLiteral("direct_stream")) {
            qualityLabel = QStringLiteral("Original remux");
        } else if (!mode.isEmpty()) {
            qualityLabel = QStringLiteral("Transcode");
        }
    }

    QString reason = info.value("decision_reason").toString().trimmed();
    if (reason.isEmpty()) {
        reason = firstReason(info.value("decision_reasons"));
    }
    if (reason.isEmpty()) {
        reason = planSummary.value("decision_reason").toString().trimmed();
    }
    if (reason.isEmpty()) {
        reason = firstReason(planSummary.value("decision_reasons"));
    }
    if (reason.isEmpty()) {
        reason = firstReason(plan.value("reasons"));
    }

    QString delivery = valueFromKeys(info, {"delivery"}).toString().trimmed();
    if (delivery.isEmpty()) {
        delivery = planSummary.value("delivery").toString().trimmed();
    }
    if (delivery.isEmpty()) {
        delivery = plan.value("delivery").toString().trimmed();
    }
    if (delivery.isEmpty()) {
        delivery = jobState.value("delivery").toString().trimmed();
    }

    QString mediaFileId = valueFromKeys(info, {"media_file_id", "mediaFileId"}).toString().trimmed();
    if (mediaFileId.isEmpty()) {
        mediaFileId = planSummary.value("media_file_id").toString().trimmed();
    }
    if (mediaFileId.isEmpty()) {
        mediaFileId = plan.value("media_file_id").toString().trimmed();
    }

    const QVariant selectedAudio =
        valueFromKeys(planSummary, {"selected_audio_track", "selectedAudioTrack"});
    const QVariant selectedSubtitle =
        valueFromKeys(planSummary, {"selected_subtitle_track", "selectedSubtitleTrack"});
    const QString audioTrack = formatTrackSelection(
        selectedAudio.isValid() ? selectedAudio : valueFromKeys(plan, {"selected_audio_track", "selectedAudioTrack"}),
        QStringLiteral("Default"));
    const QString subtitleTrack = formatTrackSelection(
        selectedSubtitle.isValid()
            ? selectedSubtitle
            : valueFromKeys(plan, {"selected_subtitle_track", "selectedSubtitleTrack"}),
        QStringLiteral("None"));

    QString ffmpegLogTail =
        valueFromKeys(info, {"ffmpeg_log_tail", "ffmpegLogTail"}).toString().trimmed();
    if (ffmpegLogTail.isEmpty()) {
        ffmpegLogTail = valueFromKeys(jobState, {"ffmpeg_log_tail", "ffmpegLogTail", "log_tail", "logTail"})
                            .toString()
                            .trimmed();
    }

    if (!mode.isEmpty()) {
        setMode(mode);
    }
    setDelivery(delivery);
    setMediaFileId(mediaFileId);
    setSelectedAudioTrack(audioTrack);
    setSelectedSubtitleTrack(subtitleTrack);
    setPlanSummary(planSummary);
    setJobState(jobState);
    setFfmpegLogTail(ffmpegLogTail);
    setActiveRung(activeRung);
    setQualityLabel(qualityLabel);
    setDecisionReason(reason);
}

void PlayerController::releaseSessionBeforeRetry() {
    if (m_apiClient && !m_sessionId.isEmpty()) {
        qInfo() << "Releasing session before retry" << m_sessionId;
        m_apiClient->endSession(m_sessionId, position(), m_duration, QStringLiteral("stopped"));
    }
    setActive(false);
    setSessionId(QString());
    setStreamUrl(QString());
    m_seekInFlight = false;
    m_pendingSeekSeconds = 0.0;
    m_pendingStreamUrl.clear();
}

int PlayerController::lowerQualityRetryBitrate() const {
    return retryBitrateFromMap(m_lastStructuredError);
}

bool PlayerController::upNextAvailable() const {
    if (m_upNext.isEmpty()) {
        return false;
    }
    if (!boolFromKeys(m_upNext, {"available"}, false)) {
        return false;
    }
    const QString episodeId = stringFromKeys(m_upNext, {"episode_id", "episodeId"});
    const QString mediaItemId = stringFromKeys(m_upNext, {"media_item_id", "mediaItemId", "series_id", "seriesId"});
    return !episodeId.isEmpty() && !mediaItemId.isEmpty();
}

bool PlayerController::canAutoplayUpNext() const {
    if (!upNextAvailable()) {
        return false;
    }
    const QVariantMap serverAutoplay = mapFromKeys(m_upNext, {"autoplay"});
    if (!serverAutoplay.isEmpty()) {
        if (!boolFromKeys(serverAutoplay, {"enabled"}, true)) {
            return false;
        }
        if (!boolFromKeys(serverAutoplay, {"allowed"}, true)) {
            return false;
        }
    }
    if (!boolFromKeys(m_upNext, {"autoplay_allowed", "autoplayAllowed"}, true)) {
        return false;
    }
    if (!boolFromKeys(m_playbackPreferences, {"autoplay_enabled", "autoplayEnabled"}, true)) {
        return false;
    }
    const int preferenceMaxConsecutive = intFromKeys(
        m_playbackPreferences,
        {"autoplay_max_consecutive", "autoplayMaxConsecutive"},
        3);
    const int maxConsecutive = intFromKeys(
        serverAutoplay,
        {"max_consecutive", "maxConsecutive"},
        preferenceMaxConsecutive);
    if (maxConsecutive <= 0) {
        return false;
    }
    const int serverConsecutive = intFromKeys(
        serverAutoplay,
        {"consecutive_count", "consecutiveCount"},
        m_autoplayConsecutiveCount);
    return qMax(m_autoplayConsecutiveCount, serverConsecutive) < maxConsecutive;
}

double PlayerController::upNextTriggerSeconds() const {
    double trigger = numberFromKeys(m_upNext, {"start_after_seconds", "startAfterSeconds"}, -1.0);
    if (!std::isfinite(trigger) || trigger < 0.0) {
        trigger = m_duration > 0.0 ? qMax(0.0, m_duration - 30.0) : 0.0;
    }

    for (const QVariant &entry : m_mediaSegments) {
        const QVariantMap segment = variantMapValue(entry);
        if (segment.isEmpty() || !segmentStatusAllowsSkip(segment)) {
            continue;
        }
        if (!segmentCanTriggerUpNext(segment, m_duration)) {
            continue;
        }
        const double start = numberFromKeys(segment, {"start_seconds", "startSeconds"}, -1.0);
        if (std::isfinite(start) && start >= 0.0) {
            trigger = qMin(trigger, start);
        }
    }

    return qMax(0.0, trigger);
}

int PlayerController::configuredUpNextCountdownSeconds() const {
    const QVariantMap serverAutoplay = mapFromKeys(m_upNext, {"autoplay"});
    const int preference = intFromKeys(
        m_playbackPreferences,
        {"autoplay_countdown_seconds", "autoplayCountdownSeconds"},
        -1);
    const int serverCountdown = intFromKeys(
        serverAutoplay,
        {"countdown_seconds", "countdownSeconds"},
        -1);
    const int raw = preference >= 0
        ? preference
        : serverCountdown >= 0
        ? serverCountdown
        : intFromKeys(m_upNext, {"countdown_seconds", "countdownSeconds"}, 10);
    return qBound(0, raw, 120);
}

void PlayerController::handleSeekCompleted(const QString &sessionId, double seconds) {
    if (!m_seekInFlight || sessionId != m_sessionId) {
        return;
    }
    if (!qFuzzyCompare(seconds + 1.0, m_pendingSeekSeconds + 1.0)) {
        return;
    }
    m_seekInFlight = false;
    qInfo() << "Seek completed" << sessionId << seconds;
    setStreamUrl(m_pendingStreamUrl);
    appendAutomationEvent(QStringLiteral("seek_completed"), {
        {QStringLiteral("session_id"), sessionId},
        {QStringLiteral("position_seconds"), seconds},
        {QStringLiteral("stream_url"), m_streamUrl}
    });
}

void PlayerController::handleSeekFailed(const QString &sessionId, const QString &error) {
    if (!m_seekInFlight || sessionId != m_sessionId) {
        return;
    }
    m_seekInFlight = false;
    qWarning() << "Seek failed" << sessionId << error;
    if (!error.isEmpty()) {
        setSessionError(error);
    }
    appendAutomationEvent(QStringLiteral("seek_failed"), {
        {QStringLiteral("session_id"), sessionId},
        {QStringLiteral("message"), error}
    });
}

QString PlayerController::buildStreamUrl(const QString &baseUrl, const QString &path) const {
    if (path.startsWith("http://") || path.startsWith("https://")) {
        return path;
    }
    QUrl base(baseUrl);
    if (base.isEmpty()) {
        return path;
    }
    QUrl rel(path.startsWith('/') ? path : QString("/%1").arg(path));
    return base.resolved(rel).toString();
}

QString PlayerController::cacheBustUrl(const QString &url) const {
    if (url.isEmpty()) {
        return url;
    }
    QUrl parsed(url);
    QUrlQuery query(parsed);
    query.removeQueryItem("ts");
    query.addQueryItem("ts", QString::number(QDateTime::currentMSecsSinceEpoch()));
    parsed.setQuery(query);
    return parsed.toString();
}
