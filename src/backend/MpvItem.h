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

    Q_INVOKABLE void setAuthorizationHeader(const QString &token);
    Q_INVOKABLE void captureVideoFrame(const QString &path);
    Q_INVOKABLE void selectVideoTrack(int trackId);

signals:
    void deliveryChanged();

private:
    QString m_delivery;
};
