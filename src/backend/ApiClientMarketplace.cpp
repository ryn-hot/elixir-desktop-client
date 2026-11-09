// Owner management over authenticated HTTP. Snapshots are DATA, never native
// execution/cleanup capabilities. Setup values are never persisted or cached
// for explicit replay; only the server's original owners authorize effects.
#include "backend/ApiClient.h"
#include <QJsonDocument>
#include <QRegularExpression>
#include <QUuid>
#include <cmath>

namespace {
const QString targetsPath =
    QStringLiteral("/api/v1/marketplace/install/targets");
const QString installationsPath =
    QStringLiteral("/api/v1/marketplace/installations/");
constexpr double maxRevision = 9007199254740991.0;

bool keys(const QJsonObject &object, QStringList expected) {
  auto actual = object.keys();
  actual.sort();
  expected.sort();
  return actual == expected;
}
bool revision(const QJsonValue &value, double minimum = 0) {
  const auto number = value.toDouble(-1);
  return value.isDouble() && std::isfinite(number) &&
         std::floor(number) == number && number >= minimum &&
         number <= maxRevision;
}
bool uuid(const QJsonValue &value) {
  if (!value.isString())
    return false;
  const auto text = value.toString();
  const QUuid id(text);
  return !id.isNull() && id.toString(QUuid::WithoutBraces) == text;
}
bool digest(const QJsonValue &value) {
  static const QRegularExpression pattern("^sha256:[0-9a-f]{64}$");
  return value.isString() && pattern.match(value.toString()).hasMatch();
}
bool controls(const QJsonObject &object, const QString &kind) {
  if (object.value("kind").toString() != kind)
    return false;
  if (kind == "absent")
    return keys(object, {"kind"});
  if (!revision(object.value("extension_revision"), 1) ||
      object.value("extension_revision").toDouble() >= maxRevision)
    return false;
  if (kind == "new_instance")
    return keys(object, {"kind", "extension_revision"});
  return kind == "existing" &&
         keys(object, {"kind", "extension_revision", "instance_revision"}) &&
         revision(object.value("instance_revision"), 1) &&
         object.value("instance_revision").toDouble() < maxRevision;
}
bool cursor(const QJsonObject &object) {
  return keys(object, {"instance_id", "extension_revision"}) &&
         uuid(object.value("instance_id")) &&
         revision(object.value("extension_revision"), 1) &&
         object.value("extension_revision").toDouble() < maxRevision;
}
bool originalRequest(const QJsonObject &object) {
  auto base = object;
  if (base.contains("direct_reference")) {
    if (!digest(base.value("direct_reference")))
      return false;
    base.remove("direct_reference");
  }
  if (base.contains("upload_source")) {
    if (!object.contains("direct_reference") ||
        !base.value("upload_source").isBool() ||
        !base.value("upload_source").toBool())
      return false;
    base.remove("upload_source");
  }
  static const QRegularExpression identity(
      "^elx:[a-z2-7]{52}/[a-z0-9]+(?:-[a-z0-9]+)*$");
  if (!keys(base, {"schema_version", "query_id", "extension_id", "release_id",
                   "target", "expected_revision", "mutation_id", "controls"}) ||
      object.value("schema_version").toDouble() != 1 ||
      !uuid(object.value("query_id")) || !uuid(object.value("mutation_id")) ||
      !digest(object.value("release_id")) ||
      object.value("extension_id").toString().size() > 121 ||
      !identity.match(object.value("extension_id").toString()).hasMatch() ||
      !revision(object.value("expected_revision")) ||
      object.value("expected_revision").toDouble() >= maxRevision ||
      QJsonDocument(object).toJson(QJsonDocument::Compact).size() > 4096)
    return false;
  const auto target = object.value("target").toObject(),
             observed = object.value("controls").toObject();
  if (target.value("kind").toString() == "existing")
    return keys(target, {"kind", "instance_id"}) &&
           uuid(target.value("instance_id")) &&
           object.value("expected_revision").toDouble() > 0 &&
           controls(observed, "existing");
  const auto name = target.value("name").toString();
  if (!keys(target, {"kind", "name"}) ||
      target.value("kind").toString() != "new" ||
      !target.value("name").isString() || name.isEmpty() ||
      name.toUtf8().size() > 128 ||
      object.value("expected_revision").toDouble() != 0 ||
      (!controls(observed, "absent") && !controls(observed, "new_instance")))
    return false;
  for (const auto character : name)
    if (character.category() == QChar::Other_Control)
      return false;
  return true;
}
bool publication(const QJsonObject &object) {
  return keys(object, {"schema_version", "publisher", "release", "head"}) &&
         object.value("schema_version").toDouble() == 1 &&
         object.value("publisher").isObject() &&
         object.value("release").isObject() &&
         object.value("head").isObject() &&
         QJsonDocument(object).toJson(QJsonDocument::Compact).size() <= 65536;
}
bool directRequest(const QJsonObject &object) {
  if (!keys(object, {"schema_version", "request_id", "publication",
                     "accepted_reference", "accept_unqualified", "target",
                     "expected_revision", "mutation_id", "controls"}) ||
      !publication(object.value("publication").toObject()) ||
      !digest(object.value("accepted_reference")) ||
      object.value("accept_unqualified") != QJsonValue(true))
    return false;
  const auto payload = object.value("publication")
                           .toObject()
                           .value("release")
                           .toObject()
                           .value("payload")
                           .toObject();
  return originalRequest(
      QJsonObject{{"schema_version", object.value("schema_version")},
                  {"query_id", object.value("request_id")},
                  {"extension_id", payload.value("extension_id")},
                  {"release_id", object.value("accepted_reference")},
                  {"target", object.value("target")},
                  {"expected_revision", object.value("expected_revision")},
                  {"mutation_id", object.value("mutation_id")},
                  {"controls", object.value("controls")}});
}
bool outboundStart(const QJsonObject &object) {
  return object.contains("publication")
             ? directRequest(object)
             : !object.contains("direct_reference") && originalRequest(object);
}
bool directPreview(const QJsonObject &object, const QJsonObject &input) {
  const auto payload =
      input.value("release").toObject().value("payload").toObject();
  if (!keys(object,
            {"schema_version",      "reference_id",     "extension_id",
             "release_id",          "publisher_id",     "name",
             "publisher",           "version",          "description",
             "media_tags",          "runtime_profile",  "stable",
             "signatures_verified", "security_tracked", "metadata_only",
             "discovery_qualified", "source_verified",  "install_available",
             "valid_for_seconds",   "warning"}) ||
      object.value("schema_version").toDouble() != 1 ||
      !digest(object.value("reference_id")) ||
      !digest(object.value("release_id")) ||
      object.value("extension_id") != payload.value("extension_id") ||
      object.value("name") != payload.value("display_name") ||
      object.value("publisher") != payload.value("publisher_name") ||
      object.value("version") != payload.value("version") ||
      object.value("description") != payload.value("description") ||
      object.value("media_tags") != payload.value("media_tags") ||
      object.value("runtime_profile") != payload.value("runtime_profile") ||
      object.value("signatures_verified") != QJsonValue(true) ||
      object.value("metadata_only") != QJsonValue(true) ||
      !object.value("stable").isBool() ||
      !object.value("security_tracked").isBool() ||
      !revision(object.value("valid_for_seconds"), 1) ||
      object.value("valid_for_seconds").toDouble() > 300 ||
      QJsonDocument(object).toJson(QJsonDocument::Compact).size() > 65536)
    return false;
  for (const auto &field :
       {"discovery_qualified", "source_verified", "install_available"})
    if (object.value(field) != QJsonValue(false))
      return false;
  return true;
}
bool targets(const QJsonObject &object, const QString &extension) {
  QStringList fields{"schema_version", "extension_id", "new_instance",
                     "instances", "next_cursor", "installation_ready"};
  if (object.contains("review_available"))
    fields.append("review_available");
  if (!keys(object, fields) ||
      object.value("schema_version").toDouble() != 1 ||
      object.value("extension_id").toString() != extension ||
      object.value("installation_ready") != QJsonValue(false) ||
      (object.contains("review_available") &&
       !object.value("review_available").isBool()) ||
      !object.value("instances").isArray() ||
      object.value("instances").toArray().size() > 20)
    return false;
  const auto fresh = object.value("new_instance").toObject();
  const auto parent = fresh.value("controls").toObject();
  const bool absent = controls(parent, "absent");
  if (!keys(fresh, {"expected_revision", "controls"}) ||
      !revision(fresh.value("expected_revision")) ||
      fresh.value("expected_revision").toDouble() != 0 ||
      (!absent && !controls(parent, "new_instance")))
    return false;
  QSet<QString> ids;
  for (const auto &value : object.value("instances").toArray()) {
    if (!value.isObject())
      return false;
    const auto row = value.toObject();
    const auto name = row.value("name").toString();
    if (!keys(row, {"instance_id", "name", "enabled", "expected_revision",
                    "controls", "pending"}) ||
        !uuid(row.value("instance_id")) ||
        ids.contains(row.value("instance_id").toString()) ||
        !row.value("name").isString() || name.isEmpty() ||
        name.toUtf8().size() > 128 || !row.value("enabled").isBool() ||
        !row.value("pending").isBool() ||
        !revision(row.value("expected_revision"), 1))
      return false;
    for (const auto character : name)
      if (character.category() == QChar::Other_Control)
        return false;
    const auto selected = row.value("controls");
    if (!selected.isNull() &&
        (!selected.isObject() || row.value("pending").toBool() ||
         !controls(selected.toObject(), "existing") ||
         selected.toObject().value("extension_revision") !=
             parent.value("extension_revision")))
      return false;
    ids.insert(row.value("instance_id").toString());
  }
  const auto next = object.value("next_cursor");
  if (!next.isNull() &&
      (!next.isObject() || !cursor(next.toObject()) ||
       object.value("instances").toArray().size() != 20 ||
       next.toObject().value("instance_id") != object.value("instances")
                                                   .toArray()
                                                   .last()
                                                   .toObject()
                                                   .value("instance_id") ||
       next.toObject().value("extension_revision") !=
           parent.value("extension_revision")))
    return false;
  return !absent || (ids.isEmpty() && next.isNull());
}
const QStringList actionKinds{"approve", "retry_stage", "setup", "activate",
                              "cancel"};
// Version-one review DATA. Unsupported access/resource shapes must not leave
// approval controls enabled. This does not recompute a review or grant access.
bool resources(const QJsonObject &object) {
  constexpr double mib = 1024 * 1024;
  auto fields =
      QStringList{"memory_bytes", "cpu_millicores", "pids", "temporary_mounts"};
  if (object.contains("state_bytes"))
    fields.append("state_bytes");
  const auto memory = object.value("memory_bytes");
  const auto state = object.value("state_bytes");
  const auto cpu = object.value("cpu_millicores");
  const auto pids = object.value("pids");
  if (!keys(object, fields) || !revision(memory, 16 * mib) ||
      memory.toDouble() > 4096 * mib ||
      std::fmod(memory.toDouble(), mib) != 0 || !revision(cpu, 1) ||
      cpu.toDouble() > 8000 || !revision(pids, 1) || pids.toDouble() > 512 ||
      (object.contains("state_bytes") &&
       (!revision(state) || state.toDouble() > 16 * mib ||
        std::fmod(state.toDouble(), mib) != 0)) ||
      !object.value("temporary_mounts").isArray())
    return false;
  const auto mounts = object.value("temporary_mounts").toArray();
  if (mounts.isEmpty() || mounts.size() > 3)
    return false;
  QSet<QString> paths;
  double total = 0;
  for (const auto &value : mounts) {
    const auto mount = value.toObject();
    const auto path = mount.value("path").toString();
    const auto bytes = mount.value("bytes");
    if (!value.isObject() || !keys(mount, {"path", "bytes"}) ||
        !QStringList{"/tmp", "/run", "/dev/shm"}.contains(path) ||
        paths.contains(path) || !revision(bytes, mib) ||
        bytes.toDouble() > 256 * mib || std::fmod(bytes.toDouble(), mib) != 0)
      return false;
    paths.insert(path);
    total += bytes.toDouble();
  }
  return total <= 256 * mib && total <= memory.toDouble() / 2;
}
bool grantReview(const QJsonObject &object, const QJsonObject &original) {
  const auto scope = object.value("scope").toObject();
  if (!keys(object, {"release_id", "manifest_sha256", "scope"}) ||
      object.value("release_id") != original.value("release_id") ||
      !digest(object.value("manifest_sha256")) ||
      !keys(scope,
            {"policy_version", "extension_id", "runtime_profile", "permissions",
             "secret_keys", "runtime", "authority_contract"}) ||
      scope.value("policy_version").toDouble() != 1 ||
      scope.value("extension_id") != original.value("extension_id") ||
      !digest(scope.value("authority_contract")) ||
      !scope.value("permissions").isArray() ||
      !scope.value("secret_keys").isArray())
    return false;
  const auto permissions = scope.value("permissions").toArray();
  const auto secrets = scope.value("secret_keys").toArray();
  if (permissions.size() > 32 || secrets.size() > 64)
    return false;
  const QStringList knownPermissions{"runtime.manage_containers",
                                     "network.egress",
                                     "live.catalog.read",
                                     "live.stream.resolve",
                                     "live.artwork.fetch",
                                     "live.network.private",
                                     "drivers.configure.indexer.registry",
                                     "drivers.configure.media.manager.tv",
                                     "drivers.configure.media.manager.movies",
                                     "drivers.configure.downloader.torrent",
                                     "drivers.configure.downloader.nzb"};
  QString previous;
  for (const auto &permission : permissions) {
    const auto name = permission.toString();
    if (!permission.isString() || !knownPermissions.contains(name) ||
        (!previous.isEmpty() && previous >= name))
      return false;
    previous = name;
  }
  previous.clear();
  static const QRegularExpression keyPattern("^[A-Za-z0-9_.-]{1,64}$");
  for (const auto &secret : secrets) {
    const auto name = secret.toString();
    if (!secret.isString() || !keyPattern.match(name).hasMatch() ||
        (!previous.isEmpty() && previous >= name))
      return false;
    previous = name;
  }
  const auto profile = scope.value("runtime_profile").toString();
  if (profile == "declarative-v1")
    return secrets.isEmpty() && scope.value("runtime").isNull();
  return (profile == "source-js-v1" || profile == "reproducible-v1") &&
         scope.value("runtime").isObject() &&
         resources(scope.value("runtime").toObject());
}
bool receipt(const QJsonValue &value) {
  if (value.isNull())
    return true;
  const auto object = value.toObject();
  return value.isObject() && keys(object, {"request_id", "kind", "status"}) &&
         uuid(object.value("request_id")) &&
         actionKinds.contains(object.value("kind").toString()) &&
         QStringList{"queued",   "running",           "acknowledged",
                     "rejected", "recovery_required", "unconfirmed"}
             .contains(object.value("status").toString());
}
bool view(const QJsonObject &object, const QString &expectedId = {}) {
  if (!keys(object, {"schema_version", "review_id", "approval_revision",
                     "operation_id", "release_id", "phase", "preparation",
                     "review", "configured_instance", "revision",
                     "available_actions", "latest_action",
                     "activation_request_id", "cancellation_request_id",
                     "installation_ready", "initial_request"}) ||
      object.value("schema_version").toDouble() != 1 ||
      !uuid(object.value("operation_id")) ||
      (!expectedId.isEmpty() &&
       object.value("operation_id").toString() != expectedId) ||
      !digest(object.value("release_id")) ||
      !object.value("installation_ready").isBool() ||
      !QStringList{"queued", "capturing_target", "selecting_source",
                   "preparing", "awaiting_approval", "staging",
                   "awaiting_setup", "installing", "awaiting_commit",
                   "activating", "cancelling", "activated", "cancelled",
                   "stopped", "recovery_required"}
           .contains(object.value("phase").toString()) ||
      !object.value("available_actions").isArray() ||
      object.value("available_actions").toArray().size() > 5 ||
      !receipt(object.value("latest_action")))
    return false;
  if (!originalRequest(object.value("initial_request").toObject()) ||
      object.value("initial_request").toObject().value("release_id") !=
          object.value("release_id"))
    return false;
  for (const auto &field : {"configured_instance", "activation_request_id",
                            "cancellation_request_id"})
    if (!object.value(field).isNull() && !uuid(object.value(field)))
      return false;
  for (const auto &field : {"revision", "approval_revision"})
    if (!object.value(field).isNull() && !revision(object.value(field)))
      return false;
  QSet<QString> actions;
  for (const auto &value : object.value("available_actions").toArray()) {
    if (!value.isString() || !actionKinds.contains(value.toString()) ||
        actions.contains(value.toString()))
      return false;
    actions.insert(value.toString());
  }
  if (!actions.isEmpty() &&
      (QStringList{"queued", "running"}.contains(object.value("latest_action")
                                                     .toObject()
                                                     .value("status")
                                                     .toString()) ||
       QStringList{"activated", "cancelled", "stopped"}.contains(
           object.value("phase").toString())))
    return false;
  const auto review = object.value("review");
  if (review.isNull()) {
    if (!object.value("review_id").isNull() || actions.contains("approve"))
      return false;
  } else if (!review.isObject() || !digest(object.value("review_id")) ||
             !grantReview(review.toObject(),
                          object.value("initial_request").toObject()))
    return false;
  if (actions.contains("approve") &&
      !revision(object.value("approval_revision")))
    return false;
  const auto preparation = object.value("preparation");
  return preparation.isNull() ||
         (preparation.isObject() &&
          uuid(preparation.toObject().value("preparation_id")) &&
          preparation.toObject().value("release_id") ==
              object.value("release_id"));
}
} // namespace

