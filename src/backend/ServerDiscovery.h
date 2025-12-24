#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QHash>

#include "backend/ServerListModel.h"

#ifdef Q_OS_MAC
#include <dns_sd.h>
#endif

class QNetworkReply;
class QTimer;
class QSocketNotifier;

class ServerDiscovery : public QObject {
    Q_OBJECT
    Q_PROPERTY(ServerListModel* mdnsModel READ mdnsModel CONSTANT)
    Q_PROPERTY(ServerListModel* registryModel READ registryModel CONSTANT)
    Q_PROPERTY(QString registryBaseUrl READ registryBaseUrl WRITE setRegistryBaseUrl NOTIFY registryBaseUrlChanged)
    Q_PROPERTY(QString authToken READ authToken WRITE setAuthToken NOTIFY authTokenChanged)
    Q_PROPERTY(QString preferredNetworkType READ preferredNetworkType WRITE setPreferredNetworkType NOTIFY preferredNetworkTypeChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(bool browsing READ browsing NOTIFY browsingChanged)

public:
    explicit ServerDiscovery(QObject *parent = nullptr);
    ~ServerDiscovery() override;

    ServerListModel *mdnsModel();
    ServerListModel *registryModel();

    QString registryBaseUrl() const;
    void setRegistryBaseUrl(const QString &value);

    QString authToken() const;
    void setAuthToken(const QString &value);

    QString preferredNetworkType() const;
    void setPreferredNetworkType(const QString &value);

    QString statusMessage() const;
    bool browsing() const;

    Q_INVOKABLE void refreshMdns();
    Q_INVOKABLE void refreshRegistry();
    Q_INVOKABLE void probeAll();

signals:
    void registryBaseUrlChanged();
    void authTokenChanged();
    void preferredNetworkTypeChanged();
    void statusMessageChanged();
    void browsingChanged();

private:
    struct PendingProbe {
        QString entryKey;
        QString endpointType;
        QString endpoint;
        QNetworkReply *reply = nullptr;
        QTimer *timer = nullptr;
    };

    void setStatusMessage(const QString &value);
    QString normalizeEndpoint(const QString &value) const;
    void probeEntry(const ServerEntry &entry);
    void probeEndpoint(const QString &entryKey, const QString &endpointType, const QString &endpoint);
    void handleProbeFinished(QNetworkReply *reply, bool forcedFailure);

    ServerListModel m_mdnsModel;
    ServerListModel m_registryModel;
    QNetworkAccessManager m_manager;
    QString m_registryBaseUrl;
    QString m_authToken;
    QString m_preferredNetworkType = "auto";
    QString m_statusMessage;
    bool m_browsing = false;
    QHash<QNetworkReply*, PendingProbe> m_probes;

#ifdef Q_OS_MAC
    struct ResolveContext {
        QString key;
        QString serviceName;
        QString regType;
        QString domain;
        uint32_t interfaceIndex = 0;
    };

    void startMdnsBrowse();
    void stopMdnsBrowse();
    void processBrowseResult();
    void processResolveResult(DNSServiceRef ref);
    QString makeMdnsKey(const QString &serviceName, const QString &regType, const QString &domain) const;

    static void onBrowse(
        DNSServiceRef ref,
        DNSServiceFlags flags,
        uint32_t interfaceIndex,
        DNSServiceErrorType errorCode,
        const char *serviceName,
        const char *regType,
        const char *domain,
        void *context);

    static void onResolve(
        DNSServiceRef ref,
        DNSServiceFlags flags,
        uint32_t interfaceIndex,
        DNSServiceErrorType errorCode,
        const char *fullName,
        const char *hostTarget,
        uint16_t port,
        uint16_t txtLen,
        const unsigned char *txtRecord,
        void *context);

    DNSServiceRef m_browseRef = nullptr;
    QSocketNotifier *m_browseNotifier = nullptr;
    QHash<DNSServiceRef, QSocketNotifier*> m_resolveNotifiers;
    QHash<DNSServiceRef, ResolveContext> m_resolveContexts;
#endif
};
