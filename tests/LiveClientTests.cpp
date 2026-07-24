#include "backend/ApiClient.h"
#include "live/LiveApiClient.h"
#include "live/LiveCatalogModel.h"
#include "live/LiveQmlNetworkAccessManagerFactory.h"
#include "live/LiveTypes.h"
#include "support/DeterministicScheduler.h"
#include "support/ScriptedNetworkAccessManager.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTest>
#include <QTimeZone>

namespace {

const QString kProviderId =
    QStringLiteral("0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d");
const QString kInstanceId =
    QStringLiteral("a7fbc769-ef8b-4220-a7da-93c58e329091");
const QString kProfileId =
    QStringLiteral("56bb1365-f71d-4a09-88aa-754f37cad251");
const QString kSessionId =
    QStringLiteral("7858b2ee-753e-42d1-9a34-2fa5c9564ea4");
const QString kRuleId = QStringLiteral("36435ae8-da34-4728-9058-369e1574b785");

QJsonObject meta(const QString &cacheState = QStringLiteral("fresh"),
                 bool partial = false) {
  return {
      {QStringLiteral("requestId"),
       QStringLiteral("01J2H3D5W6Y7Z8A9B0C1D2E3F4")},
      {QStringLiteral("generatedAt"), QStringLiteral("2026-07-10T20:00:00Z")},
      {QStringLiteral("cacheState"), cacheState},
      {QStringLiteral("partial"), partial},
  };
}

QJsonObject
item(const QString &title = QStringLiteral("Home vs Away"),
     const QString &startsAt = QStringLiteral("2026-07-10T20:00:00Z"),
     const QString &itemKey = QStringLiteral("lvk1.item.fixture-key-value")) {
  return {
      {QStringLiteral("providerId"), kProviderId},
      {QStringLiteral("itemKey"), itemKey},
      {QStringLiteral("itemType"), QStringLiteral("event")},
      {QStringLiteral("title"), title},
      {QStringLiteral("subtitle"), QStringLiteral("League")},
      {QStringLiteral("description"),
       QStringLiteral("Provider-defined plain text.")},
      {QStringLiteral("status"), QStringLiteral("live")},
      {QStringLiteral("startsAt"), startsAt},
      {QStringLiteral("endsAt"), QStringLiteral("2026-07-10T22:00:00Z")},
      {QStringLiteral("poster"),
       QJsonObject{
           {QStringLiteral("artworkId"),
            QStringLiteral("lvk1.artwork.poster-fixture")},
           {QStringLiteral("url"),
            QStringLiteral("/api/v1/live/artwork/lvk1.artwork.poster-fixture")},
           {QStringLiteral("kind"), QStringLiteral("poster")},
       }},
      {QStringLiteral("background"), QJsonValue::Null},
      {QStringLiteral("logo"), QJsonValue::Null},
      {QStringLiteral("categories"), QJsonArray{QStringLiteral("Football")}},
      {QStringLiteral("badges"), QJsonArray{QStringLiteral("Live")}},
      {QStringLiteral("facts"),
       QJsonArray{QJsonObject{
           {QStringLiteral("label"), QStringLiteral("Commentary")},
           {QStringLiteral("value"), QStringLiteral("English")},
       }}},
  };
}

QByteArray providersEnvelope() {
  return QJsonDocument(
             QJsonObject{
                 {QStringLiteral("data"),
                  QJsonArray{QJsonObject{
                      {QStringLiteral("providerId"), kProviderId},
                      {QStringLiteral("instanceId"), kInstanceId},
                      {QStringLiteral("extensionId"),
                       QStringLiteral("sports.fixture")},
                      {QStringLiteral("name"),
                       QStringLiteral("Fixture Sports")},
                      {QStringLiteral("readiness"), QStringLiteral("ready")},
                      {QStringLiteral("accountState"),
                       QStringLiteral("not_required")},
                      {QStringLiteral("disabledReason"), QJsonValue::Null},
                      {QStringLiteral("contractVersion"), 1},
                      {QStringLiteral("itemTypes"),
                       QJsonArray{QStringLiteral("event")}},
                      {QStringLiteral("protocols"),
                       QJsonArray{QStringLiteral("hls")}},
                  }}},
                 {QStringLiteral("meta"), meta()},
                 {QStringLiteral("errors"), QJsonArray{}},
             })
      .toJson(QJsonDocument::Compact);
}

QByteArray catalogsEnvelope() {
  return QJsonDocument(
             QJsonObject{
                 {QStringLiteral("data"),
                  QJsonArray{QJsonObject{
                      {QStringLiteral("providerId"), kProviderId},
                      {QStringLiteral("catalogId"),
                       QStringLiteral("live_events")},
                      {QStringLiteral("name"), QStringLiteral("Live Now")},
                      {QStringLiteral("description"), QJsonValue::Null},
                      {QStringLiteral("itemTypes"),
                       QJsonArray{QStringLiteral("event")}},
                      {QStringLiteral("presentation"),
                       QStringLiteral("landscape")},
                      {QStringLiteral("order"), 10},
                      {QStringLiteral("filters"),
                       QJsonArray{QJsonObject{
                           {QStringLiteral("id"), QStringLiteral("category")},
                           {QStringLiteral("label"),
                            QStringLiteral("Category")},
                           {QStringLiteral("type"),
                            QStringLiteral("multi_select")},
                           {QStringLiteral("required"), false},
                           {QStringLiteral("options"),
                            QJsonArray{QJsonObject{
                                {QStringLiteral("value"),
                                 QStringLiteral("football")},
                                {QStringLiteral("label"),
                                 QStringLiteral("Football")},
                            }}},
                       }}},
                  }}},
                 {QStringLiteral("meta"), meta()},
                 {QStringLiteral("errors"), QJsonArray{}},
             })
      .toJson(QJsonDocument::Compact);
}

QByteArray pageEnvelope(
    const QString &title, const QJsonValue &nextCursor = QJsonValue::Null,
    const QString &startsAt = QStringLiteral("2026-07-10T20:00:00Z"),
    const QString &itemKey = QStringLiteral("lvk1.item.fixture-key-value")) {
  return QJsonDocument(QJsonObject{
                           {QStringLiteral("data"),
                            QJsonObject{
                                {QStringLiteral("providerId"), kProviderId},
                                {QStringLiteral("catalogId"),
                                 QStringLiteral("live_events")},
                                {QStringLiteral("items"),
                                 QJsonArray{item(title, startsAt, itemKey)}},
                                {QStringLiteral("nextCursor"), nextCursor},
                            }},
                           {QStringLiteral("meta"), meta()},
                           {QStringLiteral("errors"), QJsonArray{}},
                       })
      .toJson(QJsonDocument::Compact);
}

QByteArray emptyPageEnvelope(const QString &cacheState) {
  return QJsonDocument(
             QJsonObject{
                 {QStringLiteral("data"),
                  QJsonObject{
                      {QStringLiteral("providerId"), kProviderId},
                      {QStringLiteral("catalogId"),
                       QStringLiteral("live_events")},
                      {QStringLiteral("items"), QJsonArray{}},
                      {QStringLiteral("nextCursor"), QJsonValue::Null},
                  }},
                 {QStringLiteral("meta"), meta(cacheState)},
                 {QStringLiteral("errors"), QJsonArray{}},
             })
      .toJson(QJsonDocument::Compact);
}

QByteArray itemEnvelope() {
  return QJsonDocument(
             QJsonObject{
                 {QStringLiteral("data"),
                  QJsonObject{
                      {QStringLiteral("item"), item()},
                      {QStringLiteral("streams"),
                       QJsonArray{QJsonObject{
                           {QStringLiteral("streamOptionKey"),
                            QStringLiteral("lvk1.stream.primary-fixture")},
                           {QStringLiteral("label"), QStringLiteral("Primary")},
                           {QStringLiteral("quality"), QStringLiteral("1080p")},
                           {QStringLiteral("language"), QStringLiteral("en")},
                           {QStringLiteral("protocolHint"),
                            QStringLiteral("hls")},
                           {QStringLiteral("priority"), 100},
                       }}},
                  }},
                 {QStringLiteral("meta"), meta()},
                 {QStringLiteral("errors"), QJsonArray{}},
             })
      .toJson(QJsonDocument::Compact);
}

QByteArray errorEnvelope() {
  return QJsonDocument(
             QJsonObject{
                 {QStringLiteral("data"), QJsonValue::Null},
                 {QStringLiteral("meta"), meta(QStringLiteral("none"))},
                 {QStringLiteral("errors"),
                  QJsonArray{QJsonObject{
                      {QStringLiteral("code"),
                       QStringLiteral("LIVE_PROVIDER_TIMEOUT")},
                      {QStringLiteral("message"),
                       QStringLiteral("Live provider did not respond in time")},
                      {QStringLiteral("retryable"), true},
                      {QStringLiteral("retryAfterSeconds"), 15},
                      {QStringLiteral("providerId"), kProviderId},
                  }}},
             })
      .toJson(QJsonDocument::Compact);
}

QJsonObject adminMeta() {
  return {
      {QStringLiteral("requestId"),
       QStringLiteral("c0206f86-88ee-44b3-9ef9-a89c20149fb7")},
      {QStringLiteral("generatedAt"), QStringLiteral("2026-07-13T20:00:00Z")},
      {QStringLiteral("cacheState"), QStringLiteral("none")},
      {QStringLiteral("partial"), false},
  };
}

QJsonObject audit(const QString &action, const QString &targetType,
                  const QString &targetId) {
  return {
      {QStringLiteral("auditId"),
       QStringLiteral("f9d28a83-dd72-4f45-a1a0-d04fec22a0e8")},
      {QStringLiteral("action"), action},
      {QStringLiteral("targetType"), targetType},
      {QStringLiteral("targetId"), targetId},
      {QStringLiteral("actor"),
       QJsonObject{
           {QStringLiteral("actorUserId"),
            QStringLiteral("8c0e84e9-af57-4234-a0ae-c24c2c74dca0")},
           {QStringLiteral("displayName"), QStringLiteral("Fixture Owner")},
           {QStringLiteral("homeRole"), QStringLiteral("owner")},
       }},
      {QStringLiteral("occurredAt"), QStringLiteral("2026-07-13T20:00:00Z")},
      {QStringLiteral("recordHash"), QString(64, QLatin1Char('a'))},
  };
}

QJsonObject destinationRule(int revision = 1) {
  return {
      {QStringLiteral("ruleId"), kRuleId},
      {QStringLiteral("providerId"), kProviderId},
      {QStringLiteral("revision"), revision},
      {QStringLiteral("scheme"), QStringLiteral("https")},
      {QStringLiteral("host"), QStringLiteral("origin.example")},
      {QStringLiteral("port"), 443},
      {QStringLiteral("path"), QStringLiteral("/live/")},
      {QStringLiteral("networkScope"), QStringLiteral("public")},
      {QStringLiteral("allowFetch"), true},
      {QStringLiteral("allowCredentials"), false},
      {QStringLiteral("allowClientDisclosure"), false},
      {QStringLiteral("createdBy"),
       QJsonObject{
           {QStringLiteral("actorUserId"),
            QStringLiteral("8c0e84e9-af57-4234-a0ae-c24c2c74dca0")},
           {QStringLiteral("displayName"), QStringLiteral("Fixture Owner")},
           {QStringLiteral("homeRole"), QStringLiteral("owner")},
       }},
      {QStringLiteral("createdAt"), QStringLiteral("2026-07-13T20:00:00Z")},
      {QStringLiteral("updatedAt"), QStringLiteral("2026-07-13T20:00:00Z")},
  };
}

QByteArray adminEnvelope(const QJsonValue &data) {
  return QJsonDocument(QJsonObject{{QStringLiteral("data"), data},
                                   {QStringLiteral("meta"), adminMeta()},
                                   {QStringLiteral("errors"), QJsonArray{}}})
      .toJson(QJsonDocument::Compact);
}

QJsonObject destinationMutation(bool deleted, int revision) {
  return {
      {QStringLiteral("providerId"), kProviderId},
      {QStringLiteral("ruleId"), kRuleId},
      {QStringLiteral("revision"), revision},
      {QStringLiteral("deleted"), deleted},
      {QStringLiteral("rule"), deleted ? QJsonValue(QJsonValue::Null)
                                       : QJsonValue(destinationRule(revision))},
      {QStringLiteral("audit"),
       audit(deleted ? QStringLiteral("destination_rule_delete")
                     : QStringLiteral("destination_rule_update"),
             QStringLiteral("destination_rule"), kRuleId)},
  };
}

QVariantMap destinationDraft() {
  return {{QStringLiteral("scheme"), QStringLiteral("https")},
          {QStringLiteral("host"), QStringLiteral("origin.example")},
          {QStringLiteral("port"), 443},
          {QStringLiteral("path"), QStringLiteral("/live/")},
          {QStringLiteral("networkScope"), QStringLiteral("public")},
          {QStringLiteral("allowFetch"), true},
          {QStringLiteral("allowCredentials"), false},
          {QStringLiteral("allowClientDisclosure"), false}};
}

ScriptedHttpResponse jsonResponse(const QByteArray &body, int status = 200,
                                  qint64 delayMs = 0) {
  ScriptedHttpResponse response;
  response.statusCode = status;
  response.headers.append(
      {QByteArrayLiteral("content-type"),
       QByteArrayLiteral("application/json; charset=utf-8")});
  response.body = body;
  response.delayMs = delayMs;
  return response;
}

QByteArray capturedHeader(const CapturedNetworkRequest &request,
                          const QByteArray &name) {
  for (const auto &[candidate, value] : request.headers) {
    if (candidate.compare(name, Qt::CaseInsensitive) == 0) {
      return value;
    }
  }
  return {};
}

} // namespace

