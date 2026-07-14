#include "backend/ApiClient.h"
#include "backend/LivePlaybackTarget.h"
#include "backend/LivePlayerController.h"
#include "backend/MpvItem.h"
#include "live/LiveApiClient.h"
#include "live/LiveTypes.h"
#include "support/DeterministicScheduler.h"
#include "support/ScriptedNetworkAccessManager.h"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <algorithm>
#include <array>
#include <cstddef>

namespace {

const QString kProviderId =
    QStringLiteral("0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d");
const QString kSessionId =
    QStringLiteral("5ad4cbcb-45df-43af-896c-caba52ab56a4");
const QString kSourceKey = QStringLiteral("lvk1.source.abcdefghijklmnopqrstuv");
const QString kBackupSourceKey =
    QStringLiteral("lvk1.source.backupabcdefghijklmnop");

QJsonObject meta() {
  return {
      {QStringLiteral("requestId"),
       QStringLiteral("01J2H3D5W6Y7Z8A9B0C1D2E3F4")},
      {QStringLiteral("generatedAt"), QStringLiteral("2026-07-12T20:00:00Z")},
      {QStringLiteral("cacheState"), QStringLiteral("none")},
      {QStringLiteral("partial"), false}};
}

QByteArray createdResponse(bool relay = false, bool inconsistentToken = false,
                           bool egressFallback = false) {
  const QDateTime now = QDateTime::currentDateTimeUtc();
  QJsonObject object{
      {QStringLiteral("sessionId"), kSessionId},
      {QStringLiteral("revision"), 3},
      {QStringLiteral("deliveryMode"), relay ? QStringLiteral("server_relay")
                                             : QStringLiteral("client_direct")},
      {QStringLiteral("decisionReason"),
       relay ? QStringLiteral("relay_required")
             : QStringLiteral("public_compatible_direct")},
      {QStringLiteral("egress"),
       QJsonObject{{QStringLiteral("mode"),
                    egressFallback ? QStringLiteral("direct_fallback")
                                   : QStringLiteral("server_default")},
                   {QStringLiteral("fallbackReason"),
                    egressFallback ? QJsonValue(QStringLiteral(
                                         "protected_egress_unavailable"))
                                   : QJsonValue(QJsonValue::Null)}}},
      {QStringLiteral("playbackUrl"),
       relay
           ? QStringLiteral("/api/v1/live/sessions/") + kSessionId +
                 QStringLiteral("/delivery/hls/manifest.m3u8")
           : QStringLiteral("https://public.example.invalid/live/master.m3u8")},
      {QStringLiteral("expiresAt"),
       now.addSecs(120).toString(Qt::ISODateWithMs)},
      {QStringLiteral("hardExpiresAt"),
       now.addSecs(43'200).toString(Qt::ISODateWithMs)},
      {QStringLiteral("heartbeatIntervalSeconds"), 30},
      {QStringLiteral("live"),
       QJsonObject{{QStringLiteral("seekable"), true},
                   {QStringLiteral("windowSeconds"), 1800},
                   {QStringLiteral("targetLatencySeconds"), QJsonValue::Null}}},
      {QStringLiteral("selectedSource"),
       QJsonObject{{QStringLiteral("sourceKey"), kSourceKey},
                   {QStringLiteral("label"), QStringLiteral("Primary")},
                   {QStringLiteral("quality"), QStringLiteral("1080p")}}},
      {QStringLiteral("availableSources"),
       QJsonArray{
           QJsonObject{{QStringLiteral("sourceKey"), kSourceKey},
                       {QStringLiteral("label"), QStringLiteral("Primary")},
                       {QStringLiteral("quality"), QStringLiteral("1080p")}},
           QJsonObject{{QStringLiteral("sourceKey"), kBackupSourceKey},
                       {QStringLiteral("label"), QStringLiteral("Backup")},
                       {QStringLiteral("quality"), QStringLiteral("720p")}}}},
      {QStringLiteral("trackPreferences"),
       QJsonObject{
           {QStringLiteral("audio"),
            QJsonObject{{QStringLiteral("trackId"), QStringLiteral("audio-2")},
                        {QStringLiteral("language"), QStringLiteral("es")},
                        {QStringLiteral("title"), QStringLiteral("Spanish")}}},
           {QStringLiteral("subtitle"),
            QJsonObject{{QStringLiteral("trackId"), QStringLiteral("no")},
                        {QStringLiteral("language"), QJsonValue::Null},
                        {QStringLiteral("title"), QJsonValue::Null}}}}},
  };
  if (relay || inconsistentToken) {
    object.insert(QStringLiteral("tokenRevision"), 1);
    object.insert(QStringLiteral("sessionToken"),
                  QStringLiteral("elx-live-token-v1.test-secret-value"));
  }
  return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

QByteArray
detailResponse(qint64 revision = 4,
               const QString &state = QStringLiteral("playing"),
               const QString &sourceKey = kSourceKey,
               const QString &sourceLabel = QStringLiteral("Primary"),
               const QString &quality = QStringLiteral("1080p")) {
  const QDateTime now = QDateTime::currentDateTimeUtc();
  const QJsonObject data{
      {QStringLiteral("sessionId"), kSessionId},
      {QStringLiteral("revision"), revision},
      {QStringLiteral("state"), state},
      {QStringLiteral("deliveryMode"), QStringLiteral("client_direct")},
      {QStringLiteral("protocol"), QStringLiteral("hls")},
      {QStringLiteral("selectedSource"),
       QJsonObject{{QStringLiteral("sourceKey"), sourceKey},
                   {QStringLiteral("label"), sourceLabel},
                   {QStringLiteral("quality"), quality}}},
      {QStringLiteral("availableSources"),
       QJsonArray{
           QJsonObject{{QStringLiteral("sourceKey"), sourceKey},
                       {QStringLiteral("label"), sourceLabel},
                       {QStringLiteral("quality"), quality}},
           QJsonObject{
               {QStringLiteral("sourceKey"),
                sourceKey == kBackupSourceKey ? kSourceKey : kBackupSourceKey},
               {QStringLiteral("label"), sourceKey == kBackupSourceKey
                                             ? QStringLiteral("Primary")
                                             : QStringLiteral("Backup")},
               {QStringLiteral("quality"), sourceKey == kBackupSourceKey
                                               ? QStringLiteral("1080p")
                                               : QStringLiteral("720p")}}}},
      {QStringLiteral("trackPreferences"),
       QJsonObject{
           {QStringLiteral("audio"),
            QJsonObject{{QStringLiteral("trackId"), QStringLiteral("audio-2")},
                        {QStringLiteral("language"), QStringLiteral("es")},
                        {QStringLiteral("title"), QStringLiteral("Spanish")}}},
           {QStringLiteral("subtitle"),
            QJsonObject{{QStringLiteral("trackId"), QStringLiteral("no")},
                        {QStringLiteral("language"), QJsonValue::Null},
                        {QStringLiteral("title"), QJsonValue::Null}}}}},
      {QStringLiteral("expiresAt"),
       now.addSecs(150).toString(Qt::ISODateWithMs)},
      {QStringLiteral("hardExpiresAt"),
       now.addSecs(43'200).toString(Qt::ISODateWithMs)},
      {QStringLiteral("errorCode"), QJsonValue::Null},
      {QStringLiteral("timeline"),
       QJsonArray{
           QJsonObject{{QStringLiteral("at"), now.toString(Qt::ISODateWithMs)},
                       {QStringLiteral("revision"), revision},
                       {QStringLiteral("state"), state},
                       {QStringLiteral("reason"), QJsonValue::Null}}}},
  };
  return QJsonDocument(QJsonObject{{QStringLiteral("data"), data},
                                   {QStringLiteral("meta"), meta()},
                                   {QStringLiteral("errors"), QJsonArray{}}})
      .toJson(QJsonDocument::Compact);
}

QByteArray recoveredResponse(qint64 revision, const QString &sourceKey,
                             const QString &sourceLabel,
                             const QByteArray &token) {
  QJsonObject object = QJsonDocument::fromJson(createdResponse(true)).object();
  object.insert(QStringLiteral("revision"), revision);
  object.insert(QStringLiteral("tokenRevision"), revision);
  object.insert(QStringLiteral("sessionToken"), QString::fromUtf8(token));
  object.insert(
      QStringLiteral("selectedSource"),
      QJsonObject{{QStringLiteral("sourceKey"), sourceKey},
                  {QStringLiteral("label"), sourceLabel},
                  {QStringLiteral("quality"), QStringLiteral("1080p")}});
  object.insert(
      QStringLiteral("availableSources"),
      QJsonArray{
          QJsonObject{{QStringLiteral("sourceKey"), sourceKey},
                      {QStringLiteral("label"), sourceLabel},
                      {QStringLiteral("quality"), QStringLiteral("1080p")}},
          QJsonObject{
              {QStringLiteral("sourceKey"),
               sourceKey == kBackupSourceKey ? kSourceKey : kBackupSourceKey},
              {QStringLiteral("label"), QStringLiteral("Alternative")},
              {QStringLiteral("quality"), QStringLiteral("720p")}}});
  return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

QByteArray expiringCreatedResponse() {
  QJsonObject object = QJsonDocument::fromJson(createdResponse(true)).object();
  object.insert(
      QStringLiteral("expiresAt"),
      QDateTime::currentDateTimeUtc().addSecs(30).toString(Qt::ISODateWithMs));
  return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

QByteArray errorResponse(const QString &code, bool retryable = true) {
  return QJsonDocument(
             QJsonObject{{QStringLiteral("data"), QJsonValue::Null},
                         {QStringLiteral("meta"), meta()},
                         {QStringLiteral("errors"),
                          QJsonArray{QJsonObject{
                              {QStringLiteral("code"), code},
                              {QStringLiteral("message"),
                               QStringLiteral("Live recovery fixture failure")},
                              {QStringLiteral("retryable"), retryable}}}}})
      .toJson(QJsonDocument::Compact);
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

ScriptedHttpResponse emptyResponse(int status = 204) {
  ScriptedHttpResponse response;
  response.statusCode = status;
  return response;
}

QByteArray header(const CapturedNetworkRequest &request,
                  const QByteArray &name) {
  for (const auto &[candidate, value] : request.headers) {
    if (candidate.compare(name, Qt::CaseInsensitive) == 0) {
      return value;
    }
  }
  return {};
}

class FakePlaybackTarget final : public LivePlaybackTarget {
public:
  void prepareLivePlayback(const QByteArray &sessionToken,
                           const QString &deliveryMode,
                           bool lowLatency) override {
    ++prepareCount;
    token = sessionToken;
    mode = deliveryMode;
    lowLatencyEnabled = lowLatency;
  }

  void loadLiveUrl(const QUrl &value) override {
    ++loadCount;
    url = value;
  }

  void clearLivePlayback() override {
    ++clearCount;
    std::fill(token.begin(), token.end(), '\0');
    token.clear();
    mode.clear();
    url.clear();
  }

  int prepareCount{0};
  int loadCount{0};
  int clearCount{0};
  QByteArray token;
  QString mode;
  QUrl url;
  bool lowLatencyEnabled{false};
};

} // namespace

class LivePlayerTests final : public QObject {
  Q_OBJECT

private slots:
  void initTestCase();
  void init();
  void sessionContractsEnforceTokenModeAndUtcBounds();
  void serverPlaybackUrlIsBoundToExactSessionDeliveryRoute();
  void n11DirectFallbackRequiresExplicitConfirmationBeforeLoad();
  void c30SourcesTrackPreferencesAndDvrBoundsAreStrict();
  void controllerCreatesHeartbeatsObservesAndClearsWithoutLibraryCalls();
  void relayTokenIsHeaderScopedAndClearedBetweenLoads();
  void routeExitCancelsInflightHeartbeatWithoutFailureReentry();
  void failedEndIsRetriedOnTheNextAuthenticatedStart();
  void c22RecoveryApiBuildsStrictRefreshAndManualFailoverRequests();
  void c22ControllerRefreshesThenFailsOverWithoutDuplicateActions();
  void c22ManualSourceSwitchRotatesPlaybackExactlyOnce();
  void c22ExpiryThresholdRefreshesBeforeHeartbeatMutation();
  void c22ExpectedEndAndExhaustionDoNotEnterRetryLoops();
  void c22RefreshFailureResyncsRevisionBeforeAutomaticFailover();
  void c22ReconnectPolicyIsBoundedAndCancellationStopsReloads();
  void c22RouteExitDiscardsDelayedRecoveryReplyAndToken();

private:
  QTemporaryDir m_settingsDirectory;
};

void LivePlayerTests::initTestCase() {
  QVERIFY(m_settingsDirectory.isValid());
  QCoreApplication::setOrganizationName(QStringLiteral("ElixirC20Tests"));
  QCoreApplication::setApplicationName(QStringLiteral("LivePlayer"));
  QSettings::setDefaultFormat(QSettings::IniFormat);
  QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                     m_settingsDirectory.path());
}

void LivePlayerTests::init() { QSettings().clear(); }

void LivePlayerTests::sessionContractsEnforceTokenModeAndUtcBounds() {
  auto direct = Live::parseSessionCreated(
      QJsonDocument::fromJson(createdResponse(false)));
  QVERIFY2(direct, qPrintable(direct.error));
  QVERIFY(direct.value->sessionToken.isEmpty());
  QCOMPARE(direct.value->heartbeatIntervalSeconds, 30);

  auto relay =
      Live::parseSessionCreated(QJsonDocument::fromJson(createdResponse(true)));
  QVERIFY2(relay, qPrintable(relay.error));
  QVERIFY(!relay.value->sessionToken.isEmpty());

  auto invalid = Live::parseSessionCreated(
      QJsonDocument::fromJson(createdResponse(false, true)));
  QVERIFY(!invalid);
  QVERIFY(invalid.error.contains(QStringLiteral("inconsistent")));

  QJsonObject invalidEgress =
      QJsonDocument::fromJson(createdResponse(true)).object();
  invalidEgress.insert(
      QStringLiteral("egress"),
      QJsonObject{{QStringLiteral("mode"), QStringLiteral("direct_fallback")},
                  {QStringLiteral("fallbackReason"), QJsonValue::Null}});
  const auto rejectedEgress =
      Live::parseSessionCreated(QJsonDocument(invalidEgress));
  QVERIFY(!rejectedEgress);
  QVERIFY(rejectedEgress.error.contains(QStringLiteral("egress")));

  const auto detail =
      Live::parseSessionDetail(QJsonDocument::fromJson(detailResponse()));
  QVERIFY2(detail, qPrintable(detail.error));
  QCOMPARE(detail.value->data.revision, qint64{4});
}

void LivePlayerTests::serverPlaybackUrlIsBoundToExactSessionDeliveryRoute() {
  QJsonObject response =
      QJsonDocument::fromJson(createdResponse(true)).object();
  response.insert(QStringLiteral("playbackUrl"),
                  QStringLiteral("/api/v1/live/admin/providers"));

  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(
      jsonResponse(QJsonDocument(response).toJson(QJsonDocument::Compact)));
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);

  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();

  QCOMPARE(controller.state(), QStringLiteral("failed"));
  QCOMPARE(controller.errorCode(),
           QStringLiteral("LIVE_CLIENT_PLAYBACK_URL_REJECTED"));
  QCOMPARE(target.prepareCount, 0);
  QCOMPARE(target.loadCount, 0);
}

void LivePlayerTests::
    n11DirectFallbackRequiresExplicitConfirmationBeforeLoad() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse(true, false, true)));
  network.enqueue(jsonResponse(detailResponse()));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);

  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();

  QCOMPARE(controller.state(), QStringLiteral("awaiting_egress_fallback"));
  QCOMPARE(controller.egressMode(), QStringLiteral("direct_fallback"));
  QVERIFY(controller.egressFallbackPending());
  QCOMPARE(target.loadCount, 0);
  QCOMPARE(target.prepareCount, 0);

  controller.confirmEgressFallback();
  QCOMPARE(controller.state(), QStringLiteral("loading"));
  QVERIFY(!controller.egressFallbackPending());
  QCOMPARE(target.prepareCount, 1);
  QCOMPARE(target.loadCount, 1);

  controller.stop();
  scheduler.runDue();
}

void LivePlayerTests::c30SourcesTrackPreferencesAndDvrBoundsAreStrict() {
  auto parsed = Live::parseSessionCreated(
      QJsonDocument::fromJson(createdResponse(false)));
  QVERIFY2(parsed, qPrintable(parsed.error));
  QCOMPARE(parsed.value->availableSources.size(), 2);
  QVERIFY(parsed.value->trackPreferences.audio.has_value());
  QCOMPARE(parsed.value->trackPreferences.audio->language,
           QStringLiteral("es"));
  QVERIFY(parsed.value->trackPreferences.subtitle.has_value());
  QCOMPARE(parsed.value->trackPreferences.subtitle->trackId,
           QStringLiteral("no"));

  QJsonObject duplicate =
      QJsonDocument::fromJson(createdResponse(false)).object();
  QJsonArray sources =
      duplicate.value(QStringLiteral("availableSources")).toArray();
  sources.append(sources.first());
  duplicate.insert(QStringLiteral("availableSources"), sources);
  const auto rejected = Live::parseSessionCreated(QJsonDocument(duplicate));
  QVERIFY(!rejected);
  QVERIFY(rejected.error.contains(QStringLiteral("duplicate")));

  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse()));
  network.enqueue(jsonResponse(detailResponse()));
  network.enqueue(jsonResponse(detailResponse(5)));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);

  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();
  QCOMPARE(controller.availableSources().size(), 2);
  QCOMPARE(controller.preferredAudioTrack().value(QStringLiteral("language")),
           QStringLiteral("es"));
  QCOMPARE(controller.preferredSubtitleTrack().value(QStringLiteral("trackId")),
           QStringLiteral("no"));
  QCOMPARE(controller.clampWindowPosition(-100.0), 0.0);
  QCOMPARE(controller.clampWindowPosition(2'000.0), 1'800.0);

  controller.observeMpv(
      {{QStringLiteral("coreIdle"), false},
       {QStringLiteral("pausedForCache"), false},
       {QStringLiteral("paused"), false},
       {QStringLiteral("distanceFromLiveEdgeSeconds"), 10.0},
       {QStringLiteral("audioTracks"),
        QVariantList{
            QVariantMap{{QStringLiteral("id"), QStringLiteral("audio-1")},
                        {QStringLiteral("language"), QStringLiteral("en")},
                        {QStringLiteral("title"), QStringLiteral("Main")}},
            QVariantMap{{QStringLiteral("id"), QStringLiteral("audio-2")},
                        {QStringLiteral("language"), QStringLiteral("es")},
                        {QStringLiteral("title"), QStringLiteral("Spanish")}}}},
       {QStringLiteral("subtitleTracks"), QVariantList{}},
       {QStringLiteral("audioTrackId"), QStringLiteral("audio-2")},
       {QStringLiteral("subtitleTrackId"), QStringLiteral("no")}});
  QCOMPARE(controller.seekDeltaForWindowPosition(-5.0), -1'790.0);
  QCOMPARE(controller.seekDeltaForWindowPosition(99'000.0), 10.0);
  controller.selectTrack(QStringLiteral("audio"), QStringLiteral("audio-2"));
  scheduler.runDue();
  QCOMPARE(network.capturedRequests().size(), 3);
  const QJsonObject heartbeat =
      QJsonDocument::fromJson(network.capturedRequests().at(2).body).object();
  QCOMPARE(heartbeat.value(QStringLiteral("audioTrackId")).toString(),
           QStringLiteral("audio-2"));
  QCOMPARE(heartbeat.value(QStringLiteral("audioTrackLanguage")).toString(),
           QStringLiteral("es"));
  QCOMPARE(heartbeat.value(QStringLiteral("audioTrackTitle")).toString(),
           QStringLiteral("Spanish"));
  QCOMPARE(heartbeat.value(QStringLiteral("subtitleTrackId")).toString(),
           QStringLiteral("no"));

  controller.stop();
  scheduler.runDue();
}

void LivePlayerTests::
    controllerCreatesHeartbeatsObservesAndClearsWithoutLibraryCalls() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse()));
  network.enqueue(jsonResponse(detailResponse()));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);

  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"),
                   QStringLiteral("Fixture Event"));
  QCOMPARE(controller.state(), QStringLiteral("creating_session"));
  scheduler.runDue();
  scheduler.runDue();

  QCOMPARE(target.prepareCount, 1);
  QCOMPARE(target.loadCount, 1);
  QVERIFY(target.token.isEmpty());
  QCOMPARE(target.mode, QStringLiteral("client_direct"));
  QCOMPARE(target.url, QUrl(QStringLiteral(
                           "https://public.example.invalid/live/master.m3u8")));
  QCOMPARE(controller.revision(), qint64{4});
  QCOMPARE(network.capturedRequests().size(), 2);
  QCOMPARE(network.capturedRequests().at(0).operation,
           QNetworkAccessManager::PostOperation);
  QCOMPARE(network.capturedRequests().at(0).url.path(),
           QStringLiteral("/api/v1/live/sessions"));
  QVERIFY(!header(network.capturedRequests().at(0),
                  QByteArrayLiteral("Idempotency-Key"))
               .isEmpty());
  const QJsonObject createBody =
      QJsonDocument::fromJson(network.capturedRequests().at(0).body).object();
  QCOMPARE(createBody.value(QStringLiteral("providerId")).toString(),
           kProviderId);
  QVERIFY(!createBody.contains(QStringLiteral("mediaId")));

  const QJsonObject heartbeat =
      QJsonDocument::fromJson(network.capturedRequests().at(1).body).object();
  QCOMPARE(heartbeat.value(QStringLiteral("expectedRevision")).toInteger(),
           qint64{3});
  QCOMPARE(heartbeat.value(QStringLiteral("playerState")).toString(),
           QStringLiteral("loading"));
  for (const QString &forbidden :
       {QStringLiteral("positionSeconds"), QStringLiteral("durationSeconds"),
        QStringLiteral("mediaItemId"), QStringLiteral("eventType")}) {
    QVERIFY(!heartbeat.contains(forbidden));
  }

  controller.observeMpv(
      {{QStringLiteral("pausedForCache"), true},
       {QStringLiteral("distanceFromLiveEdgeSeconds"), 7.5},
       {QStringLiteral("audioTracks"),
        QVariantList{
            QVariantMap{{QStringLiteral("id"), QStringLiteral("audio-1")}}}},
       {QStringLiteral("subtitleTracks"), QVariantList{}}});
  QCOMPARE(controller.state(), QStringLiteral("buffering"));
  QVERIFY(controller.buffering());
  QCOMPARE(controller.distanceFromLiveEdge(), 7.5);

  controller.observeMpv({{QStringLiteral("pausedForCache"), true},
                         {QStringLiteral("coreIdle"), false},
                         {QStringLiteral("paused"), true}});
  QCOMPARE(controller.state(), QStringLiteral("paused"));
  QVERIFY(!controller.buffering());

  controller.observeMpv({{QStringLiteral("pausedForCache"), false},
                         {QStringLiteral("coreIdle"), false},
                         {QStringLiteral("paused"), false}});
  QCOMPARE(controller.state(), QStringLiteral("playing"));
  controller.routeExited();
  QCOMPARE(controller.state(), QStringLiteral("idle"));
  QVERIFY(target.token.isEmpty());
  QVERIFY(target.clearCount >= 2);
  scheduler.runDue();
  QCOMPARE(network.capturedRequests().size(), 3);
  QCOMPARE(network.capturedRequests().last().url.path(),
           QStringLiteral("/api/v1/live/sessions/") + kSessionId);
  QVERIFY(network.capturedRequests().last().url.query().contains(
      QStringLiteral("expectedRevision=4")));

  for (const CapturedNetworkRequest &request : network.capturedRequests()) {
    QVERIFY(request.url.path().startsWith(QStringLiteral("/api/v1/live/")));
    QVERIFY(!request.url.path().contains(QStringLiteral("playback/progress")));
    QVERIFY(!request.url.path().contains(QStringLiteral("media-interactions")));
    QVERIFY(!request.url.path().contains(QStringLiteral("up-next")));
    QVERIFY(!request.url.query().contains(QStringLiteral("token"),
                                          Qt::CaseInsensitive));
  }
}

