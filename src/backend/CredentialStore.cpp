#include "backend/CredentialStore.h"

#include <QByteArray>
#include <QCryptographicHash>
#include <QSettings>
#include <QUrl>

#ifdef Q_OS_MACOS
#include <Security/Security.h>
#endif

namespace {
QString canonicalServer(const QString &value) {
    QUrl url(value.trimmed());
    if (!url.isValid() || url.scheme().isEmpty() || url.host().isEmpty()) {
        return value.trimmed();
    }
    url.setScheme(url.scheme().toLower());
    url.setHost(url.host().toLower());
    url.setUserInfo(QString());
    url.setQuery(QString());
    url.setFragment(QString());
    QString path = url.path();
    while (path.endsWith('/') && path.size() > 1) {
        path.chop(1);
    }
    if (path == "/") {
        path.clear();
    }
    url.setPath(path);
    return url.toString(QUrl::FullyEncoded);
}

class UnavailableCredentialStore final : public CredentialStore {
public:
    CredentialReadResult read(const QString &, const QString &) override {
        return {
            CredentialStoreStatus::Unavailable,
            QString(),
            QStringLiteral("Secure credential storage is unavailable on this platform."),
        };
    }

    CredentialStoreStatus write(
        const QString &,
        const QString &,
        const QString &,
        QString *error) override {
        if (error) {
            *error = QStringLiteral("Secure credential storage is unavailable on this platform.");
        }
        return CredentialStoreStatus::Unavailable;
    }

    CredentialStoreStatus remove(
        const QString &,
        const QString &,
        QString *error) override {
        if (error) {
            error->clear();
        }
        return CredentialStoreStatus::NotFound;
    }

    bool isSecure() const override {
        return false;
    }
};

#ifdef Q_OS_MACOS
QString keychainError(OSStatus status) {
    CFStringRef message = SecCopyErrorMessageString(status, nullptr);
    if (!message) {
        return QStringLiteral("macOS Keychain operation failed (%1).").arg(status);
    }
    const QString result = QString::fromCFString(message);
    CFRelease(message);
    return result;
}

CredentialStoreStatus keychainStatus(OSStatus status) {
    return status == errSecNotAvailable
        ? CredentialStoreStatus::Unavailable
        : CredentialStoreStatus::Error;
}

CFMutableDictionaryRef keychainQuery(const QString &service, const QString &account) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        kCFAllocatorDefault,
        0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CFStringRef serviceValue = service.toCFString();
    CFStringRef accountValue = account.toCFString();
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, serviceValue);
    CFDictionarySetValue(query, kSecAttrAccount, accountValue);
    CFRelease(serviceValue);
    CFRelease(accountValue);
    return query;
}

CFDataRef utf8Data(const QString &value) {
    const QByteArray bytes = value.toUtf8();
    return CFDataCreate(
        kCFAllocatorDefault,
        reinterpret_cast<const UInt8 *>(bytes.constData()),
        bytes.size());
}

