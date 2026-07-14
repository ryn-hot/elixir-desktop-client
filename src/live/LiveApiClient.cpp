#include "LiveApiClient.h"

#include "backend/ApiClient.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QMetaObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSet>
#include <QSharedPointer>
#include <QUrlQuery>
#include <QUuid>

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>

namespace {

constexpr qsizetype kMaximumResponseBytes = 4 * 1024 * 1024;
constexpr qsizetype kMaximumAuthQueue = 64;

struct ResponseBuffer {
  QByteArray bytes;
  bool oversize{false};
};

QVariantMap localError(const QString &code, const QString &message,
                       bool retryable, int retryAfterSeconds = 0) {
  QVariantMap result{
      {QStringLiteral("code"), code},
      {QStringLiteral("message"), message},
      {QStringLiteral("retryable"), retryable},
  };
  if (retryAfterSeconds > 0) {
    result.insert(QStringLiteral("retryAfterSeconds"), retryAfterSeconds);
  }
  return result;
}

bool validUuid(const QString &value) {
  static const QRegularExpression pattern(
      QStringLiteral("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-["
                     "89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"));
  return pattern.match(value).hasMatch() && !QUuid(value).isNull();
}

bool validPositiveInteger(const QJsonValue &value) {
  if (!value.isDouble()) {
    return false;
  }
  const double number = value.toDouble();
  return std::isfinite(number) && number >= 1.0 && std::floor(number) == number;
}

bool validNonnegativeInteger(const QJsonValue &value) {
  if (!value.isDouble()) {
    return false;
  }
  const double number = value.toDouble();
  return std::isfinite(number) && number >= 0.0 && std::floor(number) == number;
}

bool validUtcTimestamp(const QJsonValue &value) {
  if (!value.isString() || !value.toString().endsWith(QLatin1Char('Z'))) {
    return false;
  }
  return QDateTime::fromString(value.toString(), Qt::ISODateWithMs).isValid() ||
         QDateTime::fromString(value.toString(), Qt::ISODate).isValid();
}

bool validKeyId(const QString &value) {
  static const QRegularExpression pattern(
      QStringLiteral("^[A-Za-z0-9._~-]{1,32}$"));
  return pattern.match(value).hasMatch();
}

bool containsForbiddenAdminField(const QJsonValue &value) {
  static const QSet<QString> forbidden{
      QStringLiteral("authorization"), QStringLiteral("cookie"),
      QStringLiteral("cookies"),       QStringLiteral("credential"),
      QStringLiteral("credentials"),   QStringLiteral("descriptor"),
      QStringLiteral("headers"),       QStringLiteral("keymaterial"),
      QStringLiteral("material"),      QStringLiteral("replaytoken"),
      QStringLiteral("sessiontoken"),  QStringLiteral("sourceurl"),
      QStringLiteral("upstreamurl"),   QStringLiteral("valueencrypted")};
  if (value.isArray()) {
    const QJsonArray array = value.toArray();
    return std::any_of(array.cbegin(), array.cend(),
                       [](const QJsonValue &item) {
                         return containsForbiddenAdminField(item);
                       });
  }
  if (!value.isObject()) {
    return false;
  }
  const QJsonObject object = value.toObject();
  for (auto iterator = object.constBegin(); iterator != object.constEnd();
       ++iterator) {
    QString normalized = iterator.key().toLower();
    normalized.remove(QLatin1Char('_'));
    normalized.remove(QLatin1Char('-'));
    if (forbidden.contains(normalized) ||
        containsForbiddenAdminField(iterator.value())) {
      return true;
    }
  }
  return false;
}

bool validAuditReference(const QJsonValue &value) {
  if (!value.isObject()) {
    return false;
  }
  const QJsonObject audit = value.toObject();
  const QJsonObject actor = audit.value(QStringLiteral("actor")).toObject();
  const QString action = audit.value(QStringLiteral("action")).toString();
  const QString targetType =
      audit.value(QStringLiteral("targetType")).toString();
  const QString targetId = audit.value(QStringLiteral("targetId")).toString();
  const QString displayName =
      actor.value(QStringLiteral("displayName")).toString();
  const QString homeRole = actor.value(QStringLiteral("homeRole")).toString();
  const QString recordHash =
      audit.value(QStringLiteral("recordHash")).toString();
  static const QRegularExpression hashPattern(QStringLiteral("^[0-9a-f]{64}$"));
  return validUuid(audit.value(QStringLiteral("auditId")).toString()) &&
         !action.isEmpty() && action.size() <= 64 && !targetType.isEmpty() &&
         targetType.size() <= 64 && !targetId.isEmpty() &&
         targetId.size() <= 256 &&
         validUuid(actor.value(QStringLiteral("actorUserId")).toString()) &&
         !displayName.trimmed().isEmpty() && displayName.size() <= 256 &&
         QSet<QString>{QStringLiteral("owner"), QStringLiteral("admin"),
                       QStringLiteral("manager"), QStringLiteral("viewer")}
             .contains(homeRole) &&
         validUtcTimestamp(audit.value(QStringLiteral("occurredAt"))) &&
         hashPattern.match(recordHash).hasMatch();
}

bool validDestinationRule(const QJsonValue &value,
                          const QString &expectedProviderId = {}) {
  if (!value.isObject()) {
    return false;
  }
  const QJsonObject rule = value.toObject();
  const QString scheme = rule.value(QStringLiteral("scheme")).toString();
  const QString host = rule.value(QStringLiteral("host")).toString();
  const QString path = rule.value(QStringLiteral("path")).toString();
  const QString scope = rule.value(QStringLiteral("networkScope")).toString();
  const QString providerId =
      rule.value(QStringLiteral("providerId")).toString();
  return validUuid(rule.value(QStringLiteral("ruleId")).toString()) &&
         validUuid(providerId) &&
         (expectedProviderId.isEmpty() || providerId == expectedProviderId) &&
         validPositiveInteger(rule.value(QStringLiteral("revision"))) &&
         QSet<QString>{QStringLiteral("http"), QStringLiteral("https"),
                       QStringLiteral("rtmp"), QStringLiteral("srt")}
             .contains(scheme) &&
         !host.isEmpty() && host.size() <= 253 && path.startsWith('/') &&
         path.size() <= 2048 && !path.contains('?') && !path.contains('#') &&
         validPositiveInteger(rule.value(QStringLiteral("port"))) &&
         rule.value(QStringLiteral("port")).toInt() <= 65'535 &&
         QSet<QString>{QStringLiteral("public"), QStringLiteral("private_lan")}
             .contains(scope) &&
         rule.value(QStringLiteral("allowFetch")).isBool() &&
         rule.value(QStringLiteral("allowCredentials")).isBool() &&
         rule.value(QStringLiteral("allowClientDisclosure")).isBool() &&
         validUtcTimestamp(rule.value(QStringLiteral("createdAt"))) &&
         validUtcTimestamp(rule.value(QStringLiteral("updatedAt")));
}

bool validAdminMeta(const QJsonValue &value) {
  if (!value.isObject()) {
    return false;
  }
  const QJsonObject metadata = value.toObject();
  return validUuid(metadata.value(QStringLiteral("requestId")).toString()) &&
         validUtcTimestamp(metadata.value(QStringLiteral("generatedAt"))) &&
         metadata.value(QStringLiteral("cacheState")).toString() ==
             QStringLiteral("none") &&
         metadata.value(QStringLiteral("partial")).isBool() &&
         !metadata.value(QStringLiteral("partial")).toBool();
}

bool validAdminProvider(const QJsonValue &value) {
  if (!value.isObject()) {
    return false;
  }
  const QJsonObject provider = value.toObject();
  const QString readiness =
      provider.value(QStringLiteral("readiness")).toString();
  const QJsonValue disabledReason =
      provider.value(QStringLiteral("disabledReason"));
  const QJsonArray protocols =
      provider.value(QStringLiteral("effectiveProtocols")).toArray();
  const QSet<QString> supportedProtocols{QStringLiteral("hls"),
                                         QStringLiteral("dash"),
                                         QStringLiteral("http_progressive"),
                                         QStringLiteral("mpeg_ts"),
                                         QStringLiteral("rtmp"),
                                         QStringLiteral("srt")};
  const bool protocolsValid =
      std::all_of(protocols.cbegin(), protocols.cend(),
                  [&supportedProtocols](const QJsonValue &protocol) {
                    return protocol.isString() &&
                           supportedProtocols.contains(protocol.toString());
                  });
  return validUuid(provider.value(QStringLiteral("providerId")).toString()) &&
         provider.value(QStringLiteral("enabled")).isBool() &&
         QSet<QString>{QStringLiteral("ready"), QStringLiteral("degraded"),
                       QStringLiteral("unavailable"),
                       QStringLiteral("disabled")}
             .contains(readiness) &&
         (disabledReason.isNull() || disabledReason.isString()) &&
         validPositiveInteger(
             provider.value(QStringLiteral("providerRevision"))) &&
         validPositiveInteger(
             provider.value(QStringLiteral("grantRevision"))) &&
         validNonnegativeInteger(
             provider.value(QStringLiteral("activeSessions"))) &&
         protocols.size() <= 16 && protocolsValid;
}

bool validAdminSession(const QJsonValue &value) {
  if (!value.isObject()) {
    return false;
  }
  const QJsonObject session = value.toObject();
  const QString deliveryMode =
      session.value(QStringLiteral("deliveryMode")).toString();
  const QString state = session.value(QStringLiteral("state")).toString();
  return validUuid(session.value(QStringLiteral("sessionId")).toString()) &&
         validUuid(session.value(QStringLiteral("profileId")).toString()) &&
         validUuid(session.value(QStringLiteral("providerId")).toString()) &&
         QSet<QString>{QStringLiteral("client_direct"),
                       QStringLiteral("server_relay"),
                       QStringLiteral("server_remux")}
             .contains(deliveryMode) &&
         QSet<QString>{QStringLiteral("hls"),
                       QStringLiteral("dash"),
                       QStringLiteral("http_progressive"),
                       QStringLiteral("mpeg_ts"),
                       QStringLiteral("rtmp"),
                       QStringLiteral("srt")}
             .contains(session.value(QStringLiteral("protocol")).toString()) &&
         QSet<QString>{QStringLiteral("resolving"),
                       QStringLiteral("planning"),
                       QStringLiteral("provisioning_egress"),
                       QStringLiteral("starting_remux"),
                       QStringLiteral("ready"),
                       QStringLiteral("playing"),
                       QStringLiteral("reconnecting"),
                       QStringLiteral("refreshing"),
                       QStringLiteral("failing_over"),
                       QStringLiteral("ended"),
                       QStringLiteral("expired"),
                       QStringLiteral("failed")}
             .contains(state) &&
         validPositiveInteger(session.value(QStringLiteral("revision"))) &&
         validNonnegativeInteger(
             session.value(QStringLiteral("sourceIndex"))) &&
         validNonnegativeInteger(
             session.value(QStringLiteral("failoverCount"))) &&
         validNonnegativeInteger(
             session.value(QStringLiteral("refreshCount"))) &&
         validUtcTimestamp(session.value(QStringLiteral("createdAt"))) &&
         validUtcTimestamp(session.value(QStringLiteral("lastHeartbeatAt"))) &&
         validUtcTimestamp(session.value(QStringLiteral("expiresAt")));
}

bool validAdminMutation(const QString &operation, const QJsonObject &data,
                        const QString &subjectId, const QString &secondaryId) {
  if (!validPositiveInteger(data.value(QStringLiteral("revision"))) ||
      !validAuditReference(data.value(QStringLiteral("audit")))) {
    return false;
  }
  if (operation == QStringLiteral("destinationRuleCreate") ||
      operation == QStringLiteral("destinationRuleUpdate") ||
      operation == QStringLiteral("destinationRuleDelete")) {
    const bool deleted = data.value(QStringLiteral("deleted")).toBool();
    const QJsonValue rule = data.value(QStringLiteral("rule"));
    const QString ruleId = data.value(QStringLiteral("ruleId")).toString();
    return data.value(QStringLiteral("providerId")).toString() == subjectId &&
           validUuid(ruleId) &&
           (operation == QStringLiteral("destinationRuleCreate") ||
            ruleId == secondaryId) &&
           data.value(QStringLiteral("deleted")).isBool() &&
           (deleted ? rule.isNull() : validDestinationRule(rule, subjectId));
  }
  if (operation == QStringLiteral("providerDisable")) {
    return data.value(QStringLiteral("providerId")).toString() == subjectId &&
           validUuid(data.value(QStringLiteral("operationId")).toString()) &&
           data.value(QStringLiteral("status")).toString() ==
               QStringLiteral("accepted");
  }
  if (operation == QStringLiteral("grantSet") ||
      operation == QStringLiteral("grantRevoke")) {
    return data.value(QStringLiteral("providerId")).toString() == subjectId &&
           data.value(QStringLiteral("profileId")).toString() == secondaryId &&
           data.value(QStringLiteral("canBrowse")).isBool() &&
           data.value(QStringLiteral("canPlay")).isBool();
  }
  if (operation == QStringLiteral("sessionTerminate")) {
    return data.value(QStringLiteral("sessionId")).toString() == subjectId &&
           data.value(QStringLiteral("status")).toString() ==
               QStringLiteral("completed") &&
           data.value(QStringLiteral("state")).toString() ==
               QStringLiteral("ended");
  }
  if (operation.startsWith(QStringLiteral("keyRotate:"))) {
    const QString domain = operation.sliced(10);
    return QSet<QString>{QStringLiteral("envelope"),
                         QStringLiteral("token_hash"), QStringLiteral("audit")}
               .contains(domain) &&
           data.value(QStringLiteral("status")).toString() ==
               QStringLiteral("completed") &&
           data.value(QStringLiteral("keyDomain")).toString() == domain &&
           data.value(QStringLiteral("primaryKeyId")).toString() == subjectId &&
           validKeyId(
               data.value(QStringLiteral("previousPrimaryKeyId")).toString()) &&
           validNonnegativeInteger(
               data.value(QStringLiteral("reencryptedSessions"))) &&
           validNonnegativeInteger(
               data.value(QStringLiteral("reencryptedReplays"))) &&
           validNonnegativeInteger(
               data.value(QStringLiteral("terminatedSessions"))) &&
           validNonnegativeInteger(
               data.value(QStringLiteral("invalidatedCacheEntries")));
  }
  return false;
}

bool validAdminData(const QString &operation, const QJsonValue &data,
                    const QString &subjectId, const QString &secondaryId) {
  if (operation == QStringLiteral("adminProviders")) {
    if (!data.isArray() || data.toArray().size() > 200) {
      return false;
    }
    const QJsonArray providers = data.toArray();
    return std::all_of(providers.cbegin(), providers.cend(),
                       validAdminProvider);
  }
  if (operation == QStringLiteral("adminSessions")) {
    if (!data.isArray() || data.toArray().size() > 200) {
      return false;
    }
    const QJsonArray sessions = data.toArray();
    return std::all_of(sessions.cbegin(), sessions.cend(), validAdminSession);
  }
  if (operation == QStringLiteral("destinationRules")) {
    if (!data.isArray() || data.toArray().size() > 256) {
      return false;
    }
    const QJsonArray rules = data.toArray();
    return std::all_of(rules.cbegin(), rules.cend(),
                       [&subjectId](const QJsonValue &rule) {
                         return validDestinationRule(rule, subjectId);
                       });
  }
  if (operation == QStringLiteral("keyState")) {
    if (!data.isObject()) {
      return false;
    }
    const QJsonObject state = data.toObject();
    return validKeyId(state.value(QStringLiteral("envelopePrimaryKeyId"))
                          .toString()) &&
           validKeyId(state.value(QStringLiteral("tokenHashPrimaryKeyId"))
                          .toString()) &&
           validKeyId(
               state.value(QStringLiteral("auditPrimaryKeyId")).toString()) &&
           validPositiveInteger(state.value(QStringLiteral("revision")));
  }
  return data.isObject() &&
         validAdminMutation(operation, data.toObject(), subjectId, secondaryId);
}

bool validAdminEnvelope(const QJsonDocument &document, const QString &operation,
                        const QString &subjectId, const QString &secondaryId,
                        QVariant *data, QString *error) {
  if (!document.isObject()) {
    *error = QStringLiteral("Live admin response must be an object.");
    return false;
  }
  const QJsonObject envelope = document.object();
  if (!envelope.contains(QStringLiteral("data")) ||
      !validAdminMeta(envelope.value(QStringLiteral("meta"))) ||
      !envelope.value(QStringLiteral("errors")).isArray() ||
      !envelope.value(QStringLiteral("errors")).toArray().isEmpty()) {
    *error = QStringLiteral("Live admin envelope metadata is invalid.");
    return false;
  }
  if (containsForbiddenAdminField(envelope)) {
    *error = QStringLiteral("Live admin response contained sensitive fields.");
    return false;
  }
  const QJsonValue responseData = envelope.value(QStringLiteral("data"));
  if (!validAdminData(operation, responseData, subjectId, secondaryId)) {
    *error = QStringLiteral("Live admin response data is invalid.");
    return false;
  }
  *data = responseData.toVariant();
  return true;
}

bool validDestinationDraft(const QVariantMap &draft, QJsonObject *output) {
  static const QSet<QString> required{QStringLiteral("scheme"),
                                      QStringLiteral("host"),
                                      QStringLiteral("port"),
                                      QStringLiteral("path"),
                                      QStringLiteral("networkScope"),
                                      QStringLiteral("allowFetch"),
                                      QStringLiteral("allowCredentials"),
                                      QStringLiteral("allowClientDisclosure")};
  if (QSet<QString>(draft.keyBegin(), draft.keyEnd()) != required) {
    return false;
  }
  const QJsonObject value = QJsonObject::fromVariantMap(draft);
  const QString scheme = value.value(QStringLiteral("scheme")).toString();
  const QString host = value.value(QStringLiteral("host")).toString();
  const QString path = value.value(QStringLiteral("path")).toString();
  const QString scope = value.value(QStringLiteral("networkScope")).toString();
  const bool fetch = value.value(QStringLiteral("allowFetch")).toBool();
  const bool credentials =
      value.value(QStringLiteral("allowCredentials")).toBool();
  const bool disclosure =
      value.value(QStringLiteral("allowClientDisclosure")).toBool();
  const bool httpsRequired = credentials || disclosure;
  const bool privateLan = scope == QStringLiteral("private_lan");
  const bool streamTransport =
      scheme == QStringLiteral("rtmp") || scheme == QStringLiteral("srt");
  if (!required.contains(QStringLiteral("scheme")) ||
      !QSet<QString>{QStringLiteral("http"), QStringLiteral("https"),
                     QStringLiteral("rtmp"), QStringLiteral("srt")}
           .contains(scheme) ||
      host.trimmed() != host || host.isEmpty() || host.size() > 253 ||
      host.contains('/') || host.contains('?') || host.contains('#') ||
      host.contains('@') || path.isEmpty() || !path.startsWith('/') ||
      path.size() > 2048 || path.contains('?') || path.contains('#') ||
      !validPositiveInteger(value.value(QStringLiteral("port"))) ||
      value.value(QStringLiteral("port")).toInt() > 65'535 ||
      !QSet<QString>{QStringLiteral("public"), QStringLiteral("private_lan")}
           .contains(scope) ||
      !value.value(QStringLiteral("allowFetch")).isBool() ||
      !value.value(QStringLiteral("allowCredentials")).isBool() ||
      !value.value(QStringLiteral("allowClientDisclosure")).isBool() ||
      (httpsRequired && (scheme != QStringLiteral("https") || !fetch)) ||
      (streamTransport && (!fetch || credentials || disclosure)) ||
      (privateLan && disclosure)) {
    return false;
  }
  *output = value;
  return true;
}

bool validHeartbeatObservation(const QVariantMap &observation) {
  static const QSet<QString> allowed{
      QStringLiteral("playerState"),
      QStringLiteral("observedAt"),
      QStringLiteral("distanceFromLiveEdgeSeconds"),
      QStringLiteral("sourceKey"),
      QStringLiteral("audioTrackId"),
      QStringLiteral("audioTrackLanguage"),
      QStringLiteral("audioTrackTitle"),
      QStringLiteral("subtitleTrackId"),
      QStringLiteral("subtitleTrackLanguage"),
      QStringLiteral("subtitleTrackTitle")};
  for (auto iterator = observation.constBegin();
       iterator != observation.constEnd(); ++iterator) {
    if (!allowed.contains(iterator.key())) {
      return false;
    }
  }
  const QString state =
      observation.value(QStringLiteral("playerState")).toString();
  if (!QSet<QString>{QStringLiteral("loading"), QStringLiteral("buffering"),
                     QStringLiteral("playing"), QStringLiteral("paused"),
                     QStringLiteral("ended")}
           .contains(state)) {
    return false;
  }
  const QString observedAt =
      observation.value(QStringLiteral("observedAt")).toString();
  if (!observedAt.endsWith('Z') ||
      !QDateTime::fromString(observedAt, Qt::ISODateWithMs).isValid()) {
    return false;
  }
  const QVariant distance =
      observation.value(QStringLiteral("distanceFromLiveEdgeSeconds"));
  if (distance.isValid() && !distance.isNull()) {
    bool converted = false;
    const double seconds = distance.toDouble(&converted);
    if (!converted || !std::isfinite(seconds) || seconds < 0.0 ||
        seconds > 86'400.0) {
      return false;
    }
  }
  static const QRegularExpression opaque(
      QStringLiteral("^[A-Za-z0-9._~-]{16,4096}$"));
  const QVariant source = observation.value(QStringLiteral("sourceKey"));
  if (source.isValid() && !source.isNull() &&
      !opaque.match(source.toString()).hasMatch()) {
    return false;
  }
  for (const QString &key :
       {QStringLiteral("audioTrackId"), QStringLiteral("subtitleTrackId")}) {
    const QVariant value = observation.value(key);
    if (value.isValid() && !value.isNull() &&
        (value.toString().isEmpty() || value.toString().size() > 256 ||
         value.toString().trimmed() != value.toString())) {
      return false;
    }
  }
  for (const QString &prefix : {QStringLiteral("audioTrack"),
                                QStringLiteral("subtitleTrack")}) {
    const QVariant id = observation.value(prefix + QStringLiteral("Id"));
    for (const auto &[suffix, maximum] :
         std::array<std::pair<QString, int>, 2>{
             std::pair{QStringLiteral("Language"), 64},
             std::pair{QStringLiteral("Title"), 256}}) {
      const QVariant value = observation.value(prefix + suffix);
      if (value.isValid() && !value.isNull() &&
          ((!id.isValid() || id.isNull()) || value.toString().isEmpty() ||
           value.toString().size() > maximum ||
           value.toString().trimmed() != value.toString())) {
        return false;
      }
    }
  }
  return true;
}

bool validRecoveryReason(const QString &reason) {
  static const QSet<QString> reasons{QStringLiteral("expiry_threshold"),
                                     QStringLiteral("upstream_unauthorized"),
                                     QStringLiteral("upstream_forbidden"),
                                     QStringLiteral("upstream_gone"),
                                     QStringLiteral("transport"),
                                     QStringLiteral("stalled"),
                                     QStringLiteral("manual_source_switch")};
  return reasons.contains(reason);
}

void eraseSessionToken(Live::SessionCreated *session) {
  if (!session) {
    return;
  }
  std::fill(session->sessionToken.begin(), session->sessionToken.end(), '\0');
  session->sessionToken.clear();
  session->sessionToken.squeeze();
}

void drainReply(QNetworkReply *reply,
                const QSharedPointer<ResponseBuffer> &buffer) {
  if (buffer->oversize) {
    reply->readAll();
    return;
  }
  const QByteArray chunk = reply->readAll();
  if (chunk.size() > kMaximumResponseBytes - buffer->bytes.size()) {
    buffer->bytes.clear();
    buffer->oversize = true;
    reply->abort();
    return;
  }
  buffer->bytes.append(chunk);
}

} // namespace

