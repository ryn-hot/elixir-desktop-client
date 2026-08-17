#include "backend/ApiClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QUrlQuery>
#include <QDebug>
#include <QDateTime>
#include <QEventLoop>
#include <QCoreApplication>
#include <QLocale>
#include <QSysInfo>
#include <QTimer>
#include <algorithm>
#include <cmath>
#include <utility>

namespace {
constexpr int kMaxPendingAuthRequests = 256;

QString encodedPathSegment(const QString &value) {
    return QString::fromUtf8(QUrl::toPercentEncoding(value));
}

QString extensionControlPath(const QString &extensionId,
                             const QString &instanceId = QString(),
                             const QString &actionId = QString()) {
    QString path = QString("/api/v1/extensions/%1/control-surface")
                       .arg(encodedPathSegment(extensionId));
    if (!actionId.trimmed().isEmpty()) {
        path += QString("/actions/%1")
                    .arg(encodedPathSegment(actionId.trimmed()));
    }
    QUrl url(path);
    if (!instanceId.trimmed().isEmpty()) {
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("instanceId"), instanceId.trimmed());
        url.setQuery(query);
    }
    return url.toString(QUrl::FullyEncoded);
}

QString extensionAccountSetupPath(const QString &extensionId,
                                  const QString &instanceId,
                                  const QString &setupId = QString()) {
    QString path = QString("/api/v1/extensions/%1/instances/%2/account-setup")
                       .arg(encodedPathSegment(extensionId),
                            encodedPathSegment(instanceId));
    if (!setupId.trimmed().isEmpty()) {
        path += "/" + encodedPathSegment(setupId.trimmed());
    }
    return path;
}

void addClientSessionContext(QJsonObject &body, bool includeRememberDevice) {
    if (includeRememberDevice) {
        body.insert("remember_device", true);
    }
    body.insert("device_name", QSysInfo::machineHostName());
    body.insert("device_type", QStringLiteral("desktop"));
    body.insert("client_name", QStringLiteral("elixir-client"));
    body.insert("client_version", QCoreApplication::applicationVersion());
}

bool isSafeToken(const QString &value) {
    if (value.isEmpty() || value.size() > 8192) {
        return false;
    }
    for (const QChar character : value) {
        const ushort code = character.unicode();
        const bool allowed = (code >= 'a' && code <= 'z')
            || (code >= 'A' && code <= 'Z')
            || (code >= '0' && code <= '9')
            || code == '-'
            || code == '_'
            || code == '.'
            || code == '~';
        if (!allowed) {
            return false;
        }
    }
    return true;
}

QVariantMap parseApiErrorPayload(
    const QByteArray &payload,
    const QString &fallback,
    int status,
    const QString &path);

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
    const QVariantMap error = parseApiErrorPayload(payload, fallback, 0, QString());
    const QString message = error.value("message").toString().trimmed();
    if (!message.isEmpty()) {
        return message;
    }
    const QString rawText = error.value("rawText").toString().trimmed();
    if (!rawText.isEmpty()) {
        return rawText;
    }
    const QString trimmedFallback = fallback.trimmed();
    return trimmedFallback.isEmpty() ? QString("Request failed.") : trimmedFallback;
}

QVariantMap parseApiErrorPayload(
    const QByteArray &payload,
    const QString &fallback,
    int status,
    const QString &path) {
    QVariantMap result;
    result.insert("endpoint", path);
    if (status > 0) {
        result.insert("status", status);
    }

    if (!payload.isEmpty()) {
        QJsonParseError parseError;
        const QJsonDocument doc = QJsonDocument::fromJson(payload, &parseError);
        if (parseError.error == QJsonParseError::NoError && doc.isObject()) {
            const QJsonObject obj = doc.object();
            const QString code = obj.value("code").toString().trimmed();
            if (!code.isEmpty()) {
                result.insert("code", code);
            }
            const QString message = obj.value("message").toString().trimmed();
            if (!message.isEmpty()) {
                result.insert("message", message);
            }
            const QString error = obj.value("error").toString().trimmed();
            if (!error.isEmpty() && !result.contains("message")) {
                result.insert("message", error);
            }
            const QJsonValue details = obj.value("details");
            if (details.isObject()) {
                const QVariantMap detailsMap = details.toObject().toVariantMap();
                result.insert("details", detailsMap);
                const QVariant retry = detailsMap.value("retry");
                if (retry.isValid()) {
                    result.insert("retry", retry);
                }
                const QVariant fallbackDetail = detailsMap.value("fallback");
                if (fallbackDetail.isValid()) {
                    result.insert("fallback", fallbackDetail);
                }
            }
            if (result.contains("message")) {
                return result;
            }
        }

        const QString text = QString::fromUtf8(payload).trimmed();
        if (!text.isEmpty()) {
            result.insert("rawText", text);
            if (!result.contains("message")) {
                result.insert("message", text);
            }
            return result;
        }
    }

    const QString trimmedFallback = fallback.trimmed();
    result.insert("message", trimmedFallback.isEmpty() ? QString("Request failed.") : trimmedFallback);
    return result;
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

QString normalizeAcquisitionMediaType(const QString &value) {
    const QString mediaType = value.trimmed().toLower();
    if (mediaType == "movie" || mediaType == "movies") {
        return "movie";
    }
    if (mediaType == "series" || mediaType == "tv") {
        return "series";
    }
    if (mediaType == "anime") {
        return "anime";
    }
    return "movie";
}

QJsonObject findMediaScopedIdentity(const QString &mediaType, const QVariantMap &item) {
    QJsonObject result = QJsonObject::fromVariantMap(item);
    const QString normalizedType = normalizeAcquisitionMediaType(mediaType);
    result.insert("kind", normalizedType);

    QString title = item.value("title", item.value("name")).toString().trimmed();
    if (title.isEmpty()) {
        title = result.value("title").toString(result.value("name").toString()).trimmed();
    }
    if (!title.isEmpty()) {
        result.insert("title", title);
    }

    const QVariant year = item.value("year");
    if (year.isValid() && !year.isNull() && year.toInt() > 0) {
        result.insert("year", year.toInt());
    }

    QVariant externalIds = item.value("externalIds");
    if (!externalIds.isValid() || externalIds.isNull()) {
        externalIds = item.value("external_ids");
    }
    if (externalIds.canConvert<QVariantMap>()) {
        result.insert("externalIds", QJsonObject::fromVariantMap(externalIds.toMap()));
    }

    return result;
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
    normalizedPref.insert(
        "movieSourceProviderId",
        pref.value(
            "moviesDefaultSourceProviderId",
            pref.value(
                "movies_default_source_provider_id",
                pref.value("movieSourceProviderId", pref.value("movie_source_provider_id")))));
    normalizedPref.insert(
        "seriesSourceProviderId",
        pref.value(
            "tvDefaultSourceProviderId",
            pref.value(
                "tv_default_source_provider_id",
                pref.value("seriesSourceProviderId", pref.value("series_source_provider_id")))));
    normalizedPref.insert(
        "animeSourceProviderId",
        pref.value(
            "animeDefaultSourceProviderId",
            pref.value(
                "anime_default_source_provider_id",
                pref.value("animeSourceProviderId", pref.value("anime_source_provider_id")))));
    normalizedPref.insert(
        "languagePreference",
        pref.value(
            "languagePreference",
            pref.value("language_preference", QVariantMap())));
    normalizedPref.insert(
        "streamHttpEgressPolicy",
        pref.value(
            "streamHttpEgressPolicy",
            pref.value("stream_http_egress_policy", QStringLiteral("auto_http_only"))));

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
    normalized.insert(
        "movieSourceProviders",
        payload.value(
            "moviesSourceCandidates",
            payload.value(
                "movies_source_candidates",
                payload.value("movieSourceProviders", payload.value("movie_source_providers")))));
    normalized.insert(
        "seriesSourceProviders",
        payload.value(
            "tvSourceCandidates",
            payload.value(
                "tv_source_candidates",
                payload.value("seriesSourceProviders", payload.value("series_source_providers")))));
    normalized.insert(
        "animeSourceProviders",
        payload.value(
            "animeSourceCandidates",
            payload.value(
                "anime_source_candidates",
                payload.value("animeSourceProviders", payload.value("anime_source_providers")))));
    normalized.insert(
        "sourceSuiteProviders",
        payload.value(
            "sourceSuiteProviders",
            payload.value("source_suite_providers")));
    return normalized;
}

QVariantMap normalizePlaybackInteractionPreferencesPayload(const QVariantMap &payload) {
    const QVariantMap preferences =
        payload.value("preferences", payload.value("playbackPreferences")).toMap();
    return preferences.isEmpty() ? payload : preferences;
}

void insertForwardedPort(QJsonObject &body, int port, const QString &protocol, const QString &source) {
    if (port <= 0 || port > 65535) {
        return;
    }
    const QString normalizedProtocol = protocol.trimmed().isEmpty()
        ? QStringLiteral("tcp")
        : protocol.trimmed().toLower();
    const QString normalizedSource = source.trimmed().isEmpty()
        ? QStringLiteral("profile_config")
        : source.trimmed().toLower();
    body.insert("forwardedPort", QJsonObject{
        {"port", port},
        {"protocol", normalizedProtocol},
        {"source", normalizedSource}
    });
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
    if (!m_baseUrl.isEmpty()) {
        cancelOutstandingRequests(QStringLiteral("Server changed."));
        clearAuthenticationState(true);
    }
    m_baseUrl = normalized;
    emit baseUrlChanged();
}

QString ApiClient::authToken() const {
    return m_authToken;
}

void ApiClient::setAuthToken(const QString &value) {
    const QString accepted = value.isEmpty() || isSafeToken(value) ? value : QString();
    if (m_authToken == accepted) {
        return;
    }
    m_authToken = accepted;
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

bool ApiClient::accessTokenNearExpiry(int skewSeconds) const {
    return accessTokenExpired(std::max(0, skewSeconds));
}

void ApiClient::expireAuth(const QString &message) {
    if (hasRefreshToken()) {
        refreshAuth();
        return;
    }
    const QString detail = message.trimmed().isEmpty()
        ? QStringLiteral("Session expired. Please sign in again.")
        : message.trimmed();
    clearAuthenticationState(true);
    emit authExpired(detail);
}

QString ApiClient::refreshToken() const {
    return m_refreshToken;
}

void ApiClient::setRefreshToken(const QString &value) {
    const QString accepted = value.isEmpty() || isSafeToken(value) ? value : QString();
    if (m_refreshToken == accepted) {
        return;
    }
    m_refreshToken = accepted;
    emit refreshTokenChanged();
}

bool ApiClient::hasRefreshToken() const {
    return !m_refreshToken.isEmpty();
}

bool ApiClient::refreshInFlight() const {
    return m_refreshInFlight;
}

QString ApiClient::sessionId() const {
    return m_sessionId;
}

QString ApiClient::homeId() const {
    return m_homeId;
}

QString ApiClient::activeProfileId() const {
    return m_activeProfileId;
}

QString ApiClient::activeProfileName() const {
    return m_activeProfileName;
}

QString ApiClient::activeProfileType() const {
    return m_activeProfileType;
}

QString ApiClient::homeRole() const {
    return m_homeRole;
}

QStringList ApiClient::capabilities() const {
    return m_capabilities;
}

qint64 ApiClient::capabilityRevision() const {
    return m_capabilityRevision;
}

QVariantMap ApiClient::sessionState() const {
    return {
        {"session_id", m_sessionId},
        {"home_id", m_homeId},
        {"active_profile_id", m_activeProfileId},
        {"active_profile_name", m_activeProfileName},
        {"active_profile_type", m_activeProfileType},
        {"role", m_homeRole},
        {"capabilities", m_capabilities},
        {"capability_revision", m_capabilityRevision},
    };
}

void ApiClient::setSessionState(const QVariantMap &state) {
    const QString sessionId = state.value("session_id").toString();
    const QString homeId = state.value("home_id").toString();
    const QString profileId = state.value("active_profile_id").toString();
    const QString profileName = state.value("active_profile_name").toString();
    const QString profileType = state.value("active_profile_type").toString();
    const QString role = state.value("role").toString();
    const QStringList capabilities = state.value("capabilities").toStringList();
    const qint64 revision = state.value("capability_revision").toLongLong();
    if (m_sessionId == sessionId
        && m_homeId == homeId
        && m_activeProfileId == profileId
        && m_activeProfileName == profileName
        && m_activeProfileType == profileType
        && m_homeRole == role
        && m_capabilities == capabilities
        && m_capabilityRevision == revision) {
        return;
    }
    m_sessionId = sessionId;
    m_homeId = homeId;
    m_activeProfileId = profileId;
    m_activeProfileName = profileName;
    m_activeProfileType = profileType;
    m_homeRole = role;
    m_capabilities = capabilities;
    m_capabilityRevision = revision;
    emit sessionStateChanged();
}

QVariantList ApiClient::profiles() const {
    return m_profiles;
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

QStringList ApiClient::extensionUninstallingIds() const {
    return m_extensionUninstallingIds;
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

QVariantMap ApiClient::extensionsRuntimeStatus() const {
    return m_extensionsRuntimeStatus;
}

QVariantMap ApiClient::extensionControlSurface() const {
    return m_extensionControlSurface;
}

bool ApiClient::extensionControlLoading() const {
    return m_extensionControlLoading;
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

QVariantMap ApiClient::networkProtectionStatus() const {
    return m_networkProtectionStatus;
}

QVariantMap ApiClient::networkProtectionWarpDisclosure() const {
    return m_networkProtectionWarpDisclosure;
}

QVariantMap ApiClient::networkProtectionWarpProfile() const {
    return m_networkProtectionWarpProfile;
}

QVariantMap ApiClient::networkProtectionWarpDiagnostics() const {
    return m_networkProtectionWarpDiagnostics;
}

QVariantMap ApiClient::networkProtectionProfiles() const {
    return m_networkProtectionProfiles;
}

QVariantMap ApiClient::networkProtectionImportResult() const {
    return m_networkProtectionImportResult;
}

QVariantMap ApiClient::networkProtectionSwitchResult() const {
    return m_networkProtectionSwitchResult;
}

QVariantMap ApiClient::networkProtectionProviderPresets() const {
    return m_networkProtectionProviderPresets;
}

QVariantMap ApiClient::networkProtectionListenPortSyncPlan() const {
    return m_networkProtectionListenPortSyncPlan;
}

QVariantMap ApiClient::downloadBrokerRoutes() const {
    return m_downloadBrokerRoutes;
}

bool ApiClient::networkProtectionLoading() const {
    return m_networkProtectionLoading;
}

QVariantMap ApiClient::liveEgressStatus() const {
    return m_liveEgressStatus;
}

bool ApiClient::liveEgressLoading() const {
    return m_liveEgressLoading;
}

QVariantMap ApiClient::playbackHardwareReadiness() const {
    return m_playbackHardwareReadiness;
}

QVariantList ApiClient::playbackHardwareWarnings() const {
    return m_playbackHardwareWarnings;
}

bool ApiClient::playbackHardwareLoading() const {
    return m_playbackHardwareLoading;
}

QVariantMap ApiClient::animeInferenceSettings() const {
    return m_animeInferenceSettings;
}

bool ApiClient::animeInferenceSettingsLoading() const {
    return m_animeInferenceSettingsLoading;
}

QVariantMap ApiClient::playbackAdminDiagnostics() const {
    return m_playbackAdminDiagnostics;
}

bool ApiClient::playbackAdminDiagnosticsLoading() const {
    return m_playbackAdminDiagnosticsLoading;
}

QVariantMap ApiClient::playbackInteractionPreferences() const {
    return m_playbackInteractionPreferences;
}

QVariantList ApiClient::mediaSegmentJobs() const {
    return m_mediaSegmentJobs;
}

bool ApiClient::mediaSegmentJobsLoading() const {
    return m_mediaSegmentJobsLoading;
}

bool ApiClient::mediaSegmentWorkerRunning() const {
    return m_mediaSegmentWorkerRunning;
}

QVariantList ApiClient::mediaSegmentCandidates() const {
    return m_mediaSegmentCandidates;
}

bool ApiClient::mediaSegmentCandidatesLoading() const {
    return m_mediaSegmentCandidatesLoading;
}

QVariantList ApiClient::mediaInteractionLibraries() const {
    return m_mediaInteractionLibraries;
}

bool ApiClient::mediaInteractionLibrariesLoading() const {
    return m_mediaInteractionLibrariesLoading;
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

QVariantMap ApiClient::mediaScopePreview() const {
    return m_mediaScopePreview;
}

bool ApiClient::mediaScopePreviewLoading() const {
    return m_mediaScopePreviewLoading;
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

QVariantList ApiClient::acquisitionReviewReleases() const {
    return m_acquisitionReviewReleases;
}

QVariantMap ApiClient::acquisitionReviewDetail() const {
    return m_acquisitionReviewDetail;
}

QVariantMap ApiClient::acquisitionSubscriptionCoverage() const {
    return m_acquisitionSubscriptionCoverage;
}

bool ApiClient::acquisitionReviewLoading() const {
    return m_acquisitionReviewLoading;
}

void ApiClient::login(const QString &email, const QString &password) {
    QJsonObject body{{"email", email.trimmed()}, {"password", password}};
    addClientSessionContext(body, true);
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
            QString error;
            if (!applyTokenResponse(obj, &error)) {
                clearAuthenticationState(true);
                emit loginFailed(error);
                return;
            }
            sendRequest(
                "GET",
                "/api/v1/auth/session",
                QJsonObject(),
                [this](const QJsonDocument &sessionDoc) {
                    QString sessionError;
                    if (!sessionDoc.isObject()
                        || !applySessionResponse(sessionDoc.object(), &sessionError)) {
                        clearAuthenticationState(true);
                        emit loginFailed(
                            sessionError.isEmpty()
                                ? QStringLiteral("Unexpected account-session response.")
                                : sessionError);
                        return;
                    }
                    emit loginSucceeded();
                },
                [this](const QString &sessionError) {
                    clearAuthenticationState(true);
                    emit loginFailed(sessionError);
                });
        },
        [this](const QString &error) { emit loginFailed(error); });
}

void ApiClient::signup(const QString &email, const QString &password) {
    QJsonObject body{{"email", email.trimmed()}, {"password", password}};
    addClientSessionContext(body, true);
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
            QString error;
            if (!applyTokenResponse(obj, &error)) {
                clearAuthenticationState(true);
                emit loginFailed(error);
                return;
            }
            sendRequest(
                "GET",
                "/api/v1/auth/session",
                QJsonObject(),
                [this](const QJsonDocument &sessionDoc) {
                    QString sessionError;
                    if (!sessionDoc.isObject()
                        || !applySessionResponse(sessionDoc.object(), &sessionError)) {
                        clearAuthenticationState(true);
                        emit loginFailed(
                            sessionError.isEmpty()
                                ? QStringLiteral("Unexpected account-session response.")
                                : sessionError);
                        return;
                    }
                    emit loginSucceeded();
                },
                [this](const QString &sessionError) {
                    clearAuthenticationState(true);
                    emit loginFailed(sessionError);
                });
        },
        [this](const QString &error) { emit loginFailed(error); });
}

void ApiClient::restoreSession() {
    if (!hasRefreshToken()) {
        emit sessionRestoreFailed(QStringLiteral("No remembered session is available."));
        return;
    }
    beginRefresh(true);
}

void ApiClient::refreshAuth() {
    if (!hasRefreshToken()) {
        clearAuthenticationState(true);
        emit authExpired(QStringLiteral("This device is no longer signed in."));
        return;
    }
    beginRefresh(false);
}

void ApiClient::logout() {
    cancelOutstandingRequests(QStringLiteral("Signed out."));
    if (m_authToken.isEmpty()) {
        clearAuthenticationState(true);
        emit logoutCompleted();
        return;
    }
    m_logoutInFlight = true;
    sendRequest(
        "POST",
        "/api/v1/auth/logout",
        QJsonObject(),
        [this](const QJsonDocument &) {
            m_logoutInFlight = false;
            clearAuthenticationState(true);
            emit logoutCompleted();
        },
        [this](const QString &) {
            m_logoutInFlight = false;
            clearAuthenticationState(true);
            emit logoutCompleted();
        },
        true);
}

void ApiClient::fetchProfiles() {
    sendRequest(
        "GET",
        "/api/v1/profiles",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject() || !doc.object().value("profiles").isArray()) {
                emit requestFailed("/api/v1/profiles", "Unexpected profiles response.");
                return;
            }
            m_profiles = doc.object().value("profiles").toArray().toVariantList();
            emit profilesChanged();
            emit profilesReceived(m_profiles);
        });
}

void ApiClient::selectProfile(const QString &profileId, const QString &pin) {
    const QString normalizedProfileId = profileId.trimmed();
    if (normalizedProfileId.isEmpty()) {
        emit requestFailed("/api/v1/profiles", "Profile id is required.");
        return;
    }
    cancelOutstandingRequests(QStringLiteral("Profile changed."));
    m_profileSwitchInFlight = true;
    QJsonObject body;
    if (!pin.isEmpty()) {
        body.insert("pin", pin);
    }
    const QString path = QStringLiteral("/api/v1/profiles/%1/select")
        .arg(QString::fromUtf8(QUrl::toPercentEncoding(normalizedProfileId)));
    sendRequest(
        "POST",
        path,
        body,
        [this, normalizedProfileId](const QJsonDocument &doc) {
            QString error;
            if (!doc.isObject()) {
                m_profileSwitchInFlight = false;
                emit requestFailed("/api/v1/profiles", "Unexpected profile-selection response.");
                return;
            }
            const QJsonObject response = doc.object();
            const bool applied = response.contains("access_token")
                ? applyTokenResponse(response, &error)
                : applySessionResponse(response, &error);
            if (!applied) {
                m_profileSwitchInFlight = false;
                emit requestFailed(
                    "/api/v1/profiles",
                    error.isEmpty() ? QStringLiteral("Invalid profile-selection response.") : error);
                return;
            }
            m_profileSwitchInFlight = false;
            emit profileSelected(normalizedProfileId);
        },
        [this](const QString &) {
            m_profileSwitchInFlight = false;
        });
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

void ApiClient::analyzeMediaSegments(
    const QString &mediaItemId,
    const QString &itemType,
    bool force) {
    const QString trimmedMediaItemId = mediaItemId.trimmed();
    QString normalizedItemType = itemType.trimmed().toLower();
    if (normalizedItemType == "tv" || normalizedItemType == "show") {
        normalizedItemType = QStringLiteral("series");
    }
    if (trimmedMediaItemId.isEmpty()) {
        emit requestFailed(
            "/api/v1/items/:item_type/:item_id/media-segment-jobs/analyze",
            "Media item id is required.");
        return;
    }
    if (normalizedItemType.isEmpty()) {
        emit requestFailed(
            "/api/v1/items/:item_type/:item_id/media-segment-jobs/analyze",
            "Media item type is required.");
        return;
    }

    QJsonObject body{{"force", force}};
    sendRequest(
        "POST",
        QString("/api/v1/items/%1/%2/media-segment-jobs/analyze")
            .arg(normalizedItemType, trimmedMediaItemId),
        body,
        [this, trimmedMediaItemId](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/items/:item_type/:item_id/media-segment-jobs/analyze",
                    "Media segment analysis response was not an object.");
                return;
            }
            const QVariantMap summary = doc.object().value("summary").toObject().toVariantMap();
            emit mediaSegmentAnalysisCompleted(trimmedMediaItemId, summary);
        });
}