QVariantMap ApiClient::marketplaceInstallTargets() const {
  if (m_marketplaceTargetsQuery.startsWith("direct:")) {
    if (marketplaceDirectReferenceFresh() &&
        m_marketplaceTargetsQuery ==
            "direct:" +
                m_marketplaceDirectReference.value("reference_id").toString() &&
        m_marketplaceInstallTargets.value("extension_id") ==
            m_marketplaceDirectReference.value("extension_id"))
      return m_marketplaceInstallTargets;
    return {};
  }
  if (!marketplaceSearchFresh() ||
      m_marketplaceTargetsQuery != m_marketplaceSearchId)
    return {};
  const auto extension = m_marketplaceInstallTargets.value("extension_id");
  for (const auto &entry : marketplaceSearchResults())
    if (entry.toMap().value("extension_id") == extension)
      return m_marketplaceInstallTargets;
  return {};
}
QVariantMap ApiClient::marketplaceInstallation() const {
  return m_marketplaceInstallation;
}
bool ApiClient::marketplaceInstallationLoading() const {
  return m_marketplaceInstallationLoading;
}
QString ApiClient::marketplaceInstallationNotice() const {
  return m_marketplaceInstallationNotice;
}
bool ApiClient::marketplaceInstallationHasOriginalStart() const {
  return outboundStart(m_marketplaceOriginalStart);
}
bool ApiClient::marketplaceInstallationHasOriginalAction() const {
  return !m_marketplaceOriginalAction.isEmpty();
}
void ApiClient::clearMarketplaceInstallation() {
  clearMarketplaceDirectReference();
  m_marketplaceDirectRequestEpoch = ++m_marketplaceDirectEpoch;
  m_marketplaceDirectLoading = false;
  ++m_marketplaceInstallationEpoch;
  m_marketplaceInstallTargets.clear();
  m_marketplaceTargetsQuery.clear();
  m_marketplaceInstallation.clear();
  m_marketplaceInstallationId.clear();
  m_marketplaceInstallationNotice.clear();
  m_marketplaceInstallationLoading = false;
  m_marketplaceOriginalStart = {};
  m_marketplaceOriginalAction = {};
  m_marketplaceActionOperation.clear();
  emit marketplaceInstallationChanged();
}
void ApiClient::failMarketplaceInstallationRead(const QString &message) {
  // Keep only the last original operation ID for an explicit retry. Never
  // leave stale action hints or target controls enabled after a failed read.
  m_marketplaceInstallTargets.clear();
  m_marketplaceTargetsQuery.clear();
  m_marketplaceInstallation.clear();
  m_marketplaceInstallationLoading = false;
  m_marketplaceInstallationNotice = message;
  emit marketplaceInstallationChanged();
}
void ApiClient::fetchMarketplaceInstallTargets(const QString &extensionId,
                                               const QVariantMap &after) {
  fetchMarketplaceSourceTargets(extensionId, after, false);
}
void ApiClient::fetchMarketplaceDirectInstallTargets(const QVariantMap &after) {
  fetchMarketplaceSourceTargets(
      marketplaceDirectReference().value("extension_id").toString(), after,
      true);
}
void ApiClient::fetchMarketplaceSourceTargets(const QString &extensionId,
                                              const QVariantMap &after,
                                              bool direct) {
  if (m_marketplaceInstallationLoading)
    return;
  bool listed = false;
  for (const auto &item : marketplaceSearchResults())
    listed |= item.toMap().value("extension_id").toString() == extensionId;
  const auto page = QJsonObject::fromVariantMap(after);
  if (direct)
    listed = marketplaceDirectReferenceFresh() &&
             m_marketplaceDirectReference.value("extension_id").toString() ==
                 extensionId;
  if ((direct && !marketplaceOwner()) || !listed ||
      (!page.isEmpty() && !cursor(page))) {
    failMarketplaceInstallationRead("Search again and choose a checked listing "
                                    "before inspecting installation targets.");
    return;
  }
  const auto epoch = m_marketplaceInstallationEpoch;
  const auto query =
      direct ? "direct:" +
                   m_marketplaceDirectReference.value("reference_id").toString()
             : m_marketplaceSearchId;
  m_marketplaceInstallTargets.clear();
  m_marketplaceTargetsQuery.clear();
  m_marketplaceInstallationLoading = true;
  m_marketplaceInstallationNotice.clear();
  emit marketplaceInstallationChanged();
  QJsonObject body{{"schema_version", 1}, {"extension_id", extensionId}};
  if (!page.isEmpty())
    body.insert("after", page);
  sendRequest(
      "POST", targetsPath, body,
      [this, epoch, query, extensionId, direct](const QJsonDocument &doc) {
        if (epoch != m_marketplaceInstallationEpoch)
          return;
        m_marketplaceInstallationLoading = false;
        if (direct ? (!marketplaceDirectReferenceFresh() ||
                      query != "direct:" + m_marketplaceDirectReference
                                               .value("reference_id")
                                               .toString())
                   : (query != m_marketplaceSearchId ||
                      !marketplaceSearchFresh())) {
          emit marketplaceInstallationChanged();
          return;
        }
        if (!doc.isObject() || !targets(doc.object(), extensionId)) {
          failMarketplaceInstallationRead(
              "Installation targets were not supported. Refresh before "
              "choosing a target.");
          return;
        }
        m_marketplaceInstallTargets = doc.object().toVariantMap();
        m_marketplaceTargetsQuery = query;
        emit marketplaceInstallationChanged();
      },
      [this, epoch](const QString &) {
        if (epoch == m_marketplaceInstallationEpoch)
          failMarketplaceInstallationRead("Target checks were not confirmed. "
                                          "No installation was requested.");
      });
}
void ApiClient::fetchCurrentMarketplaceInstallation() {
  readMarketplaceInstallation(true);
}
bool ApiClient::marketplaceDirectReferenceFresh() const {
  return marketplaceOwner() && !m_marketplaceDirectReference.isEmpty() &&
         !m_marketplaceDirectPublication.isEmpty() &&
         m_marketplaceDirectAge.isValid() &&
         m_marketplaceDirectAge.elapsed() < m_marketplaceDirectLifetimeMs;
}
QVariantMap ApiClient::marketplaceDirectReference() const {
  return marketplaceDirectReferenceFresh() ? m_marketplaceDirectReference
                                           : QVariantMap{};
}
bool ApiClient::marketplaceDirectReferenceLoading() const {
  return m_marketplaceDirectLoading;
}
void ApiClient::clearMarketplaceDirectReference() {
  ++m_marketplaceDirectEpoch;
  m_marketplaceDirectReference.clear();
  m_marketplaceDirectPublication = {};
  m_marketplaceDirectAge.invalidate();
  m_marketplaceDirectLifetimeMs = 0;
  if (m_marketplaceDirectExpiry)
    m_marketplaceDirectExpiry->stop();
  if (m_marketplaceTargetsQuery.startsWith("direct:")) {
    m_marketplaceTargetsQuery.clear();
    m_marketplaceInstallTargets.clear();
  }
  emit marketplaceInstallationChanged();
}
void ApiClient::previewMarketplaceDirectReference(const QString &text) {
  if (m_marketplaceDirectLoading || m_marketplaceInstallationLoading)
    return;
  clearMarketplaceDirectReference();
  if (!marketplaceOwner() || text.toUtf8().size() > 65536) {
    marketplaceInstallationMessage("A current owner and a signed developer "
                                   "reference of at most 64 KiB are required.");
    return;
  }
  QJsonParseError error;
  const auto parsed = QJsonDocument::fromJson(text.toUtf8(), &error);
  if (error.error != QJsonParseError::NoError || !parsed.isObject() ||
      !publication(parsed.object())) {
    marketplaceInstallationMessage("Paste the signed publication.json object, "
                                   "not a URL, package or verification claim.");
    return;
  }
  const auto input = parsed.object();
  const auto epoch = m_marketplaceDirectEpoch;
  m_marketplaceDirectRequestEpoch = epoch;
  m_marketplaceDirectLoading = true;
  m_marketplaceInstallationNotice.clear();
  emit marketplaceInstallationChanged();
  sendRequest(
      "POST", "/api/v1/marketplace/import", input,
      [this, epoch, input](const QJsonDocument &doc) {
        if (m_marketplaceDirectRequestEpoch != epoch)
          return;
        m_marketplaceDirectLoading = false;
        if (epoch != m_marketplaceDirectEpoch) {
          emit marketplaceInstallationChanged();
          return;
        }
        if (!marketplaceOwner() || !doc.isObject() ||
            !directPreview(doc.object(), input)) {
          marketplaceInstallationMessage("The signed reference preview was not "
                                         "supported. Nothing was installed.");
          return;
        }
        m_marketplaceDirectPublication = input;
        m_marketplaceDirectReference = doc.object().toVariantMap();
        m_marketplaceDirectLifetimeMs = static_cast<qint64>(
            doc.object().value("valid_for_seconds").toDouble() * 1000);
        m_marketplaceDirectAge.start();
        if (!m_marketplaceDirectExpiry) {
          m_marketplaceDirectExpiry = new QTimer(this);
          m_marketplaceDirectExpiry->setSingleShot(true);
          connect(m_marketplaceDirectExpiry, &QTimer::timeout, this,
                  [this] { clearMarketplaceDirectReference(); });
        }
        m_marketplaceDirectExpiry->start(
            static_cast<int>(m_marketplaceDirectLifetimeMs));
        emit marketplaceInstallationChanged();
      },
      [this, epoch](const QString &) {
        if (m_marketplaceDirectRequestEpoch != epoch)
          return;
        m_marketplaceDirectLoading = false;
        if (epoch == m_marketplaceDirectEpoch)
          marketplaceInstallationMessage(
              "Reference checks were not confirmed. Nothing was installed or "
              "made searchable.");
        else
          emit marketplaceInstallationChanged();
      });
}
void ApiClient::pollMarketplaceInstallation() {
  readMarketplaceInstallation(false);
}
void ApiClient::readMarketplaceInstallation(bool current) {
  if (m_marketplaceInstallationLoading ||
      (!current && m_marketplaceInstallationId.isEmpty()))
    return;
  const auto epoch = m_marketplaceInstallationEpoch;
  const auto id = m_marketplaceInstallationId;
  m_marketplaceInstallationLoading = true;
  m_marketplaceInstallationNotice.clear();
  emit marketplaceInstallationChanged();
  sendRequest(
      "GET", installationsPath + (current ? "current" : id), {},
      [this, epoch, id, current](const QJsonDocument &doc) {
        if (epoch != m_marketplaceInstallationEpoch)
          return;
        m_marketplaceInstallationLoading = false;
        QJsonObject result;
        if (current) {
          if (!doc.isObject() ||
              !keys(doc.object(), {"schema_version", "operation"}) ||
              doc.object().value("schema_version").toDouble() != 1) {
            failMarketplaceInstallationRead(
                "Current installation response was not supported.");
            return;
          }
          const auto operation = doc.object().value("operation");
          if (operation.isNull()) {
            m_marketplaceInstallation.clear();
            m_marketplaceInstallationId.clear();
            emit marketplaceInstallationChanged();
            return;
          }
          result = operation.toObject();
        } else
          result = doc.object();
        if (!view(result, current ? QString() : id)) {
          failMarketplaceInstallationRead(
              "Installation status was not supported. Retry the original "
              "operation.");
          return;
        }
        const auto next = result.value("operation_id").toString();
        if (m_marketplaceActionOperation != next) {
          m_marketplaceOriginalAction = {};
          m_marketplaceActionOperation.clear();
        }
        const auto initial = result.value("initial_request").toObject();
        if (!(directRequest(m_marketplaceOriginalStart) &&
              initial.value("direct_reference") ==
                  m_marketplaceOriginalStart.value("accepted_reference") &&
              initial.value("query_id") ==
                  m_marketplaceOriginalStart.value("request_id") &&
              !initial.contains("upload_source") &&
              initial.value("mutation_id") ==
                  m_marketplaceOriginalStart.value("mutation_id") &&
              initial.value("target") ==
                  m_marketplaceOriginalStart.value("target") &&
              initial.value("controls") ==
                  m_marketplaceOriginalStart.value("controls") &&
              initial.value("expected_revision") ==
                  m_marketplaceOriginalStart.value("expected_revision")))
          m_marketplaceOriginalStart = initial;
        m_marketplaceInstallation = result.toVariantMap();
        m_marketplaceInstallationId = result.value("operation_id").toString();
        emit marketplaceInstallationChanged();
      },
      [this, epoch](const QString &) {
        if (epoch == m_marketplaceInstallationEpoch)
          failMarketplaceInstallationRead(
              "Installation status was not confirmed. The server operation may "
              "still be running.");
      });
}

