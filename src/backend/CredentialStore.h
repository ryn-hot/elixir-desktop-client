#pragma once

#include <QString>
#include <memory>

enum class CredentialStoreStatus {
    Success,
    NotFound,
    Unavailable,
    Error,
};

struct CredentialReadResult {
    CredentialStoreStatus status = CredentialStoreStatus::Error;
    QString value;
    QString error;
};

class CredentialStore {
public:
    virtual ~CredentialStore() = default;

    virtual CredentialReadResult read(const QString &service, const QString &account) = 0;
    virtual CredentialStoreStatus write(
        const QString &service,
        const QString &account,
        const QString &value,
        QString *error) = 0;
    virtual CredentialStoreStatus remove(
        const QString &service,
        const QString &account,
        QString *error) = 0;
    virtual bool isSecure() const = 0;
};

std::shared_ptr<CredentialStore> createPlatformCredentialStore();
QString credentialAccountForServer(const QString &baseUrl);
