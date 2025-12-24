#include "backend/ServerDiscovery.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QTimer>
#include <QUrl>

#ifdef Q_OS_MAC
#include <QSocketNotifier>
#include <arpa/inet.h>
#endif

namespace {
constexpr int kProbeTimeoutMs = 1500;
constexpr const char *kServiceType = "_elixir-media._tcp";
} // namespace

ServerDiscovery::ServerDiscovery(QObject *parent)
    : QObject(parent) {
    m_mdnsModel.setPreferredNetworkType(m_preferredNetworkType);
    m_registryModel.setPreferredNetworkType(m_preferredNetworkType);
}

ServerDiscovery::~ServerDiscovery() {
#ifdef Q_OS_MAC
    stopMdnsBrowse();
#endif
}

ServerListModel *ServerDiscovery::mdnsModel() {
    return &m_mdnsModel;
}

ServerListModel *ServerDiscovery::registryModel() {
    return &m_registryModel;
}

QString ServerDiscovery::registryBaseUrl() const {
    return m_registryBaseUrl;
}

void ServerDiscovery::setRegistryBaseUrl(const QString &value) {
    const QString normalized = normalizeEndpoint(value);
    if (m_registryBaseUrl == normalized) {
        return;
    }
    m_registryBaseUrl = normalized;
    emit registryBaseUrlChanged();
}

QString ServerDiscovery::authToken() const {
    return m_authToken;
}

void ServerDiscovery::setAuthToken(const QString &value) {
    if (m_authToken == value) {
        return;
    }
    m_authToken = value;
    emit authTokenChanged();
}

QString ServerDiscovery::preferredNetworkType() const {
    return m_preferredNetworkType;
}

void ServerDiscovery::setPreferredNetworkType(const QString &value) {
    const QString normalized = value.trimmed().isEmpty() ? "auto" : value.trimmed();
    if (m_preferredNetworkType == normalized) {
        return;
    }
    m_preferredNetworkType = normalized;
    m_mdnsModel.setPreferredNetworkType(normalized);
    m_registryModel.setPreferredNetworkType(normalized);
    emit preferredNetworkTypeChanged();
}

QString ServerDiscovery::statusMessage() const {
    return m_statusMessage;
}

bool ServerDiscovery::browsing() const {
    return m_browsing;
}

void ServerDiscovery::refreshMdns() {
#ifdef Q_OS_MAC
    m_mdnsModel.clear();
    stopMdnsBrowse();
    startMdnsBrowse();
#else
    setStatusMessage("mDNS discovery is not available on this platform.");
#endif
}

void ServerDiscovery::refreshRegistry() {
    if (m_registryBaseUrl.trimmed().isEmpty()) {
        setStatusMessage("Registry base URL is not set.");
        return;
    }

    QUrl base(m_registryBaseUrl);
    QUrl url = base.resolved(QUrl("/api/v1/me/servers"));

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    if (!m_authToken.isEmpty()) {
        request.setRawHeader("Authorization", QByteArray("Bearer ") + m_authToken.toUtf8());
    }

    QNetworkReply *reply = m_manager.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray payload = reply->readAll();
        const bool okStatus = status >= 200 && status < 300;

        if (reply->error() != QNetworkReply::NoError || !okStatus) {
            const QString detail = payload.isEmpty()
                ? reply->errorString()
                : QString::fromUtf8(payload);
            setStatusMessage(QString("Registry fetch failed: %1").arg(detail));
            reply->deleteLater();
            return;
        }

        QJsonParseError parseError;
        const QJsonDocument doc = QJsonDocument::fromJson(payload, &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            setStatusMessage(QString("Registry JSON error: %1").arg(parseError.errorString()));
            reply->deleteLater();
            return;
        }

        if (!doc.isArray()) {
            setStatusMessage("Registry response was not a list.");
            reply->deleteLater();
            return;
        }

        QVector<ServerEntry> entries;
        const QJsonArray array = doc.array();
        entries.reserve(array.size());
        for (const QJsonValue &value : array) {
            if (!value.isObject()) {
                continue;
            }
            const QJsonObject obj = value.toObject();
            ServerEntry entry;
            entry.serverId = obj.value("server_id").toString();
            entry.name = obj.value("device_name").toString();
            entry.status = obj.value("status").toString();
            entry.lastSeenAt = obj.value("last_seen_at").toString();
            entry.wanEndpoint = obj.value("wan_direct_endpoint").toString();
            entry.overlayEndpoint = obj.value("overlay_endpoint").toString();
            entry.source = "registry";
            entry.key = QString("registry:%1").arg(entry.serverId.isEmpty() ? entry.name : entry.serverId);

            const QJsonValue lanValue = obj.value("lan_addresses");
            if (lanValue.isArray()) {
                const QJsonArray lanArray = lanValue.toArray();
                for (const QJsonValue &lanEntry : lanArray) {
                    entry.lanAddresses.append(lanEntry.toString());
                }
            }

            entries.push_back(entry);
        }

        m_registryModel.setEntries(entries);
        setStatusMessage(QString("Found %1 registry server(s).").arg(entries.size()));
        probeAll();
        reply->deleteLater();
    });
}

