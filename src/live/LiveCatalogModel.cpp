#include "LiveCatalogModel.h"

#include "LiveApiClient.h"

#include <QDateTime>
#include <algorithm>

LiveCatalogModel::LiveCatalogModel(LiveApiClient *apiClient, QObject *parent)
    : QAbstractListModel(parent), m_apiClient(apiClient) {
  connectApi();
}

int LiveCatalogModel::rowCount(const QModelIndex &parent) const {
  return parent.isValid() ? 0 : static_cast<int>(m_items.size());
}

QVariant LiveCatalogModel::data(const QModelIndex &index, int role) const {
  if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
    return {};
  }
  const Live::Item &item = m_items.at(index.row());
  switch (role) {
  case ProviderIdRole:
    return item.providerId;
  case ItemKeyRole:
    return item.itemKey;
  case ItemTypeRole:
    return item.itemType;
  case TitleRole:
    return item.title;
  case SubtitleRole:
    return item.subtitle;
  case DescriptionRole:
    return item.description;
  case StatusRole:
    return item.status;
  case StartsAtUtcRole:
    return item.startsAtUtc ? QVariant(*item.startsAtUtc) : QVariant();
  case EndsAtUtcRole:
    return item.endsAtUtc ? QVariant(*item.endsAtUtc) : QVariant();
  case StartsAtLocalRole:
    return localTime(item.startsAtUtc);
  case EndsAtLocalRole:
    return localTime(item.endsAtUtc);
  case PosterRole:
    return item.poster ? QVariant(item.poster->toVariantMap()) : QVariant();
  case BackgroundRole:
    return item.background ? QVariant(item.background->toVariantMap())
                           : QVariant();
  case LogoRole:
    return item.logo ? QVariant(item.logo->toVariantMap()) : QVariant();
  case CategoriesRole:
    return item.categories;
  case BadgesRole:
    return item.badges;
  case FactsRole:
    return item.toVariantMap().value(QStringLiteral("facts"));
  default:
    return {};
  }
}

QHash<int, QByteArray> LiveCatalogModel::roleNames() const {
  return {
      {ProviderIdRole, "providerId"},
      {ItemKeyRole, "itemKey"},
      {ItemTypeRole, "itemType"},
      {TitleRole, "title"},
      {SubtitleRole, "subtitle"},
      {DescriptionRole, "description"},
      {StatusRole, "status"},
      {StartsAtUtcRole, "startsAtUtc"},
      {EndsAtUtcRole, "endsAtUtc"},
      {StartsAtLocalRole, "startsAtLocal"},
      {EndsAtLocalRole, "endsAtLocal"},
      {PosterRole, "poster"},
      {BackgroundRole, "background"},
      {LogoRole, "logo"},
      {CategoriesRole, "categories"},
      {BadgesRole, "badges"},
      {FactsRole, "facts"},
  };
}

QVariantList LiveCatalogModel::providers() const {
  return Live::providersToVariants(m_providers);
}

QVariantList LiveCatalogModel::catalogs() const {
  return Live::catalogsToVariants(m_catalogs);
}

QString LiveCatalogModel::selectedProviderId() const {
  return m_selectedProviderId;
}
QString LiveCatalogModel::selectedCatalogId() const {
  return m_selectedCatalogId;
}
bool LiveCatalogModel::catalogIndexLoading() const {
  return m_catalogIndexLoading;
}
bool LiveCatalogModel::pageLoading() const { return m_pageLoading; }
bool LiveCatalogModel::loadingMore() const { return m_loadingMore; }
bool LiveCatalogModel::itemLoading() const { return m_itemLoading; }
bool LiveCatalogModel::hasMore() const { return !m_nextCursor.isEmpty(); }
bool LiveCatalogModel::stale() const { return m_stale; }
bool LiveCatalogModel::partial() const { return m_partial; }
QVariantList LiveCatalogModel::errors() const { return m_errors; }
QVariantMap LiveCatalogModel::lastError() const { return m_lastError; }
QVariantMap LiveCatalogModel::selectedItem() const { return m_selectedItem; }
QVariantList LiveCatalogModel::selectedStreams() const {
  return m_selectedStreams;
}
QString LiveCatalogModel::timeZoneId() const {
  return QString::fromUtf8(m_timeZone.id());
}
quint64 LiveCatalogModel::generation() const { return m_generation; }

void LiveCatalogModel::setTimeZoneId(const QString &timeZoneId) {
  const QTimeZone candidate(timeZoneId.toUtf8());
  if (!candidate.isValid() || candidate == m_timeZone) {
    return;
  }
  m_timeZone = candidate;
  if (!m_items.isEmpty()) {
    emit dataChanged(index(0), index(static_cast<int>(m_items.size() - 1)),
                     {StartsAtLocalRole, EndsAtLocalRole});
  }
  if (m_selectedItemData) {
    m_selectedItem = itemVariant(*m_selectedItemData);
    emit selectedItemChanged();
  }
  emit timeZoneChanged();
}

