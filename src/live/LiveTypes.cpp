#include "LiveTypes.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QRegularExpression>
#include <QSet>
#include <QUuid>

#include <cmath>
#include <limits>

namespace {

constexpr int kShortTextMax = 256;

QString pathError(const QString &path, const QString &message) {
  return QStringLiteral("%1: %2").arg(path, message);
}

bool isInteger(const QJsonValue &value, int *result) {
  if (!value.isDouble()) {
    return false;
  }
  const double number = value.toDouble();
  if (!std::isfinite(number) || std::floor(number) != number ||
      number < static_cast<double>(std::numeric_limits<int>::min()) ||
      number > static_cast<double>(std::numeric_limits<int>::max())) {
    return false;
  }
  *result = static_cast<int>(number);
  return true;
}

bool hasForbiddenControl(const QString &value) {
  for (const QChar character : value) {
    const ushort code = character.unicode();
    if (code <= 0x0008 || code == 0x000B || code == 0x000C ||
        (code >= 0x000E && code <= 0x001F) || code == 0x007F) {
      return true;
    }
  }
  return false;
}

bool rejectUnknownKeys(const QJsonObject &object, const QSet<QString> &allowed,
                       QString *error, const QString &path) {
  for (const QString &key : object.keys()) {
    if (!allowed.contains(key)) {
      *error = pathError(path + '.' + key, QStringLiteral("unknown field"));
      return false;
    }
  }
  return true;
}

bool parseString(const QJsonObject &object, const QString &key, QString *output,
                 QString *error, const QString &path, int minimum, int maximum,
                 bool nullable = false) {
  if (!object.contains(key)) {
    *error =
        pathError(path + '.' + key, QStringLiteral("missing required field"));
    return false;
  }
  const QJsonValue value = object.value(key);
  if (nullable && value.isNull()) {
    output->clear();
    return true;
  }
  if (!value.isString()) {
    *error = pathError(path + '.' + key, QStringLiteral("expected string"));
    return false;
  }
  const QString string = value.toString();
  if (string.size() < minimum || string.size() > maximum ||
      hasForbiddenControl(string)) {
    *error = pathError(
        path + '.' + key,
        QStringLiteral("invalid string bounds or control characters"));
    return false;
  }
  *output = string;
  return true;
}

bool parseOptionalString(const QJsonObject &object, const QString &key,
                         QString *output, QString *error, const QString &path,
                         int maximum) {
  if (!object.contains(key) || object.value(key).isNull()) {
    output->clear();
    return true;
  }
  return parseString(object, key, output, error, path, 0, maximum);
}

bool parseBool(const QJsonObject &object, const QString &key, bool *output,
               QString *error, const QString &path) {
  if (!object.contains(key) || !object.value(key).isBool()) {
    *error = pathError(path + '.' + key, QStringLiteral("expected boolean"));
    return false;
  }
  *output = object.value(key).toBool();
  return true;
}

bool parseInt(const QJsonObject &object, const QString &key, int *output,
              QString *error, const QString &path) {
  if (!object.contains(key) || !isInteger(object.value(key), output)) {
    *error = pathError(path + '.' + key, QStringLiteral("expected integer"));
    return false;
  }
  return true;
}

bool parsePositiveInt64(const QJsonObject &object, const QString &key,
                        qint64 *output, QString *error, const QString &path,
                        bool optional = false) {
  if (optional && !object.contains(key)) {
    return true;
  }
  if (!object.contains(key) || !object.value(key).isDouble()) {
    *error = pathError(path + '.' + key, QStringLiteral("expected integer"));
    return false;
  }
  const double number = object.value(key).toDouble();
  if (!std::isfinite(number) || std::floor(number) != number || number < 1.0 ||
      number > 9'007'199'254'740'991.0) {
    *error = pathError(path + '.' + key,
                       QStringLiteral("expected positive safe integer"));
    return false;
  }
  *output = static_cast<qint64>(number);
  return true;
}

bool isUuid(const QString &value) {
  static const QRegularExpression pattern(
      QStringLiteral("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-["
                     "89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"));
  return pattern.match(value).hasMatch() && !QUuid(value).isNull();
}

bool parseUuid(const QJsonObject &object, const QString &key, QString *output,
               QString *error, const QString &path, bool nullable = false) {
  if (!parseString(object, key, output, error, path, 0, 64, nullable)) {
    return false;
  }
  if (nullable && output->isEmpty()) {
    return true;
  }
  if (!isUuid(*output)) {
    *error = pathError(path + '.' + key, QStringLiteral("expected UUID"));
    return false;
  }
  return true;
}

bool parseEnum(const QJsonObject &object, const QString &key, QString *output,
               QString *error, const QString &path,
               const QSet<QString> &allowed, bool nullable = false) {
  if (!parseString(object, key, output, error, path, 0, 256, nullable)) {
    return false;
  }
  if (nullable && output->isEmpty()) {
    return true;
  }
  if (!allowed.contains(*output)) {
    *error = pathError(path + '.' + key, QStringLiteral("unsupported value"));
    return false;
  }
  return true;
}

bool parseStringArray(const QJsonObject &object, const QString &key,
                      QStringList *output, QString *error, const QString &path,
                      int minimum, int maximum, int itemMaximum,
                      const QSet<QString> &allowed = {}) {
  if (!object.contains(key) || !object.value(key).isArray()) {
    *error = pathError(path + '.' + key, QStringLiteral("expected array"));
    return false;
  }
  const QJsonArray values = object.value(key).toArray();
  if (values.size() < minimum || values.size() > maximum) {
    *error =
        pathError(path + '.' + key, QStringLiteral("invalid array bounds"));
    return false;
  }
  QSet<QString> unique;
  output->clear();
  for (qsizetype index = 0; index < values.size(); ++index) {
    const QJsonValue value = values.at(index);
    if (!value.isString()) {
      *error = pathError(QStringLiteral("%1.%2[%3]").arg(path, key).arg(index),
                         QStringLiteral("expected string"));
      return false;
    }
    const QString item = value.toString();
    if (item.isEmpty() || item.size() > itemMaximum ||
        hasForbiddenControl(item) ||
        (!allowed.isEmpty() && !allowed.contains(item)) ||
        unique.contains(item)) {
      *error = pathError(QStringLiteral("%1.%2[%3]").arg(path, key).arg(index),
                         QStringLiteral("invalid or duplicate value"));
      return false;
    }
    unique.insert(item);
    output->append(item);
  }
  return true;
}

bool parseUtcDateTimeValue(const QJsonValue &value,
                           std::optional<QDateTime> *output, QString *error,
                           const QString &path, bool nullable) {
  if (nullable && value.isNull()) {
    output->reset();
    return true;
  }
  if (!value.isString() || !value.toString().endsWith('Z')) {
    *error =
        pathError(path, QStringLiteral("expected a UTC date-time ending in Z"));
    return false;
  }
  QDateTime parsed = QDateTime::fromString(value.toString(), Qt::ISODateWithMs);
  if (!parsed.isValid()) {
    parsed = QDateTime::fromString(value.toString(), Qt::ISODate);
  }
  if (!parsed.isValid() || parsed.offsetFromUtc() != 0) {
    *error = pathError(path, QStringLiteral("invalid UTC date-time"));
    return false;
  }
  *output = parsed.toUTC();
  return true;
}

bool parseMeta(const QJsonValue &value, Live::ApiMeta *output, QString *error) {
  if (!value.isObject()) {
    *error =
        pathError(QStringLiteral("$.meta"), QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  static const QSet<QString> keys{
      QStringLiteral("requestId"),
      QStringLiteral("generatedAt"),
      QStringLiteral("cacheState"),
      QStringLiteral("partial"),
  };
  for (const QString &key : object.keys()) {
    if (!keys.contains(key)) {
      *error = pathError(QStringLiteral("$.meta.%1").arg(key),
                         QStringLiteral("unknown field"));
      return false;
    }
  }
  if (!parseString(object, QStringLiteral("requestId"), &output->requestId,
                   error, QStringLiteral("$.meta"), 16, 64)) {
    return false;
  }
  static const QRegularExpression requestPattern(
      QStringLiteral("^[A-Za-z0-9_-]+$"));
  if (!requestPattern.match(output->requestId).hasMatch()) {
    *error = pathError(QStringLiteral("$.meta.requestId"),
                       QStringLiteral("invalid request id"));
    return false;
  }
  std::optional<QDateTime> generatedAt;
  if (!object.contains(QStringLiteral("generatedAt")) ||
      !parseUtcDateTimeValue(object.value(QStringLiteral("generatedAt")),
                             &generatedAt, error,
                             QStringLiteral("$.meta.generatedAt"), false)) {
    return false;
  }
  output->generatedAtUtc = *generatedAt;
  if (!parseEnum(object, QStringLiteral("cacheState"), &output->cacheState,
                 error, QStringLiteral("$.meta"),
                 {QStringLiteral("none"), QStringLiteral("fresh"),
                  QStringLiteral("stale"), QStringLiteral("revalidating")})) {
    return false;
  }
  return parseBool(object, QStringLiteral("partial"), &output->partial, error,
                   QStringLiteral("$.meta"));
}

bool parseErrors(const QJsonValue &value, QList<Live::ApiError> *output,
                 QString *error) {
  if (!value.isArray()) {
    *error =
        pathError(QStringLiteral("$.errors"), QStringLiteral("expected array"));
    return false;
  }
  const QJsonArray array = value.toArray();
  if (array.size() > 50) {
    *error = pathError(QStringLiteral("$.errors"),
                       QStringLiteral("too many errors"));
    return false;
  }
  static const QSet<QString> codes{
      QStringLiteral("LIVE_INVALID_REQUEST"),
      QStringLiteral("LIVE_CONTRACT_INVALID"),
      QStringLiteral("LIVE_AUTH_REQUIRED"),
      QStringLiteral("LIVE_CSRF_REQUIRED"),
      QStringLiteral("LIVE_CAPABILITY_REQUIRED"),
      QStringLiteral("LIVE_PROVIDER_FORBIDDEN"),
      QStringLiteral("LIVE_PROVIDER_NOT_FOUND"),
      QStringLiteral("LIVE_PROVIDER_UNAVAILABLE"),
      QStringLiteral("LIVE_PROVIDER_TIMEOUT"),
      QStringLiteral("LIVE_ITEM_NOT_FOUND"),
      QStringLiteral("LIVE_STREAM_UNAVAILABLE"),
      QStringLiteral("LIVE_STREAM_EXPIRED"),
      QStringLiteral("LIVE_PROTOCOL_UNSUPPORTED"),
      QStringLiteral("LIVE_EGRESS_REQUIRED"),
      QStringLiteral("LIVE_EGRESS_UNAVAILABLE"),
      QStringLiteral("LIVE_RELAY_CAPACITY"),
      QStringLiteral("LIVE_REMUX_CAPACITY"),
      QStringLiteral("LIVE_RATE_LIMITED"),
      QStringLiteral("LIVE_SESSION_NOT_FOUND"),
      QStringLiteral("LIVE_SESSION_EXPIRED"),
      QStringLiteral("LIVE_SESSION_FORBIDDEN"),
      QStringLiteral("LIVE_SESSION_CONFLICT"),
      QStringLiteral("LIVE_REVISION_CONFLICT"),
      QStringLiteral("LIVE_DESTINATION_RULE_CONFLICT"),
      QStringLiteral("LIVE_IDEMPOTENCY_CONFLICT"),
      QStringLiteral("LIVE_UPSTREAM_REJECTED"),
      QStringLiteral("LIVE_UPSTREAM_AUTH_FAILED"),
      QStringLiteral("LIVE_UPSTREAM_STALLED"),
      QStringLiteral("LIVE_FAILOVER_EXHAUSTED"),
      QStringLiteral("LIVE_CONTROL_LEASE_UNAVAILABLE"),
      QStringLiteral("LIVE_INTERNAL_ERROR"),
  };
  output->clear();
  for (qsizetype index = 0; index < array.size(); ++index) {
    if (!array.at(index).isObject()) {
      *error = pathError(QStringLiteral("$.errors[%1]").arg(index),
                         QStringLiteral("expected object"));
      return false;
    }
    const QJsonObject object = array.at(index).toObject();
    const QString path = QStringLiteral("$.errors[%1]").arg(index);
    Live::ApiError parsed;
    if (!parseEnum(object, QStringLiteral("code"), &parsed.code, error, path,
                   codes) ||
        !parseString(object, QStringLiteral("message"), &parsed.message, error,
                     path, 0, kShortTextMax) ||
        !parseBool(object, QStringLiteral("retryable"), &parsed.retryable,
                   error, path)) {
      return false;
    }
    if (object.contains(QStringLiteral("retryAfterSeconds")) &&
        !object.value(QStringLiteral("retryAfterSeconds")).isNull()) {
      int seconds = 0;
      if (!parseInt(object, QStringLiteral("retryAfterSeconds"), &seconds,
                    error, path) ||
          seconds < 1 || seconds > 3600) {
        *error = pathError(path + QStringLiteral(".retryAfterSeconds"),
                           QStringLiteral("out of range"));
        return false;
      }
      parsed.retryAfterSeconds = seconds;
    }
    if (object.contains(QStringLiteral("providerId")) &&
        !object.value(QStringLiteral("providerId")).isNull() &&
        !parseUuid(object, QStringLiteral("providerId"), &parsed.providerId,
                   error, path)) {
      return false;
    }
    output->append(std::move(parsed));
  }
  return true;
}

bool parseEnvelopeShell(const QJsonDocument &document, QJsonValue *data,
                        Live::ApiMeta *meta, QList<Live::ApiError> *errors,
                        QString *error) {
  if (!document.isObject()) {
    *error = pathError(QStringLiteral("$"),
                       QStringLiteral("expected object envelope"));
    return false;
  }
  const QJsonObject object = document.object();
  if (!object.contains(QStringLiteral("data")) ||
      !object.contains(QStringLiteral("meta")) ||
      !object.contains(QStringLiteral("errors"))) {
    *error = pathError(QStringLiteral("$"),
                       QStringLiteral("missing data, meta, or errors"));
    return false;
  }
  *data = object.value(QStringLiteral("data"));
  return parseMeta(object.value(QStringLiteral("meta")), meta, error) &&
         parseErrors(object.value(QStringLiteral("errors")), errors, error);
}

bool parseArtwork(const QJsonValue &value, std::optional<Live::Artwork> *output,
                  QString *error, const QString &path) {
  if (value.isNull()) {
    output->reset();
    return true;
  }
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object or null"));
    return false;
  }
  const QJsonObject object = value.toObject();
  Live::Artwork parsed;
  if (!parseString(object, QStringLiteral("artworkId"), &parsed.artworkId,
                   error, path, 16, 2048) ||
      !parseString(object, QStringLiteral("url"), &parsed.url, error, path, 1,
                   4096) ||
      !parseEnum(object, QStringLiteral("kind"), &parsed.kind, error, path,
                 {QStringLiteral("poster"), QStringLiteral("background"),
                  QStringLiteral("logo")})) {
    return false;
  }
  static const QRegularExpression opaque(QStringLiteral("^[A-Za-z0-9._~-]+$"));
  if (!opaque.match(parsed.artworkId).hasMatch() ||
      !parsed.url.startsWith(QStringLiteral("/api/v1/live/artwork/"))) {
    *error =
        pathError(path, QStringLiteral("invalid artwork identifier or URL"));
    return false;
  }
  *output = std::move(parsed);
  return true;
}

bool parseFacts(const QJsonValue &value, QList<Live::Fact> *output,
                QString *error, const QString &path) {
  if (!value.isArray() || value.toArray().size() > 20) {
    *error = pathError(path, QStringLiteral("expected bounded array"));
    return false;
  }
  output->clear();
  const QJsonArray array = value.toArray();
  for (qsizetype index = 0; index < array.size(); ++index) {
    if (!array.at(index).isObject()) {
      *error = pathError(QStringLiteral("%1[%2]").arg(path).arg(index),
                         QStringLiteral("expected object"));
      return false;
    }
    const QJsonObject object = array.at(index).toObject();
    const QString itemPath = QStringLiteral("%1[%2]").arg(path).arg(index);
    Live::Fact fact;
    if (!parseString(object, QStringLiteral("label"), &fact.label, error,
                     itemPath, 0, kShortTextMax) ||
        !parseString(object, QStringLiteral("value"), &fact.value, error,
                     itemPath, 0, kShortTextMax)) {
      return false;
    }
    output->append(std::move(fact));
  }
  return true;
}

bool parseItemValue(const QJsonValue &value, Live::Item *output, QString *error,
                    const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  if (!parseUuid(object, QStringLiteral("providerId"), &output->providerId,
                 error, path) ||
      !parseString(object, QStringLiteral("itemKey"), &output->itemKey, error,
                   path, 16, 2048) ||
      !parseEnum(object, QStringLiteral("itemType"), &output->itemType, error,
                 path, {QStringLiteral("event"), QStringLiteral("channel")}) ||
      !parseString(object, QStringLiteral("title"), &output->title, error, path,
                   0, kShortTextMax) ||
      !parseOptionalString(object, QStringLiteral("subtitle"),
                           &output->subtitle, error, path, kShortTextMax) ||
      !parseOptionalString(object, QStringLiteral("description"),
                           &output->description, error, path, 4000) ||
      !parseEnum(object, QStringLiteral("status"), &output->status, error, path,
                 {QStringLiteral("scheduled"), QStringLiteral("live"),
                  QStringLiteral("ended"), QStringLiteral("unavailable"),
                  QStringLiteral("unknown")})) {
    return false;
  }
  static const QRegularExpression opaque(QStringLiteral("^[A-Za-z0-9._~-]+$"));
  if (!opaque.match(output->itemKey).hasMatch()) {
    *error = pathError(path + QStringLiteral(".itemKey"),
                       QStringLiteral("invalid opaque key"));
    return false;
  }
  if (object.contains(QStringLiteral("startsAt")) &&
      !parseUtcDateTimeValue(object.value(QStringLiteral("startsAt")),
                             &output->startsAtUtc, error,
                             path + QStringLiteral(".startsAt"), true)) {
    return false;
  }
  if (object.contains(QStringLiteral("endsAt")) &&
      !parseUtcDateTimeValue(object.value(QStringLiteral("endsAt")),
                             &output->endsAtUtc, error,
                             path + QStringLiteral(".endsAt"), true)) {
    return false;
  }
  if (output->startsAtUtc && output->endsAtUtc &&
      *output->endsAtUtc < *output->startsAtUtc) {
    *error = pathError(path + QStringLiteral(".endsAt"),
                       QStringLiteral("precedes startsAt"));
    return false;
  }
  if (!object.contains(QStringLiteral("poster")) ||
      !parseArtwork(object.value(QStringLiteral("poster")), &output->poster,
                    error, path + QStringLiteral(".poster")) ||
      !object.contains(QStringLiteral("background")) ||
      !parseArtwork(object.value(QStringLiteral("background")),
                    &output->background, error,
                    path + QStringLiteral(".background")) ||
      !object.contains(QStringLiteral("logo")) ||
      !parseArtwork(object.value(QStringLiteral("logo")), &output->logo, error,
                    path + QStringLiteral(".logo")) ||
      !parseStringArray(object, QStringLiteral("categories"),
                        &output->categories, error, path, 0, 20,
                        kShortTextMax) ||
      !parseStringArray(object, QStringLiteral("badges"), &output->badges,
                        error, path, 0, 20, kShortTextMax) ||
      !object.contains(QStringLiteral("facts")) ||
      !parseFacts(object.value(QStringLiteral("facts")), &output->facts, error,
                  path + QStringLiteral(".facts"))) {
    return false;
  }
  return true;
}

bool parseFilter(const QJsonValue &value, Live::FilterDefinition *output,
                 QString *error, const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  if (!parseString(object, QStringLiteral("id"), &output->id, error, path, 1,
                   128) ||
      !parseString(object, QStringLiteral("label"), &output->label, error, path,
                   0, kShortTextMax) ||
      !parseEnum(object, QStringLiteral("type"), &output->type, error, path,
                 {QStringLiteral("toggle"), QStringLiteral("single_select"),
                  QStringLiteral("multi_select"), QStringLiteral("search"),
                  QStringLiteral("date")}) ||
      !parseBool(object, QStringLiteral("required"), &output->required, error,
                 path)) {
    return false;
  }
  static const QRegularExpression idPattern(
      QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._~-]{0,127}$"));
  if (!idPattern.match(output->id).hasMatch()) {
    *error = pathError(path + QStringLiteral(".id"),
                       QStringLiteral("invalid filter id"));
    return false;
  }
  output->defaultValue =
      object.contains(QStringLiteral("default"))
          ? object.value(QStringLiteral("default")).toVariant()
          : QVariant();
  if (!object.contains(QStringLiteral("options")) ||
      !object.value(QStringLiteral("options")).isArray() ||
      object.value(QStringLiteral("options")).toArray().size() > 200) {
    *error = pathError(path + QStringLiteral(".options"),
                       QStringLiteral("expected bounded array"));
    return false;
  }
  output->options.clear();
  const QJsonArray options = object.value(QStringLiteral("options")).toArray();
  for (qsizetype index = 0; index < options.size(); ++index) {
    if (!options.at(index).isObject()) {
      *error = pathError(QStringLiteral("%1.options[%2]").arg(path).arg(index),
                         QStringLiteral("expected object"));
      return false;
    }
    const QJsonObject optionObject = options.at(index).toObject();
    const QString optionPath =
        QStringLiteral("%1.options[%2]").arg(path).arg(index);
    Live::FilterOption option;
    if (!parseString(optionObject, QStringLiteral("value"), &option.value,
                     error, optionPath, 1, 512) ||
        !parseString(optionObject, QStringLiteral("label"), &option.label,
                     error, optionPath, 0, kShortTextMax)) {
      return false;
    }
    output->options.append(std::move(option));
  }
  return true;
}

bool parseCatalogValue(const QJsonValue &value, Live::Catalog *output,
                       QString *error, const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  if (!parseUuid(object, QStringLiteral("providerId"), &output->providerId,
                 error, path) ||
      !parseString(object, QStringLiteral("catalogId"), &output->catalogId,
                   error, path, 1, 128) ||
      !parseString(object, QStringLiteral("name"), &output->name, error, path,
                   0, kShortTextMax) ||
      !parseOptionalString(object, QStringLiteral("description"),
                           &output->description, error, path, 4000) ||
      !parseStringArray(object, QStringLiteral("itemTypes"), &output->itemTypes,
                        error, path, 1, 2, 16,
                        {QStringLiteral("event"), QStringLiteral("channel")}) ||
      !parseEnum(object, QStringLiteral("presentation"), &output->presentation,
                 error, path,
                 {QStringLiteral("landscape"), QStringLiteral("poster"),
                  QStringLiteral("compact_list")}) ||
      !parseInt(object, QStringLiteral("order"), &output->order, error, path)) {
    return false;
  }
  static const QRegularExpression idPattern(
      QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._~-]{0,127}$"));
  if (!idPattern.match(output->catalogId).hasMatch()) {
    *error = pathError(path + QStringLiteral(".catalogId"),
                       QStringLiteral("invalid catalog id"));
    return false;
  }
  if (!object.contains(QStringLiteral("filters")) ||
      !object.value(QStringLiteral("filters")).isArray() ||
      object.value(QStringLiteral("filters")).toArray().size() > 12) {
    *error = pathError(path + QStringLiteral(".filters"),
                       QStringLiteral("expected bounded array"));
    return false;
  }
  QSet<QString> ids;
  output->filters.clear();
  const QJsonArray filters = object.value(QStringLiteral("filters")).toArray();
  for (qsizetype index = 0; index < filters.size(); ++index) {
    Live::FilterDefinition filter;
    const QString filterPath =
        QStringLiteral("%1.filters[%2]").arg(path).arg(index);
    if (!parseFilter(filters.at(index), &filter, error, filterPath) ||
        ids.contains(filter.id)) {
      if (ids.contains(filter.id)) {
        *error = pathError(filterPath + QStringLiteral(".id"),
                           QStringLiteral("duplicate filter id"));
      }
      return false;
    }
    ids.insert(filter.id);
    output->filters.append(std::move(filter));
  }
  return true;
}

bool parseStream(const QJsonValue &value, Live::StreamChoice *output,
                 QString *error, const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  if (!parseString(object, QStringLiteral("streamOptionKey"),
                   &output->streamOptionKey, error, path, 16, 2048) ||
      !parseString(object, QStringLiteral("label"), &output->label, error, path,
                   0, kShortTextMax) ||
      !parseOptionalString(object, QStringLiteral("quality"), &output->quality,
                           error, path, 256) ||
      !parseOptionalString(object, QStringLiteral("language"),
                           &output->language, error, path, 64) ||
      !parseInt(object, QStringLiteral("priority"), &output->priority, error,
                path)) {
    return false;
  }
  if (object.contains(QStringLiteral("protocolHint")) &&
      !parseEnum(object, QStringLiteral("protocolHint"), &output->protocolHint,
                 error, path,
                 {QStringLiteral("hls"), QStringLiteral("dash"),
                  QStringLiteral("http_progressive"), QStringLiteral("mpeg_ts"),
                  QStringLiteral("rtmp"), QStringLiteral("srt")},
                 true)) {
    return false;
  }
  static const QRegularExpression opaque(QStringLiteral("^[A-Za-z0-9._~-]+$"));
  if (!opaque.match(output->streamOptionKey).hasMatch()) {
    *error = pathError(path + QStringLiteral(".streamOptionKey"),
                       QStringLiteral("invalid opaque key"));
    return false;
  }
  return true;
}

bool parseSelectedSource(const QJsonValue &value, Live::SelectedSource *output,
                         QString *error, const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  static const QSet<QString> keys{QStringLiteral("sourceKey"),
                                  QStringLiteral("label"),
                                  QStringLiteral("quality")};
  if (!rejectUnknownKeys(object, keys, error, path)) {
    return false;
  }
  static const QRegularExpression opaque(
      QStringLiteral("^[A-Za-z0-9._~-]{16,4096}$"));
  if (!parseString(object, QStringLiteral("sourceKey"), &output->sourceKey,
                   error, path, 16, 4096) ||
      !parseString(object, QStringLiteral("label"), &output->label, error, path,
                   0, kShortTextMax) ||
      !object.contains(QStringLiteral("quality")) ||
      !parseOptionalString(object, QStringLiteral("quality"), &output->quality,
                           error, path, kShortTextMax) ||
      !opaque.match(output->sourceKey).hasMatch()) {
    if (error->isEmpty()) {
      *error = pathError(path + QStringLiteral(".sourceKey"),
                         QStringLiteral("invalid opaque source key"));
    }
    return false;
  }
  return true;
}

bool parseAvailableSources(const QJsonValue &value,
                           const Live::SelectedSource &selected,
                           QList<Live::SelectedSource> *output,
                           QString *error, const QString &path) {
  if (!value.isArray() || value.toArray().isEmpty() ||
      value.toArray().size() > 8) {
    *error = pathError(path, QStringLiteral("expected 1-8 sources"));
    return false;
  }
  QSet<QString> keys;
  int selectedMatches = 0;
  const QJsonArray values = value.toArray();
  for (qsizetype index = 0; index < values.size(); ++index) {
    Live::SelectedSource source;
    const QString sourcePath = path + QStringLiteral("[%1]").arg(index);
    if (!parseSelectedSource(values.at(index), &source, error, sourcePath) ||
        keys.contains(source.sourceKey)) {
      if (keys.contains(source.sourceKey)) {
        *error = pathError(sourcePath + QStringLiteral(".sourceKey"),
                           QStringLiteral("duplicate source key"));
      }
      return false;
    }
    keys.insert(source.sourceKey);
    if (source.sourceKey == selected.sourceKey && source.label == selected.label &&
        source.quality == selected.quality) {
      ++selectedMatches;
    }
    output->append(std::move(source));
  }
  if (selectedMatches != 1) {
    *error = pathError(path,
                       QStringLiteral("selected source is not in source list"));
    return false;
  }
  return true;
}

bool parseTrackSelection(const QJsonValue &value,
                         std::optional<Live::TrackSelection> *output,
                         QString *error, const QString &path) {
  if (value.isNull()) {
    output->reset();
    return true;
  }
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object or null"));
    return false;
  }
  const QJsonObject object = value.toObject();
  static const QSet<QString> keys{QStringLiteral("trackId"),
                                  QStringLiteral("language"),
                                  QStringLiteral("title")};
  if (!rejectUnknownKeys(object, keys, error, path)) {
    return false;
  }
  Live::TrackSelection selection;
  if (!parseString(object, QStringLiteral("trackId"), &selection.trackId,
                   error, path, 1, 256) ||
      !object.contains(QStringLiteral("language")) ||
      !parseOptionalString(object, QStringLiteral("language"),
                           &selection.language, error, path, 64) ||
      !object.contains(QStringLiteral("title")) ||
      !parseOptionalString(object, QStringLiteral("title"), &selection.title,
                           error, path, 256)) {
    return false;
  }
  *output = std::move(selection);
  return true;
}

bool parseTrackPreferences(const QJsonValue &value,
                           Live::TrackPreferences *output, QString *error,
                           const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  static const QSet<QString> keys{QStringLiteral("audio"),
                                  QStringLiteral("subtitle")};
  return rejectUnknownKeys(object, keys, error, path) &&
         object.contains(QStringLiteral("audio")) &&
         parseTrackSelection(object.value(QStringLiteral("audio")),
                             &output->audio, error,
                             path + QStringLiteral(".audio")) &&
         object.contains(QStringLiteral("subtitle")) &&
         parseTrackSelection(object.value(QStringLiteral("subtitle")),
                             &output->subtitle, error,
                             path + QStringLiteral(".subtitle"));
}

bool parseLiveWindow(const QJsonValue &value, Live::LiveWindow *output,
                     QString *error, const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  static const QSet<QString> keys{QStringLiteral("seekable"),
                                  QStringLiteral("windowSeconds"),
                                  QStringLiteral("targetLatencySeconds")};
  if (!rejectUnknownKeys(object, keys, error, path)) {
    return false;
  }
  if (!object.contains(QStringLiteral("windowSeconds")) ||
      !object.contains(QStringLiteral("targetLatencySeconds"))) {
    *error = pathError(path, QStringLiteral("missing live window field"));
    return false;
  }
  if (!parseBool(object, QStringLiteral("seekable"), &output->seekable, error,
                 path)) {
    return false;
  }
  if (object.contains(QStringLiteral("windowSeconds")) &&
      !object.value(QStringLiteral("windowSeconds")).isNull()) {
    int seconds = 0;
    if (!parseInt(object, QStringLiteral("windowSeconds"), &seconds, error,
                  path) ||
        seconds < 1 || seconds > 86'400) {
      *error = pathError(path + QStringLiteral(".windowSeconds"),
                         QStringLiteral("out of range"));
      return false;
    }
    output->windowSeconds = seconds;
  }
  if (object.contains(QStringLiteral("targetLatencySeconds")) &&
      !object.value(QStringLiteral("targetLatencySeconds")).isNull()) {
    const QJsonValue latency =
        object.value(QStringLiteral("targetLatencySeconds"));
    const double seconds = latency.toDouble(-1.0);
    if (!latency.isDouble() || !std::isfinite(seconds) || seconds < 0.0 ||
        seconds > 300.0) {
      *error = pathError(path + QStringLiteral(".targetLatencySeconds"),
                         QStringLiteral("out of range"));
      return false;
    }
    output->targetLatencySeconds = seconds;
  }
  return true;
}

bool parseSessionEgress(const QJsonValue &value, Live::SessionEgress *output,
                        QString *error, const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  static const QSet<QString> keys{QStringLiteral("mode"),
                                  QStringLiteral("fallbackReason")};
  if (!rejectUnknownKeys(object, keys, error, path) ||
      !parseEnum(object, QStringLiteral("mode"), &output->mode, error, path,
                 {QStringLiteral("server_default"),
                  QStringLiteral("protected"),
                  QStringLiteral("direct_fallback")}) ||
      !object.contains(QStringLiteral("fallbackReason")) ||
      !parseOptionalString(object, QStringLiteral("fallbackReason"),
                           &output->fallbackReason, error, path, 64)) {
    return false;
  }
  const bool fallback = output->mode == QStringLiteral("direct_fallback");
  if (fallback !=
      (output->fallbackReason ==
       QStringLiteral("protected_egress_unavailable"))) {
    *error = pathError(path, QStringLiteral("inconsistent egress outcome"));
    return false;
  }
  return true;
}

bool parseRequiredUtc(const QJsonObject &object, const QString &key,
                      QDateTime *output, QString *error, const QString &path) {
  std::optional<QDateTime> parsed;
  if (!object.contains(key) ||
      !parseUtcDateTimeValue(object.value(key), &parsed, error,
                             path + '.' + key, false)) {
    return false;
  }
  *output = *parsed;
  return true;
}

bool parseSessionDetailValue(const QJsonValue &value,
                             Live::SessionDetail *output, QString *error,
                             const QString &path) {
  if (!value.isObject()) {
    *error = pathError(path, QStringLiteral("expected object"));
    return false;
  }
  const QJsonObject object = value.toObject();
  static const QSet<QString> keys{
      QStringLiteral("sessionId"), QStringLiteral("revision"),
      QStringLiteral("state"),     QStringLiteral("deliveryMode"),
      QStringLiteral("protocol"),  QStringLiteral("selectedSource"),
      QStringLiteral("availableSources"),
      QStringLiteral("trackPreferences"), QStringLiteral("expiresAt"),
      QStringLiteral("hardExpiresAt"), QStringLiteral("errorCode"),
      QStringLiteral("timeline")};
  if (!rejectUnknownKeys(object, keys, error, path)) {
    return false;
  }
  if (!parseUuid(object, QStringLiteral("sessionId"), &output->sessionId, error,
                 path) ||
      !parsePositiveInt64(object, QStringLiteral("revision"), &output->revision,
                          error, path) ||
      !parseEnum(object, QStringLiteral("state"), &output->state, error, path,
                 {QStringLiteral("resolving"), QStringLiteral("planning"),
                  QStringLiteral("provisioning_egress"),
                  QStringLiteral("starting_remux"), QStringLiteral("ready"),
                  QStringLiteral("playing"), QStringLiteral("reconnecting"),
                  QStringLiteral("refreshing"), QStringLiteral("failing_over"),
                  QStringLiteral("ended"), QStringLiteral("expired"),
                  QStringLiteral("failed")}) ||
      !parseEnum(object, QStringLiteral("deliveryMode"), &output->deliveryMode,
                 error, path,
                 {QStringLiteral("client_direct"),
                  QStringLiteral("server_relay"),
                  QStringLiteral("server_remux")}) ||
      !parseEnum(object, QStringLiteral("protocol"), &output->protocol, error,
                 path,
                 {QStringLiteral("hls"), QStringLiteral("dash"),
                  QStringLiteral("http_progressive"), QStringLiteral("mpeg_ts"),
                  QStringLiteral("rtmp"), QStringLiteral("srt")}) ||
      !parseSelectedSource(object.value(QStringLiteral("selectedSource")),
                           &output->selectedSource, error,
                           path + QStringLiteral(".selectedSource")) ||
      !parseAvailableSources(object.value(QStringLiteral("availableSources")),
                             output->selectedSource,
                             &output->availableSources, error,
                             path + QStringLiteral(".availableSources")) ||
      !parseTrackPreferences(object.value(QStringLiteral("trackPreferences")),
                             &output->trackPreferences, error,
                             path + QStringLiteral(".trackPreferences")) ||
      !parseRequiredUtc(object, QStringLiteral("expiresAt"),
                        &output->expiresAtUtc, error, path) ||
      !parseRequiredUtc(object, QStringLiteral("hardExpiresAt"),
                        &output->hardExpiresAtUtc, error, path) ||
      !object.contains(QStringLiteral("errorCode")) ||
      !parseOptionalString(object, QStringLiteral("errorCode"),
                           &output->errorCode, error, path, 128) ||
      !object.contains(QStringLiteral("timeline")) ||
      !object.value(QStringLiteral("timeline")).isArray() ||
      object.value(QStringLiteral("timeline")).toArray().size() > 100) {
    if (error->isEmpty()) {
      *error = pathError(path + QStringLiteral(".timeline"),
                         QStringLiteral("expected bounded array"));
    }
    return false;
  }
  if (output->expiresAtUtc > output->hardExpiresAtUtc) {
    *error = pathError(path + QStringLiteral(".expiresAt"),
                       QStringLiteral("exceeds hard expiration"));
    return false;
  }
  const QJsonArray timeline =
      object.value(QStringLiteral("timeline")).toArray();
  if (timeline.isEmpty()) {
    *error = pathError(path + QStringLiteral(".timeline"),
                       QStringLiteral("expected non-empty array"));
    return false;
  }
  static const QSet<QString> timelineKeys{
      QStringLiteral("at"), QStringLiteral("revision"), QStringLiteral("state"),
      QStringLiteral("reason")};
  for (qsizetype index = 0; index < timeline.size(); ++index) {
    if (!timeline.at(index).isObject()) {
      *error = pathError(QStringLiteral("%1.timeline[%2]").arg(path).arg(index),
                         QStringLiteral("expected object"));
      return false;
    }
    const QJsonObject entry = timeline.at(index).toObject();
    const QString entryPath =
        QStringLiteral("%1.timeline[%2]").arg(path).arg(index);
    qint64 revision = 0;
    QString state;
    QString reason;
    std::optional<QDateTime> at;
    if (!rejectUnknownKeys(entry, timelineKeys, error, entryPath) ||
        !parsePositiveInt64(entry, QStringLiteral("revision"), &revision, error,
                            entryPath) ||
        revision > output->revision ||
        !parseEnum(entry, QStringLiteral("state"), &state, error, entryPath,
                   {QStringLiteral("resolving"), QStringLiteral("planning"),
                    QStringLiteral("provisioning_egress"),
                    QStringLiteral("starting_remux"), QStringLiteral("ready"),
                    QStringLiteral("playing"), QStringLiteral("reconnecting"),
                    QStringLiteral("refreshing"),
                    QStringLiteral("failing_over"), QStringLiteral("ended"),
                    QStringLiteral("expired"), QStringLiteral("failed")}) ||
        !entry.contains(QStringLiteral("reason")) ||
        !parseOptionalString(entry, QStringLiteral("reason"), &reason, error,
                             entryPath, 128) ||
        !entry.contains(QStringLiteral("at")) ||
        !parseUtcDateTimeValue(entry.value(QStringLiteral("at")), &at, error,
                               entryPath + QStringLiteral(".at"), false)) {
      if (revision > output->revision && error->isEmpty()) {
        *error = pathError(entryPath + QStringLiteral(".revision"),
                           QStringLiteral("exceeds session revision"));
      }
      return false;
    }
  }
  return true;
}

template <typename T, typename Parser>
bool parseArrayData(const QJsonValue &data, QList<T> *output, QString *error,
                    int maximum, Parser parser) {
  if (!data.isArray() || data.toArray().size() > maximum) {
    *error = pathError(QStringLiteral("$.data"),
                       QStringLiteral("expected bounded array"));
    return false;
  }
  output->clear();
  const QJsonArray array = data.toArray();
  for (qsizetype index = 0; index < array.size(); ++index) {
    T item;
    if (!parser(array.at(index), &item, error,
                QStringLiteral("$.data[%1]").arg(index))) {
      return false;
    }
    output->append(std::move(item));
  }
  return true;
}

} // namespace

