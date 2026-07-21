#pragma once

#include "backend/LivePlaybackTarget.h"

#include <MpvQt/mpvabstractitem.h>
#include <QString>
#include <QVariantList>

class MpvItem : public MpvAbstractItem, public LivePlaybackTarget {
  Q_OBJECT
  Q_PROPERTY(
      QString delivery READ delivery WRITE setDelivery NOTIFY deliveryChanged)
  Q_PROPERTY(bool hlsDelivery READ hlsDelivery NOTIFY deliveryChanged)
  Q_PROPERTY(
      bool liveProfileActive READ liveProfileActive NOTIFY liveProfileChanged)
  Q_PROPERTY(bool authorizationHeaderActive READ authorizationHeaderActive
                 NOTIFY liveProfileChanged)

public:
  explicit MpvItem(QQuickItem *parent = nullptr);

  QString delivery() const;
  void setDelivery(const QString &value);
  bool hlsDelivery() const;
  bool liveProfileActive() const;
  bool authorizationHeaderActive() const;
  [[nodiscard]] static QVariantList
  authorizationHeaderFields(const QString &token);

  Q_INVOKABLE void setAuthorizationHeader(const QString &token);
  Q_INVOKABLE void beginLivePlayback(const QString &sessionToken,
                                     const QString &deliveryMode,
                                     bool lowLatency);
  Q_INVOKABLE void clearLivePlayback() override;
  void prepareLivePlayback(const QByteArray &sessionToken,
                           const QString &deliveryMode,
                           bool lowLatency) override;
  void loadLiveUrl(const QUrl &url) override;
  Q_INVOKABLE void captureVideoFrame(const QString &path);
  Q_INVOKABLE void selectVideoTrack(int trackId);

signals:
  void deliveryChanged();
  void liveProfileChanged();
  void liveFileStarted();
  void liveFileLoaded();
  void liveFileEnded(const QString &reason);

private:
  QString m_delivery;
  bool m_liveProfileActive{false};
  bool m_authorizationHeaderActive{false};
};