void ApiClient::fetchItemMediaSegments(
    const QString &mediaItemId,
    const QString &itemType) {
    const QString trimmedMediaItemId = mediaItemId.trimmed();
    QString normalizedItemType = itemType.trimmed().toLower();
    if (normalizedItemType == "tv" || normalizedItemType == "show") {
        normalizedItemType = QStringLiteral("series");
    }

    if (trimmedMediaItemId.isEmpty()) {
        emit requestFailed(
            "/api/v1/items/:item_type/:item_id/segments",
            "Media item id is required.");
        return;
    }
    if (normalizedItemType.isEmpty()) {
        emit requestFailed(
            "/api/v1/items/:item_type/:item_id/segments",
            "Media item type is required.");
        return;
    }

    const QString encodedItemType = QString::fromUtf8(QUrl::toPercentEncoding(normalizedItemType));
    const QString encodedMediaItemId =
        QString::fromUtf8(QUrl::toPercentEncoding(trimmedMediaItemId));
    const QString path =
        QString("/api/v1/items/%1/%2/segments").arg(encodedItemType, encodedMediaItemId);
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this, trimmedMediaItemId, normalizedItemType, path](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(path, "Media segments response was not an object.");
                return;
            }
            emit itemMediaSegmentsReceived(
                trimmedMediaItemId,
                normalizedItemType,
                doc.object().toVariantMap());
        });
}

void ApiClient::disableMediaSegment(
    const QString &segmentId,
    const QString &reason) {
    const QString trimmedSegmentId = segmentId.trimmed();
    if (trimmedSegmentId.isEmpty()) {
        emit requestFailed("/api/v1/media-segments/:id/disable", "Media segment id is required.");
        return;
    }

    QJsonObject body;
    const QString trimmedReason = reason.trimmed();
    if (!trimmedReason.isEmpty()) {
        body.insert("reason", trimmedReason);
    }

    const QString encodedSegmentId = QString::fromUtf8(QUrl::toPercentEncoding(trimmedSegmentId));
    const QString path = QString("/api/v1/media-segments/%1/disable").arg(encodedSegmentId);
    sendRequest(
        "POST",
        path,
        body,
        [this, trimmedSegmentId, path](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(path, "Media segment disable response was not an object.");
                return;
            }
            emit mediaSegmentDisabled(trimmedSegmentId, doc.object().toVariantMap());
        });
}

void ApiClient::deleteLibraryItem(const QString &mediaItemId, bool stopTracking) {
    deleteLibraryItemWithAction(
        mediaItemId,
        stopTracking ? QStringLiteral("delete_and_release_owner")
                     : QStringLiteral("delete_local_only"),
        false);
}

void ApiClient::deleteLibraryItemWithAction(const QString &mediaItemId,
                                            const QString &ownerReleaseAction,
                                            bool bestEffort) {
    const QString trimmed = mediaItemId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/library/items/:id", "Media item id is required.");
        return;
    }
    const QString action = ownerReleaseAction.trimmed().isEmpty()
                               ? QStringLiteral("delete_local_only")
                               : ownerReleaseAction.trimmed();
    QJsonObject body{
        {"ownerReleaseAction", action},
        {"ownerReleaseBestEffort", bestEffort}
    };
    sendRequest(
        "DELETE",
        QString("/api/v1/library/items/%1").arg(trimmed),
        body,
        [this, trimmed](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/library/items/:id", "Delete response was not an object.");
                return;
            }
            const QVariantMap result = doc.object().toVariantMap();
            emit mediaItemDeleted(trimmed, result);
            fetchLibrary();
        });
}

void ApiClient::deleteEpisode(const QString &episodeId, bool blockInElixir) {
    const QString trimmed = episodeId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/library/episodes/:id", "Episode id is required.");
        return;
    }
    QJsonObject body{{"blockInElixir", blockInElixir}};
    sendRequest(
        "DELETE",
        QString("/api/v1/library/episodes/%1").arg(trimmed),
        body,
        [this, trimmed](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/library/episodes/:id", "Delete response was not an object.");
                return;
            }
            const QVariantMap result = doc.object().toVariantMap();
            emit episodeDeleted(trimmed, result);
        });
}

void ApiClient::restoreEpisode(const QString &episodeId) {
    const QString trimmed = episodeId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/library/episodes/:id/restore", "Episode id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/library/episodes/%1/restore").arg(trimmed),
        QJsonObject(),
        [this, trimmed](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/library/episodes/:id/restore", "Restore response was not an object.");
                return;
            }
            const QVariantMap result = doc.object().toVariantMap();
            emit episodeRestored(trimmed, result);
        });
}

void ApiClient::restoreBlockedEpisodes(const QString &mediaItemId) {
    const QString trimmed = mediaItemId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/library/items/:id/restore-blocked-episodes", "Media item id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/library/items/%1/restore-blocked-episodes").arg(trimmed),
        QJsonObject(),
        [this, trimmed](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/library/items/:id/restore-blocked-episodes", "Restore response was not an object.");
                return;
            }
            const QVariantMap result = doc.object().toVariantMap();
            emit blockedEpisodesRestored(trimmed, result);
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
    applyCurrentPlaybackContext(body);
    m_lastPlaybackBody = body;
    sendPlaybackRequest(body);
}

void ApiClient::startEpisodePlayback(const QString &mediaItemId, const QString &episodeId) {
    QJsonObject body{{"media_item_id", mediaItemId}};
    if (!episodeId.trimmed().isEmpty()) {
        body.insert("preferred_episode_id", episodeId);
    } else {
        body.insert("preferred_episode_id", QJsonValue::Null);
    }
    applyCurrentPlaybackContext(body);
    m_lastPlaybackBody = body;
    sendPlaybackRequest(body);
}

void ApiClient::retryLastPlayback() {
    if (m_lastPlaybackBody.isEmpty()) {
        QVariantMap error;
        error.insert("endpoint", "/api/v1/play");
        error.insert("message", "No playback request is available to retry.");
        emit playbackFailed(error);
        emit requestFailed("/api/v1/play", error.value("message").toString());
        emit requestFailedDetailed("/api/v1/play", error);
        return;
    }
    QJsonObject body = m_lastPlaybackBody;
    applyCurrentPlaybackContext(body);
    m_lastPlaybackBody = body;
    sendPlaybackRequest(body);
}

void ApiClient::retryLastPlaybackFrom(double seconds) {
    if (m_lastPlaybackBody.isEmpty()) {
        retryLastPlayback();
        return;
    }
    QJsonObject body = m_lastPlaybackBody;
    if (std::isfinite(seconds) && seconds > 0.0) {
        body.insert("start_position_seconds", seconds);
    }
    applyCurrentPlaybackContext(body);
    m_lastPlaybackBody = body;
    sendPlaybackRequest(body);
}

