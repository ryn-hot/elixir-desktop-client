#include "backend/LibraryModel.h"

#include <QJsonValue>
#include <QMetaType>

MediaFilterModel::MediaFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent) {
    setDynamicSortFilter(true);
}

QString MediaFilterModel::typeFilter() const {
    return m_typeFilter;
}

void MediaFilterModel::setTypeFilter(const QString &value) {
    if (m_typeFilter == value) {
        return;
    }
    m_typeFilter = value;
    invalidateFilter();
    emit typeFilterChanged();
}

bool MediaFilterModel::requireProgress() const {
    return m_requireProgress;
}

void MediaFilterModel::setRequireProgress(bool value) {
    if (m_requireProgress == value) {
        return;
    }
    m_requireProgress = value;
    invalidateFilter();
    emit requireProgressChanged();
}

bool MediaFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const {
    const QModelIndex index = sourceModel()->index(sourceRow, 0, sourceParent);
    if (!m_typeFilter.isEmpty()) {
        const QString type = sourceModel()->data(index, MediaRoles::TypeRole).toString();
        if (type != m_typeFilter) {
            return false;
        }
    }
    if (m_requireProgress) {
        const double progress = sourceModel()->data(index, MediaRoles::ProgressRole).toDouble();
        if (progress <= 0.0) {
            return false;
        }
    }
    return true;
}

LibraryModel::LibraryModel(QObject *parent)
    : QAbstractListModel(parent) {
    m_allModel.setSourceModel(this);

    m_moviesModel.setSourceModel(this);
    m_moviesModel.setTypeFilter("movie");

    m_seriesModel.setSourceModel(this);
    m_seriesModel.setTypeFilter("series");

    m_animeModel.setSourceModel(this);
    m_animeModel.setTypeFilter("anime");

    m_continueModel.setSourceModel(this);
    m_continueModel.setRequireProgress(true);
}

int LibraryModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) {
        return 0;
    }
    return m_items.size();
}

QVariant LibraryModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return QVariant();
    }
    const MediaItem &item = m_items.at(index.row());
    switch (role) {
        case MediaRoles::IdRole:
            return item.id;
        case MediaRoles::TitleRole:
            return item.title;
        case MediaRoles::TypeRole:
            return item.type;
        case MediaRoles::YearRole:
            return item.year;
        case MediaRoles::PosterRole:
            return item.posterUrl;
        case MediaRoles::BackdropRole:
            return item.backdropUrl;
        case MediaRoles::OverviewRole:
            return item.overview;
        case MediaRoles::ProgressRole:
            return item.progress;
        case MediaRoles::RuntimeRole:
            return item.runtimeSeconds;
        case MediaRoles::UpdatedAtRole:
            return item.updatedAt;
        default:
            return QVariant();
    }
}

QHash<int, QByteArray> LibraryModel::roleNames() const {
    return {
        {MediaRoles::IdRole, "mediaId"},
        {MediaRoles::TitleRole, "title"},
        {MediaRoles::TypeRole, "type"},
        {MediaRoles::YearRole, "year"},
        {MediaRoles::PosterRole, "poster"},
        {MediaRoles::BackdropRole, "backdrop"},
        {MediaRoles::OverviewRole, "overview"},
        {MediaRoles::ProgressRole, "progress"},
        {MediaRoles::RuntimeRole, "runtime"},
        {MediaRoles::UpdatedAtRole, "updatedAt"},
    };
}

int LibraryModel::count() const {
    return m_items.size();
}

QVariantMap LibraryModel::get(int index) const {
    if (index < 0 || index >= m_items.size()) {
        return QVariantMap();
    }
    const MediaItem &item = m_items.at(index);
    return {
        {"mediaId", item.id},
        {"title", item.title},
        {"type", item.type},
        {"year", item.year},
        {"poster", item.posterUrl},
        {"backdrop", item.backdropUrl},
        {"overview", item.overview},
        {"progress", item.progress},
        {"runtime", item.runtimeSeconds},
        {"updatedAt", item.updatedAt},
    };
}

int LibraryModel::indexOfId(const QString &id) const {
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

QAbstractItemModel *LibraryModel::allModel() {
    return &m_allModel;
}

QAbstractItemModel *LibraryModel::moviesModel() {
    return &m_moviesModel;
}

QAbstractItemModel *LibraryModel::seriesModel() {
    return &m_seriesModel;
}

QAbstractItemModel *LibraryModel::animeModel() {
    return &m_animeModel;
}

QAbstractItemModel *LibraryModel::continueWatchingModel() {
    return &m_continueModel;
}

void LibraryModel::setItems(const QVariantList &items) {
    beginResetModel();
    m_items.clear();
    m_items.reserve(items.size());
    for (const QVariant &value : items) {
        const QVariantMap map = value.toMap();
        if (!map.isEmpty()) {
            m_items.push_back(itemFromVariant(map));
        }
    }
    endResetModel();
    emit countChanged();
}

MediaItem LibraryModel::itemFromVariant(const QVariantMap &map) const {
    MediaItem item;
    item.id = map.value("id").toString();
    item.title = map.value("title").toString();
    item.type = map.value("type").toString();
    item.year = map.value("year").toInt();
    item.updatedAt = map.value("updated_at").toString();
    item.runtimeSeconds = map.value("runtime_seconds").toInt();
    item.progress = map.value("progress").toDouble();

    const QVariantMap metadata = map.value("metadata").toMap();
    item.posterUrl = extractImage(metadata, {"poster", "posterUrl", "poster_url", "poster_path", "cover", "image"});
    item.backdropUrl = extractImage(metadata, {"background", "backdrop", "fanart", "backdropUrl", "backdrop_path"});
    if (item.backdropUrl.isEmpty()) {
        item.backdropUrl = item.posterUrl;
    }
    item.overview = extractDescription(metadata);

    return item;
}

QString LibraryModel::extractImage(const QVariantMap &metadata, const QStringList &keys) const {
    for (const QString &key : keys) {
        const QVariant value = metadata.value(key);
        if (!value.isValid()) {
            continue;
        }
        if (value.typeId() == QMetaType::QString) {
            const QString url = value.toString();
            if (!url.isEmpty()) {
                return url;
            }
        } else if (value.typeId() == QMetaType::QVariantMap) {
            const QVariantMap nested = value.toMap();
            const QString url = nested.value("url").toString();
            if (!url.isEmpty()) {
                return url;
            }
            for (const QString &subKey : {"extraLarge", "large", "medium", "original", "path"}) {
                const QString candidate = nested.value(subKey).toString();
                if (!candidate.isEmpty()) {
                    return candidate;
                }
            }
        }
    }

    if (metadata.contains("coverImage")) {
        const QVariantMap cover = metadata.value("coverImage").toMap();
        for (const QString &subKey : {"extraLarge", "large", "medium", "color"}) {
            const QString candidate = cover.value(subKey).toString();
            if (!candidate.isEmpty()) {
                return candidate;
            }
        }
    }

    return QString();
}

QString LibraryModel::extractDescription(const QVariantMap &metadata) const {
    for (const QString &key : {"description", "overview", "plot", "summary"}) {
        const QString raw = metadata.value(key).toString();
        if (raw.isEmpty()) {
            continue;
        }
        QString cleaned;
        cleaned.reserve(raw.size());
        bool inTag = false;
        for (const QChar &ch : raw) {
            if (ch == '<') {
                inTag = true;
                continue;
            }
            if (ch == '>') {
                inTag = false;
                continue;
            }
            if (!inTag) {
                cleaned.append(ch);
            }
        }
        return cleaned.simplified();
    }
    return QString();
}