void ServerDiscovery::probeAll() {
    const QVector<ServerEntry> mdnsEntries = m_mdnsModel.entries();
    for (const ServerEntry &entry : mdnsEntries) {
        probeEntry(entry);
    }

    const QVector<ServerEntry> registryEntries = m_registryModel.entries();
    for (const ServerEntry &entry : registryEntries) {
        probeEntry(entry);
    }
}

void ServerDiscovery::setStatusMessage(const QString &value) {
    if (m_statusMessage == value) {
        return;
    }
    m_statusMessage = value;
    emit statusMessageChanged();
}

QString ServerDiscovery::normalizeEndpoint(const QString &value) const {
    QString trimmed = value.trimmed();
    if (trimmed.isEmpty()) {
        return trimmed;
    }
    if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
        trimmed.prepend("http://");
    }
    while (trimmed.endsWith('/')) {
        trimmed.chop(1);
    }
    return trimmed;
}

void ServerDiscovery::probeEntry(const ServerEntry &entry) {
    if (!entry.lanAddresses.isEmpty()) {
        probeEndpoint(entry.key, "lan", entry.lanAddresses.first());
    }
    if (!entry.wanEndpoint.isEmpty()) {
        probeEndpoint(entry.key, "wan", entry.wanEndpoint);
    }
}

void ServerDiscovery::probeEndpoint(const QString &entryKey, const QString &endpointType, const QString &endpoint) {
    const QString normalized = normalizeEndpoint(endpoint);
    if (normalized.isEmpty()) {
        return;
    }

    QUrl base(normalized);
    QUrl url = base.resolved(QUrl("/health"));

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, "ElixirClient/1.0");

    QNetworkReply *reply = m_manager.get(request);
    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);

    PendingProbe probe;
    probe.entryKey = entryKey;
    probe.endpointType = endpointType;
    probe.endpoint = normalized;
    probe.reply = reply;
    probe.timer = timer;

    m_probes.insert(reply, probe);

    connect(timer, &QTimer::timeout, this, [this, reply]() {
        handleProbeFinished(reply, true);
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleProbeFinished(reply, false);
    });

    timer->start(kProbeTimeoutMs);
}

void ServerDiscovery::handleProbeFinished(QNetworkReply *reply, bool forcedFailure) {
    if (!m_probes.contains(reply)) {
        return;
    }

    PendingProbe probe = m_probes.take(reply);
    if (probe.timer) {
        probe.timer->stop();
    }

    bool reachable = false;
    QString detail;

    if (forcedFailure) {
        reply->abort();
        detail = "Timeout";
    } else {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() == QNetworkReply::NoError && status >= 200 && status < 300) {
            reachable = true;
            detail = "OK";
        } else if (status > 0) {
            detail = QString("HTTP %1").arg(status);
        } else {
            detail = reply->errorString();
        }
    }

    m_mdnsModel.updateHealth(probe.entryKey, probe.endpointType, reachable, detail);
    m_registryModel.updateHealth(probe.entryKey, probe.endpointType, reachable, detail);

    reply->deleteLater();
}

#ifdef Q_OS_MAC
void ServerDiscovery::startMdnsBrowse() {
    DNSServiceRef browseRef = nullptr;
    const DNSServiceErrorType err = DNSServiceBrowse(
        &browseRef,
        0,
        0,
        kServiceType,
        nullptr,
        &ServerDiscovery::onBrowse,
        this);

    if (err != kDNSServiceErr_NoError) {
        setStatusMessage(QString("mDNS browse failed: %1").arg(err));
        return;
    }

    m_browseRef = browseRef;
    const int fd = DNSServiceRefSockFD(browseRef);
    if (fd == -1) {
        setStatusMessage("mDNS browse socket unavailable.");
        DNSServiceRefDeallocate(browseRef);
        m_browseRef = nullptr;
        return;
    }

    m_browseNotifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
    connect(m_browseNotifier, &QSocketNotifier::activated, this, [this](int) {
        processBrowseResult();
    });

    m_browsing = true;
    emit browsingChanged();
    setStatusMessage("mDNS browsing started.");
}

void ServerDiscovery::stopMdnsBrowse() {
    if (m_browseNotifier) {
        m_browseNotifier->deleteLater();
        m_browseNotifier = nullptr;
    }

    if (m_browseRef) {
        DNSServiceRefDeallocate(m_browseRef);
        m_browseRef = nullptr;
    }

    for (auto it = m_resolveNotifiers.begin(); it != m_resolveNotifiers.end(); ++it) {
        if (it.value()) {
            it.value()->deleteLater();
        }
        if (it.key()) {
            DNSServiceRefDeallocate(it.key());
        }
    }
    m_resolveNotifiers.clear();
    m_resolveContexts.clear();

    if (m_browsing) {
        m_browsing = false;
        emit browsingChanged();
    }
}