void ApiClient::retryLastPlaybackWithLowerQuality(double seconds, int maxBitrateBps) {
    if (m_lastPlaybackBody.isEmpty()) {
        retryLastPlayback();
        return;
    }
    QJsonObject body = m_lastPlaybackBody;
    if (std::isfinite(seconds) && seconds > 0.0) {
        body.insert("start_position_seconds", seconds);
    }
    applyCurrentPlaybackContext(body);
    QJsonObject caps = body.value("client_capabilities").toObject();
    if (maxBitrateBps > 0) {
        caps.insert("max_bitrate_bps", maxBitrateBps);
    }
    caps.insert("quality_mode", "fixed");
    body.insert("client_capabilities", caps);
    if (caps.contains("profile_version")) {
        body.insert("profile_version", caps.value("profile_version"));
    }
    if (caps.contains("app_version")) {
        body.insert("app_version", caps.value("app_version"));
    }
    if (!m_networkType.isEmpty() && m_networkType != "auto") {
        body.insert("network_type", m_networkType);
    }
    m_lastPlaybackBody = body;
    sendPlaybackRequest(body);
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

void ApiClient::heartbeatSession(const QString &sessionId) {
    if (sessionId.trimmed().isEmpty()) {
        return;
    }
    sendRequest("POST", QString("/api/v1/sessions/%1/heartbeat").arg(sessionId), QJsonObject(),
                [](const QJsonDocument &) {},
                ErrorHandler(),
                true);
}

void ApiClient::reportPlaybackProgress(
    const QString &sessionId,
    double positionSeconds,
    double durationSeconds,
    bool paused,
    const QString &eventType,
    const QVariantMap &progressMetadata) {
    if (sessionId.trimmed().isEmpty() || !std::isfinite(positionSeconds) || positionSeconds < 0.0) {
        return;
    }
    QJsonObject body{{"positionSeconds", positionSeconds}, {"paused", paused}};
    if (std::isfinite(durationSeconds) && durationSeconds > 0.0) {
        body.insert("durationSeconds", durationSeconds);
    }
    const QString trimmedEventType = eventType.trimmed();
    if (!trimmedEventType.isEmpty()) {
        body.insert("eventType", trimmedEventType);
    }
    for (auto it = progressMetadata.cbegin(); it != progressMetadata.cend(); ++it) {
        if (!it.key().trimmed().isEmpty() && it.value().isValid() && !it.value().isNull()) {
            body.insert(it.key(), QJsonValue::fromVariant(it.value()));
        }
    }
    body.insert("clientReportedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));

    sendRequest("POST", QString("/api/v1/sessions/%1/progress").arg(sessionId), body,
                [](const QJsonDocument &) {},
                ErrorHandler(),
                true);
}

void ApiClient::endSession(
    const QString &sessionId,
    double positionSeconds,
    double durationSeconds,
    const QString &eventType) {
    if (sessionId.trimmed().isEmpty()) {
        return;
    }
    QJsonObject body;
    if (std::isfinite(positionSeconds) && positionSeconds >= 0.0) {
        body.insert("positionSeconds", positionSeconds);
    }
    if (std::isfinite(durationSeconds) && durationSeconds > 0.0) {
        body.insert("durationSeconds", durationSeconds);
    }
    const QString trimmedEventType = eventType.trimmed();
    if (!trimmedEventType.isEmpty()) {
        body.insert("eventType", trimmedEventType);
    }
    if (!body.isEmpty()) {
        body.insert("clientReportedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    }

    sendRequest("POST", QString("/api/v1/sessions/%1/end").arg(sessionId), body,
                [](const QJsonDocument &) {},
                ErrorHandler(),
                true);
}

void ApiClient::applyCurrentPlaybackContext(QJsonObject &body) const {
    if (!m_networkType.isEmpty() && m_networkType != "auto") {
        body.insert("network_type", m_networkType);
    }
    if (!m_clientCapabilities.isEmpty()) {
        const QJsonObject caps = QJsonObject::fromVariantMap(m_clientCapabilities);
        body.insert("client_capabilities", caps);
        if (caps.contains("profile_version")) {
            body.insert("profile_version", caps.value("profile_version"));
        }
        if (caps.contains("app_version")) {
            body.insert("app_version", caps.value("app_version"));
        }
    }
}

void ApiClient::sendPlaybackRequest(const QJsonObject &body) {
    sendRequest("POST", "/api/v1/play", body,
                [this](const QJsonDocument &doc) {
                    if (!doc.isObject()) {
                        QVariantMap error;
                        error.insert("endpoint", "/api/v1/play");
                        error.insert("message", "Playback response was not an object.");
                        emit playbackFailed(error);
                        emit requestFailed("/api/v1/play", error.value("message").toString());
                        emit requestFailedDetailed("/api/v1/play", error);
                        return;
                    }
                    emit playbackStarted(doc.object().toVariantMap());
                });
}

bool ApiClient::endSessionBlocking(const QString &sessionId, int timeoutMs) {
    if (sessionId.trimmed().isEmpty() || m_baseUrl.trimmed().isEmpty()) {
        return false;
    }

    const QString path = QString("/api/v1/sessions/%1/end").arg(sessionId);
    QNetworkRequest request(makeUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    const QString locale = QLocale::system().name().replace('_', '-');
    if (!locale.trimmed().isEmpty()) {
        request.setRawHeader("Accept-Language", locale.toUtf8());
    }
    if (!m_authToken.isEmpty()) {
        request.setRawHeader("Authorization", QByteArray("Bearer ") + m_authToken.toUtf8());
    }

    QNetworkReply *reply = m_manager.post(request, QJsonDocument(QJsonObject()).toJson());
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    QObject::connect(&timer, &QTimer::timeout, reply, &QNetworkReply::abort);
    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
    timer.start(std::max(1, timeoutMs));
    loop.exec();

    const bool timedOut = !timer.isActive();
    if (!timedOut) {
        timer.stop();
    }
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const bool ok = !timedOut
        && reply->error() == QNetworkReply::NoError
        && status >= 200
        && status < 300;
    if (!ok) {
        qWarning() << "Blocking session end failed" << sessionId
                   << "status" << status
                   << "error" << reply->errorString();
    }
    reply->deleteLater();
    return ok;
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
    const quint64 requestId = ++m_extensionsCatalogRequestId;
    sendRequest(
        "GET",
        "/api/v1/extensions/catalog",
        QJsonObject(),
        [this, requestId](const QJsonDocument &doc) {
            if (requestId != m_extensionsCatalogRequestId) {
                return;
            }
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/catalog", "Extensions catalog response was not an object.");
                return;
            }
            updateExtensionsCatalog(doc.object());
        });
}

void ApiClient::refreshExtensionsCatalog() {
    const quint64 requestId = ++m_extensionsCatalogRequestId;
    sendRequest(
        "POST",
        "/api/v1/extensions/registries/refresh",
        QJsonObject(),
        [this, requestId](const QJsonDocument &doc) {
            if (requestId != m_extensionsCatalogRequestId) {
                return;
            }
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/registries/refresh", "Extensions refresh response was not an object.");
                return;
            }
            updateExtensionsCatalog(doc.object());
        });
}

void ApiClient::installExtension(const QString &downloadUrl) {
    installExtensionSource(downloadUrl, QString());
}

void ApiClient::installExtensionSource(const QString &downloadUrl, const QString &packagePath) {
    const QString trimmedUrl = downloadUrl.trimmed();
    const QString trimmedPath = packagePath.trimmed();
    if (trimmedUrl.isEmpty() && trimmedPath.isEmpty()) {
        emit requestFailed("/api/v1/extensions/install", "Download URL or package path is required.");
        return;
    }
    QJsonObject body;
    if (!trimmedUrl.isEmpty()) {
        body.insert("downloadUrl", trimmedUrl);
    }
    if (!trimmedPath.isEmpty()) {
        body.insert("packagePath", trimmedPath);
    }
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
            fetchExtensionStatusSummary();
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
            fetchExtensionStatusSummary();
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
            fetchExtensionStatusSummary();
        });
}

void ApiClient::uninstallExtension(const QString &extensionId) {
    const QString trimmed = extensionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/uninstall", "Extension id is required.");
        return;
    }
    if (m_extensionUninstallingIds.contains(trimmed)) {
        return;
    }

    QString displayName = trimmed;
    for (const QVariant &value : m_extensionsInstalled) {
        const QVariantMap extension = value.toMap();
        if (extension.value("extension_id").toString() != trimmed) {
            continue;
        }
        const QString candidate = extension.value("name").toString().trimmed();
        if (!candidate.isEmpty()) {
            displayName = candidate;
        }
        break;
    }

    setExtensionUninstalling(trimmed, true);
    sendRequest(
        "POST",
        QString("/api/v1/extensions/%1/uninstall").arg(trimmed),
        QJsonObject(),
        [this, trimmed, displayName](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                setExtensionUninstalling(trimmed, false);
                emit requestFailed("/api/v1/extensions/:id/uninstall", "Uninstall response was not an object.");
                return;
            }
            removeInstalledExtension(trimmed);
            setExtensionUninstalling(trimmed, false);
            emit extensionUninstalled(trimmed, displayName);
            fetchExtensionsCatalog();
            fetchExtensionInstances();
            fetchExtensionStatusSummary();
        },
        [this, trimmed](const QString &) {
            setExtensionUninstalling(trimmed, false);
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
        [this, trimmed](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/:id/instances", "Create instance response was not an object.");
                return;
            }
            fetchExtensionInstances();
            fetchExtensionStatusSummary();
            fetchExtensionControlSurface(trimmed);
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
            fetchManagerPreferences();
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
            confirmExtensionsPlan(planId);
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

void ApiClient::confirmExtensionsPlan(const QString &planId) {
    const QString trimmed = planId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/plan/:id/confirm", "Plan id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/extensions/plan/%1/confirm").arg(trimmed),
        QJsonObject(),
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
        });
}

void ApiClient::resetExtensionsRuntime() {
    sendRequest(
        "POST",
        "/api/v1/extensions/runtime/reset",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/extensions/runtime/reset", "Runtime reset response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const QJsonObject runObj = obj.value("run").toObject();
            const QVariantMap run = runObj.toVariantMap();
            if (!run.isEmpty() && m_extensionsReconcileRun != run) {
                m_extensionsReconcileRun = run;
                emit extensionsReconcileRunChanged();
            }

            emit extensionsRuntimeResetCompleted(
                obj.value("status").toString(),
                obj.value("message").toString());

            fetchExtensionRuns();
            fetchExtensionInstances();
            fetchDesiredBlueprints();
            fetchExtensionStatusSummary();
            fetchLatestReconcileRun();
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
    fetchExtensionControlSurfaceForInstance(extensionId, QString());
}

void ApiClient::fetchExtensionControlSurfaceForInstance(
    const QString &extensionId,
    const QString &instanceId) {
    const QString trimmed = extensionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/control-surface", "Extension id is required.");
        return;
    }
    const quint64 requestId = ++m_extensionControlRequestId;
    if (!m_extensionControlLoading) {
        m_extensionControlLoading = true;
        emit extensionControlLoadingChanged();
    }
    sendRequest(
        "GET",
        extensionControlPath(trimmed, instanceId),
        QJsonObject(),
        [this, requestId](const QJsonDocument &doc) {
            if (requestId != m_extensionControlRequestId) {
                return;
            }
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
        [this, requestId](const QString &) {
            if (requestId != m_extensionControlRequestId) {
                return;
            }
            if (m_extensionControlLoading) {
                m_extensionControlLoading = false;
                emit extensionControlLoadingChanged();
            }
        });
}

void ApiClient::updateExtensionControlSurfaceSettings(
    const QString &extensionId,
    const QVariantMap &values) {
    updateExtensionControlSurfaceSettingsForInstance(
        extensionId, QString(), values);
}

void ApiClient::updateExtensionControlSurfaceSettingsForInstance(
    const QString &extensionId,
    const QString &instanceId,
    const QVariantMap &values) {
    const QString trimmed = extensionId.trimmed();
    const QString trimmedInstanceId = instanceId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/extensions/:id/control-surface", "Extension id is required.");
        return;
    }
    const quint64 requestId = ++m_extensionControlRequestId;
    if (!m_extensionControlLoading) {
        m_extensionControlLoading = true;
        emit extensionControlLoadingChanged();
    }
    QJsonObject body;
    body.insert("values", QJsonObject::fromVariantMap(values));
    QStringList fieldIds = values.keys();
    fieldIds.sort(Qt::CaseSensitive);
    sendRequest(
        "PUT",
        extensionControlPath(trimmed, trimmedInstanceId),
        body,
        [this, trimmed, trimmedInstanceId, fieldIds, requestId](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                if (requestId == m_extensionControlRequestId
                    && m_extensionControlLoading) {
                    m_extensionControlLoading = false;
                    emit extensionControlLoadingChanged();
                }
                if (requestId == m_extensionControlRequestId) {
                    emit requestFailed(
                        "/api/v1/extensions/:id/control-surface",
                        "Control surface update response was not an object.");
                }
                return;
            }
            if (requestId == m_extensionControlRequestId) {
                updateExtensionControlSurfaceState(doc.object());
                if (m_extensionControlLoading) {
                    m_extensionControlLoading = false;
                    emit extensionControlLoadingChanged();
                }
            }
            emit extensionControlSettingsUpdated(
                trimmed, trimmedInstanceId, fieldIds);
        },
        [this, requestId](const QString &) {
            if (requestId != m_extensionControlRequestId) {
                return;
            }
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
    invokeExtensionControlActionForInstance(
        extensionId, QString(), actionId, params);
}

void ApiClient::invokeExtensionControlActionForInstance(
    const QString &extensionId,
    const QString &instanceId,
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
    const quint64 requestId = ++m_extensionControlRequestId;
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
        extensionControlPath(
            trimmedExtensionId, instanceId, trimmedActionId),
        body,
        [this, trimmedExtensionId, trimmedActionId, requestId](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                if (requestId == m_extensionControlRequestId
                    && m_extensionControlLoading) {
                    m_extensionControlLoading = false;
                    emit extensionControlLoadingChanged();
                }
                if (requestId == m_extensionControlRequestId) {
                    emit requestFailed(
                        "/api/v1/extensions/:id/control-surface/actions/:action_id",
                        "Control action response was not an object.");
                }
                return;
            }
            const QJsonObject obj = doc.object();
            if (requestId == m_extensionControlRequestId) {
                updateExtensionControlSurfaceState(obj.value("controlSurface").toObject());
                if (m_extensionControlLoading) {
                    m_extensionControlLoading = false;
                    emit extensionControlLoadingChanged();
                }
            }
            emit extensionControlActionCompleted(
                trimmedExtensionId,
                trimmedActionId,
                obj.value("message").toString());
        },
        [this, requestId](const QString &) {
            if (requestId != m_extensionControlRequestId) {
                return;
            }
            if (m_extensionControlLoading) {
                m_extensionControlLoading = false;
                emit extensionControlLoadingChanged();
            }
        });
}

void ApiClient::startExtensionAccountSetup(
    const QString &extensionId,
    const QString &instanceId) {
    const QString trimmedExtensionId = extensionId.trimmed();
    const QString trimmedInstanceId = instanceId.trimmed();
    const QString endpoint = extensionAccountSetupPath(
        trimmedExtensionId, trimmedInstanceId);
    if (trimmedExtensionId.isEmpty() || trimmedInstanceId.isEmpty()) {
        emit requestFailed(endpoint, "Extension and instance ids are required.");
        return;
    }
    sendRequest(
        "POST",
        endpoint,
        QJsonObject(),
        [this, trimmedExtensionId, trimmedInstanceId, endpoint](
            const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(endpoint, "Account setup response was not an object.");
                return;
            }
            const QJsonObject object = doc.object();
            const QString setupId = object.value("setupId").toString().trimmed();
            const QString configureUrl =
                object.value("configureUrl").toString().trimmed();
            if (setupId.isEmpty() || configureUrl.isEmpty()) {
                emit requestFailed(endpoint, "Account setup response was incomplete.");
                return;
            }
            emit extensionAccountSetupStarted(
                trimmedExtensionId,
                trimmedInstanceId,
                setupId,
                configureUrl);
        });
}

void ApiClient::checkExtensionAccountSetup(
    const QString &extensionId,
    const QString &instanceId,
    const QString &setupId) {
    const QString trimmedExtensionId = extensionId.trimmed();
    const QString trimmedInstanceId = instanceId.trimmed();
    const QString trimmedSetupId = setupId.trimmed();
    const QString endpoint = extensionAccountSetupPath(
        trimmedExtensionId, trimmedInstanceId, trimmedSetupId);
    if (trimmedExtensionId.isEmpty() || trimmedInstanceId.isEmpty()
        || trimmedSetupId.isEmpty()) {
        emit requestFailed(endpoint, "Extension, instance, and setup ids are required.");
        return;
    }
    sendRequest(
        "GET",
        endpoint,
        QJsonObject(),
        [this, trimmedExtensionId, trimmedInstanceId, trimmedSetupId, endpoint](
            const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(endpoint, "Account setup status was not an object.");
                return;
            }
            const QJsonObject object = doc.object();
            const bool completed = object.value("completed").toBool(false);
            emit extensionAccountSetupStatusReceived(
                trimmedExtensionId,
                trimmedInstanceId,
                trimmedSetupId,
                completed);
            if (completed) {
                emit extensionAccountSetupCompleted(
                    trimmedExtensionId,
                    trimmedInstanceId,
                    trimmedSetupId);
            }
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

void ApiClient::fetchNetworkProtectionStatus() {
    setNetworkProtectionLoading(true);
    sendRequest(
        "GET",
        "/api/v1/network/protection/status",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setNetworkProtectionLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/status", "Network protection status response was not an object.");
                return;
            }
            updateNetworkProtectionStatus(doc.object());
        },
        [this](const QString &) {
            setNetworkProtectionLoading(false);
        });
}

void ApiClient::fetchNetworkProtectionProfiles() {
    sendRequest(
        "GET",
        "/api/v1/network/protection/profiles",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/profiles", "Network protection profiles response was not an object.");
                return;
            }
            updateNetworkProtectionProfiles(doc.object());
        });
}

void ApiClient::fetchNetworkProtectionWarpDisclosure() {
    sendRequest(
        "GET",
        "/api/v1/network/protection/warp/disclosure",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/warp/disclosure", "WARP disclosure response was not an object.");
                return;
            }
            updateNetworkProtectionWarpDisclosure(doc.object());
        });
}

void ApiClient::fetchNetworkProtectionWarpDiagnostics() {
    sendRequest(
        "GET",
        "/api/v1/network/protection/warp/diagnostics",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/warp/diagnostics", "WARP diagnostics response was not an object.");
                return;
            }
            updateNetworkProtectionWarpDiagnostics(doc.object());
        });
}