class LiveClientTests final : public QObject {
  Q_OBJECT

private slots:
  void frozenEnvelopesParseStrictlyAndPreserveUnknownExtensionFields();
  void malformedMetaAndNonUtcDatesFailClosed();
  void transportUsesBearerHeaderAndCancellationIsTerminal();
  void catalogFilterQueryPreservesLiteralPlus();
  void modelSuppressesOldGenerationAndConvertsUtcForDisplay();
  void modelSurfacesStructuredErrorsAndItemStreams();
  void modelRefreshPreservesRowsAcrossTimeoutAndEmptyStalePage();
  void artworkAuthenticationPolicyIsExactOriginAndPath();
  void timezoneDstTransitionUsesSystemRules();
  void c31AdminTransportCoversEveryMutationAndCasBody();
  void c31AdminResponsesRejectSecretsAndMismatchedIdentity();
  void c31AdminInvalidInputNeverLeavesTheClient();
};

void LiveClientTests::
    frozenEnvelopesParseStrictlyAndPreserveUnknownExtensionFields() {
  QJsonObject providers = QJsonDocument::fromJson(providersEnvelope()).object();
  QJsonArray providerData = providers.value(QStringLiteral("data")).toArray();
  QJsonObject provider = providerData.first().toObject();
  provider.insert(QStringLiteral("futureField"), QStringLiteral("ignored"));
  providerData[0] = provider;
  providers.insert(QStringLiteral("data"), providerData);
  const auto parsedProviders = Live::parseProviders(QJsonDocument(providers));
  QVERIFY2(parsedProviders, qPrintable(parsedProviders.error));
  QCOMPARE(parsedProviders.value->data.first().name,
           QStringLiteral("Fixture Sports"));
  QCOMPARE(parsedProviders.value->data.first().instanceId, kInstanceId);
  QCOMPARE(parsedProviders.value->data.first().accountState,
           QStringLiteral("not_required"));

  provider.insert(QStringLiteral("readiness"),
                  QStringLiteral("needs_account"));
  provider.insert(QStringLiteral("accountState"),
                  QStringLiteral("needs_account"));
  providerData[0] = provider;
  providers.insert(QStringLiteral("data"), providerData);
  const auto needsAccount = Live::parseProviders(QJsonDocument(providers));
  QVERIFY2(needsAccount, qPrintable(needsAccount.error));
  QCOMPARE(needsAccount.value->data.first().accountState,
           QStringLiteral("needs_account"));

  const auto parsedCatalogs =
      Live::parseCatalogs(QJsonDocument::fromJson(catalogsEnvelope()));
  QVERIFY2(parsedCatalogs, qPrintable(parsedCatalogs.error));
  QCOMPARE(
      parsedCatalogs.value->data.first().filters.first().options.first().value,
      QStringLiteral("football"));

  const auto parsedItem =
      Live::parseItem(QJsonDocument::fromJson(itemEnvelope()));
  QVERIFY2(parsedItem, qPrintable(parsedItem.error));
  QCOMPARE(parsedItem.value->item.status, QStringLiteral("live"));
  QCOMPARE(parsedItem.value->streams.first().protocolHint,
           QStringLiteral("hls"));
}

