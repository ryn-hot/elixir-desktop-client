#include "backend/LibraryModel.h"

#include <QJsonValue>
#include <QMetaType>

MediaFilterModel::MediaFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent) {
    setDynamicSortFilter(true);
    setSortCaseSensitivity(Qt::CaseInsensitive);
    setSortLocaleAware(true);

    auto emitCountChanged = [this]() { emit countChanged(); };
    connect(this, &QAbstractItemModel::rowsInserted, this, emitCountChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, emitCountChanged);
    connect(this, &QAbstractItemModel::modelReset, this, emitCountChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, emitCountChanged);
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

QString MediaFilterModel::searchQuery() const {
    return m_searchQuery;
}

void MediaFilterModel::setSearchQuery(const QString &value) {
    if (m_searchQuery == value) {
        return;
    }
    m_searchQuery = value;
    invalidateFilter();
    emit searchQueryChanged();
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

int MediaFilterModel::count() const {
    return rowCount();
}

bool MediaFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const {
    const QModelIndex index = sourceModel()->index(sourceRow, 0, sourceParent);
    if (!m_typeFilter.isEmpty()) {
        const QString type = sourceModel()->data(index, MediaRoles::TypeRole).toString();
        if (type != m_typeFilter) {
            return false;
        }
    }
    if (!m_searchQuery.trimmed().isEmpty()) {
        const QString query = m_searchQuery.trimmed();
        const QString title = sourceModel()->data(index, MediaRoles::TitleRole).toString();
        const QString overview = sourceModel()->data(index, MediaRoles::OverviewRole).toString();
        if (!title.contains(query, Qt::CaseInsensitive) &&
            !overview.contains(query, Qt::CaseInsensitive)) {
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

    m_searchModel.setSourceModel(this);
    applySortMode();
    applyFilterMode();
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

QAbstractItemModel *LibraryModel::searchModel() {
    return &m_searchModel;
}

QString LibraryModel::searchQuery() const {
    return m_searchQuery;
}

void LibraryModel::setSearchQuery(const QString &value) {
    if (m_searchQuery == value) {
        return;
    }
    m_searchQuery = value;
    applySearchQuery();
    emit searchQueryChanged();
}

QString LibraryModel::sortMode() const {
    return m_sortMode;
}

void LibraryModel::setSortMode(const QString &value) {
    const QString normalized = value.trimmed().isEmpty() ? "recent" : value.trimmed().toLower();
    if (m_sortMode == normalized) {
        return;
    }
    m_sortMode = normalized;
    applySortMode();
    emit sortModeChanged();
}

QString LibraryModel::filterMode() const {
    return m_filterMode;
}

void LibraryModel::setFilterMode(const QString &value) {
    const QString normalized = value.trimmed().isEmpty() ? "all" : value.trimmed().toLower();
    if (m_filterMode == normalized) {
        return;
    }
    m_filterMode = normalized;
    applyFilterMode();
    emit filterModeChanged();
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
    if (item.title.trimmed().isEmpty()) {
        item.title = extractTitle(metadata);
    }
    if (item.year <= 0) {
        item.year = extractYear(metadata);
    }
    item.posterUrl = extractImage(metadata, {"poster", "posterUrl", "poster_url", "poster_path", "cover", "image"});
    item.backdropUrl = extractImage(metadata, {"background", "backdrop", "fanart", "backdropUrl", "backdrop_path"});
    if (item.backdropUrl.isEmpty()) {
        item.backdropUrl = item.posterUrl;
    }
    item.overview = extractDescription(metadata);
    if (item.overview.isEmpty()) {
        item.overview = map.value("description").toString();
        if (item.overview.isEmpty()) {
            item.overview = map.value("summary").toString();
        }
    }

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

QString LibraryModel::extractTitle(const QVariantMap &metadata) const {
    for (const QString &key : {"title", "name", "original_title", "original_name"}) {
        const QString value = metadata.value(key).toString();
        if (!value.isEmpty()) {
            return value;
        }
    }

    if (metadata.contains("title")) {
        const QVariantMap nested = metadata.value("title").toMap();
        for (const QString &key : {"english", "romaji", "native"}) {
            const QString value = nested.value(key).toString();
            if (!value.isEmpty()) {
                return value;
            }
        }
    }

    return QString();
}

int LibraryModel::extractYear(const QVariantMap &metadata) const {
    const int metaYear = metadata.value("year").toInt();
    if (metaYear > 0) {
        return metaYear;
    }

    const QString date = metadata.value("release_date").toString();
    if (date.size() >= 4) {
        const int year = date.left(4).toInt();
        if (year > 0) {
            return year;
        }
    }

    const QString firstAir = metadata.value("first_air_date").toString();
    if (firstAir.size() >= 4) {
        const int year = firstAir.left(4).toInt();
        if (year > 0) {
            return year;
        }
    }

    const QVariantMap startDate = metadata.value("startDate").toMap();
    const int startYear = startDate.value("year").toInt();
    if (startYear > 0) {
        return startYear;
    }

    return 0;
}

void LibraryModel::applySearchQuery() {
    m_searchModel.setSearchQuery(m_searchQuery);
}

void LibraryModel::applySortMode() {
    int role = MediaRoles::UpdatedAtRole;
    Qt::SortOrder order = Qt::DescendingOrder;

    if (m_sortMode == "title") {
        role = MediaRoles::TitleRole;
        order = Qt::AscendingOrder;
    } else if (m_sortMode == "year") {
        role = MediaRoles::YearRole;
        order = Qt::DescendingOrder;
    }

    for (MediaFilterModel *model : {&m_allModel, &m_moviesModel, &m_seriesModel, &m_animeModel, &m_continueModel, &m_searchModel}) {
        model->setSortRole(role);
        model->sort(0, order);
    }
}

void LibraryModel::applyFilterMode() {
    if (m_filterMode == "movies") {
        m_searchModel.setTypeFilter("movie");
        m_searchModel.setRequireProgress(false);
    } else if (m_filterMode == "series") {
        m_searchModel.setTypeFilter("series");
        m_searchModel.setRequireProgress(false);
    } else if (m_filterMode == "anime") {
        m_searchModel.setTypeFilter("anime");
        m_searchModel.setRequireProgress(false);
    } else if (m_filterMode == "continue") {
        m_searchModel.setTypeFilter(QString());
        m_searchModel.setRequireProgress(true);
    } else {
        m_searchModel.setTypeFilter(QString());
        m_searchModel.setRequireProgress(false);
    }
}