void ApiClient::fetchNetworkProtectionProviderPresets() {
    sendRequest(
        "GET",
        "/api/v1/network/protection/provider-presets",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/provider-presets", "Provider presets response was not an object.");
                return;
            }
            updateNetworkProtectionProviderPresets(doc.object());
        });
}

void ApiClient::fetchNetworkProtectionListenPortSyncPlan() {
    sendRequest(
        "GET",
        "/api/v1/network/protection/qbittorrent/listen-port-sync",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/qbittorrent/listen-port-sync", "qBittorrent listen-port sync response was not an object.");
                return;
            }
            updateNetworkProtectionListenPortSyncPlan(doc.object());
        });
}

void ApiClient::fetchLiveEgressStatus() {
    static const QString endpoint = QStringLiteral("/api/v1/live/admin/egress");
    setLiveEgressLoading(true);
    sendRequest(
        "GET",
        endpoint,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setLiveEgressLoading(false);
            const QJsonObject envelope = doc.isObject() ? doc.object() : QJsonObject();
            const QJsonValue data = envelope.value(QStringLiteral("data"));
            if (!data.isObject()) {
                emit requestFailed(
                    QStringLiteral("/api/v1/live/admin/egress"),
                    QStringLiteral("Live egress status response was invalid."));
                return;
            }
            const QJsonObject status = data.toObject();
            const QSet<QString> expected{
                QStringLiteral("enabled"),
                QStringLiteral("ready"),
                QStringLiteral("activeBindings"),
                QStringLiteral("availableCapacity"),
                QStringLiteral("defaultPolicy"),
                QStringLiteral("profiles"),
                QStringLiteral("assignments")
            };
            const QStringList keys = status.keys();
            const QSet<QString> actual(keys.cbegin(), keys.cend());
            if (actual != expected
                || !status.value(QStringLiteral("enabled")).isBool()
                || !status.value(QStringLiteral("ready")).isBool()
                || !status.value(QStringLiteral("activeBindings")).isDouble()
                || !status.value(QStringLiteral("availableCapacity")).isDouble()
                || !status.value(QStringLiteral("defaultPolicy")).isObject()
                || !status.value(QStringLiteral("profiles")).isArray()
                || !status.value(QStringLiteral("assignments")).isArray()) {
                emit requestFailed(
                    QStringLiteral("/api/v1/live/admin/egress"),
                    QStringLiteral("Live egress status response was invalid."));
                return;
            }
            updateLiveEgressStatus(status);
        },
        [this](const QString &) {
            setLiveEgressLoading(false);
        });
}

void ApiClient::updateLiveEgressPolicy(
    const QString &scopeType,
    const QString &scopeId,
    const QString &mode,
    const QString &policyId,
    bool allowFallback,
    qint64 expectedRevision) {
    static const QString endpoint = QStringLiteral("/api/v1/live/admin/egress");
    const QString normalizedScope = scopeType.trimmed();
    const QString normalizedScopeId = scopeId.trimmed();
    const QString normalizedMode = mode.trimmed();
    const QString normalizedPolicyId = policyId.trimmed();
    const bool scopeValid = normalizedScope == QStringLiteral("server_default")
        ? normalizedScopeId.isEmpty()
        : (normalizedScope == QStringLiteral("profile")
           || normalizedScope == QStringLiteral("provider"))
              && !normalizedScopeId.isEmpty();
    const bool modeValid = normalizedMode == QStringLiteral("off")
        || normalizedMode == QStringLiteral("prefer_protected")
        || normalizedMode == QStringLiteral("require_protected");
    const bool policyShapeValid = normalizedMode == QStringLiteral("off")
        ? normalizedPolicyId.isEmpty() && !allowFallback
        : !normalizedPolicyId.isEmpty()
              && (normalizedMode == QStringLiteral("prefer_protected") || !allowFallback);
    if (!scopeValid || !modeValid || !policyShapeValid || expectedRevision < 0) {
        emit requestFailed(endpoint, QStringLiteral("Live egress policy selection is invalid."));
        return;
    }
    QJsonObject body{
        {QStringLiteral("scopeType"), normalizedScope},
        {QStringLiteral("mode"), normalizedMode},
        {QStringLiteral("allowFallback"), allowFallback},
        {QStringLiteral("expectedRevision"), expectedRevision}
    };
    if (!normalizedScopeId.isEmpty()) {
        body.insert(QStringLiteral("scopeId"), normalizedScopeId);
    }
    if (!normalizedPolicyId.isEmpty()) {
        body.insert(QStringLiteral("policyId"), normalizedPolicyId);
    }
    setLiveEgressLoading(true);
    sendRequest(
        "PUT",
        endpoint,
        body,
        [this](const QJsonDocument &doc) {
            setLiveEgressLoading(false);
            if (!doc.isObject() || !doc.object().value(QStringLiteral("data")).isObject()) {
                emit requestFailed(
                    QStringLiteral("/api/v1/live/admin/egress"),
                    QStringLiteral("Live egress policy response was invalid."));
                return;
            }
            fetchLiveEgressStatus();
        },
        [this](const QString &) {
            setLiveEgressLoading(false);
        });
}

void ApiClient::applyNetworkProtectionListenPortSync() {
    setNetworkProtectionLoading(true);
    sendRequest(
        "POST",
        "/api/v1/network/protection/qbittorrent/listen-port-sync/apply",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setNetworkProtectionLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/qbittorrent/listen-port-sync/apply", "qBittorrent listen-port sync response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const QJsonObject plan = obj.value("plan").toObject();
            updateNetworkProtectionListenPortSyncPlan(plan.isEmpty() ? obj : plan);
            fetchNetworkProtectionStatus();
            fetchNetworkProtectionListenPortSyncPlan();
        },
        [this](const QString &) {
            setNetworkProtectionLoading(false);
        });
}

void ApiClient::fetchPlaybackHardwareReadiness(bool diagnostics) {
    setPlaybackHardwareLoading(true);
    const QString path = diagnostics
        ? QStringLiteral("/api/v1/playback/hardware/readiness?diagnostics=true")
        : QStringLiteral("/api/v1/playback/hardware/readiness");
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setPlaybackHardwareLoading(false);
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/playback/hardware/readiness",
                    "Playback hardware readiness response was not an object.");
                return;
            }
            updatePlaybackHardwareReadiness(doc.object());
        },
        [this](const QString &) {
            setPlaybackHardwareLoading(false);
        });
}

void ApiClient::fetchPlaybackHardwareWarnings() {
    sendRequest(
        "GET",
        "/api/v1/playback/hardware/warnings",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isArray()) {
                emit requestFailed(
                    "/api/v1/playback/hardware/warnings",
                    "Playback hardware warning response was not a list.");
                return;
            }
            updatePlaybackHardwareWarnings(doc.array());
        });
}

void ApiClient::refreshPlaybackHardwareStatus(bool diagnostics) {
    fetchPlaybackHardwareReadiness(diagnostics);
    fetchPlaybackHardwareWarnings();
}

void ApiClient::fetchAnimeInferenceSettings() {
    setAnimeInferenceSettingsLoading(true);
    sendRequest(
        "GET",
        "/api/v1/settings/anime-inference",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setAnimeInferenceSettingsLoading(false);
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/settings/anime-inference",
                    "Anime inference settings response was not an object.");
                return;
            }
            updateAnimeInferenceSettings(doc.object());
        },
        [this](const QString &) {
            setAnimeInferenceSettingsLoading(false);
        });
}

void ApiClient::setAnimeInferenceSlowHardwareEnabled(bool enabled) {
    setAnimeInferenceSettingsLoading(true);
    QJsonObject body;
    body.insert("slowHardwareEnabled", enabled);
    sendRequest(
        "PATCH",
        "/api/v1/settings/anime-inference",
        body,
        [this](const QJsonDocument &doc) {
            setAnimeInferenceSettingsLoading(false);
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/settings/anime-inference",
                    "Anime inference settings response was not an object.");
                return;
            }
            updateAnimeInferenceSettings(doc.object());
        },
        [this](const QString &) {
            setAnimeInferenceSettingsLoading(false);
        });
}

void ApiClient::fetchPlaybackAdminDiagnostics() {
    setPlaybackAdminDiagnosticsLoading(true);
    sendRequest(
        "GET",
        "/api/v1/playback/admin/sessions",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setPlaybackAdminDiagnosticsLoading(false);
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/playback/admin/sessions",
                    "Playback diagnostics response was not an object.");
                return;
            }
            updatePlaybackAdminDiagnostics(doc.object());
        },
        [this](const QString &) {
            setPlaybackAdminDiagnosticsLoading(false);
        });
}

void ApiClient::stopPlaybackAdminSession(const QString &sessionId) {
    const QString trimmed = sessionId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/playback/admin/sessions", "Playback session id is required.");
        return;
    }
    sendRequest(
        "POST",
        QString("/api/v1/sessions/%1/end").arg(trimmed),
        QJsonObject(),
        [this](const QJsonDocument &) {
            fetchPlaybackAdminDiagnostics();
        },
        ErrorHandler(),
        true);
}

void ApiClient::applyFirstRunDownloadSetup(const QString &choice, bool acceptedWarpDisclosure) {
    const QString trimmedChoice = choice.trimmed();
    if (trimmedChoice.isEmpty()) {
        emit requestFailed("/api/v1/network/protection/first-run", "First-run download setup choice is required.");
        return;
    }

    setNetworkProtectionLoading(true);
    QJsonObject body{
        {"choice", trimmedChoice},
        {"acceptedWarpDisclosure", acceptedWarpDisclosure},
        {"apply", true}
    };
    sendRequest(
        "POST",
        "/api/v1/network/protection/first-run",
        body,
        [this](const QJsonDocument &doc) {
            setNetworkProtectionLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/first-run", "First-run download setup response was not an object.");
                return;
            }
            const QJsonObject obj = doc.object();
            const QJsonObject switchResult = obj.value("switchResult").toObject();
            if (!switchResult.isEmpty()) {
                updateNetworkProtectionSwitchResult(switchResult);
            }
            const QJsonObject routes = obj.value("routes").toObject();
            if (!routes.isEmpty()) {
                updateDownloadBrokerRoutes(routes);
            }
            fetchNetworkProtectionProfiles();
            fetchNetworkProtectionWarpDiagnostics();
            fetchNetworkProtectionStatus();
            fetchNetworkProtectionListenPortSyncPlan();
            fetchDownloadBrokerRoutes();
        },
        [this](const QString &) {
            setNetworkProtectionLoading(false);
        });
}

void ApiClient::createCloudflareWarpProfile(bool acceptedDisclosure) {
    setNetworkProtectionLoading(true);
    QJsonObject body{{"acceptedDisclosure", acceptedDisclosure}};
    sendRequest(
        "POST",
        "/api/v1/network/protection/warp/profile",
        body,
        [this](const QJsonDocument &doc) {
            setNetworkProtectionLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/warp/profile", "WARP profile response was not an object.");
                return;
            }
            updateNetworkProtectionWarpProfile(doc.object());
            const QJsonObject obj = doc.object();
            const QJsonObject profile = obj.value("profile").toObject();
            if (!profile.isEmpty()) {
                fetchNetworkProtectionProfiles();
                updateNetworkProtectionStatus(QJsonObject{
                    {"mode", "unknown"},
                    {"state", profile.value("status").toString("blocked")},
                    {"strict", profile.value("strict").toBool(true)},
                    {"protectedApps", QJsonArray()},
                    {"torrentReachability", QJsonObject()},
                    {"managedDownloaders", QJsonObject()},
                    {"activeProfile", profile},
                    {"checks", obj.value("checks").toArray()},
                    {"blocker", obj.value("blocker")}
                });
                const QString profileId = profile.value("id").toString();
                if (!profileId.isEmpty() && obj.value("blocker").isNull()) {
                    switchNetworkProtectionProfile(profileId, true);
                }
            }
        },
        [this](const QString &) {
            setNetworkProtectionLoading(false);
        });
}

void ApiClient::resetCloudflareWarpProfile(bool recreate) {
    setNetworkProtectionLoading(true);
    QJsonObject body{
        {"confirmReset", true},
        {"recreate", recreate}
    };
    sendRequest(
        "POST",
        "/api/v1/network/protection/warp/reset",
        body,
        [this](const QJsonDocument &doc) {
            setNetworkProtectionLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/warp/reset", "WARP reset response was not an object.");
                return;
            }
            updateNetworkProtectionWarpProfile(doc.object());
            fetchNetworkProtectionProfiles();
            fetchNetworkProtectionWarpDiagnostics();
            fetchNetworkProtectionStatus();
        },
        [this](const QString &) {
            setNetworkProtectionLoading(false);
        });
}

void ApiClient::importWireGuardProfile(const QString &name, const QString &config) {
    importWireGuardProfileWithOptions(name, config, QString(), 0, QString(), QString());
}

void ApiClient::importWireGuardProfileWithOptions(
    const QString &name,
    const QString &config,
    const QString &provider,
    int forwardedPort,
    const QString &forwardedPortProtocol,
    const QString &forwardedPortSource) {
    const QString trimmedConfig = config.trimmed();
    if (trimmedConfig.isEmpty()) {
        emit requestFailed("/api/v1/network/protection/import/wireguard", "WireGuard config is required.");
        return;
    }
    setNetworkProtectionLoading(true);
    QJsonObject body{
        {"name", name.trimmed().isEmpty() ? QString("Imported WireGuard") : name.trimmed()},
        {"config", trimmedConfig}
    };
    const QString trimmedProvider = provider.trimmed();
    if (!trimmedProvider.isEmpty()) {
        body.insert("provider", trimmedProvider);
    }
    insertForwardedPort(body, forwardedPort, forwardedPortProtocol, forwardedPortSource);
    sendRequest(
        "POST",
        "/api/v1/network/protection/import/wireguard",
        body,
        [this](const QJsonDocument &doc) {
            setNetworkProtectionLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/import/wireguard", "WireGuard import response was not an object.");
                return;
            }
            updateNetworkProtectionImportResult(doc.object());
            fetchNetworkProtectionProfiles();
            fetchNetworkProtectionStatus();
            fetchNetworkProtectionListenPortSyncPlan();
        },
        [this](const QString &) {
            setNetworkProtectionLoading(false);
        });
}

void ApiClient::importOpenVpnProfile(
    const QString &name,
    const QString &config,
    const QString &username,
    const QString &password) {
    importOpenVpnProfileWithOptions(name, config, username, password, QString(), 0, QString(), QString());
}

void ApiClient::importOpenVpnProfileWithOptions(
    const QString &name,
    const QString &config,
    const QString &username,
    const QString &password,
    const QString &provider,
    int forwardedPort,
    const QString &forwardedPortProtocol,
    const QString &forwardedPortSource) {
    const QString trimmedConfig = config.trimmed();
    if (trimmedConfig.isEmpty()) {
        emit requestFailed("/api/v1/network/protection/import/openvpn", "OpenVPN config is required.");
        return;
    }
    QJsonObject body{
        {"name", name.trimmed().isEmpty() ? QString("Imported OpenVPN") : name.trimmed()},
        {"config", trimmedConfig}
    };
    if (!username.trimmed().isEmpty()) {
        body.insert("username", username.trimmed());
    }
    if (!password.trimmed().isEmpty()) {
        body.insert("password", password.trimmed());
    }
    const QString trimmedProvider = provider.trimmed();
    if (!trimmedProvider.isEmpty()) {
        body.insert("provider", trimmedProvider);
    }
    insertForwardedPort(body, forwardedPort, forwardedPortProtocol, forwardedPortSource);
    setNetworkProtectionLoading(true);
    sendRequest(
        "POST",
        "/api/v1/network/protection/import/openvpn",
        body,
        [this](const QJsonDocument &doc) {
            setNetworkProtectionLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/import/openvpn", "OpenVPN import response was not an object.");
                return;
            }
            updateNetworkProtectionImportResult(doc.object());
            fetchNetworkProtectionProfiles();
            fetchNetworkProtectionStatus();
            fetchNetworkProtectionListenPortSyncPlan();
        },
        [this](const QString &) {
            setNetworkProtectionLoading(false);
        });
}

