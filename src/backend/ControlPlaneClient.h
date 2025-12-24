#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QJsonObject>
#include <QUrl>
#include <functional>

class QJsonDocument;

class ControlPlaneClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString authToken READ authToken WRITE setAuthToken NOTIFY authTokenChanged)
    Q_PROPERTY(QString accessTokenExpiresAt READ accessTokenExpiresAt WRITE setAccessTokenExpiresAt NOTIFY accessTokenExpiresAtChanged)

public:
    explicit ControlPlaneClient(QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &value);

    QString authToken() const;
    void setAuthToken(const QString &value);

    QString accessTokenExpiresAt() const;
    void setAccessTokenExpiresAt(const QString &value);

    Q_INVOKABLE void login(const QString &email, const QString &password);
    Q_INVOKABLE void signup(const QString &email, const QString &password);

signals:
    void baseUrlChanged();
    void authTokenChanged();
    void accessTokenExpiresAtChanged();

    void loginSucceeded();
    void loginFailed(const QString &error);
    void authExpired(const QString &message);
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
};
