#pragma once

#include <QObject>
#include <QVariant>

class ApiClient;

class PlayerController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString streamUrl READ streamUrl NOTIFY streamUrlChanged)
    Q_PROPERTY(QString sessionId READ sessionId NOTIFY sessionIdChanged)
    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)
    Q_PROPERTY(QString delivery READ delivery NOTIFY diagnosticsChanged)
    Q_PROPERTY(QString mediaFileId READ mediaFileId NOTIFY diagnosticsChanged)
    Q_PROPERTY(QString sessionState READ sessionState NOTIFY sessionStateChanged)
    Q_PROPERTY(QString sessionError READ sessionError NOTIFY sessionErrorChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double localPosition READ localPosition NOTIFY localPositionChanged)
    Q_PROPERTY(double seekOffset READ seekOffset NOTIFY seekOffsetChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool serverSeekRequired READ serverSeekRequired NOTIFY serverSeekRequiredChanged)
    Q_PROPERTY(QString qualityLabel READ qualityLabel NOTIFY qualityChanged)
    Q_PROPERTY(QVariantMap activeRung READ activeRung NOTIFY qualityChanged)
    Q_PROPERTY(QString decisionReason READ decisionReason NOTIFY decisionReasonChanged)
    Q_PROPERTY(QString selectedAudioTrack READ selectedAudioTrack NOTIFY diagnosticsChanged)
    Q_PROPERTY(QString selectedSubtitleTrack READ selectedSubtitleTrack NOTIFY diagnosticsChanged)
    Q_PROPERTY(QVariantMap planSummary READ planSummary NOTIFY diagnosticsChanged)
    Q_PROPERTY(QVariantMap jobState READ jobState NOTIFY diagnosticsChanged)
    Q_PROPERTY(QString ffmpegLogTail READ ffmpegLogTail NOTIFY diagnosticsChanged)
    Q_PROPERTY(QVariantMap lastStructuredError READ lastStructuredError NOTIFY recoveryChanged)
    Q_PROPERTY(bool retryAvailable READ retryAvailable NOTIFY recoveryChanged)
    Q_PROPERTY(bool lowerQualityRetryAvailable READ lowerQualityRetryAvailable NOTIFY recoveryChanged)

public:
    explicit PlayerController(QObject *parent = nullptr);

    void setApiClient(ApiClient *client);

    QString streamUrl() const;
    QString sessionId() const;
    QString mode() const;
    QString delivery() const;
    QString mediaFileId() const;
    QString sessionState() const;
    QString sessionError() const;
    double duration() const;
    double position() const;
    double localPosition() const;
    double seekOffset() const;
    bool paused() const;
    bool active() const;
    bool serverSeekRequired() const;
    QString qualityLabel() const;
    QVariantMap activeRung() const;
    QString decisionReason() const;
    QString selectedAudioTrack() const;
    QString selectedSubtitleTrack() const;
    QVariantMap planSummary() const;
    QVariantMap jobState() const;
    QString ffmpegLogTail() const;
    QVariantMap lastStructuredError() const;
    bool retryAvailable() const;
    bool lowerQualityRetryAvailable() const;

    Q_INVOKABLE void beginPlayback(const QVariantMap &info);
    Q_INVOKABLE void applyPlaybackFailure(const QVariantMap &error);
    Q_INVOKABLE void applySessionPoll(const QVariantMap &info);
    Q_INVOKABLE void updateLocalPosition(double seconds);
    Q_INVOKABLE void setPaused(bool paused);
    Q_INVOKABLE void seek(double seconds);
    Q_INVOKABLE void retrySamePlan();
    Q_INVOKABLE void retryFromCurrentPosition();
    Q_INVOKABLE void retryWithLowerQuality();
    Q_INVOKABLE void endSession();
    Q_INVOKABLE void recordAutomationEvent(const QString &event, const QVariantMap &fields = QVariantMap());
    Q_INVOKABLE void reset();

signals:
    void streamUrlChanged();
    void sessionIdChanged();
    void modeChanged();
    void sessionStateChanged();
    void sessionErrorChanged();
    void durationChanged();
    void positionChanged();
    void localPositionChanged();
    void seekOffsetChanged();
    void pausedChanged();
    void activeChanged();
    void serverSeekRequiredChanged();
    void qualityChanged();
    void decisionReasonChanged();
    void diagnosticsChanged();
    void recoveryChanged();

private slots:
    void handleSeekCompleted(const QString &sessionId, double seconds);
    void handleSeekFailed(const QString &sessionId, const QString &error);

private:
    void setStreamUrl(const QString &value);
    void setSessionId(const QString &value);
    void setMode(const QString &value);
    void setDelivery(const QString &value);
    void setMediaFileId(const QString &value);
    void setSessionState(const QString &value);
    void setSessionError(const QString &value);
    void setDuration(double value);
    void setLocalPositionInternal(double value);
    void setSeekOffsetInternal(double value);
    void setActive(bool value);
    void setServerSeekRequired(bool value);
    void setQualityLabel(const QString &value);
    void setActiveRung(const QVariantMap &value);
    void setDecisionReason(const QString &value);
    void setSelectedAudioTrack(const QString &value);
    void setSelectedSubtitleTrack(const QString &value);
    void setPlanSummary(const QVariantMap &value);
    void setJobState(const QVariantMap &value);
    void setFfmpegLogTail(const QString &value);
    void setLastStructuredError(const QVariantMap &value);
    void updatePlaybackDiagnostics(const QVariantMap &info);
    void releaseSessionBeforeRetry();
    int lowerQualityRetryBitrate() const;

    QString buildStreamUrl(const QString &baseUrl, const QString &path) const;
    QString cacheBustUrl(const QString &url) const;

    ApiClient *m_apiClient = nullptr;
    QString m_streamUrl;
    QString m_sessionId;
    QString m_mode;
    QString m_delivery;
    QString m_mediaFileId;
    QString m_sessionState;
    QString m_sessionError;
    QString m_qualityLabel;
    QVariantMap m_activeRung;
    QString m_decisionReason;
    QString m_selectedAudioTrack;
    QString m_selectedSubtitleTrack;
    QVariantMap m_planSummary;
    QVariantMap m_jobState;
    QString m_ffmpegLogTail;
    QVariantMap m_lastStructuredError;
    double m_duration = 0.0;
    double m_localPosition = 0.0;
    double m_seekOffset = 0.0;
    bool m_paused = false;
    bool m_active = false;
    bool m_serverSeekRequired = false;
    bool m_seekInFlight = false;
    double m_pendingSeekSeconds = 0.0;
    QString m_pendingStreamUrl;
    double m_lastAutomationPositionEvent = -1.0;
};