void ApiClient::switchNetworkProtectionProfile(const QString &targetProfileId, bool apply) {
    const QString trimmed = targetProfileId.trimmed();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/network/protection/switch", "Target profile is required.");
        return;
    }
    setNetworkProtectionLoading(true);
    QJsonObject body{
        {"targetProfileId", trimmed},
        {"apply", apply}
    };
    sendRequest(
        "POST",
        "/api/v1/network/protection/switch",
        body,
        [this](const QJsonDocument &doc) {
            setNetworkProtectionLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/network/protection/switch", "Network protection switch response was not an object.");
                return;
            }
            updateNetworkProtectionSwitchResult(doc.object());
            fetchNetworkProtectionProfiles();
            fetchNetworkProtectionWarpDiagnostics();
            fetchNetworkProtectionStatus();
            fetchNetworkProtectionListenPortSyncPlan();
        },
        [this](const QString &) {
            setNetworkProtectionLoading(false);
        });
}

void ApiClient::fetchDownloadBrokerRoutes() {
    sendRequest(
        "GET",
        "/api/v1/download-broker/routes",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/download-broker/routes", "Download broker routes response was not an object.");
                return;
            }
            updateDownloadBrokerRoutes(doc.object());
        });
}

void ApiClient::updateDownloadBrokerRoute(const QString &logicalId, const QString &bindingKind) {
    updateDownloadBrokerRouteForOwner(logicalId, bindingKind, QString());
}

void ApiClient::updateDownloadBrokerRouteForOwner(
    const QString &logicalId,
    const QString &bindingKind,
    const QString &ownerId) {
    const QString trimmedLogicalId = logicalId.trimmed();
    const QString trimmedBindingKind = bindingKind.trimmed();
    if (trimmedLogicalId.isEmpty() || trimmedBindingKind.isEmpty()) {
        emit requestFailed("/api/v1/download-broker/routes", "Route and binding kind are required.");
        return;
    }
    QJsonObject body{{"bindingKind", trimmedBindingKind}};
    const QString trimmedOwnerId = ownerId.trimmed();
    if (!trimmedOwnerId.isEmpty() && trimmedOwnerId != QStringLiteral("default")) {
        body.insert("ownerId", trimmedOwnerId);
    }
    sendRequest(
        "PUT",
        "/api/v1/download-broker/routes/" + trimmedLogicalId,
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/download-broker/routes", "Download broker route response was not an object.");
                return;
            }
            fetchDownloadBrokerRoutes();
        });
}

void ApiClient::setNetworkProtectionLoading(bool loading) {
    if (m_networkProtectionLoading == loading) {
        return;
    }
    m_networkProtectionLoading = loading;
    emit networkProtectionLoadingChanged();
}

void ApiClient::setLiveEgressLoading(bool loading) {
    if (m_liveEgressLoading == loading) {
        return;
    }
    m_liveEgressLoading = loading;
    emit liveEgressLoadingChanged();
}

void ApiClient::updateLiveEgressStatus(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_liveEgressStatus == value) {
        return;
    }
    m_liveEgressStatus = value;
    emit liveEgressChanged();
}

void ApiClient::updateNetworkProtectionStatus(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionStatus == value) {
        return;
    }
    m_networkProtectionStatus = value;
    emit networkProtectionChanged();
}

void ApiClient::updateNetworkProtectionWarpDisclosure(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionWarpDisclosure == value) {
        return;
    }
    m_networkProtectionWarpDisclosure = value;
    emit networkProtectionChanged();
}

void ApiClient::updateNetworkProtectionWarpProfile(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionWarpProfile == value) {
        return;
    }
    m_networkProtectionWarpProfile = value;
    emit networkProtectionChanged();
}

void ApiClient::updateNetworkProtectionWarpDiagnostics(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionWarpDiagnostics == value) {
        return;
    }
    m_networkProtectionWarpDiagnostics = value;
    emit networkProtectionChanged();
}

void ApiClient::updateNetworkProtectionProfiles(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionProfiles == value) {
        return;
    }
    m_networkProtectionProfiles = value;
    emit networkProtectionChanged();
}

void ApiClient::updateNetworkProtectionImportResult(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionImportResult == value) {
        return;
    }
    m_networkProtectionImportResult = value;
    emit networkProtectionChanged();
}

void ApiClient::updateNetworkProtectionSwitchResult(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionSwitchResult == value) {
        return;
    }
    m_networkProtectionSwitchResult = value;
    emit networkProtectionChanged();
}

void ApiClient::updateNetworkProtectionProviderPresets(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionProviderPresets == value) {
        return;
    }
    m_networkProtectionProviderPresets = value;
    emit networkProtectionChanged();
}

void ApiClient::updateNetworkProtectionListenPortSyncPlan(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_networkProtectionListenPortSyncPlan == value) {
        return;
    }
    m_networkProtectionListenPortSyncPlan = value;
    emit networkProtectionChanged();
}

void ApiClient::updateDownloadBrokerRoutes(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_downloadBrokerRoutes == value) {
        return;
    }
    m_downloadBrokerRoutes = value;
    emit networkProtectionChanged();
}

void ApiClient::setPlaybackHardwareLoading(bool loading) {
    if (m_playbackHardwareLoading == loading) {
        return;
    }
    m_playbackHardwareLoading = loading;
    emit playbackHardwareLoadingChanged();
}

void ApiClient::updatePlaybackHardwareReadiness(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_playbackHardwareReadiness == value) {
        return;
    }
    m_playbackHardwareReadiness = value;
    emit playbackHardwareChanged();
}

void ApiClient::updatePlaybackHardwareWarnings(const QJsonArray &warnings) {
    const QVariantList value = warnings.toVariantList();
    if (m_playbackHardwareWarnings == value) {
        return;
    }
    m_playbackHardwareWarnings = value;
    emit playbackHardwareChanged();
}

void ApiClient::setAnimeInferenceSettingsLoading(bool loading) {
    if (m_animeInferenceSettingsLoading == loading) {
        return;
    }
    m_animeInferenceSettingsLoading = loading;
    emit animeInferenceSettingsLoadingChanged();
}

void ApiClient::updateAnimeInferenceSettings(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_animeInferenceSettings == value) {
        return;
    }
    m_animeInferenceSettings = value;
    emit animeInferenceSettingsChanged();
}

void ApiClient::setPlaybackAdminDiagnosticsLoading(bool loading) {
    if (m_playbackAdminDiagnosticsLoading == loading) {
        return;
    }
    m_playbackAdminDiagnosticsLoading = loading;
    emit playbackAdminDiagnosticsLoadingChanged();
}

void ApiClient::updatePlaybackAdminDiagnostics(const QJsonObject &obj) {
    const QVariantMap value = obj.toVariantMap();
    if (m_playbackAdminDiagnostics == value) {
        return;
    }
    m_playbackAdminDiagnostics = value;
    emit playbackAdminDiagnosticsChanged();
}

void ApiClient::setMediaSegmentJobsLoading(bool loading) {
    if (m_mediaSegmentJobsLoading == loading) {
        return;
    }
    m_mediaSegmentJobsLoading = loading;
    emit mediaSegmentJobsLoadingChanged();
}

void ApiClient::setMediaSegmentWorkerRunning(bool running) {
    if (m_mediaSegmentWorkerRunning == running) {
        return;
    }
    m_mediaSegmentWorkerRunning = running;
    emit mediaSegmentWorkerRunningChanged();
}

void ApiClient::updateMediaSegmentJobs(const QJsonArray &jobs) {
    const QVariantList value = jobs.toVariantList();
    if (m_mediaSegmentJobs == value) {
        return;
    }
    m_mediaSegmentJobs = value;
    emit mediaSegmentJobsChanged();
}

void ApiClient::upsertMediaSegmentJob(const QVariantMap &job) {
    const QString id = job.value("id").toString().trimmed();
    if (id.isEmpty()) {
        return;
    }

    QVariantList updated = m_mediaSegmentJobs;
    bool replaced = false;
    for (qsizetype i = 0; i < updated.size(); ++i) {
        const QVariantMap current = updated.at(i).toMap();
        if (current.value("id").toString() == id) {
            updated.replace(i, job);
            replaced = true;
            break;
        }
    }
    if (!replaced) {
        updated.prepend(job);
    }
    if (m_mediaSegmentJobs == updated) {
        return;
    }
    m_mediaSegmentJobs = updated;
    emit mediaSegmentJobsChanged();
}

void ApiClient::setMediaSegmentCandidatesLoading(bool loading) {
    if (m_mediaSegmentCandidatesLoading == loading) {
        return;
    }
    m_mediaSegmentCandidatesLoading = loading;
    emit mediaSegmentCandidatesLoadingChanged();
}

void ApiClient::updateMediaSegmentCandidates(const QJsonArray &candidates) {
    const QVariantList value = candidates.toVariantList();
    if (m_mediaSegmentCandidates == value) {
        return;
    }
    m_mediaSegmentCandidates = value;
    emit mediaSegmentCandidatesChanged();
}

void ApiClient::setMediaInteractionLibrariesLoading(bool loading) {
    if (m_mediaInteractionLibrariesLoading == loading) {
        return;
    }
    m_mediaInteractionLibrariesLoading = loading;
    emit mediaInteractionLibrariesLoadingChanged();
}

void ApiClient::updateMediaInteractionLibraries(const QJsonArray &libraries) {
    const QVariantList value = libraries.toVariantList();
    if (m_mediaInteractionLibraries == value) {
        return;
    }
    m_mediaInteractionLibraries = value;
    emit mediaInteractionLibrariesChanged();
}

void ApiClient::upsertMediaInteractionLibrary(const QVariantMap &library) {
    const QString sourceConfigId =
        library.value("source_config_id", library.value("sourceConfigId")).toString().trimmed();
    if (sourceConfigId.isEmpty()) {
        return;
    }

    QVariantList updated = m_mediaInteractionLibraries;
    bool replaced = false;
    for (qsizetype i = 0; i < updated.size(); ++i) {
        const QVariantMap current = updated.at(i).toMap();
        const QString currentId =
            current.value("source_config_id", current.value("sourceConfigId")).toString();
        if (currentId == sourceConfigId) {
            updated.replace(i, library);
            replaced = true;
            break;
        }
    }
    if (!replaced) {
        updated.append(library);
    }
    if (m_mediaInteractionLibraries == updated) {
        return;
    }
    m_mediaInteractionLibraries = updated;
    emit mediaInteractionLibrariesChanged();
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

void ApiClient::setAcquisitionReviewLoading(bool loading) {
    if (m_acquisitionReviewLoading == loading) {
        return;
    }
    m_acquisitionReviewLoading = loading;
    emit acquisitionReviewLoadingChanged();
}

void ApiClient::updateAcquisitionReviewReleases(const QJsonObject &obj) {
    const QVariantList releases = obj.value("releases").toArray().toVariantList();
    if (m_acquisitionReviewReleases == releases) {
        return;
    }
    m_acquisitionReviewReleases = releases;
    emit acquisitionReviewChanged();
}

void ApiClient::updateAcquisitionReviewDetail(const QJsonObject &obj) {
    const QVariantMap detail = obj.toVariantMap();
    if (m_acquisitionReviewDetail == detail) {
        return;
    }
    m_acquisitionReviewDetail = detail;
    emit acquisitionReviewDetailChanged();
}

void ApiClient::updateAcquisitionSubscriptionCoverage(const QJsonObject &obj) {
    const QVariantMap coverage = obj.toVariantMap();
    if (m_acquisitionSubscriptionCoverage == coverage) {
        return;
    }
    m_acquisitionSubscriptionCoverage = coverage;
    emit acquisitionSubscriptionCoverageChanged();
}

void ApiClient::fetchMediaAcquisition(int limit) {
    const int boundedLimit = qBound(1, limit, 50);
    if (m_mediaAcquisitionFetchInFlight) {
        m_mediaAcquisitionRefreshQueued = true;
        m_mediaAcquisitionQueuedLimit = boundedLimit;
        return;
    }

    m_mediaAcquisitionFetchInFlight = true;
    QUrlQuery query;
    query.addQueryItem("limit", QString::number(boundedLimit));
    const QString path = QString("/api/v1/find/acquisition?%1")
                             .arg(query.toString(QUrl::FullyEncoded));
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/find/acquisition", "Acquisition response was not an object.");
                finishMediaAcquisitionFetch();
                return;
            }
            updateMediaAcquisitionState(doc.object());
            finishMediaAcquisitionFetch();
        },
        [this](const QString &) {
            finishMediaAcquisitionFetch();
        });
}

void ApiClient::findAnotherRelease(const QString &intentId) {
    const QString trimmedIntentId = intentId.trimmed();
    if (trimmedIntentId.isEmpty()) {
        emit requestFailed(
            "/api/v1/find/acquisition/:intent_id/find-another-release",
            "Intent id is required.");
        return;
    }

    sendRequest(
        "POST",
        QString("/api/v1/find/acquisition/%1/find-another-release").arg(trimmedIntentId),
        QJsonObject(),
        [this](const QJsonDocument &) {
            fetchMediaAcquisition();
        });
}

void ApiClient::retryAcquisitionRequest(
    const QString &subscriptionId,
    const QString &reason) {
    const QString trimmedSubscriptionId = subscriptionId.trimmed();
    if (trimmedSubscriptionId.isEmpty()) {
        emit requestFailed(
            "/api/v1/acquisition/requests/:id/retry",
            "Subscription id is required.");
        return;
    }

    QJsonObject body;
    const QString trimmedReason = reason.trimmed();
    if (!trimmedReason.isEmpty()) {
        body.insert("reason", trimmedReason);
    }

    sendRequest(
        "POST",
        QString("/api/v1/acquisition/requests/%1/retry").arg(trimmedSubscriptionId),
        body,
        [this](const QJsonDocument &) {
            fetchMediaAcquisition();
        });
}

void ApiClient::cancelAcquisitionSubscription(
    const QString &subscriptionId,
    const QString &mode,
    const QString &reason,
    bool deleteFiles) {
    const QString trimmedSubscriptionId = subscriptionId.trimmed();
    if (trimmedSubscriptionId.isEmpty()) {
        emit requestFailed(
            "/api/v1/acquisition/subscriptions/:id/cancel",
            "Subscription id is required.");
        return;
    }

    QJsonObject body;
    const QString trimmedMode = mode.trimmed();
    body.insert("mode", trimmedMode.isEmpty() ? QStringLiteral("dismiss") : trimmedMode);
    const QString trimmedReason = reason.trimmed();
    if (!trimmedReason.isEmpty()) {
        body.insert("reason", trimmedReason);
    }
    body.insert("deleteFiles", deleteFiles);

    sendRequest(
        "POST",
        QString("/api/v1/acquisition/subscriptions/%1/cancel").arg(trimmedSubscriptionId),
        body,
        [this](const QJsonDocument &) {
            fetchMediaAcquisition();
        });
}

void ApiClient::fetchAcquisitionReleases(
    const QString &state,
    const QString &subscriptionId,
    int limit) {
    if (m_acquisitionReleasesFetchInFlight) {
        m_acquisitionReleasesRefreshQueued = true;
        m_acquisitionReleasesQueuedState = state;
        m_acquisitionReleasesQueuedSubscriptionId = subscriptionId;
        m_acquisitionReleasesQueuedLimit = limit;
        return;
    }

    m_acquisitionReleasesFetchInFlight = true;
    QUrlQuery query;
    if (!state.trimmed().isEmpty()) {
        query.addQueryItem("state", state.trimmed());
    }
    if (!subscriptionId.trimmed().isEmpty()) {
        query.addQueryItem("subscriptionId", subscriptionId.trimmed());
    }
    if (limit > 0) {
        query.addQueryItem("limit", QString::number(qBound(1, limit, 500)));
    }
    QString path = "/api/v1/acquisition/releases";
    if (!query.isEmpty()) {
        path.append('?');
        path.append(query.toString(QUrl::FullyEncoded));
    }
    setAcquisitionReviewLoading(true);
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/acquisition/releases", "Release review response was not an object.");
                finishAcquisitionReleasesFetch();
                return;
            }
            updateAcquisitionReviewReleases(doc.object());
            finishAcquisitionReleasesFetch();
        },
        [this](const QString &) {
            finishAcquisitionReleasesFetch();
        });
}

