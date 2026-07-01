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

void PlayerController::beginPlayback(const QVariantMap &info) {
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
    updatePlaybackDiagnostics(info);
    setLocalPositionInternal(0.0);
    setPaused(false);
    setActive(true);
    m_seekInFlight = false;
    m_pendingSeekSeconds = 0.0;
    m_pendingStreamUrl.clear();
    m_lastAutomationPositionEvent = -1.0;
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
        {QStringLiteral("duration_seconds"), m_duration}
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
        return;
    }
    setSeekOffsetInternal(0.0);
    setLocalPositionInternal(seconds);
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
        m_apiClient->endSession(m_sessionId);
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
    setPaused(false);
    m_seekInFlight = false;
    m_pendingSeekSeconds = 0.0;
    m_pendingStreamUrl.clear();
    m_lastAutomationPositionEvent = -1.0;
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
        m_apiClient->endSession(m_sessionId);
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
