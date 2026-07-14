#pragma once

#include "LiveTypes.h"

#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QVariantMap>

class ApiClient;
class QNetworkReply;

class LiveApiClient final : public QObject {
  Q_OBJECT

public:
  explicit LiveApiClient(ApiClient *authClient, QObject *parent = nullptr);
  LiveApiClient(ApiClient *authClient, QNetworkAccessManager *networkManager,
                QObject *parent = nullptr);

  [[nodiscard]] QString serverBaseUrl() const;
  [[nodiscard]] QString accountSessionId() const;

  [[nodiscard]] quint64 listProviders(quint64 generation);
  [[nodiscard]] quint64 listCatalogs(quint64 generation);
  [[nodiscard]] quint64 listCatalogItems(const QString &providerId,
                                         const QString &catalogId,
                                         const QVariantMap &filters,
                                         const QString &cursor, int limit,
                                         quint64 generation);
  [[nodiscard]] quint64 getItem(const QString &providerId,
                                const QString &itemKey, quint64 generation);
  [[nodiscard]] quint64 createSession(const QString &providerId,
                                      const QString &itemKey,
                                      const QString &streamOptionKey,
                                      const QVariantMap &clientCapabilities,
                                      const QString &idempotencyKey,
                                      quint64 generation);
  [[nodiscard]] quint64 getSession(const QString &sessionId,
                                   quint64 generation);
  [[nodiscard]] quint64 heartbeatSession(const QString &sessionId,
                                         qint64 expectedRevision,
                                         const QVariantMap &observation,
                                         quint64 generation);
  [[nodiscard]] quint64 refreshSession(const QString &sessionId,
                                       qint64 expectedRevision,
                                       const QString &reason,
                                       quint64 generation);
  [[nodiscard]] quint64 failoverSession(const QString &sessionId,
                                        qint64 expectedRevision,
                                        const QString &reason,
                                        const QString &requestedSourceKey,
                                        quint64 generation);
  [[nodiscard]] quint64 endSession(const QString &sessionId,
                                   qint64 expectedRevision, quint64 generation);

  Q_INVOKABLE quint64 listAdminProviders(quint64 generation);
  Q_INVOKABLE quint64 listAdminSessions(quint64 generation);
  Q_INVOKABLE quint64 getAdminKeyState(quint64 generation);
  Q_INVOKABLE quint64 listAdminDestinationRules(const QString &providerId,
                                                quint64 generation);
  Q_INVOKABLE quint64 createAdminDestinationRule(
      const QString &providerId, qint64 expectedProviderRevision,
      const QVariantMap &rule, quint64 generation);
  Q_INVOKABLE quint64 updateAdminDestinationRule(const QString &providerId,
                                                 const QString &ruleId,
                                                 qint64 expectedRevision,
                                                 const QVariantMap &rule,
                                                 quint64 generation);
  Q_INVOKABLE quint64 deleteAdminDestinationRule(const QString &providerId,
                                                 const QString &ruleId,
                                                 qint64 expectedRevision,
                                                 quint64 generation);
  Q_INVOKABLE quint64 disableAdminProvider(const QString &providerId,
                                           qint64 expectedRevision,
                                           quint64 generation);
  Q_INVOKABLE quint64 setAdminProviderGrant(const QString &providerId,
                                            const QString &profileId,
                                            bool canBrowse, bool canPlay,
                                            qint64 expectedRevision,
                                            quint64 generation);
  Q_INVOKABLE quint64 revokeAdminProviderGrant(const QString &providerId,
                                               const QString &profileId,
                                               qint64 expectedRevision,
                                               quint64 generation);
  Q_INVOKABLE quint64 terminateAdminSession(const QString &sessionId,
                                            qint64 expectedRevision,
                                            quint64 generation);
  Q_INVOKABLE quint64 rotateAdminKey(const QString &keyDomain,
                                     const QString &keyId,
                                     qint64 expectedRevision,
                                     quint64 generation);