LiveApiClient::LiveApiClient(ApiClient *authClient, QObject *parent)
    : LiveApiClient(authClient, nullptr, parent) {}

LiveApiClient::LiveApiClient(ApiClient *authClient,
                             QNetworkAccessManager *networkManager,
                             QObject *parent)
    : QObject(parent), m_authClient(authClient),
      m_networkManager(networkManager ? networkManager
                                      : &m_ownedNetworkManager) {
  qRegisterMetaType<Live::ProvidersEnvelope>();
  qRegisterMetaType<Live::CatalogsEnvelope>();
  qRegisterMetaType<Live::CatalogPageEnvelope>();
  qRegisterMetaType<Live::ItemEnvelope>();
  qRegisterMetaType<Live::SessionCreated>();
  qRegisterMetaType<Live::SessionDetailEnvelope>();

  if (!m_authClient) {
    return;
  }
  m_authContextKey = authContextKey();
  connect(m_authClient, &ApiClient::baseUrlChanged, this,
          &LiveApiClient::authContextChanged);
  connect(m_authClient, &ApiClient::sessionStateChanged, this,
          &LiveApiClient::authContextChanged);
  connect(m_authClient, &ApiClient::refreshInFlightChanged, this, [this]() {
    if (m_authClient && !m_authClient->refreshInFlight()) {
      drainAuthQueue();
    }
  });
  connect(m_authClient, &ApiClient::authTokenChanged, this, [this]() {
    if (!m_authClient || m_authClient->authToken().isEmpty()) {
      cancelAll();
      return;
    }
    if (!m_authClient->refreshInFlight()) {
      drainAuthQueue();
    }
  });
  connect(m_authClient, &ApiClient::authExpired, this,
          [this]() { cancelAll(); });
  connect(m_authClient, &QObject::destroyed, this, [this]() {
    m_authClient = nullptr;
    cancelAll();
  });
}

