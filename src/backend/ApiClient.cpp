#include "backend/ApiClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QUrlQuery>
#include <QDebug>
#include <QDateTime>
#include <QLocale>

namespace {
QString formatRegistryError(const QJsonValue &errorValue) {
    if (!errorValue.isObject()) {
        return QString();
    }
    const QJsonObject errorObj = errorValue.toObject();
    const QString url = errorObj.value("url").toString();
    const QString message = errorObj.value("error").toString();
    const QString occurredAt = errorObj.value("occurred_at").toString();
    QString errorMessage;
    if (!url.isEmpty()) {
        errorMessage = url;
    }
    if (!message.isEmpty()) {
        errorMessage = errorMessage.isEmpty() ? message : QString("%1 - %2").arg(errorMessage, message);
    }
    if (!occurredAt.isEmpty()) {
        errorMessage = errorMessage.isEmpty()
            ? occurredAt
            : QString("%1 (%2)").arg(errorMessage, occurredAt);
    }
    return errorMessage;
}

QString formatApiErrorDetail(const QByteArray &payload, const QString &fallback) {
    if (!payload.isEmpty()) {
        QJsonParseError parseError;
        const QJsonDocument doc = QJsonDocument::fromJson(payload, &parseError);
        if (parseError.error == QJsonParseError::NoError && doc.isObject()) {
            const QJsonObject obj = doc.object();
            const QString message = obj.value("message").toString().trimmed();
            if (!message.isEmpty()) {
                return message;
            }
            const QString error = obj.value("error").toString().trimmed();
            if (!error.isEmpty()) {
                return error;
            }
        }

        const QString text = QString::fromUtf8(payload).trimmed();
        if (!text.isEmpty()) {
            return text;
        }
    }

    const QString trimmedFallback = fallback.trimmed();
    return trimmedFallback.isEmpty() ? QString("Request failed.") : trimmedFallback;
}

QString normalizeMediaType(const QString &value) {
    const QString mediaType = value.trimmed().toLower();
    if (mediaType == "movie" || mediaType == "movies") {
        return "movies";
    }
    if (mediaType == "series" || mediaType == "tv") {
        return "tv";
    }
    if (mediaType == "anime") {
        return "anime";
    }
    return "movies";
}

QVariantMap normalizeFindMediaPreferencesPayload(const QVariantMap &payload) {
    const QVariantMap pref = payload.value("preferences").toMap();
    QVariantMap normalizedPref;
    normalizedPref.insert(
        "movieProviderId",
        pref.value(
            "moviesDefaultManagerProviderId",
            pref.value(
                "movies_default_manager_provider_id",
                pref.value("movieProviderId", pref.value("movie_provider_id")))));
    normalizedPref.insert(
        "seriesProviderId",
        pref.value(
            "tvDefaultManagerProviderId",
            pref.value(
                "tv_default_manager_provider_id",
                pref.value("seriesProviderId", pref.value("series_provider_id")))));
    normalizedPref.insert(
        "animeProviderId",
        pref.value(
            "animeDefaultManagerProviderId",
            pref.value(
                "anime_default_manager_provider_id",
                pref.value("animeProviderId", pref.value("anime_provider_id")))));

    QVariantMap normalized;
    normalized.insert("preferences", normalizedPref);
    normalized.insert(
        "movieProviders",
        payload.value(
            "moviesManagerCandidates",
            payload.value(
                "movies_manager_candidates",
                payload.value("movieProviders", payload.value("movie_providers")))));
    normalized.insert(
        "seriesProviders",
        payload.value(
            "tvManagerCandidates",
            payload.value(
                "tv_manager_candidates",
                payload.value("seriesProviders", payload.value("series_providers")))));
    normalized.insert(
        "animeProviders",
        payload.value(
            "animeManagerCandidates",
            payload.value(
                "anime_manager_candidates",
                payload.value("animeProviders", payload.value("anime_providers")))));
    return normalized;
}
} // namespace

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

bool ApiClient::accessTokenExpired(int skewSeconds) const {
    if (m_authToken.trimmed().isEmpty()) {
        return true;
    }
    if (m_accessTokenExpiresAt.trimmed().isEmpty()) {
        return false;
    }
    const QDateTime expiresAt = QDateTime::fromString(m_accessTokenExpiresAt, Qt::ISODate);
    if (!expiresAt.isValid()) {
        return false;
    }
    return expiresAt <= QDateTime::currentDateTimeUtc().addSecs(skewSeconds);
}

