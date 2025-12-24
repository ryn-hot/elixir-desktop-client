#pragma once

#include <QAbstractListModel>
#include <QStringList>
#include <QVariant>
#include <QVector>

struct ServerEntry {
    QString key;
    QString serverId;
    QString name;
    QString source;
    QStringList lanAddresses;
    QString wanEndpoint;
    QString overlayEndpoint;
    QString status;
    QString lastSeenAt;
    bool lanReachable = false;
    bool wanReachable = false;
    QString lanDetail;
    QString wanDetail;
};

class ServerListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString preferredNetworkType READ preferredNetworkType WRITE setPreferredNetworkType NOTIFY preferredNetworkTypeChanged)

public:
    enum Role {
        KeyRole = Qt::UserRole + 1,
        ServerIdRole,
        NameRole,
        SourceRole,
        StatusRole,
        LastSeenAtRole,
        LanAddressesRole,
        WanEndpointRole,
        OverlayEndpointRole,
        LanReachableRole,
        WanReachableRole,
        SelectedEndpointRole,
        SelectedNetworkRole,
        SelectedReachableRole,
        SelectedDetailRole
    };

    explicit ServerListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;

    QString preferredNetworkType() const;
    void setPreferredNetworkType(const QString &value);

    Q_INVOKABLE QVariantMap get(int index) const;

    void setEntries(const QVector<ServerEntry> &entries);
    void upsertEntry(const ServerEntry &entry);
    void removeEntry(const QString &key);
    void clear();
    bool updateHealth(const QString &key, const QString &endpointType, bool reachable, const QString &detail);

    QVector<ServerEntry> entries() const;

signals:
    void countChanged();
    void preferredNetworkTypeChanged();

private:
    struct Selection {
        QString endpoint;
        QString network;
        bool reachable = false;
        QString detail;
    };

    int indexForKey(const QString &key) const;
    QString primaryLanAddress(const ServerEntry &entry) const;
    Selection selectEndpoint(const ServerEntry &entry) const;

    QVector<ServerEntry> m_entries;
    QString m_preferredNetworkType = "auto";
};
