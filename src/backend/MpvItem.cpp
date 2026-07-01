#include "backend/MpvItem.h"

#include <QDir>
#include <QFileInfo>
#include <QStringList>
#include <QVariantList>

MpvItem::MpvItem(QQuickItem *parent)
    : MpvAbstractItem(parent) {
    // Inherit MpvAbstractItem behavior; QML can call getProperty/setPropertyAsync/commandAsync.
}

QString MpvItem::delivery() const {
    return m_delivery;
}

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

void MpvItem::setAuthorizationHeader(const QString &token) {
    QVariantList headers;
    const QString trimmed = token.trimmed();
    if (!trimmed.isEmpty()) {
        headers.append(QStringLiteral("Authorization: Bearer %1").arg(trimmed));
    }
    setPropertyAsync(QStringLiteral("http-header-fields"), headers);
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
