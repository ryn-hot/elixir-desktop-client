#include "backend/MpvItem.h"

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