  Q_INVOKABLE void cancel(quint64 requestId);
  Q_INVOKABLE void cancelAll();

signals:
  void providersReceived(quint64 requestId, quint64 generation,
                         const Live::ProvidersEnvelope &envelope);
  void catalogsReceived(quint64 requestId, quint64 generation,
                        const Live::CatalogsEnvelope &envelope);
  void catalogPageReceived(quint64 requestId, quint64 generation,
                           const Live::CatalogPageEnvelope &envelope);
  void itemReceived(quint64 requestId, quint64 generation,
                    const Live::ItemEnvelope &envelope);
  void sessionCreated(quint64 requestId, quint64 generation,
                      const Live::SessionCreated &session);
  void sessionDetailReceived(quint64 requestId, quint64 generation,
                             const Live::SessionDetailEnvelope &envelope);
  void sessionRecovered(quint64 requestId, quint64 generation,
                        const Live::SessionCreated &session);
  void sessionEnded(quint64 requestId, quint64 generation,
                    const QString &sessionId);
  void adminResponseReceived(quint64 requestId, quint64 generation,
                             const QString &operation, const QVariant &data);
  void requestFailed(quint64 requestId, quint64 generation,
                     const QString &endpoint, const QVariantMap &error);
  void requestCancelled(quint64 requestId, quint64 generation);
  void authContextInvalidated();

private:
  enum class RequestKind {
    Providers,
    Catalogs,
    CatalogPage,
    Item,
    SessionCreate,
    SessionGet,
    SessionHeartbeat,
    SessionRecovery,
    SessionEnd,
    Admin
  };

  struct Request {
    quint64 id{0};
    quint64 generation{0};
    RequestKind kind{RequestKind::Providers};
    QString endpoint;
    int authRetryCount{0};
    QByteArray method{QByteArrayLiteral("GET")};
    QByteArray body;
    QByteArray idempotencyKey;
    QString sessionId;
    QString adminOperation;
    QString adminSubjectId;
    QString adminSecondaryId;
  };

  [[nodiscard]] static Request requestShell(quint64 id, quint64 generation,
                                            RequestKind kind,
                                            const QString &endpoint);

  [[nodiscard]] quint64
  enqueue(RequestKind kind, const QString &endpoint, quint64 generation,
          QByteArray method = QByteArrayLiteral("GET"), QByteArray body = {},
          QByteArray idempotencyKey = {}, QString sessionId = {},
          QString adminOperation = {}, QString adminSubjectId = {},
          QString adminSecondaryId = {});
  [[nodiscard]] quint64
  enqueueAdmin(const QString &operation, const QString &endpoint,
               quint64 generation, QByteArray method = QByteArrayLiteral("GET"),
               QByteArray body = {}, QString subjectId = {},
               QString secondaryId = {});
  [[nodiscard]] quint64 invalidAdminRequest(const QString &operation,
                                            const QString &endpoint,
                                            quint64 generation,
                                            const QString &message);
  [[nodiscard]] quint64 recoverSession(const QString &sessionId,
                                       qint64 expectedRevision,
                                       const QString &reason,
                                       const QString &requestedSourceKey,
                                       bool failover, quint64 generation);
  void dispatch(Request request);
  void queueForAuthRefresh(Request request);
  void drainAuthQueue();
  void complete(QNetworkReply *reply, const Request &request,
                const QByteArray &payload, bool oversize);
  void fail(const Request &request, const QString &code, const QString &message,
            bool retryable = false, int retryAfterSeconds = 0);
  void authContextChanged();
  [[nodiscard]] QString authContextKey() const;
  [[nodiscard]] QString endpointForCatalogPage(const QString &providerId,
                                               const QString &catalogId,
                                               const QVariantMap &filters,
                                               const QString &cursor, int limit,
                                               QString *error) const;
  [[nodiscard]] static QString encodePathSegment(const QString &value);

  ApiClient *m_authClient{nullptr};
  QNetworkAccessManager m_ownedNetworkManager;
  QNetworkAccessManager *m_networkManager{nullptr};
  quint64 m_nextRequestId{1};
  QString m_authContextKey;
  QList<Request> m_authQueue;
  QHash<quint64, QPointer<QNetworkReply>> m_replies;
  QHash<quint64, quint64> m_generations;
  QSet<quint64> m_cancelled;
};
