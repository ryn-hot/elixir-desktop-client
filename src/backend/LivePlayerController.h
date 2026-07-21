#pragma once

#include "backend/LivePlaybackTarget.h"
#include "live/LiveTypes.h"

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

class LiveApiClient;
class MpvItem;

class LivePlayerController final : public QObject {
  Q_OBJECT
  Q_PROPERTY(QString state READ state NOTIFY stateChanged)
  Q_PROPERTY(QString sessionId READ sessionId NOTIFY sessionChanged)
  Q_PROPERTY(qint64 revision READ revision NOTIFY sessionChanged)
  Q_PROPERTY(QString playbackUrl READ playbackUrl NOTIFY sessionChanged)
  Q_PROPERTY(QString deliveryMode READ deliveryMode NOTIFY sessionChanged)
  Q_PROPERTY(QString egressMode READ egressMode NOTIFY egressChanged)
  Q_PROPERTY(bool seekable READ seekable NOTIFY liveWindowChanged)
  Q_PROPERTY(int windowSeconds READ windowSeconds NOTIFY liveWindowChanged)
  Q_PROPERTY(double distanceFromLiveEdge READ distanceFromLiveEdge NOTIFY
                 observationChanged)
  Q_PROPERTY(bool buffering READ buffering NOTIFY observationChanged)
  Q_PROPERTY(bool recovering READ recovering NOTIFY recoveryChanged)
  Q_PROPERTY(int reconnectAttempt READ reconnectAttempt NOTIFY recoveryChanged)
  Q_PROPERTY(int reconnectSecondsRemaining READ reconnectSecondsRemaining NOTIFY
                 recoveryChanged)
  Q_PROPERTY(QString selectedSourceLabel READ selectedSourceLabel NOTIFY
                 sessionChanged)
  Q_PROPERTY(QString selectedSourceKey READ selectedSourceKey NOTIFY
                 sessionChanged)
  Q_PROPERTY(QString selectedSourceQuality READ selectedSourceQuality NOTIFY
                 sessionChanged)
  Q_PROPERTY(QVariantList availableSources READ availableSources NOTIFY
                 sessionChanged)
  Q_PROPERTY(QVariantMap preferredAudioTrack READ preferredAudioTrack NOTIFY
                 sessionChanged)
  Q_PROPERTY(QVariantMap preferredSubtitleTrack READ preferredSubtitleTrack
                 NOTIFY sessionChanged)
  Q_PROPERTY(
      QVariantList audioTracks READ audioTracks NOTIFY observationChanged)
  Q_PROPERTY(
      QVariantList subtitleTracks READ subtitleTracks NOTIFY observationChanged)
  Q_PROPERTY(QString errorCode READ errorCode NOTIFY errorChanged)
  Q_PROPERTY(QString failureMessage READ failureMessage NOTIFY errorChanged)
  Q_PROPERTY(bool failureRetryable READ failureRetryable NOTIFY errorChanged)
  Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)

public:
  explicit LivePlayerController(LiveApiClient *api, QObject *parent = nullptr);
  LivePlayerController(LiveApiClient *api, LivePlaybackTarget *target,
                       QObject *parent = nullptr);
  ~LivePlayerController() override;

  [[nodiscard]] QString state() const;
  [[nodiscard]] QString sessionId() const;
  [[nodiscard]] qint64 revision() const;
  [[nodiscard]] QString playbackUrl() const;
  [[nodiscard]] QString deliveryMode() const;
  [[nodiscard]] QString egressMode() const;
  [[nodiscard]] bool seekable() const;
  [[nodiscard]] int windowSeconds() const;
  [[nodiscard]] double distanceFromLiveEdge() const;
  [[nodiscard]] bool buffering() const;
  [[nodiscard]] bool recovering() const;
  [[nodiscard]] int reconnectAttempt() const;
  [[nodiscard]] int reconnectSecondsRemaining() const;
  [[nodiscard]] QString selectedSourceLabel() const;
  [[nodiscard]] QString selectedSourceKey() const;
  [[nodiscard]] QString selectedSourceQuality() const;
  [[nodiscard]] QVariantList availableSources() const;
  [[nodiscard]] QVariantMap preferredAudioTrack() const;
  [[nodiscard]] QVariantMap preferredSubtitleTrack() const;
  [[nodiscard]] QVariantList audioTracks() const;
  [[nodiscard]] QVariantList subtitleTracks() const;
  [[nodiscard]] QString errorCode() const;
  [[nodiscard]] QString failureMessage() const;
  [[nodiscard]] bool failureRetryable() const;
  [[nodiscard]] QString statusText() const;

  Q_INVOKABLE bool attachPlayer(QObject *player);
  Q_INVOKABLE void start(const QString &providerId, const QString &itemKey,
                         const QString &streamOptionKey,
                         const QString &title = {},
                         const QVariant &expectedEndUtc = {});
  Q_INVOKABLE void stop();
  Q_INVOKABLE void routeExited();
  Q_INVOKABLE void sendHeartbeatNow();
  Q_INVOKABLE void observeMpv(const QVariantMap &observation);
  Q_INVOKABLE void selectTrack(const QString &type, const QString &trackId);
  Q_INVOKABLE void switchSource(const QString &sourceKey);
  Q_INVOKABLE double clampWindowPosition(double seconds) const;
  Q_INVOKABLE double seekDeltaForWindowPosition(double seconds) const;
  Q_INVOKABLE void cancelRecovery();
  Q_INVOKABLE void retryRecoveryNow();

  [[nodiscard]] static int reconnectDelayMs(const QString &sessionId,
                                            int zeroBasedAttempt);