void LiveClientTests::malformedMetaAndNonUtcDatesFailClosed() {
  QJsonObject envelope =
      QJsonDocument::fromJson(pageEnvelope(QStringLiteral("Old"))).object();
  QJsonObject metadata = envelope.value(QStringLiteral("meta")).toObject();
  metadata.insert(QStringLiteral("unexpected"), true);
  envelope.insert(QStringLiteral("meta"), metadata);
  auto parsed = Live::parseCatalogPage(QJsonDocument(envelope));
  QVERIFY(!parsed);
  QVERIFY(parsed.error.contains(QStringLiteral("unknown field")));

  envelope =
      QJsonDocument::fromJson(pageEnvelope(QStringLiteral("Old"))).object();
  QJsonObject data = envelope.value(QStringLiteral("data")).toObject();
  QJsonArray items = data.value(QStringLiteral("items")).toArray();
  QJsonObject first = items.first().toObject();
  first.insert(QStringLiteral("startsAt"),
               QStringLiteral("2026-07-10T15:00:00-05:00"));
  items[0] = first;
  data.insert(QStringLiteral("items"), items);
  envelope.insert(QStringLiteral("data"), data);
  parsed = Live::parseCatalogPage(QJsonDocument(envelope));
  QVERIFY(!parsed);
  QVERIFY(parsed.error.contains(QStringLiteral("ending in Z")));
}