void LivePlayerTests::relayTokenIsHeaderScopedAndClearedBetweenLoads() {
  QCOMPARE(MpvItem::authorizationHeaderFields(
               QStringLiteral("elx-live-token-v1.test-secret-value")),
           QVariantList{QStringLiteral(
               "Authorization: Bearer elx-live-token-v1.test-secret-value")});
  QVERIFY(MpvItem::authorizationHeaderFields(
              QStringLiteral("elx-live-token-v1.bad\r\nInjected: yes"))
              .isEmpty());
  QVERIFY(MpvItem::authorizationHeaderFields(QString()).isEmpty());

  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example:8443"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse(true)));
  network.enqueue(jsonResponse(detailResponse()));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);

  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();
  QCOMPARE(target.token,
           QByteArrayLiteral("elx-live-token-v1.test-secret-value"));
  QCOMPARE(target.url,
           QUrl(QStringLiteral("https://server.example:8443/api/v1/live/") +
                QStringLiteral("stream/") + kSessionId +
                QStringLiteral("/master.m3u8")));
  QVERIFY(!target.url.hasQuery());

  controller.stop();
  QVERIFY(target.token.isEmpty());
  scheduler.runDue();
  QVERIFY(QSettings()
              .value(QStringLiteral("live/pendingEndSessionId"))
              .toString()
              .isEmpty());
}