void LiveCatalogModel::refreshIndex() {
  beginNewGeneration();
  clearErrors();
  m_pageLoading = false;
  m_loadingMore = false;
  if (!m_selectedProviderId.isEmpty() && !m_selectedCatalogId.isEmpty()) {
    clearPage(true);
  }
  m_catalogIndexLoading = true;
  emit loadingChanged();
  m_providerRequestId =
      m_apiClient ? m_apiClient->listProviders(m_generation) : 0;
  m_catalogRequestId =
      m_apiClient ? m_apiClient->listCatalogs(m_generation) : 0;
  if (!m_apiClient) {
    m_catalogIndexLoading = false;
    setError({
        {QStringLiteral("code"), QStringLiteral("LIVE_CLIENT_UNAVAILABLE")},
        {QStringLiteral("message"),
         QStringLiteral("Live browsing is unavailable.")},
        {QStringLiteral("retryable"), false},
    });
    emit loadingChanged();
  }
}

void LiveCatalogModel::selectCatalog(const QString &providerId,
                                     const QString &catalogId,
                                     const QVariantMap &filters) {
  beginNewGeneration();
  m_selectedProviderId = providerId;
  m_selectedCatalogId = catalogId;
  m_filters = filters;
  emit selectionChanged();
  requestFirstPage(false);
}

void LiveCatalogModel::refreshPage() {
  if (m_selectedProviderId.isEmpty() || m_selectedCatalogId.isEmpty()) {
    return;
  }
  beginNewGeneration();
  requestFirstPage(true);
}

void LiveCatalogModel::loadMoreItems() {
  if (!m_apiClient || m_nextCursor.isEmpty() || m_loadingMore ||
      m_pageLoading) {
    return;
  }
  clearErrors();
  m_loadingMore = true;
  emit loadingChanged();
  m_pageRequestId =
      m_apiClient->listCatalogItems(m_selectedProviderId, m_selectedCatalogId,
                                    m_filters, m_nextCursor, 40, m_generation);
}

void LiveCatalogModel::loadItem(const QString &providerId,
                                const QString &itemKey) {
  if (!m_apiClient) {
    return;
  }
  cancelRequest(m_itemRequestId);
  m_selectedItem.clear();
  m_selectedItemData.reset();
  m_selectedStreams.clear();
  m_itemLoading = true;
  emit selectedItemChanged();
  emit loadingChanged();
  m_itemRequestId = m_apiClient->getItem(providerId, itemKey, m_generation);
}

void LiveCatalogModel::cancelItemRequest() {
  cancelRequest(m_itemRequestId);
  if (m_itemLoading) {
    m_itemLoading = false;
    emit loadingChanged();
  }
}

void LiveCatalogModel::clearSelection() {
  beginNewGeneration();
  m_selectedProviderId.clear();
  m_selectedCatalogId.clear();
  m_filters.clear();
  clearPage(false);
  emit selectionChanged();
}

void LiveCatalogModel::cancel() {
  beginNewGeneration();
  m_catalogIndexLoading = false;
  m_pageLoading = false;
  m_loadingMore = false;
  m_itemLoading = false;
  emit loadingChanged();
}