void LiveClientTests::transportUsesBearerHeaderAndCancellationIsTerminal() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(providersEnvelope(), 200, 20));
  LiveApiClient live(&auth, &network);
  QSignalSpy received(&live, &LiveApiClient::providersReceived);
  QSignalSpy cancelled(&live, &LiveApiClient::requestCancelled);

  const quint64 requestId = live.listProviders(7);
  QCOMPARE(network.capturedRequests().size(), 1);
  const CapturedNetworkRequest &request = network.capturedRequests().first();
  QCOMPARE(request.url.path(), QStringLiteral("/api/v1/live/providers"));
  QVERIFY(!request.url.hasQuery());
  QCOMPARE(capturedHeader(request, QByteArrayLiteral("Authorization")),
           QByteArrayLiteral("Bearer test-access-token"));
  live.cancel(requestId);
  QCOMPARE(cancelled.count(), 1);
  scheduler.advance(20);
  QCOMPARE(received.count(), 0);

  network.enqueue(jsonResponse(providersEnvelope()));
  const quint64 successId = live.listProviders(8);
  scheduler.runDue();
  QCOMPARE(received.count(), 1);
  QCOMPARE(received.first().at(0).toULongLong(), successId);
  QCOMPARE(received.first().at(1).toULongLong(), quint64{8});
}

