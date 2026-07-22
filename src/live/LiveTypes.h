#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QJsonDocument>
#include <QList>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantMap>

#include <optional>

namespace Live {

struct ApiError {
  QString code;
  QString message;
  bool retryable{false};
  std::optional<int> retryAfterSeconds;
  QString providerId;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct ApiMeta {
  QString requestId;
  QDateTime generatedAtUtc;
  QString cacheState;
  bool partial{false};

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct Provider {
  QString providerId;
  QString instanceId;
  QString extensionId;
  QString name;
  QString readiness;
  QString disabledReason;
  QString accountState;
  int contractVersion{0};
  QStringList itemTypes;
  QStringList protocols;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct FilterOption {
  QString value;
  QString label;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct FilterDefinition {
  QString id;
  QString label;
  QString type;
  bool required{false};
  QVariant defaultValue;
  QList<FilterOption> options;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct Catalog {
  QString providerId;
  QString catalogId;
  QString name;
  QString description;
  QStringList itemTypes;
  QString presentation;
  int order{0};
  QList<FilterDefinition> filters;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct Artwork {
  QString artworkId;
  QString url;
  QString kind;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct Fact {
  QString label;
  QString value;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct Item {
  QString providerId;
  QString itemKey;
  QString itemType;
  QString title;
  QString subtitle;
  QString description;
  QString status;
  std::optional<QDateTime> startsAtUtc;
  std::optional<QDateTime> endsAtUtc;
  std::optional<Artwork> poster;
  std::optional<Artwork> background;
  std::optional<Artwork> logo;
  QStringList categories;
  QStringList badges;
  QList<Fact> facts;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct StreamChoice {
  QString streamOptionKey;
  QString label;
  QString quality;
  QString language;
  QString protocolHint;
  int priority{0};

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct ProvidersEnvelope {
  QList<Provider> data;
  ApiMeta meta;
  QList<ApiError> errors;
};

struct CatalogsEnvelope {
  QList<Catalog> data;
  ApiMeta meta;
  QList<ApiError> errors;
};

struct CatalogPageEnvelope {
  QString providerId;
  QString catalogId;
  QList<Item> items;
  QString nextCursor;
  ApiMeta meta;
  QList<ApiError> errors;
};

struct ItemEnvelope {
  Item item;
  QList<StreamChoice> streams;
  ApiMeta meta;
  QList<ApiError> errors;
};

struct SelectedSource {
  QString sourceKey;
  QString label;
  QString quality;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct TrackSelection {
  QString trackId;
  QString language;
  QString title;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct TrackPreferences {
  std::optional<TrackSelection> audio;
  std::optional<TrackSelection> subtitle;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct LiveWindow {
  bool seekable{false};
  std::optional<int> windowSeconds;
  std::optional<double> targetLatencySeconds;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct SessionEgress {
  QString mode;
  QString fallbackReason;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct SessionCreated {
  QString sessionId;
  qint64 revision{0};
  std::optional<qint64> tokenRevision;
  QString deliveryMode;
  QString decisionReason;
  SessionEgress egress;
  QString playbackUrl;
  QByteArray sessionToken;
  QDateTime expiresAtUtc;
  QDateTime hardExpiresAtUtc;
  int heartbeatIntervalSeconds{0};
  LiveWindow live;
  SelectedSource selectedSource;
  QList<SelectedSource> availableSources;
  TrackPreferences trackPreferences;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct SessionDetail {
  QString sessionId;
  qint64 revision{0};
  QString state;
  QString deliveryMode;
  QString protocol;
  SelectedSource selectedSource;
  QList<SelectedSource> availableSources;
  TrackPreferences trackPreferences;
  QDateTime expiresAtUtc;
  QDateTime hardExpiresAtUtc;
  QString errorCode;

  [[nodiscard]] QVariantMap toVariantMap() const;
};

struct SessionDetailEnvelope {
  SessionDetail data;
  ApiMeta meta;
  QList<ApiError> errors;
};

struct ErrorEnvelope {
  ApiMeta meta;
  QList<ApiError> errors;
};

template <typename T> struct ParseResult {
  std::optional<T> value;
  QString error;

  [[nodiscard]] explicit operator bool() const noexcept {
    return value.has_value();
  }
};

[[nodiscard]] ParseResult<ProvidersEnvelope>
parseProviders(const QJsonDocument &document);
[[nodiscard]] ParseResult<CatalogsEnvelope>
parseCatalogs(const QJsonDocument &document);
[[nodiscard]] ParseResult<CatalogPageEnvelope>
parseCatalogPage(const QJsonDocument &document);
[[nodiscard]] ParseResult<ItemEnvelope>
parseItem(const QJsonDocument &document);
[[nodiscard]] ParseResult<SessionCreated>
parseSessionCreated(const QJsonDocument &document);
[[nodiscard]] ParseResult<SessionDetailEnvelope>
parseSessionDetail(const QJsonDocument &document);
[[nodiscard]] ParseResult<ErrorEnvelope>
parseError(const QJsonDocument &document);

[[nodiscard]] QVariantList
providersToVariants(const QList<Provider> &providers);
[[nodiscard]] QVariantList catalogsToVariants(const QList<Catalog> &catalogs);
[[nodiscard]] QVariantList errorsToVariants(const QList<ApiError> &errors);
[[nodiscard]] QVariantList
streamsToVariants(const QList<StreamChoice> &streams);

} // namespace Live

Q_DECLARE_METATYPE(Live::ProvidersEnvelope)
Q_DECLARE_METATYPE(Live::CatalogsEnvelope)
Q_DECLARE_METATYPE(Live::CatalogPageEnvelope)
Q_DECLARE_METATYPE(Live::ItemEnvelope)
Q_DECLARE_METATYPE(Live::SessionCreated)
Q_DECLARE_METATYPE(Live::SessionDetailEnvelope)