void LiveCatalogModel::connectApi() {
  if (!m_apiClient) {
    return;
  }
  connect(m_apiClient, &LiveApiClient::authContextInvalidated, this, [this]() {
    cancel();
    beginResetModel();
    m_items.clear();
    m_itemKeys.clear();
    endResetModel();
    m_providers.clear();
    m_catalogs.clear();
    m_selectedProviderId.clear();
    m_selectedCatalogId.clear();
    m_filters.clear();
    m_nextCursor.clear();
    m_selectedItem.clear();
    m_selectedItemData.reset();
    m_selectedStreams.clear();
    m_stale = false;
    m_partial = false;
    clearErrors();
    emit providersChanged();
    emit catalogsChanged();
    emit selectionChanged();
    emit selectedItemChanged();
    emit pageStateChanged();
  });
  connect(m_apiClient, &LiveApiClient::providersReceived, this,
          [this](quint64 requestId, quint64 generation,
                 const Live::ProvidersEnvelope &envelope) {
            if (requestId != m_providerRequestId ||
                generation != m_generation) {
              return;
            }
            m_providerRequestId = 0;
            m_providers = envelope.data;
            m_stale = envelope.meta.cacheState == QStringLiteral("stale");
            m_partial = m_partial || envelope.meta.partial;
            m_errors.append(Live::errorsToVariants(envelope.errors));
            m_catalogIndexLoading = m_catalogRequestId != 0;
            emit providersChanged();
            emit errorsChanged();
            emit pageStateChanged();
            emit loadingChanged();
          });
  connect(m_apiClient, &LiveApiClient::catalogsReceived, this,
          [this](quint64 requestId, quint64 generation,
                 const Live::CatalogsEnvelope &envelope) {
            if (requestId != m_catalogRequestId || generation != m_generation) {
              return;
            }
            m_catalogRequestId = 0;
            m_catalogs = envelope.data;
            const bool hadSelection = !m_selectedProviderId.isEmpty() &&
                                      !m_selectedCatalogId.isEmpty();
            const bool selectionAvailable =
                hadSelection &&
                std::any_of(m_catalogs.cbegin(), m_catalogs.cend(),
                            [this](const Live::Catalog &catalog) {
                              return catalog.providerId ==
                                         m_selectedProviderId &&
                                     catalog.catalogId == m_selectedCatalogId;
                            });
            const bool authoritative =
                !envelope.meta.partial &&
                envelope.meta.cacheState != QStringLiteral("stale");

            if (hadSelection && !selectionAvailable && authoritative) {
              m_selectedProviderId.clear();
              m_selectedCatalogId.clear();
              m_filters.clear();
              clearPage(false);
              emit selectionChanged();
            } else if (selectionAvailable && m_apiClient) {
              clearPage(true);
              m_pageLoading = true;
              m_pageRequestId = m_apiClient->listCatalogItems(
                  m_selectedProviderId, m_selectedCatalogId, m_filters,
                  QString(), 40, m_generation);
            }
            m_stale =
                m_stale || envelope.meta.cacheState == QStringLiteral("stale");
            m_partial = m_partial || envelope.meta.partial;
            m_errors.append(Live::errorsToVariants(envelope.errors));
            m_catalogIndexLoading = m_providerRequestId != 0;
            emit catalogsChanged();
            emit errorsChanged();
            emit pageStateChanged();
            emit loadingChanged();
          });
  connect(
      m_apiClient, &LiveApiClient::catalogPageReceived, this,
      [this](quint64 requestId, quint64 generation,
             const Live::CatalogPageEnvelope &envelope) {
        if (requestId != m_pageRequestId || generation != m_generation) {
          return;
        }
        const bool append = m_loadingMore;
        m_pageRequestId = 0;
        m_pageLoading = false;
        m_loadingMore = false;
        if (envelope.providerId != m_selectedProviderId ||
            envelope.catalogId != m_selectedCatalogId) {
          setError({
              {QStringLiteral("code"),
               QStringLiteral("LIVE_CLIENT_CONTEXT_MISMATCH")},
              {QStringLiteral("message"),
               QStringLiteral(
                   "The Live response did not match the selected catalog.")},
              {QStringLiteral("retryable"), true},
          });
        } else {
          applyPage(envelope, append);
        }
        emit loadingChanged();
      });
  connect(m_apiClient, &LiveApiClient::itemReceived, this,
          [this](quint64 requestId, quint64 generation,
                 const Live::ItemEnvelope &envelope) {
            if (requestId != m_itemRequestId || generation != m_generation) {
              return;
            }
            m_itemRequestId = 0;
            m_itemLoading = false;
            m_selectedItemData = envelope.item;
            m_selectedItem = itemVariant(envelope.item);
            m_selectedStreams = Live::streamsToVariants(envelope.streams);
            if (!envelope.errors.isEmpty()) {
              m_errors = Live::errorsToVariants(envelope.errors);
              emit errorsChanged();
            }
            emit selectedItemChanged();
            emit loadingChanged();
          });
  connect(m_apiClient, &LiveApiClient::requestFailed, this,
          [this](quint64 requestId, quint64 generation, const QString &,
                 const QVariantMap &error) {
            if (generation != m_generation) {
              return;
            }
            bool matched = false;
            if (requestId == m_providerRequestId) {
              m_providerRequestId = 0;
              matched = true;
            }
            if (requestId == m_catalogRequestId) {
              m_catalogRequestId = 0;
              matched = true;
            }
            if (requestId == m_pageRequestId) {
              m_pageRequestId = 0;
              m_pageLoading = false;
              m_loadingMore = false;
              matched = true;
            }
            if (requestId == m_itemRequestId) {
              m_itemRequestId = 0;
              m_itemLoading = false;
              matched = true;
            }
            if (!matched) {
              return;
            }
            m_catalogIndexLoading =
                m_providerRequestId != 0 || m_catalogRequestId != 0;
            setError(error);
            emit loadingChanged();
          });
  connect(m_apiClient, &LiveApiClient::requestCancelled, this,
          [this](quint64 requestId, quint64 generation) {
            if (generation != m_generation) {
              return;
            }
            if (requestId == m_providerRequestId)
              m_providerRequestId = 0;
            if (requestId == m_catalogRequestId)
              m_catalogRequestId = 0;
            if (requestId == m_pageRequestId)
              m_pageRequestId = 0;
            if (requestId == m_itemRequestId)
              m_itemRequestId = 0;
            m_catalogIndexLoading =
                m_providerRequestId != 0 || m_catalogRequestId != 0;
            m_pageLoading = false;
            m_loadingMore = false;
            m_itemLoading = false;
            emit loadingChanged();
          });
}

