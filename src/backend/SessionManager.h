#pragma once

#include <QObject>
#include <QSettings>

class SessionManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString registryUrl READ registryUrl WRITE setRegistryUrl NOTIFY registryUrlChanged)
    Q_PROPERTY(QString authToken READ authToken WRITE setAuthToken NOTIFY authTokenChanged)
    Q_PROPERTY(QString accessTokenExpiresAt READ accessTokenExpiresAt WRITE setAccessTokenExpiresAt NOTIFY accessTokenExpiresAtChanged)
    Q_PROPERTY(QString controlPlaneEmail READ controlPlaneEmail WRITE setControlPlaneEmail NOTIFY controlPlaneEmailChanged)
    Q_PROPERTY(QString controlPlaneToken READ controlPlaneToken WRITE setControlPlaneToken NOTIFY controlPlaneTokenChanged)
    Q_PROPERTY(QString controlPlaneExpiresAt READ controlPlaneExpiresAt WRITE setControlPlaneExpiresAt NOTIFY controlPlaneExpiresAtChanged)
    Q_PROPERTY(QString selectedServerId READ selectedServerId WRITE setSelectedServerId NOTIFY selectedServerIdChanged)
    Q_PROPERTY(QString playbackMaxResolution READ playbackMaxResolution WRITE setPlaybackMaxResolution NOTIFY playbackMaxResolutionChanged)
    Q_PROPERTY(int playbackMaxBitrateBps READ playbackMaxBitrateBps WRITE setPlaybackMaxBitrateBps NOTIFY playbackMaxBitrateBpsChanged)
    Q_PROPERTY(QStringList playbackSupportedContainers READ playbackSupportedContainers WRITE setPlaybackSupportedContainers NOTIFY playbackSupportedContainersChanged)
    Q_PROPERTY(QStringList playbackSupportedVideoCodecs READ playbackSupportedVideoCodecs WRITE setPlaybackSupportedVideoCodecs NOTIFY playbackSupportedVideoCodecsChanged)
    Q_PROPERTY(QStringList playbackSupportedAudioCodecs READ playbackSupportedAudioCodecs WRITE setPlaybackSupportedAudioCodecs NOTIFY playbackSupportedAudioCodecsChanged)
    Q_PROPERTY(QString email READ email WRITE setEmail NOTIFY emailChanged)
    Q_PROPERTY(QString networkType READ networkType WRITE setNetworkType NOTIFY networkTypeChanged)

public:
    explicit SessionManager(QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &value);

    QString registryUrl() const;
    void setRegistryUrl(const QString &value);

    QString authToken() const;
    void setAuthToken(const QString &value);

    QString accessTokenExpiresAt() const;
    void setAccessTokenExpiresAt(const QString &value);

    QString controlPlaneEmail() const;
    void setControlPlaneEmail(const QString &value);

    QString controlPlaneToken() const;
    void setControlPlaneToken(const QString &value);

    QString controlPlaneExpiresAt() const;
    void setControlPlaneExpiresAt(const QString &value);

    QString selectedServerId() const;
    void setSelectedServerId(const QString &value);

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

    QString email() const;
    void setEmail(const QString &value);

    QString networkType() const;
    void setNetworkType(const QString &value);

    Q_INVOKABLE void clearAuth();
    Q_INVOKABLE void clearControlPlaneAuth();

signals:
    void baseUrlChanged();
    void registryUrlChanged();
    void authTokenChanged();
    void accessTokenExpiresAtChanged();
    void controlPlaneEmailChanged();
    void controlPlaneTokenChanged();
    void controlPlaneExpiresAtChanged();
    void selectedServerIdChanged();
    void playbackMaxResolutionChanged();
    void playbackMaxBitrateBpsChanged();
    void playbackSupportedContainersChanged();
    void playbackSupportedVideoCodecsChanged();
    void playbackSupportedAudioCodecsChanged();
    void emailChanged();
    void networkTypeChanged();

private:
    void storeValue(const QString &key, const QVariant &value);

    QSettings m_settings;
    QString m_baseUrl;
    QString m_registryUrl;
    QString m_authToken;
    QString m_accessTokenExpiresAt;
    QString m_controlPlaneEmail;
    QString m_controlPlaneToken;
    QString m_controlPlaneExpiresAt;
    QString m_selectedServerId;
    QString m_playbackMaxResolution;
    int m_playbackMaxBitrateBps = 0;
    QStringList m_playbackSupportedContainers;
    QStringList m_playbackSupportedVideoCodecs;
    QStringList m_playbackSupportedAudioCodecs;
    QString m_email;
    QString m_networkType;
};
