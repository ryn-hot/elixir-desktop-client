#pragma once

#include <QByteArray>
#include <QString>
#include <QUrl>

class LivePlaybackTarget {
public:
  virtual ~LivePlaybackTarget() = default;

  virtual void prepareLivePlayback(const QByteArray &sessionToken,
                                   const QString &deliveryMode,
                                   bool lowLatency) = 0;
  virtual void loadLiveUrl(const QUrl &url) = 0;
  virtual void clearLivePlayback() = 0;
};
