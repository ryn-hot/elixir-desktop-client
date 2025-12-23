#pragma once

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QStringList>
#include <QVector>

#include "backend/MediaItem.h"

namespace MediaRoles {
    enum Role {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        TypeRole,
        YearRole,
        PosterRole,
        BackdropRole,
        OverviewRole,
        ProgressRole,
        RuntimeRole,
        UpdatedAtRole
    };
}

class MediaFilterModel : public QSortFilterProxyModel {
    Q_OBJECT
    Q_PROPERTY(QString typeFilter READ typeFilter WRITE setTypeFilter NOTIFY typeFilterChanged)
    Q_PROPERTY(bool requireProgress READ requireProgress WRITE setRequireProgress NOTIFY requireProgressChanged)

public:
    explicit MediaFilterModel(QObject *parent = nullptr);

    QString typeFilter() const;
    void setTypeFilter(const QString &value);

    bool requireProgress() const;
    void setRequireProgress(bool value);

signals:
    void typeFilterChanged();
    void requireProgressChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    QString m_typeFilter;
    bool m_requireProgress = false;
};

class LibraryModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit LibraryModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;

    Q_INVOKABLE QVariantMap get(int index) const;
    Q_INVOKABLE int indexOfId(const QString &id) const;
    Q_INVOKABLE QAbstractItemModel *allModel();
    Q_INVOKABLE QAbstractItemModel *moviesModel();
    Q_INVOKABLE QAbstractItemModel *seriesModel();
    Q_INVOKABLE QAbstractItemModel *animeModel();
    Q_INVOKABLE QAbstractItemModel *continueWatchingModel();

public slots:
    void setItems(const QVariantList &items);

signals:
    void countChanged();

private:
    MediaItem itemFromVariant(const QVariantMap &map) const;
    QString extractImage(const QVariantMap &metadata, const QStringList &keys) const;
    QString extractDescription(const QVariantMap &metadata) const;

    QVector<MediaItem> m_items;
    MediaFilterModel m_allModel;
    MediaFilterModel m_moviesModel;
    MediaFilterModel m_seriesModel;
    MediaFilterModel m_animeModel;
    MediaFilterModel m_continueModel;
};