void ApiClient::expireAuth(const QString &message) {
    const QString detail = message.trimmed().isEmpty()
        ? QStringLiteral("Session expired. Please sign in again.")
        : message.trimmed();
    setAuthToken(QString());
    setAccessTokenExpiresAt(QString());
    emit authExpired(detail);
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

QVariantList ApiClient::extensionsInstalled() const {
    return m_extensionsInstalled;
}

QVariantList ApiClient::extensionsAvailable() const {
    return m_extensionsAvailable;
}

QVariantList ApiClient::extensionsCore() const {
    return m_extensionsCore;
}

QString ApiClient::extensionsLastRefreshedAt() const {
    return m_extensionsLastRefreshedAt;
}

QString ApiClient::extensionsLastRefreshSuccessAt() const {
    return m_extensionsLastRefreshSuccessAt;
}

QString ApiClient::extensionsLastRefreshError() const {
    return m_extensionsLastRefreshError;
}

QVariantList ApiClient::extensionsInstances() const {
    return m_extensionsInstances;
}

QVariantList ApiClient::extensionsSecrets() const {
    return m_extensionsSecrets;
}

QVariantMap ApiClient::extensionsPlan() const {
    return m_extensionsPlan;
}

QVariantList ApiClient::extensionsPlanConflicts() const {
    return m_extensionsPlanConflicts;
}

QString ApiClient::extensionsPlanId() const {
    return m_extensionsPlanId;
}

QVariantMap ApiClient::extensionsRun() const {
    return m_extensionsRun;
}

QVariantList ApiClient::extensionsRunSteps() const {
    return m_extensionsRunSteps;
}

QString ApiClient::extensionsRunId() const {
    return m_extensionsRunId;
}

QVariantList ApiClient::extensionsRuns() const {
    return m_extensionsRuns;
}

QVariantMap ApiClient::extensionsReconcileRun() const {
    return m_extensionsReconcileRun;
}

QVariantList ApiClient::extensionsDesiredBlueprints() const {
    return m_extensionsDesiredBlueprints;
}

QVariantList ApiClient::extensionsStatusItems() const {
    return m_extensionsStatusItems;
}

int ApiClient::extensionsNeedsAttentionCount() const {
    return m_extensionsNeedsAttentionCount;
}

QVariantMap ApiClient::extensionControlSurface() const {
    return m_extensionControlSurface;
}

bool ApiClient::extensionControlLoading() const {
    return m_extensionControlLoading;
}

bool ApiClient::extensionsAutoWireEnabled() const {
    return m_extensionsAutoWireEnabled;
}

QString ApiClient::extensionsAutoWirePendingPlanId() const {
    return m_extensionsAutoWirePendingPlanId;
}

QString ApiClient::extensionsAutoWirePendingReason() const {
    return m_extensionsAutoWirePendingReason;
}

int ApiClient::extensionsAutoWirePendingConflicts() const {
    return m_extensionsAutoWirePendingConflicts;
}

QString ApiClient::extensionsDownloaderProfile() const {
    return m_extensionsDownloaderProfile;
}

QString ApiClient::extensionsDownloaderDefaultProfile() const {
    return m_extensionsDownloaderDefaultProfile;
}

QString ApiClient::extensionsDownloaderProfileSource() const {
    return m_extensionsDownloaderProfileSource;
}

QString ApiClient::extensionsDownloaderProfileUpdatedAt() const {
    return m_extensionsDownloaderProfileUpdatedAt;
}

int ApiClient::extensionsDownloaderPendingUpdateCount() const {
    return m_extensionsDownloaderPendingUpdateCount;
}

QVariantList ApiClient::extensionsDownloaderProfileOptions() const {
    return m_extensionsDownloaderProfileOptions;
}

QVariantList ApiClient::extensionsDownloaderTelemetry() const {
    return m_extensionsDownloaderTelemetry;
}

QVariantMap ApiClient::mediaFindResult() const {
    return m_mediaFindResult;
}

bool ApiClient::mediaFindLoading() const {
    return m_mediaFindLoading;
}

QVariantMap ApiClient::mediaManagerPreferences() const {
    return m_mediaManagerPreferences;
}

QVariantMap ApiClient::mediaAddResult() const {
    return m_mediaAddResult;
}

bool ApiClient::mediaAddLoading() const {
    return m_mediaAddLoading;
}

QVariantMap ApiClient::mediaAcquisitionStatus() const {
    return m_mediaAcquisitionStatus;
}

QVariantList ApiClient::mediaAcquisitionItems() const {
    return m_mediaAcquisitionItems;
}

int ApiClient::mediaAcquisitionActiveCount() const {
    return m_mediaAcquisitionActiveCount;
}

int ApiClient::mediaAcquisitionDownloadingCount() const {
    return m_mediaAcquisitionDownloadingCount;
}

int ApiClient::mediaAcquisitionNeedsAttentionCount() const {
    return m_mediaAcquisitionNeedsAttentionCount;
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

void ApiClient::fetchExtensionsCatalog() {
    sendRequest(
        "GET",
        "/api/v1/extensions/catalog",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/catalog", "Extensions catalog response was not an object.");
                return;
            }
            updateExtensionsCatalog(doc.object());
        });
}

void ApiClient::refreshExtensionsCatalog() {
    sendRequest(
        "POST",
        "/api/v1/extensions/registries/refresh",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/registries/refresh", "Extensions refresh response was not an object.");
                return;
            }
            updateExtensionsCatalog(doc.object());
        });
}

void ApiClient::installExtension(const QString &downloadUrl) {
    const QString trimmed = downloadUrl.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/install", "Download URL is required.");
        return;
    }
    QJsonObject body{{"downloadUrl", trimmed}};
    sendRequest(
        "POST",
        "/api/v1/extensions/install",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/install", "Install response was not an object.");
                return;
            }
            fetchExtensionsCatalog();
            fetchExtensionInstances();
        });
}

void ApiClient::enableExtension(const QString &extensionId) {
    const QString trimmed = extensionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/enable", "Extension id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/%1/enable").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/:id/enable", "Enable response was not an object.");
                return;
            }
            fetchExtensionsCatalog();
            fetchExtensionInstances();
        });
}

void ApiClient::disableExtension(const QString &extensionId) {
    const QString trimmed = extensionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/disable", "Extension id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/%1/disable").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/:id/disable", "Disable response was not an object.");
                return;
            }
            fetchExtensionsCatalog();
            fetchExtensionInstances();
        });
}

void ApiClient::uninstallExtension(const QString &extensionId) {
    const QString trimmed = extensionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/uninstall", "Extension id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/%1/uninstall").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/:id/uninstall", "Uninstall response was not an object.");
                return;
            }
            fetchExtensionsCatalog();
            fetchExtensionInstances();
        });
}

void ApiClient::fetchExtensionInstances(const QString &extensionId) {
    QString path = "/api/v1/extensions/instances";
    if (!extensionId.trimmed().isEmpty()) {
        path = QString("%1?extension_id=%2")
                   .arg(path, QUrl::toPercentEncoding(extensionId));
    }
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isArray()) {
                emit requestFailed("/api/v1/extensions/instances", "Instances response was not a list.");
                return;
            }
            const QVariantList instances = doc.array().toVariantList();
            if (m_extensionsInstances != instances) {
                m_extensionsInstances = instances;
                emit extensionsInstancesChanged();
            }
        });
}

void ApiClient::createExtensionInstance(
    const QString &extensionId,
    const QString &instanceName,
    const QString &configJson) {
    const QString trimmed = extensionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/instances", "Extension id is required.");
        return;
    }
    QJsonObject body;
    if (!instanceName.trimmed().isEmpty()) {
        body.insert("instanceName", instanceName.trimmed());
    }
    if (!configJson.trimmed().isEmpty()) {
        QJsonParseError parseError{};
        const QJsonDocument parsed = QJsonDocument::fromJson(configJson.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            emit requestFailed("/api/v1/extensions/:id/instances", "Config JSON is invalid.");
            return;
        }
        if (parsed.isObject()) {
            body.insert("config", parsed.object());
        } else if (parsed.isArray()) {
            body.insert("config", parsed.array());
        } else if (!parsed.isNull()) {
            body.insert("config", QJsonValue::fromVariant(parsed.toVariant()));
        }
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/%1/instances").arg(trimmed),
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
            emit requestFailed("/api/v1/extensions/:id/instances", "Create instance response was not an object.");
            return;
        }
        fetchExtensionInstances();
    });
}