QString LiveApiClient::serverBaseUrl() const {
  return m_authClient ? m_authClient->baseUrl() : QString();
}

QString LiveApiClient::accountSessionId() const {
  return m_authClient ? m_authClient->sessionId() : QString();
}

LiveApiClient::Request LiveApiClient::requestShell(quint64 id,
                                                   quint64 generation,
                                                   RequestKind kind,
                                                   const QString &endpoint) {
  Request request;
  request.id = id;
  request.generation = generation;
  request.kind = kind;
  request.endpoint = endpoint;
  return request;
}

quint64 LiveApiClient::listProviders(quint64 generation) {
  return enqueue(RequestKind::Providers,
                 QStringLiteral("/api/v1/live/providers"), generation);
}

quint64 LiveApiClient::listCatalogs(quint64 generation) {
  return enqueue(RequestKind::Catalogs, QStringLiteral("/api/v1/live/catalogs"),
                 generation);
}

quint64 LiveApiClient::listCatalogItems(const QString &providerId,
                                        const QString &catalogId,
                                        const QVariantMap &filters,
                                        const QString &cursor, int limit,
                                        quint64 generation) {
  QString error;
  const QString endpoint = endpointForCatalogPage(
      providerId, catalogId, filters, cursor, limit, &error);
  const quint64 requestId =
      enqueue(RequestKind::CatalogPage, endpoint, generation);
  if (!error.isEmpty()) {
    QMetaObject::invokeMethod(
        this,
        [this, requestId, generation, error]() {
          if (m_generations.contains(requestId)) {
            fail(requestShell(requestId, generation, RequestKind::CatalogPage,
                              QStringLiteral("/api/v1/live/catalogs")),
                 QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"), error);
          }
        },
        Qt::QueuedConnection);
  }
  return requestId;
}

quint64 LiveApiClient::getItem(const QString &providerId,
                               const QString &itemKey, quint64 generation) {
  static const QRegularExpression opaque(
      QStringLiteral("^[A-Za-z0-9._~-]{16,2048}$"));
  QString endpoint;
  QString error;
  if (!validUuid(providerId)) {
    error = QStringLiteral("Provider id is invalid.");
  } else if (!opaque.match(itemKey).hasMatch()) {
    error = QStringLiteral("Item key is invalid.");
  } else {
    endpoint =
        QStringLiteral("/api/v1/live/items/%1/%2")
            .arg(encodePathSegment(providerId), encodePathSegment(itemKey));
  }
  const quint64 requestId = enqueue(RequestKind::Item, endpoint, generation);
  if (!error.isEmpty()) {
    QMetaObject::invokeMethod(
        this,
        [this, requestId, generation, error]() {
          if (m_generations.contains(requestId)) {
            fail(requestShell(requestId, generation, RequestKind::Item,
                              QStringLiteral("/api/v1/live/items")),
                 QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"), error);
          }
        },
        Qt::QueuedConnection);
  }
  return requestId;
}

quint64 LiveApiClient::createSession(const QString &providerId,
                                     const QString &itemKey,
                                     const QString &streamOptionKey,
                                     const QVariantMap &clientCapabilities,
                                     const QString &idempotencyKey,
                                     quint64 generation) {
  static const QRegularExpression opaque(
      QStringLiteral("^[A-Za-z0-9._~-]{16,2048}$"));
  static const QRegularExpression idempotency(
      QStringLiteral("^[!-~]{16,128}$"));
  QString error;
  if (!validUuid(providerId)) {
    error = QStringLiteral("Provider id is invalid.");
  } else if (!opaque.match(itemKey).hasMatch() ||
             !opaque.match(streamOptionKey).hasMatch()) {
    error = QStringLiteral("Live item or stream key is invalid.");
  } else if (!idempotency.match(idempotencyKey).hasMatch()) {
    error = QStringLiteral("Live idempotency key is invalid.");
  }
  const QJsonObject body{
      {QStringLiteral("providerId"), providerId},
      {QStringLiteral("itemKey"), itemKey},
      {QStringLiteral("streamOptionKey"), streamOptionKey},
      {QStringLiteral("client"),
       QJsonObject::fromVariantMap(clientCapabilities)},
  };
  const QString endpoint =
      error.isEmpty() ? QStringLiteral("/api/v1/live/sessions") : QString();
  const quint64 requestId =
      enqueue(RequestKind::SessionCreate, endpoint, generation,
              QByteArrayLiteral("POST"),
              QJsonDocument(body).toJson(QJsonDocument::Compact),
              idempotencyKey.toUtf8());
  if (!error.isEmpty()) {
    QMetaObject::invokeMethod(
        this,
        [this, requestId, generation, error]() {
          if (m_generations.contains(requestId)) {
            fail(requestShell(requestId, generation, RequestKind::SessionCreate,
                              QStringLiteral("/api/v1/live/sessions")),
                 QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"), error);
          }
        },
        Qt::QueuedConnection);
  }
  return requestId;
}

quint64 LiveApiClient::getSession(const QString &sessionId,
                                  quint64 generation) {
  const QString endpoint = validUuid(sessionId)
                               ? QStringLiteral("/api/v1/live/sessions/%1")
                                     .arg(encodePathSegment(sessionId))
                               : QString();
  const quint64 requestId =
      enqueue(RequestKind::SessionGet, endpoint, generation,
              QByteArrayLiteral("GET"), {}, {}, sessionId);
  if (endpoint.isEmpty()) {
    QMetaObject::invokeMethod(
        this,
        [this, requestId, generation]() {
          if (m_generations.contains(requestId)) {
            fail(requestShell(requestId, generation, RequestKind::SessionGet,
                              QStringLiteral("/api/v1/live/sessions")),
                 QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"),
                 QStringLiteral("Live session id is invalid."));
          }
        },
        Qt::QueuedConnection);
  }
  return requestId;
}

quint64 LiveApiClient::heartbeatSession(const QString &sessionId,
                                        qint64 expectedRevision,
                                        const QVariantMap &observation,
                                        quint64 generation) {
  QString endpoint;
  if (validUuid(sessionId) && expectedRevision > 0 &&
      validHeartbeatObservation(observation)) {
    endpoint = QStringLiteral("/api/v1/live/sessions/%1/heartbeat")
                   .arg(encodePathSegment(sessionId));
  }
  QVariantMap payload = observation;
  payload.insert(QStringLiteral("expectedRevision"), expectedRevision);
  const quint64 requestId =
      enqueue(RequestKind::SessionHeartbeat, endpoint, generation,
              QByteArrayLiteral("POST"),
              QJsonDocument(QJsonObject::fromVariantMap(payload))
                  .toJson(QJsonDocument::Compact),
              {}, sessionId);
  if (endpoint.isEmpty()) {
    QMetaObject::invokeMethod(
        this,
        [this, requestId, generation]() {
          if (m_generations.contains(requestId)) {
            fail(requestShell(requestId, generation,
                              RequestKind::SessionHeartbeat,
                              QStringLiteral("/api/v1/live/sessions")),
                 QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"),
                 QStringLiteral("Live heartbeat identity is invalid."));
          }
        },
        Qt::QueuedConnection);
  }
  return requestId;
}

quint64 LiveApiClient::refreshSession(const QString &sessionId,
                                      qint64 expectedRevision,
                                      const QString &reason,
                                      quint64 generation) {
  return recoverSession(sessionId, expectedRevision, reason, {}, false,
                        generation);
}

quint64 LiveApiClient::failoverSession(const QString &sessionId,
                                       qint64 expectedRevision,
                                       const QString &reason,
                                       const QString &requestedSourceKey,
                                       quint64 generation) {
  return recoverSession(sessionId, expectedRevision, reason, requestedSourceKey,
                        true, generation);
}

quint64 LiveApiClient::recoverSession(const QString &sessionId,
                                      qint64 expectedRevision,
                                      const QString &reason,
                                      const QString &requestedSourceKey,
                                      bool failover, quint64 generation) {
  static const QRegularExpression opaque(
      QStringLiteral("^[A-Za-z0-9._~-]{16,2048}$"));
  const bool manual = reason == QStringLiteral("manual_source_switch");
  const bool validSource = requestedSourceKey.isEmpty() ||
                           opaque.match(requestedSourceKey).hasMatch();
  const bool validShape =
      validUuid(sessionId) && expectedRevision > 0 &&
      validRecoveryReason(reason) && validSource &&
      (failover ? (manual == !requestedSourceKey.isEmpty())
                : (!manual && requestedSourceKey.isEmpty()));
  const QString action =
      failover ? QStringLiteral("failover") : QStringLiteral("refresh");
  const QString endpoint = validShape
                               ? QStringLiteral("/api/v1/live/sessions/%1/%2")
                                     .arg(encodePathSegment(sessionId), action)
                               : QString();
  QJsonObject payload{{QStringLiteral("expectedRevision"), expectedRevision},
                      {QStringLiteral("reason"), reason}};
  if (!requestedSourceKey.isEmpty()) {
    payload.insert(QStringLiteral("requestedSourceKey"), requestedSourceKey);
  }
  const quint64 requestId = enqueue(
      RequestKind::SessionRecovery, endpoint, generation,
      QByteArrayLiteral("POST"),
      QJsonDocument(payload).toJson(QJsonDocument::Compact), {}, sessionId);
  if (!validShape) {
    QMetaObject::invokeMethod(
        this,
        [this, requestId, generation]() {
          if (m_generations.contains(requestId)) {
            fail(requestShell(requestId, generation,
                              RequestKind::SessionRecovery,
                              QStringLiteral("/api/v1/live/sessions")),
                 QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"),
                 QStringLiteral("Live recovery identity is invalid."));
          }
        },
        Qt::QueuedConnection);
  }
  return requestId;
}

quint64 LiveApiClient::endSession(const QString &sessionId,
                                  qint64 expectedRevision, quint64 generation) {
  QString endpoint;
  if (validUuid(sessionId) && expectedRevision > 0) {
    endpoint = QStringLiteral("/api/v1/live/sessions/%1?expectedRevision=%2")
                   .arg(encodePathSegment(sessionId))
                   .arg(expectedRevision);
  }
  const quint64 requestId =
      enqueue(RequestKind::SessionEnd, endpoint, generation,
              QByteArrayLiteral("DELETE"), {}, {}, sessionId);
  if (endpoint.isEmpty()) {
    QMetaObject::invokeMethod(
        this,
        [this, requestId, generation]() {
          if (m_generations.contains(requestId)) {
            fail(requestShell(requestId, generation, RequestKind::SessionEnd,
                              QStringLiteral("/api/v1/live/sessions")),
                 QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"),
                 QStringLiteral("Live session end identity is invalid."));
          }
        },
        Qt::QueuedConnection);
  }
  return requestId;
}

quint64 LiveApiClient::listAdminProviders(quint64 generation) {
  return enqueueAdmin(QStringLiteral("adminProviders"),
                      QStringLiteral("/api/v1/live/admin/providers"),
                      generation);
}

quint64 LiveApiClient::listAdminSessions(quint64 generation) {
  return enqueueAdmin(QStringLiteral("adminSessions"),
                      QStringLiteral("/api/v1/live/admin/sessions"),
                      generation);
}

quint64 LiveApiClient::getAdminKeyState(quint64 generation) {
  return enqueueAdmin(QStringLiteral("keyState"),
                      QStringLiteral("/api/v1/live/admin/keys"), generation);
}

quint64 LiveApiClient::listAdminDestinationRules(const QString &providerId,
                                                 quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/providers");
  if (!validUuid(providerId)) {
    return invalidAdminRequest(QStringLiteral("destinationRules"), base,
                               generation,
                               QStringLiteral("Live provider id is invalid."));
  }
  return enqueueAdmin(QStringLiteral("destinationRules"),
                      QStringLiteral("%1/%2/destination-rules")
                          .arg(base, encodePathSegment(providerId)),
                      generation, QByteArrayLiteral("GET"), {}, providerId);
}

quint64 LiveApiClient::createAdminDestinationRule(
    const QString &providerId, qint64 expectedProviderRevision,
    const QVariantMap &rule, quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/providers");
  QJsonObject body;
  if (!validUuid(providerId) || expectedProviderRevision < 1 ||
      !validDestinationDraft(rule, &body)) {
    return invalidAdminRequest(
        QStringLiteral("destinationRuleCreate"), base, generation,
        QStringLiteral("Live destination rule is invalid."));
  }
  body.insert(QStringLiteral("expectedProviderRevision"),
              expectedProviderRevision);
  const QString endpoint = QStringLiteral("%1/%2/destination-rules")
                               .arg(base, encodePathSegment(providerId));
  return enqueueAdmin(QStringLiteral("destinationRuleCreate"), endpoint,
                      generation, QByteArrayLiteral("POST"),
                      QJsonDocument(body).toJson(QJsonDocument::Compact),
                      providerId);
}

quint64 LiveApiClient::updateAdminDestinationRule(const QString &providerId,
                                                  const QString &ruleId,
                                                  qint64 expectedRevision,
                                                  const QVariantMap &rule,
                                                  quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/providers");
  QJsonObject body;
  if (!validUuid(providerId) || !validUuid(ruleId) || expectedRevision < 1 ||
      !validDestinationDraft(rule, &body)) {
    return invalidAdminRequest(
        QStringLiteral("destinationRuleUpdate"), base, generation,
        QStringLiteral("Live destination rule is invalid."));
  }
  body.insert(QStringLiteral("expectedRevision"), expectedRevision);
  const QString endpoint =
      QStringLiteral("%1/%2/destination-rules/%3")
          .arg(base, encodePathSegment(providerId), encodePathSegment(ruleId));
  return enqueueAdmin(QStringLiteral("destinationRuleUpdate"), endpoint,
                      generation, QByteArrayLiteral("PUT"),
                      QJsonDocument(body).toJson(QJsonDocument::Compact),
                      providerId, ruleId);
}

quint64 LiveApiClient::deleteAdminDestinationRule(const QString &providerId,
                                                  const QString &ruleId,
                                                  qint64 expectedRevision,
                                                  quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/providers");
  if (!validUuid(providerId) || !validUuid(ruleId) || expectedRevision < 1) {
    return invalidAdminRequest(
        QStringLiteral("destinationRuleDelete"), base, generation,
        QStringLiteral("Live destination rule identity is invalid."));
  }
  const QJsonObject body{
      {QStringLiteral("expectedRevision"), expectedRevision}};
  const QString endpoint =
      QStringLiteral("%1/%2/destination-rules/%3")
          .arg(base, encodePathSegment(providerId), encodePathSegment(ruleId));
  return enqueueAdmin(QStringLiteral("destinationRuleDelete"), endpoint,
                      generation, QByteArrayLiteral("DELETE"),
                      QJsonDocument(body).toJson(QJsonDocument::Compact),
                      providerId, ruleId);
}

quint64 LiveApiClient::disableAdminProvider(const QString &providerId,
                                            qint64 expectedRevision,
                                            quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/providers");
  if (!validUuid(providerId) || expectedRevision < 1) {
    return invalidAdminRequest(QStringLiteral("providerDisable"), base,
                               generation,
                               QStringLiteral("Live provider is invalid."));
  }
  const QJsonObject body{
      {QStringLiteral("expectedRevision"), expectedRevision}};
  return enqueueAdmin(
      QStringLiteral("providerDisable"),
      QStringLiteral("%1/%2/disable").arg(base, encodePathSegment(providerId)),
      generation, QByteArrayLiteral("POST"),
      QJsonDocument(body).toJson(QJsonDocument::Compact), providerId);
}

quint64 LiveApiClient::setAdminProviderGrant(const QString &providerId,
                                             const QString &profileId,
                                             bool canBrowse, bool canPlay,
                                             qint64 expectedRevision,
                                             quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/providers");
  if (!validUuid(providerId) || !validUuid(profileId) || expectedRevision < 1 ||
      (!canBrowse && canPlay)) {
    return invalidAdminRequest(
        QStringLiteral("grantSet"), base, generation,
        QStringLiteral("Live provider grant is invalid."));
  }
  const QJsonObject body{
      {QStringLiteral("canBrowse"), canBrowse},
      {QStringLiteral("canPlay"), canPlay},
      {QStringLiteral("expectedRevision"), expectedRevision}};
  const QString endpoint = QStringLiteral("%1/%2/grants/%3")
                               .arg(base, encodePathSegment(providerId),
                                    encodePathSegment(profileId));
  return enqueueAdmin(QStringLiteral("grantSet"), endpoint, generation,
                      QByteArrayLiteral("PUT"),
                      QJsonDocument(body).toJson(QJsonDocument::Compact),
                      providerId, profileId);
}

quint64 LiveApiClient::revokeAdminProviderGrant(const QString &providerId,
                                                const QString &profileId,
                                                qint64 expectedRevision,
                                                quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/providers");
  if (!validUuid(providerId) || !validUuid(profileId) || expectedRevision < 1) {
    return invalidAdminRequest(
        QStringLiteral("grantRevoke"), base, generation,
        QStringLiteral("Live provider grant identity is invalid."));
  }
  const QJsonObject body{
      {QStringLiteral("expectedRevision"), expectedRevision}};
  const QString endpoint = QStringLiteral("%1/%2/grants/%3")
                               .arg(base, encodePathSegment(providerId),
                                    encodePathSegment(profileId));
  return enqueueAdmin(QStringLiteral("grantRevoke"), endpoint, generation,
                      QByteArrayLiteral("DELETE"),
                      QJsonDocument(body).toJson(QJsonDocument::Compact),
                      providerId, profileId);
}

quint64 LiveApiClient::terminateAdminSession(const QString &sessionId,
                                             qint64 expectedRevision,
                                             quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/sessions");
  if (!validUuid(sessionId) || expectedRevision < 1) {
    return invalidAdminRequest(
        QStringLiteral("sessionTerminate"), base, generation,
        QStringLiteral("Live session identity is invalid."));
  }
  const QJsonObject body{
      {QStringLiteral("expectedRevision"), expectedRevision}};
  return enqueueAdmin(
      QStringLiteral("sessionTerminate"),
      QStringLiteral("%1/%2/terminate").arg(base, encodePathSegment(sessionId)),
      generation, QByteArrayLiteral("POST"),
      QJsonDocument(body).toJson(QJsonDocument::Compact), sessionId);
}

quint64 LiveApiClient::rotateAdminKey(const QString &keyDomain,
                                      const QString &keyId,
                                      qint64 expectedRevision,
                                      quint64 generation) {
  const QString base = QStringLiteral("/api/v1/live/admin/keys");
  if (!QSet<QString>{QStringLiteral("envelope"), QStringLiteral("token_hash"),
                     QStringLiteral("audit")}
           .contains(keyDomain) ||
      !validKeyId(keyId) || expectedRevision < 1) {
    return invalidAdminRequest(QStringLiteral("keyRotate:%1").arg(keyDomain),
                               base, generation,
                               QStringLiteral("Live key rotation is invalid."));
  }
  const QJsonObject body{{QStringLiteral("expectedRevision"), expectedRevision},
                         {QStringLiteral("keyId"), keyId}};
  const QString routeDomain = keyDomain == QStringLiteral("token_hash")
                                  ? QStringLiteral("token-hash")
                                  : keyDomain;
  return enqueueAdmin(
      QStringLiteral("keyRotate:%1").arg(keyDomain),
      QStringLiteral("%1/%2/rotate").arg(base, encodePathSegment(routeDomain)),
      generation, QByteArrayLiteral("POST"),
      QJsonDocument(body).toJson(QJsonDocument::Compact), keyId);
}

void LiveApiClient::cancel(quint64 requestId) {
  if (!m_generations.contains(requestId)) {
    return;
  }
  const quint64 generation = m_generations.value(requestId);
  m_cancelled.insert(requestId);
  for (auto iterator = m_authQueue.begin(); iterator != m_authQueue.end();) {
    if (iterator->id == requestId) {
      iterator = m_authQueue.erase(iterator);
    } else {
      ++iterator;
    }
  }
  const QPointer<QNetworkReply> reply = m_replies.value(requestId);
  if (reply) {
    reply->abort();
    return;
  }
  m_generations.remove(requestId);
  m_cancelled.remove(requestId);
  emit requestCancelled(requestId, generation);
}

void LiveApiClient::cancelAll() {
  const QList<quint64> requestIds = m_generations.keys();
  for (const quint64 requestId : requestIds) {
    cancel(requestId);
  }
}

quint64 LiveApiClient::enqueue(RequestKind kind, const QString &endpoint,
                               quint64 generation, QByteArray method,
                               QByteArray body, QByteArray idempotencyKey,
                               QString sessionId, QString adminOperation,
                               QString adminSubjectId,
                               QString adminSecondaryId) {
  const quint64 id = m_nextRequestId++;
  m_generations.insert(id, generation);
  Request request{id,
                  generation,
                  kind,
                  endpoint,
                  0,
                  std::move(method),
                  std::move(body),
                  std::move(idempotencyKey),
                  std::move(sessionId),
                  std::move(adminOperation),
                  std::move(adminSubjectId),
                  std::move(adminSecondaryId)};
  if (endpoint.isEmpty()) {
    return id;
  }
  if (!m_authClient) {
    QMetaObject::invokeMethod(
        this,
        [this, request]() {
          if (m_generations.contains(request.id)) {
            fail(request, QStringLiteral("LIVE_CLIENT_AUTH_UNAVAILABLE"),
                 QStringLiteral("Authentication is unavailable."));
          }
        },
        Qt::QueuedConnection);
    return id;
  }
  if (m_authClient->authToken().isEmpty()) {
    QMetaObject::invokeMethod(
        this,
        [this, request]() {
          if (m_generations.contains(request.id)) {
            fail(request, QStringLiteral("LIVE_AUTH_REQUIRED"),
                 QStringLiteral("Sign in to browse Live content."));
          }
        },
        Qt::QueuedConnection);
    return id;
  }
  if (m_authClient->hasRefreshToken() &&
      m_authClient->accessTokenNearExpiry()) {
    queueForAuthRefresh(std::move(request));
  } else {
    dispatch(std::move(request));
  }
  return id;
}

quint64 LiveApiClient::enqueueAdmin(const QString &operation,
                                    const QString &endpoint, quint64 generation,
                                    QByteArray method, QByteArray body,
                                    QString subjectId, QString secondaryId) {
  return enqueue(RequestKind::Admin, endpoint, generation, std::move(method),
                 std::move(body), {}, {}, operation, std::move(subjectId),
                 std::move(secondaryId));
}

quint64 LiveApiClient::invalidAdminRequest(const QString &operation,
                                           const QString &endpoint,
                                           quint64 generation,
                                           const QString &message) {
  const quint64 requestId =
      enqueueAdmin(operation, QString(), generation, QByteArrayLiteral("GET"));
  QMetaObject::invokeMethod(
      this,
      [this, requestId, generation, operation, endpoint, message]() {
        if (!m_generations.contains(requestId)) {
          return;
        }
        Request request =
            requestShell(requestId, generation, RequestKind::Admin, endpoint);
        request.adminOperation = operation;
        fail(request, QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"), message);
      },
      Qt::QueuedConnection);
  return requestId;
}

void LiveApiClient::dispatch(Request request) {
  if (!m_authClient || !m_generations.contains(request.id) ||
      m_cancelled.contains(request.id)) {
    return;
  }
  QUrl base(m_authClient->baseUrl());
  const QString scheme = base.scheme().toLower();
  if (!base.isValid() ||
      (scheme != QStringLiteral("http") && scheme != QStringLiteral("https")) ||
      base.host().isEmpty() || !base.userInfo().isEmpty()) {
    fail(request, QStringLiteral("LIVE_CLIENT_BASE_URL_INVALID"),
         QStringLiteral("The server URL is invalid."));
    return;
  }
  base.setPath(QStringLiteral("/"));
  base.setQuery(QString());
  base.setFragment(QString());
  const QUrl url = base.resolved(QUrl(request.endpoint));
  if (!url.isValid() || url.scheme().toLower() != scheme ||
      url.host().compare(base.host(), Qt::CaseInsensitive) != 0 ||
      url.port(base.port(-1)) != base.port(-1)) {
    fail(request, QStringLiteral("LIVE_CLIENT_ENDPOINT_INVALID"),
         QStringLiteral("The Live endpoint is invalid."));
    return;
  }

  QNetworkRequest networkRequest(url);
  networkRequest.setRawHeader("Accept", "application/json");
  networkRequest.setRawHeader("Authorization",
                              QByteArrayLiteral("Bearer ") +
                                  m_authClient->authToken().toUtf8());
  if (!request.idempotencyKey.isEmpty()) {
    networkRequest.setRawHeader("Idempotency-Key", request.idempotencyKey);
  }
  const QString locale = QLocale::system().name().replace('_', '-');
  if (!locale.isEmpty()) {
    networkRequest.setRawHeader("Accept-Language", locale.toUtf8());
  }
  networkRequest.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                              QNetworkRequest::ManualRedirectPolicy);
  networkRequest.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                              QNetworkRequest::AlwaysNetwork);
  networkRequest.setTransferTimeout(15'000);

  QNetworkReply *reply = nullptr;
  if (request.method == QByteArrayLiteral("GET")) {
    reply = m_networkManager->get(networkRequest);
  } else if (request.method == QByteArrayLiteral("POST")) {
    networkRequest.setHeader(QNetworkRequest::ContentTypeHeader,
                             QStringLiteral("application/json"));
    reply = m_networkManager->post(networkRequest, request.body);
  } else if (request.method == QByteArrayLiteral("PUT")) {
    networkRequest.setHeader(QNetworkRequest::ContentTypeHeader,
                             QStringLiteral("application/json"));
    reply = m_networkManager->put(networkRequest, request.body);
  } else if (request.method == QByteArrayLiteral("DELETE")) {
    if (!request.body.isEmpty()) {
      networkRequest.setHeader(QNetworkRequest::ContentTypeHeader,
                               QStringLiteral("application/json"));
    }
    reply = m_networkManager->sendCustomRequest(
        networkRequest, QByteArrayLiteral("DELETE"), request.body);
  } else {
    fail(request, QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"),
         QStringLiteral("The Live HTTP method is invalid."));
    return;
  }
  m_replies.insert(request.id, reply);
  const auto buffer = QSharedPointer<ResponseBuffer>::create();
  const auto enforceDeclaredSize = [reply, buffer]() {
    bool valid = false;
    const qint64 length =
        reply->header(QNetworkRequest::ContentLengthHeader).toLongLong(&valid);
    if (valid && length > kMaximumResponseBytes && !buffer->oversize) {
      buffer->bytes.clear();
      buffer->oversize = true;
      reply->abort();
    }
  };
  connect(reply, &QNetworkReply::metaDataChanged, this, enforceDeclaredSize);
  connect(reply, &QIODevice::readyRead, this,
          [reply, buffer]() { drainReply(reply, buffer); });
  connect(reply, &QNetworkReply::finished, this,
          [this, reply, request, buffer]() {
            drainReply(reply, buffer);
            m_replies.remove(request.id);
            complete(reply, request, buffer->bytes, buffer->oversize);
            reply->deleteLater();
          });
}

void LiveApiClient::queueForAuthRefresh(Request request) {
  if (!m_authClient || !m_authClient->hasRefreshToken()) {
    fail(request, QStringLiteral("LIVE_AUTH_REQUIRED"),
         QStringLiteral("The Live session cannot be refreshed."));
    return;
  }
  if (m_authQueue.size() >= kMaximumAuthQueue) {
    fail(request, QStringLiteral("LIVE_CLIENT_AUTH_QUEUE_FULL"),
         QStringLiteral(
             "Too many Live requests are waiting for authentication."),
         true);
    return;
  }
  m_authQueue.append(std::move(request));
  if (!m_authClient->refreshInFlight()) {
    m_authClient->refreshAuth();
  }
}

void LiveApiClient::drainAuthQueue() {
  if (!m_authClient || m_authClient->refreshInFlight() ||
      m_authQueue.isEmpty()) {
    return;
  }
  QList<Request> requests = std::move(m_authQueue);
  m_authQueue.clear();
  if (m_authClient->authToken().isEmpty()) {
    for (const Request &request : requests) {
      if (m_generations.contains(request.id)) {
        fail(request, QStringLiteral("LIVE_AUTH_REQUIRED"),
             QStringLiteral("The Live session refresh failed."));
      }
    }
    return;
  }
  for (Request &request : requests) {
    dispatch(std::move(request));
  }
}

void LiveApiClient::complete(QNetworkReply *reply, const Request &request,
                             const QByteArray &payload, bool oversize) {
  if (!m_generations.contains(request.id)) {
    return;
  }
  if (m_cancelled.remove(request.id)) {
    m_generations.remove(request.id);
    emit requestCancelled(request.id, request.generation);
    return;
  }
  if (oversize) {
    fail(request, QStringLiteral("LIVE_CLIENT_RESPONSE_TOO_LARGE"),
         QStringLiteral("The Live response exceeded the client limit."));
    return;
  }
  const int status =
      reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
  if (status == 401 && request.authRetryCount == 0 && m_authClient &&
      m_authClient->hasRefreshToken()) {
    Request retry = request;
    retry.authRetryCount = 1;
    queueForAuthRefresh(std::move(retry));
    return;
  }
  if (reply->error() != QNetworkReply::NoError || status < 200 ||
      status >= 300) {
    QJsonParseError parseError;
    const QJsonDocument document =
        QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error == QJsonParseError::NoError) {
      const auto parsed = Live::parseError(document);
      if (parsed && !parsed.value->errors.isEmpty()) {
        const Live::ApiError &apiError = parsed.value->errors.first();
        m_generations.remove(request.id);
        emit requestFailed(request.id, request.generation, request.endpoint,
                           apiError.toVariantMap());
        return;
      }
    }
    const QString message =
        reply->error() == QNetworkReply::NoError
            ? QStringLiteral("The Live request failed with HTTP %1.")
                  .arg(status)
            : QStringLiteral("The Live request could not be completed.");
    fail(request, QStringLiteral("LIVE_CLIENT_NETWORK"), message, true);
    return;
  }
  if (request.kind == RequestKind::SessionEnd) {
    if (status != 204 || !payload.isEmpty()) {
      fail(request, QStringLiteral("LIVE_CLIENT_CONTRACT_INVALID"),
           QStringLiteral("The Live end response was invalid."));
      return;
    }
    m_generations.remove(request.id);
    emit sessionEnded(request.id, request.generation, request.sessionId);
    return;
  }
  const QByteArray contentType =
      reply->header(QNetworkRequest::ContentTypeHeader).toByteArray().toLower();
  if (!contentType.startsWith("application/json")) {
    fail(
        request, QStringLiteral("LIVE_CLIENT_CONTRACT_INVALID"),
        QStringLiteral("The Live server returned an unexpected content type."));
    return;
  }
  QJsonParseError parseError;
  const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
  if (parseError.error != QJsonParseError::NoError) {
    fail(request, QStringLiteral("LIVE_CLIENT_CONTRACT_INVALID"),
         QStringLiteral("The Live server returned invalid JSON."));
    return;
  }

  QString contractError;
  switch (request.kind) {
  case RequestKind::Providers: {
    auto parsed = Live::parseProviders(document);
    if (parsed) {
      m_generations.remove(request.id);
      emit providersReceived(request.id, request.generation, *parsed.value);
      return;
    }
    contractError = parsed.error;
    break;
  }
  case RequestKind::Catalogs: {
    auto parsed = Live::parseCatalogs(document);
    if (parsed) {
      m_generations.remove(request.id);
      emit catalogsReceived(request.id, request.generation, *parsed.value);
      return;
    }
    contractError = parsed.error;
    break;
  }
  case RequestKind::CatalogPage: {
    auto parsed = Live::parseCatalogPage(document);
    if (parsed) {
      m_generations.remove(request.id);
      emit catalogPageReceived(request.id, request.generation, *parsed.value);
      return;
    }
    contractError = parsed.error;
    break;
  }
  case RequestKind::Item: {
    auto parsed = Live::parseItem(document);
    if (parsed) {
      m_generations.remove(request.id);
      emit itemReceived(request.id, request.generation, *parsed.value);
      return;
    }
    contractError = parsed.error;
    break;
  }
  case RequestKind::SessionCreate: {
    auto parsed = Live::parseSessionCreated(document);
    if (parsed) {
      m_generations.remove(request.id);
      emit sessionCreated(request.id, request.generation, *parsed.value);
      eraseSessionToken(&*parsed.value);
      return;
    }
    contractError = parsed.error;
    break;
  }
  case RequestKind::SessionGet:
  case RequestKind::SessionHeartbeat: {
    auto parsed = Live::parseSessionDetail(document);
    if (parsed && parsed.value->data.sessionId == request.sessionId) {
      m_generations.remove(request.id);
      emit sessionDetailReceived(request.id, request.generation, *parsed.value);
      return;
    }
    contractError =
        parsed ? QStringLiteral("Live session id mismatch.") : parsed.error;
    break;
  }
  case RequestKind::SessionRecovery: {
    auto parsed = Live::parseSessionCreated(document);
    if (parsed && parsed.value->sessionId == request.sessionId) {
      m_generations.remove(request.id);
      emit sessionRecovered(request.id, request.generation, *parsed.value);
      eraseSessionToken(&*parsed.value);
      return;
    }
    if (parsed) {
      eraseSessionToken(&*parsed.value);
    }
    contractError =
        parsed ? QStringLiteral("Live session id mismatch.") : parsed.error;
    break;
  }
  case RequestKind::SessionEnd:
    contractError = QStringLiteral("Unexpected Live end response.");
    break;
  case RequestKind::Admin: {
    QVariant data;
    if (validAdminEnvelope(document, request.adminOperation,
                           request.adminSubjectId, request.adminSecondaryId,
                           &data, &contractError)) {
      m_generations.remove(request.id);
      emit adminResponseReceived(request.id, request.generation,
                                 request.adminOperation, data);
      return;
    }
    break;
  }
  }
  fail(request, QStringLiteral("LIVE_CLIENT_CONTRACT_INVALID"),
       contractError.isEmpty()
           ? QStringLiteral("The Live response did not match the contract.")
           : contractError);
}

void LiveApiClient::fail(const Request &request, const QString &code,
                         const QString &message, bool retryable,
                         int retryAfterSeconds) {
  m_replies.remove(request.id);
  m_generations.remove(request.id);
  m_cancelled.remove(request.id);
  emit requestFailed(request.id, request.generation, request.endpoint,
                     localError(code, message, retryable, retryAfterSeconds));
}

void LiveApiClient::authContextChanged() {
  const QString next = authContextKey();
  if (next == m_authContextKey) {
    return;
  }
  cancelAll();
  m_authContextKey = next;
  emit authContextInvalidated();
}

QString LiveApiClient::authContextKey() const {
  if (!m_authClient) {
    return {};
  }
  return QStringLiteral("%1\n%2\n%3\n%4")
      .arg(m_authClient->baseUrl(), m_authClient->sessionId(),
           m_authClient->activeProfileId(),
           QString::number(m_authClient->capabilityRevision()));
}

QString LiveApiClient::endpointForCatalogPage(const QString &providerId,
                                              const QString &catalogId,
                                              const QVariantMap &filters,
                                              const QString &cursor, int limit,
                                              QString *error) const {
  static const QRegularExpression idPattern(
      QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._~-]{0,127}$"));
  if (!validUuid(providerId)) {
    *error = QStringLiteral("Provider id is invalid.");
    return {};
  }
  if (!idPattern.match(catalogId).hasMatch()) {
    *error = QStringLiteral("Catalog id is invalid.");
    return {};
  }
  if (limit < 1 || limit > 100 || filters.size() > 12 || cursor.size() > 2048) {
    *error = QStringLiteral("Catalog query bounds are invalid.");
    return {};
  }
  QUrlQuery query;
  query.addQueryItem(QStringLiteral("limit"), QString::number(limit));
  if (!cursor.isEmpty()) {
    query.addQueryItem(QStringLiteral("cursor"), cursor);
  }
  QStringList keys = filters.keys();
  std::sort(keys.begin(), keys.end());
  for (const QString &key : keys) {
    if (!idPattern.match(key).hasMatch()) {
      *error = QStringLiteral("A filter id is invalid.");
      return {};
    }
    const QString queryKey = QStringLiteral("filters[%1]").arg(key);
    const QVariant value = filters.value(key);
    QStringList values;
    if (value.metaType().id() == QMetaType::QStringList) {
      values = value.toStringList();
    } else if (value.metaType().id() == QMetaType::QVariantList) {
      const QVariantList list = value.toList();
      if (list.size() > 200) {
        *error = QStringLiteral("A filter has too many values.");
        return {};
      }
      for (const QVariant &entry : list) {
        if (entry.metaType().id() != QMetaType::QString) {
          *error =
              QStringLiteral("A filter list contains an unsupported value.");
          return {};
        }
        values.append(entry.toString());
      }
    } else if (value.metaType().id() == QMetaType::Bool) {
      values.append(value.toBool() ? QStringLiteral("true")
                                   : QStringLiteral("false"));
    } else if (value.metaType().id() == QMetaType::QString) {
      values.append(value.toString());
    } else {
      *error = QStringLiteral("A filter has an unsupported value type.");
      return {};
    }
    for (const QString &entry : values) {
      if (entry.size() > 512) {
        *error = QStringLiteral("A filter value is too long.");
        return {};
      }
      query.addQueryItem(queryKey, entry);
    }
  }
  const QString endpoint =
      QStringLiteral("/api/v1/live/catalogs/%1/%2/items?%3")
          .arg(encodePathSegment(providerId), encodePathSegment(catalogId),
               query.query(QUrl::FullyEncoded));
  if (endpoint.size() > 8192) {
    *error = QStringLiteral("The catalog query is too large.");
    return {};
  }
  return endpoint;
}

QString LiveApiClient::encodePathSegment(const QString &value) {
  return QString::fromLatin1(QUrl::toPercentEncoding(value));
}
