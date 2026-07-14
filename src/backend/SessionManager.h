#pragma once

#include <QObject>
#include <QSettings>
#include <QVariantMap>
#include <memory>

class CredentialStore;

class SessionManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString registryUrl READ registryUrl WRITE setRegistryUrl NOTIFY registryUrlChanged)
    Q_PROPERTY(QString authToken READ authToken WRITE setAuthToken NOTIFY authTokenChanged)
    Q_PROPERTY(QString accessTokenExpiresAt READ accessTokenExpiresAt WRITE setAccessTokenExpiresAt NOTIFY accessTokenExpiresAtChanged)
    Q_PROPERTY(bool hasRefreshToken READ hasRefreshToken NOTIFY refreshTokenChanged)
    Q_PROPERTY(bool secureCredentialStorage READ secureCredentialStorage CONSTANT)
    Q_PROPERTY(QString sessionId READ sessionId WRITE setSessionId NOTIFY sessionIdChanged)
    Q_PROPERTY(QString homeId READ homeId WRITE setHomeId NOTIFY homeIdChanged)
    Q_PROPERTY(QString activeProfileId READ activeProfileId WRITE setActiveProfileId NOTIFY activeProfileIdChanged)
    Q_PROPERTY(QString activeProfileName READ activeProfileName WRITE setActiveProfileName NOTIFY activeProfileNameChanged)
    Q_PROPERTY(QString activeProfileType READ activeProfileType WRITE setActiveProfileType NOTIFY activeProfileTypeChanged)
    Q_PROPERTY(QString homeRole READ homeRole WRITE setHomeRole NOTIFY homeRoleChanged)
    Q_PROPERTY(QStringList capabilities READ capabilities WRITE setCapabilities NOTIFY capabilitiesChanged)
    Q_PROPERTY(qint64 capabilityRevision READ capabilityRevision WRITE setCapabilityRevision NOTIFY capabilityRevisionChanged)
    Q_PROPERTY(QString controlPlaneEmail READ controlPlaneEmail WRITE setControlPlaneEmail NOTIFY controlPlaneEmailChanged)
    Q_PROPERTY(QString controlPlaneToken READ controlPlaneToken WRITE setControlPlaneToken NOTIFY controlPlaneTokenChanged)
    Q_PROPERTY(QString controlPlaneExpiresAt READ controlPlaneExpiresAt WRITE setControlPlaneExpiresAt NOTIFY controlPlaneExpiresAtChanged)
    Q_PROPERTY(QString selectedServerId READ selectedServerId WRITE setSelectedServerId NOTIFY selectedServerIdChanged)
    Q_PROPERTY(QString playbackQualityMode READ playbackQualityMode WRITE setPlaybackQualityMode NOTIFY playbackQualityModeChanged)
    Q_PROPERTY(QString playbackMaxResolution READ playbackMaxResolution WRITE setPlaybackMaxResolution NOTIFY playbackMaxResolutionChanged)
    Q_PROPERTY(int playbackMaxBitrateBps READ playbackMaxBitrateBps WRITE setPlaybackMaxBitrateBps NOTIFY playbackMaxBitrateBpsChanged)
    Q_PROPERTY(QStringList playbackSupportedContainers READ playbackSupportedContainers WRITE setPlaybackSupportedContainers NOTIFY playbackSupportedContainersChanged)
    Q_PROPERTY(QStringList playbackSupportedVideoCodecs READ playbackSupportedVideoCodecs WRITE setPlaybackSupportedVideoCodecs NOTIFY playbackSupportedVideoCodecsChanged)
    Q_PROPERTY(QStringList playbackSupportedAudioCodecs READ playbackSupportedAudioCodecs WRITE setPlaybackSupportedAudioCodecs NOTIFY playbackSupportedAudioCodecsChanged)
    Q_PROPERTY(QString subtitleMode READ subtitleMode WRITE setSubtitleMode NOTIFY subtitleModeChanged)
    Q_PROPERTY(QString subtitleLang READ subtitleLang WRITE setSubtitleLang NOTIFY subtitleLangChanged)
    Q_PROPERTY(QString subtitleTitle READ subtitleTitle WRITE setSubtitleTitle NOTIFY subtitleTitleChanged)
    Q_PROPERTY(QString email READ email WRITE setEmail NOTIFY emailChanged)
    Q_PROPERTY(QString networkType READ networkType WRITE setNetworkType NOTIFY networkTypeChanged)

