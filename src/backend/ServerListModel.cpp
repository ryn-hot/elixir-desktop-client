#include "backend/ServerListModel.h"

ServerListModel::ServerListModel(QObject *parent)
    : QAbstractListModel(parent) {}

int ServerListModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) {
        return 0;
    }
    return static_cast<int>(m_entries.size());
}

QVariant ServerListModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size()) {
        return {};
    }

    const ServerEntry &entry = m_entries.at(index.row());
    switch (role) {
        case KeyRole:
            return entry.key;
        case ServerIdRole:
            return entry.serverId;
        case NameRole:
            return entry.name;
        case SourceRole:
            return entry.source;
        case StatusRole:
            return entry.status;
        case LastSeenAtRole:
            return entry.lastSeenAt;
        case LanAddressesRole:
            return entry.lanAddresses;
        case WanEndpointRole:
            return entry.wanEndpoint;
        case OverlayEndpointRole:
            return entry.overlayEndpoint;
        case LanReachableRole:
            return entry.lanReachable;
        case WanReachableRole:
            return entry.wanReachable;
        case SelectedEndpointRole: {
            Selection selection = selectEndpoint(entry);
            return selection.endpoint;
        }
        case SelectedNetworkRole: {
            Selection selection = selectEndpoint(entry);
            return selection.network;
        }
        case SelectedReachableRole: {
            Selection selection = selectEndpoint(entry);
            return selection.reachable;
        }
        case SelectedDetailRole: {
            Selection selection = selectEndpoint(entry);
            return selection.detail;
        }
        default:
            return {};
    }
}

QHash<int, QByteArray> ServerListModel::roleNames() const {
    return {
        {KeyRole, "key"},
        {ServerIdRole, "serverId"},
        {NameRole, "name"},
        {SourceRole, "source"},
        {StatusRole, "status"},
        {LastSeenAtRole, "lastSeenAt"},
        {LanAddressesRole, "lanAddresses"},
        {WanEndpointRole, "wanEndpoint"},
        {OverlayEndpointRole, "overlayEndpoint"},
        {LanReachableRole, "lanReachable"},
        {WanReachableRole, "wanReachable"},
        {SelectedEndpointRole, "selectedEndpoint"},
        {SelectedNetworkRole, "selectedNetwork"},
        {SelectedReachableRole, "selectedReachable"},
        {SelectedDetailRole, "selectedDetail"}
    };
}

int ServerListModel::count() const {
    return static_cast<int>(m_entries.size());
}

QString ServerListModel::preferredNetworkType() const {
    return m_preferredNetworkType;
}

void ServerListModel::setPreferredNetworkType(const QString &value) {
    const QString normalized = value.trimmed().isEmpty() ? "auto" : value.trimmed();
    if (m_preferredNetworkType == normalized) {
        return;
    }
    m_preferredNetworkType = normalized;
    emit preferredNetworkTypeChanged();
    if (!m_entries.isEmpty()) {
        emit dataChanged(index(0), index(m_entries.size() - 1), {SelectedEndpointRole, SelectedNetworkRole, SelectedReachableRole, SelectedDetailRole});
    }
}

QVariantMap ServerListModel::get(int index) const {
    if (index < 0 || index >= m_entries.size()) {
        return {};
    }

    const ServerEntry &entry = m_entries.at(index);
    QVariantMap map;
    map.insert("key", entry.key);
    map.insert("serverId", entry.serverId);
    map.insert("name", entry.name);
    map.insert("source", entry.source);
    map.insert("status", entry.status);
    map.insert("lastSeenAt", entry.lastSeenAt);
    map.insert("lanAddresses", entry.lanAddresses);
    map.insert("wanEndpoint", entry.wanEndpoint);
    map.insert("overlayEndpoint", entry.overlayEndpoint);
    map.insert("lanReachable", entry.lanReachable);
    map.insert("wanReachable", entry.wanReachable);

    const Selection selection = selectEndpoint(entry);
    map.insert("selectedEndpoint", selection.endpoint);
    map.insert("selectedNetwork", selection.network);
    map.insert("selectedReachable", selection.reachable);
    map.insert("selectedDetail", selection.detail);

    return map;
}

void ServerListModel::setEntries(const QVector<ServerEntry> &entries) {
    beginResetModel();
    m_entries = entries;
    endResetModel();
    emit countChanged();
}

void ServerListModel::upsertEntry(const ServerEntry &entry) {
    const int index = indexForKey(entry.key);
    if (index >= 0) {
        m_entries[index] = entry;
        emit dataChanged(this->index(index), this->index(index));
        return;
    }

    const int row = m_entries.size();
    beginInsertRows(QModelIndex(), row, row);
    m_entries.push_back(entry);
    endInsertRows();
    emit countChanged();
}

void ServerListModel::removeEntry(const QString &key) {
    const int index = indexForKey(key);
    if (index < 0) {
        return;
    }
    beginRemoveRows(QModelIndex(), index, index);
    m_entries.removeAt(index);
    endRemoveRows();
    emit countChanged();
}

void ServerListModel::clear() {
    if (m_entries.isEmpty()) {
        return;
    }
    beginResetModel();
    m_entries.clear();
    endResetModel();
    emit countChanged();
}

bool ServerListModel::updateHealth(const QString &key, const QString &endpointType, bool reachable, const QString &detail) {
    const int index = indexForKey(key);
    if (index < 0) {
        return false;
    }

    ServerEntry &entry = m_entries[index];
    if (endpointType == "wan") {
        entry.wanReachable = reachable;
        entry.wanDetail = detail;
    } else {
        entry.lanReachable = reachable;
        entry.lanDetail = detail;
    }

    emit dataChanged(this->index(index), this->index(index), {LanReachableRole, WanReachableRole, SelectedEndpointRole, SelectedNetworkRole, SelectedReachableRole, SelectedDetailRole});
    return true;
}

QVector<ServerEntry> ServerListModel::entries() const {
    return m_entries;
}

int ServerListModel::indexForKey(const QString &key) const {
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries.at(i).key == key) {
            return i;
        }
    }
    return -1;
}

QString ServerListModel::primaryLanAddress(const ServerEntry &entry) const {
    if (!entry.lanAddresses.isEmpty()) {
        return entry.lanAddresses.first();
    }
    return {};
}

ServerListModel::Selection ServerListModel::selectEndpoint(const ServerEntry &entry) const {
    const QString lan = primaryLanAddress(entry);
    const QString wan = entry.wanEndpoint;
    const QString preferred = m_preferredNetworkType.toLower();

    if (preferred == "lan") {
        if (!lan.isEmpty()) {
            return {lan, "lan", entry.lanReachable, entry.lanDetail};
        }
        if (!wan.isEmpty()) {
            return {wan, "wan", entry.wanReachable, entry.wanDetail};
        }
    } else if (preferred == "wan") {
        if (!wan.isEmpty()) {
            return {wan, "wan", entry.wanReachable, entry.wanDetail};
        }
        if (!lan.isEmpty()) {
            return {lan, "lan", entry.lanReachable, entry.lanDetail};
        }
    } else {
        if (!lan.isEmpty() && entry.lanReachable) {
            return {lan, "lan", true, entry.lanDetail};
        }
        if (!wan.isEmpty() && entry.wanReachable) {
            return {wan, "wan", true, entry.wanDetail};
        }
        if (!lan.isEmpty()) {
            return {lan, "lan", entry.lanReachable, entry.lanDetail};
        }
        if (!wan.isEmpty()) {
            return {wan, "wan", entry.wanReachable, entry.wanDetail};
        }
    }

    return {QString(), "", false, QString()};
}