class MacKeychainCredentialStore final : public CredentialStore {
public:
    CredentialReadResult read(const QString &service, const QString &account) override {
        CFMutableDictionaryRef query = keychainQuery(service, account);
        CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
        CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne);
        CFTypeRef result = nullptr;
        const OSStatus status = SecItemCopyMatching(query, &result);
        CFRelease(query);
        if (status == errSecItemNotFound) {
            return {CredentialStoreStatus::NotFound, QString(), QString()};
        }
        if (status != errSecSuccess) {
            return {keychainStatus(status), QString(), keychainError(status)};
        }
        if (!result || CFGetTypeID(result) != CFDataGetTypeID()) {
            if (result) {
                CFRelease(result);
            }
            return {
                CredentialStoreStatus::Error,
                QString(),
                QStringLiteral("macOS Keychain returned an invalid credential value."),
            };
        }
        CFDataRef data = static_cast<CFDataRef>(result);
        const QByteArray valueBytes(
            reinterpret_cast<const char *>(CFDataGetBytePtr(data)),
            static_cast<int>(CFDataGetLength(data)));
        CFRelease(result);
        return {CredentialStoreStatus::Success, QString::fromUtf8(valueBytes), QString()};
    }

    CredentialStoreStatus write(
        const QString &service,
        const QString &account,
        const QString &value,
        QString *error) override {
        CFMutableDictionaryRef query = keychainQuery(service, account);
        CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(
            kCFAllocatorDefault,
            0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
        CFDataRef valueData = utf8Data(value);
        CFDictionarySetValue(attributes, kSecValueData, valueData);
        CFDictionarySetValue(
            attributes,
            kSecAttrAccessible,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly);
        OSStatus status = SecItemUpdate(query, attributes);
        if (status == errSecItemNotFound) {
            CFDictionarySetValue(query, kSecValueData, valueData);
            CFDictionarySetValue(
                query,
                kSecAttrAccessible,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly);
            status = SecItemAdd(query, nullptr);
            if (status == errSecDuplicateItem) {
                CFDictionaryRemoveValue(query, kSecValueData);
                status = SecItemUpdate(query, attributes);
            }
        }
        CFRelease(valueData);
        CFRelease(attributes);
        CFRelease(query);
        if (status != errSecSuccess) {
            if (error) {
                *error = keychainError(status);
            }
            return keychainStatus(status);
        }
        if (error) {
            error->clear();
        }
        return CredentialStoreStatus::Success;
    }

    CredentialStoreStatus remove(
        const QString &service,
        const QString &account,
        QString *error) override {
        CFMutableDictionaryRef query = keychainQuery(service, account);
        const OSStatus status = SecItemDelete(query);
        CFRelease(query);
        if (status == errSecItemNotFound) {
            if (error) {
                error->clear();
            }
            return CredentialStoreStatus::NotFound;
        }
        if (status != errSecSuccess) {
            if (error) {
                *error = keychainError(status);
            }
            return keychainStatus(status);
        }
        if (error) {
            error->clear();
        }
        return CredentialStoreStatus::Success;
    }

    bool isSecure() const override {
        return true;
    }
};
#endif

#ifdef ELIXIR_ALLOW_INSECURE_CREDENTIAL_STORAGE
class DevelopmentSettingsCredentialStore final : public CredentialStore {
public:
    CredentialReadResult read(const QString &service, const QString &account) override {
        QSettings settings;
        const QString key = QStringLiteral("developmentCredentials/%1/%2").arg(service, account);
        if (!settings.contains(key)) {
            return {CredentialStoreStatus::NotFound, QString(), QString()};
        }
        return {CredentialStoreStatus::Success, settings.value(key).toString(), QString()};
    }

    CredentialStoreStatus write(
        const QString &service,
        const QString &account,
        const QString &value,
        QString *error) override {
        QSettings settings;
        settings.setValue(QStringLiteral("developmentCredentials/%1/%2").arg(service, account), value);
        settings.sync();
        if (error) {
            *error = settings.status() == QSettings::NoError
                ? QString()
                : QStringLiteral("Development credential storage write failed.");
        }
        return settings.status() == QSettings::NoError
            ? CredentialStoreStatus::Success
            : CredentialStoreStatus::Error;
    }

    CredentialStoreStatus remove(
        const QString &service,
        const QString &account,
        QString *error) override {
        QSettings settings;
        settings.remove(QStringLiteral("developmentCredentials/%1/%2").arg(service, account));
        settings.sync();
        if (error) {
            *error = settings.status() == QSettings::NoError
                ? QString()
                : QStringLiteral("Development credential storage removal failed.");
        }
        return settings.status() == QSettings::NoError
            ? CredentialStoreStatus::Success
            : CredentialStoreStatus::Error;
    }

    bool isSecure() const override {
        return false;
    }
};
#endif
} // namespace

std::shared_ptr<CredentialStore> createPlatformCredentialStore() {
#ifdef Q_OS_MACOS
    return std::make_shared<MacKeychainCredentialStore>();
#elif defined(ELIXIR_ALLOW_INSECURE_CREDENTIAL_STORAGE)
    return std::make_shared<DevelopmentSettingsCredentialStore>();
#else
    return std::make_shared<UnavailableCredentialStore>();
#endif
}

QString credentialAccountForServer(const QString &baseUrl) {
    const QByteArray digest = QCryptographicHash::hash(
        canonicalServer(baseUrl).toUtf8(),
        QCryptographicHash::Sha256);
    return QString::fromLatin1(digest.toHex());
}
