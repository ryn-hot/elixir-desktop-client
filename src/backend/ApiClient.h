#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QJsonObject>
#include <QUrl>
#include <QVariant>
#include <functional>

class QJsonDocument;

class ApiClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString authToken READ authToken WRITE setAuthToken NOTIFY authTokenChanged)
    Q_PROPERTY(QString accessTokenExpiresAt READ accessTokenExpiresAt WRITE setAccessTokenExpiresAt NOTIFY accessTokenExpiresAtChanged)
    Q_PROPERTY(QVariantMap clientCapabilities READ clientCapabilities WRITE setClientCapabilities NOTIFY clientCapabilitiesChanged)
    Q_PROPERTY(QString networkType READ networkType WRITE setNetworkType NOTIFY networkTypeChanged)

public:
    explicit ApiClient(QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &value);

    QString authToken() const;
    void setAuthToken(const QString &value);

    QString accessTokenExpiresAt() const;
    void setAccessTokenExpiresAt(const QString &value);

    QVariantMap clientCapabilities() const;
    void setClientCapabilities(const QVariantMap &value);

    QString networkType() const;
    void setNetworkType(const QString &value);

    Q_INVOKABLE void login(const QString &email, const QString &password);
    Q_INVOKABLE void signup(const QString &email, const QString &password);
    Q_INVOKABLE void startPasswordReset(const QString &email);
    Q_INVOKABLE void completePasswordReset(const QString &token, const QString &newPassword);
    Q_INVOKABLE void fetchLibrary();
    Q_INVOKABLE void fetchMediaDetails(const QString &mediaItemId);
    Q_INVOKABLE void startPlayback(const QString &mediaItemId, const QString &preferredFileId);
    Q_INVOKABLE void seekPlayback(const QString &sessionId, double seconds);
    Q_INVOKABLE void pollSession(const QString &sessionId);
    Q_INVOKABLE void endSession(const QString &sessionId);
    Q_INVOKABLE void runScan(bool forceMetadata);

signals:
    void baseUrlChanged();
    void authTokenChanged();
    void accessTokenExpiresAtChanged();
    void clientCapabilitiesChanged();
    void networkTypeChanged();

    void loginSucceeded();
    void loginFailed(const QString &error);
    void authExpired(const QString &message);
    void passwordResetStarted(const QString &token, const QString &expiresAt);
    void passwordResetCompleted();
    void passwordResetFailed(const QString &error);
    void libraryReceived(const QVariantList &items);
    void mediaDetailsReceived(const QVariantMap &details);
    void playbackStarted(const QVariantMap &info);
    void sessionPolled(const QVariantMap &info);
    void scanCompleted();
    void requestFailed(const QString &endpoint, const QString &error);

private:
    using SuccessHandler = std::function<void(const QJsonDocument &)>;
    using ErrorHandler = std::function<void(const QString &)>;

    QString normalizeBaseUrl(const QString &value) const;
    QUrl makeUrl(const QString &path) const;
    void sendRequest(
        const QString &method,
        const QString &path,
        const QJsonObject &body,
        const SuccessHandler &onSuccess,
        const ErrorHandler &onError = ErrorHandler());

    QNetworkAccessManager m_manager;
    QString m_baseUrl;
    QString m_authToken;
    QString m_accessTokenExpiresAt;
    QVariantMap m_clientCapabilities;
    QString m_networkType;
};
