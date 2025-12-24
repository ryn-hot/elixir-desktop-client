#pragma once

#include <QObject>
#include <QVariant>

class ApiClient;

class PlayerController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString streamUrl READ streamUrl NOTIFY streamUrlChanged)
    Q_PROPERTY(QString sessionId READ sessionId NOTIFY sessionIdChanged)
    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)
    Q_PROPERTY(QString sessionState READ sessionState NOTIFY sessionStateChanged)
    Q_PROPERTY(QString sessionError READ sessionError NOTIFY sessionErrorChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double localPosition READ localPosition NOTIFY localPositionChanged)
    Q_PROPERTY(double seekOffset READ seekOffset NOTIFY seekOffsetChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit PlayerController(QObject *parent = nullptr);

    void setApiClient(ApiClient *client);

    QString streamUrl() const;
    QString sessionId() const;
    QString mode() const;
    QString sessionState() const;
    QString sessionError() const;
    double duration() const;
    double position() const;
    double localPosition() const;
    double seekOffset() const;
    bool paused() const;
    bool active() const;

    Q_INVOKABLE void beginPlayback(const QVariantMap &info);
    Q_INVOKABLE void applySessionPoll(const QVariantMap &info);
    Q_INVOKABLE void updateLocalPosition(double seconds);
    Q_INVOKABLE void setPaused(bool paused);
    Q_INVOKABLE void seek(double seconds);
    Q_INVOKABLE void endSession();
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

private:
    void setStreamUrl(const QString &value);
    void setSessionId(const QString &value);
    void setMode(const QString &value);
    void setSessionState(const QString &value);
    void setSessionError(const QString &value);
    void setDuration(double value);
    void setLocalPositionInternal(double value);
    void setSeekOffsetInternal(double value);
    void setActive(bool value);

    QString buildStreamUrl(const QString &baseUrl, const QString &path) const;
    QString cacheBustUrl(const QString &url) const;

    ApiClient *m_apiClient = nullptr;
    QString m_streamUrl;
    QString m_sessionId;
    QString m_mode;
    QString m_sessionState;
    QString m_sessionError;
    double m_duration = 0.0;
    double m_localPosition = 0.0;
    double m_seekOffset = 0.0;
    bool m_paused = false;
    bool m_active = false;
};
