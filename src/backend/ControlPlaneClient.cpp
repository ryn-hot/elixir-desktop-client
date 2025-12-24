#include "backend/ControlPlaneClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>

ControlPlaneClient::ControlPlaneClient(QObject *parent)
    : QObject(parent) {}

QString ControlPlaneClient::baseUrl() const {
    return m_baseUrl;
}

void ControlPlaneClient::setBaseUrl(const QString &value) {
    const QString normalized = normalizeBaseUrl(value);
    if (m_baseUrl == normalized) {
        return;
    }
    m_baseUrl = normalized;
    emit baseUrlChanged();
}

QString ControlPlaneClient::authToken() const {
    return m_authToken;
}

void ControlPlaneClient::setAuthToken(const QString &value) {
    if (m_authToken == value) {
        return;
    }
    m_authToken = value;
    emit authTokenChanged();
}

QString ControlPlaneClient::accessTokenExpiresAt() const {
    return m_accessTokenExpiresAt;
}

void ControlPlaneClient::setAccessTokenExpiresAt(const QString &value) {
    if (m_accessTokenExpiresAt == value) {
        return;
    }
    m_accessTokenExpiresAt = value;
    emit accessTokenExpiresAtChanged();
}

void ControlPlaneClient::login(const QString &email, const QString &password) {
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

void ControlPlaneClient::signup(const QString &email, const QString &password) {
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

QString ControlPlaneClient::normalizeBaseUrl(const QString &value) const {
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

QUrl ControlPlaneClient::makeUrl(const QString &path) const {
    const QUrl base(normalizeBaseUrl(m_baseUrl));
    QUrl relative(path.startsWith('/') ? path : QString("/%1").arg(path));
    return base.resolved(relative);
}

void ControlPlaneClient::sendRequest(
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