void LivePlayerTests::routeExitCancelsInflightHeartbeatWithoutFailureReentry() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse()));
  network.enqueue(jsonResponse(detailResponse(), 200, 50));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);

  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  QCOMPARE(controller.state(), QStringLiteral("loading"));
  QCOMPARE(network.capturedRequests().size(), 2);

  controller.routeExited();
  QCOMPARE(controller.state(), QStringLiteral("idle"));
  QVERIFY(controller.errorCode().isEmpty());
  QCOMPARE(network.capturedRequests().size(), 3);
  scheduler.runDue();
  scheduler.advance(50);
  QCOMPARE(controller.state(), QStringLiteral("idle"));
  QVERIFY(target.token.isEmpty());
}

void LivePlayerTests::failedEndIsRetriedOnTheNextAuthenticatedStart() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse()));
  network.enqueue(jsonResponse(detailResponse()));
  ScriptedHttpResponse failedEnd;
  failedEnd.networkError = QNetworkReply::TemporaryNetworkFailureError;
  network.enqueue(failedEnd);
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget firstTarget;
  {
    LivePlayerController first(&live, &firstTarget);
    first.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                QStringLiteral("lvk1.stream.abcdefghijklmnop"));
    scheduler.runDue();
    scheduler.runDue();
    first.routeExited();
    scheduler.runDue();
  }
  QCOMPARE(
      QSettings().value(QStringLiteral("live/pendingEndSessionId")).toString(),
      kSessionId);

  network.enqueue(emptyResponse());
  network.enqueue(jsonResponse(createdResponse()));
  network.enqueue(jsonResponse(detailResponse()));
  FakePlaybackTarget secondTarget;
  LivePlayerController second(&live, &secondTarget);
  const qsizetype before = network.capturedRequests().size();
  second.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
               QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  QCOMPARE(network.capturedRequests().size(), before + 2);
  QCOMPARE(network.capturedRequests().at(before).url.path(),
           QStringLiteral("/api/v1/live/sessions/") + kSessionId);
  QCOMPARE(network.capturedRequests().at(before + 1).operation,
           QNetworkAccessManager::PostOperation);
  scheduler.runDue();
  scheduler.runDue();
  QVERIFY(QSettings()
              .value(QStringLiteral("live/pendingEndSessionId"))
              .toString()
              .isEmpty());
}

