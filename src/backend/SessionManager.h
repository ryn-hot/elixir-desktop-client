#pragma once

#include <QObject>
#include <QSettings>

class SessionManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString registryUrl READ registryUrl WRITE setRegistryUrl NOTIFY registryUrlChanged)
    Q_PROPERTY(QString authToken READ authToken WRITE setAuthToken NOTIFY authTokenChanged)
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

    QString email() const;
    void setEmail(const QString &value);

    QString networkType() const;
    void setNetworkType(const QString &value);

    Q_INVOKABLE void clearAuth();

signals:
    void baseUrlChanged();
    void registryUrlChanged();
    void authTokenChanged();
    void emailChanged();
    void networkTypeChanged();

private:
    void storeValue(const QString &key, const QVariant &value);

    QSettings m_settings;
    QString m_baseUrl;
    QString m_registryUrl;
    QString m_authToken;
    QString m_email;
    QString m_networkType;
};