void LiveClientTests::catalogFilterQueryPreservesLiteralPlus() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(pageEnvelope(QStringLiteral("Nature"))));
  LiveApiClient live(&auth, &network);

  const quint64 requestId = live.listCatalogItems(
      kProviderId, QStringLiteral("live_events"),
      {{QStringLiteral("category"), QStringLiteral("Animals + Nature")}},
      QString(), 40, 1);

  QVERIFY(requestId > 0);
  QCOMPARE(network.capturedRequests().size(), 1);
  const QString query =
      network.capturedRequests().constFirst().url.query(QUrl::FullyEncoded);
  QVERIFY2(
      query.contains(QStringLiteral(
          "filters[category]=Animals%20%2B%20Nature")),
      qPrintable(query));
  QVERIFY(!query.contains(QStringLiteral("Animals%20+%20Nature")));
}

void LiveClientTests::modelSuppressesOldGenerationAndConvertsUtcForDisplay() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(
      jsonResponse(pageEnvelope(QStringLiteral("Old generation")), 200, 20));
  network.enqueue(
      jsonResponse(pageEnvelope(QStringLiteral("Current generation"),
                                QStringLiteral("lvk1.cursor.next-value"))));
  LiveApiClient live(&auth, &network);
  LiveCatalogModel model(&live);
  model.setTimeZoneId(QStringLiteral("America/Chicago"));

  model.selectCatalog(
      kProviderId, QStringLiteral("live_events"),
      {{QStringLiteral("category"), QStringList{QStringLiteral("football")}}});
  const quint64 firstGeneration = model.generation();
  model.selectCatalog(
      kProviderId, QStringLiteral("live_events"),
      {{QStringLiteral("category"), QStringList{QStringLiteral("football")}}});
  QVERIFY(model.generation() > firstGeneration);
  scheduler.runDue();

  QCOMPARE(model.rowCount(), 1);
  QCOMPARE(model.data(model.index(0), LiveCatalogModel::TitleRole).toString(),
           QStringLiteral("Current generation"));
  QVERIFY(model.hasMore());
  const QDateTime local =
      model.data(model.index(0), LiveCatalogModel::StartsAtLocalRole)
          .toDateTime();
  QCOMPARE(local.timeZone(), QTimeZone("America/Chicago"));
  QCOMPARE(local.time(), QTime(15, 0));
  QCOMPARE(local.offsetFromUtc(), -5 * 60 * 60);
  scheduler.advance(20);
  QCOMPARE(model.data(model.index(0), LiveCatalogModel::TitleRole).toString(),
           QStringLiteral("Current generation"));

  QCOMPARE(network.capturedRequests().size(), 2);
  const QString query =
      network.capturedRequests().last().url.query(QUrl::FullyDecoded);
  QVERIFY(query.contains(QStringLiteral("filters[category]=football")));
  QVERIFY(!query.contains(QStringLiteral("token"), Qt::CaseInsensitive));

  network.enqueue(jsonResponse(
      pageEnvelope(QStringLiteral("Second event"), QJsonValue::Null,
                   QStringLiteral("2026-07-10T21:00:00Z"),
                   QStringLiteral("lvk1.item.second-fixture-value"))));
  model.loadMoreItems();
  scheduler.runDue();
  QCOMPARE(model.rowCount(), 2);
  QVERIFY(network.capturedRequests()
              .last()
              .url.query(QUrl::FullyDecoded)
              .contains(QStringLiteral("cursor=lvk1.cursor.next-value")));

  auth.setBaseUrl(QStringLiteral("https://other.example"));
  QCOMPARE(model.rowCount(), 0);
  QVERIFY(model.selectedItem().isEmpty());
}

void LiveClientTests::modelSurfacesStructuredErrorsAndItemStreams() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(errorEnvelope(), 504));
  network.enqueue(jsonResponse(pageEnvelope(QStringLiteral("Current"))));
  network.enqueue(jsonResponse(itemEnvelope()));
  LiveApiClient live(&auth, &network);
  LiveCatalogModel model(&live);

  model.selectCatalog(kProviderId, QStringLiteral("live_events"));
  scheduler.runDue();
  QCOMPARE(model.lastError().value(QStringLiteral("code")).toString(),
           QStringLiteral("LIVE_PROVIDER_TIMEOUT"));
  QVERIFY(model.lastError().value(QStringLiteral("retryable")).toBool());
  QCOMPARE(model.lastError().value(QStringLiteral("retryAfterSeconds")).toInt(),
           15);

  model.refreshPage();
  scheduler.runDue();
  QCOMPARE(model.rowCount(), 1);
  model.loadItem(kProviderId, QStringLiteral("lvk1.item.fixture-key-value"));
  scheduler.runDue();
  QCOMPARE(model.selectedItem().value(QStringLiteral("title")).toString(),
           QStringLiteral("Home vs Away"));
  QCOMPARE(model.selectedStreams().size(), 1);
  QCOMPARE(model.selectedStreams()
               .first()
               .toMap()
               .value(QStringLiteral("streamOptionKey"))
               .toString(),
           QStringLiteral("lvk1.stream.primary-fixture"));
}

