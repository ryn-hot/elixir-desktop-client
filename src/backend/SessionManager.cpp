#include "backend/SessionManager.h"

namespace {
constexpr const char *kBaseUrlKey = "session/baseUrl";
constexpr const char *kAuthTokenKey = "session/authToken";
constexpr const char *kEmailKey = "session/email";
constexpr const char *kNetworkTypeKey = "session/networkType";
}

SessionManager::SessionManager(QObject *parent)
    : QObject(parent),
      m_baseUrl(m_settings.value(kBaseUrlKey, "http://127.0.0.1:44301").toString()),
      m_authToken(m_settings.value(kAuthTokenKey, "").toString()),
      m_email(m_settings.value(kEmailKey, "").toString()),
      m_networkType(m_settings.value(kNetworkTypeKey, "auto").toString()) {}

QString SessionManager::baseUrl() const {
    return m_baseUrl;
}

void SessionManager::setBaseUrl(const QString &value) {
    if (m_baseUrl == value) {
        return;
    }
    m_baseUrl = value;
    storeValue(kBaseUrlKey, m_baseUrl);
    emit baseUrlChanged();
}

QString SessionManager::authToken() const {
    return m_authToken;
}

void SessionManager::setAuthToken(const QString &value) {
    if (m_authToken == value) {
        return;
    }
    m_authToken = value;
    storeValue(kAuthTokenKey, m_authToken);
    emit authTokenChanged();
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
    if (m_networkType == value) {
        return;
    }
    m_networkType = value;
    storeValue(kNetworkTypeKey, m_networkType);
    emit networkTypeChanged();
}

void SessionManager::clearAuth() {
    setAuthToken(QString());
}

void SessionManager::storeValue(const QString &key, const QVariant &value) {
    m_settings.setValue(key, value);
    m_settings.sync();
}
