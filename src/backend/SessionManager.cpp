#include "backend/SessionManager.h"

namespace {
constexpr const char *kBaseUrlKey = "session/baseUrl";
constexpr const char *kRegistryUrlKey = "session/registryUrl";
constexpr const char *kAuthTokenKey = "session/authToken";
constexpr const char *kAccessTokenExpiresAtKey = "session/accessTokenExpiresAt";
constexpr const char *kControlPlaneEmailKey = "session/controlPlaneEmail";
constexpr const char *kControlPlaneTokenKey = "session/controlPlaneToken";
constexpr const char *kControlPlaneExpiresAtKey = "session/controlPlaneExpiresAt";
constexpr const char *kSelectedServerIdKey = "session/selectedServerId";
constexpr const char *kEmailKey = "session/email";
constexpr const char *kNetworkTypeKey = "session/networkType";
}

SessionManager::SessionManager(QObject *parent)
    : QObject(parent),
      m_baseUrl(m_settings.value(kBaseUrlKey, "http://127.0.0.1:44301").toString()),
      m_registryUrl(m_settings.value(kRegistryUrlKey, m_baseUrl).toString()),
      m_authToken(m_settings.value(kAuthTokenKey, "").toString()),
      m_accessTokenExpiresAt(m_settings.value(kAccessTokenExpiresAtKey, "").toString()),
      m_controlPlaneEmail(m_settings.value(kControlPlaneEmailKey, "").toString()),
      m_controlPlaneToken(m_settings.value(kControlPlaneTokenKey, "").toString()),
      m_controlPlaneExpiresAt(m_settings.value(kControlPlaneExpiresAtKey, "").toString()),
      m_selectedServerId(m_settings.value(kSelectedServerIdKey, "").toString()),
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

QString SessionManager::registryUrl() const {
    return m_registryUrl;
}

void SessionManager::setRegistryUrl(const QString &value) {
    if (m_registryUrl == value) {
        return;
    }
    m_registryUrl = value;
    storeValue(kRegistryUrlKey, m_registryUrl);
    emit registryUrlChanged();
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

QString SessionManager::accessTokenExpiresAt() const {
    return m_accessTokenExpiresAt;
}

void SessionManager::setAccessTokenExpiresAt(const QString &value) {
    if (m_accessTokenExpiresAt == value) {
        return;
    }
    m_accessTokenExpiresAt = value;
    storeValue(kAccessTokenExpiresAtKey, m_accessTokenExpiresAt);
    emit accessTokenExpiresAtChanged();
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
    setAccessTokenExpiresAt(QString());
}

void SessionManager::clearControlPlaneAuth() {
    setControlPlaneToken(QString());
    setControlPlaneExpiresAt(QString());
}

void SessionManager::storeValue(const QString &key, const QVariant &value) {
    m_settings.setValue(key, value);
    m_settings.sync();
}