void LiveCatalogModel::beginNewGeneration() {
  cancelRequest(m_providerRequestId);
  cancelRequest(m_catalogRequestId);
  cancelRequest(m_pageRequestId);
  cancelRequest(m_itemRequestId);
  ++m_generation;
  if (m_generation == 0) {
    m_generation = 1;
  }
  emit generationChanged();
}

void LiveCatalogModel::requestFirstPage(bool preserveItems) {
  clearErrors();
  clearPage(preserveItems);
  m_pageLoading = true;
  emit loadingChanged();
  if (!m_apiClient) {
    m_pageLoading = false;
    setError({
        {QStringLiteral("code"), QStringLiteral("LIVE_CLIENT_UNAVAILABLE")},
        {QStringLiteral("message"),
         QStringLiteral("Live browsing is unavailable.")},
        {QStringLiteral("retryable"), false},
    });
    emit loadingChanged();
    return;
  }
  m_pageRequestId =
      m_apiClient->listCatalogItems(m_selectedProviderId, m_selectedCatalogId,
                                    m_filters, QString(), 40, m_generation);
}

void LiveCatalogModel::cancelRequest(quint64 &requestId) {
  if (requestId != 0 && m_apiClient) {
    m_apiClient->cancel(requestId);
  }
  requestId = 0;
}

void LiveCatalogModel::clearPage(bool preserveItems) {
  if (!preserveItems) {
    m_nextCursor.clear();
  }
  m_stale = false;
  m_partial = false;
  m_selectedItem.clear();
  m_selectedItemData.reset();
  m_selectedStreams.clear();
  if (!preserveItems && !m_items.isEmpty()) {
    beginResetModel();
    m_items.clear();
    m_itemKeys.clear();
    endResetModel();
  }
  emit selectedItemChanged();
  emit pageStateChanged();
}

void LiveCatalogModel::setError(const QVariantMap &error) {
  m_lastError = error;
  m_errors = {error};
  emit errorsChanged();
}

void LiveCatalogModel::clearErrors() {
  if (m_errors.isEmpty() && m_lastError.isEmpty()) {
    return;
  }
  m_errors.clear();
  m_lastError.clear();
  emit errorsChanged();
}

void LiveCatalogModel::applyPage(const Live::CatalogPageEnvelope &envelope,
                                 bool append) {
  if (!append) {
    const bool preserveNewerRows =
        envelope.meta.cacheState == QStringLiteral("stale") &&
        envelope.items.isEmpty() && !m_items.isEmpty();
    if (!preserveNewerRows) {
      beginResetModel();
      m_items = envelope.items;
      m_itemKeys.clear();
      for (const Live::Item &item : m_items) {
        m_itemKeys.insert(item.itemKey);
      }
      endResetModel();
      m_nextCursor = envelope.nextCursor;
    }
  } else {
    QList<Live::Item> additions;
    for (const Live::Item &item : envelope.items) {
      if (!m_itemKeys.contains(item.itemKey)) {
        additions.append(item);
        m_itemKeys.insert(item.itemKey);
      }
    }
    if (!additions.isEmpty()) {
      const int first = static_cast<int>(m_items.size());
      const int last = first + static_cast<int>(additions.size()) - 1;
      beginInsertRows({}, first, last);
      m_items.append(additions);
      endInsertRows();
    }
  }
  if (append) {
    m_nextCursor = envelope.nextCursor;
  }
  m_stale = envelope.meta.cacheState == QStringLiteral("stale");
  m_partial = envelope.meta.partial;
  m_errors = Live::errorsToVariants(envelope.errors);
  m_lastError.clear();
  emit pageStateChanged();
  emit errorsChanged();
}

QVariant
LiveCatalogModel::localTime(const std::optional<QDateTime> &utc) const {
  return utc ? QVariant(utc->toTimeZone(m_timeZone)) : QVariant();
}

QVariantMap LiveCatalogModel::itemVariant(const Live::Item &item) const {
  QVariantMap result = item.toVariantMap();
  result.insert(QStringLiteral("startsAtLocal"), localTime(item.startsAtUtc));
  result.insert(QStringLiteral("endsAtLocal"), localTime(item.endsAtUtc));
  return result;
}