void ApiClient::updateExtensionInstanceConfig(const QString &instanceId, const QString &configJson) {
    const QString trimmed = instanceId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/instances/:id", "Instance id is required.");
        return;
    }
    QJsonObject body;
    const QString trimmedConfig = configJson.trimmed();
    if (trimmedConfig.isEmpty()) {
        body.insert("config", QJsonValue());
    } else {
        QJsonParseError parseError{};
        const QJsonDocument parsed = QJsonDocument::fromJson(trimmedConfig.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            emit requestFailed("/api/v1/extensions/instances/:id", "Config JSON is invalid.");
            return;
        }
        if (parsed.isObject()) {
            body.insert("config", parsed.object());
        } else if (parsed.isArray()) {
            body.insert("config", parsed.array());
        } else if (parsed.isNull()) {
            body.insert("config", QJsonValue());
        } else {
            body.insert("config", QJsonValue::fromVariant(parsed.toVariant()));
        }
    }
    sendRequest(
        "PATCH",
        QString("/api/v1/extensions/instances/%1").arg(trimmed),
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/instances/:id", "Update config response was not an object.");
                return;
            }
            fetchExtensionInstances();
        });
}

void ApiClient::setExtensionInstanceEnabled(const QString &instanceId, bool enabled) {
    const QString trimmed = instanceId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/instances/:id", "Instance id is required.");
        return;
    }
    QJsonObject body{{"enabled", enabled}};
    sendRequest(
        "PATCH",
        QString("/api/v1/extensions/instances/%1").arg(trimmed),
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/instances/:id", "Update instance response was not an object.");
                return;
            }
            fetchExtensionInstances();
        });
}

void ApiClient::deleteExtensionInstance(const QString &instanceId) {
    const QString trimmed = instanceId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/instances/:id", "Instance id is required.");
        return;
    }
    sendRequest(
        "DELETE",
        QString("/api/v1/extensions/instances/%1").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/instances/:id", "Delete instance response was not an object.");
                return;
            }
            fetchExtensionInstances();
            fetchInstanceSecrets();
        });
}

void ApiClient::rollbackExtensionInstance(const QString &instanceId) {
    const QString trimmed = instanceId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/instances/:id/rollback", "Instance id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/instances/%1/rollback").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/instances/:id/rollback", "Rollback response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            updateExtensionsPlan(obj);
            const QString planId = obj.contains("plan_id")
                ? obj.value("plan_id").toString()
                : obj.value("planId").toString();
            if (planId.isEmpty()) {
                emit requestFailed("/api/v1/extensions/instances/:id/rollback", "Rollback plan id missing.");
                return;
            }
            confirmExtensionsPlan(planId, QVariantList());
        });
}

void ApiClient::createSecret(
    const QString &scope,
    const QString &scopeId,
    const QString &key,
    const QString &value,
    bool rotatable) {
    const QString trimmedScope = scope.trimmed();
    const QString trimmedKey = key.trimmed();
    const QString trimmedScopeId = scopeId.trimmed();
    if (trimmedScope.isEmpty() || trimmedKey.isEmpty()) {
        emit requestFailed("/api/v1/extensions/secrets", "Scope and key are required.");
        return;
    }
    if ((trimmedScope == "instance" || trimmedScope == "provider") && trimmedScopeId.isEmpty()) {
        emit requestFailed("/api/v1/extensions/secrets", "Scope id is required for instance/provider secrets.");
        return;
    }
    QJsonObject body{
        {"scope", trimmedScope},
        {"key", trimmedKey},
        {"value", value}
    };
    if (!trimmedScopeId.isEmpty()) {
        body.insert("scopeId", trimmedScopeId);
    }
    if (rotatable) {
        body.insert("rotatable", true);
    }
    sendRequest(
        "POST",
        "/api/v1/extensions/secrets",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/secrets", "Create secret response was not an object.");
                return;
            }
            fetchInstanceSecrets();
        });
}

void ApiClient::createInstanceSecret(
    const QString &instanceId,
    const QString &key,
    const QString &value,
    bool rotatable) {
    createSecret("instance", instanceId, key, value, rotatable);
}

void ApiClient::fetchInstanceSecrets(const QString &instanceId) {
    const QString trimmedId = instanceId.trimmed();
    QString path;
    if (trimmedId.isEmpty()) {
        path = "/api/v1/extensions/secrets";
    } else {
        path = QString("/api/v1/extensions/secrets?scope=instance&scopeId=%1")
                   .arg(QUrl::toPercentEncoding(trimmedId));
    }
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isArray()) {
                emit requestFailed("/api/v1/extensions/secrets", "Secrets response was not a list.");
                return;
            }
            const QVariantList secrets = doc.array().toVariantList();
            if (m_extensionsSecrets != secrets) {
                m_extensionsSecrets = secrets;
                emit extensionsSecretsChanged();
            }
        });
}

void ApiClient::rotateSecret(const QString &secretId, const QString &value) {
    const QString trimmed = secretId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/secrets/:id/rotate", "Secret id is required.");
        return;
    }
    QJsonObject body;
    const QString trimmedValue = value.trimmed();
    if (!trimmedValue.isEmpty()) {
        body.insert("value", trimmedValue);
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/secrets/%1/rotate").arg(trimmed),
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/secrets/:id/rotate", "Rotate response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            emit secretRotated(obj.value("secret_id").toString(), obj.value("value").toString());
            fetchInstanceSecrets();
        });
}