void LiveClientTests::
    modelRefreshPreservesRowsAcrossTimeoutAndEmptyStalePage() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(pageEnvelope(QStringLiteral("Current"))));
  LiveApiClient live(&auth, &network);
  LiveCatalogModel model(&live);

  model.selectCatalog(kProviderId, QStringLiteral("live_events"));
  scheduler.runDue();
  QCOMPARE(model.rowCount(), 1);

  network.enqueue(jsonResponse(providersEnvelope()));
  network.enqueue(jsonResponse(catalogsEnvelope()));
  network.enqueue(jsonResponse(errorEnvelope(), 504));
  model.refreshIndex();
  QVERIFY(model.catalogIndexLoading());
  QVERIFY(model.pageLoading());
  QCOMPARE(model.rowCount(), 1);
  scheduler.runDue();
  QCOMPARE(model.rowCount(), 1);
  QCOMPARE(model.lastError().value(QStringLiteral("code")).toString(),
           QStringLiteral("LIVE_PROVIDER_TIMEOUT"));

  network.enqueue(jsonResponse(emptyPageEnvelope(QStringLiteral("stale"))));
  model.refreshPage();
  scheduler.runDue();
  QCOMPARE(model.rowCount(), 1);
  QVERIFY(model.stale());

  network.enqueue(jsonResponse(emptyPageEnvelope(QStringLiteral("fresh"))));
  model.refreshPage();
  scheduler.runDue();
  QCOMPARE(model.rowCount(), 0);
  QVERIFY(!model.stale());
}

void LiveClientTests::artworkAuthenticationPolicyIsExactOriginAndPath() {
  const QUrl base(QStringLiteral("https://server.example:8443"));
  QVERIFY(LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
      QUrl(QStringLiteral(
          "https://server.example:8443/api/v1/live/artwork/lvk1.fixture")),
      base));
  QVERIFY(!LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
      QUrl(QStringLiteral(
          "http://server.example:8443/api/v1/live/artwork/lvk1.fixture")),
      base));
  QVERIFY(!LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
      QUrl(QStringLiteral(
          "https://evil.example:8443/api/v1/live/artwork/lvk1.fixture")),
      base));
  QVERIFY(!LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
      QUrl(QStringLiteral(
          "https://server.example/api/v1/live/artwork/lvk1.fixture")),
      base));
  QVERIFY(!LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
      QUrl(QStringLiteral("https://server.example:8443/api/v1/live/artwork/"
                          "lvk1.fixture?token=no")),
      base));
  QVERIFY(!LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
      QUrl(QStringLiteral(
          "https://user@server.example:8443/api/v1/live/artwork/lvk1.fixture")),
      base));
  QVERIFY(!LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
      QUrl(QStringLiteral(
          "https://server.example:8443/api/v1/live/artworkish/lvk1.fixture")),
      base));
}

void LiveClientTests::timezoneDstTransitionUsesSystemRules() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(
      jsonResponse(pageEnvelope(QStringLiteral("Before DST"), QJsonValue::Null,
                                QStringLiteral("2026-03-08T07:30:00Z"))));
  LiveApiClient live(&auth, &network);
  LiveCatalogModel model(&live);
  model.setTimeZoneId(QStringLiteral("America/Chicago"));
  model.selectCatalog(kProviderId, QStringLiteral("live_events"));
  scheduler.runDue();
  QDateTime local =
      model.data(model.index(0), LiveCatalogModel::StartsAtLocalRole)
          .toDateTime();
  QCOMPARE(local.time(), QTime(1, 30));
  QCOMPARE(local.offsetFromUtc(), -6 * 60 * 60);

  network.enqueue(
      jsonResponse(pageEnvelope(QStringLiteral("After DST"), QJsonValue::Null,
                                QStringLiteral("2026-03-08T08:30:00Z"))));
  model.refreshPage();
  scheduler.runDue();
  local = model.data(model.index(0), LiveCatalogModel::StartsAtLocalRole)
              .toDateTime();
  QCOMPARE(local.time(), QTime(3, 30));
  QCOMPARE(local.offsetFromUtc(), -5 * 60 * 60);
}

