#include "backend/MpvItem.h"

#include <MpvQt/mpvcontroller.h>
#include <QDir>
#include <QFileInfo>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

MpvItem::MpvItem(QQuickItem *parent) : MpvAbstractItem(parent) {
  auto *controller = mpvController();
  connect(controller, &MpvController::fileStarted, this, [this]() {
    if (m_liveProfileActive) {
      emit liveFileStarted();
    }
  });
  connect(controller, &MpvController::fileLoaded, this, [this]() {
    if (m_liveProfileActive) {
      emit liveFileLoaded();
    }
  });
  connect(controller, &MpvController::endFile, this,
          [this](const QString &reason) {
            if (m_liveProfileActive) {
              emit liveFileEnded(reason);
            }
          });
}

QString MpvItem::delivery() const { return m_delivery; }

void MpvItem::setDelivery(const QString &value) {
  const QString normalized = value.trimmed();
  if (m_delivery == normalized) {
    return;
  }
  m_delivery = normalized;
  emit deliveryChanged();
}

bool MpvItem::hlsDelivery() const {
  return m_delivery.startsWith(QStringLiteral("hls_"));
}

bool MpvItem::liveProfileActive() const { return m_liveProfileActive; }

bool MpvItem::authorizationHeaderActive() const {
  return m_authorizationHeaderActive;
}

void MpvItem::setAuthorizationHeader(const QString &token) {
  const QVariantList headers = authorizationHeaderFields(token);
  setPropertyBlocking(QStringLiteral("http-header-fields"), headers);
  const bool active = !headers.isEmpty();
  if (m_authorizationHeaderActive != active) {
    m_authorizationHeaderActive = active;
    emit liveProfileChanged();
  }
}

QVariantList MpvItem::authorizationHeaderFields(const QString &token) {
  const QString trimmed = token.trimmed();
  if (trimmed.size() < 16 || trimmed.size() > 2048) {
    return {};
  }
  for (const QChar character : trimmed) {
    const ushort value = character.unicode();
    if (value < 0x21 || value > 0x7e) {
      return {};
    }
  }
  return {QStringLiteral("Authorization: Bearer %1").arg(trimmed)};
}

void MpvItem::beginLivePlayback(const QString &sessionToken,
                                const QString &deliveryMode, bool lowLatency) {
  prepareLivePlayback(sessionToken.toUtf8(), deliveryMode, lowLatency);
}

void MpvItem::prepareLivePlayback(const QByteArray &sessionToken,
                                  const QString &deliveryMode,
                                  bool lowLatency) {
  clearLivePlayback();
  setDelivery(deliveryMode);
  setAuthorizationHeader(QString::fromUtf8(sessionToken));
  setPropertyAsync(QStringLiteral("cache"), QStringLiteral("yes"));
  setPropertyAsync(QStringLiteral("cache-secs"), lowLatency ? 8 : 20);
  setPropertyAsync(QStringLiteral("demuxer-readahead-secs"),
                   lowLatency ? 3 : 10);
  setPropertyAsync(QStringLiteral("demuxer-max-bytes"), 64 * 1024 * 1024);
  setPropertyAsync(QStringLiteral("demuxer-max-back-bytes"), 8 * 1024 * 1024);
  m_liveProfileActive = true;
  emit liveProfileChanged();
}

void MpvItem::loadLiveUrl(const QUrl &url) {
  if (!m_liveProfileActive || !url.isValid()) {
    return;
  }
  commandAsync(QStringList{QStringLiteral("loadfile"),
                           url.toString(QUrl::FullyEncoded),
                           QStringLiteral("replace")});
}

void MpvItem::clearLivePlayback() {
  const bool wasActive = m_liveProfileActive;
  m_liveProfileActive = false;
  setAuthorizationHeader(QString());
  if (wasActive) {
    commandAsync(QStringList{QStringLiteral("stop")});
    setPropertyAsync(QStringLiteral("cache-secs"), 20);
    setPropertyAsync(QStringLiteral("demuxer-readahead-secs"), 10);
    emit liveProfileChanged();
  }
  setDelivery(QString());
}

void MpvItem::captureVideoFrame(const QString &path) {
  const QString trimmed = path.trimmed();
  if (trimmed.isEmpty()) {
    return;
  }

  const QFileInfo fileInfo(trimmed);
  QDir().mkpath(fileInfo.absolutePath());
  commandAsync(QStringList{
      QStringLiteral("screenshot-to-file"),
      trimmed,
      QStringLiteral("video"),
  });
}

void MpvItem::selectVideoTrack(int trackId) {
  if (trackId <= 0) {
    return;
  }

  commandAsync(QStringList{
      QStringLiteral("set"),
      QStringLiteral("vid"),
      QString::number(trackId),
  });
}