void LivePlayerTests::
    c22RecoveryApiBuildsStrictRefreshAndManualFailoverRequests() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(
      jsonResponse(recoveredResponse(6, kSourceKey, QStringLiteral("Primary"),
                                     QByteArrayLiteral("token-refresh-0001"))));
  network.enqueue(jsonResponse(
      recoveredResponse(9, kBackupSourceKey, QStringLiteral("Backup"),
                        QByteArrayLiteral("token-backup-00002"))));
  LiveApiClient live(&auth, &network);
  QSignalSpy failed(&live, &LiveApiClient::requestFailed);

  const quint64 refreshId = live.refreshSession(
      kSessionId, 4, QStringLiteral("upstream_unauthorized"), 11);
  const quint64 failoverId = live.failoverSession(
      kSessionId, 6, QStringLiteral("manual_source_switch"), kBackupSourceKey,
      11);
  QVERIFY(refreshId > 0);
  QVERIFY(failoverId > refreshId);
  scheduler.runDue();

  QCOMPARE(network.capturedRequests().size(), 2);
  const CapturedNetworkRequest &refresh = network.capturedRequests().at(0);
  QCOMPARE(refresh.operation, QNetworkAccessManager::PostOperation);
  QCOMPARE(refresh.url.path(), QStringLiteral("/api/v1/live/sessions/") +
                                   kSessionId + QStringLiteral("/refresh"));
  QVERIFY(!refresh.url.hasQuery());
  QCOMPARE(header(refresh, QByteArrayLiteral("Authorization")),
           QByteArrayLiteral("Bearer account-access-token"));
  QJsonObject body = QJsonDocument::fromJson(refresh.body).object();
  QCOMPARE(body.value(QStringLiteral("expectedRevision")).toInteger(),
           qint64{4});
  QCOMPARE(body.value(QStringLiteral("reason")).toString(),
           QStringLiteral("upstream_unauthorized"));
  QVERIFY(!body.contains(QStringLiteral("requestedSourceKey")));

  const CapturedNetworkRequest &failover = network.capturedRequests().at(1);
  QCOMPARE(failover.url.path(), QStringLiteral("/api/v1/live/sessions/") +
                                    kSessionId + QStringLiteral("/failover"));
  body = QJsonDocument::fromJson(failover.body).object();
  QCOMPARE(body.value(QStringLiteral("reason")).toString(),
           QStringLiteral("manual_source_switch"));
  QCOMPARE(body.value(QStringLiteral("requestedSourceKey")).toString(),
           kBackupSourceKey);

  const quint64 invalidId = live.refreshSession(
      kSessionId, 9, QStringLiteral("manual_source_switch"), 11);
  QVERIFY(invalidId > failoverId);
  QCoreApplication::processEvents();
  QCOMPARE(network.capturedRequests().size(), 2);
  QCOMPARE(failed.size(), 1);
}