void LiveClientTests::c31AdminTransportCoversEveryMutationAndCasBody() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);

  const QJsonObject provider{
      {QStringLiteral("providerId"), kProviderId},
      {QStringLiteral("enabled"), true},
      {QStringLiteral("readiness"), QStringLiteral("ready")},
      {QStringLiteral("disabledReason"), QJsonValue::Null},
      {QStringLiteral("providerRevision"), 4},
      {QStringLiteral("grantRevision"), 7},
      {QStringLiteral("activeSessions"), 1},
      {QStringLiteral("effectiveProtocols"), QJsonArray{QStringLiteral("hls")}},
  };
  const QJsonObject session{
      {QStringLiteral("sessionId"), kSessionId},
      {QStringLiteral("profileId"), kProfileId},
      {QStringLiteral("providerId"), kProviderId},
      {QStringLiteral("deliveryMode"), QStringLiteral("server_relay")},
      {QStringLiteral("protocol"), QStringLiteral("hls")},
      {QStringLiteral("state"), QStringLiteral("playing")},
      {QStringLiteral("revision"), 9},
      {QStringLiteral("sourceIndex"), 0},
      {QStringLiteral("failoverCount"), 1},
      {QStringLiteral("refreshCount"), 2},
      {QStringLiteral("createdAt"), QStringLiteral("2026-07-13T19:00:00Z")},
      {QStringLiteral("lastHeartbeatAt"),
       QStringLiteral("2026-07-13T20:00:00Z")},
      {QStringLiteral("expiresAt"), QStringLiteral("2026-07-13T21:00:00Z")},
      {QStringLiteral("endedAt"), QJsonValue::Null},
      {QStringLiteral("errorCode"), QJsonValue::Null},
  };
  const QJsonObject keyState{
      {QStringLiteral("envelopePrimaryKeyId"), QStringLiteral("live-env-1")},
      {QStringLiteral("tokenHashPrimaryKeyId"), QStringLiteral("live-token-1")},
      {QStringLiteral("auditPrimaryKeyId"), QStringLiteral("live-audit-1")},
      {QStringLiteral("revision"), 11},
  };
  const QJsonObject disabled{
      {QStringLiteral("operationId"),
       QStringLiteral("96eb0c82-81f7-428e-8e20-a898d57358d7")},
      {QStringLiteral("status"), QStringLiteral("accepted")},
      {QStringLiteral("revision"), 5},
      {QStringLiteral("providerId"), kProviderId},
      {QStringLiteral("audit"), audit(QStringLiteral("provider_disable"),
                                      QStringLiteral("provider"), kProviderId)},
  };
  const auto grant = [](bool browse, bool play, int revision) {
    return QJsonObject{
        {QStringLiteral("providerId"), kProviderId},
        {QStringLiteral("profileId"), kProfileId},
        {QStringLiteral("canBrowse"), browse},
        {QStringLiteral("canPlay"), play},
        {QStringLiteral("revision"), revision},
        {QStringLiteral("audit"),
         audit(QStringLiteral("provider_grant_set"),
               QStringLiteral("provider_grant"), kProfileId)},
    };
  };
  const QJsonObject terminated{
      {QStringLiteral("status"), QStringLiteral("completed")},
      {QStringLiteral("revision"), 10},
      {QStringLiteral("sessionId"), kSessionId},
      {QStringLiteral("state"), QStringLiteral("ended")},
      {QStringLiteral("audit"), audit(QStringLiteral("session_terminate"),
                                      QStringLiteral("session"), kSessionId)},
  };
  const QJsonObject rotated{
      {QStringLiteral("status"), QStringLiteral("completed")},
      {QStringLiteral("revision"), 12},
      {QStringLiteral("keyDomain"), QStringLiteral("token_hash")},
      {QStringLiteral("primaryKeyId"), QStringLiteral("live-token-2")},
      {QStringLiteral("previousPrimaryKeyId"), QStringLiteral("live-token-1")},
      {QStringLiteral("reencryptedSessions"), 0},
      {QStringLiteral("reencryptedReplays"), 0},
      {QStringLiteral("terminatedSessions"), 1},
      {QStringLiteral("invalidatedCacheEntries"), 0},
      {QStringLiteral("audit"),
       audit(QStringLiteral("token_hash_key_rotate"),
             QStringLiteral("live_key"), QStringLiteral("token_hash"))},
  };

  for (const QByteArray &response :
       {adminEnvelope(QJsonArray{provider}), adminEnvelope(QJsonArray{session}),
        adminEnvelope(keyState), adminEnvelope(QJsonArray{destinationRule()}),
        adminEnvelope(destinationMutation(false, 1)),
        adminEnvelope(destinationMutation(false, 2)),
        adminEnvelope(destinationMutation(true, 3)), adminEnvelope(disabled),
        adminEnvelope(grant(true, true, 8)),
        adminEnvelope(grant(false, false, 9)), adminEnvelope(terminated),
        adminEnvelope(rotated)}) {
    network.enqueue(jsonResponse(response));
  }

  LiveApiClient live(&auth, &network);
  QSignalSpy received(&live, &LiveApiClient::adminResponseReceived);
  live.listAdminProviders(31);
  scheduler.runDue();
  live.listAdminSessions(31);
  scheduler.runDue();
  live.getAdminKeyState(31);
  scheduler.runDue();
  live.listAdminDestinationRules(kProviderId, 31);
  scheduler.runDue();
  live.createAdminDestinationRule(kProviderId, 4, destinationDraft(), 31);
  scheduler.runDue();
  live.updateAdminDestinationRule(kProviderId, kRuleId, 1, destinationDraft(),
                                  31);
  scheduler.runDue();
  live.deleteAdminDestinationRule(kProviderId, kRuleId, 2, 31);
  scheduler.runDue();
  live.disableAdminProvider(kProviderId, 4, 31);
  scheduler.runDue();
  live.setAdminProviderGrant(kProviderId, kProfileId, true, true, 7, 31);
  scheduler.runDue();
  live.revokeAdminProviderGrant(kProviderId, kProfileId, 8, 31);
  scheduler.runDue();
  live.terminateAdminSession(kSessionId, 9, 31);
  scheduler.runDue();
  live.rotateAdminKey(QStringLiteral("token_hash"),
                      QStringLiteral("live-token-2"), 11, 31);
  scheduler.runDue();

  QCOMPARE(received.count(), 12);
  QCOMPARE(network.capturedRequests().size(), 12);
  QCOMPARE(network.capturedRequests().at(0).url.path(),
           QStringLiteral("/api/v1/live/admin/providers"));
  QCOMPARE(network.capturedRequests().at(4).operation,
           QNetworkAccessManager::PostOperation);
  QCOMPARE(network.capturedRequests().at(5).operation,
           QNetworkAccessManager::PutOperation);
  QCOMPARE(network.capturedRequests().at(6).operation,
           QNetworkAccessManager::CustomOperation);
  QCOMPARE(network.capturedRequests().at(11).url.path(),
           QStringLiteral("/api/v1/live/admin/keys/token-hash/rotate"));
  for (const CapturedNetworkRequest &request : network.capturedRequests()) {
    QCOMPARE(capturedHeader(request, QByteArrayLiteral("Authorization")),
             QByteArrayLiteral("Bearer test-access-token"));
    QVERIFY(!request.url.query().contains(QStringLiteral("token"),
                                          Qt::CaseInsensitive));
  }
  const QJsonObject createBody =
      QJsonDocument::fromJson(network.capturedRequests().at(4).body).object();
  QCOMPARE(createBody.value(QStringLiteral("expectedProviderRevision")).toInt(),
           4);
  const QJsonObject deleteBody =
      QJsonDocument::fromJson(network.capturedRequests().at(6).body).object();
  QCOMPARE(deleteBody.value(QStringLiteral("expectedRevision")).toInt(), 2);
  const QJsonObject rotateBody =
      QJsonDocument::fromJson(network.capturedRequests().at(11).body).object();
  QCOMPARE(rotateBody.value(QStringLiteral("keyId")).toString(),
           QStringLiteral("live-token-2"));
  QCOMPARE(rotateBody.value(QStringLiteral("expectedRevision")).toInt(), 11);
}