void ApiClient::applyBlueprintPlan(const QString &blueprintId, const QString &paramsJson) {
    const QString trimmed = blueprintId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/blueprints/apply", "Blueprint id is required.");
        return;
    }
    QJsonObject body;
    body.insert("blueprint_id", trimmed);
    if (!paramsJson.trimmed().isEmpty()) {
        QJsonParseError parseError{};
        const QJsonDocument parsed = QJsonDocument::fromJson(paramsJson.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            emit requestFailed("/api/v1/extensions/blueprints/apply", "Params JSON is invalid.");
            return;
        }
        if (parsed.isObject()) {
            body.insert("params", parsed.object());
        } else if (parsed.isArray()) {
            body.insert("params", parsed.array());
        } else if (!parsed.isNull()) {
            body.insert("params", QJsonValue::fromVariant(parsed.toVariant()));
        }
    }
    sendRequest(
        "POST",
        "/api/v1/extensions/blueprints/apply",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/blueprints/apply", "Plan response was not an object.");
                return;
            }
            updateExtensionsPlan(doc.object());
            fetchDesiredBlueprints();
        });
}

void ApiClient::confirmExtensionsPlan(const QString &planId, const QVariantList &decisions) {
    const QString trimmed = planId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/plan/:id/confirm", "Plan id is required.");
        return;
    }
    QJsonObject body;
    if (!decisions.isEmpty()) {
        QJsonArray slotConflicts;
        for (const QVariant &entry : decisions) {
            const QVariantMap map = entry.toMap();
            const QString conflictId = map.value("conflictId").toString().trimmed();
            const QString action = map.value("action").toString().trimmed();
            if (conflictId.isEmpty() || action.isEmpty()) {
                continue;
            }
            QJsonObject item;
            item.insert("conflictId", conflictId);
            item.insert("action", action);
            slotConflicts.append(item);
        }
        if (!slotConflicts.isEmpty()) {
            QJsonObject decisionsObj;
            decisionsObj.insert("slotConflicts", slotConflicts);
            body.insert("decisions", decisionsObj);
        }
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/plan/%1/confirm").arg(trimmed),
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/plan/:id/confirm", "Plan confirm response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const QString runId = obj.value("run_id").toString();
            const QString status = obj.value("status").toString();
            const auto isTerminal = [](const QString &value) {
                return value == "completed" || value == "failed" || value == "canceled";
            };
            bool changed = false;
            if (!runId.isEmpty() && m_extensionsRunId != runId) {
                m_extensionsRunId = runId;
                if (!m_extensionsRunSteps.isEmpty()) {
                    m_extensionsRunSteps.clear();
                }
                changed = true;
            }
            if (!runId.isEmpty()) {
                QVariantMap runSummary = m_extensionsRun;
                runSummary.insert("run_id", runId);
                if (!status.isEmpty()) {
                    runSummary.insert("status", status);
                }
                if (m_extensionsRun != runSummary) {
                    m_extensionsRun = runSummary;
                    changed = true;
                }
                if (changed) {
                    emit extensionsRunChanged();
                }
                fetchExtensionRunDetail(runId);
                fetchExtensionRuns();
            }
            if (isTerminal(status)) {
                fetchExtensionInstances();
                fetchInstanceSecrets();
                fetchDesiredBlueprints();
                fetchAutoWireStatus();
                fetchManagerPreferences();
            } else {
                fetchDesiredBlueprints();
            }
            emit extensionsPlanChanged();
        });
}

void ApiClient::cancelExtensionsPlan(const QString &planId) {
    const QString trimmed = planId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/plan/:id/cancel", "Plan id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/plan/%1/cancel").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/plan/:id/cancel", "Plan cancel response was not an object.");
                return;
            }
            emit extensionsPlanChanged();
        });
}

void ApiClient::fetchExtensionRunDetail(const QString &runId) {
    const QString trimmed = runId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/runs/:id", "Run id is required.");
        return;
    }
    sendRequest(
        "GET",
        QString("/api/v1/extensions/runs/%1").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/runs/:id", "Run detail response was not an object.");
                return;
            }
            updateExtensionsRun(doc.object());
        });
}

void ApiClient::fetchExtensionRuns(int limit) {
    const int effectiveLimit = limit > 0 ? limit : 50;
    const QString path = QString("/api/v1/extensions/runs?limit=%1").arg(effectiveLimit);
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isArray()) {
                emit requestFailed("/api/v1/extensions/runs", "Runs response was not a list.");
                return;
            }
            const QVariantList runs = doc.array().toVariantList();
            if (m_extensionsRuns != runs) {
                m_extensionsRuns = runs;
                emit extensionsRunsChanged();
            }
        });
}

void ApiClient::clearExtensionRuns() {
    sendRequest(
        "DELETE",
        "/api/v1/extensions/runs",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/runs", "Clear runs response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const int deleted = obj.value("deleted").toInt();
            emit runsCleared(deleted);
            fetchExtensionRuns();
        });
}

void ApiClient::fetchLatestReconcileRun() {
    sendRequest(
        "GET",
        "/api/v1/extensions/reconcile/latest",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/reconcile/latest", "Reconcile response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const QJsonObject runObj = obj.value("run").toObject();
            const QVariantMap run = runObj.toVariantMap();
            if (m_extensionsReconcileRun != run) {
                m_extensionsReconcileRun = run;
                emit extensionsReconcileRunChanged();
            }
        });
}

void ApiClient::reconcileNow() {
    sendRequest(
        "POST",
        "/api/v1/extensions/reconcile/now",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/reconcile/now", "Reconcile response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const QJsonObject runObj = obj.value("run").toObject();
            const QVariantMap run = runObj.toVariantMap();
            if (m_extensionsReconcileRun != run) {
                m_extensionsReconcileRun = run;
                emit extensionsReconcileRunChanged();
            }
            fetchExtensionRuns();
            fetchExtensionInstances();
            fetchDesiredBlueprints();
            fetchAutoWireStatus();
        });
}

void ApiClient::fetchDesiredBlueprints(const QString &applied) {
    QString path = "/api/v1/extensions/desired-blueprints";
    const QString trimmed = applied.trimmed().toLower();
    if (trimmed == "true" || trimmed == "false") {
        path = QString("%1?applied=%2").arg(path, trimmed);
    }
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isArray()) {
                emit requestFailed("/api/v1/extensions/desired-blueprints", "Desired blueprints response was not a list.");
                return;
            }
            const QVariantList items = doc.array().toVariantList();
            if (m_extensionsDesiredBlueprints != items) {
                m_extensionsDesiredBlueprints = items;
                emit extensionsDesiredBlueprintsChanged();
            }
        });
}