void LivePlayerTests::
    c22ControllerRefreshesThenFailsOverWithoutDuplicateActions() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse(true)));
  network.enqueue(jsonResponse(detailResponse(4)));
  network.enqueue(
      jsonResponse(recoveredResponse(6, kSourceKey, QStringLiteral("Primary"),
                                     QByteArrayLiteral("token-refresh-0001"))));
  network.enqueue(jsonResponse(detailResponse(7)));
  network.enqueue(jsonResponse(
      recoveredResponse(10, kBackupSourceKey, QStringLiteral("Backup"),
                        QByteArrayLiteral("token-backup-00002"))));
  network.enqueue(
      jsonResponse(detailResponse(11, QStringLiteral("playing"),
                                  kBackupSourceKey, QStringLiteral("Backup"))));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);

  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();
  QCOMPARE(controller.revision(), qint64{4});

  controller.observeMpv({{QStringLiteral("error"),
                          QStringLiteral("HTTP error 401 Unauthorized")}});
  controller.observeMpv({{QStringLiteral("error"),
                          QStringLiteral("HTTP error 401 Unauthorized")}});
  QCOMPARE(controller.state(), QStringLiteral("refreshing"));
  scheduler.runDue();
  scheduler.runDue();
  QCOMPARE(controller.revision(), qint64{7});
  QCOMPARE(target.token, QByteArrayLiteral("token-refresh-0001"));

  controller.observeMpv({{QStringLiteral("error"),
                          QStringLiteral("HTTP error 401 Unauthorized")}});
  QCOMPARE(controller.state(), QStringLiteral("switching_source"));
  scheduler.runDue();
  scheduler.runDue();
  QCOMPARE(controller.revision(), qint64{11});
  QCOMPARE(controller.selectedSourceLabel(), QStringLiteral("Backup"));
  QCOMPARE(target.token, QByteArrayLiteral("token-backup-00002"));
  QCOMPARE(target.loadCount, 3);

  int refreshRequests = 0;
  int failoverRequests = 0;
  for (const CapturedNetworkRequest &request : network.capturedRequests()) {
    refreshRequests += request.url.path().endsWith(QStringLiteral("/refresh"));
    failoverRequests +=
        request.url.path().endsWith(QStringLiteral("/failover"));
  }
  QCOMPARE(refreshRequests, 1);
  QCOMPARE(failoverRequests, 1);
  controller.stop();
  scheduler.runDue();
}

