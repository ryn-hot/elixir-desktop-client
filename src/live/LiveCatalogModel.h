#pragma once

#include "LiveTypes.h"

#include <QAbstractListModel>
#include <QSet>
#include <QTimeZone>
#include <QVariantList>
#include <QVariantMap>

class LiveApiClient;

class LiveCatalogModel final : public QAbstractListModel {
  Q_OBJECT
  Q_PROPERTY(QVariantList providers READ providers NOTIFY providersChanged)
  Q_PROPERTY(QVariantList catalogs READ catalogs NOTIFY catalogsChanged)
  Q_PROPERTY(QString selectedProviderId READ selectedProviderId NOTIFY
                 selectionChanged)
  Q_PROPERTY(
      QString selectedCatalogId READ selectedCatalogId NOTIFY selectionChanged)
  Q_PROPERTY(
      bool catalogIndexLoading READ catalogIndexLoading NOTIFY loadingChanged)
  Q_PROPERTY(bool pageLoading READ pageLoading NOTIFY loadingChanged)
  Q_PROPERTY(bool loadingMore READ loadingMore NOTIFY loadingChanged)
  Q_PROPERTY(bool itemLoading READ itemLoading NOTIFY loadingChanged)
  Q_PROPERTY(bool hasMore READ hasMore NOTIFY pageStateChanged)
  Q_PROPERTY(bool stale READ stale NOTIFY pageStateChanged)
  Q_PROPERTY(bool partial READ partial NOTIFY pageStateChanged)
  Q_PROPERTY(QVariantList errors READ errors NOTIFY errorsChanged)
  Q_PROPERTY(QVariantMap lastError READ lastError NOTIFY errorsChanged)
  Q_PROPERTY(
      QVariantMap selectedItem READ selectedItem NOTIFY selectedItemChanged)
  Q_PROPERTY(QVariantList selectedStreams READ selectedStreams NOTIFY
                 selectedItemChanged)
  Q_PROPERTY(QString timeZoneId READ timeZoneId WRITE setTimeZoneId NOTIFY
                 timeZoneChanged)
  Q_PROPERTY(quint64 generation READ generation NOTIFY generationChanged)

public:
  enum Role {
    ProviderIdRole = Qt::UserRole + 1,
    ItemKeyRole,
    ItemTypeRole,
    TitleRole,
    SubtitleRole,
    DescriptionRole,
    StatusRole,
    StartsAtUtcRole,
    EndsAtUtcRole,
    StartsAtLocalRole,
    EndsAtLocalRole,
    PosterRole,
    BackgroundRole,
    LogoRole,
    CategoriesRole,
    BadgesRole,
    FactsRole,
  };
  Q_ENUM(Role)

  explicit LiveCatalogModel(LiveApiClient *apiClient,
                            QObject *parent = nullptr);

  [[nodiscard]] int
  rowCount(const QModelIndex &parent = QModelIndex()) const override;
  [[nodiscard]] QVariant data(const QModelIndex &index,
                              int role) const override;
  [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

  [[nodiscard]] QVariantList providers() const;
  [[nodiscard]] QVariantList catalogs() const;
  [[nodiscard]] QString selectedProviderId() const;
  [[nodiscard]] QString selectedCatalogId() const;
  [[nodiscard]] bool catalogIndexLoading() const;
  [[nodiscard]] bool pageLoading() const;
  [[nodiscard]] bool loadingMore() const;
  [[nodiscard]] bool itemLoading() const;
  [[nodiscard]] bool hasMore() const;
  [[nodiscard]] bool stale() const;
  [[nodiscard]] bool partial() const;
  [[nodiscard]] QVariantList errors() const;
  [[nodiscard]] QVariantMap lastError() const;
  [[nodiscard]] QVariantMap selectedItem() const;
  [[nodiscard]] QVariantList selectedStreams() const;
  [[nodiscard]] QString timeZoneId() const;
  void setTimeZoneId(const QString &timeZoneId);
  [[nodiscard]] quint64 generation() const;

  Q_INVOKABLE void refreshIndex();
  Q_INVOKABLE void selectCatalog(const QString &providerId,
                                 const QString &catalogId,
                                 const QVariantMap &filters = {});
  Q_INVOKABLE void refreshPage();
  Q_INVOKABLE void loadMoreItems();
  Q_INVOKABLE void loadItem(const QString &providerId, const QString &itemKey);
  Q_INVOKABLE void cancelItemRequest();
  Q_INVOKABLE void clearSelection();
  Q_INVOKABLE void cancel();

signals:
  void providersChanged();
  void catalogsChanged();
  void selectionChanged();
  void loadingChanged();
  void pageStateChanged();
  void errorsChanged();
  void selectedItemChanged();
  void timeZoneChanged();
  void generationChanged();

private:
  void connectApi();
  void beginNewGeneration();
  void requestFirstPage(bool preserveItems);
  void cancelRequest(quint64 &requestId);
  void clearPage(bool preserveItems);
  void setError(const QVariantMap &error);
  void clearErrors();
  void applyPage(const Live::CatalogPageEnvelope &envelope, bool append);
  [[nodiscard]] QVariant localTime(const std::optional<QDateTime> &utc) const;
  [[nodiscard]] QVariantMap itemVariant(const Live::Item &item) const;

  LiveApiClient *m_apiClient{nullptr};
  QList<Live::Provider> m_providers;
  QList<Live::Catalog> m_catalogs;
  QList<Live::Item> m_items;
  QSet<QString> m_itemKeys;
  QString m_selectedProviderId;
  QString m_selectedCatalogId;
  QVariantMap m_filters;
  QString m_nextCursor;
  bool m_catalogIndexLoading{false};
  bool m_pageLoading{false};
  bool m_loadingMore{false};
  bool m_itemLoading{false};
  bool m_stale{false};
  bool m_partial{false};
  QVariantList m_errors;
  QVariantMap m_lastError;
  QVariantMap m_selectedItem;
  std::optional<Live::Item> m_selectedItemData;
  QVariantList m_selectedStreams;
  QTimeZone m_timeZone{QTimeZone::systemTimeZone()};
  quint64 m_generation{1};
  quint64 m_providerRequestId{0};
  quint64 m_catalogRequestId{0};
  quint64 m_pageRequestId{0};
  quint64 m_itemRequestId{0};
};