void LiveClientTests::c31AdminResponsesRejectSecretsAndMismatchedIdentity() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  QJsonObject provider{
      {QStringLiteral("providerId"), kProviderId},
      {QStringLiteral("enabled"), true},
      {QStringLiteral("readiness"), QStringLiteral("ready")},
      {QStringLiteral("disabledReason"), QJsonValue::Null},
      {QStringLiteral("providerRevision"), 1},
      {QStringLiteral("grantRevision"), 1},
      {QStringLiteral("activeSessions"), 0},
      {QStringLiteral("effectiveProtocols"), QJsonArray{}},
      {QStringLiteral("sessionToken"), QStringLiteral("must-not-escape")},
  };
  QJsonObject mismatch = destinationMutation(false, 2);
  mismatch.insert(QStringLiteral("providerId"),
                  QStringLiteral("df8f3fa8-44c4-4202-86c0-9ea20be6debf"));
  network.enqueue(jsonResponse(adminEnvelope(QJsonArray{provider})));
  network.enqueue(jsonResponse(adminEnvelope(mismatch)));
  LiveApiClient live(&auth, &network);
  QSignalSpy received(&live, &LiveApiClient::adminResponseReceived);
  QSignalSpy failed(&live, &LiveApiClient::requestFailed);

  live.listAdminProviders(32);
  scheduler.runDue();
  live.updateAdminDestinationRule(kProviderId, kRuleId, 1, destinationDraft(),
                                  32);
  scheduler.runDue();

  QCOMPARE(received.count(), 0);
  QCOMPARE(failed.count(), 2);
  QCOMPARE(failed.at(0).at(3).toMap().value(QStringLiteral("code")).toString(),
           QStringLiteral("LIVE_CLIENT_CONTRACT_INVALID"));
  QCOMPARE(failed.at(1).at(3).toMap().value(QStringLiteral("code")).toString(),
           QStringLiteral("LIVE_CLIENT_CONTRACT_INVALID"));
}

void LiveClientTests::c31AdminInvalidInputNeverLeavesTheClient() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("test-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  LiveApiClient live(&auth, &network);
  QSignalSpy failed(&live, &LiveApiClient::requestFailed);
  QVariantMap unsafeDraft = destinationDraft();
  unsafeDraft.insert(QStringLiteral("scheme"), QStringLiteral("http"));
  unsafeDraft.insert(QStringLiteral("allowCredentials"), true);

  live.listAdminDestinationRules(QStringLiteral("not-a-uuid"), 33);
  live.createAdminDestinationRule(kProviderId, 1, unsafeDraft, 33);
  live.rotateAdminKey(QStringLiteral("unknown"), QStringLiteral("key-2"), 1,
                      33);

  QTRY_COMPARE(failed.count(), 3);
  QCOMPARE(network.capturedRequests().size(), 0);
  for (const QList<QVariant> &arguments : failed) {
    QCOMPARE(arguments.at(3).toMap().value(QStringLiteral("code")).toString(),
             QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"));
  }
}

QTEST_GUILESS_MAIN(LiveClientTests)

#include "LiveClientTests.moc"