void ServerDiscovery::processBrowseResult() {
    if (!m_browseRef) {
        return;
    }

    const DNSServiceErrorType err = DNSServiceProcessResult(m_browseRef);
    if (err != kDNSServiceErr_NoError) {
        setStatusMessage(QString("mDNS browse error: %1").arg(err));
    }
}

void ServerDiscovery::processResolveResult(DNSServiceRef ref) {
    if (!ref) {
        return;
    }

    const DNSServiceErrorType err = DNSServiceProcessResult(ref);
    if (err != kDNSServiceErr_NoError) {
        setStatusMessage(QString("mDNS resolve error: %1").arg(err));
    }
}

QString ServerDiscovery::makeMdnsKey(const QString &serviceName, const QString &regType, const QString &domain) const {
    return QString("mdns:%1|%2|%3").arg(serviceName, regType, domain);
}

void ServerDiscovery::onBrowse(
    DNSServiceRef ref,
    DNSServiceFlags flags,
    uint32_t interfaceIndex,
    DNSServiceErrorType errorCode,
    const char *serviceName,
    const char *regType,
    const char *domain,
    void *context) {
    Q_UNUSED(ref)

    auto *self = static_cast<ServerDiscovery *>(context);
    if (!self) {
        return;
    }

    if (errorCode != kDNSServiceErr_NoError) {
        self->setStatusMessage(QString("mDNS browse callback error: %1").arg(errorCode));
        return;
    }

    const QString service = QString::fromUtf8(serviceName);
    const QString type = QString::fromUtf8(regType);
    const QString domainStr = QString::fromUtf8(domain);
    const QString key = self->makeMdnsKey(service, type, domainStr);

    if (!(flags & kDNSServiceFlagsAdd)) {
        self->m_mdnsModel.removeEntry(key);
        return;
    }

    DNSServiceRef resolveRef = nullptr;
    const DNSServiceErrorType resolveErr = DNSServiceResolve(
        &resolveRef,
        0,
        interfaceIndex,
        serviceName,
        regType,
        domain,
        &ServerDiscovery::onResolve,
        context);

    if (resolveErr != kDNSServiceErr_NoError || !resolveRef) {
        self->setStatusMessage(QString("mDNS resolve failed: %1").arg(resolveErr));
        return;
    }

    const int fd = DNSServiceRefSockFD(resolveRef);
    if (fd == -1) {
        DNSServiceRefDeallocate(resolveRef);
        return;
    }

    ResolveContext ctx;
    ctx.key = key;
    ctx.serviceName = service;
    ctx.regType = type;
    ctx.domain = domainStr;
    ctx.interfaceIndex = interfaceIndex;

    self->m_resolveContexts.insert(resolveRef, ctx);
    QSocketNotifier *notifier = new QSocketNotifier(fd, QSocketNotifier::Read, self);
    self->m_resolveNotifiers.insert(resolveRef, notifier);

    QObject::connect(notifier, &QSocketNotifier::activated, self, [self, resolveRef](int) {
        self->processResolveResult(resolveRef);
    });
}

void ServerDiscovery::onResolve(
    DNSServiceRef ref,
    DNSServiceFlags flags,
    uint32_t interfaceIndex,
    DNSServiceErrorType errorCode,
    const char *fullName,
    const char *hostTarget,
    uint16_t port,
    uint16_t txtLen,
    const unsigned char *txtRecord,
    void *context) {
    Q_UNUSED(flags)
    Q_UNUSED(interfaceIndex)
    Q_UNUSED(fullName)
    Q_UNUSED(txtLen)
    Q_UNUSED(txtRecord)

    auto *self = static_cast<ServerDiscovery *>(context);
    if (!self) {
        return;
    }

    if (errorCode != kDNSServiceErr_NoError) {
        self->setStatusMessage(QString("mDNS resolve callback error: %1").arg(errorCode));
    } else {
        const ResolveContext ctx = self->m_resolveContexts.value(ref);
        QString host = QString::fromUtf8(hostTarget);
        if (host.endsWith('.')) {
            host.chop(1);
        }
        const int resolvedPort = ntohs(port);
        const QString endpoint = QString("%1:%2").arg(host).arg(resolvedPort);

        ServerEntry entry;
        entry.key = ctx.key;
        entry.name = ctx.serviceName;
        entry.source = "mdns";
        entry.status = "discovered";
        entry.lanAddresses = QStringList{endpoint};

        self->m_mdnsModel.upsertEntry(entry);
        self->probeEntry(entry);
    }

    if (self->m_resolveNotifiers.contains(ref)) {
        QSocketNotifier *notifier = self->m_resolveNotifiers.take(ref);
        if (notifier) {
            notifier->deleteLater();
        }
    }
    self->m_resolveContexts.remove(ref);
    DNSServiceRefDeallocate(ref);
}
#endif