void ApiClient::clearDesiredBlueprints(const QString &applied) {
    QString path = "/api/v1/extensions/desired-blueprints";
    const QString trimmed = applied.trimmed().toLower();
    if (trimmed == "true" || trimmed == "false") {
        path = QString("%1?applied=%2").arg(path, trimmed);
    }
    sendRequest(
        "DELETE",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/desired-blueprints", "Desired blueprints clear response was not an object.");
                return;
            }
            const int deleted = doc.object().value("deleted").toInt();
            emit desiredBlueprintsCleared(deleted);
            fetchDesiredBlueprints();
        });
}

void ApiClient::fetchExtensionStatusSummary() {
    sendRequest(
        "GET",
        "/api/v1/extensions/status-summary",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/status-summary", "Extension status response was not an object.");
                return;
            }
            updateExtensionStatusSummary(doc.object());
        });
}

void ApiClient::fetchExtensionControlSurface(const QString &extensionId) {
    const QString trimmed = extensionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/control-surface", "Extension id is required.");
        return;
    }
    if (!m_extensionControlLoading) {
        m_extensionControlLoading = true;
        emit extensionControlLoadingChanged();
    }
    sendRequest(
        "GET",
        QString("/api/v1/extensions/%1/control-surface").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                if (m_extensionControlLoading) {
                    m_extensionControlLoading = false;
                    emit extensionControlLoadingChanged();
                }
                emit requestFailed(
                    "/api/v1/extensions/:id/control-surface",
                    "Control surface response was not an object.");
                return;
            }
            updateExtensionControlSurfaceState(doc.object());
            if (m_extensionControlLoading) {
                m_extensionControlLoading = false;
                emit extensionControlLoadingChanged();
            }
        },
        [this](const QString &) {
            if (m_extensionControlLoading) {
                m_extensionControlLoading = false;
                emit extensionControlLoadingChanged();
            }
        });
}

void ApiClient::updateExtensionControlSurfaceSettings(
    const QString &extensionId,
    const QVariantMap &values) {
    const QString trimmed = extensionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/control-surface", "Extension id is required.");
        return;
    }
    if (!m_extensionControlLoading) {
        m_extensionControlLoading = true;
        emit extensionControlLoadingChanged();
    }
    QJsonObject body;
    body.insert("values", QJsonObject::fromVariantMap(values));
    sendRequest(
        "PUT",
        QString("/api/v1/extensions/%1/control-surface").arg(trimmed),
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                if (m_extensionControlLoading) {
                    m_extensionControlLoading = false;
                    emit extensionControlLoadingChanged();
                }
                emit requestFailed(
                    "/api/v1/extensions/:id/control-surface",
                    "Control surface update response was not an object.");
                return;
            }
            updateExtensionControlSurfaceState(doc.object());
            if (m_extensionControlLoading) {
                m_extensionControlLoading = false;
                emit extensionControlLoadingChanged();
            }
        },
        [this](const QString &) {
            if (m_extensionControlLoading) {
                m_extensionControlLoading = false;
                emit extensionControlLoadingChanged();
            }
        });
}

void ApiClient::invokeExtensionControlAction(
    const QString &extensionId,
    const QString &actionId,
    const QVariantMap &params) {
    const QString trimmedExtensionId = extensionId.trimmed();
    const QString trimmedActionId = actionId.trimmed();
    if (trimmedExtensionId.isEmpty() || trimmedActionId.isEmpty()) {
        emit requestFailed(
            "/api/v1/extensions/:id/control-surface/actions/:action_id",
            "Extension id and action id are required.");
        return;
    }
    if (!m_extensionControlLoading) {
        m_extensionControlLoading = true;
        emit extensionControlLoadingChanged();
    }
    QJsonObject body;
    if (!params.isEmpty()) {
        body.insert("params", QJsonObject::fromVariantMap(params));
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/%1/control-surface/actions/%2")
            .arg(trimmedExtensionId, trimmedActionId),
        body,
        [this, trimmedExtensionId, trimmedActionId](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                if (m_extensionControlLoading) {
                    m_extensionControlLoading = false;
                    emit extensionControlLoadingChanged();
                }
                emit requestFailed(
                    "/api/v1/extensions/:id/control-surface/actions/:action_id",
                    "Control action response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            updateExtensionControlSurfaceState(obj.value("controlSurface").toObject());
            if (m_extensionControlLoading) {
                m_extensionControlLoading = false;
                emit extensionControlLoadingChanged();
            }
            emit extensionControlActionCompleted(
                trimmedExtensionId,
                trimmedActionId,
                obj.value("message").toString());
        },
        [this](const QString &) {
            if (m_extensionControlLoading) {
                m_extensionControlLoading = false;
                emit extensionControlLoadingChanged();
            }
        });
}

void ApiClient::fetchAutoWireStatus() {
    sendRequest(
        "GET",
        "/api/v1/extensions/auto-wire",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/auto-wire", "Auto-wire response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const bool enabled = obj.value("enabled").toBool(m_extensionsAutoWireEnabled);
            const QString pendingPlanId = obj.value("pendingPlanId").toString();
            const QString pendingReason = obj.value("pendingReason").toString();
            const int pendingConflicts = obj.value("pendingConflicts").toInt();

            bool changed = false;
            if (m_extensionsAutoWireEnabled != enabled) {
                m_extensionsAutoWireEnabled = enabled;
                changed = true;
            }
            if (m_extensionsAutoWirePendingPlanId != pendingPlanId) {
                m_extensionsAutoWirePendingPlanId = pendingPlanId;
                changed = true;
            }
            if (m_extensionsAutoWirePendingReason != pendingReason) {
                m_extensionsAutoWirePendingReason = pendingReason;
                changed = true;
            }
            if (m_extensionsAutoWirePendingConflicts != pendingConflicts) {
                m_extensionsAutoWirePendingConflicts = pendingConflicts;
                changed = true;
            }
            if (changed) {
                emit extensionsAutoWireStatusChanged();
            }
        });
}

