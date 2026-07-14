#include "backend/SessionManager.h"
#include "backend/CredentialStore.h"

#include <QUrl>
#include <utility>

namespace {
constexpr const char *kBaseUrlKey = "session/baseUrl";
constexpr const char *kRegistryUrlKey = "session/registryUrl";
constexpr const char *kAuthTokenKey = "session/authToken";
constexpr const char *kAccessTokenExpiresAtKey = "session/accessTokenExpiresAt";
constexpr const char *kRefreshTokenService = "com.elixir.media.auth.refresh-token.v1";
constexpr const char *kControlPlaneEmailKey = "session/controlPlaneEmail";
constexpr const char *kControlPlaneTokenKey = "session/controlPlaneToken";
constexpr const char *kControlPlaneExpiresAtKey = "session/controlPlaneExpiresAt";
constexpr const char *kSelectedServerIdKey = "session/selectedServerId";
constexpr const char *kPlaybackQualityModeKey = "playback/qualityMode";
constexpr const char *kPlaybackMaxResolutionKey = "playback/maxResolution";
constexpr const char *kPlaybackMaxBitrateKey = "playback/maxBitrateBps";
constexpr const char *kPlaybackSupportedContainersKey = "playback/supportedContainers";
constexpr const char *kPlaybackSupportedVideoCodecsKey = "playback/supportedVideoCodecs";
constexpr const char *kPlaybackSupportedAudioCodecsKey = "playback/supportedAudioCodecs";
constexpr const char *kPlaybackProfileVersionKey = "playback/profileVersion";
constexpr int kNativeMpvPlaybackProfileVersion = 5;
constexpr const char *kSubtitleModeKey = "playback/subtitleMode";
constexpr const char *kSubtitleLangKey = "playback/subtitleLang";
constexpr const char *kSubtitleTitleKey = "playback/subtitleTitle";
constexpr const char *kEmailKey = "session/email";
constexpr const char *kNetworkTypeKey = "session/networkType";

QStringList nativeMpvContainers() {
    return {"mkv", "mp4", "m4v", "avi", "mov", "webm", "ts", "m2ts", "wmv"};
}

QStringList nativeMpvVideoCodecs() {
    return {"h264", "hevc", "h265", "mpeg4", "mpeg2video", "vp9", "av1", "vc1"};
}

QStringList nativeMpvAudioCodecs() {
    return {"aac", "ac3", "eac3", "mp3", "opus", "dts", "truehd", "flac", "vorbis"};
}

QString normalizePlaybackQualityMode(const QString &value) {
    const QString normalized = value.trimmed().toLower();
    if (normalized == "automatic" || normalized == "fixed") {
        return normalized;
    }
    return "original";
}

QString normalizeServerUrl(const QString &value) {
    QString normalized = value.trimmed();
    if (normalized.isEmpty()) {
        return normalized;
    }
    if (!normalized.startsWith("http://") && !normalized.startsWith("https://")) {
        normalized.prepend("http://");
    }
    QUrl url(normalized);
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

bool isSafeCredentialToken(const QString &value) {
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
}

SessionManager::SessionManager(QObject *parent)
    : SessionManager(createPlatformCredentialStore(), parent) {}

SessionManager::SessionManager(
    std::shared_ptr<CredentialStore> credentialStore,
    QObject *parent)
    : QObject(parent),
      m_credentialStore(std::move(credentialStore)),
      m_baseUrl(normalizeServerUrl(m_settings.value(kBaseUrlKey, "http://127.0.0.1:44301").toString())),
      m_registryUrl(m_settings.value(kRegistryUrlKey, m_baseUrl).toString()),
      m_controlPlaneEmail(m_settings.value(kControlPlaneEmailKey, "").toString()),
      m_controlPlaneToken(m_settings.value(kControlPlaneTokenKey, "").toString()),
      m_controlPlaneExpiresAt(m_settings.value(kControlPlaneExpiresAtKey, "").toString()),
      m_selectedServerId(m_settings.value(kSelectedServerIdKey, "").toString()),
      m_playbackQualityMode(normalizePlaybackQualityMode(m_settings.value(kPlaybackQualityModeKey, "original").toString())),
      m_playbackMaxResolution(m_settings.value(kPlaybackMaxResolutionKey, "unlimited").toString()),
      m_playbackMaxBitrateBps(m_settings.value(kPlaybackMaxBitrateKey, 0).toInt()),
      m_playbackSupportedContainers(m_settings.value(kPlaybackSupportedContainersKey, nativeMpvContainers()).toStringList()),
      m_playbackSupportedVideoCodecs(m_settings.value(kPlaybackSupportedVideoCodecsKey, nativeMpvVideoCodecs()).toStringList()),
      m_playbackSupportedAudioCodecs(m_settings.value(kPlaybackSupportedAudioCodecsKey, nativeMpvAudioCodecs()).toStringList()),
      m_subtitleMode(m_settings.value(kSubtitleModeKey, "default").toString()),
      m_subtitleLang(m_settings.value(kSubtitleLangKey, "").toString()),
      m_subtitleTitle(m_settings.value(kSubtitleTitleKey, "").toString()),
      m_email(m_settings.value(kEmailKey, "").toString()),
      m_networkType(m_settings.value(kNetworkTypeKey, "auto").toString()) {
    if (!m_credentialStore) {
        m_credentialStore = createPlatformCredentialStore();
    }
    migrateLegacySessionState();
    loadScopedSessionState();
    loadRefreshTokenForCurrentServer();

    const int profileVersion = m_settings.value(kPlaybackProfileVersionKey, 0).toInt();
    if (profileVersion < 2) {
        m_playbackMaxResolution = "unlimited";
        m_playbackMaxBitrateBps = 0;
        m_playbackSupportedContainers = nativeMpvContainers();
        m_playbackSupportedVideoCodecs = nativeMpvVideoCodecs();
        m_playbackSupportedAudioCodecs = nativeMpvAudioCodecs();
        storeValue(kPlaybackMaxResolutionKey, m_playbackMaxResolution);
        storeValue(kPlaybackMaxBitrateKey, m_playbackMaxBitrateBps);
        storeValue(kPlaybackSupportedContainersKey, m_playbackSupportedContainers);
        storeValue(kPlaybackSupportedVideoCodecsKey, m_playbackSupportedVideoCodecs);
        storeValue(kPlaybackSupportedAudioCodecsKey, m_playbackSupportedAudioCodecs);
    }
    if (profileVersion < 3) {
        m_playbackQualityMode = normalizePlaybackQualityMode(m_playbackQualityMode);
        storeValue(kPlaybackQualityModeKey, m_playbackQualityMode);
    }
    if (profileVersion < kNativeMpvPlaybackProfileVersion) {
        storeValue(kPlaybackProfileVersionKey, kNativeMpvPlaybackProfileVersion);
    }
}

QString SessionManager::baseUrl() const {
    return m_baseUrl;
}

void SessionManager::setBaseUrl(const QString &value) {
    setBaseUrlInternal(value, true);
}

void SessionManager::setBaseUrlRuntimeOverride(const QString &value) {
    setBaseUrlInternal(value, false);
}

void SessionManager::setBaseUrlInternal(const QString &value, bool persist) {
    const QString normalized = normalizeServerUrl(value);
    if (m_baseUrl == normalized) {
        return;
    }
    clearRuntimeSession(persist);
    setRefreshTokenInMemory(QString());
    m_baseUrl = normalized;
    if (persist) {
        storeValue(kBaseUrlKey, m_baseUrl);
    }
    emit baseUrlChanged();
    if (persist) {
        clearRuntimeSession(true);
        loadRefreshTokenForCurrentServer();
    }
}

QString SessionManager::registryUrl() const {
    return m_registryUrl;
}

void SessionManager::setRegistryUrl(const QString &value) {
    setRegistryUrlInternal(value, true);
}

void SessionManager::setRegistryUrlRuntimeOverride(const QString &value) {
    setRegistryUrlInternal(value, false);
}

void SessionManager::setRegistryUrlInternal(const QString &value, bool persist) {
    if (m_registryUrl == value) {
        return;
    }
    m_registryUrl = value;
    if (persist) {
        storeValue(kRegistryUrlKey, m_registryUrl);
    }
    emit registryUrlChanged();
}

QString SessionManager::authToken() const {
    return m_authToken;
}

void SessionManager::setAuthToken(const QString &value) {
    setAuthTokenInternal(value, true);
}

void SessionManager::setAuthTokenRuntimeOverride(const QString &value) {
    setAuthTokenInternal(value, false);
}

void SessionManager::setAuthTokenInternal(const QString &value, bool persist) {
    const QString accepted = value.isEmpty() || isSafeCredentialToken(value) ? value : QString();
    if (m_authToken == accepted) {
        return;
    }
    m_authToken = accepted;
    if (persist) {
        storeAuthValue("accessToken", m_authToken);
    }
    emit authTokenChanged();
}

QString SessionManager::accessTokenExpiresAt() const {
    return m_accessTokenExpiresAt;
}

void SessionManager::setAccessTokenExpiresAt(const QString &value) {
    setAccessTokenExpiresAtInternal(value, true);
}

void SessionManager::setAccessTokenExpiresAtRuntimeOverride(const QString &value) {
    setAccessTokenExpiresAtInternal(value, false);
}

void SessionManager::setAccessTokenExpiresAtInternal(const QString &value, bool persist) {
    if (m_accessTokenExpiresAt == value) {
        return;
    }
    m_accessTokenExpiresAt = value;
    if (persist) {
        storeAuthValue("accessTokenExpiresAt", m_accessTokenExpiresAt);
    }
    emit accessTokenExpiresAtChanged();
}

QString SessionManager::refreshToken() const {
    return m_refreshToken;
}

void SessionManager::setRefreshToken(const QString &value) {
    const QString accepted = value.isEmpty() || isSafeCredentialToken(value) ? value : QString();
    if (m_refreshToken == accepted) {
        return;
    }
    setRefreshTokenInMemory(accepted);
    if (m_baseUrl.isEmpty() || !m_credentialStore) {
        if (!accepted.isEmpty()) {
            emit credentialStorageError(QStringLiteral("Cannot persist a refresh token without secure server storage."));
        }
        return;
    }

    QString error;
    const QString account = credentialAccountForServer(m_baseUrl);
    const CredentialStoreStatus status = accepted.isEmpty()
        ? m_credentialStore->remove(kRefreshTokenService, account, &error)
        : m_credentialStore->write(kRefreshTokenService, account, accepted, &error);
    if (status != CredentialStoreStatus::Success
        && status != CredentialStoreStatus::NotFound) {
        emit credentialStorageError(
            error.isEmpty()
                ? QStringLiteral("Secure refresh-token storage failed.")
                : error);
    }
}

bool SessionManager::hasRefreshToken() const {
    return !m_refreshToken.isEmpty();
}

bool SessionManager::secureCredentialStorage() const {
    return m_credentialStore && m_credentialStore->isSecure();
}

QString SessionManager::sessionId() const {
    return m_sessionId;
}

void SessionManager::setSessionId(const QString &value) {
    if (m_sessionId == value) {
        return;
    }
    m_sessionId = value;
    storeAuthValue("sessionId", value);
    emit sessionIdChanged();
    emit sessionStateChanged();
}

QString SessionManager::homeId() const {
    return m_homeId;
}

void SessionManager::setHomeId(const QString &value) {
    if (m_homeId == value) {
        return;
    }
    m_homeId = value;
    storeAuthValue("homeId", value);
    emit homeIdChanged();
    emit sessionStateChanged();
}

QString SessionManager::activeProfileId() const {
    return m_activeProfileId;
}

void SessionManager::setActiveProfileId(const QString &value) {
    if (m_activeProfileId == value) {
        return;
    }
    m_activeProfileId = value;
    storeAuthValue("activeProfileId", value);
    emit activeProfileIdChanged();
    emit sessionStateChanged();
}

QString SessionManager::activeProfileName() const {
    return m_activeProfileName;
}

void SessionManager::setActiveProfileName(const QString &value) {
    if (m_activeProfileName == value) {
        return;
    }
    m_activeProfileName = value;
    storeAuthValue("activeProfileName", value);
    emit activeProfileNameChanged();
    emit sessionStateChanged();
}

QString SessionManager::activeProfileType() const {
    return m_activeProfileType;
}

void SessionManager::setActiveProfileType(const QString &value) {
    if (m_activeProfileType == value) {
        return;
    }
    m_activeProfileType = value;
    storeAuthValue("activeProfileType", value);
    emit activeProfileTypeChanged();
    emit sessionStateChanged();
}

QString SessionManager::homeRole() const {
    return m_homeRole;
}

void SessionManager::setHomeRole(const QString &value) {
    if (m_homeRole == value) {
        return;
    }
    m_homeRole = value;
    storeAuthValue("homeRole", value);
    emit homeRoleChanged();
    emit sessionStateChanged();
}

QStringList SessionManager::capabilities() const {
    return m_capabilities;
}

void SessionManager::setCapabilities(const QStringList &value) {
    if (m_capabilities == value) {
        return;
    }
    m_capabilities = value;
    storeAuthValue("capabilities", value);
    emit capabilitiesChanged();
    emit sessionStateChanged();
}

qint64 SessionManager::capabilityRevision() const {
    return m_capabilityRevision;
}

void SessionManager::setCapabilityRevision(qint64 value) {
    if (m_capabilityRevision == value) {
        return;
    }
    m_capabilityRevision = value;
    storeAuthValue("capabilityRevision", value);
    emit capabilityRevisionChanged();
    emit sessionStateChanged();
}

QVariantMap SessionManager::sessionState() const {
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

void SessionManager::setSessionState(const QVariantMap &state) {
    setSessionId(state.value("session_id").toString());
    setHomeId(state.value("home_id").toString());
    setActiveProfileId(state.value("active_profile_id").toString());
    setActiveProfileName(state.value("active_profile_name").toString());
    setActiveProfileType(state.value("active_profile_type").toString());
    setHomeRole(state.value("role").toString());
    setCapabilities(state.value("capabilities").toStringList());
    setCapabilityRevision(state.value("capability_revision").toLongLong());
}

QString SessionManager::controlPlaneEmail() const {
    return m_controlPlaneEmail;
}

void SessionManager::setControlPlaneEmail(const QString &value) {
    if (m_controlPlaneEmail == value) {
        return;
    }
    m_controlPlaneEmail = value;
    storeValue(kControlPlaneEmailKey, m_controlPlaneEmail);
    emit controlPlaneEmailChanged();
}

QString SessionManager::controlPlaneToken() const {
    return m_controlPlaneToken;
}

void SessionManager::setControlPlaneToken(const QString &value) {
    if (m_controlPlaneToken == value) {
        return;
    }
    m_controlPlaneToken = value;
    storeValue(kControlPlaneTokenKey, m_controlPlaneToken);
    emit controlPlaneTokenChanged();
}

QString SessionManager::controlPlaneExpiresAt() const {
    return m_controlPlaneExpiresAt;
}

void SessionManager::setControlPlaneExpiresAt(const QString &value) {
    if (m_controlPlaneExpiresAt == value) {
        return;
    }
    m_controlPlaneExpiresAt = value;
    storeValue(kControlPlaneExpiresAtKey, m_controlPlaneExpiresAt);
    emit controlPlaneExpiresAtChanged();
}

QString SessionManager::selectedServerId() const {
    return m_selectedServerId;
}

void SessionManager::setSelectedServerId(const QString &value) {
    if (m_selectedServerId == value) {
        return;
    }
    m_selectedServerId = value;
    storeValue(kSelectedServerIdKey, m_selectedServerId);
    emit selectedServerIdChanged();
}

QString SessionManager::playbackQualityMode() const {
    return m_playbackQualityMode;
}

void SessionManager::setPlaybackQualityMode(const QString &value) {
    const QString normalized = normalizePlaybackQualityMode(value);
    if (m_playbackQualityMode == normalized) {
        return;
    }
    m_playbackQualityMode = normalized;
    storeValue(kPlaybackQualityModeKey, m_playbackQualityMode);
    emit playbackQualityModeChanged();
}

QString SessionManager::playbackMaxResolution() const {
    return m_playbackMaxResolution;
}

void SessionManager::setPlaybackMaxResolution(const QString &value) {
    if (m_playbackMaxResolution == value) {
        return;
    }
    m_playbackMaxResolution = value;
    storeValue(kPlaybackMaxResolutionKey, m_playbackMaxResolution);
    emit playbackMaxResolutionChanged();
}

int SessionManager::playbackMaxBitrateBps() const {
    return m_playbackMaxBitrateBps;
}

void SessionManager::setPlaybackMaxBitrateBps(int value) {
    if (m_playbackMaxBitrateBps == value) {
        return;
    }
    m_playbackMaxBitrateBps = value;
    storeValue(kPlaybackMaxBitrateKey, m_playbackMaxBitrateBps);
    emit playbackMaxBitrateBpsChanged();
}

QStringList SessionManager::playbackSupportedContainers() const {
    return m_playbackSupportedContainers;
}

void SessionManager::setPlaybackSupportedContainers(const QStringList &value) {
    if (m_playbackSupportedContainers == value) {
        return;
    }
    m_playbackSupportedContainers = value;
    storeValue(kPlaybackSupportedContainersKey, m_playbackSupportedContainers);
    emit playbackSupportedContainersChanged();
}

QStringList SessionManager::playbackSupportedVideoCodecs() const {
    return m_playbackSupportedVideoCodecs;
}

void SessionManager::setPlaybackSupportedVideoCodecs(const QStringList &value) {
    if (m_playbackSupportedVideoCodecs == value) {
        return;
    }
    m_playbackSupportedVideoCodecs = value;
    storeValue(kPlaybackSupportedVideoCodecsKey, m_playbackSupportedVideoCodecs);
    emit playbackSupportedVideoCodecsChanged();
}

QStringList SessionManager::playbackSupportedAudioCodecs() const {
    return m_playbackSupportedAudioCodecs;
}

void SessionManager::setPlaybackSupportedAudioCodecs(const QStringList &value) {
    if (m_playbackSupportedAudioCodecs == value) {
        return;
    }
    m_playbackSupportedAudioCodecs = value;
    storeValue(kPlaybackSupportedAudioCodecsKey, m_playbackSupportedAudioCodecs);
    emit playbackSupportedAudioCodecsChanged();
}

QString SessionManager::subtitleMode() const {
    return m_subtitleMode;
}

void SessionManager::setSubtitleMode(const QString &value) {
    if (m_subtitleMode == value) {
        return;
    }
    m_subtitleMode = value;
    storeValue(kSubtitleModeKey, m_subtitleMode);
    emit subtitleModeChanged();
}

QString SessionManager::subtitleLang() const {
    return m_subtitleLang;
}

void SessionManager::setSubtitleLang(const QString &value) {
    if (m_subtitleLang == value) {
        return;
    }
    m_subtitleLang = value;
    storeValue(kSubtitleLangKey, m_subtitleLang);
    emit subtitleLangChanged();
}

QString SessionManager::subtitleTitle() const {
    return m_subtitleTitle;
}

void SessionManager::setSubtitleTitle(const QString &value) {
    if (m_subtitleTitle == value) {
        return;
    }
    m_subtitleTitle = value;
    storeValue(kSubtitleTitleKey, m_subtitleTitle);
    emit subtitleTitleChanged();
}

QString SessionManager::email() const {
    return m_email;
}

void SessionManager::setEmail(const QString &value) {
    if (m_email == value) {
        return;
    }
    m_email = value;
    storeValue(kEmailKey, m_email);
    emit emailChanged();
}

QString SessionManager::networkType() const {
    return m_networkType;
}

void SessionManager::setNetworkType(const QString &value) {
    setNetworkTypeInternal(value, true);
}

void SessionManager::setNetworkTypeRuntimeOverride(const QString &value) {
    setNetworkTypeInternal(value, false);
}

void SessionManager::setNetworkTypeInternal(const QString &value, bool persist) {
    if (m_networkType == value) {
        return;
    }
    m_networkType = value;
    if (persist) {
        storeValue(kNetworkTypeKey, m_networkType);
    }
    emit networkTypeChanged();
}

void SessionManager::clearAuth() {
    setRefreshToken(QString());
    clearRuntimeSession(true);
}

void SessionManager::clearControlPlaneAuth() {
    setControlPlaneToken(QString());
    setControlPlaneExpiresAt(QString());
}

void SessionManager::storeValue(const QString &key, const QVariant &value) {
    m_settings.setValue(key, value);
    m_settings.sync();
}

void SessionManager::setRefreshTokenInMemory(const QString &value) {
    if (m_refreshToken == value) {
        return;
    }
    m_refreshToken = value;
    emit refreshTokenChanged();
}

void SessionManager::loadRefreshTokenForCurrentServer() {
    if (m_baseUrl.isEmpty() || !m_credentialStore) {
        setRefreshTokenInMemory(QString());
        return;
    }
    const CredentialReadResult result = m_credentialStore->read(
        kRefreshTokenService,
        credentialAccountForServer(m_baseUrl));
    if (result.status == CredentialStoreStatus::Success) {
        if (isSafeCredentialToken(result.value)) {
            setRefreshTokenInMemory(result.value);
            return;
        }
        QString removalError;
        m_credentialStore->remove(
            kRefreshTokenService,
            credentialAccountForServer(m_baseUrl),
            &removalError);
        setRefreshTokenInMemory(QString());
        emit credentialStorageError(QStringLiteral("Stored refresh credential was invalid and was removed."));
        return;
    }
    setRefreshTokenInMemory(QString());
    if (result.status != CredentialStoreStatus::NotFound && !result.error.isEmpty()) {
        emit credentialStorageError(result.error);
    }
}

void SessionManager::clearRuntimeSession(bool persist) {
    if (persist && m_authToken.isEmpty()) {
        storeAuthValue("accessToken", QString());
    }
    if (persist && m_accessTokenExpiresAt.isEmpty()) {
        storeAuthValue("accessTokenExpiresAt", QString());
    }
    setAuthTokenInternal(QString(), persist);
    setAccessTokenExpiresAtInternal(QString(), persist);
    clearSessionMetadata(persist);
}

void SessionManager::clearSessionMetadata(bool persist) {
    const auto clearString = [this, persist](
                                 QString &field,
                                 const QString &key,
                                 void (SessionManager::*signal)()) {
        if (field.isEmpty()) {
            if (persist) {
                storeAuthValue(key, QString());
            }
            return;
        }
        field.clear();
        if (persist) {
            storeAuthValue(key, QString());
        }
        emit (this->*signal)();
    };
    clearString(m_sessionId, "sessionId", &SessionManager::sessionIdChanged);
    clearString(m_homeId, "homeId", &SessionManager::homeIdChanged);
    clearString(m_activeProfileId, "activeProfileId", &SessionManager::activeProfileIdChanged);
    clearString(m_activeProfileName, "activeProfileName", &SessionManager::activeProfileNameChanged);
    clearString(m_activeProfileType, "activeProfileType", &SessionManager::activeProfileTypeChanged);
    clearString(m_homeRole, "homeRole", &SessionManager::homeRoleChanged);
    if (!m_capabilities.isEmpty()) {
        m_capabilities.clear();
        if (persist) {
            storeAuthValue("capabilities", QStringList());
        }
        emit capabilitiesChanged();
    } else if (persist) {
        storeAuthValue("capabilities", QStringList());
    }
    if (m_capabilityRevision != 0) {
        m_capabilityRevision = 0;
        if (persist) {
            storeAuthValue("capabilityRevision", 0);
        }
        emit capabilityRevisionChanged();
    } else if (persist) {
        storeAuthValue("capabilityRevision", 0);
    }
    emit sessionStateChanged();
}

void SessionManager::loadScopedSessionState() {
    m_authToken = m_settings.value(authSettingKey("accessToken"), "").toString();
    if (!m_authToken.isEmpty() && !isSafeCredentialToken(m_authToken)) {
        m_authToken.clear();
        storeAuthValue("accessToken", QString());
    }
    m_accessTokenExpiresAt =
        m_settings.value(authSettingKey("accessTokenExpiresAt"), "").toString();
    m_sessionId = m_settings.value(authSettingKey("sessionId"), "").toString();
    m_homeId = m_settings.value(authSettingKey("homeId"), "").toString();
    m_activeProfileId = m_settings.value(authSettingKey("activeProfileId"), "").toString();
    m_activeProfileName = m_settings.value(authSettingKey("activeProfileName"), "").toString();
    m_activeProfileType = m_settings.value(authSettingKey("activeProfileType"), "").toString();
    m_homeRole = m_settings.value(authSettingKey("homeRole"), "").toString();
    m_capabilities = m_settings.value(authSettingKey("capabilities")).toStringList();
    m_capabilityRevision = m_settings.value(authSettingKey("capabilityRevision"), 0).toLongLong();
}

void SessionManager::migrateLegacySessionState() {
    const QString scopedTokenKey = authSettingKey("accessToken");
    if (!m_settings.contains(scopedTokenKey) && m_settings.contains(kAuthTokenKey)) {
        m_settings.setValue(scopedTokenKey, m_settings.value(kAuthTokenKey));
    }
    const QString scopedExpiryKey = authSettingKey("accessTokenExpiresAt");
    if (!m_settings.contains(scopedExpiryKey) && m_settings.contains(kAccessTokenExpiresAtKey)) {
        m_settings.setValue(scopedExpiryKey, m_settings.value(kAccessTokenExpiresAtKey));
    }
    m_settings.remove(kAuthTokenKey);
    m_settings.remove(kAccessTokenExpiresAtKey);
    m_settings.sync();
}

QString SessionManager::authSettingKey(const QString &name) const {
    return QStringLiteral("session/accounts/%1/%2")
        .arg(credentialAccountForServer(m_baseUrl), name);
}

void SessionManager::storeAuthValue(const QString &name, const QVariant &value) {
    if (m_baseUrl.isEmpty()) {
        return;
    }
    storeValue(authSettingKey(name), value);
}