void LivePlayerTests::
    c22RefreshFailureResyncsRevisionBeforeAutomaticFailover() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse(true)));
  network.enqueue(jsonResponse(detailResponse(4)));
  network.enqueue(jsonResponse(
      errorResponse(QStringLiteral("LIVE_STREAM_UNAVAILABLE")), 502));
  network.enqueue(jsonResponse(detailResponse(6)));
  network.enqueue(jsonResponse(
      recoveredResponse(9, kBackupSourceKey, QStringLiteral("Backup"),
                        QByteArrayLiteral("token-backup-00002"))));
  network.enqueue(
      jsonResponse(detailResponse(10, QStringLiteral("playing"),
                                  kBackupSourceKey, QStringLiteral("Backup"))));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);

  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();
  controller.observeMpv(
      {{QStringLiteral("error"), QStringLiteral("HTTP error 403 Forbidden")}});
  scheduler.runDue();
  scheduler.runDue();
  scheduler.runDue();
  scheduler.runDue();

  QCOMPARE(controller.revision(), qint64{10});
  QCOMPARE(controller.selectedSourceLabel(), QStringLiteral("Backup"));
  QCOMPARE(network.capturedRequests().at(3).operation,
           QNetworkAccessManager::GetOperation);
  const QJsonObject failover =
      QJsonDocument::fromJson(network.capturedRequests().at(4).body).object();
  QCOMPARE(failover.value(QStringLiteral("expectedRevision")).toInteger(),
           qint64{6});
  QCOMPARE(failover.value(QStringLiteral("reason")).toString(),
           QStringLiteral("upstream_forbidden"));
  controller.stop();
  scheduler.runDue();
}