void ApiClient::setAutoWireEnabled(bool enabled) {
    QJsonObject body{{"enabled", enabled}};
    sendRequest(
        "POST",
        "/api/v1/extensions/auto-wire",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/auto-wire", "Auto-wire response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const bool nextEnabled = obj.value("enabled").toBool(m_extensionsAutoWireEnabled);
            const QString pendingPlanId = obj.value("pendingPlanId").toString();
            const QString pendingReason = obj.value("pendingReason").toString();
            const int pendingConflicts = obj.value("pendingConflicts").toInt();

            bool changed = false;
            if (m_extensionsAutoWireEnabled != nextEnabled) {
                m_extensionsAutoWireEnabled = nextEnabled;
                changed = true;
            }
            if (m_extensionsAutoWirePendingPlanId != pendingPlanId) {
                m_extensionsAutoWirePendingPlanId = pendingPlanId;
                changed = true;
            }
            if (m_extensionsAutoWirePendingReason != pendingReason) {
                m_extensionsAutoWirePendingReason = pendingReason;
                changed = true;
            }
            if (m_extensionsAutoWirePendingConflicts != pendingConflicts) {
                m_extensionsAutoWirePendingConflicts = pendingConflicts;
                changed = true;
            }
            if (changed) {
                emit extensionsAutoWireStatusChanged();
            }
        });
}

void ApiClient::fetchAutoWirePlan() {
    sendRequest(
        "GET",
        "/api/v1/extensions/auto-wire/plan",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/auto-wire/plan", "Auto-wire plan response was not an object.");
                return;
            }
            updateExtensionsPlan(doc.object());
        });
}

void ApiClient::fetchDownloaderProfile() {
    sendRequest(
        "GET",
        "/api/v1/extensions/downloaders/profile",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/downloaders/profile", "Downloader profile response was not an object.");
                return;
            }
            updateDownloaderProfileState(doc.object());
        });
}

void ApiClient::updateDownloaderProfile(const QString &profile) {
    const QString trimmed = profile.trimmed().toLower();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/downloaders/profile", "Downloader profile is required.");
        return;
    }
    QJsonObject body{{"profile", trimmed}};
    sendRequest(
        "PATCH",
        "/api/v1/extensions/downloaders/profile",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/downloaders/profile", "Downloader profile response was not an object.");
                return;
            }
            updateDownloaderProfileState(doc.object());
        });
}

void ApiClient::updateDownloaderProfileState(const QJsonObject &obj) {
    const QString profile = obj.value("profile").toString();
    const QString defaultProfile = obj.value("defaultProfile").toString();
    const QString source = obj.value("source").toString();
    const QString updatedAt = obj.value("updatedAt").toString();
    const int pendingUpdates = obj.value("pendingUpdateCount").toInt();
    const QVariantList options = obj.value("profiles").toArray().toVariantList();
    const QVariantList telemetry = obj.value("downloaders").toArray().toVariantList();

    bool changed = false;
    if (m_extensionsDownloaderProfile != profile) {
        m_extensionsDownloaderProfile = profile;
        changed = true;
    }
    if (m_extensionsDownloaderDefaultProfile != defaultProfile) {
        m_extensionsDownloaderDefaultProfile = defaultProfile;
        changed = true;
    }
    if (m_extensionsDownloaderProfileSource != source) {
        m_extensionsDownloaderProfileSource = source;
        changed = true;
    }
    if (m_extensionsDownloaderProfileUpdatedAt != updatedAt) {
        m_extensionsDownloaderProfileUpdatedAt = updatedAt;
        changed = true;
    }
    if (m_extensionsDownloaderPendingUpdateCount != pendingUpdates) {
        m_extensionsDownloaderPendingUpdateCount = pendingUpdates;
        changed = true;
    }
    if (m_extensionsDownloaderProfileOptions != options) {
        m_extensionsDownloaderProfileOptions = options;
        changed = true;
    }
    if (m_extensionsDownloaderTelemetry != telemetry) {
        m_extensionsDownloaderTelemetry = telemetry;
        changed = true;
    }
    if (changed) {
        emit extensionsDownloaderSettingsChanged();
    }
}

void ApiClient::updateMediaAcquisitionState(const QJsonObject &obj) {
    const QVariantMap status = obj.toVariantMap();
    const QVariantList items = obj.value("items").toArray().toVariantList();
    const int activeCount = obj.value("activeCount").toInt();
    const int downloadingCount = obj.value("downloadingCount").toInt();
    const int needsAttentionCount = obj.value("needsAttentionCount").toInt();

    bool changed = false;
    if (m_mediaAcquisitionStatus != status) {
        m_mediaAcquisitionStatus = status;
        changed = true;
    }
    if (m_mediaAcquisitionItems != items) {
        m_mediaAcquisitionItems = items;
        changed = true;
    }
    if (m_mediaAcquisitionActiveCount != activeCount) {
        m_mediaAcquisitionActiveCount = activeCount;
        changed = true;
    }
    if (m_mediaAcquisitionDownloadingCount != downloadingCount) {
        m_mediaAcquisitionDownloadingCount = downloadingCount;
        changed = true;
    }
    if (m_mediaAcquisitionNeedsAttentionCount != needsAttentionCount) {
        m_mediaAcquisitionNeedsAttentionCount = needsAttentionCount;
        changed = true;
    }
    if (changed) {
        emit mediaAcquisitionChanged();
    }
}

void ApiClient::fetchMediaAcquisition(int limit) {
    QUrlQuery query;
    query.addQueryItem("limit", QString::number(qBound(1, limit, 50)));
    const QString path = QString("/api/v1/find/acquisition?%1")
                             .arg(query.toString(QUrl::FullyEncoded));
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/find/acquisition", "Acquisition response was not an object.");
                return;
            }
            updateMediaAcquisitionState(doc.object());
        });
}

