#pragma once

#include <MpvQt/mpvabstractitem.h>
#include <QString>

class MpvItem : public MpvAbstractItem {
    Q_OBJECT
    Q_PROPERTY(QString delivery READ delivery WRITE setDelivery NOTIFY deliveryChanged)
    Q_PROPERTY(bool hlsDelivery READ hlsDelivery NOTIFY deliveryChanged)

public:
    explicit MpvItem(QQuickItem *parent = nullptr);

    QString delivery() const;
    void setDelivery(const QString &value);
    bool hlsDelivery() const;

signals:
    void deliveryChanged();

private:
    QString m_delivery;
};