bool ApiClient::marketplaceConnectionSaving() const {
  return m_marketplaceConnectionSaving;
}
QString ApiClient::marketplaceConnectionNotice() const {
  return m_marketplaceConnectionNotice;
}
void ApiClient::saveMarketplaceWireguard(const QString &config) {
  if (m_marketplaceConnectionSaving || m_authToken.isEmpty() ||
      !marketplaceOwner() || !capabilities().contains("secrets_manage"))
    return;
  const auto material = config.trimmed();
  if (material.isEmpty() || material.toUtf8().size() > 256 * 1024 ||
      material.contains(QChar(0))) {
    m_marketplaceConnectionNotice =
        "Paste a bounded, dedicated WireGuard configuration.";
    emit marketplaceConnectionChanged();
    return;
  }
  m_marketplaceConnectionSaving = true;
  m_marketplaceConnectionNotice =
      "Saving connection configuration; protection is not confirmed.";
  const auto generation = ++m_marketplaceConnectionRequestId;
  emit marketplaceConnectionChanged();
  sendRequest(
      "POST", "/api/v1/network/protection/import/wireguard",
      QJsonObject{{"profileId", "marketplace-network"},
                  {"name", "Marketplace connection"},
                  {"purpose", "marketplace_network"},
                  {"strict", true},
                  {"config", material}},
      [this, generation](const QJsonDocument &doc) {
        if (generation != m_marketplaceConnectionRequestId)
          return;
        m_marketplaceConnectionSaving = false;
        const auto profile = doc.object().value("profile").toObject();
        if (!marketplaceOwner() || !doc.isObject() ||
            profile.value("id") != "marketplace-network" ||
            profile.value("scope") != "marketplace_network" ||
            profile.value("kind") != "wireguard_config" ||
            profile.value("strict") != QJsonValue(true) ||
            profile.value("enabled") != QJsonValue(true) ||
            !doc.object().value("blocker").isNull()) {
          m_marketplaceConnectionNotice =
              "Connection configuration was not confirmed. Check the server "
              "before retrying.";
        } else {
          m_marketplaceConnectionNotice =
              "Configuration saved. Connection readiness is shown above; the "
              "server must select this saved marketplace profile. Downloader "
              "and extension-HTTP profiles are unchanged.";
        }
        emit marketplaceConnectionChanged();
        pollMarketplaceSettings();
      },
      [this, generation](const QString &) {
        if (generation != m_marketplaceConnectionRequestId)
          return;
        m_marketplaceConnectionSaving = false;
        m_marketplaceConnectionNotice =
            "Save outcome is unconfirmed. Check the connection before "
            "retrying; no alternate network was selected.";
        emit marketplaceConnectionChanged();
      });
}
void ApiClient::retryMarketplaceConnection() {
  if (m_marketplaceConnectionSaving || m_authToken.isEmpty() ||
      !marketplaceOwner() || !capabilities().contains("secrets_manage"))
    return;
  m_marketplaceConnectionSaving = true;
  m_marketplaceConnectionNotice = "Requesting a connection retry; protection is not confirmed.";
  const auto generation = ++m_marketplaceConnectionRequestId;
  emit marketplaceConnectionChanged();
  sendRequest("POST", "/api/v1/marketplace/connection/retry",
      QJsonObject{{"schema_version", 1}},
      [this, generation](const QJsonDocument &doc) {
        if (generation != m_marketplaceConnectionRequestId) return;
        m_marketplaceConnectionSaving = false;
        const auto reply = doc.object();
        if (!marketplaceOwner() || !doc.isObject() ||
            !keys(reply, {"schema_version", "requested"}) ||
            reply.value("schema_version") != QJsonValue(1) ||
            !reply.value("requested").isBool())
          m_marketplaceConnectionNotice = "Connection retry was not confirmed. Check live status.";
        else
          m_marketplaceConnectionNotice = reply.value("requested").toBool()
              ? "Retry requested. Existing cleanup and protection checks must finish first."
              : "No configured connection recovery task is running. Check the server's startup configuration.";
        emit marketplaceConnectionChanged();
        pollMarketplaceSettings();
      }, [this, generation](const QString &) {
        if (generation != m_marketplaceConnectionRequestId) return;
        m_marketplaceConnectionSaving = false;
        m_marketplaceConnectionNotice = "Retry outcome is unconfirmed. No alternate network was selected.";
        emit marketplaceConnectionChanged();
      });
}
void ApiClient::saveMarketplaceProviderSetup(bool enabled, const QString &consentVersion) {
  if (m_marketplaceConnectionSaving || m_marketplaceSettingsLoading || m_authToken.isEmpty()
      || !marketplaceOwner() || !capabilities().contains("secrets_manage")
      || !m_marketplaceSettings.value("runtime_fresh").toBool())
    return;
  const auto setup = QJsonObject::fromVariantMap(m_marketplaceSettings.value("provider_setup").toMap());
  const auto preferences = m_marketplaceSettings.value("settings").toMap();
  if (!keys(setup, {"schema_version", "revision", "enabled", "consent_current", "consent_version"})
      || !revision(setup.value("revision")) || setup.value("revision").toDouble() >= maxRevision
      || preferences.value("revision").toDouble() < 1
      || (enabled ? consentVersion != "elixir-marketplace-warp-v1" : !consentVersion.isEmpty())) {
    m_marketplaceConnectionNotice = "Save marketplace choices and review current VPN consent before continuing.";
    emit marketplaceConnectionChanged();
    return;
  }
  // The auth-refresh mechanism retains this exact body/mutation UUID. An
  // unknown outcome is not replayed as a newly generated registration choice.
  const auto generation = ++m_marketplaceConnectionRequestId;
  const auto expected = setup.value("revision").toDouble();
  const QJsonObject body{{"schema_version", 1}, {"expected_revision", expected},
      {"mutation_id", QUuid::createUuid().toString(QUuid::WithoutBraces)},
      {"enabled", enabled}, {"consent_version", enabled ? QJsonValue(consentVersion) : QJsonValue(QJsonValue::Null)}};
  QElapsedTimer elapsed; elapsed.start();
  m_marketplaceConnectionSaving = true;
  m_marketplaceConnectionNotice = "Saving VPN choice; protection is not confirmed.";
  emit marketplaceConnectionChanged();
  sendRequest("PATCH", "/api/v1/marketplace/connection/provider", body,
      [this, generation, expected, enabled, elapsed](const QJsonDocument &doc) {
        if (generation != m_marketplaceConnectionRequestId) return;
        m_marketplaceConnectionSaving = false;
        const auto setup = doc.object().value("provider_setup").toObject();
        const bool supported = marketplaceOwner() && doc.isObject()
            && updateMarketplaceSettings(doc.object(), elapsed.elapsed());
        if (generation != m_marketplaceConnectionRequestId) return;
        if (!supported
            || setup.value("revision").toDouble() != expected + 1
            || setup.value("enabled") != QJsonValue(enabled)
            || (enabled && setup.value("consent_current") != QJsonValue(true))) {
          invalidateMarketplaceRuntime();
          m_marketplaceConnectionNotice = "VPN choice was not confirmed. Reload status before retrying.";
        } else {
          m_marketplaceConnectionNotice = enabled
              ? "VPN consent saved. The server will connect using its retained marketplace identity; wait for protected status."
              : "Disconnect requested. The marketplace identity is retained for reconnecting; stopped is not confirmed yet.";
        }
        emit marketplaceConnectionChanged();
        pollMarketplaceSettings();
      }, [this, generation](const QString &) {
        if (generation != m_marketplaceConnectionRequestId) return;
        m_marketplaceConnectionSaving = false;
        invalidateMarketplaceRuntime();
        m_marketplaceConnectionNotice = "VPN choice outcome is unconfirmed. Reload before retrying; no alternate network was selected.";
        emit marketplaceConnectionChanged();
        pollMarketplaceSettings();
      });
}
bool ApiClient::marketplaceOwner() const {
  const auto caps = capabilities();
  return homeRole() == "owner" && activeProfileType() == "account" &&
         caps.contains("settings_manage") &&
         caps.contains("extensions_manage") && caps.contains("server_admin");
}
bool ApiClient::marketplaceActionAvailable(const QString &kind) const {
  return !m_marketplaceInstallationLoading && marketplaceOwner() &&
         m_marketplaceInstallation.value("operation_id").toString() ==
             m_marketplaceInstallationId &&
         !m_marketplaceInstallationId.isEmpty() &&
         m_marketplaceInstallation.value("available_actions")
             .toStringList()
             .contains(kind);
}
void ApiClient::marketplaceInstallationMessage(const QString &message) {
  m_marketplaceInstallationNotice = message;
  emit marketplaceInstallationChanged();
}
void ApiClient::startMarketplaceInstallation(const QString &extensionId,
                                             const QString &releaseId,
                                             const QString &name,
                                             const QString &instanceId) {
  startMarketplaceSourceInstallation(extensionId, releaseId, name, instanceId,
                                     false);
}
void ApiClient::startMarketplaceDirectInstallation(const QString &name,
                                                   const QString &instanceId,
                                                   bool accepted) {
  if (!accepted || !marketplaceDirectReferenceFresh()) {
    marketplaceInstallationMessage(
        "Review the exact developer reference and explicitly accept its "
        "unqualified adoption before installing.");
    return;
  }
  startMarketplaceSourceInstallation(
      m_marketplaceDirectReference.value("extension_id").toString(),
      m_marketplaceDirectReference.value("release_id").toString(), name,
      instanceId, true);
}
void ApiClient::startMarketplaceSourceInstallation(const QString &extensionId,
                                                   const QString &releaseId,
                                                   const QString &name,
                                                   const QString &instanceId,
                                                   bool direct) {
  if (m_marketplaceInstallationLoading)
    return;
  if (!marketplaceOwner()) {
    marketplaceInstallationMessage(
        "Only the current server owner can manage an installation.");
    return;
  }
  const auto selected =
      QJsonObject::fromVariantMap(marketplaceInstallTargets());
  bool listed = false;
  for (const auto &entry : marketplaceSearchResults()) {
    const auto card = entry.toMap();
    listed |= card.value("extension_id").toString() == extensionId &&
              card.value("release_id").toString() == releaseId;
  }
  if (direct)
    listed =
        marketplaceDirectReferenceFresh() &&
        m_marketplaceTargetsQuery ==
            "direct:" +
                m_marketplaceDirectReference.value("reference_id").toString() &&
        extensionId ==
            m_marketplaceDirectReference.value("extension_id").toString() &&
        releaseId ==
            m_marketplaceDirectReference.value("release_id").toString();
  // Availability to BEGIN a review is not source/permission/install authority.
  // Older servers omit the additive field and remain read-only in this UI.
  if (!listed || selected.value("extension_id").toString() != extensionId ||
      selected.value("review_available") != QJsonValue(true) ||
      selected.value("installation_ready") != QJsonValue(false)) {
    marketplaceInstallationMessage(
        "Installation review is not enabled for this checked listing on this server.");
    return;
  }
  const auto phase = m_marketplaceInstallation.value("phase").toString();
  const bool terminal =
      QStringList{"activated", "cancelled", "stopped"}.contains(phase);
  if ((!m_marketplaceInstallationId.isEmpty() && !terminal) ||
      (!m_marketplaceOriginalStart.isEmpty() &&
       m_marketplaceInstallationId.isEmpty())) {
    marketplaceInstallationMessage("Check or retry the original installation "
                                   "before starting another request.");
    return;
  }
  QJsonObject target, observed;
  QJsonValue expected;
  if (instanceId.isEmpty()) {
    target = {{"kind", "new"}, {"name", name}};
    const auto row = selected.value("new_instance").toObject();
    observed = row.value("controls").toObject();
    expected = row.value("expected_revision");
  } else {
    for (const auto &entry : selected.value("instances").toArray()) {
      const auto row = entry.toObject();
      if (row.value("instance_id").toString() == instanceId &&
          !row.value("pending").toBool() && row.value("controls").isObject()) {
        target = {{"kind", "existing"}, {"instance_id", instanceId}};
        observed = row.value("controls").toObject();
        expected = row.value("expected_revision");
        break;
      }
    }
  }
  QJsonObject request{
      {"schema_version", 1},
      {"query_id", m_marketplaceTargetsQuery},
      {"extension_id", extensionId},
      {"release_id", releaseId},
      {"target", target},
      {"expected_revision", expected},
      {"controls", observed},
      {"mutation_id", QUuid::createUuid().toString(QUuid::WithoutBraces)}};
  if (direct) {
    request.remove("query_id");
    request.remove("extension_id");
    request.remove("release_id");
    request.insert("request_id",
                   QUuid::createUuid().toString(QUuid::WithoutBraces));
    request.insert("publication", m_marketplaceDirectPublication);
    request.insert(
        "accepted_reference",
        m_marketplaceDirectReference.value("reference_id").toString());
    request.insert("accept_unqualified", true);
  }
  if (!outboundStart(request)) {
    marketplaceInstallationMessage("Refresh and choose an available target "
                                   "with a name of at most 128 UTF-8 bytes.");
    return;
  }
  m_marketplaceOriginalStart = request;
  m_marketplaceOriginalAction = {};
  m_marketplaceActionOperation.clear();
  m_marketplaceInstallation.clear();
  m_marketplaceInstallationId.clear();
  sendOriginalMarketplaceStart();
}
void ApiClient::retryMarketplaceInstallationStart() {
  if (m_marketplaceInstallationLoading)
    return;
  if (!marketplaceOwner() || !outboundStart(m_marketplaceOriginalStart)) {
    marketplaceInstallationMessage(
        "Reconnect to the original operation before retrying.");
    return;
  }
  // No fresh target, changed query, replacement mutation or discovery request.
  sendOriginalMarketplaceStart();
}
void ApiClient::sendOriginalMarketplaceStart() {
  const auto epoch = m_marketplaceInstallationEpoch;
  m_marketplaceInstallationLoading = true;
  m_marketplaceInstallationNotice.clear();
  emit marketplaceInstallationChanged();
  sendRequest(
      "POST",
      m_marketplaceOriginalStart.contains("publication")
          ? installationsPath + "direct"
          : installationsPath.chopped(1),
      m_marketplaceOriginalStart,
      [this, epoch](const QJsonDocument &doc) {
        if (epoch != m_marketplaceInstallationEpoch)
          return;
        m_marketplaceInstallationLoading = false;
        if (!doc.isObject() ||
            !keys(doc.object(), {"schema_version", "operation_id"}) ||
            doc.object().value("schema_version").toDouble() != 1 ||
            !uuid(doc.object().value("operation_id"))) {
          failMarketplaceInstallationRead(
              "Start acknowledgement was not supported. Check the original "
              "operation before retrying.");
          return;
        }
        m_marketplaceInstallationId =
            doc.object().value("operation_id").toString();
        emit marketplaceInstallationChanged();
        pollMarketplaceInstallation();
      },
      [this, epoch](const QString &) {
        if (epoch == m_marketplaceInstallationEpoch)
          failMarketplaceInstallationRead(
              "Start was not confirmed. Check current status or retry the "
              "original request; it may already be running.");
      });
}
void ApiClient::approveMarketplaceInstallation(bool automaticUpdates) {
  const auto value = QJsonObject::fromVariantMap(m_marketplaceInstallation);
  if (!digest(value.value("review_id")) ||
      !revision(value.value("approval_revision")) ||
      value.value("approval_revision").toDouble() >= maxRevision) {
    marketplaceInstallationMessage(
        "Poll the original permission review before approving.");
    return;
  }
  if (!value.value("review")
           .toObject()
           .value("scope")
           .toObject()
           .value("secret_keys")
           .toArray()
           .isEmpty() &&
      !capabilities().contains("secrets_manage")) {
    marketplaceInstallationMessage(
        "Secret-management permission is required to approve this extension.");
    return;
  }
  sendMarketplaceInstallationAction(
      {{"action", "approve"},
       {"review_id", value.value("review_id")},
       {"expected_revision", value.value("approval_revision")},
       {"automatic_updates", automaticUpdates}});
}
void ApiClient::submitMarketplaceInstallationSetup(const QVariantMap &values) {
  if (!marketplaceActionAvailable("setup")) {
    marketplaceInstallationMessage(
        "Setup is not available. Poll the original operation.");
    return;
  }
  const auto scope = QJsonObject::fromVariantMap(m_marketplaceInstallation)
                         .value("review")
                         .toObject()
                         .value("scope")
                         .toObject();
  const auto names = scope.value("secret_keys").toArray();
  if (values.size() > 64 || names.size() > 64 ||
      (!names.isEmpty() && !capabilities().contains("secrets_manage"))) {
    marketplaceInstallationMessage(
        "Setup needs bounded inputs and current secret-management permission.");
    return;
  }
  QJsonArray changes;
  static const QRegularExpression keyPattern("^[A-Za-z0-9_.-]{1,64}$");
  for (auto it = values.begin(); it != values.end(); ++it) {
    if (!names.contains(it.key()) || !keyPattern.match(it.key()).hasMatch()) {
      marketplaceInstallationMessage(
          "A setup key is outside the original permission review.");
      return;
    }
    if (it.value().isNull())
      changes.append(QJsonObject{{"operation", "remove"}, {"key", it.key()}});
    else if (it.value().metaType().id() == QMetaType::QString &&
             it.value().toString().toUtf8().size() <= 65536)
      changes.append(QJsonObject{{"operation", "set"},
                                 {"key", it.key()},
                                 {"value", it.value().toString()},
                                 {"rotatable", false}});
    else {
      marketplaceInstallationMessage(
          "Each setup value must be a string of at most 64 KiB.");
      return;
    }
  }
  // Values exist only in the bounded outgoing request/normal auth retry. Never
  // in properties, settings, logs, history or an explicit-replay cache. This
  // does not promise secure erasure of Qt/network heap buffers.
  sendMarketplaceInstallationAction(
      {{"action", "setup"}, {"credentials", changes}});
}
void ApiClient::activateMarketplaceInstallation() {
  sendMarketplaceInstallationAction({{"action", "activate"}});
}
void ApiClient::cancelMarketplaceInstallation() {
  sendMarketplaceInstallationAction({{"action", "cancel"}});
}
void ApiClient::retryMarketplaceInstallationStage() {
  sendMarketplaceInstallationAction({{"action", "retry_stage"}});
}
void ApiClient::retryMarketplaceInstallationAction() {
  if (m_marketplaceInstallationLoading)
    return;
  if (m_marketplaceOriginalAction.value("action").toString() == "setup") {
    marketplaceInstallationMessage(
        "Check status, or re-enter the exact original setup values to retry. "
        "Secret values are not cached.");
    return;
  }
  if (m_marketplaceOriginalAction.isEmpty() ||
      m_marketplaceActionOperation != m_marketplaceInstallationId) {
    marketplaceInstallationMessage(
        "Reconnect to the original operation before retrying an action.");
    return;
  }
  sendMarketplaceInstallationAction(m_marketplaceOriginalAction, true);
}
void ApiClient::sendMarketplaceInstallationAction(QJsonObject request,
                                                  bool retry) {
  if (m_marketplaceInstallationLoading)
    return;
  const auto kind = request.value("action").toString();
  if (!marketplaceOwner() || !uuid(m_marketplaceInstallationId) ||
      !actionKinds.contains(kind) ||
      (!retry && !marketplaceActionAvailable(kind))) {
    marketplaceInstallationMessage(
        "This action is not currently available. Poll the original operation.");
    return;
  }
  if (!retry) {
    QJsonValue mutation;
    if (m_marketplaceActionOperation == m_marketplaceInstallationId &&
        m_marketplaceOriginalAction.value("action") ==
            request.value("action")) {
      auto prior = m_marketplaceOriginalAction;
      mutation = prior.take("mutation_id");
      if (kind != "setup" && prior != request) {
        marketplaceInstallationMessage(
            "Retry the original decision or cancel before changing its input.");
        return;
      }
    } else if (kind == "activate")
      mutation = QJsonValue::fromVariant(
          m_marketplaceInstallation.value("activation_request_id"));
    else if (kind == "cancel")
      mutation = QJsonValue::fromVariant(
          m_marketplaceInstallation.value("cancellation_request_id"));
    if (!uuid(mutation))
      mutation = QUuid::createUuid().toString(QUuid::WithoutBraces);
    request.insert("mutation_id", mutation);
  }
  const QJsonObject body{{"schema_version", 1}, {"request", request}};
  if (QJsonDocument(body).toJson().size() > 1024 * 1024) {
    marketplaceInstallationMessage("Setup exceeds the 1 MiB request bound.");
    return;
  }
  if (kind == "setup")
    m_marketplaceOriginalAction = {
        {"action", QStringLiteral("setup")},
        {"mutation_id", request.value("mutation_id").toString()}};
  else
    m_marketplaceOriginalAction = request;
  m_marketplaceActionOperation = m_marketplaceInstallationId;
  const auto epoch = m_marketplaceInstallationEpoch;
  const auto id = m_marketplaceInstallationId;
  const auto mutation = request.value("mutation_id");
  m_marketplaceInstallationLoading = true;
  m_marketplaceInstallationNotice.clear();
  m_marketplaceInstallation.insert("available_actions", QVariantList{});
  emit marketplaceInstallationChanged();
  sendRequest(
      "POST", installationsPath + id + "/actions", body,
      [this, epoch, id, kind, mutation](const QJsonDocument &doc) {
        if (epoch != m_marketplaceInstallationEpoch)
          return;
        m_marketplaceInstallationLoading = false;
        const auto value = doc.object();
        const auto acknowledged = value.value("receipt");
        if (!doc.isObject() ||
            !keys(value, {"schema_version", "operation_id", "receipt"}) ||
            value.value("schema_version").toDouble() != 1 ||
            value.value("operation_id").toString() != id ||
            !receipt(acknowledged) || !acknowledged.isObject() ||
            acknowledged.toObject().value("request_id") != mutation ||
            acknowledged.toObject().value("kind").toString() != kind) {
          failMarketplaceInstallationRead(
              "Action acknowledgement was not supported. Check the original "
              "operation before retrying.");
          return;
        }
        // A request acknowledgement is not an approval, activation or cleanup.
        emit marketplaceInstallationChanged();
        pollMarketplaceInstallation();
      },
      [this, epoch](const QString &) {
        if (epoch == m_marketplaceInstallationEpoch) {
          m_marketplaceInstallationLoading = false;
          marketplaceInstallationMessage(
              "Action was not confirmed. Check status or retry the original "
              "request; it may already have been handled.");
        }
      });
}
