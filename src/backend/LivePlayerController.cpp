#include "backend/LivePlayerController.h"

#include "backend/ApiClient.h"
#include "backend/MpvItem.h"
#include "live/LiveApiClient.h"

#include <QCryptographicHash>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSettings>
#include <QSysInfo>
#include <QUrlQuery>
#include <QUuid>

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <utility>

namespace {

constexpr auto kPendingSessionKey = "live/pendingEndSessionId";
constexpr auto kPendingRevisionKey = "live/pendingEndRevision";
constexpr auto kPendingServerKey = "live/pendingEndServer";
constexpr auto kPendingAccountSessionKey = "live/pendingEndAccountSession";
constexpr int kStallWindowMs = 5'000;
constexpr int kStablePlaybackMs = 10'000;
constexpr int kRefreshLeadMs = 60'000;
constexpr int kMaximumClientFailovers = 2;
constexpr std::array<int, 5> kReconnectCapsMs{1'000, 2'000, 4'000, 8'000,
                                              15'000};

void erase(QByteArray *value) {
  if (!value) {
    return;
  }
  std::fill(value->begin(), value->end(), '\0');
  value->clear();
  value->squeeze();
}

bool terminal(const QString &state) {
  return state == QStringLiteral("ended") ||
         state == QStringLiteral("expired") ||
         state == QStringLiteral("failed");
}

QString fallbackFailureMessage(const QString &code) {
  if (code == QStringLiteral("LIVE_STREAM_UNAVAILABLE") ||
      code == QStringLiteral("LIVE_STREAM_EXPIRED")) {
    return QStringLiteral(
        "This stream is no longer available. Reload the event to see current options.");
  }
  if (code == QStringLiteral("LIVE_PROTOCOL_UNSUPPORTED")) {
    return QStringLiteral("This stream is not compatible with this client.");
  }
  if (code == QStringLiteral("LIVE_FAILOVER_EXHAUSTED")) {
    return QStringLiteral("Playback could not recover using the available sources.");
  }
  if (code == QStringLiteral("LIVE_SESSION_EXPIRED") ||
      code == QStringLiteral("LIVE_SESSION_NOT_FOUND")) {
    return QStringLiteral("This Live session has ended. Reload the event to try again.");
  }
  return QStringLiteral("Playback could not be completed.");
}

QString boundedTrackText(const QVariant &value, qsizetype maximum) {
  const QString text = value.toString();
  if (text.isEmpty() || text.size() > maximum || text.trimmed() != text) {
    return {};
  }
  for (const QChar character : text) {
    if (character.isLowSurrogate() || character.isHighSurrogate() ||
        character.category() == QChar::Other_Control) {
      return {};
    }
  }
  return text;
}

QVariantList boundedTrackList(const QVariant &value) {
  const QVariantList input = value.toList();
  QVariantList output;
  output.reserve(std::min<qsizetype>(input.size(), 64));
  for (const QVariant &entry : input) {
    if (output.size() >= 64) {
      break;
    }
    const QVariantMap track = entry.toMap();
    const QString id = boundedTrackText(track.value(QStringLiteral("id")), 256);
    if (id.isEmpty()) {
      continue;
    }
    QVariantMap normalized{{QStringLiteral("id"), id}};
    for (const auto &[key, maximum] :
         std::array<std::pair<QString, qsizetype>, 4>{
             std::pair{QStringLiteral("label"), qsizetype{256}},
             std::pair{QStringLiteral("language"), qsizetype{64}},
             std::pair{QStringLiteral("title"), qsizetype{256}},
             std::pair{QStringLiteral("selected"), qsizetype{0}}}) {
      if (key == QStringLiteral("selected")) {
        normalized.insert(key, track.value(key).toBool());
        continue;
      }
      const QString text = boundedTrackText(track.value(key), maximum);
      if (!text.isEmpty()) {
        normalized.insert(key, text);
      }
    }
    output.append(normalized);
  }
  return output;
}

} // namespace

LivePlayerController::LivePlayerController(LiveApiClient *api, QObject *parent)
    : LivePlayerController(api, nullptr, parent) {}

LivePlayerController::LivePlayerController(LiveApiClient *api,
                                           LivePlaybackTarget *target,
                                           QObject *parent)
    : QObject(parent), m_api(api), m_target(target) {
  m_heartbeatTimer.setSingleShot(false);
  connect(&m_heartbeatTimer, &QTimer::timeout, this,
          &LivePlayerController::sendHeartbeatNow);
  m_stallTimer.setSingleShot(true);
  m_stallTimer.setInterval(kStallWindowMs);
  connect(&m_stallTimer, &QTimer::timeout, this, [this]() {
    if (m_buffering) {
      beginTransportRecovery(QStringLiteral("stalled"));
    }
  });
  m_reconnectTimer.setSingleShot(true);
  connect(&m_reconnectTimer, &QTimer::timeout, this,
          &LivePlayerController::performTransportReconnect);
  m_countdownTimer.setSingleShot(false);
  m_countdownTimer.setInterval(1'000);
  connect(&m_countdownTimer, &QTimer::timeout, this, [this]() {
    if (m_reconnectSecondsRemaining > 0) {
      --m_reconnectSecondsRemaining;
      emit recoveryChanged();
    }
    if (m_reconnectSecondsRemaining <= 0) {
      m_countdownTimer.stop();
    }
  });
  m_expiryTimer.setSingleShot(true);
  connect(&m_expiryTimer, &QTimer::timeout, this,
          &LivePlayerController::scheduleExpiryRefresh);
  m_stableTimer.setSingleShot(true);
  m_stableTimer.setInterval(kStablePlaybackMs);
  connect(&m_stableTimer, &QTimer::timeout, this,
          &LivePlayerController::resetStableRecoveryState);
  connectApi();
}

LivePlayerController::~LivePlayerController() { closeSession(false); }

QString LivePlayerController::state() const { return m_state; }
QString LivePlayerController::sessionId() const { return m_sessionId; }
qint64 LivePlayerController::revision() const { return m_revision; }
QString LivePlayerController::playbackUrl() const { return m_playbackUrl; }
QString LivePlayerController::deliveryMode() const { return m_deliveryMode; }
QString LivePlayerController::egressMode() const { return m_egressMode; }
bool LivePlayerController::seekable() const { return m_seekable; }
int LivePlayerController::windowSeconds() const { return m_windowSeconds; }
double LivePlayerController::distanceFromLiveEdge() const {
  return m_distanceFromLiveEdge;
}
bool LivePlayerController::buffering() const { return m_buffering; }
bool LivePlayerController::recovering() const {
  return m_recoveryAction != RecoveryAction::None ||
         m_reconcileAction != ReconcileAction::None ||
         m_reconnectTimer.isActive() ||
         m_state == QStringLiteral("reconnecting") ||
         m_state == QStringLiteral("refreshing") ||
         m_state == QStringLiteral("switching_source");
}
int LivePlayerController::reconnectAttempt() const {
  return m_reconnectAttempt;
}
int LivePlayerController::reconnectSecondsRemaining() const {
  return m_reconnectSecondsRemaining;
}
QString LivePlayerController::selectedSourceLabel() const {
  return m_sourceLabel;
}
QString LivePlayerController::selectedSourceKey() const { return m_sourceKey; }
QString LivePlayerController::selectedSourceQuality() const {
  return m_sourceQuality;
}
QVariantList LivePlayerController::availableSources() const {
  return m_availableSources;
}
QVariantMap LivePlayerController::preferredAudioTrack() const {
  return m_preferredAudioTrack;
}
QVariantMap LivePlayerController::preferredSubtitleTrack() const {
  return m_preferredSubtitleTrack;
}
QVariantList LivePlayerController::audioTracks() const { return m_audioTracks; }
QVariantList LivePlayerController::subtitleTracks() const {
  return m_subtitleTracks;
}
QString LivePlayerController::errorCode() const { return m_errorCode; }
QString LivePlayerController::failureMessage() const {
  return m_failureMessage;
}
bool LivePlayerController::failureRetryable() const {
  return m_failureRetryable;
}

QString LivePlayerController::statusText() const {
  if (m_state == QStringLiteral("playing")) {
    return m_distanceFromLiveEdge > 5.0 ? QStringLiteral("Behind live")
                                        : QStringLiteral("Live");
  }
  if (m_state == QStringLiteral("buffering")) {
    return QStringLiteral("Buffering");
  }
  if (m_state == QStringLiteral("reconnecting")) {
    return QStringLiteral("Reconnecting");
  }
  if (m_state == QStringLiteral("refreshing")) {
    return QStringLiteral("Refreshing stream");
  }
  if (m_state == QStringLiteral("switching_source")) {
    return QStringLiteral("Switching source");
  }
  if (m_state == QStringLiteral("creating_session") ||
      m_state == QStringLiteral("loading")) {
    return QStringLiteral("Starting");
  }
  if (m_state == QStringLiteral("ended")) {
    return QStringLiteral("Event ended");
  }
  if (m_state == QStringLiteral("unavailable")) {
    return QStringLiteral("Unavailable");
  }
  return {};
}

bool LivePlayerController::attachPlayer(QObject *player) {
  auto *mpv = qobject_cast<MpvItem *>(player);
  if (!mpv) {
    return false;
  }
  if (m_target && m_target != mpv) {
    m_target->clearLivePlayback();
  }
  m_mpv = mpv;
  m_target = mpv;
  connect(mpv, &QObject::destroyed, this, [this, mpv]() {
    if (m_mpv == mpv) {
      m_mpv = nullptr;
      m_target = nullptr;
    }
  });
  return true;
}

void LivePlayerController::start(const QString &providerId,
                                 const QString &itemKey,
                                 const QString &streamOptionKey,
                                 const QString &title,
                                 const QDateTime &expectedEndUtc) {
  closeSession(false);
  ++m_generation;
  m_title = title.left(256);
  m_expectedEndUtc = expectedEndUtc.toUTC();
  m_providerId = providerId;
  m_itemKey = itemKey;
  m_streamOptionKey = streamOptionKey;
  m_idempotencyKey =
      QStringLiteral("live-%1").arg(QUuid::createUuid().toString(QUuid::Id128));
  m_errorCode.clear();
  m_failureMessage.clear();
  m_failureRetryable = false;
  emit errorChanged();
  if (!m_api || !m_target) {
    fail(QStringLiteral("LIVE_CLIENT_PLAYER_UNAVAILABLE"));
    return;
  }
  retryPendingEnd();
  setState(QStringLiteral("creating_session"));
  m_createRequest =
      m_api->createSession(providerId, itemKey, streamOptionKey, capabilities(),
                           m_idempotencyKey, m_generation);
}

void LivePlayerController::stop() { closeSession(true); }

void LivePlayerController::routeExited() { closeSession(false); }

void LivePlayerController::sendHeartbeatNow() {
  if (!m_api || m_sessionId.isEmpty() || m_revision < 1 ||
      !(m_state == QStringLiteral("loading") ||
        m_state == QStringLiteral("playing") ||
        m_state == QStringLiteral("buffering") ||
        m_state == QStringLiteral("paused")) ||
      m_controlRequest != 0 || m_recoveryRequest != 0 ||
      m_reconcileRequest != 0 || m_reconnectTimer.isActive()) {
    return;
  }
  QVariantMap observation{
      {QStringLiteral("playerState"), playerState()},
      {QStringLiteral("observedAt"),
       QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
      {QStringLiteral("distanceFromLiveEdgeSeconds"),
       std::max(0.0, m_distanceFromLiveEdge)},
      {QStringLiteral("sourceKey"), m_sourceKey},
  };
  const auto addTrack =
      [&observation](const QString &prefix, const QString &trackId,
                     const QString &language, const QString &title) {
        if (trackId.isEmpty()) {
          return;
        }
        observation.insert(prefix + QStringLiteral("Id"), trackId);
        if (!language.isEmpty()) {
          observation.insert(prefix + QStringLiteral("Language"), language);
        }
        if (!title.isEmpty()) {
          observation.insert(prefix + QStringLiteral("Title"), title);
        }
      };
  addTrack(QStringLiteral("audioTrack"), m_audioTrackId, m_audioTrackLanguage,
           m_audioTrackTitle);
  addTrack(QStringLiteral("subtitleTrack"), m_subtitleTrackId,
           m_subtitleTrackLanguage, m_subtitleTrackTitle);
  m_controlRequest = m_api->heartbeatSession(m_sessionId, m_revision,
                                             observation, m_generation);
  m_sentTrackSelectionVersion = m_trackSelectionVersion;
}

void LivePlayerController::observeMpv(const QVariantMap &observation) {
  if (m_sessionId.isEmpty()) {
    return;
  }
  const bool coreIdle = observation.value(QStringLiteral("coreIdle")).toBool();
  const bool pausedForCache =
      observation.value(QStringLiteral("pausedForCache")).toBool();
  const bool paused = observation.value(QStringLiteral("paused")).toBool();
  const bool nextBuffering = !paused && (coreIdle || pausedForCache);
  const double distance =
      observation.value(QStringLiteral("distanceFromLiveEdgeSeconds"))
          .toDouble();
  if (std::isfinite(distance) && distance >= 0.0) {
    m_distanceFromLiveEdge = distance;
  }
  m_buffering = nextBuffering;
  m_audioTracks =
      boundedTrackList(observation.value(QStringLiteral("audioTracks")));
  m_subtitleTracks =
      boundedTrackList(observation.value(QStringLiteral("subtitleTracks")));
  updateObservedTrackSelection(
      QStringLiteral("audio"),
      boundedTrackText(observation.value(QStringLiteral("audioTrackId")), 256),
      m_audioTracks);
  updateObservedTrackSelection(
      QStringLiteral("subtitle"),
      boundedTrackText(observation.value(QStringLiteral("subtitleTrackId")),
                       256),
      m_subtitleTracks);
  emit observationChanged();

  const QString playerError =
      observation.value(QStringLiteral("error")).toString().left(512);
  if (!playerError.isEmpty()) {
    const QString reason = classifyMpvError(playerError);
    if (reason == QStringLiteral("upstream_unauthorized") ||
        reason == QStringLiteral("upstream_forbidden") ||
        reason == QStringLiteral("upstream_gone")) {
      requestRefresh(reason);
    } else {
      beginTransportRecovery(reason);
    }
    return;
  }
  if (observation.value(QStringLiteral("eofReached")).toBool()) {
    const bool expected =
        m_expectedEndUtc.isValid() &&
        QDateTime::currentDateTimeUtc() >= m_expectedEndUtc.addSecs(-30);
    if (expected) {
      closeSession(true);
    } else {
      beginTransportRecovery(QStringLiteral("transport"));
    }
    return;
  }
  if (recovering()) {
    return;
  }
  if (nextBuffering) {
    m_stableTimer.stop();
    if (!m_stallTimer.isActive()) {
      m_stallTimer.start();
    }
  } else {
    m_stallTimer.stop();
    if (!paused && !m_stableTimer.isActive()) {
      m_stableTimer.start();
    }
  }
  setState(nextBuffering ? QStringLiteral("buffering")
                         : (paused ? QStringLiteral("paused")
                                   : QStringLiteral("playing")));
}

void LivePlayerController::updateObservedTrackSelection(
    const QString &type, const QString &trackId, const QVariantList &tracks) {
  QString language;
  QString title;
  for (const QVariant &entry : tracks) {
    const QVariantMap track = entry.toMap();
    if (track.value(QStringLiteral("id")).toString() == trackId) {
      language = track.value(QStringLiteral("language")).toString().toLower();
      language.replace('_', '-');
      title = track.value(QStringLiteral("title")).toString();
      break;
    }
  }
  QString *currentId = nullptr;
  QString *currentLanguage = nullptr;
  QString *currentTitle = nullptr;
  if (type == QStringLiteral("audio")) {
    currentId = &m_audioTrackId;
    currentLanguage = &m_audioTrackLanguage;
    currentTitle = &m_audioTrackTitle;
  } else if (type == QStringLiteral("subtitle")) {
    currentId = &m_subtitleTrackId;
    currentLanguage = &m_subtitleTrackLanguage;
    currentTitle = &m_subtitleTrackTitle;
  } else {
    return;
  }
  if (*currentId == trackId && *currentLanguage == language &&
      *currentTitle == title) {
    return;
  }
  *currentId = trackId;
  *currentLanguage = language;
  *currentTitle = title;
  ++m_trackSelectionVersion;
}

void LivePlayerController::selectTrack(const QString &type,
                                       const QString &trackId) {
  const bool subtitleOff =
      type == QStringLiteral("subtitle") && trackId == QStringLiteral("no");
  const QVariantList *tracks = type == QStringLiteral("audio") ? &m_audioTracks
                               : type == QStringLiteral("subtitle")
                                   ? &m_subtitleTracks
                                   : nullptr;
  if (!tracks || trackId.isEmpty() || trackId.size() > 256 ||
      (!subtitleOff &&
       std::none_of(
           tracks->cbegin(), tracks->cend(), [&trackId](const QVariant &entry) {
             return entry.toMap().value(QStringLiteral("id")).toString() ==
                    trackId;
           }))) {
    m_errorCode = QStringLiteral("LIVE_CLIENT_INVALID_REQUEST");
    emit errorChanged();
    return;
  }
  updateObservedTrackSelection(type, trackId, *tracks);
  sendHeartbeatNow();
}

void LivePlayerController::switchSource(const QString &sourceKey) {
  static const QRegularExpression opaque(
      QStringLiteral("^[A-Za-z0-9._~-]{16,2048}$"));
  const bool available = std::any_of(
      m_availableSources.cbegin(), m_availableSources.cend(),
      [&sourceKey](const QVariant &source) {
        return source.toMap().value(QStringLiteral("sourceKey")).toString() ==
               sourceKey;
      });
  if (!opaque.match(sourceKey).hasMatch() || sourceKey == m_sourceKey ||
      !available) {
    m_errorCode = QStringLiteral("LIVE_CLIENT_INVALID_REQUEST");
    emit errorChanged();
    return;
  }
  requestFailover(QStringLiteral("manual_source_switch"), sourceKey);
}

double LivePlayerController::clampWindowPosition(double seconds) const {
  if (!m_seekable || m_windowSeconds < 1 || !std::isfinite(seconds)) {
    return 0.0;
  }
  return std::clamp(seconds, 0.0, static_cast<double>(m_windowSeconds));
}

double LivePlayerController::seekDeltaForWindowPosition(double seconds) const {
  if (!m_seekable || m_windowSeconds < 1) {
    return 0.0;
  }
  const double position = clampWindowPosition(seconds);
  const double currentDistance = std::clamp(
      m_distanceFromLiveEdge, 0.0, static_cast<double>(m_windowSeconds));
  const double desiredDistance =
      static_cast<double>(m_windowSeconds) - position;
  return currentDistance - desiredDistance;
}

void LivePlayerController::cancelRecovery() {
  if (!recovering()) {
    return;
  }
  closeSession(false);
  setState(QStringLiteral("unavailable"));
}

void LivePlayerController::retryRecoveryNow() {
  if (!m_reconnectTimer.isActive()) {
    return;
  }
  m_reconnectTimer.stop();
  m_countdownTimer.stop();
  m_reconnectSecondsRemaining = 0;
  emit recoveryChanged();
  performTransportReconnect();
}

int LivePlayerController::reconnectDelayMs(const QString &sessionId,
                                           int zeroBasedAttempt) {
  if (zeroBasedAttempt < 0 ||
      zeroBasedAttempt >= static_cast<int>(kReconnectCapsMs.size())) {
    return -1;
  }
  const QByteArray seed =
      sessionId.toUtf8() + ':' + QByteArray::number(zeroBasedAttempt);
  const QByteArray digest =
      QCryptographicHash::hash(seed, QCryptographicHash::Sha256);
  const auto *bytes =
      reinterpret_cast<const unsigned char *>(digest.constData());
  const quint32 sample = (static_cast<quint32>(bytes[0]) << 24U) |
                         (static_cast<quint32>(bytes[1]) << 16U) |
                         (static_cast<quint32>(bytes[2]) << 8U) |
                         static_cast<quint32>(bytes[3]);
  const quint32 range =
      static_cast<quint32>(
          kReconnectCapsMs[static_cast<std::size_t>(zeroBasedAttempt)]) +
      1U;
  return static_cast<int>(sample % range);
}

void LivePlayerController::connectApi() {
  if (!m_api) {
    return;
  }
  connect(m_api, &LiveApiClient::sessionCreated, this,
          &LivePlayerController::handleCreated);
  connect(m_api, &LiveApiClient::sessionDetailReceived, this,
          &LivePlayerController::handleDetail);
  connect(m_api, &LiveApiClient::sessionRecovered, this,
          &LivePlayerController::handleRecovered);
  connect(m_api, &LiveApiClient::requestFailed, this,
          [this](quint64 requestId, quint64 generation, const QString &,
                 const QVariantMap &error) {
            handleFailure(requestId, generation, error);
          });
  connect(m_api, &LiveApiClient::requestCancelled, this,
          [this](quint64 requestId, quint64 generation) {
            if (requestIsCurrent(requestId, generation)) {
              handleFailure(requestId, generation,
                            {{QStringLiteral("code"),
                              QStringLiteral("LIVE_CLIENT_CANCELLED")}});
            }
          });
  connect(
      m_api, &LiveApiClient::sessionEnded, this,
      [this](quint64 requestId, quint64 generation, const QString &sessionId) {
        Q_UNUSED(generation)
        if (requestId == m_endRequest) {
          m_endRequest = 0;
          clearPendingEnd(sessionId);
        }
      });
  connect(m_api, &LiveApiClient::authContextInvalidated, this, [this]() {
    closeSession(false);
    QTimer::singleShot(0, this, &LivePlayerController::retryPendingEnd);
  });
}

void LivePlayerController::handleCreated(quint64 requestId, quint64 generation,
                                         const Live::SessionCreated &session) {
  if (requestId == m_reconcileRequest && generation == m_generation &&
      m_reconcileAction == ReconcileAction::ReplayCreate) {
    m_reconcileRequest = 0;
    m_reconcileAction = ReconcileAction::None;
    if (!applySession(session, false)) {
      finishRecoveryFailure(QStringLiteral("LIVE_CLIENT_RECOVERY_INVALID"),
                            true);
    }
    return;
  }
  if (requestId != m_createRequest || generation != m_generation) {
    return;
  }
  m_createRequest = 0;
  if (!applySession(session, true)) {
    fail(QStringLiteral("LIVE_CLIENT_PLAYBACK_URL_REJECTED"));
  }
}

void LivePlayerController::handleDetail(
    quint64 requestId, quint64 generation,
    const Live::SessionDetailEnvelope &envelope) {
  if (requestId == m_reconcileRequest && generation == m_generation &&
      envelope.data.sessionId == m_sessionId) {
    m_reconcileRequest = 0;
    if (envelope.data.revision < m_revision) {
      finishRecoveryFailure(QStringLiteral("LIVE_CLIENT_REVISION_REGRESSION"),
                            true);
      return;
    }
    m_revision = envelope.data.revision;
    applySourceAndTrackState(envelope.data.selectedSource,
                             envelope.data.availableSources,
                             envelope.data.trackPreferences);
    emit sessionChanged();
    if (terminal(envelope.data.state)) {
      m_reconcileAction = ReconcileAction::None;
      finishRecoveryFailure(envelope.data.errorCode.isEmpty()
                                ? QStringLiteral("LIVE_FAILOVER_EXHAUSTED")
                                : envelope.data.errorCode,
                            true);
      return;
    }
    const ReconcileAction action = m_reconcileAction;
    const QString reason = m_pendingRecoveryReason;
    m_reconcileAction = ReconcileAction::None;
    if (action == ReconcileAction::Failover) {
      requestFailover(reason.isEmpty() ? QStringLiteral("transport") : reason);
    }
    return;
  }
  if (requestId != m_controlRequest || generation != m_generation ||
      envelope.data.sessionId != m_sessionId) {
    return;
  }
  m_controlRequest = 0;
  if (envelope.data.revision < m_revision) {
    return;
  }
  m_revision = envelope.data.revision;
  applySourceAndTrackState(envelope.data.selectedSource,
                           envelope.data.availableSources,
                           envelope.data.trackPreferences);
  emit sessionChanged();
  if (m_trackSelectionVersion > m_sentTrackSelectionVersion) {
    QMetaObject::invokeMethod(this, &LivePlayerController::sendHeartbeatNow,
                              Qt::QueuedConnection);
  }
  if (terminal(envelope.data.state)) {
    clearPlaybackSecrets();
    setState(envelope.data.state == QStringLiteral("ended")
                 ? QStringLiteral("ended")
                 : QStringLiteral("unavailable"));
  }
}

void LivePlayerController::handleRecovered(
    quint64 requestId, quint64 generation,
    const Live::SessionCreated &session) {
  if (requestId != m_recoveryRequest || generation != m_generation) {
    return;
  }
  const qint64 expectedRevision =
      m_revision + (m_recoveryAction == RecoveryAction::Refresh ? 2 : 3);
  m_recoveryRequest = 0;
  if (session.revision != expectedRevision || !applySession(session, false)) {
    finishRecoveryFailure(QStringLiteral("LIVE_CLIENT_RECOVERY_INVALID"), true);
  }
}

bool LivePlayerController::applySession(const Live::SessionCreated &session,
                                        bool initial) {
  if (!m_api || !m_target || session.revision < 1 ||
      (!initial &&
       (session.sessionId != m_sessionId || session.revision < m_revision))) {
    return false;
  }
  const QUrl url = validatedPlaybackUrl(session);
  if (!url.isValid()) {
    return false;
  }
  const QString previousSource = m_sourceKey;
  const QString previousDeliveryMode = m_deliveryMode;
  if (initial) {
    m_sessionId = session.sessionId;
    m_serverScope = m_api->serverBaseUrl();
    m_accountSessionScope = m_api->accountSessionId();
  }
  m_revision = session.revision;
  m_playbackUrl = url.toString(QUrl::FullyEncoded);
  m_deliveryMode = session.deliveryMode;
  m_egressMode = session.egress.mode;
  erase(&m_sessionToken);
  m_sessionToken = session.sessionToken;
  m_seekable = session.live.seekable;
  m_windowSeconds = session.live.windowSeconds.value_or(0);
  applySourceAndTrackState(session.selectedSource, session.availableSources,
                           session.trackPreferences);
  m_expiresAtUtc = session.expiresAtUtc;
  m_lowLatency = session.live.targetLatencySeconds.has_value();
  if (!initial && (previousSource != m_sourceKey ||
                   previousDeliveryMode != m_deliveryMode)) {
    m_refreshAttemptedForSource = false;
    m_reconnectAttempt = 0;
  }
  m_recoveryAction = RecoveryAction::None;
  m_reconcileAction = ReconcileAction::None;
  m_pendingRecoveryReason.clear();
  m_reconnectTimer.stop();
  m_countdownTimer.stop();
  m_stallTimer.stop();
  m_stableTimer.stop();
  m_reconnectSecondsRemaining = 0;
  emit recoveryChanged();
  emit sessionChanged();
  emit liveWindowChanged();
  m_heartbeatTimer.start(session.heartbeatIntervalSeconds * 1000);
  emit egressChanged();
  beginPlaybackLoad(url);
  scheduleExpiryRefresh();
  sendHeartbeatNow();
  return true;
}

void LivePlayerController::beginPlaybackLoad(const QUrl &url) {
  if (!m_target || !url.isValid()) {
    fail(QStringLiteral("LIVE_CLIENT_PLAYBACK_URL_REJECTED"));
    return;
  }
  m_target->prepareLivePlayback(m_sessionToken, m_deliveryMode, m_lowLatency);
  m_target->loadLiveUrl(url);
  emit playbackLoadRequested(url);
  setState(QStringLiteral("loading"));
}

void LivePlayerController::applySourceAndTrackState(
    const Live::SelectedSource &selectedSource,
    const QList<Live::SelectedSource> &sources,
    const Live::TrackPreferences &preferences) {
  m_sourceKey = selectedSource.sourceKey;
  m_sourceLabel = selectedSource.label;
  m_sourceQuality = selectedSource.quality;
  m_availableSources.clear();
  m_availableSources.reserve(sources.size());
  for (const Live::SelectedSource &source : sources) {
    m_availableSources.append(source.toVariantMap());
  }
  m_preferredAudioTrack =
      preferences.audio ? preferences.audio->toVariantMap() : QVariantMap{};
  m_preferredSubtitleTrack = preferences.subtitle
                                 ? preferences.subtitle->toVariantMap()
                                 : QVariantMap{};
}

void LivePlayerController::beginTransportRecovery(const QString &reason) {
  if (!m_api || !m_target || m_sessionId.isEmpty() || m_revision < 1 ||
      terminal(m_state) || m_recoveryRequest != 0 || m_reconcileRequest != 0 ||
      m_reconnectTimer.isActive()) {
    return;
  }
  if (m_expectedEndUtc.isValid() &&
      QDateTime::currentDateTimeUtc() >= m_expectedEndUtc.addSecs(-30)) {
    closeSession(true);
    return;
  }
  const int delay = reconnectDelayMs(m_sessionId, m_reconnectAttempt);
  if (delay < 0) {
    requestRefresh(reason == QStringLiteral("stalled")
                       ? QStringLiteral("stalled")
                       : QStringLiteral("transport"));
    return;
  }
  ++m_reconnectAttempt;
  m_pendingRecoveryReason = reason == QStringLiteral("stalled")
                                ? reason
                                : QStringLiteral("transport");
  m_stallTimer.stop();
  m_stableTimer.stop();
  m_reconnectSecondsRemaining = (delay + 999) / 1'000;
  if (m_reconnectSecondsRemaining > 0) {
    m_countdownTimer.start();
  }
  m_reconnectTimer.start(delay);
  setState(QStringLiteral("reconnecting"));
  emit recoveryChanged();
}

void LivePlayerController::performTransportReconnect() {
  if (!m_target || m_sessionId.isEmpty() || m_playbackUrl.isEmpty() ||
      m_recoveryRequest != 0 || m_reconcileRequest != 0) {
    return;
  }
  const QUrl url(m_playbackUrl);
  if (!url.isValid()) {
    finishRecoveryFailure(QStringLiteral("LIVE_CLIENT_PLAYBACK_URL_REJECTED"),
                          true);
    return;
  }
  m_countdownTimer.stop();
  m_reconnectSecondsRemaining = 0;
  emit recoveryChanged();
  m_target->prepareLivePlayback(m_sessionToken, m_deliveryMode, m_lowLatency);
  m_target->loadLiveUrl(url);
  emit playbackLoadRequested(url);
  setState(QStringLiteral("loading"));
  sendHeartbeatNow();
}

void LivePlayerController::requestRefresh(const QString &reason) {
  if (!m_api || m_sessionId.isEmpty() || m_revision < 1 || terminal(m_state) ||
      m_recoveryRequest != 0 || m_reconcileRequest != 0) {
    return;
  }
  if (m_refreshAttemptedForSource) {
    requestFailover(reason == QStringLiteral("stalled")
                        ? QStringLiteral("stalled")
                        : QStringLiteral("transport"));
    return;
  }
  if (m_controlRequest != 0) {
    const quint64 request = m_controlRequest;
    m_controlRequest = 0;
    m_api->cancel(request);
  }
  m_reconnectTimer.stop();
  m_countdownTimer.stop();
  m_stallTimer.stop();
  m_stableTimer.stop();
  m_reconnectSecondsRemaining = 0;
  m_refreshAttemptedForSource = true;
  m_pendingRecoveryReason = reason;
  m_recoveryAction = RecoveryAction::Refresh;
  setState(QStringLiteral("refreshing"));
  emit recoveryChanged();
  m_recoveryRequest =
      m_api->refreshSession(m_sessionId, m_revision, reason, m_generation);
}

void LivePlayerController::requestFailover(const QString &reason,
                                           const QString &requestedSourceKey) {
  if (!m_api || m_sessionId.isEmpty() || m_revision < 1 || terminal(m_state) ||
      m_recoveryRequest != 0 || m_reconcileRequest != 0) {
    return;
  }
  const bool manual = reason == QStringLiteral("manual_source_switch");
  if (!manual && m_failoverAttempts >= kMaximumClientFailovers) {
    finishRecoveryFailure(QStringLiteral("LIVE_FAILOVER_EXHAUSTED"), true);
    return;
  }
  if (m_controlRequest != 0) {
    const quint64 request = m_controlRequest;
    m_controlRequest = 0;
    m_api->cancel(request);
  }
  m_reconnectTimer.stop();
  m_countdownTimer.stop();
  m_stallTimer.stop();
  m_stableTimer.stop();
  m_reconnectSecondsRemaining = 0;
  if (!manual) {
    ++m_failoverAttempts;
  }
  m_pendingRecoveryReason = reason;
  m_recoveryAction = RecoveryAction::Failover;
  setState(QStringLiteral("switching_source"));
  emit recoveryChanged();
  m_recoveryRequest = m_api->failoverSession(m_sessionId, m_revision, reason,
                                             requestedSourceKey, m_generation);
}

void LivePlayerController::resyncThen(ReconcileAction action,
                                      const QString &reason) {
  if (!m_api || m_sessionId.isEmpty() || m_reconcileRequest != 0) {
    finishRecoveryFailure(QStringLiteral("LIVE_CLIENT_RECOVERY_FAILED"), true);
    return;
  }
  if (m_controlRequest != 0) {
    const quint64 request = m_controlRequest;
    m_controlRequest = 0;
    m_api->cancel(request);
  }
  m_recoveryAction = RecoveryAction::None;
  m_reconcileAction = action;
  m_pendingRecoveryReason = reason;
  m_reconcileRequest = m_api->getSession(m_sessionId, m_generation);
  emit recoveryChanged();
}

void LivePlayerController::replayCreateForRecovery() {
  if (!m_api || m_providerId.isEmpty() || m_itemKey.isEmpty() ||
      m_streamOptionKey.isEmpty() || m_idempotencyKey.isEmpty() ||
      m_reconcileRequest != 0) {
    finishRecoveryFailure(QStringLiteral("LIVE_CLIENT_RECOVERY_FAILED"), true);
    return;
  }
  m_recoveryAction = RecoveryAction::None;
  m_reconcileAction = ReconcileAction::ReplayCreate;
  m_reconcileRequest =
      m_api->createSession(m_providerId, m_itemKey, m_streamOptionKey,
                           capabilities(), m_idempotencyKey, m_generation);
  setState(QStringLiteral("refreshing"));
  emit recoveryChanged();
}

void LivePlayerController::finishRecoveryFailure(const QString &code,
                                                 bool terminalFailure,
                                                 const QString &message,
                                                 bool retryable) {
  setFailure(code.isEmpty() ? QStringLiteral("LIVE_CLIENT_RECOVERY_FAILED")
                            : code,
             message, retryable);
  cancelRecoveryWork();
  if (terminalFailure) {
    closeSession(false);
    setState(QStringLiteral("unavailable"));
  } else {
    setState(m_buffering ? QStringLiteral("buffering")
                         : QStringLiteral("playing"));
  }
}

void LivePlayerController::scheduleExpiryRefresh() {
  m_expiryTimer.stop();
  if (m_sessionId.isEmpty() || !m_expiresAtUtc.isValid()) {
    return;
  }
  const qint64 untilRefresh =
      QDateTime::currentDateTimeUtc().msecsTo(m_expiresAtUtc) - kRefreshLeadMs;
  if (untilRefresh <= 0) {
    requestRefresh(QStringLiteral("expiry_threshold"));
    return;
  }
  m_expiryTimer.start(static_cast<int>(
      std::min<qint64>(untilRefresh, std::numeric_limits<int>::max())));
}

void LivePlayerController::cancelRecoveryWork() {
  m_stallTimer.stop();
  m_reconnectTimer.stop();
  m_countdownTimer.stop();
  m_expiryTimer.stop();
  m_stableTimer.stop();
  const quint64 recoveryRequest = m_recoveryRequest;
  const quint64 reconcileRequest = m_reconcileRequest;
  m_recoveryRequest = 0;
  m_reconcileRequest = 0;
  m_recoveryAction = RecoveryAction::None;
  m_reconcileAction = ReconcileAction::None;
  m_reconnectSecondsRemaining = 0;
  if (m_api && recoveryRequest != 0) {
    m_api->cancel(recoveryRequest);
  }
  if (m_api && reconcileRequest != 0) {
    m_api->cancel(reconcileRequest);
  }
  emit recoveryChanged();
}

void LivePlayerController::resetStableRecoveryState() {
  if (m_state != QStringLiteral("playing") || m_buffering) {
    return;
  }
  m_reconnectAttempt = 0;
  m_pendingRecoveryReason.clear();
  emit recoveryChanged();
}

QString LivePlayerController::classifyMpvError(const QString &error) const {
  const QString normalized = error.toLower();
  if (normalized.contains(QStringLiteral("401")) ||
      normalized.contains(QStringLiteral("unauthorized"))) {
    return QStringLiteral("upstream_unauthorized");
  }
  if (normalized.contains(QStringLiteral("403")) ||
      normalized.contains(QStringLiteral("forbidden"))) {
    return QStringLiteral("upstream_forbidden");
  }
  if (normalized.contains(QStringLiteral("410")) ||
      normalized.contains(QStringLiteral("gone"))) {
    return QStringLiteral("upstream_gone");
  }
  return QStringLiteral("transport");
}

void LivePlayerController::handleFailure(quint64 requestId, quint64 generation,
                                         const QVariantMap &error) {
  const QString code = error.value(QStringLiteral("code")).toString().left(128);
  const QString message =
      error.value(QStringLiteral("message")).toString().left(512);
  const bool retryable = error.value(QStringLiteral("retryable")).toBool();
  if (requestId == m_endRequest) {
    if (code == QStringLiteral("LIVE_SESSION_NOT_FOUND") ||
        code == QStringLiteral("LIVE_SESSION_EXPIRED")) {
      QSettings settings;
      clearPendingEnd(
          settings.value(QString::fromLatin1(kPendingSessionKey)).toString());
    }
    m_endRequest = 0;
    return;
  }
  if (generation != m_generation) {
    return;
  }

  if (requestId == m_recoveryRequest) {
    const RecoveryAction action = m_recoveryAction;
    const bool manual =
        m_pendingRecoveryReason == QStringLiteral("manual_source_switch");
    m_recoveryRequest = 0;
    if (code == QStringLiteral("LIVE_FAILOVER_EXHAUSTED") ||
        code == QStringLiteral("LIVE_SESSION_EXPIRED") ||
        code == QStringLiteral("LIVE_SESSION_NOT_FOUND")) {
      finishRecoveryFailure(code, true, message, retryable);
    } else if (code == QStringLiteral("LIVE_CLIENT_NETWORK")) {
      replayCreateForRecovery();
    } else if (action == RecoveryAction::Refresh) {
      resyncThen(ReconcileAction::Failover, m_pendingRecoveryReason);
    } else if (manual) {
      replayCreateForRecovery();
    } else if (m_failoverAttempts < kMaximumClientFailovers) {
      resyncThen(ReconcileAction::Failover, m_pendingRecoveryReason);
    } else {
      finishRecoveryFailure(QStringLiteral("LIVE_FAILOVER_EXHAUSTED"), true);
    }
    return;
  }

  if (requestId == m_reconcileRequest) {
    const ReconcileAction action = m_reconcileAction;
    m_reconcileRequest = 0;
    m_reconcileAction = ReconcileAction::None;
    if (code == QStringLiteral("LIVE_SESSION_EXPIRED") ||
        code == QStringLiteral("LIVE_SESSION_NOT_FOUND") ||
        code == QStringLiteral("LIVE_FAILOVER_EXHAUSTED")) {
      finishRecoveryFailure(code, true, message, retryable);
    } else if (code == QStringLiteral("LIVE_CLIENT_NETWORK") &&
               action != ReconcileAction::ReplayCreate) {
      replayCreateForRecovery();
    } else {
      finishRecoveryFailure(code, true, message, retryable);
    }
    return;
  }

  if (requestId == m_controlRequest) {
    m_controlRequest = 0;
    if (code == QStringLiteral("LIVE_CLIENT_NETWORK")) {
      beginTransportRecovery(QStringLiteral("transport"));
    } else if (code == QStringLiteral("LIVE_SESSION_CONFLICT") && m_api &&
               !m_sessionId.isEmpty()) {
      m_controlRequest = m_api->getSession(m_sessionId, m_generation);
    } else if (code == QStringLiteral("LIVE_SESSION_EXPIRED") ||
               code == QStringLiteral("LIVE_SESSION_NOT_FOUND")) {
      finishRecoveryFailure(code, true, message, retryable);
    } else {
      fail(code, message, retryable);
    }
    return;
  }

  if (requestId != m_createRequest) {
    return;
  }
  m_createRequest = 0;
  fail(code, message, retryable);
}

void LivePlayerController::closeSession(bool terminalState) {
  if (m_api && !m_sessionId.isEmpty() && m_revision > 0 && m_endRequest == 0) {
    persistPendingEnd();
    m_endRequest = m_api->endSession(m_sessionId, m_revision, m_generation);
  }
  clearPlaybackSecrets();
  setState(terminalState ? QStringLiteral("ended") : QStringLiteral("idle"));
}

void LivePlayerController::clearPlaybackSecrets() {
  m_heartbeatTimer.stop();
  cancelRecoveryWork();
  const quint64 createRequest = m_createRequest;
  const quint64 controlRequest = m_controlRequest;
  m_createRequest = 0;
  m_controlRequest = 0;
  if (createRequest != 0 && m_api) {
    m_api->cancel(createRequest);
  }
  if (controlRequest != 0 && m_api) {
    m_api->cancel(controlRequest);
  }
  if (m_target) {
    m_target->clearLivePlayback();
  }
  erase(&m_sessionToken);
  m_playbackUrl.clear();
  m_deliveryMode.clear();
  m_egressMode.clear();
  m_sourceKey.clear();
  m_sourceLabel.clear();
  m_sourceQuality.clear();
  m_availableSources.clear();
  m_preferredAudioTrack.clear();
  m_preferredSubtitleTrack.clear();
  m_sessionId.clear();
  m_revision = 0;
  m_serverScope.clear();
  m_accountSessionScope.clear();
  m_providerId.clear();
  m_itemKey.clear();
  m_streamOptionKey.clear();
  m_idempotencyKey.clear();
  m_pendingRecoveryReason.clear();
  m_expiresAtUtc = {};
  m_reconnectAttempt = 0;
  m_failoverAttempts = 0;
  m_refreshAttemptedForSource = false;
  m_lowLatency = false;
  m_seekable = false;
  m_windowSeconds = 0;
  m_distanceFromLiveEdge = 0.0;
  m_buffering = false;
  m_audioTracks.clear();
  m_subtitleTracks.clear();
  m_audioTrackId.clear();
  m_audioTrackLanguage.clear();
  m_audioTrackTitle.clear();
  m_subtitleTrackId.clear();
  m_subtitleTrackLanguage.clear();
  m_subtitleTrackTitle.clear();
  m_trackSelectionVersion = 0;
  m_sentTrackSelectionVersion = 0;
  emit playbackCleared();
  emit egressChanged();
  emit sessionChanged();
  emit liveWindowChanged();
  emit observationChanged();
}

void LivePlayerController::setState(const QString &state) {
  if (m_state == state) {
    return;
  }
  m_state = state;
  emit stateChanged();
}

void LivePlayerController::setFailure(const QString &code, const QString &message,
                                      bool retryable) {
  m_errorCode = code.isEmpty() ? QStringLiteral("LIVE_CLIENT_FAILED")
                               : code.left(128);
  m_failureMessage = message.trimmed().left(512);
  if (m_failureMessage.isEmpty()) {
    m_failureMessage = fallbackFailureMessage(m_errorCode);
  }
  m_failureRetryable = retryable;
  emit errorChanged();
}

void LivePlayerController::fail(const QString &code, const QString &message,
                                bool retryable) {
  setFailure(code, message, retryable);
  closeSession(false);
  setState(QStringLiteral("failed"));
}

QVariantMap LivePlayerController::capabilities() const {
#if defined(Q_OS_MACOS)
  const QString platform = QStringLiteral("macos");
#elif defined(Q_OS_WIN)
  const QString platform = QStringLiteral("windows");
#else
  const QString platform = QStringLiteral("linux");
#endif
  return {
      {QStringLiteral("platform"), platform},
      {QStringLiteral("player"), QStringLiteral("mpv")},
      {QStringLiteral("protocols"),
       QStringList{QStringLiteral("hls"), QStringLiteral("dash"),
                   QStringLiteral("http_progressive"),
                   QStringLiteral("mpeg_ts")}},
      {QStringLiteral("videoCodecs"),
       QStringList{QStringLiteral("h264"), QStringLiteral("hevc"),
                   QStringLiteral("vp9"), QStringLiteral("av1")}},
      {QStringLiteral("audioCodecs"),
       QStringList{QStringLiteral("aac"), QStringLiteral("ac3"),
                   QStringLiteral("eac3"), QStringLiteral("opus")}},
      {QStringLiteral("supportsRequestHeaders"), true},
      {QStringLiteral("supportsCookies"), false},
      {QStringLiteral("supportsLowLatencyHls"), false},
      {QStringLiteral("supportsOriginTimeShift"), true},
  };
}

QUrl LivePlayerController::validatedPlaybackUrl(
    const Live::SessionCreated &session) const {
  if (!m_api) {
    return {};
  }
  const QUrl supplied(session.playbackUrl);
  if (!supplied.isValid() || !supplied.userInfo().isEmpty() ||
      supplied.hasFragment()) {
    return {};
  }
  if (session.deliveryMode == QStringLiteral("client_direct")) {
    if (supplied.isRelative() || supplied.scheme() != QStringLiteral("https") ||
        supplied.host().isEmpty() || supplied.hasQuery()) {
      return {};
    }
    return supplied;
  }
  if (!supplied.isRelative() || !supplied.scheme().isEmpty() ||
      !supplied.host().isEmpty() || supplied.hasQuery()) {
    return {};
  }
  const QString sessionUuid =
      QUuid(session.sessionId).toString(QUuid::WithoutBraces).toLower();
  const QString deliveryRoot = QStringLiteral("/api/v1/live/sessions/") +
                               sessionUuid + QStringLiteral("/delivery/");
  const QString encodedPath = supplied.path(QUrl::FullyEncoded);
  const bool hlsManifest =
      encodedPath == deliveryRoot + QStringLiteral("hls/manifest.m3u8");
  const bool progressive =
      encodedPath == deliveryRoot + QStringLiteral("stream");
  if ((!hlsManifest && !progressive) ||
      (session.deliveryMode == QStringLiteral("server_remux") &&
       !hlsManifest)) {
    return {};
  }
  QUrl base(m_api->serverBaseUrl());
  if (!base.isValid() || base.host().isEmpty() ||
      (base.scheme() != QStringLiteral("http") &&
       base.scheme() != QStringLiteral("https"))) {
    return {};
  }
  base.setPath(QStringLiteral("/"));
  base.setQuery(QString());
  base.setFragment(QString());
  return base.resolved(supplied);
}

bool LivePlayerController::requestIsCurrent(quint64 requestId,
                                            quint64 generation) const {
  return generation == m_generation &&
         (requestId == m_createRequest || requestId == m_controlRequest ||
          requestId == m_recoveryRequest || requestId == m_reconcileRequest ||
          requestId == m_endRequest);
}

QString LivePlayerController::playerState() const {
  if (m_state == QStringLiteral("buffering")) {
    return QStringLiteral("buffering");
  }
  if (m_state == QStringLiteral("playing")) {
    return QStringLiteral("playing");
  }
  if (m_state == QStringLiteral("paused")) {
    return QStringLiteral("paused");
  }
  return QStringLiteral("loading");
}

void LivePlayerController::persistPendingEnd() {
  QSettings settings;
  settings.setValue(QString::fromLatin1(kPendingSessionKey), m_sessionId);
  settings.setValue(QString::fromLatin1(kPendingRevisionKey), m_revision);
  settings.setValue(QString::fromLatin1(kPendingServerKey), m_serverScope);
  settings.setValue(QString::fromLatin1(kPendingAccountSessionKey),
                    m_accountSessionScope);
}

void LivePlayerController::clearPendingEnd(const QString &sessionId) {
  QSettings settings;
  if (settings.value(QString::fromLatin1(kPendingSessionKey)).toString() ==
      sessionId) {
    settings.remove(QString::fromLatin1(kPendingSessionKey));
    settings.remove(QString::fromLatin1(kPendingRevisionKey));
    settings.remove(QString::fromLatin1(kPendingServerKey));
    settings.remove(QString::fromLatin1(kPendingAccountSessionKey));
  }
}

void LivePlayerController::retryPendingEnd() {
  if (!m_api || m_endRequest != 0) {
    return;
  }
  QSettings settings;
  const QString sessionId =
      settings.value(QString::fromLatin1(kPendingSessionKey)).toString();
  const qint64 revision =
      settings.value(QString::fromLatin1(kPendingRevisionKey)).toLongLong();
  const QString server =
      settings.value(QString::fromLatin1(kPendingServerKey)).toString();
  const QString accountSession =
      settings.value(QString::fromLatin1(kPendingAccountSessionKey)).toString();
  if (!sessionId.isEmpty() && revision > 0 &&
      server == m_api->serverBaseUrl() &&
      accountSession == m_api->accountSessionId()) {
    m_endRequest = m_api->endSession(sessionId, revision, m_generation);
  }
}
