#include "backend/ApiClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkReply>
#include <QUrlQuery>
#include <QDebug>
#include <QLocale>

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
                    QVariantMap details = doc.object().toVariantMap();
                    const QVariant existingGenres = details.value("genres");
                    if (existingGenres.toList().isEmpty()) {
                        QVariantList parsed;
                        const QVariantMap meta = details.value("metadata").toMap();
                        const QVariant metaGenres = meta.value("genres");
                        if (metaGenres.canConvert<QVariantList>()) {
                            parsed = metaGenres.toList();
                        } else if (metaGenres.canConvert<QStringList>()) {
                            const QStringList list = metaGenres.toStringList();
                            for (const QString &value : list) {
                                parsed.append(value);
                            }
                        }
                        if (parsed.isEmpty()) {
                            const QString single = meta.value("genre").toString();
                            if (!single.trimmed().isEmpty()) {
                                parsed.append(single);
                            }
                        }
                        if (!parsed.isEmpty()) {
                            details.insert("genres", parsed);
                        }
                    }
                    emit mediaDetailsReceived(details);
                });
}

void ApiClient::fetchSeasons(const QString &seriesId) {
    if (seriesId.trimmed().isEmpty()) {
        return;
    }
    sendRequest("GET", QString("/api/v1/library/series/%1/seasons").arg(seriesId), QJsonObject(),
                [this, seriesId](const QJsonDocument &doc) {
                    if (!doc.isArray()) {
                        emit requestFailed("/api/v1/library/series/:id/seasons", "Seasons response was not a list.");
                        return;
                    }
                    emit seasonsReceived(seriesId, doc.array().toVariantList());
                });
}

void ApiClient::fetchSeasonDetail(const QString &seasonId) {
    if (seasonId.trimmed().isEmpty()) {
        return;
    }
    sendRequest("GET", QString("/api/v1/library/seasons/%1").arg(seasonId), QJsonObject(),
                [this, seasonId](const QJsonDocument &doc) {
                    if (!doc.isObject()) {
                        emit requestFailed("/api/v1/library/seasons/:id", "Season detail response was not an object.");
                        return;
                    }
                    emit seasonDetailReceived(seasonId, doc.object().toVariantMap());
                });
}

void ApiClient::fetchEpisodes(const QString &seasonId) {
    if (seasonId.trimmed().isEmpty()) {
        return;
    }
    sendRequest("GET", QString("/api/v1/library/seasons/%1/episodes").arg(seasonId), QJsonObject(),
                [this, seasonId](const QJsonDocument &doc) {
                    if (!doc.isArray()) {
                        emit requestFailed("/api/v1/library/seasons/:id/episodes", "Episodes response was not a list.");
                        return;
                    }
                    emit episodesReceived(seasonId, doc.array().toVariantList());
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
                [this, sessionId, seconds](const QJsonDocument &) {
                    emit seekCompleted(sessionId, seconds);
                },
                [this, sessionId](const QString &error) {
                    emit seekFailed(sessionId, error);
                },
                true);
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
                [](const QJsonDocument &) {},
                ErrorHandler(),
                true);
}

void ApiClient::runScan(bool forceMetadata) {
    const QString path = QString("/api/v1/library/scan?force_metadata=%1")
                             .arg(forceMetadata ? "true" : "false");
    sendRequest("POST", path, QJsonObject(),
                [this](const QJsonDocument &) { emit scanCompleted(); });
}

void ApiClient::fetchReviewQueue(const QString &status, int limit, int offset) {
    QString path = "/api/v1/library/review/queue";
    QUrlQuery query;
    if (!status.trimmed().isEmpty()) {
        query.addQueryItem("status", status.trimmed());
    }
    if (limit > 0) {
        query.addQueryItem("limit", QString::number(limit));
    }
    if (offset > 0) {
        query.addQueryItem("offset", QString::number(offset));
    }
    if (!query.isEmpty()) {
        path.append('?');
        path.append(query.toString(QUrl::FullyEncoded));
    }

    sendRequest("GET", path, QJsonObject(),
                [this](const QJsonDocument &doc) {
                    if (!doc.isArray()) {
                        emit requestFailed("/api/v1/library/review/queue", "Review queue response was not a list.");
                        return;
                    }
                    emit reviewQueueReceived(doc.array().toVariantList());
                });
}

void ApiClient::fetchReviewQueueDetail(const QString &reviewId) {
    if (reviewId.trimmed().isEmpty()) {
        return;
    }
    sendRequest("GET", QString("/api/v1/library/review/queue/%1").arg(reviewId), QJsonObject(),
                [this](const QJsonDocument &doc) {
                    if (!doc.isObject()) {
                        emit requestFailed("/api/v1/library/review/queue/:id", "Review detail response was not an object.");
                        return;
                    }
                    emit reviewDetailReceived(doc.object().toVariantMap());
                });
}

void ApiClient::applyReviewMatch(
    const QString &reviewId,
    const QString &libraryType,
    const QVariantMap &externalIds,
    const QString &normalizedKey) {
    if (reviewId.trimmed().isEmpty()) {
        emit requestFailed("/api/v1/library/review/queue/:id/apply", "Review id is required.");
        return;
    }
    QJsonObject body{{"library_type", libraryType.trimmed()}};
    if (!normalizedKey.trimmed().isEmpty()) {
        body.insert("normalized_key", normalizedKey.trimmed());
    }
    QJsonObject externalIdsObj;
    for (auto it = externalIds.constBegin(); it != externalIds.constEnd(); ++it) {
        if (it.value().isValid() && !it.value().toString().trimmed().isEmpty()) {
            externalIdsObj.insert(it.key(), QJsonValue::fromVariant(it.value()));
        }
    }
    body.insert("external_ids", externalIdsObj);

    sendRequest(
        "POST",
        QString("/api/v1/library/review/queue/%1/apply").arg(reviewId),
        body,
        [this, reviewId](const QJsonDocument &) { emit reviewApplied(reviewId); });
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
    const ErrorHandler &onError,
    bool allowNonJson) {
    if (m_baseUrl.trimmed().isEmpty()) {
        const QString msg = "Base URL is not set.";
        if (onError) {
            onError(msg);
        }
        emit requestFailed(path, msg);
        return;
    }

    const QStringList bodyKeys = body.keys();
    qInfo() << "API request" << method << path << "base" << m_baseUrl
            << "keys" << bodyKeys;

    QNetworkRequest request(makeUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    const QString locale = QLocale::system().name().replace('_', '-');
    if (!locale.trimmed().isEmpty()) {
        request.setRawHeader("Accept-Language", locale.toUtf8());
    }
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

    connect(reply, &QNetworkReply::finished, this, [this, reply, path, onSuccess, onError, allowNonJson]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray payload = reply->readAll();
        const bool okStatus = status >= 200 && status < 300;
        qInfo() << "API response" << path << "status" << status
                << "bytes" << payload.size() << "error" << reply->error();

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
            if (allowNonJson) {
                qInfo() << "API response (non-JSON)" << path << "bytes" << payload.size();
                onSuccess(QJsonDocument());
                reply->deleteLater();
                return;
            }
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
