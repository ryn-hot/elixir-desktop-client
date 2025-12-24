#include "backend/PlayerController.h"

#include "backend/ApiClient.h"

#include <QDateTime>
#include <QUrl>
#include <QUrlQuery>
#include <QtGlobal>

PlayerController::PlayerController(QObject *parent)
    : QObject(parent) {}

void PlayerController::setApiClient(ApiClient *client) {
    m_apiClient = client;
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
        setSessionState(state);
    }

    const QString error = info.value("error").toString();
    if (error != m_sessionError) {
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
            m_apiClient->seekPlayback(m_sessionId, seconds);
        }
        setSeekOffsetInternal(seconds);
        setLocalPositionInternal(0.0);
        setStreamUrl(cacheBustUrl(m_streamUrl));
        return;
    }
    setSeekOffsetInternal(0.0);
    setLocalPositionInternal(seconds);
}

void PlayerController::endSession() {
    if (m_apiClient && !m_sessionId.isEmpty()) {
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
}

void PlayerController::setStreamUrl(const QString &value) {
    if (m_streamUrl == value) {
        return;
    }
    m_streamUrl = value;
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
