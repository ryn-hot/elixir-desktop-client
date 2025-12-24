#include "backend/ApiClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkReply>
#include <QUrlQuery>

ApiClient::ApiClient(QObject *parent)
    : QObject(parent) {}

QString ApiClient::baseUrl() const {
    return m_baseUrl;
}

void ApiClient::setBaseUrl(const QString &value) {
    const QString normalized = normalizeBaseUrl(value);
    if (m_baseUrl == normalized) {
        return;
    }
    m_baseUrl = normalized;
    emit baseUrlChanged();
}

QString ApiClient::authToken() const {
    return m_authToken;
}

void ApiClient::setAuthToken(const QString &value) {
    if (m_authToken == value) {
        return;
    }
    m_authToken = value;
    emit authTokenChanged();
}

QString ApiClient::accessTokenExpiresAt() const {
    return m_accessTokenExpiresAt;
}

void ApiClient::setAccessTokenExpiresAt(const QString &value) {
    if (m_accessTokenExpiresAt == value) {
        return;
    }
    m_accessTokenExpiresAt = value;
    emit accessTokenExpiresAtChanged();
}

QVariantMap ApiClient::clientCapabilities() const {
    return m_clientCapabilities;
}

void ApiClient::setClientCapabilities(const QVariantMap &value) {
    if (m_clientCapabilities == value) {
        return;
    }
    m_clientCapabilities = value;
    emit clientCapabilitiesChanged();
}

QString ApiClient::networkType() const {
    return m_networkType;
}

void ApiClient::setNetworkType(const QString &value) {
    if (m_networkType == value) {
        return;
    }
    m_networkType = value;
    emit networkTypeChanged();
}

void ApiClient::login(const QString &email, const QString &password) {
    QJsonObject body{{"email", email.trimmed()}, {"password", password}};
    sendRequest(
        "POST",
        "/api/v1/auth/login",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit loginFailed("Unexpected login response.");
                return;
            }
            const QJsonObject obj = doc.object();
            const QString token = obj.value("access_token").toString();
            if (!token.isEmpty()) {
                setAuthToken(token);
            }
            const QString expiresAt = obj.value("access_expires_at").toString();
            if (!expiresAt.isEmpty()) {
                setAccessTokenExpiresAt(expiresAt);
            }
            emit loginSucceeded();
        },
        [this](const QString &error) { emit loginFailed(error); });
}

void ApiClient::signup(const QString &email, const QString &password) {
    QJsonObject body{{"email", email.trimmed()}, {"password", password}};
    sendRequest(
        "POST",
        "/api/v1/auth/signup",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit loginFailed("Unexpected signup response.");
                return;
            }
            const QJsonObject obj = doc.object();
            const QString token = obj.value("access_token").toString();
            if (!token.isEmpty()) {
                setAuthToken(token);
            }
            const QString expiresAt = obj.value("access_expires_at").toString();
            if (!expiresAt.isEmpty()) {
                setAccessTokenExpiresAt(expiresAt);
            }
            emit loginSucceeded();
        },
        [this](const QString &error) { emit loginFailed(error); });
}

void ApiClient::startPasswordReset(const QString &email) {
    QJsonObject body{{"email", email.trimmed()}};
    sendRequest(
        "POST",
        "/api/v1/auth/reset/start",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit passwordResetFailed("Reset response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            emit passwordResetStarted(obj.value("token").toString(), obj.value("expires_at").toString());
        },
        [this](const QString &error) { emit passwordResetFailed(error); });
}

void ApiClient::completePasswordReset(const QString &token, const QString &newPassword) {
    QJsonObject body{{"token", token.trimmed()}, {"new_password", newPassword}};
    sendRequest(
        "POST",
        "/api/v1/auth/reset/complete",
        body,
        [this](const QJsonDocument &) { emit passwordResetCompleted(); },
        [this](const QString &error) { emit passwordResetFailed(error); });
}

void ApiClient::fetchLibrary() {
    sendRequest("GET", "/api/v1/library/items", QJsonObject(),
                [this](const QJsonDocument &doc) {
                    if (!doc.isArray()) {
                        emit requestFailed("/api/v1/library/items", "Library response was not a list.");
                        return;
                    }
                    emit libraryReceived(doc.array().toVariantList());
                });
}

void ApiClient::fetchMediaDetails(const QString &mediaItemId) {
    sendRequest("GET", QString("/api/v1/library/items/%1").arg(mediaItemId), QJsonObject(),
                [this](const QJsonDocument &doc) {
                    if (!doc.isObject()) {
                        emit requestFailed("/api/v1/library/items/:id", "Details response was not an object.");
                        return;
                    }
                    emit mediaDetailsReceived(doc.object().toVariantMap());
                });
}