void ApiClient::fetchAcquisitionRelease(const QString &releaseId) {
    const QString trimmedReleaseId = releaseId.trimmed();
    if (trimmedReleaseId.isEmpty()) {
        emit requestFailed("/api/v1/acquisition/releases/:id", "Release id is required.");
        return;
    }
    if (!m_acquisitionReviewDetail.isEmpty()) {
        m_acquisitionReviewDetail = QVariantMap();
        emit acquisitionReviewDetailChanged();
    }
    setAcquisitionReviewLoading(true);
    sendRequest(
        "GET",
        QString("/api/v1/acquisition/releases/%1").arg(trimmedReleaseId),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setAcquisitionReviewLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/acquisition/releases/:id", "Release detail response was not an object.");
                return;
            }
            updateAcquisitionReviewDetail(doc.object());
        },
        [this](const QString &) {
            setAcquisitionReviewLoading(false);
        });
}

void ApiClient::fetchAcquisitionSubscriptionCoverage(const QString &subscriptionId) {
    const QString trimmedSubscriptionId = subscriptionId.trimmed();
    if (trimmedSubscriptionId.isEmpty()) {
        emit requestFailed("/api/v1/acquisition/subscriptions/:id/coverage", "Subscription id is required.");
        return;
    }
    setAcquisitionReviewLoading(true);
    sendRequest(
        "GET",
        QString("/api/v1/acquisition/subscriptions/%1/coverage").arg(trimmedSubscriptionId),
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setAcquisitionReviewLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/acquisition/subscriptions/:id/coverage", "Coverage response was not an object.");
                return;
            }
            updateAcquisitionSubscriptionCoverage(doc.object());
        },
        [this](const QString &) {
            setAcquisitionReviewLoading(false);
        });
}

void ApiClient::inspectAcquisitionRelease(const QString &releaseId, const QVariantMap &request) {
    const QString trimmedReleaseId = releaseId.trimmed();
    if (trimmedReleaseId.isEmpty()) {
        emit requestFailed("/api/v1/acquisition/releases/:id/inspect", "Release id is required.");
        return;
    }
    setAcquisitionReviewLoading(true);
    sendRequest(
        "POST",
        QString("/api/v1/acquisition/releases/%1/inspect").arg(trimmedReleaseId),
        QJsonObject::fromVariantMap(request),
        [this, trimmedReleaseId](const QJsonDocument &doc) {
            setAcquisitionReviewLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/acquisition/releases/:id/inspect", "Inspect response was not an object.");
                return;
            }
            updateAcquisitionReviewDetail(doc.object());
            emit acquisitionReviewActionCompleted(trimmedReleaseId, "inspect", doc.object().toVariantMap());
            fetchAcquisitionReleases("review_required", QString(), 50);
            fetchMediaAcquisition();
        },
        [this](const QString &) {
            setAcquisitionReviewLoading(false);
        });
}

void ApiClient::approveAcquisitionRelease(const QString &releaseId, const QVariantMap &request) {
    const QString trimmedReleaseId = releaseId.trimmed();
    if (trimmedReleaseId.isEmpty()) {
        emit requestFailed("/api/v1/acquisition/releases/:id/approve", "Release id is required.");
        return;
    }
    setAcquisitionReviewLoading(true);
    sendRequest(
        "POST",
        QString("/api/v1/acquisition/releases/%1/approve").arg(trimmedReleaseId),
        QJsonObject::fromVariantMap(request),
        [this, trimmedReleaseId](const QJsonDocument &doc) {
            setAcquisitionReviewLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/acquisition/releases/:id/approve", "Approve response was not an object.");
                return;
            }
            updateAcquisitionReviewDetail(doc.object());
            emit acquisitionReviewActionCompleted(trimmedReleaseId, "approve", doc.object().toVariantMap());
            fetchAcquisitionReleases("review_required", QString(), 50);
            fetchMediaAcquisition();
        },
        [this](const QString &) {
            setAcquisitionReviewLoading(false);
        });
}

void ApiClient::rejectAcquisitionRelease(const QString &releaseId, const QVariantMap &request) {
    const QString trimmedReleaseId = releaseId.trimmed();
    if (trimmedReleaseId.isEmpty()) {
        emit requestFailed("/api/v1/acquisition/releases/:id/reject", "Release id is required.");
        return;
    }
    setAcquisitionReviewLoading(true);
    sendRequest(
        "POST",
        QString("/api/v1/acquisition/releases/%1/reject").arg(trimmedReleaseId),
        QJsonObject::fromVariantMap(request),
        [this, trimmedReleaseId](const QJsonDocument &doc) {
            setAcquisitionReviewLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/acquisition/releases/:id/reject", "Reject response was not an object.");
                return;
            }
            updateAcquisitionReviewDetail(doc.object());
            emit acquisitionReviewActionCompleted(trimmedReleaseId, "reject", doc.object().toVariantMap());
            fetchAcquisitionReleases("review_required", QString(), 50);
            fetchMediaAcquisition();
        },
        [this](const QString &) {
            setAcquisitionReviewLoading(false);
        });
}

void ApiClient::retryAcquisitionRelease(const QString &releaseId, const QVariantMap &request) {
    const QString trimmedReleaseId = releaseId.trimmed();
    if (trimmedReleaseId.isEmpty()) {
        emit requestFailed("/api/v1/acquisition/releases/:id/retry", "Release id is required.");
        return;
    }
    setAcquisitionReviewLoading(true);
    sendRequest(
        "POST",
        QString("/api/v1/acquisition/releases/%1/retry").arg(trimmedReleaseId),
        QJsonObject::fromVariantMap(request),
        [this, trimmedReleaseId](const QJsonDocument &doc) {
            setAcquisitionReviewLoading(false);
            if (!doc.isObject()) {
                emit requestFailed("/api/v1/acquisition/releases/:id/retry", "Retry response was not an object.");
                return;
            }
            updateAcquisitionReviewDetail(doc.object());
            emit acquisitionReviewActionCompleted(trimmedReleaseId, "retry", doc.object().toVariantMap());
            fetchAcquisitionReleases("review_required", QString(), 50);
            fetchMediaAcquisition();
        },
        [this](const QString &) {
            setAcquisitionReviewLoading(false);
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
                merged.insert("sourceProviders", targetsObject.value("sourceCandidates"));
                merged.insert("defaultManagerProviderId", targetsObject.value("defaultManagerProviderId"));
                merged.insert("preferredManagerProviderId", targetsObject.value("preferredManagerProviderId"));
                merged.insert("defaultSourceProviderId", targetsObject.value("defaultSourceProviderId"));
                merged.insert("preferredSourceProviderId", targetsObject.value("preferredSourceProviderId"));

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
                    merged.insert("sourceProviders", targetsObject.value("sourceCandidates"));
                    merged.insert("defaultManagerProviderId", targetsObject.value("defaultManagerProviderId"));
                    merged.insert("preferredManagerProviderId", targetsObject.value("preferredManagerProviderId"));
                    merged.insert("defaultSourceProviderId", targetsObject.value("defaultSourceProviderId"));
                    merged.insert("preferredSourceProviderId", targetsObject.value("preferredSourceProviderId"));

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

void ApiClient::addMediaToAcquisition(
    const QString &mediaType,
    const QVariantMap &item,
    const QVariantMap &options) {
    const QString requestedType = mediaType.trimmed().toLower();
    QString acquisitionType = QStringLiteral("movie");
    if (requestedType == "series" || requestedType == "tv") {
        acquisitionType = QStringLiteral("series");
    } else if (requestedType == "anime") {
        acquisitionType = QStringLiteral("anime");
    }
    const QString title = item.value("title", item.value("name")).toString().trimmed();
    if (title.isEmpty()) {
        emit requestFailed("/api/v1/find/acquisition", "Title is required.");
        return;
    }

    QJsonObject body;
    body.insert("mediaType", acquisitionType);
    body.insert("title", title);

    const QVariant year = item.value("year");
    if (year.isValid() && !year.isNull() && year.toInt() > 0) {
        body.insert("year", year.toInt());
    }

    QVariant externalIds = item.value("externalIds");
    if (!externalIds.isValid() || externalIds.isNull()) {
        externalIds = item.value("external_ids");
    }
    if (externalIds.canConvert<QVariantMap>()) {
        body.insert("externalIds", QJsonObject::fromVariantMap(externalIds.toMap()));
    }

    const QString sourceProviderId = options.value("sourceProviderId").toString().trimmed();
    if (!sourceProviderId.isEmpty()) {
        body.insert("sourceProviderId", sourceProviderId);
    }

    const QString sourceSelectionRoute = options.value("sourceSelectionRoute").toString().trimmed();
    if (!sourceSelectionRoute.isEmpty()) {
        body.insert("sourceSelectionRoute", sourceSelectionRoute);
    }

    const QString sourceSelectionMode = options.value("sourceSelectionMode").toString().trimmed();
    if (!sourceSelectionMode.isEmpty()) {
        body.insert("sourceSelectionMode", sourceSelectionMode);
    }

    const QString sourceSuiteId = options.value("sourceSuiteId").toString().trimmed();
    if (!sourceSuiteId.isEmpty()) {
        body.insert("sourceSuiteId", sourceSuiteId);
    }

    if (options.contains("routePolicy")) {
        const QString routePolicy = options.value("routePolicy").toString().trimmed();
        if (!routePolicy.isEmpty()) {
            body.insert("routePolicy", routePolicy);
        }
    }

    const auto insertStringOption = [&body, &options](const QString &key) {
        if (!options.contains(key)) {
            return;
        }
        const QString value = options.value(key).toString().trimmed();
        if (!value.isEmpty()) {
            body.insert(key, value);
        }
    };
    insertStringOption(QStringLiteral("requestMode"));
    insertStringOption(QStringLiteral("requestScope"));
    insertStringOption(QStringLiteral("metadataPolicy"));
    insertStringOption(QStringLiteral("completionPolicy"));
    insertStringOption(QStringLiteral("idempotencyKey"));

    const QString monitorPolicy = options.value("monitorPolicy").toString().trimmed();
    if (!monitorPolicy.isEmpty()) {
        body.insert("monitorPolicy", monitorPolicy);
    }
    if (options.contains("releaseDelaySeconds")) {
        body.insert("releaseDelaySeconds", options.value("releaseDelaySeconds").toLongLong());
    }
    if (options.contains("scope") && options.value("scope").canConvert<QVariantMap>()) {
        body.insert("scope", QJsonObject::fromVariantMap(options.value("scope").toMap()));
    }
    if (options.contains("animeAudioPreference")
        && options.value("animeAudioPreference").canConvert<QVariantMap>()) {
        const QVariantMap animeAudioPreference = options.value("animeAudioPreference").toMap();
        if (!animeAudioPreference.isEmpty()) {
            body.insert("animeAudioPreference", QJsonObject::fromVariantMap(animeAudioPreference));
        }
    }
    if (options.contains("target") && options.value("target").canConvert<QVariantMap>()) {
        body.insert("target", QJsonObject::fromVariantMap(options.value("target").toMap()));
    }
    if (options.contains("targets")) {
        body.insert("targets", QJsonArray::fromVariantList(options.value("targets").toList()));
    }

    if (!m_mediaAddLoading) {
        m_mediaAddLoading = true;
        emit mediaAddLoadingChanged();
    }
    sendRequest(
        "POST",
        "/api/v1/find/acquisition",
        body,
        [this, title, acquisitionType](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                if (m_mediaAddLoading) {
                    m_mediaAddLoading = false;
                    emit mediaAddLoadingChanged();
                }
                emit requestFailed("/api/v1/find/acquisition", "Acquisition response was not an object.");
                return;
            }

            QVariantMap result = doc.object().toVariantMap();
            const QVariantMap detail = result.value("detail").toMap();
            const QVariantMap subscription = detail.value("subscription").toMap();
            const QString subscriptionId =
                subscription.value("subscriptionId", subscription.value("subscription_id"))
                    .toString();
            if (!subscriptionId.isEmpty()) {
                result.insert("intentId", subscriptionId);
                result.insert("intent_id", subscriptionId);
            }
            result.insert("title", subscription.value("title", title).toString());
            result.insert("mediaType", subscription.value("mediaType", acquisitionType).toString());
            result.insert("managerLabel", QStringLiteral("Elixir acquisition"));
            result.insert("manager_label", QStringLiteral("Elixir acquisition"));
            result.insert("nativeAcquisition", true);
            const QString requestMode =
                subscription.value("requestMode", subscription.value("request_mode", QStringLiteral("monitored")))
                    .toString();
            const QString requestScope =
                subscription.value("requestScope", subscription.value("request_scope", QStringLiteral("subscription")))
                    .toString();
            result.insert("requestMode", requestMode);
            result.insert("requestScope", requestScope);
            result.insert("oneShot", requestMode == QStringLiteral("one_shot"));

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

void ApiClient::fetchFindMediaScopePreview(
    const QString &mediaType,
    const QVariantMap &item,
    const QString &sourceProviderId) {
    const QString acquisitionType = normalizeAcquisitionMediaType(mediaType);

    QJsonObject body;
    body.insert("mediaType", acquisitionType);
    body.insert("result", findMediaScopedIdentity(acquisitionType, item));

    const QString provider = sourceProviderId.trimmed();
    if (!provider.isEmpty()) {
        body.insert("providerId", provider);
    }

    const quint64 requestId = ++m_mediaScopePreviewRequestId;
    m_mediaScopePreview = QVariantMap();
    emit mediaScopePreviewChanged();
    if (!m_mediaScopePreviewLoading) {
        m_mediaScopePreviewLoading = true;
        emit mediaScopePreviewLoadingChanged();
    }

    sendRequest(
        "POST",
        "/api/v1/find-media/scope-preview",
        body,
        [this, requestId](const QJsonDocument &doc) {
            if (requestId != m_mediaScopePreviewRequestId) {
                return;
            }
            if (!doc.isObject()) {
                if (m_mediaScopePreviewLoading) {
                    m_mediaScopePreviewLoading = false;
                    emit mediaScopePreviewLoadingChanged();
                }
                emit requestFailed(
                    "/api/v1/find-media/scope-preview",
                    "Scope preview response was not an object.");
                return;
            }

            const QVariantMap preview = doc.object().toVariantMap();
            if (m_mediaScopePreview != preview) {
                m_mediaScopePreview = preview;
                emit mediaScopePreviewChanged();
            }
            if (m_mediaScopePreviewLoading) {
                m_mediaScopePreviewLoading = false;
                emit mediaScopePreviewLoadingChanged();
            }
        },
        [this, requestId](const QString &) {
            if (requestId != m_mediaScopePreviewRequestId) {
                return;
            }
            if (m_mediaScopePreviewLoading) {
                m_mediaScopePreviewLoading = false;
                emit mediaScopePreviewLoadingChanged();
            }
        });
}

void ApiClient::addScopedMediaFromFind(
    const QString &mediaType,
    const QVariantMap &item,
    const QString &sourceProviderId,
    const QVariantMap &scope,
    const QString &routePolicy,
    const QVariantMap &animeAudioPreference) {
    const QString provider = sourceProviderId.trimmed();
    if (provider.isEmpty()) {
        emit requestFailed(
            "/api/v1/find-media/scoped-add",
            "Install or enable an acquisition source before adding scoped media.");
        return;
    }
    const QString acquisitionType = normalizeAcquisitionMediaType(mediaType);

    QJsonObject body;
    body.insert("providerId", provider);
    body.insert("mediaType", acquisitionType);
    body.insert("result", findMediaScopedIdentity(acquisitionType, item));
    body.insert("scope", QJsonObject::fromVariantMap(scope));
    const QString trimmedRoutePolicy = routePolicy.trimmed();
    if (!trimmedRoutePolicy.isEmpty()) {
        body.insert("routePolicy", trimmedRoutePolicy);
    }
    if (!animeAudioPreference.isEmpty()) {
        body.insert("animeAudioPreference", QJsonObject::fromVariantMap(animeAudioPreference));
    }

    if (!m_mediaAddLoading) {
        m_mediaAddLoading = true;
        emit mediaAddLoadingChanged();
    }
    sendRequest(
        "POST",
        "/api/v1/find-media/scoped-add",
        body,
        [this, item, acquisitionType](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                if (m_mediaAddLoading) {
                    m_mediaAddLoading = false;
                    emit mediaAddLoadingChanged();
                }
                emit requestFailed(
                    "/api/v1/find-media/scoped-add",
                    "Scoped add response was not an object.");
                return;
            }

            QVariantMap result = doc.object().toVariantMap();
            const QString subscriptionId =
                result.value("subscriptionId", result.value("subscription_id")).toString();
            if (!subscriptionId.isEmpty()) {
                result.insert("intentId", subscriptionId);
                result.insert("intent_id", subscriptionId);
            }
            const QString title = item.value("title", item.value("name", QStringLiteral("Media")))
                                      .toString();
            result.insert("title", title);
            result.insert("mediaType", acquisitionType);
            result.insert("managerLabel", QStringLiteral("Elixir acquisition"));
            result.insert("manager_label", QStringLiteral("Elixir acquisition"));
            result.insert("nativeAcquisition", true);
            result.insert("scopedFindMedia", true);
            const QString requestMode =
                result.value("requestMode", result.value("request_mode", QStringLiteral("one_shot")))
                    .toString();
            const QString requestScope =
                result.value("requestScope", result.value("request_scope", QStringLiteral("selected_targets")))
                    .toString();
            result.insert("requestMode", requestMode);
            result.insert("requestScope", requestScope);
            result.insert("oneShot", requestMode == QStringLiteral("one_shot"));

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

void ApiClient::fetchPlaybackInteractionPreferences() {
    sendRequest(
        "GET",
        "/api/v1/profile/playback-interactions",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/profile/playback-interactions",
                    "Playback interaction preferences response was not an object.");
                return;
            }
            const QVariantMap payload =
                normalizePlaybackInteractionPreferencesPayload(doc.object().toVariantMap());
            if (m_playbackInteractionPreferences != payload) {
                m_playbackInteractionPreferences = payload;
                emit playbackInteractionPreferencesChanged();
            }
        });
}

void ApiClient::updatePlaybackInteractionPreferences(const QVariantMap &preferences) {
    sendRequest(
        "PUT",
        "/api/v1/profile/playback-interactions",
        QJsonObject::fromVariantMap(preferences),
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/profile/playback-interactions",
                    "Playback interaction preferences update response was not an object.");
                return;
            }
            const QVariantMap payload =
                normalizePlaybackInteractionPreferencesPayload(doc.object().toVariantMap());
            if (m_playbackInteractionPreferences != payload) {
                m_playbackInteractionPreferences = payload;
                emit playbackInteractionPreferencesChanged();
            }
        });
}

void ApiClient::fetchMediaSegmentJobs(
    const QString &status,
    const QString &providerKind,
    const QString &jobType,
    int limit) {
    QUrlQuery query;
    const QString trimmedStatus = status.trimmed();
    const QString trimmedProviderKind = providerKind.trimmed();
    const QString trimmedJobType = jobType.trimmed();
    if (!trimmedStatus.isEmpty()) {
        query.addQueryItem("status", trimmedStatus);
    }
    if (!trimmedProviderKind.isEmpty()) {
        query.addQueryItem("providerKind", trimmedProviderKind);
    }
    if (!trimmedJobType.isEmpty()) {
        query.addQueryItem("jobType", trimmedJobType);
    }
    query.addQueryItem("limit", QString::number(qBound(1, limit, 500)));

    QString path = "/api/v1/media-segment-jobs";
    if (!query.isEmpty()) {
        path.append('?');
        path.append(query.toString(QUrl::FullyEncoded));
    }

    setMediaSegmentJobsLoading(true);
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setMediaSegmentJobsLoading(false);
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/media-segment-jobs",
                    "Media segment jobs response was not an object.");
                return;
            }
            updateMediaSegmentJobs(doc.object().value("jobs").toArray());
        },
        [this](const QString &) {
            setMediaSegmentJobsLoading(false);
        });
}