void LivePlayerTests::c22ManualSourceSwitchRotatesPlaybackExactlyOnce() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse(true)));
  network.enqueue(jsonResponse(detailResponse(4)));
  network.enqueue(jsonResponse(
      recoveredResponse(7, kBackupSourceKey, QStringLiteral("Backup"),
                        QByteArrayLiteral("manual-backup-token"))));
  network.enqueue(
      jsonResponse(detailResponse(8, QStringLiteral("playing"),
                                  kBackupSourceKey, QStringLiteral("Backup"))));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);
  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();

  controller.switchSource(kBackupSourceKey);
  QCOMPARE(controller.state(), QStringLiteral("switching_source"));
  scheduler.runDue();
  scheduler.runDue();

  QCOMPARE(controller.revision(), qint64{8});
  QCOMPARE(controller.selectedSourceLabel(), QStringLiteral("Backup"));
  QCOMPARE(target.token, QByteArrayLiteral("manual-backup-token"));
  QCOMPARE(target.loadCount, 2);
  const CapturedNetworkRequest &request = network.capturedRequests().at(2);
  QCOMPARE(request.url.path(), QStringLiteral("/api/v1/live/sessions/") +
                                   kSessionId + QStringLiteral("/failover"));
  const QJsonObject body = QJsonDocument::fromJson(request.body).object();
  QCOMPARE(body.value(QStringLiteral("expectedRevision")).toInteger(),
           qint64{4});
  QCOMPARE(body.value(QStringLiteral("reason")).toString(),
           QStringLiteral("manual_source_switch"));
  QCOMPARE(body.value(QStringLiteral("requestedSourceKey")).toString(),
           kBackupSourceKey);
  controller.stop();
  scheduler.runDue();
}

void LivePlayerTests::c22ExpiryThresholdRefreshesBeforeHeartbeatMutation() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(expiringCreatedResponse()));
  network.enqueue(jsonResponse(
      recoveredResponse(5, kSourceKey, QStringLiteral("Primary"),
                        QByteArrayLiteral("expiry-refresh-token"))));
  network.enqueue(jsonResponse(detailResponse(6)));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);
  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();
  scheduler.runDue();

  QCOMPARE(controller.revision(), qint64{6});
  QCOMPARE(network.capturedRequests().at(1).url.path(),
           QStringLiteral("/api/v1/live/sessions/") + kSessionId +
               QStringLiteral("/refresh"));
  const QJsonObject refresh =
      QJsonDocument::fromJson(network.capturedRequests().at(1).body).object();
  QCOMPARE(refresh.value(QStringLiteral("expectedRevision")).toInteger(),
           qint64{3});
  QCOMPARE(refresh.value(QStringLiteral("reason")).toString(),
           QStringLiteral("expiry_threshold"));
  QCOMPARE(target.token, QByteArrayLiteral("expiry-refresh-token"));
  controller.stop();
  scheduler.runDue();
}