void ApiClient::startPlayback(const QString &mediaItemId, const QString &preferredFileId) {
    QJsonObject body{{"media_item_id", mediaItemId}};
    if (!preferredFileId.trimmed().isEmpty()) {
        body.insert("preferred_file_id", preferredFileId);
    } else {
        body.insert("preferred_file_id", QJsonValue::Null);
    }
    if (!m_networkType.isEmpty() && m_networkType != "auto") {
        body.insert("network_type", m_networkType);
    }
    if (!m_clientCapabilities.isEmpty()) {
        body.insert("client_capabilities", QJsonObject::fromVariantMap(m_clientCapabilities));
    }
    sendRequest("POST", "/api/v1/play", body,
                [this](const QJsonDocument &doc) {
                    if (!doc.isObject()) {
                        emit requestFailed("/api/v1/play", "Playback response was not an object.");
                        return;
                    }
                    emit playbackStarted(doc.object().toVariantMap());
                });
}

void ApiClient::seekPlayback(const QString &sessionId, double seconds) {
    QJsonObject body{{"position_seconds", seconds}};
    sendRequest("POST", QString("/api/v1/sessions/%1/seek").arg(sessionId), body,
                [](const QJsonDocument &) {});
}

void ApiClient::pollSession(const QString &sessionId) {
    if (sessionId.trimmed().isEmpty()) {
        return;
    }
    sendRequest("GET", QString("/api/v1/sessions/%1/poll").arg(sessionId), QJsonObject(),
                [this](const QJsonDocument &doc) {
                    if (!doc.isObject()) {
                        emit requestFailed("/api/v1/sessions/:id/poll", "Session poll response was not an object.");
                        return;
                    }
                    emit sessionPolled(doc.object().toVariantMap());
                });
}

void ApiClient::endSession(const QString &sessionId) {
    sendRequest("POST", QString("/api/v1/sessions/%1/end").arg(sessionId), QJsonObject(),
                [](const QJsonDocument &) {});
}

void ApiClient::runScan(bool forceMetadata) {
    const QString path = QString("/api/v1/library/scan?force_metadata=%1")
                             .arg(forceMetadata ? "true" : "false");
    sendRequest("POST", path, QJsonObject(),
                [this](const QJsonDocument &) { emit scanCompleted(); });
}

QString ApiClient::normalizeBaseUrl(const QString &value) const {
    QString trimmed = value.trimmed();
    if (trimmed.isEmpty()) {
        return trimmed;
    }
    if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
        trimmed.prepend("http://");
    }
    while (trimmed.endsWith('/')) {
        trimmed.chop(1);
    }
    return trimmed;
}

QUrl ApiClient::makeUrl(const QString &path) const {
    const QUrl base(normalizeBaseUrl(m_baseUrl));
    QUrl relative(path.startsWith('/') ? path : QString("/%1").arg(path));
    return base.resolved(relative);
}

void ApiClient::sendRequest(
    const QString &method,
    const QString &path,
    const QJsonObject &body,
    const SuccessHandler &onSuccess,
    const ErrorHandler &onError) {
    if (m_baseUrl.trimmed().isEmpty()) {
        const QString msg = "Base URL is not set.";
        if (onError) {
            onError(msg);
        }
        emit requestFailed(path, msg);
        return;
    }

    QNetworkRequest request(makeUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    if (!m_authToken.isEmpty()) {
        request.setRawHeader("Authorization", QByteArray("Bearer ") + m_authToken.toUtf8());
    }

    QNetworkReply *reply = nullptr;
    if (method == "GET") {
        reply = m_manager.get(request);
    } else if (method == "POST") {
        reply = m_manager.post(request, QJsonDocument(body).toJson());
    } else {
        reply = m_manager.sendCustomRequest(request, method.toUtf8(), QJsonDocument(body).toJson());
    }

    connect(reply, &QNetworkReply::finished, this, [this, reply, path, onSuccess, onError]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray payload = reply->readAll();
        const bool okStatus = status >= 200 && status < 300;

        if (reply->error() != QNetworkReply::NoError || !okStatus) {
            const QString detail = payload.isEmpty()
                ? reply->errorString()
                : QString::fromUtf8(payload);
            if (status == 401 && !path.startsWith("/api/v1/auth/")) {
                setAuthToken(QString());
                setAccessTokenExpiresAt(QString());
                emit authExpired(detail.isEmpty() ? "Authentication expired." : detail);
            }
            if (onError) {
                onError(detail);
            }
            emit requestFailed(path, detail);
            reply->deleteLater();
            return;
        }

        if (!onSuccess) {
            reply->deleteLater();
            return;
        }

        QJsonParseError parseError;
        const QJsonDocument doc = QJsonDocument::fromJson(payload, &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            const QString detail = QString("Invalid JSON: %1").arg(parseError.errorString());
            if (onError) {
                onError(detail);
            }
            emit requestFailed(path, detail);
            reply->deleteLater();
            return;
        }

        onSuccess(doc);
        reply->deleteLater();
    });
}