void ApiClient::runMediaSegmentWorker() {
    if (m_mediaSegmentWorkerRunning) {
        return;
    }

    setMediaSegmentWorkerRunning(true);
    sendRequest(
        "POST",
        "/api/v1/media-segment-jobs/run-worker",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setMediaSegmentWorkerRunning(false);
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/media-segment-jobs/run-worker",
                    "Media segment worker response was not an object.");
                return;
            }
            const QVariantMap summary = doc.object().value("summary").toObject().toVariantMap();
            emit mediaSegmentWorkerRunCompleted(summary);
        },
        [this](const QString &) {
            setMediaSegmentWorkerRunning(false);
        });
}

void ApiClient::fetchMediaSegmentCandidates(
    const QString &validationState,
    const QString &providerKind,
    bool lowConfidence,
    int limit) {
    QUrlQuery query;
    const QString trimmedValidationState = validationState.trimmed();
    const QString trimmedProviderKind = providerKind.trimmed();
    if (!trimmedValidationState.isEmpty()) {
        query.addQueryItem("validationState", trimmedValidationState);
    }
    if (!trimmedProviderKind.isEmpty()) {
        query.addQueryItem("providerKind", trimmedProviderKind);
    }
    query.addQueryItem("lowConfidence", lowConfidence ? "true" : "false");
    query.addQueryItem("limit", QString::number(qBound(1, limit, 500)));

    QString path = "/api/v1/media-segments/candidates";
    if (!query.isEmpty()) {
        path.append('?');
        path.append(query.toString(QUrl::FullyEncoded));
    }

    setMediaSegmentCandidatesLoading(true);
    sendRequest(
        "GET",
        path,
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setMediaSegmentCandidatesLoading(false);
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/media-segments/candidates",
                    "Media segment candidates response was not an object.");
                return;
            }
            updateMediaSegmentCandidates(doc.object().value("candidates").toArray());
        },
        [this](const QString &) {
            setMediaSegmentCandidatesLoading(false);
        });
}

void ApiClient::fetchMediaInteractionLibraries() {
    setMediaInteractionLibrariesLoading(true);
    sendRequest(
        "GET",
        "/api/v1/media-interaction-libraries",
        QJsonObject(),
        [this](const QJsonDocument &doc) {
            setMediaInteractionLibrariesLoading(false);
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/media-interaction-libraries",
                    "Media interaction libraries response was not an object.");
                return;
            }
            updateMediaInteractionLibraries(doc.object().value("libraries").toArray());
        },
        [this](const QString &) {
            setMediaInteractionLibrariesLoading(false);
        });
}

void ApiClient::updateMediaInteractionLibrarySettings(
    const QString &sourceConfigId,
    const QVariantMap &settings) {
    const QString trimmedSourceConfigId = sourceConfigId.trimmed();
    if (trimmedSourceConfigId.isEmpty()) {
        emit requestFailed(
            "/api/v1/media-interaction-libraries/:source_config_id",
            "Source config id is required.");
        return;
    }

    const QString encodedSourceConfigId =
        QString::fromUtf8(QUrl::toPercentEncoding(trimmedSourceConfigId));
    sendRequest(
        "PUT",
        QString("/api/v1/media-interaction-libraries/%1").arg(encodedSourceConfigId),
        QJsonObject::fromVariantMap(settings),
        [this, trimmedSourceConfigId](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/media-interaction-libraries/:source_config_id",
                    "Media interaction library update response was not an object.");
                return;
            }
            const QVariantMap library = doc.object().value("library").toObject().toVariantMap();
            upsertMediaInteractionLibrary(library);
            emit mediaInteractionLibrarySettingsUpdated(trimmedSourceConfigId, library);
        });
}

void ApiClient::updateMediaItemWatchState(
    const QString &mediaItemId,
    const QString &itemType,
    const QString &action,
    int durationSeconds) {
    const QString trimmedMediaItemId = mediaItemId.trimmed();
    QString normalizedItemType = itemType.trimmed().toLower();
    if (normalizedItemType == "tv" || normalizedItemType == "show") {
        normalizedItemType = QStringLiteral("series");
    }
    QString normalizedAction = action.trimmed().toLower().replace("-", "_");
    if (normalizedAction == "reset_progress") {
        normalizedAction = QStringLiteral("reset");
    }

    if (trimmedMediaItemId.isEmpty()) {
        emit requestFailed(
            "/api/v1/items/:item_type/:item_id/watch-state",
            "Media item id is required.");
        return;
    }
    if (normalizedItemType.isEmpty()) {
        emit requestFailed(
            "/api/v1/items/:item_type/:item_id/watch-state",
            "Media item type is required.");
        return;
    }
    if (normalizedAction != "watched" && normalizedAction != "unwatched"
        && normalizedAction != "reset") {
        emit requestFailed(
            "/api/v1/items/:item_type/:item_id/watch-state",
            "Watch state action must be watched, unwatched, or reset.");
        return;
    }

    QJsonObject body;
    if (durationSeconds > 0) {
        body.insert("durationSeconds", durationSeconds);
    }

    const QString encodedItemType = QString::fromUtf8(QUrl::toPercentEncoding(normalizedItemType));
    const QString encodedMediaItemId =
        QString::fromUtf8(QUrl::toPercentEncoding(trimmedMediaItemId));
    const QString path = QString("/api/v1/items/%1/%2/watch-state/%3")
                             .arg(encodedItemType, encodedMediaItemId, normalizedAction);
    sendRequest(
        "POST",
        path,
        body,
        [this, trimmedMediaItemId, normalizedItemType, normalizedAction, path](
            const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(path, "Watch state response was not an object.");
                return;
            }
            const QVariantMap playbackState =
                doc.object().value("playback_state").toObject().toVariantMap();
            emit mediaWatchStateUpdated(
                trimmedMediaItemId,
                normalizedItemType,
                normalizedAction,
                playbackState);
        });
}

void ApiClient::cancelMediaSegmentJob(
    const QString &jobId,
    const QString &reason) {
    const QString trimmedJobId = jobId.trimmed();
    if (trimmedJobId.isEmpty()) {
        emit requestFailed("/api/v1/media-segment-jobs/:id/cancel", "Job id is required.");
        return;
    }

    QJsonObject body;
    const QString trimmedReason = reason.trimmed();
    if (!trimmedReason.isEmpty()) {
        body.insert("reason", trimmedReason);
    }

    sendRequest(
        "POST",
        QString("/api/v1/media-segment-jobs/%1/cancel").arg(trimmedJobId),
        body,
        [this, trimmedJobId](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/media-segment-jobs/:id/cancel",
                    "Media segment job cancel response was not an object.");
                return;
            }
            const QVariantMap job = doc.object().value("job").toObject().toVariantMap();
            upsertMediaSegmentJob(job);
            emit mediaSegmentJobActionCompleted(trimmedJobId, "cancel", job);
        });
}

void ApiClient::retryMediaSegmentJob(
    const QString &jobId,
    const QString &reason) {
    const QString trimmedJobId = jobId.trimmed();
    if (trimmedJobId.isEmpty()) {
        emit requestFailed("/api/v1/media-segment-jobs/:id/retry", "Job id is required.");
        return;
    }

    QJsonObject body;
    const QString trimmedReason = reason.trimmed();
    if (!trimmedReason.isEmpty()) {
        body.insert("reason", trimmedReason);
    }

    sendRequest(
        "POST",
        QString("/api/v1/media-segment-jobs/%1/retry").arg(trimmedJobId),
        body,
        [this, trimmedJobId](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/media-segment-jobs/:id/retry",
                    "Media segment job retry response was not an object.");
                return;
            }
            const QVariantMap job = doc.object().value("job").toObject().toVariantMap();
            upsertMediaSegmentJob(job);
            emit mediaSegmentJobActionCompleted(trimmedJobId, "retry", job);
        });
}