void ApiClient::findMedia(
    const QString &query,
    const QString &mediaType,
    const QVariantList &providerIds) {
    const QString trimmedQuery = query.trimmed();
    const QString normalizedType = normalizeMediaType(mediaType);
    const quint64 requestId = ++m_mediaFindRequestId;
    if (trimmedQuery.isEmpty()) {
        if (m_mediaFindLoading) {
            m_mediaFindLoading = false;
        }
        m_mediaFindLoading = true;
        emit mediaFindLoadingChanged();

        QUrlQuery targetsQuery;
        targetsQuery.addQueryItem("media_type", normalizedType);
        const QString targetsPath = QString("/api/v1/find/targets?%1")
                                        .arg(targetsQuery.toString(QUrl::FullyEncoded));

        sendRequest(
            "GET",
            targetsPath,
            QJsonObject(),
            [this, requestId, normalizedType](const QJsonDocument &targetsDoc) {
                if (requestId != m_mediaFindRequestId) {
                    return;
                }
                if (!targetsDoc.isObject()) {
                    if (m_mediaFindLoading) {
                        m_mediaFindLoading = false;
                        emit mediaFindLoadingChanged();
                    }
                    emit requestFailed("/api/v1/find/targets", "Targets response was not an object.");
                    return;
                }
                const QJsonObject targetsObject = targetsDoc.object();
                QJsonObject merged;
                merged.insert("query", "");
                merged.insert("mediaType", normalizedType);
                merged.insert("results", QJsonArray());
                merged.insert("providerErrors", QJsonArray());
                merged.insert("searchProviders", targetsObject.value("searchProviders"));
                merged.insert("managerProviders", targetsObject.value("managerCandidates"));
                merged.insert("defaultManagerProviderId", targetsObject.value("defaultManagerProviderId"));
                merged.insert("preferredManagerProviderId", targetsObject.value("preferredManagerProviderId"));

                const QVariantMap result = merged.toVariantMap();
                if (m_mediaFindResult != result) {
                    m_mediaFindResult = result;
                    emit mediaFindResultChanged();
                }
                if (m_mediaFindLoading) {
                    m_mediaFindLoading = false;
                    emit mediaFindLoadingChanged();
                }
            },
            [this, requestId](const QString &) {
                if (requestId != m_mediaFindRequestId) {
                    return;
                }
                if (m_mediaFindLoading) {
                    m_mediaFindLoading = false;
                    emit mediaFindLoadingChanged();
                }
            });
        return;
    }

    QJsonArray providerArray;
    for (const QVariant &entry : providerIds) {
        const QString providerId = entry.toString().trimmed();
        if (!providerId.isEmpty()) {
            providerArray.append(providerId);
        }
    }

    if (!m_mediaFindLoading) {
        m_mediaFindLoading = true;
        emit mediaFindLoadingChanged();
    }

    QUrlQuery targetsQuery;
    targetsQuery.addQueryItem("media_type", normalizedType);
    const QString targetsPath = QString("/api/v1/find/targets?%1")
                                    .arg(targetsQuery.toString(QUrl::FullyEncoded));

    sendRequest(
        "GET",
        targetsPath,
        QJsonObject(),
        [this, requestId, trimmedQuery, normalizedType, providerArray](const QJsonDocument &targetsDoc) {
            if (requestId != m_mediaFindRequestId) {
                return;
            }
            if (!targetsDoc.isObject()) {
                if (m_mediaFindLoading) {
                    m_mediaFindLoading = false;
                    emit mediaFindLoadingChanged();
                }
                emit requestFailed("/api/v1/find/targets", "Targets response was not an object.");
                return;
            }
            QJsonObject searchBody;
            searchBody.insert("mediaType", normalizedType);
            searchBody.insert("query", trimmedQuery);
            if (!providerArray.isEmpty()) {
                searchBody.insert("providers", providerArray);
            }
            const QJsonObject targetsObject = targetsDoc.object();
            sendRequest(
                "POST",
                "/api/v1/find/search",
                searchBody,
                [this, requestId, targetsObject](const QJsonDocument &searchDoc) {
                    if (requestId != m_mediaFindRequestId) {
                        return;
                    }
                    if (!searchDoc.isObject()) {
                        if (m_mediaFindLoading) {
                            m_mediaFindLoading = false;
                            emit mediaFindLoadingChanged();
                        }
                        emit requestFailed("/api/v1/find/search", "Search response was not an object.");
                        return;
                    }
                    QJsonObject merged = searchDoc.object();
                    merged.insert("searchProviders", targetsObject.value("searchProviders"));
                    merged.insert("managerProviders", targetsObject.value("managerCandidates"));
                    merged.insert("defaultManagerProviderId", targetsObject.value("defaultManagerProviderId"));
                    merged.insert("preferredManagerProviderId", targetsObject.value("preferredManagerProviderId"));

                    const QVariantMap result = merged.toVariantMap();
                    if (m_mediaFindResult != result) {
                        m_mediaFindResult = result;
                        emit mediaFindResultChanged();
                    }
                    if (m_mediaFindLoading) {
                        m_mediaFindLoading = false;
                        emit mediaFindLoadingChanged();
                    }
                },
                [this, requestId](const QString &) {
                    if (requestId != m_mediaFindRequestId) {
                        return;
                    }
                    if (m_mediaFindLoading) {
                        m_mediaFindLoading = false;
                        emit mediaFindLoadingChanged();
                    }
                });
        },
        [this, requestId](const QString &) {
            if (requestId != m_mediaFindRequestId) {
                return;
            }
            if (m_mediaFindLoading) {
                m_mediaFindLoading = false;
                emit mediaFindLoadingChanged();
            }
        });
}

void ApiClient::addMediaToManager(
    const QString &mediaType,
    const QVariantMap &item,
    const QString &managerProviderId,
    const QVariantMap &options) {
    QJsonObject body;
    body.insert("mediaType", normalizeMediaType(mediaType));
    body.insert("item", QJsonObject::fromVariantMap(item));
    const QString trimmedManager = managerProviderId.trimmed();
    if (!trimmedManager.isEmpty()) {
        body.insert("managerProviderId", trimmedManager);
    }
    if (!options.isEmpty()) {
        body.insert("options", QJsonObject::fromVariantMap(options));
    }

    if (!m_mediaAddLoading) {
        m_mediaAddLoading = true;
        emit mediaAddLoadingChanged();
    }
    sendRequest(
        "POST",
        "/api/v1/find/add",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                if (m_mediaAddLoading) {
                    m_mediaAddLoading = false;
                    emit mediaAddLoadingChanged();
                }
                emit requestFailed("/api/v1/find/add", "Add response was not an object.");
                return;
            }
            const QVariantMap result = doc.object().toVariantMap();
            if (m_mediaAddResult != result) {
                m_mediaAddResult = result;
                emit mediaAddResultChanged();
            }
            if (m_mediaAddLoading) {
                m_mediaAddLoading = false;
                emit mediaAddLoadingChanged();
            }
        },
        [this](const QString &) {
            if (m_mediaAddLoading) {
                m_mediaAddLoading = false;
                emit mediaAddLoadingChanged();
            }
        });
}