namespace Live {

QVariantMap ApiError::toVariantMap() const {
  QVariantMap result{{QStringLiteral("code"), code},
                     {QStringLiteral("message"), message},
                     {QStringLiteral("retryable"), retryable}};
  if (retryAfterSeconds) {
    result.insert(QStringLiteral("retryAfterSeconds"), *retryAfterSeconds);
  }
  if (!providerId.isEmpty()) {
    result.insert(QStringLiteral("providerId"), providerId);
  }
  return result;
}

QVariantMap ApiMeta::toVariantMap() const {
  return {
      {QStringLiteral("requestId"), requestId},
      {QStringLiteral("generatedAt"), generatedAtUtc},
      {QStringLiteral("cacheState"), cacheState},
      {QStringLiteral("partial"), partial},
  };
}

QVariantMap Provider::toVariantMap() const {
  return {
      {QStringLiteral("providerId"), providerId},
      {QStringLiteral("extensionId"), extensionId},
      {QStringLiteral("name"), name},
      {QStringLiteral("readiness"), readiness},
      {QStringLiteral("disabledReason"), disabledReason},
      {QStringLiteral("contractVersion"), contractVersion},
      {QStringLiteral("itemTypes"), itemTypes},
      {QStringLiteral("protocols"), protocols},
  };
}

QVariantMap FilterOption::toVariantMap() const {
  return {{QStringLiteral("value"), value}, {QStringLiteral("label"), label}};
}

QVariantMap FilterDefinition::toVariantMap() const {
  QVariantList converted;
  converted.reserve(options.size());
  for (const FilterOption &option : options) {
    converted.append(option.toVariantMap());
  }
  return {
      {QStringLiteral("id"), id},
      {QStringLiteral("label"), label},
      {QStringLiteral("type"), type},
      {QStringLiteral("required"), required},
      {QStringLiteral("default"), defaultValue},
      {QStringLiteral("options"), converted},
  };
}

QVariantMap Catalog::toVariantMap() const {
  QVariantList converted;
  converted.reserve(filters.size());
  for (const FilterDefinition &filter : filters) {
    converted.append(filter.toVariantMap());
  }
  return {
      {QStringLiteral("providerId"), providerId},
      {QStringLiteral("catalogId"), catalogId},
      {QStringLiteral("name"), name},
      {QStringLiteral("description"), description},
      {QStringLiteral("itemTypes"), itemTypes},
      {QStringLiteral("presentation"), presentation},
      {QStringLiteral("order"), order},
      {QStringLiteral("filters"), converted},
  };
}

QVariantMap Artwork::toVariantMap() const {
  return {{QStringLiteral("artworkId"), artworkId},
          {QStringLiteral("url"), url},
          {QStringLiteral("kind"), kind}};
}

QVariantMap Fact::toVariantMap() const {
  return {{QStringLiteral("label"), label}, {QStringLiteral("value"), value}};
}

QVariantMap Item::toVariantMap() const {
  QVariantList factValues;
  factValues.reserve(facts.size());
  for (const Fact &fact : facts) {
    factValues.append(fact.toVariantMap());
  }
  return {
      {QStringLiteral("providerId"), providerId},
      {QStringLiteral("itemKey"), itemKey},
      {QStringLiteral("itemType"), itemType},
      {QStringLiteral("title"), title},
      {QStringLiteral("subtitle"), subtitle},
      {QStringLiteral("description"), description},
      {QStringLiteral("status"), status},
      {QStringLiteral("startsAt"),
       startsAtUtc ? QVariant(*startsAtUtc) : QVariant()},
      {QStringLiteral("endsAt"), endsAtUtc ? QVariant(*endsAtUtc) : QVariant()},
      {QStringLiteral("poster"),
       poster ? QVariant(poster->toVariantMap()) : QVariant()},
      {QStringLiteral("background"),
       background ? QVariant(background->toVariantMap()) : QVariant()},
      {QStringLiteral("logo"),
       logo ? QVariant(logo->toVariantMap()) : QVariant()},
      {QStringLiteral("categories"), categories},
      {QStringLiteral("badges"), badges},
      {QStringLiteral("facts"), factValues},
  };
}

QVariantMap StreamChoice::toVariantMap() const {
  return {
      {QStringLiteral("streamOptionKey"), streamOptionKey},
      {QStringLiteral("label"), label},
      {QStringLiteral("quality"), quality},
      {QStringLiteral("language"), language},
      {QStringLiteral("protocolHint"), protocolHint},
      {QStringLiteral("priority"), priority},
  };
}

QVariantMap SelectedSource::toVariantMap() const {
  return {{QStringLiteral("sourceKey"), sourceKey},
          {QStringLiteral("label"), label},
          {QStringLiteral("quality"), quality}};
}

QVariantMap TrackSelection::toVariantMap() const {
  return {{QStringLiteral("trackId"), trackId},
          {QStringLiteral("language"), language},
          {QStringLiteral("title"), title}};
}

QVariantMap TrackPreferences::toVariantMap() const {
  return {{QStringLiteral("audio"),
           audio ? QVariant(audio->toVariantMap()) : QVariant()},
          {QStringLiteral("subtitle"),
           subtitle ? QVariant(subtitle->toVariantMap()) : QVariant()}};
}

QVariantMap LiveWindow::toVariantMap() const {
  return {
      {QStringLiteral("seekable"), seekable},
      {QStringLiteral("windowSeconds"),
       windowSeconds ? QVariant(*windowSeconds) : QVariant()},
      {QStringLiteral("targetLatencySeconds"),
       targetLatencySeconds ? QVariant(*targetLatencySeconds) : QVariant()}};
}

QVariantMap SessionEgress::toVariantMap() const {
  return {{QStringLiteral("mode"), mode},
          {QStringLiteral("fallbackReason"), fallbackReason}};
}

QVariantMap SessionCreated::toVariantMap() const {
  QVariantList sources;
  sources.reserve(availableSources.size());
  for (const SelectedSource &source : availableSources) {
    sources.append(source.toVariantMap());
  }
  return {
      {QStringLiteral("sessionId"), sessionId},
      {QStringLiteral("revision"), revision},
      {QStringLiteral("tokenRevision"),
       tokenRevision ? QVariant(*tokenRevision) : QVariant()},
      {QStringLiteral("deliveryMode"), deliveryMode},
      {QStringLiteral("decisionReason"), decisionReason},
      {QStringLiteral("egress"), egress.toVariantMap()},
      {QStringLiteral("playbackUrl"), playbackUrl},
      {QStringLiteral("expiresAt"), expiresAtUtc},
      {QStringLiteral("hardExpiresAt"), hardExpiresAtUtc},
      {QStringLiteral("heartbeatIntervalSeconds"), heartbeatIntervalSeconds},
      {QStringLiteral("live"), live.toVariantMap()},
      {QStringLiteral("selectedSource"), selectedSource.toVariantMap()},
      {QStringLiteral("availableSources"), sources},
      {QStringLiteral("trackPreferences"), trackPreferences.toVariantMap()}};
}

QVariantMap SessionDetail::toVariantMap() const {
  QVariantList sources;
  sources.reserve(availableSources.size());
  for (const SelectedSource &source : availableSources) {
    sources.append(source.toVariantMap());
  }
  return {{QStringLiteral("sessionId"), sessionId},
          {QStringLiteral("revision"), revision},
          {QStringLiteral("state"), state},
          {QStringLiteral("deliveryMode"), deliveryMode},
          {QStringLiteral("protocol"), protocol},
          {QStringLiteral("selectedSource"), selectedSource.toVariantMap()},
          {QStringLiteral("availableSources"), sources},
          {QStringLiteral("trackPreferences"),
           trackPreferences.toVariantMap()},
          {QStringLiteral("expiresAt"), expiresAtUtc},
          {QStringLiteral("hardExpiresAt"), hardExpiresAtUtc},
          {QStringLiteral("errorCode"), errorCode}};
}

ParseResult<ProvidersEnvelope> parseProviders(const QJsonDocument &document) {
  ProvidersEnvelope envelope;
  QJsonValue data;
  QString error;
  if (!parseEnvelopeShell(document, &data, &envelope.meta, &envelope.errors,
                          &error) ||
      !parseArrayData<Provider>(
          data, &envelope.data, &error, 500,
          [](const QJsonValue &value, Provider *provider, QString *parseError,
             const QString &path) {
            if (!value.isObject()) {
              *parseError = pathError(path, QStringLiteral("expected object"));
              return false;
            }
            const QJsonObject object = value.toObject();
            if (!parseUuid(object, QStringLiteral("providerId"),
                           &provider->providerId, parseError, path) ||
                !parseOptionalString(object, QStringLiteral("extensionId"),
                                     &provider->extensionId, parseError, path,
                                     256) ||
                !parseString(object, QStringLiteral("name"), &provider->name,
                             parseError, path, 0, kShortTextMax) ||
                !parseEnum(object, QStringLiteral("readiness"),
                           &provider->readiness, parseError, path,
                           {QStringLiteral("ready"), QStringLiteral("degraded"),
                            QStringLiteral("unavailable"),
                            QStringLiteral("disabled")}) ||
                !parseOptionalString(object, QStringLiteral("disabledReason"),
                                     &provider->disabledReason, parseError,
                                     path, 256) ||
                !parseInt(object, QStringLiteral("contractVersion"),
                          &provider->contractVersion, parseError, path) ||
                provider->contractVersion != 1 ||
                !parseStringArray(
                    object, QStringLiteral("itemTypes"), &provider->itemTypes,
                    parseError, path, 1, 2, 16,
                    {QStringLiteral("event"), QStringLiteral("channel")}) ||
                !parseStringArray(
                    object, QStringLiteral("protocols"), &provider->protocols,
                    parseError, path, 0, 6, 32,
                    {QStringLiteral("hls"), QStringLiteral("dash"),
                     QStringLiteral("http_progressive"),
                     QStringLiteral("mpeg_ts"), QStringLiteral("rtmp"),
                     QStringLiteral("srt")})) {
              if (provider->contractVersion != 1 && parseError->isEmpty()) {
                *parseError =
                    pathError(path + QStringLiteral(".contractVersion"),
                              QStringLiteral("unsupported contract version"));
              }
              return false;
            }
            return true;
          })) {
    return {{}, error};
  }
  return {std::move(envelope), {}};
}

ParseResult<CatalogsEnvelope> parseCatalogs(const QJsonDocument &document) {
  CatalogsEnvelope envelope;
  QJsonValue data;
  QString error;
  if (!parseEnvelopeShell(document, &data, &envelope.meta, &envelope.errors,
                          &error) ||
      !parseArrayData<Catalog>(data, &envelope.data, &error, 1000,
                               parseCatalogValue)) {
    return {{}, error};
  }
  return {std::move(envelope), {}};
}

ParseResult<CatalogPageEnvelope>
parseCatalogPage(const QJsonDocument &document) {
  CatalogPageEnvelope envelope;
  QJsonValue data;
  QString error;
  if (!parseEnvelopeShell(document, &data, &envelope.meta, &envelope.errors,
                          &error)) {
    return {{}, error};
  }
  if (!data.isObject()) {
    return {
        {},
        pathError(QStringLiteral("$.data"), QStringLiteral("expected object"))};
  }
  const QJsonObject object = data.toObject();
  if (!parseUuid(object, QStringLiteral("providerId"), &envelope.providerId,
                 &error, QStringLiteral("$.data")) ||
      !parseString(object, QStringLiteral("catalogId"), &envelope.catalogId,
                   &error, QStringLiteral("$.data"), 1, 128) ||
      !object.contains(QStringLiteral("nextCursor")) ||
      !parseString(object, QStringLiteral("nextCursor"), &envelope.nextCursor,
                   &error, QStringLiteral("$.data"), 0, 2048, true) ||
      !object.contains(QStringLiteral("items")) ||
      !parseArrayData<Item>(object.value(QStringLiteral("items")),
                            &envelope.items, &error, 100, parseItemValue)) {
    return {{}, error};
  }
  for (const Item &item : envelope.items) {
    if (item.providerId != envelope.providerId) {
      return {{},
              pathError(QStringLiteral("$.data.items"),
                        QStringLiteral("provider id mismatch"))};
    }
  }
  return {std::move(envelope), {}};
}

ParseResult<ItemEnvelope> parseItem(const QJsonDocument &document) {
  ItemEnvelope envelope;
  QJsonValue data;
  QString error;
  if (!parseEnvelopeShell(document, &data, &envelope.meta, &envelope.errors,
                          &error)) {
    return {{}, error};
  }
  if (!data.isObject()) {
    return {
        {},
        pathError(QStringLiteral("$.data"), QStringLiteral("expected object"))};
  }
  const QJsonObject object = data.toObject();
  if (!object.contains(QStringLiteral("item")) ||
      !parseItemValue(object.value(QStringLiteral("item")), &envelope.item,
                      &error, QStringLiteral("$.data.item")) ||
      !object.contains(QStringLiteral("streams")) ||
      !object.value(QStringLiteral("streams")).isArray() ||
      object.value(QStringLiteral("streams")).toArray().size() > 20) {
    if (error.isEmpty()) {
      error = pathError(QStringLiteral("$.data.streams"),
                        QStringLiteral("expected bounded array"));
    }
    return {{}, error};
  }
  const QJsonArray streams = object.value(QStringLiteral("streams")).toArray();
  QSet<QString> keys;
  for (qsizetype index = 0; index < streams.size(); ++index) {
    StreamChoice stream;
    const QString path = QStringLiteral("$.data.streams[%1]").arg(index);
    if (!parseStream(streams.at(index), &stream, &error, path) ||
        keys.contains(stream.streamOptionKey)) {
      if (keys.contains(stream.streamOptionKey)) {
        error = pathError(path + QStringLiteral(".streamOptionKey"),
                          QStringLiteral("duplicate stream key"));
      }
      return {{}, error};
    }
    keys.insert(stream.streamOptionKey);
    envelope.streams.append(std::move(stream));
  }
  return {std::move(envelope), {}};
}

ParseResult<SessionCreated> parseSessionCreated(const QJsonDocument &document) {
  if (!document.isObject()) {
    return {{},
            pathError(QStringLiteral("$"), QStringLiteral("expected object"))};
  }
  const QJsonObject object = document.object();
  static const QSet<QString> keys{QStringLiteral("sessionId"),
                                  QStringLiteral("revision"),
                                  QStringLiteral("tokenRevision"),
                                  QStringLiteral("deliveryMode"),
                                  QStringLiteral("decisionReason"),
                                  QStringLiteral("egress"),
                                  QStringLiteral("playbackUrl"),
                                  QStringLiteral("sessionToken"),
                                  QStringLiteral("expiresAt"),
                                  QStringLiteral("hardExpiresAt"),
                                  QStringLiteral("heartbeatIntervalSeconds"),
                                  QStringLiteral("live"),
                                  QStringLiteral("selectedSource"),
                                  QStringLiteral("availableSources"),
                                  QStringLiteral("trackPreferences")};
  SessionCreated session;
  QString error;
  if (!rejectUnknownKeys(object, keys, &error, QStringLiteral("$"))) {
    return {{}, error};
  }
  qint64 tokenRevision = 0;
  if (!parseUuid(object, QStringLiteral("sessionId"), &session.sessionId,
                 &error, QStringLiteral("$")) ||
      !parsePositiveInt64(object, QStringLiteral("revision"), &session.revision,
                          &error, QStringLiteral("$")) ||
      !parseEnum(object, QStringLiteral("deliveryMode"), &session.deliveryMode,
                 &error, QStringLiteral("$"),
                 {QStringLiteral("client_direct"),
                  QStringLiteral("server_relay"),
                  QStringLiteral("server_remux")}) ||
      !parseString(object, QStringLiteral("decisionReason"),
                   &session.decisionReason, &error, QStringLiteral("$"), 1,
                   128) ||
      !parseSessionEgress(object.value(QStringLiteral("egress")),
                          &session.egress, &error,
                          QStringLiteral("$.egress")) ||
      !parseString(object, QStringLiteral("playbackUrl"), &session.playbackUrl,
                   &error, QStringLiteral("$"), 1, 8192) ||
      !parseRequiredUtc(object, QStringLiteral("expiresAt"),
                        &session.expiresAtUtc, &error, QStringLiteral("$")) ||
      !parseRequiredUtc(object, QStringLiteral("hardExpiresAt"),
                        &session.hardExpiresAtUtc, &error,
                        QStringLiteral("$")) ||
      !parseInt(object, QStringLiteral("heartbeatIntervalSeconds"),
                &session.heartbeatIntervalSeconds, &error,
                QStringLiteral("$")) ||
      session.heartbeatIntervalSeconds < 5 ||
      session.heartbeatIntervalSeconds > 300 ||
      !parseLiveWindow(object.value(QStringLiteral("live")), &session.live,
                       &error, QStringLiteral("$.live")) ||
      !parseSelectedSource(object.value(QStringLiteral("selectedSource")),
                           &session.selectedSource, &error,
                           QStringLiteral("$.selectedSource")) ||
      !parseAvailableSources(
          object.value(QStringLiteral("availableSources")),
          session.selectedSource, &session.availableSources, &error,
          QStringLiteral("$.availableSources")) ||
      !parseTrackPreferences(
          object.value(QStringLiteral("trackPreferences")),
          &session.trackPreferences, &error,
          QStringLiteral("$.trackPreferences"))) {
    return {{},
            error.isEmpty() ? QStringLiteral("invalid session response")
                            : error};
  }
  if (object.contains(QStringLiteral("tokenRevision"))) {
    if (!parsePositiveInt64(object, QStringLiteral("tokenRevision"),
                            &tokenRevision, &error, QStringLiteral("$"))) {
      return {{}, error};
    }
    session.tokenRevision = tokenRevision;
  }
  if (object.contains(QStringLiteral("sessionToken"))) {
    QString token;
    if (!parseString(object, QStringLiteral("sessionToken"), &token, &error,
                     QStringLiteral("$"), 16, 2048)) {
      return {{}, error};
    }
    session.sessionToken = token.toUtf8();
  }
  const bool direct = session.deliveryMode == QStringLiteral("client_direct");
  if ((direct && (!session.sessionToken.isEmpty() || session.tokenRevision)) ||
      (!direct && (session.sessionToken.isEmpty() || !session.tokenRevision)) ||
      (direct && session.egress.mode != QStringLiteral("server_default")) ||
      session.expiresAtUtc > session.hardExpiresAtUtc) {
    return {{},
            pathError(QStringLiteral("$"),
                      QStringLiteral("inconsistent session delivery"))};
  }
  return {std::move(session), {}};
}

ParseResult<SessionDetailEnvelope>
parseSessionDetail(const QJsonDocument &document) {
  SessionDetailEnvelope envelope;
  QJsonValue data;
  QString error;
  static const QSet<QString> keys{
      QStringLiteral("data"), QStringLiteral("meta"), QStringLiteral("errors")};
  if (!document.isObject() ||
      !rejectUnknownKeys(document.object(), keys, &error,
                         QStringLiteral("$")) ||
      !parseEnvelopeShell(document, &data, &envelope.meta, &envelope.errors,
                          &error) ||
      !parseSessionDetailValue(data, &envelope.data, &error,
                               QStringLiteral("$.data"))) {
    return {{}, error};
  }
  return {std::move(envelope), {}};
}

ParseResult<ErrorEnvelope> parseError(const QJsonDocument &document) {
  ErrorEnvelope envelope;
  QJsonValue data;
  QString error;
  if (!parseEnvelopeShell(document, &data, &envelope.meta, &envelope.errors,
                          &error)) {
    return {{}, error};
  }
  if (!data.isNull() || envelope.errors.isEmpty()) {
    return {
        {},
        pathError(QStringLiteral("$"),
                  QStringLiteral("expected null data and at least one error"))};
  }
  return {std::move(envelope), {}};
}

QVariantList providersToVariants(const QList<Provider> &providers) {
  QVariantList result;
  result.reserve(providers.size());
  for (const Provider &provider : providers) {
    result.append(provider.toVariantMap());
  }
  return result;
}

QVariantList catalogsToVariants(const QList<Catalog> &catalogs) {
  QVariantList result;
  result.reserve(catalogs.size());
  for (const Catalog &catalog : catalogs) {
    result.append(catalog.toVariantMap());
  }
  return result;
}

QVariantList errorsToVariants(const QList<ApiError> &errors) {
  QVariantList result;
  result.reserve(errors.size());
  for (const ApiError &error : errors) {
    result.append(error.toVariantMap());
  }
  return result;
}

QVariantList streamsToVariants(const QList<StreamChoice> &streams) {
  QVariantList result;
  result.reserve(streams.size());
  for (const StreamChoice &stream : streams) {
    result.append(stream.toVariantMap());
  }
  return result;
}

} // namespace Live