signals:
  void stateChanged();
  void sessionChanged();
  void liveWindowChanged();
  void observationChanged();
  void recoveryChanged();
  void egressChanged();
  void errorChanged();
  void playbackLoadRequested(const QUrl &url);
  void playbackCleared();

private:
  enum class RecoveryAction { None, Refresh, Failover };
  enum class ReconcileAction { None, Failover, ReplayCreate };

  void connectApi();
  void handleCreated(quint64 requestId, quint64 generation,
                     const Live::SessionCreated &session);
  void handleDetail(quint64 requestId, quint64 generation,
                    const Live::SessionDetailEnvelope &envelope);
  void handleRecovered(quint64 requestId, quint64 generation,
                       const Live::SessionCreated &session);
  void handleFailure(quint64 requestId, quint64 generation,
                     const QVariantMap &error);
  bool applySession(const Live::SessionCreated &session, bool initial);
  void beginPlaybackLoad(const QUrl &url);
  void beginTransportRecovery(const QString &reason);
  void performTransportReconnect();
  void requestRefresh(const QString &reason);
  void requestFailover(const QString &reason,
                       const QString &requestedSourceKey = {});
  void resyncThen(ReconcileAction action, const QString &reason);
  void replayCreateForRecovery();
  void finishRecoveryFailure(const QString &code, bool terminalFailure,
                             const QString &message = {},
                             bool retryable = false);
  void scheduleExpiryRefresh();
  void cancelRecoveryWork();
  void resetStableRecoveryState();
  [[nodiscard]] QString classifyMpvError(const QString &error) const;
  void closeSession(bool terminalState);
  void clearPlaybackSecrets();
  void setState(const QString &state);
  void fail(const QString &code, const QString &message = {},
            bool retryable = false);
  void setFailure(const QString &code, const QString &message, bool retryable);
  [[nodiscard]] QVariantMap capabilities() const;
  [[nodiscard]] QUrl
  validatedPlaybackUrl(const Live::SessionCreated &session) const;
  [[nodiscard]] bool requestIsCurrent(quint64 requestId,
                                      quint64 generation) const;
  [[nodiscard]] QString playerState() const;
  [[nodiscard]] LivePlaybackTarget *playbackTarget() const;
  void applySourceAndTrackState(const Live::SelectedSource &selectedSource,
                                const QList<Live::SelectedSource> &sources,
                                const Live::TrackPreferences &preferences);
  void updateObservedTrackSelection(const QString &type,
                                    const QString &trackId,
                                    const QVariantList &tracks);
  void persistPendingEnd();
  void clearPendingEnd(const QString &sessionId);
  void retryPendingEnd();

  LiveApiClient *m_api{nullptr};
  LivePlaybackTarget *m_injectedTarget{nullptr};
  QPointer<MpvItem> m_mpv;
  QTimer m_heartbeatTimer;
  QTimer m_stallTimer;
  QTimer m_reconnectTimer;
  QTimer m_countdownTimer;
  QTimer m_expiryTimer;
  QTimer m_stableTimer;
  quint64 m_generation{0};
  quint64 m_createRequest{0};
  quint64 m_controlRequest{0};
  quint64 m_recoveryRequest{0};
  quint64 m_reconcileRequest{0};
  quint64 m_endRequest{0};
  RecoveryAction m_recoveryAction{RecoveryAction::None};
  ReconcileAction m_reconcileAction{ReconcileAction::None};
  QString m_state{QStringLiteral("idle")};
  QString m_sessionId;
  qint64 m_revision{0};
  QString m_playbackUrl;
  QString m_deliveryMode;
  QString m_egressMode;
  QByteArray m_sessionToken;
  QString m_sourceKey;
  QString m_sourceLabel;
  QString m_sourceQuality;
  QVariantList m_availableSources;
  QVariantMap m_preferredAudioTrack;
  QVariantMap m_preferredSubtitleTrack;
  bool m_seekable{false};
  int m_windowSeconds{0};
  double m_distanceFromLiveEdge{0.0};
  bool m_buffering{false};
  QString m_audioTrackId;
  QString m_audioTrackLanguage;
  QString m_audioTrackTitle;
  QString m_subtitleTrackId;
  QString m_subtitleTrackLanguage;
  QString m_subtitleTrackTitle;
  quint64 m_trackSelectionVersion{0};
  quint64 m_sentTrackSelectionVersion{0};
  QVariantList m_audioTracks;
  QVariantList m_subtitleTracks;
  QString m_errorCode;
  QString m_failureMessage;
  bool m_failureRetryable{false};
  QString m_title;
  QDateTime m_expectedEndUtc;
  QString m_serverScope;
  QString m_accountSessionScope;
  QString m_providerId;
  QString m_itemKey;
  QString m_streamOptionKey;
  QString m_idempotencyKey;
  QString m_pendingRecoveryReason;
  QDateTime m_expiresAtUtc;
  int m_reconnectAttempt{0};
  int m_reconnectSecondsRemaining{0};
  int m_failoverAttempts{0};
  bool m_refreshAttemptedForSource{false};
  bool m_lowLatency{false};
};