void LivePlayerTests::c22ExpectedEndAndExhaustionDoNotEnterRetryLoops() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));

  {
    DeterministicScheduler scheduler;
    ScriptedNetworkAccessManager network(scheduler);
    network.enqueue(jsonResponse(createdResponse()));
    network.enqueue(jsonResponse(detailResponse(4)));
    network.enqueue(emptyResponse());
    LiveApiClient live(&auth, &network);
    FakePlaybackTarget target;
    LivePlayerController controller(&live, &target);
    controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                     QStringLiteral("lvk1.stream.abcdefghijklmnop"), {},
                     QDateTime::currentDateTimeUtc().addSecs(5));
    scheduler.runDue();
    scheduler.runDue();
    controller.observeMpv({{QStringLiteral("eofReached"), true}});
    QCOMPARE(controller.state(), QStringLiteral("ended"));
    scheduler.runDue();
    for (const CapturedNetworkRequest &request : network.capturedRequests()) {
      QVERIFY(!request.url.path().endsWith(QStringLiteral("/refresh")));
      QVERIFY(!request.url.path().endsWith(QStringLiteral("/failover")));
    }
  }

  {
    DeterministicScheduler scheduler;
    ScriptedNetworkAccessManager network(scheduler);
    network.enqueue(jsonResponse(createdResponse(true)));
    network.enqueue(jsonResponse(detailResponse(4)));
    network.enqueue(jsonResponse(
        errorResponse(QStringLiteral("LIVE_FAILOVER_EXHAUSTED"), false), 503));
    network.enqueue(emptyResponse());
    LiveApiClient live(&auth, &network);
    FakePlaybackTarget target;
    LivePlayerController controller(&live, &target);
    controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                     QStringLiteral("lvk1.stream.abcdefghijklmnop"));
    scheduler.runDue();
    scheduler.runDue();
    controller.observeMpv(
        {{QStringLiteral("error"), QStringLiteral("HTTP 401 Unauthorized")}});
    scheduler.runDue();
    scheduler.runDue();
    QCOMPARE(controller.state(), QStringLiteral("unavailable"));
    QCOMPARE(controller.errorCode(), QStringLiteral("LIVE_FAILOVER_EXHAUSTED"));
    const qsizetype requestCount = network.capturedRequests().size();
    scheduler.runDue();
    QCOMPARE(network.capturedRequests().size(), requestCount);
  }
}

void LivePlayerTests::c22ReconnectPolicyIsBoundedAndCancellationStopsReloads() {
  constexpr std::array<int, 5> caps{1'000, 2'000, 4'000, 8'000, 15'000};
  for (int attempt = 0; attempt < static_cast<int>(caps.size()); ++attempt) {
    const int delay =
        LivePlayerController::reconnectDelayMs(kSessionId, attempt);
    QVERIFY(delay >= 0);
    QVERIFY(delay <= caps[static_cast<std::size_t>(attempt)]);
    QCOMPARE(delay,
             LivePlayerController::reconnectDelayMs(kSessionId, attempt));
  }
  QCOMPARE(LivePlayerController::reconnectDelayMs(kSessionId, 5), -1);

  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse()));
  network.enqueue(jsonResponse(detailResponse(4)));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);
  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();

  const qsizetype beforeInvalidSwitch = network.capturedRequests().size();
  controller.switchSource(kSourceKey);
  QCOMPARE(controller.errorCode(),
           QStringLiteral("LIVE_CLIENT_INVALID_REQUEST"));
  QCOMPARE(network.capturedRequests().size(), beforeInvalidSwitch);

  controller.observeMpv(
      {{QStringLiteral("error"), QStringLiteral("connection reset")}});
  QCOMPARE(controller.state(), QStringLiteral("reconnecting"));
  QCOMPARE(controller.reconnectAttempt(), 1);
  controller.retryRecoveryNow();
  QCOMPARE(controller.state(), QStringLiteral("loading"));
  QCOMPARE(target.loadCount, 2);
  controller.observeMpv({{QStringLiteral("eofReached"), true}});
  QCOMPARE(controller.reconnectAttempt(), 2);
  controller.cancelRecovery();
  QCOMPARE(controller.state(), QStringLiteral("unavailable"));
  const int loads = target.loadCount;
  scheduler.runDue();
  QCOMPARE(target.loadCount, loads);
}

void LivePlayerTests::c22RouteExitDiscardsDelayedRecoveryReplyAndToken() {
  ApiClient auth;
  auth.setBaseUrl(QStringLiteral("https://server.example"));
  auth.setAuthToken(QStringLiteral("account-access-token"));
  DeterministicScheduler scheduler;
  ScriptedNetworkAccessManager network(scheduler);
  network.enqueue(jsonResponse(createdResponse(true)));
  network.enqueue(jsonResponse(detailResponse(4)));
  network.enqueue(
      jsonResponse(recoveredResponse(6, kSourceKey, QStringLiteral("Primary"),
                                     QByteArrayLiteral("late-secret-token")),
                   200, 50));
  network.enqueue(emptyResponse());
  LiveApiClient live(&auth, &network);
  FakePlaybackTarget target;
  LivePlayerController controller(&live, &target);
  controller.start(kProviderId, QStringLiteral("lvk1.item.abcdefghijklmnop"),
                   QStringLiteral("lvk1.stream.abcdefghijklmnop"));
  scheduler.runDue();
  scheduler.runDue();
  controller.observeMpv(
      {{QStringLiteral("error"), QStringLiteral("HTTP 410 Gone")}});
  QCOMPARE(controller.state(), QStringLiteral("refreshing"));
  controller.routeExited();
  QCOMPARE(controller.state(), QStringLiteral("idle"));
  scheduler.runDue();
  scheduler.advance(50);
  QCOMPARE(controller.state(), QStringLiteral("idle"));
  QCOMPARE(target.loadCount, 1);
  QVERIFY(target.token.isEmpty());
}

QTEST_GUILESS_MAIN(LivePlayerTests)

#include "LivePlayerTests.moc"