void ApiClient::updateManagerPreferences(
    const QString &movieProviderId,
    const QString &seriesProviderId,
    const QString &animeProviderId,
    const QString &movieSourceProviderId,
    const QString &seriesSourceProviderId,
    const QString &animeSourceProviderId,
    const QVariantMap &languagePreference) {
    QJsonObject body;
    const QString movie = movieProviderId.trimmed();
    const QString series = seriesProviderId.trimmed();
    const QString anime = animeProviderId.trimmed();
    const QString movieSource = movieSourceProviderId.trimmed();
    const QString seriesSource = seriesSourceProviderId.trimmed();
    const QString animeSource = animeSourceProviderId.trimmed();
    body.insert(
        "moviesDefaultManagerProviderId",
        movie.isEmpty() ? QJsonValue::Null : QJsonValue(movie));
    body.insert(
        "tvDefaultManagerProviderId",
        series.isEmpty() ? QJsonValue::Null : QJsonValue(series));
    body.insert(
        "animeDefaultManagerProviderId",
        anime.isEmpty() ? QJsonValue::Null : QJsonValue(anime));
    body.insert(
        "moviesDefaultSourceProviderId",
        movieSource.isEmpty() ? QJsonValue::Null : QJsonValue(movieSource));
    body.insert(
        "tvDefaultSourceProviderId",
        seriesSource.isEmpty() ? QJsonValue::Null : QJsonValue(seriesSource));
    body.insert(
        "animeDefaultSourceProviderId",
        animeSource.isEmpty() ? QJsonValue::Null : QJsonValue(animeSource));
    if (!languagePreference.isEmpty()) {
        body.insert("languagePreference", QJsonObject::fromVariantMap(languagePreference));
    }

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

void ApiClient::updateStreamHttpEgressPolicy(const QString &policy) {
    const QString trimmed = policy.trimmed().toLower();
    if (trimmed.isEmpty()) {
        emit requestFailed("/api/v1/find/preferences", "Stream HTTP egress policy is required.");
        return;
    }
    QJsonObject body{{"streamHttpEgressPolicy", trimmed}};
    sendRequest(
        "PATCH",
        "/api/v1/find/preferences",
        body,
        [this](const QJsonDocument &doc) {
            if (!doc.isObject()) {
                emit requestFailed(
                    "/api/v1/find/preferences",
                    "Stream egress policy update response was not an object.");
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

void ApiClient::setExtensionUninstalling(const QString &extensionId, bool uninstalling) {
    const bool contains = m_extensionUninstallingIds.contains(extensionId);
    if (contains == uninstalling) {
        return;
    }
    if (uninstalling) {
        m_extensionUninstallingIds.append(extensionId);
    } else {
        m_extensionUninstallingIds.removeAll(extensionId);
    }
    emit extensionUninstallingChanged();
}

void ApiClient::removeInstalledExtension(const QString &extensionId) {
    QVariantList installed;
    installed.reserve(m_extensionsInstalled.size());
    for (const QVariant &value : m_extensionsInstalled) {
        if (value.toMap().value("extension_id").toString() != extensionId) {
            installed.append(value);
        }
    }
    if (installed == m_extensionsInstalled) {
        return;
    }
    m_extensionsInstalled = installed;
    emit extensionsCatalogChanged();
}

void ApiClient::finishMediaAcquisitionFetch() {
    m_mediaAcquisitionFetchInFlight = false;
    if (!m_mediaAcquisitionRefreshQueued || m_authToken.isEmpty()) {
        m_mediaAcquisitionRefreshQueued = false;
        return;
    }

    const int limit = m_mediaAcquisitionQueuedLimit;
    m_mediaAcquisitionRefreshQueued = false;
    fetchMediaAcquisition(limit);
}

void ApiClient::finishAcquisitionReleasesFetch() {
    m_acquisitionReleasesFetchInFlight = false;
    if (!m_acquisitionReleasesRefreshQueued || m_authToken.isEmpty()) {
        m_acquisitionReleasesRefreshQueued = false;
        setAcquisitionReviewLoading(false);
        return;
    }

    const QString state = m_acquisitionReleasesQueuedState;
    const QString subscriptionId = m_acquisitionReleasesQueuedSubscriptionId;
    const int limit = m_acquisitionReleasesQueuedLimit;
    m_acquisitionReleasesRefreshQueued = false;
    fetchAcquisitionReleases(state, subscriptionId, limit);
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
    QVariantMap run = runObj.toVariantMap();
    if (obj.contains("stageSummary")) {
        run.insert("stageSummary", obj.value("stageSummary").toObject().toVariantMap());
    } else if (obj.contains("stage_summary")) {
        run.insert("stageSummary", obj.value("stage_summary").toObject().toVariantMap());
    }
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
        fetchManagerPreferences();
    }
}

void ApiClient::updateExtensionStatusSummary(const QJsonObject &obj) {
    const QVariantList items = obj.value("items").toArray().toVariantList();
    const int needsAttention = obj.value("needsAttentionCount").toInt();
    const QVariantMap runtimeStatus = obj.value("dockerRuntime").toObject().toVariantMap();

    bool changed = false;
    if (m_extensionsStatusItems != items) {
        m_extensionsStatusItems = items;
        changed = true;
    }
    if (m_extensionsNeedsAttentionCount != needsAttention) {
        m_extensionsNeedsAttentionCount = needsAttention;
        changed = true;
    }
    if (m_extensionsRuntimeStatus != runtimeStatus) {
        m_extensionsRuntimeStatus = runtimeStatus;
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
    QUrl url(trimmed);
    const QString scheme = url.scheme().toLower();
    if (!url.isValid()
        || (scheme != "http" && scheme != "https")
        || url.host().isEmpty()) {
        return QString();
    }
    url.setScheme(scheme);
    url.setHost(url.host().toLower());
    url.setUserInfo(QString());
    url.setPath(QString());
    url.setQuery(QString());
    url.setFragment(QString());
    return url.toString(QUrl::FullyEncoded);
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
    PendingRequest request;
    request.method = method;
    request.path = path;
    request.body = body;
    request.onSuccess = onSuccess;
    request.onError = onError;
    request.allowNonJson = allowNonJson;
    request.attachAuthorization = !isPublicAuthPath(path);
    request.generation = m_requestGeneration;

    const bool isProfileSelection = path.startsWith("/api/v1/profiles/")
        && path.endsWith("/select");
    if ((m_profileSwitchInFlight && !isProfileSelection)
        || (m_logoutInFlight && path != "/api/v1/auth/logout")) {
        const QString message = m_logoutInFlight
            ? QStringLiteral("Sign-out is in progress.")
            : QStringLiteral("Profile selection is in progress.");
        const QVariantMap error{
            {"endpoint", path},
            {"code", "auth_context_transition"},
            {"message", message},
        };
        emitRequestError(request, error, message);
        return;
    }

    if (m_baseUrl.trimmed().isEmpty()) {
        const QString msg = "Base URL is not set.";
        QVariantMap error{{"endpoint", path}, {"code", "base_url_missing"}, {"message", msg}};
        emitRequestError(request, error, msg);
        return;
    }

    if (request.attachAuthorization
        && canRefreshRequest(path)
        && hasRefreshToken()
        && accessTokenNearExpiry()) {
        queueForRefresh(std::move(request));
        return;
    }
    dispatchRequest(std::move(request));
}

void ApiClient::dispatchRequest(PendingRequest request) {
    if (request.generation != m_requestGeneration) {
        return;
    }

    const QStringList bodyKeys = request.body.keys();
    qInfo() << "API request" << request.method << request.path << "base" << m_baseUrl
            << "keys" << bodyKeys;

    QNetworkRequest networkRequest(makeUrl(request.path));
    networkRequest.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    networkRequest.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::ManualRedirectPolicy);
    const QString locale = QLocale::system().name().replace('_', '-');
    if (!locale.trimmed().isEmpty()) {
        networkRequest.setRawHeader("Accept-Language", locale.toUtf8());
    }
    if (request.attachAuthorization && !m_authToken.isEmpty()) {
        networkRequest.setRawHeader("Authorization", QByteArray("Bearer ") + m_authToken.toUtf8());
    }

    QNetworkReply *reply = nullptr;
    if (request.method == "GET") {
        reply = m_manager.get(networkRequest);
    } else if (request.method == "POST") {
        reply = m_manager.post(networkRequest, QJsonDocument(request.body).toJson());
    } else {
        reply = m_manager.sendCustomRequest(
            networkRequest,
            request.method.toUtf8(),
            QJsonDocument(request.body).toJson());
    }
    m_activeReplies.insert(reply);

    connect(reply, &QNetworkReply::finished, this, [this, reply, request = std::move(request)]() mutable {
        m_activeReplies.remove(reply);
        if (request.generation != m_requestGeneration) {
            reply->deleteLater();
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray payload = reply->readAll();
        const bool okStatus = status >= 200 && status < 300;
        qInfo() << "API response" << request.path << "status" << status
                << "bytes" << payload.size() << "error" << reply->error();

        if (reply->error() != QNetworkReply::NoError || !okStatus) {
            const QVariantMap errorDetail =
                parseApiErrorPayload(payload, reply->errorString(), status, request.path);
            const QString detail = errorDetail.value("message").toString();
            if (status == 401
                && request.attachAuthorization
                && canRefreshRequest(request.path)
                && request.retryCount == 0
                && hasRefreshToken()) {
                ++request.retryCount;
                reply->deleteLater();
                queueForRefresh(std::move(request));
                return;
            }
            if (status == 401 && request.attachAuthorization && !m_refreshInFlight) {
                clearAuthenticationState(true);
                emit authExpired(
                    detail.isEmpty()
                        ? QStringLiteral("This device was signed out.")
                        : detail);
            }
            emitRequestError(request, errorDetail, detail);
            reply->deleteLater();
            return;
        }

        if (!request.onSuccess) {
            reply->deleteLater();
            return;
        }

        QJsonParseError parseError;
        const QJsonDocument doc = QJsonDocument::fromJson(payload, &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            if (request.allowNonJson) {
                qInfo() << "API response (non-JSON)" << request.path << "bytes" << payload.size();
                request.onSuccess(QJsonDocument());
                reply->deleteLater();
                return;
            }
            const QString detail = QString("Invalid JSON: %1").arg(parseError.errorString());
            const QVariantMap errorDetail{
                {"endpoint", request.path},
                {"code", "invalid_json"},
                {"message", detail},
            };
            emitRequestError(request, errorDetail, detail);
            reply->deleteLater();
            return;
        }

        request.onSuccess(doc);
        reply->deleteLater();
    });
}

void ApiClient::queueForRefresh(PendingRequest request) {
    if (request.generation != m_requestGeneration) {
        return;
    }
    if (m_pendingRequests.size() >= kMaxPendingAuthRequests) {
        const QString message = QStringLiteral("Too many requests are waiting for authentication.");
        const QVariantMap error{
            {"endpoint", request.path},
            {"code", "auth_queue_full"},
            {"message", message},
        };
        emitRequestError(request, error, message);
        return;
    }
    m_pendingRequests.push_back(std::move(request));
    beginRefresh(false);
}

void ApiClient::beginRefresh(bool restoring) {
    if (m_refreshInFlight) {
        m_refreshRestoring = m_refreshRestoring || restoring;
        return;
    }
    if (!hasRefreshToken()) {
        finishRefreshFailure(QStringLiteral("No remembered session is available."), restoring);
        return;
    }

    m_refreshInFlight = true;
    m_refreshRestoring = restoring;
    emit refreshInFlightChanged();
    QJsonObject body{{"refresh_token", m_refreshToken}};
    addClientSessionContext(body, false);
    PendingRequest request;
    request.method = "POST";
    request.path = "/api/v1/auth/refresh";
    request.body = body;
    request.attachAuthorization = false;
    request.retryCount = 1;
    request.generation = m_requestGeneration;
    request.onSuccess = [this](const QJsonDocument &doc) {
        if (!doc.isObject()) {
            finishRefreshFailure(QStringLiteral("Unexpected refresh response."), m_refreshRestoring);
            return;
        }
        finishRefreshSuccess(doc.object(), m_refreshRestoring);
    };
    request.onError = [this](const QString &error) {
        finishRefreshFailure(error, m_refreshRestoring);
    };
    dispatchRequest(std::move(request));
}

void ApiClient::finishRefreshSuccess(const QJsonObject &response, bool restoring) {
    QString error;
    if (!applyTokenResponse(response, &error)) {
        finishRefreshFailure(error, restoring);
        return;
    }

    PendingRequest sessionRequest;
    sessionRequest.method = "GET";
    sessionRequest.path = "/api/v1/auth/session";
    sessionRequest.attachAuthorization = true;
    sessionRequest.retryCount = 1;
    sessionRequest.generation = m_requestGeneration;
    sessionRequest.onSuccess = [this, restoring](const QJsonDocument &doc) {
        QString sessionError;
        if (!doc.isObject() || !applySessionResponse(doc.object(), &sessionError)) {
            finishRefreshFailure(
                sessionError.isEmpty()
                    ? QStringLiteral("Unexpected account-session response.")
                    : sessionError,
                restoring);
            return;
        }
        m_refreshInFlight = false;
        m_refreshRestoring = false;
        emit refreshInFlightChanged();
        if (restoring) {
            emit sessionRestored();
        }
        replayPendingRequests();
    };
    sessionRequest.onError = [this, restoring](const QString &sessionError) {
        finishRefreshFailure(sessionError, restoring);
    };
    dispatchRequest(std::move(sessionRequest));
}

void ApiClient::finishRefreshFailure(const QString &error, bool restoring) {
    const QString detail = error.trimmed().isEmpty()
        ? QStringLiteral("This device was signed out.")
        : error.trimmed();
    const bool wasInFlight = m_refreshInFlight;
    m_refreshInFlight = false;
    m_refreshRestoring = false;
    if (wasInFlight) {
        emit refreshInFlightChanged();
    }
    clearAuthenticationState(true);
    failPendingRequests(detail);
    if (restoring) {
        emit sessionRestoreFailed(detail);
    }
    emit authExpired(detail);
}

void ApiClient::replayPendingRequests() {
    QList<PendingRequest> pending = std::move(m_pendingRequests);
    m_pendingRequests.clear();
    for (PendingRequest &request : pending) {
        if (request.generation != m_requestGeneration) {
            continue;
        }
        dispatchRequest(std::move(request));
    }
}

void ApiClient::failPendingRequests(const QString &error) {
    QList<PendingRequest> pending = std::move(m_pendingRequests);
    m_pendingRequests.clear();
    for (const PendingRequest &request : pending) {
        const QVariantMap detail{
            {"endpoint", request.path},
            {"code", "auth_refresh_failed"},
            {"message", error},
        };
        emitRequestError(request, detail, error);
    }
}

void ApiClient::cancelOutstandingRequests(const QString &reason) {
    ++m_requestGeneration;
    ++m_extensionsCatalogRequestId;
    ++m_extensionControlRequestId;
    const bool wasRefreshing = m_refreshInFlight;
    m_refreshInFlight = false;
    m_refreshRestoring = false;
    m_profileSwitchInFlight = false;
    m_logoutInFlight = false;
    m_mediaAcquisitionFetchInFlight = false;
    m_mediaAcquisitionRefreshQueued = false;
    m_acquisitionReleasesFetchInFlight = false;
    m_acquisitionReleasesRefreshQueued = false;
    setAcquisitionReviewLoading(false);
    if (m_extensionControlLoading) {
        m_extensionControlLoading = false;
        emit extensionControlLoadingChanged();
    }
    if (!m_extensionUninstallingIds.isEmpty()) {
        m_extensionUninstallingIds.clear();
        emit extensionUninstallingChanged();
    }
    if (wasRefreshing) {
        emit refreshInFlightChanged();
    }
    const QSet<QNetworkReply *> replies = m_activeReplies;
    m_activeReplies.clear();
    for (QNetworkReply *reply : replies) {
        if (reply) {
            reply->abort();
        }
    }
    failPendingRequests(reason);
}

void ApiClient::clearAuthenticationState(bool clearRefreshToken) {
    m_profileSwitchInFlight = false;
    m_logoutInFlight = false;
    setAuthToken(QString());
    setAccessTokenExpiresAt(QString());
    if (clearRefreshToken) {
        setRefreshToken(QString());
    }
    setSessionState(QVariantMap());
    if (!m_profiles.isEmpty()) {
        m_profiles.clear();
        emit profilesChanged();
    }
}

bool ApiClient::applyTokenResponse(const QJsonObject &response, QString *error) {
    const QString accessToken = response.value("access_token").toString();
    const QString refreshToken = response.value("refresh_token").toString();
    const QString accessExpiresAt = response.value("access_expires_at").toString();
    const QString refreshExpiresAt = response.value("refresh_expires_at").toString();
    const QString sessionId = response.value("session_id").toString();
    const QString homeId = response.value("home_id").toString();
    const QString profileId = response.value("profile_id").toString();
    const QString role = response.value("role").toString();
    const QJsonObject profile = response.value("profile").toObject();
    const QDateTime expiry = QDateTime::fromString(accessExpiresAt, Qt::ISODate);
    const QDateTime refreshExpiry = QDateTime::fromString(refreshExpiresAt, Qt::ISODate);
    const QDateTime now = QDateTime::currentDateTimeUtc();
    if (!isSafeToken(accessToken)
        || !isSafeToken(refreshToken)
        || !expiry.isValid()
        || !refreshExpiry.isValid()
        || expiry <= now
        || refreshExpiry <= now
        || sessionId.isEmpty()
        || homeId.isEmpty()
        || profileId.isEmpty()
        || role.isEmpty()
        || profile.value("id").toString() != profileId
        || profile.value("display_name").toString().trimmed().isEmpty()
        || profile.value("profile_type").toString().isEmpty()) {
        if (error) {
            *error = QStringLiteral("Invalid authentication response.");
        }
        return false;
    }

    QVariantMap state = sessionState();
    if (state.value("active_profile_id").toString() != profileId) {
        state.insert("capabilities", QStringList());
        state.insert("capability_revision", 0);
    }
    state.insert("session_id", sessionId);
    state.insert("home_id", homeId);
    state.insert("active_profile_id", profileId);
    state.insert("active_profile_name", profile.value("display_name").toString());
    state.insert("active_profile_type", profile.value("profile_type").toString());
    state.insert("role", role);
    setAuthToken(accessToken);
    setAccessTokenExpiresAt(accessExpiresAt);
    setRefreshToken(refreshToken);
    setSessionState(state);
    if (error) {
        error->clear();
    }
    return true;
}

bool ApiClient::applySessionResponse(const QJsonObject &response, QString *error) {
    const QString sessionId = response.value("session_id").toString();
    const QString homeId = response.value("home_id").toString();
    const QString profileId = response.value("active_profile_id").toString();
    const QString role = response.value("role").toString();
    const QString accessExpiresAt = response.value("access_expires_at").toString();
    const QJsonObject profile = response.value("profile").toObject();
    const QJsonArray capabilitiesJson = response.value("capabilities").toArray();
    const qint64 revision = response.value("capability_revision").toVariant().toLongLong();
    const QDateTime expiry = QDateTime::fromString(accessExpiresAt, Qt::ISODate);
    if (sessionId.isEmpty()
        || homeId.isEmpty()
        || profileId.isEmpty()
        || role.isEmpty()
        || !expiry.isValid()
        || expiry <= QDateTime::currentDateTimeUtc()
        || profile.value("id").toString() != profileId
        || profile.value("display_name").toString().trimmed().isEmpty()
        || profile.value("profile_type").toString().isEmpty()
        || revision <= 0
        || (!m_sessionId.isEmpty() && m_sessionId != sessionId)
        || (!m_homeId.isEmpty() && m_homeId != homeId)) {
        if (error) {
            *error = QStringLiteral("Invalid account-session response.");
        }
        return false;
    }
    QStringList capabilities;
    QSet<QString> uniqueCapabilities;
    for (const QJsonValue &value : capabilitiesJson) {
        const QString capability = value.toString().trimmed();
        if (capability.isEmpty() || uniqueCapabilities.contains(capability)) {
            if (error) {
                *error = QStringLiteral("Invalid account-session capabilities.");
            }
            return false;
        }
        uniqueCapabilities.insert(capability);
        capabilities.push_back(capability);
    }
    QVariantMap state{
        {"session_id", sessionId},
        {"home_id", homeId},
        {"active_profile_id", profileId},
        {"active_profile_name", profile.value("display_name").toString()},
        {"active_profile_type", profile.value("profile_type").toString()},
        {"role", role},
        {"capabilities", capabilities},
        {"capability_revision", revision},
    };
    setAccessTokenExpiresAt(accessExpiresAt);
    setSessionState(state);
    if (error) {
        error->clear();
    }
    return true;
}

bool ApiClient::isPublicAuthPath(const QString &path) {
    return path == "/api/v1/auth/login"
        || path == "/api/v1/auth/signup"
        || path == "/api/v1/auth/refresh"
        || path.startsWith("/api/v1/auth/reset/");
}

bool ApiClient::canRefreshRequest(const QString &path) {
    return !isPublicAuthPath(path);
}

void ApiClient::emitRequestError(
    const PendingRequest &request,
    const QVariantMap &errorDetail,
    const QString &message) {
    if (request.onError) {
        request.onError(message);
    }
    if (request.path == "/api/v1/play") {
        emit playbackFailed(errorDetail);
    }
    emit requestFailedDetailed(request.path, errorDetail);
    emit requestFailed(request.path, message);
}
