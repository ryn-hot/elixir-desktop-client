#include "backend/PlayerController.h"

#include "backend/ApiClient.h"

#include <QDateTime>
#include <QUrl>
#include <QUrlQuery>
#include <QDebug>
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
    setDuration(info.value("duration_seconds").toDouble());
    setSeekOffsetInternal(info.value("logical_start_seconds").toDouble());
    setLocalPositionInternal(0.0);
    setPaused(false);
    setActive(true);
    m_seekInFlight = false;
    m_pendingSeekSeconds = 0.0;
    m_pendingStreamUrl.clear();
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

    if (m_duration <= 0.0) {
        const double polledDuration = info.value("duration_seconds").toDouble();
        if (polledDuration > 0.0) {
            setDuration(polledDuration);
        }
    }
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
}

void PlayerController::setPaused(bool paused) {
    if (m_paused == paused) {
        return;
    }
    m_paused = paused;
    emit pausedChanged();
}

void PlayerController::seek(double seconds) {
    if (!m_active || m_sessionId.isEmpty()) {
        return;
    }
    if (m_mode == "transcode") {
        if (m_apiClient) {
            m_pendingSeekSeconds = seconds;
            m_pendingStreamUrl = cacheBustUrl(m_streamUrl);
            m_seekInFlight = true;
            qInfo() << "Seek request" << m_sessionId << seconds;
            m_apiClient->seekPlayback(m_sessionId, seconds);
        }
        setSeekOffsetInternal(seconds);
        setLocalPositionInternal(0.0);
        return;
    }
    setSeekOffsetInternal(0.0);
    setLocalPositionInternal(seconds);
}

void PlayerController::endSession() {
    if (m_apiClient && !m_sessionId.isEmpty()) {
        qInfo() << "Ending session" << m_sessionId;
        m_apiClient->endSession(m_sessionId);
    }
    reset();
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
    setPaused(false);
    m_seekInFlight = false;
    m_pendingSeekSeconds = 0.0;
    m_pendingStreamUrl.clear();
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

void PlayerController::setSessionState(const QString &value) {
    if (m_sessionState == value) {
        return;
    }
    m_sessionState = value;
    emit sessionStateChanged();
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