void ApiClient::fetchManagerPreferences() {
    sendRequest(
        "GET",
        "/api/v1/find/preferences",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/find/preferences",
                    "Manager preferences response was not an object.");
                return;
            }
            const QVariantMap payload = normalizeFindMediaPreferencesPayload(doc.object().toVariantMap());
            if (m_mediaManagerPreferences != payload) {
                m_mediaManagerPreferences = payload;
                emit mediaManagerPreferencesChanged();
            }
        });
}

void ApiClient::updateManagerPreferences(
    const QString &movieProviderId,
    const QString &seriesProviderId,
    const QString &animeProviderId) {
    QJsonObject body;
    const QString movie = movieProviderId.trimmed();
    const QString series = seriesProviderId.trimmed();
    const QString anime = animeProviderId.trimmed();
    body.insert(
        "moviesDefaultManagerProviderId",
        movie.isEmpty() ? QJsonValue::Null : QJsonValue(movie));
    body.insert(
        "tvDefaultManagerProviderId",
        series.isEmpty() ? QJsonValue::Null : QJsonValue(series));
    body.insert(
        "animeDefaultManagerProviderId",
        anime.isEmpty() ? QJsonValue::Null : QJsonValue(anime));

    sendRequest(
        "PATCH",
        "/api/v1/find/preferences",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/find/preferences",
                    "Manager preferences update response was not an object.");
                return;
            }
            const QVariantMap payload = normalizeFindMediaPreferencesPayload(doc.object().toVariantMap());
            if (m_mediaManagerPreferences != payload) {
                m_mediaManagerPreferences = payload;
                emit mediaManagerPreferencesChanged();
            }
        });
}

void ApiClient::updateExtensionsCatalog(const QJsonObject &obj) {
    const QVariantList installed = obj.value("installed").toArray().toVariantList();
    const QVariantList available = obj.value("available").toArray().toVariantList();
    const QVariantList core = obj.value("core_extensions").toArray().toVariantList();
    const QString refreshedAt = obj.value("last_refreshed_at").toString();
    const QString successAt = obj.value("last_refresh_success_at").toString();
    const QString errorMessage = formatRegistryError(obj.value("last_refresh_error"));

    if (m_extensionsInstalled != installed || m_extensionsAvailable != available || m_extensionsCore != core) {
        m_extensionsInstalled = installed;
        m_extensionsAvailable = available;
        m_extensionsCore = core;
        emit extensionsCatalogChanged();
    }
    if (m_extensionsLastRefreshedAt != refreshedAt) {
        m_extensionsLastRefreshedAt = refreshedAt;
        emit extensionsLastRefreshedAtChanged();
    }
    if (m_extensionsLastRefreshSuccessAt != successAt) {
        m_extensionsLastRefreshSuccessAt = successAt;
        emit extensionsLastRefreshSuccessAtChanged();
    }
    if (m_extensionsLastRefreshError != errorMessage) {
        m_extensionsLastRefreshError = errorMessage;
        emit extensionsLastRefreshErrorChanged();
    }
}

void ApiClient::updateExtensionsPlan(const QJsonObject &obj) {
    const QVariantMap plan = obj.toVariantMap();
    const QJsonValue planIdValue = obj.contains("plan_id")
        ? obj.value("plan_id")
        : obj.value("planId");
    const QString planId = planIdValue.toString();
    const QVariantList conflicts = obj.value("conflicts").toArray().toVariantList();

    bool changed = false;
    if (m_extensionsPlan != plan) {
        m_extensionsPlan = plan;
        changed = true;
    }
    if (m_extensionsPlanConflicts != conflicts) {
        m_extensionsPlanConflicts = conflicts;
        changed = true;
    }
    if (m_extensionsPlanId != planId) {
        m_extensionsPlanId = planId;
        changed = true;
    }
    if (changed) {
        emit extensionsPlanChanged();
    }
}

void ApiClient::updateExtensionsRun(const QJsonObject &obj) {
    const QJsonObject runObj = obj.value("run").toObject();
    const QVariantMap run = runObj.toVariantMap();
    const QVariantList steps = obj.value("steps").toArray().toVariantList();
    const QString runId = runObj.value("run_id").toString();
    const QString prevStatus = m_extensionsRun.value("status").toString();
    const QString nextStatus = runObj.value("status").toString();

    bool changed = false;
    if (m_extensionsRun != run) {
        m_extensionsRun = run;
        changed = true;
    }
    if (m_extensionsRunSteps != steps) {
        m_extensionsRunSteps = steps;
        changed = true;
    }
    if (!runId.isEmpty() && m_extensionsRunId != runId) {
        m_extensionsRunId = runId;
        changed = true;
    }
    if (changed) {
        emit extensionsRunChanged();
    }
    const auto isTerminal = [](const QString &status) {
        return status == "completed" || status == "failed" || status == "canceled";
    };
    if (isTerminal(nextStatus) && !isTerminal(prevStatus)) {
        fetchExtensionInstances();
        fetchInstanceSecrets();
        fetchDesiredBlueprints();
        fetchAutoWireStatus();
        fetchManagerPreferences();
    }
}

void ApiClient::updateExtensionStatusSummary(const QJsonObject &obj) {
    const QVariantList items = obj.value("items").toArray().toVariantList();
    const int needsAttention = obj.value("needsAttentionCount").toInt();

    bool changed = false;
    if (m_extensionsStatusItems != items) {
        m_extensionsStatusItems = items;
        changed = true;
    }
    if (m_extensionsNeedsAttentionCount != needsAttention) {
        m_extensionsNeedsAttentionCount = needsAttention;
        changed = true;
    }
    if (changed) {
        emit extensionsStatusSummaryChanged();
    }
}

void ApiClient::updateExtensionControlSurfaceState(const QJsonObject &obj) {
    const QVariantMap surface = obj.toVariantMap();
    if (m_extensionControlSurface != surface) {
        m_extensionControlSurface = surface;
        emit extensionControlSurfaceChanged();
    }
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
            const QString detail = formatApiErrorDetail(payload, reply->errorString());
            if (status == 401 && !path.startsWith("/api/v1/auth/")) {
                expireAuth(detail.isEmpty() ? "Authentication expired." : detail);
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