public:
    explicit SessionManager(QObject *parent = nullptr);
    explicit SessionManager(std::shared_ptr<CredentialStore> credentialStore, QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &value);
    void setBaseUrlRuntimeOverride(const QString &value);

    QString registryUrl() const;
    void setRegistryUrl(const QString &value);
    void setRegistryUrlRuntimeOverride(const QString &value);

    QString authToken() const;
    void setAuthToken(const QString &value);
    void setAuthTokenRuntimeOverride(const QString &value);

    QString accessTokenExpiresAt() const;
    void setAccessTokenExpiresAt(const QString &value);
    void setAccessTokenExpiresAtRuntimeOverride(const QString &value);

    QString refreshToken() const;
    void setRefreshToken(const QString &value);
    bool hasRefreshToken() const;
    bool secureCredentialStorage() const;

    QString sessionId() const;
    void setSessionId(const QString &value);
    QString homeId() const;
    void setHomeId(const QString &value);
    QString activeProfileId() const;
    void setActiveProfileId(const QString &value);
    QString activeProfileName() const;
    void setActiveProfileName(const QString &value);
    QString activeProfileType() const;
    void setActiveProfileType(const QString &value);
    QString homeRole() const;
    void setHomeRole(const QString &value);
    QStringList capabilities() const;
    void setCapabilities(const QStringList &value);
    qint64 capabilityRevision() const;
    void setCapabilityRevision(qint64 value);
    QVariantMap sessionState() const;
    void setSessionState(const QVariantMap &state);

    QString controlPlaneEmail() const;
    void setControlPlaneEmail(const QString &value);

    QString controlPlaneToken() const;
    void setControlPlaneToken(const QString &value);

    QString controlPlaneExpiresAt() const;
    void setControlPlaneExpiresAt(const QString &value);

    QString selectedServerId() const;
    void setSelectedServerId(const QString &value);

    QString playbackQualityMode() const;
    void setPlaybackQualityMode(const QString &value);

    QString playbackMaxResolution() const;
    void setPlaybackMaxResolution(const QString &value);

    int playbackMaxBitrateBps() const;
    void setPlaybackMaxBitrateBps(int value);

    QStringList playbackSupportedContainers() const;
    void setPlaybackSupportedContainers(const QStringList &value);

    QStringList playbackSupportedVideoCodecs() const;
    void setPlaybackSupportedVideoCodecs(const QStringList &value);

    QStringList playbackSupportedAudioCodecs() const;
    void setPlaybackSupportedAudioCodecs(const QStringList &value);

    QString subtitleMode() const;
    void setSubtitleMode(const QString &value);

    QString subtitleLang() const;
    void setSubtitleLang(const QString &value);

    QString subtitleTitle() const;
    void setSubtitleTitle(const QString &value);

    QString email() const;
    void setEmail(const QString &value);

    QString networkType() const;
    void setNetworkType(const QString &value);
    void setNetworkTypeRuntimeOverride(const QString &value);

    Q_INVOKABLE void clearAuth();
    Q_INVOKABLE void clearControlPlaneAuth();

signals:
    void baseUrlChanged();
    void registryUrlChanged();
    void authTokenChanged();
    void accessTokenExpiresAtChanged();
    void refreshTokenChanged();
    void credentialStorageError(const QString &message);
    void sessionIdChanged();
    void homeIdChanged();
    void activeProfileIdChanged();
    void activeProfileNameChanged();
    void activeProfileTypeChanged();
    void homeRoleChanged();
    void capabilitiesChanged();
    void capabilityRevisionChanged();
    void sessionStateChanged();
    void controlPlaneEmailChanged();
    void controlPlaneTokenChanged();
    void controlPlaneExpiresAtChanged();
    void selectedServerIdChanged();
    void playbackQualityModeChanged();
    void playbackMaxResolutionChanged();
    void playbackMaxBitrateBpsChanged();
    void playbackSupportedContainersChanged();
    void playbackSupportedVideoCodecsChanged();
    void playbackSupportedAudioCodecsChanged();
    void subtitleModeChanged();
    void subtitleLangChanged();
    void subtitleTitleChanged();
    void emailChanged();
    void networkTypeChanged();

private:
    void storeValue(const QString &key, const QVariant &value);
    void setBaseUrlInternal(const QString &value, bool persist);
    void setRegistryUrlInternal(const QString &value, bool persist);
    void setAuthTokenInternal(const QString &value, bool persist);
    void setAccessTokenExpiresAtInternal(const QString &value, bool persist);
    void setNetworkTypeInternal(const QString &value, bool persist);
    void setRefreshTokenInMemory(const QString &value);
    void loadRefreshTokenForCurrentServer();
    void clearRuntimeSession(bool persist);
    void clearSessionMetadata(bool persist);
    void loadScopedSessionState();
    void migrateLegacySessionState();
    QString authSettingKey(const QString &name) const;
    void storeAuthValue(const QString &name, const QVariant &value);

    QSettings m_settings;
    std::shared_ptr<CredentialStore> m_credentialStore;
    QString m_baseUrl;
    QString m_registryUrl;
    QString m_authToken;
    QString m_accessTokenExpiresAt;
    QString m_refreshToken;
    QString m_sessionId;
    QString m_homeId;
    QString m_activeProfileId;
    QString m_activeProfileName;
    QString m_activeProfileType;
    QString m_homeRole;
    QStringList m_capabilities;
    qint64 m_capabilityRevision = 0;
    QString m_controlPlaneEmail;
    QString m_controlPlaneToken;
    QString m_controlPlaneExpiresAt;
    QString m_selectedServerId;
    QString m_playbackQualityMode;
    QString m_playbackMaxResolution;
    int m_playbackMaxBitrateBps = 0;
    QStringList m_playbackSupportedContainers;
    QStringList m_playbackSupportedVideoCodecs;
    QStringList m_playbackSupportedAudioCodecs;
    QString m_subtitleMode;
    QString m_subtitleLang;
    QString m_subtitleTitle;
    QString m_email;
    QString m_networkType;
};
