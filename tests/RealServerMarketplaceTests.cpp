// Normal authenticated ApiClient + shipped QML over a real loopback socket.
// Only the explicitly owned protected fixture supplies input, through stdin.
// Simulated eligibility is NOT real billing, public serving or scale proof.
#include "backend/ApiClient.h"

#include <QColor>
#include <QCryptographicHash>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QImage>
#include <QJSValue>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeySequence>
#include <QLoggingCategory>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickView>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QScopedPointer>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QtQml>

#include <algorithm>
#include <cstdio>
#include <functional>

namespace {
bool until(const std::function<bool()> &predicate, int timeoutMs) {
  QElapsedTimer elapsed;
  elapsed.start();
  do {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    if (predicate())
      return true;
    QTest::qWait(10);
  } while (elapsed.elapsed() < timeoutMs);
  return predicate();
}

struct Sample {
  qint64 firstFrameMs = -1;
  qint64 readyMs = -1;
  qint64 localCompleteMs = -1;
  bool peersPendingAtLocalCompletion = false;
};
constexpr const char *installationShell = R"QML(
  import QtQuick 6.5
  import "qrc:/qml/views" as Views
  Flickable {
    id: viewport
    objectName: "installationQualificationScroll"
    clip: true; contentWidth: width; contentHeight: content.implicitHeight
    readonly property bool owner: apiClient.authToken !== ""
        && apiClient.homeRole === "owner" && apiClient.activeProfileType === "account"
        && ["extensions_manage","settings_manage","server_admin"].every(function(c) {
            return apiClient.capabilities.indexOf(c) >= 0
        })
    Column {
      id: content; width: parent.width; spacing: 12
      Views.MarketplaceDirectReferencePane {
        width: parent.width; canManage: viewport.owner; expanded: true
        onInspect: function(preview) { installation.inspectDirect(preview) }
      }
      Views.MarketplaceInstallationPane {
        id: installation; width: parent.width; canManage: viewport.owner
      }
    }
  }
)QML";
constexpr const char *catalogInstallationShell = R"QML(
  import QtQuick 6.5
  import "qrc:/qml/views" as Views
  Views.CommunityMarketplaceView { }
)QML";
constexpr const char *customerFirstRunShell = R"QML(
  import QtQuick 6.5
  import "qrc:/qml/views" as Views
  Flickable {
    clip:true;contentWidth:width;contentHeight:settings.implicitHeight
    Views.MarketplaceSettingsView {
      id:settings;width:parent.width;height:implicitHeight
      client:apiClient;setupMode:true;prepareBrowsing:true
    }
  }
)QML";
qint64 p95(QList<qint64> values) {
  std::sort(values.begin(), values.end());
  return values.at((values.size() * 95 + 99) / 100 - 1);
}

QQuickItem *visualItem(QQuickItem *root, const QString &name) {
  if (!root)
    return nullptr;
  if (root->objectName() == name)
    return root;
  for (auto *child : root->childItems())
    if (auto *found = visualItem(child, name))
      return found;
  return nullptr;
}

bool click(QQuickView &view, QQuickItem *item) {
  if (!item || !item->isVisible() || !item->isEnabled())
    return false;
  const QPoint point =
      item->mapToScene(QPointF(item->width() / 2, item->height() / 2))
          .toPoint();
  if (!QRect(QPoint(), view.size()).contains(point))
    return false;
  QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier, point, 0);
  return true;
}

// Require actual card geometry, text layout and nonuniform name-label pixels,
// not just a non-black window/background or a populated native model.
bool cardFrame(QQuickView &view, QObject *root, const QVariantList &checked,
               QImage *capture = nullptr) {
  auto *card =
      visualItem(qobject_cast<QQuickItem *>(root), "communityMarketplaceCard");
  if (!card || !card->isVisible() || card->width() < 96 || card->height() < 32)
    return false;
  const QRect region = card->mapRectToScene(card->boundingRect())
                           .toAlignedRect()
                           .intersected(QRect(QPoint(), view.size()));
  if (region.width() < 96 || region.height() < 32)
    return false;
  auto *name = visualItem(card, "communityCardName");
  if (!name || !name->isVisible() ||
      name->property("text").toString().isEmpty())
    return false;
  auto modelData = card->property("modelData");
  if (modelData.metaType() == QMetaType::fromType<QJSValue>())
    modelData = modelData.value<QJSValue>().toVariant();
  const auto painted = modelData.toMap();
  const bool current =
      std::any_of(checked.begin(), checked.end(), [&](const QVariant &value) {
        const auto row = value.toMap();
        return painted.value("extension_id") == row.value("extension_id") &&
               painted.value("release_id") == row.value("release_id") &&
               name->property("text") == row.value("name");
      });
  if (!current)
    return false;
  const QRect nameRegion = name->mapRectToScene(name->boundingRect())
                               .toAlignedRect()
                               .intersected(region);
  if (nameRegion.width() < 96 || nameRegion.height() < 8)
    return false;
  const QImage frame = view.grabWindow();
  if (frame.isNull())
    return false;
  const qreal ratio = frame.devicePixelRatio();
  const QImage pixels = frame
                            .copy(QRect(qRound(nameRegion.x() * ratio),
                                        qRound(nameRegion.y() * ratio),
                                        qRound(nameRegion.width() * ratio),
                                        qRound(nameRegion.height() * ratio)))
                            .convertToFormat(QImage::Format_RGB32);
  if (pixels.isNull())
    return false;
  const auto background = pixels.pixel(0, 0);
  bool different = false;
  for (int y = 0; y < pixels.height() && !different; y += 2)
    for (int x = 0; x < pixels.width(); x += 2)
      if (pixels.pixel(x, y) != background) {
        different = true;
        break;
      }
  if (different && capture)
    *capture = frame;
  return different;
}
} // namespace

class RealServerMarketplaceTests final : public QObject {
  Q_OBJECT
private:
  void readFixture(bool installation = false) {
    QFile input;
    QVERIFY(input.open(stdin, QIODevice::ReadOnly));
    QByteArray bytes;
    const int maximum = installation ? 160 * 1024 : 32768;
    while (bytes.size() <= maximum) {
      const auto chunk = input.read(maximum + 1 - bytes.size());
      if (chunk.isEmpty())
        break;
      bytes += chunk;
    }
    QVERIFY2(!bytes.isEmpty() && bytes.size() <= maximum,
             "bounded explicit fixture stdin required");
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(bytes, &error);
    QVERIFY(error.error == QJsonParseError::NoError && document.isObject());
    const auto data = document.object();
    QVERIFY(data.value("schema_version") == 1 &&
            data.value("fixture_only") == true);
    if (installation)
      QCOMPARE(data.value("purpose").toString(), QString("installation"));
    if (data.contains("provider_setup_required"))
      QVERIFY(data.value("provider_setup_required").isBool());
    QCOMPARE(data.value("provider_setup_required").toBool(), m_customerSetup);
    const QUrl url(data.value("server_url").toString());
    QVERIFY(url.scheme() == "http" && url.host() == "127.0.0.1" &&
            url.port() > 0 && url.userInfo().isEmpty() &&
            url.query().isEmpty() && url.fragment().isEmpty() &&
            url.path().isEmpty());
    m_url = url.toString();
    m_email = data.value("email").toString();
    QVERIFY(m_email.endsWith("@management.example.test") &&
            m_email.size() < 128);
    QVERIFY(data.value("password") == "fixture-password-only");
    const auto directory = data.value("capture_directory").toString();
    QVERIFY(QDir::isAbsolutePath(directory) && QFileInfo(directory).isDir());
    // macOS /var and /private/var may name the same owned temp directory.
    m_directory = QFileInfo(directory).canonicalFilePath();
    QVERIFY(!m_directory.isEmpty());
    const auto entries = data.value("expected").toArray();
    QCOMPARE(entries.size(), installation ? 1 : 20);
    const QRegularExpression idPattern(
        "^elx:[a-z2-7]{52}/[a-z0-9][a-z0-9-]{0,63}$");
    const QRegularExpression digestPattern("^sha256:[a-f0-9]{64}$");
    for (const auto &entry : entries) {
      const auto row = entry.toObject();
      const auto id = row.value("extension_id").toString();
      QVERIFY(idPattern.match(id).hasMatch() && !m_expected.contains(id));
      QVERIFY(
          digestPattern.match(row.value("release_id").toString()).hasMatch());
      m_expected.insert(id, row.value("release_id").toString());
    }
    m_name = entries.first().toObject().value("name").toString();
    m_exact = entries.first().toObject().value("extension_id").toString();
    if (data.contains("playback")) {
      const auto playback = data.value("playback").toObject();
      const QRegularExpression uuid("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$");
      m_playbackItem = playback.value("media_item_id").toString();
      m_playbackFile = playback.value("media_file_id").toString();
      QVERIFY(uuid.match(m_playbackItem).hasMatch() && uuid.match(m_playbackFile).hasMatch());
    }
    QVERIFY(
        QRegularExpression("^[A-Za-z0-9 ._-]{1,96}$").match(m_name).hasMatch());
    if (installation) {
      const auto updates = data.value("updates").toArray();
      QCOMPARE(updates.size(), 2);
      for (int n = 0; n < updates.size(); ++n) {
        const auto update = updates.at(n).toObject();
        const auto publication = update.value("publication").toObject();
        const auto release = publication.value("release").toObject()
                                 .value("payload").toObject();
        const auto id = update.value("release_id").toString();
        QVERIFY(digestPattern.match(id).hasMatch());
        QCOMPARE(release.value("extension_id").toString(), m_exact);
        QCOMPARE(release.value("version").toString(),
                 n == 0 ? QString("1.0.0") : QString("1.1.0"));
        QCOMPARE(publication.value("head").toObject().value("payload")
                     .toObject().value("stable_release_id").toString(), id);
        const auto text = QJsonDocument(publication).toJson(QJsonDocument::Compact);
        QVERIFY(!text.isEmpty() && text.size() <= 65536);
        m_publications.append(QString::fromUtf8(text));
        m_releases.append(id);
      }
      QCOMPARE(m_expected.value(m_exact), m_releases.first());
      QVERIFY(m_releases.first() != m_releases.last());
    }
    m_progress.setFileName(m_directory + "/progress.jsonl");
    QVERIFY(m_progress.open(QIODevice::WriteOnly | QIODevice::NewOnly));
    QVERIFY(m_progress.setPermissions(QFileDevice::ReadOwner |
                                      QFileDevice::WriteOwner));
    m_fixtureRead = true;
  }

private slots:
  void initTestCase() {
    QVERIFY(m_settings.isValid());
    QVERIFY(!QLoggingCategory::defaultCategory()->isInfoEnabled());
    QCoreApplication::setOrganizationName("ElixirMarketplaceFixture");
    QCoreApplication::setApplicationName("ProtectedDesktopQualification");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                       m_settings.path());
    QSettings().clear();
  }

  void packaged_views_have_no_authority_without_login() {
    ApiClient client;
    QQuickView view;
    view.setColor(QColor("#151515"));
    view.resize(1100, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty("apiClient", &client);
    view.setSource(QUrl("qrc:/qml/views/CommunityMarketplaceView.qml"));
    QVERIFY(view.status() == QQuickView::Ready && view.rootObject());
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    QVERIFY(!view.rootObject()->property("canManage").toBool());
    QVERIFY(client.marketplaceSearchResults().isEmpty());
    QVERIFY(!visualItem(view.rootObject(), "communityMarketplaceCard"));
    QVERIFY(!view.grabWindow().isNull());
    view.setSource(QUrl("qrc:/qml/views/MarketplaceBrowsePreparation.qml"));
    QVERIFY(view.status() == QQuickView::Ready && view.rootObject());
    QVERIFY(!view.rootObject()->property("active").toBool());
    QVERIFY(!view.rootObject()->property("connected").toBool());
    QVERIFY(!client.marketplaceSearchLoading());
    QQmlComponent installation(view.engine());
    installation.setData(installationShell, QUrl("qualification:/installation.qml"));
    QVERIFY(until([&] { return installation.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(installation.isReady(), qPrintable(installation.errorString()));
    auto *noAuthority = qobject_cast<QQuickItem *>(installation.create());
    QVERIFY(noAuthority);
    view.setContent(QUrl("qualification:/installation.qml"), &installation, noAuthority);
    QVERIFY(!noAuthority->property("owner").toBool());
    auto *direct = visualItem(noAuthority, "marketplaceDirectReferencePane");
    auto *pane = visualItem(noAuthority, "marketplaceInstallationPane");
    QVERIFY(direct && pane && !direct->isVisible() && !pane->isVisible());
    QVERIFY(!client.marketplaceInstallationLoading());
    QVERIFY(!client.marketplaceDirectReferenceLoading());
  }

  void acknowledged_approval_keeps_polling_until_setup_without_replaying_approval() {
    // Deterministic UI-only transition race: an accepted approval can precede
    // archiving/staging. No fake admission, permission commit or native pass.
    QQuickView view;
    view.resize(1100, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    QQmlComponent component(view.engine());
    component.setData(R"QML(
      import QtQuick 6.5
      import "qrc:/qml/views" as Views
      Item {
        id: root
        property int polls: 0
        property int approvals: 0
        QtObject {
          id: mock
          objectName: "approvalTransitionClient"
          property string authToken: ""
          property var capabilities: ["secrets_manage"]
          property bool marketplaceInstallationLoading: false
          property string marketplaceInstallationNotice: ""
          property bool marketplaceInstallationHasOriginalStart: false
          property bool marketplaceInstallationHasOriginalAction: false
          property var marketplaceInstallTargets: ({})
          property var marketplaceInstallation: ({
            operation_id: "00000000-0000-4000-8000-000000000001",
            phase: "awaiting_approval", available_actions: ["cancel", "approve"],
            latest_action: {kind:"approve", status:"acknowledged"},
            review: {scope:{secret_keys:[]}}
          })
          function approveMarketplaceInstallation() { root.approvals++ }
          function pollMarketplaceInstallation() {
            root.polls++
            if (root.polls === 2)
              marketplaceInstallation = ({
                operation_id: "00000000-0000-4000-8000-000000000001",
                phase: "awaiting_setup", available_actions: ["cancel", "setup"],
                latest_action: {kind:"approve", status:"acknowledged"},
                review: {scope:{secret_keys:[]}}
              })
          }
          signal sessionStateChanged()
        }
        Views.MarketplaceInstallationPane {
          width: parent.width; client: mock; canManage: true
        }
      }
    )QML", QUrl("qualification:/approval-transition.qml"));
    QVERIFY(until([&] { return component.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    auto *root = qobject_cast<QQuickItem *>(component.create());
    QVERIFY(root);
    view.setContent(QUrl("qualification:/approval-transition.qml"), &component, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *pane = visualItem(root, "marketplaceInstallationPane");
    auto *approve = visualItem(root, "marketplaceApproveInstallation");
    auto *automatic = visualItem(root, "marketplaceAutomaticUpdates");
    auto *timer = root->findChild<QObject *>("marketplaceInstallationPollTimer");
    auto *client = root->findChild<QObject *>("approvalTransitionClient");
    QVERIFY(pane && approve && automatic && timer && client);
    QVERIFY(pane->property("approvalAcknowledged").toBool());
    QVERIFY(!approve->isEnabled() && !automatic->isEnabled());
    QVERIFY(!automatic->property("checked").toBool());
    QVERIFY(timer->property("running").toBool());
    QVERIFY(until([&] { return root->property("polls").toInt() == 2
        && !timer->property("running").toBool(); }, 4500));
    QCOMPARE(root->property("approvals").toInt(), 0);
    const auto setState = [&](const QString &phase, const QString &kind, const QString &status) {
      return client->setProperty("marketplaceInstallation", QVariantMap{
        {"operation_id", "00000000-0000-4000-8000-000000000001"}, {"phase", phase},
        {"available_actions", QStringList{"cancel", "approve"}},
        {"latest_action", QVariantMap{{"kind", kind}, {"status", status}}},
        {"review", QVariantMap{{"scope", QVariantMap{{"secret_keys", QStringList{}}}}}}});
    };
    QVERIFY(setState("awaiting_approval", "approve", "rejected"));
    QVERIFY(!pane->property("approvalAcknowledged").toBool());
    QVERIFY(!timer->property("running").toBool());
    QVERIFY(setState("awaiting_approval", "setup", "acknowledged"));
    QVERIFY(!timer->property("running").toBool());
    QVERIFY(setState("awaiting_setup", "approve", "acknowledged"));
    QVERIFY(!timer->property("running").toBool());
    QVERIFY(setState("awaiting_approval", "approve", "acknowledged"));
    QVERIFY(timer->property("running").toBool());
    QVERIFY(pane->setProperty("canManage", false));
    QVERIFY(!timer->property("running").toBool());
    QCOMPARE(root->property("approvals").toInt(), 0);
  }

  void visual_lookup_does_not_depend_on_qobject_ownership() {
    QQuickItem root;
    QQuickItem delegate;
    delegate.setObjectName("delegate");
    delegate.setParentItem(&root);
    QVERIFY(delegate.parent() == nullptr);
    QVERIFY(root.findChild<QQuickItem *>("delegate") == nullptr);
    QCOMPARE(visualItem(&root, "delegate"), &delegate);
    QVERIFY(visualItem(&root, "absent") == nullptr);
  }

  void keyboard_input_replaces_existing_text() {
    QQuickView view;
    view.setColor(QColor("#151515"));
    view.resize(640, 160);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    QQmlComponent component(view.engine());
    component.setData("import QtQuick 6.5\nimport QtQuick.Controls "
                      "6.5\nTextField { text: 'prior text' }",
                      QUrl("qualification:/keyboard.qml"));
    QVERIFY(until([&] { return component.status() != QQmlComponent::Loading; },
                  5000));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    auto *field = qobject_cast<QQuickItem *>(component.create());
    QVERIFY(field);
    view.setContent(QUrl("qualification:/keyboard.qml"), &component, field);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    qint64 frame = -1;
    for (const auto &text : {QString("Elixir Cold-Page Fixture 01"),
                             QString("elx:example/cold-page-01"), QString()}) {
      QVERIFY(type(view, field, text, frame));
      QVERIFY(frame >= 0);
    }
  }

  void developer_reference_paste_and_click_reaches_the_shipped_handler() {
    // UI geometry/dispatch regression only. No fake signature, network,
    // eligibility, preview or successful installation is claimed here.
    QQuickView view;
    view.resize(1100, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    QQmlComponent component(view.engine());
    component.setData(R"QML(
      import QtQuick 6.5
      import "qrc:/qml/views" as Views
      Item {
        id: root
        property int calls: 0
        property string pasted: ""
        QtObject {
          id: mock
          property var marketplaceDirectReference: ({})
          property bool marketplaceDirectReferenceLoading: false
          function clearMarketplaceDirectReference() { marketplaceDirectReference = ({}) }
          function previewMarketplaceDirectReference(text) { root.calls++; root.pasted = text }
        }
        Views.MarketplaceDirectReferencePane {
          width: parent.width; client: mock; canManage: true; expanded: true
        }
      }
    )QML", QUrl("qualification:/reference-dispatch.qml"));
    QVERIFY(until([&] { return component.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    auto *root = qobject_cast<QQuickItem *>(component.create());
    QVERIFY(root);
    view.setContent(QUrl("qualification:/reference-dispatch.qml"), &component, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *reference = visualItem(root, "marketplaceDeveloperReferenceText");
    QVERIFY(reference);
    int expected = 0;
    for (int length : {256, 20000}) {
      const auto pasted = QString("{\"synthetic_ui_dispatch_only\":\"")
          + QString(length, 'x') + "\"}";
      QVERIFY(reference->setProperty("text", pasted));
      QVERIFY(installationClick(view, root, "marketplaceCheckDeveloperReference"));
      ++expected;
      QVERIFY(until([&] { return root->property("calls").toInt() == expected; }, 1000));
      QCOMPARE(root->property("pasted").toString(), pasted);
    }
  }

  void scrolling_installation_shell_paste_reaches_the_real_request_handler() {
    // Exercise the SAME scrolling layout and real ApiClient as the failed live
    // case. No base URL: reaching dispatch must fail locally, never issue HTTP
    // or imply a valid signed preview or an installation.
    ApiClient client;
    client.setAuthToken("offline-ui-dispatch-only");
    client.setSessionState({{"session_id", "00000000-0000-4000-8000-000000000001"},
        {"home_id", "00000000-0000-4000-8000-000000000002"},
        {"active_profile_id", "00000000-0000-4000-8000-000000000003"},
        {"active_profile_type", "account"}, {"role", "owner"},
        {"capabilities", QStringList{"extensions_manage", "settings_manage", "server_admin"}}});
    QQuickView view;
    view.resize(1100, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty("apiClient", &client);
    QQmlComponent component(view.engine());
    component.setData(installationShell, QUrl("qualification:/scrolling-reference-dispatch.qml"));
    QVERIFY(until([&] { return component.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    auto *root = qobject_cast<QQuickItem *>(component.create());
    QVERIFY(root);
    view.setContent(QUrl("qualification:/scrolling-reference-dispatch.qml"), &component, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    QVERIFY(root->property("owner").toBool());
    auto *reference = visualItem(root, "marketplaceDeveloperReferenceText");
    QVERIFY(reference);
    QSignalSpy failed(&client, &ApiClient::requestFailedDetailed);
    int expected = 0;
    for (int length : {256, 20000}) {
      const auto pasted = QString::fromUtf8(QJsonDocument(QJsonObject{
          {"schema_version", 1}, {"publisher", QJsonObject{}}, {"head", QJsonObject{}},
          {"release", QJsonObject{{"synthetic_ui_dispatch_only", QString(length, 'x')}}}})
          .toJson(QJsonDocument::Compact));
      QVERIFY(reference->setProperty("text", pasted));
      QVERIFY(installationClick(view, root, "marketplaceCheckDeveloperReference"));
      ++expected;
      QVERIFY(until([&] { return failed.count() == expected; }, 1000));
      const auto error = failed.last();
      QCOMPARE(error.at(0).toString(), QString("/api/v1/marketplace/import"));
      QCOMPARE(error.at(1).toMap().value("code").toString(), QString("base_url_missing"));
      QVERIFY(!client.marketplaceDirectReferenceLoading());
      QVERIFY(client.marketplaceDirectReference().isEmpty());
    }
  }

  void free_provider_ui_requires_a_separate_explicit_consent_click() {
    QQuickView view;
    view.resize(700, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    QQmlComponent component(view.engine());
    component.setData(R"QML(
      import QtQuick 6.5
      import "qrc:/qml/views" as Views
      Item {
        id: root
        property int calls: 0
        property bool selected: false
        property string version: ""
        QtObject {
          id: mock
          property string authToken: "synthetic-layout-only"
          property string homeRole: "owner"
          property string activeProfileType: "account"
          property var capabilities: ["extensions_manage","settings_manage","server_admin","secrets_manage"]
          property bool marketplaceSettingsLoading: false
          property bool marketplaceConnectionSaving: false
          property string marketplaceConnectionNotice: ""
          property var marketplaceSettings: ({
            settings:{revision:1,preferences:{schema_version:1,contribution:"off",metering:"unknown",
              contribution_disclosure_version:null,paid_support_consent:false,issuer_disclosure_version:null}},
            runtime_fresh:true,runtime_status:"not_connected",contribution_disclosure_version:1,issuer_disclosure_version:1,
            contribution_disclosure:"Synthetic layout only",issuer_disclosure:"Synthetic layout only",
            startup:{configured:true,retry_owner_present:true,retry_after_seconds:null},
            provider_setup:{schema_version:1,revision:0,enabled:false,consent_current:false,consent_version:"elixir-marketplace-warp-v1"}})
          property var marketplaceSearch: ({})
          property bool marketplaceSearchLoading: false
          property var marketplaceSearchResults: []
          property int marketplaceSearchAvailableCount: 0
          signal sessionStateChanged()
          signal marketplaceSettingsSaved()
          signal requestFailed(string endpoint, string error)
          function pollMarketplaceSettings() {}
          function saveMarketplaceProviderSetup(enabled, version) { root.calls++;root.selected=enabled;root.version=version }
        }
        Flickable {
          anchors.fill:parent;contentHeight:settings.implicitHeight;clip:true
          Views.MarketplaceSettingsView {
            id:settings;width:parent.width;height:implicitHeight
            client:mock;setupMode:true;prepareBrowsing:false;manageInitialLoad:false
          }
        }
      }
    )QML", QUrl("qualification:/provider-consent.qml"));
    QVERIFY(until([&] { return component.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    auto *root = qobject_cast<QQuickItem *>(component.create());
    QVERIFY(root);
    view.setContent(QUrl("qualification:/provider-consent.qml"), &component, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *consent = visualItem(root, "marketplaceProviderConsent");
    auto *enable = visualItem(root, "marketplaceProviderEnable");
    QVERIFY(consent && enable && consent->isVisible());
    QVERIFY(!consent->property("checked").toBool() && !enable->isEnabled());
    QCOMPARE(root->property("calls").toInt(), 0);
    QVERIFY(installationClick(view, root, "marketplaceProviderConsent"));
    QVERIFY(until([&] { return enable->isEnabled(); }, 1000));
    QVERIFY(installationClick(view, root, "marketplaceProviderEnable"));
    QCOMPARE(root->property("calls").toInt(), 1);
    QVERIFY(root->property("selected").toBool());
    QCOMPARE(root->property("version").toString(), QString("elixir-marketplace-warp-v1"));
    QVERIFY(!consent->property("checked").toBool());
    QVERIFY(!enable->isEnabled());
  }

  void local_empty_progress_keeps_peer_lookup_nonfinal_and_inputs_responsive() {
    // Presentation only. No actual principal, source, eligibility or native
    // transport is supplied by this synthetic view model.
    QQuickView view;
    view.resize(1100, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    QQmlComponent component(view.engine());
    component.setData(R"QML(
      import QtQuick 6.5
      import "qrc:/qml/views" as Views
      Item {
        id: root
        property alias response: mock.marketplaceSearch
        QtObject {
          id: mock
          property string authToken: "synthetic-presentation-only"
          property string homeRole: "owner"
          property string activeProfileType: "account"
          property var capabilities: ["extensions_manage","settings_manage","server_admin"]
          property bool marketplaceSearchLoading: false
          property bool marketplaceSettingsLoading: false
          property var marketplaceSettings: ({})
          property var marketplaceSearch: ({phase:"checking",query_id:"presentation-only",
            query:{text:"",tags:[],limit:20},local_page_complete:false,searching_peers:false,
            network_complete:false})
          property int marketplaceSearchAvailableCount: 0
          property var marketplaceSearchResults: []
          property bool marketplaceInstallationLoading: false
          property var marketplaceInstallation: ({})
          property var marketplaceInstallTargets: ({})
          property string marketplaceInstallationNotice: ""
          property var marketplaceDirectReference: ({})
          property bool marketplaceDirectReferenceLoading: false
          function pollMarketplaceSettings() {}
          function pollMarketplaceSearch() {}
          function acceptMarketplaceSearchResults() {}
          function clearMarketplaceSearch() {}
          function fetchCurrentMarketplaceInstallation() {}
          function clearMarketplaceDirectReference() {}
        }
        Views.CommunityMarketplaceView { anchors.fill:parent; client:mock }
      }
    )QML", QUrl("qualification:/local-empty-progress.qml"));
    QVERIFY(until([&] { return component.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    auto *root = qobject_cast<QQuickItem *>(component.create());
    QVERIFY(root);
    view.setContent(QUrl("qualification:/local-empty-progress.qml"), &component, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *community = visualItem(root, "communityMarketplaceView");
    auto *activity = visualItem(root, "communitySearchActivity");
    auto *notice = visualItem(root, "communitySearchNotice");
    auto *field = visualItem(root, "communitySearchText");
    auto *tag = visualItem(root, "communityTag_live");
    QVERIFY(community && activity && notice && field && tag);
    QVERIFY(activity->property("running").toBool());
    auto responseValue = root->property("response");
    if (responseValue.metaType() == QMetaType::fromType<QJSValue>())
      responseValue = responseValue.value<QJSValue>().toVariant();
    auto response = responseValue.toMap();
    QVERIFY(!response.isEmpty());
    response["local_page_complete"] = true;
    response["searching_peers"] = true;
    QVERIFY(root->setProperty("response", response));
    QVERIFY(until([&] { return community->property("localSearchComplete").toBool()
      && !activity->property("running").toBool(); }, 1000));
    QVERIFY(notice->property("text").toString().contains("No checked local matches"));
    QVERIFY(notice->property("text").toString().contains("background"));
    QVERIFY(field->isEnabled() && tag->isEnabled());
    QVERIFY(!visualItem(root, "communityMarketplaceCard"));
    response["phase"] = "unavailable";
    QVERIFY(root->setProperty("response", response));
    QVERIFY(until([&] { return notice->property("text").toString().contains("unavailable"); }, 1000));
    response["phase"] = "checking";
    response["query_id"] = "replacement-presentation-only";
    response["local_page_complete"] = false;
    response["searching_peers"] = false;
    QVERIFY(root->setProperty("response", response));
    QVERIFY(until([&] { return !community->property("localSearchComplete").toBool()
      && activity->property("running").toBool(); }, 1000));
  }

  void catalog_card_scroll_dispatches_without_a_developer_reference() {
    // Geometry/dispatch only, with synthetic presentation data. No real
    // principal, signature, eligibility, network or installation is asserted.
    QQuickView view;
    view.resize(1100, 260);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    QQmlComponent component(view.engine());
    component.setData(R"QML(
      import QtQuick 6.5
      import "qrc:/qml/views" as Views
      Item {
        id: root
        property int calls: 0
        property int directCalls: 0
        property string chosen: ""
        QtObject {
          id: mock
          property string authToken: "synthetic-layout-only"
          property string homeRole: "owner"
          property string activeProfileType: "account"
          property var capabilities: ["extensions_manage","settings_manage","server_admin"]
          property bool marketplaceSearchLoading: false
          property bool marketplaceSettingsLoading: false
          property var marketplaceSettings: ({})
          property var marketplaceSearch: ({phase:"ready",query_id:"layout-only",query:{text:"",tags:[],limit:20}})
          property int marketplaceSearchAvailableCount: 1
          property var marketplaceSearchResults: [{extension_id:"synthetic-layout-only",release_id:"layout-release",
            name:"Synthetic layout only",publisher:"Layout",version:"1",media_tags:["live"],
            description:"Long layout content. ".repeat(180),support:{verified_supporters:0,weighted_score:0}}]
          property bool marketplaceInstallationLoading: false
          property var marketplaceInstallation: ({})
          property var marketplaceInstallTargets: ({})
          property string marketplaceInstallationNotice: ""
          property var marketplaceDirectReference: ({})
          property bool marketplaceDirectReferenceLoading: false
          function pollMarketplaceSettings() {}
          function pollMarketplaceSearch() {}
          function acceptMarketplaceSearchResults() {}
          function clearMarketplaceSearch() {}
          function fetchCurrentMarketplaceInstallation() {}
          function clearMarketplaceDirectReference() {}
          function fetchMarketplaceInstallTargets(id) { root.calls++; root.chosen=id }
          function previewMarketplaceDirectReference(text) { root.directCalls++ }
        }
        Views.CommunityMarketplaceView { anchors.fill:parent; client:mock }
      }
    )QML", QUrl("qualification:/catalog-scroll-dispatch.qml"));
    QVERIFY(until([&] { return component.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    auto *root = qobject_cast<QQuickItem *>(component.create());
    QVERIFY(root);
    view.setContent(QUrl("qualification:/catalog-scroll-dispatch.qml"), &component, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *button = visualItem(root, "communityReviewInstallation");
    QVERIFY(button && button->mapRectToScene(button->boundingRect()).bottom() > view.height());
    QVERIFY(installationClick(view, root, "communityReviewInstallation"));
    QVERIFY(until([&] { return root->property("calls").toInt() == 1; }, 1000));
    QCOMPARE(root->property("chosen").toString(), QString("synthetic-layout-only"));
    QCOMPARE(root->property("directCalls").toInt(), 0);
  }

  void protected_setup_search_render_and_replacement() {
    readFixture();
    if (!m_fixtureRead)
      return; // Preserve the original input assertion.
    ApiClient client;
    client.setBaseUrl(m_url);
    QSignalSpy loggedIn(&client, &ApiClient::loginSucceeded);
    QSignalSpy loginFailed(&client, &ApiClient::loginFailed);
    QVERIFY(progress("login_started"));
    client.login(m_email, QStringLiteral("fixture-password-only"));
    QVERIFY(
        until([&] { return loggedIn.count() == 1 || !loginFailed.isEmpty(); },
              15000));
    QCOMPARE(loggedIn.count(), 1);
    QCOMPARE(loginFailed.count(), 0);
    QCOMPARE(client.homeRole(), QStringLiteral("owner"));
    QCOMPARE(client.activeProfileType(), QStringLiteral("account"));
    for (const auto &cap :
         {"extensions_manage", "settings_manage", "server_admin"})
      QVERIFY(client.capabilities().contains(QString::fromLatin1(cap)));
    QVERIFY(!client.authToken().isEmpty());
    QVERIFY(progress("login_confirmed"));

    QQuickView view;
    view.setColor(QColor("#151515"));
    view.resize(1100, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty("apiClient", &client);
    QQmlComponent shell(view.engine());
    shell.setData(R"QML(
            import QtQuick 6.5
            import "qrc:/qml/views" as Views
            Item {
                id: root
                property bool browsing: false
                readonly property bool owner: apiClient.authToken !== ""
                    && apiClient.homeRole === "owner" && apiClient.activeProfileType === "account"
                    && ["extensions_manage","settings_manage","server_admin"].every(function(c) {
                        return apiClient.capabilities.indexOf(c) >= 0
                    })
                Views.MarketplaceBrowsePreparation {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    client: apiClient; allowed: root.owner && !root.browsing
                    fullCatalog: true; snapshot: apiClient.marketplaceSettings
                }
                Loader {
                    anchors.fill: parent; active: root.browsing
                    sourceComponent: Component { Views.CommunityMarketplaceView { client: apiClient } }
                }
                Timer {
                    interval: 5000; repeat: true
                    running: !root.browsing && root.owner && Qt.application.state === Qt.ApplicationActive
                    onTriggered: apiClient.pollMarketplaceSettings()
                }
                Component.onCompleted: apiClient.pollMarketplaceSettings()
            }
        )QML",
                  QUrl("qualification:/marketplace-shell.qml"));
    // Inline components may still be importing local QML modules here.
    // Loading is not an error and cannot be treated as a ready component.
    QVERIFY(
        until([&] { return shell.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(shell.isReady(), qPrintable(shell.errorString()));
    QObject *root = shell.create();
    QVERIFY2(root, qPrintable(shell.errorString()));
    view.setContent(QUrl("qualification:/marketplace-shell.qml"), &shell, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    QVERIFY(QGuiApplication::applicationState() == Qt::ApplicationActive);
    auto *preparation = visualItem(qobject_cast<QQuickItem *>(root),
                                   "marketplaceBrowsePreparation");
    QVERIFY(preparation);
    QElapsedTimer setup;
    setup.start();
    QVERIFY(progress("setup_started"));
    qint64 setupFirstData = -1;
    bool bad = false;
    QVERIFY(until(
        [&] {
          const auto response = client.marketplaceSearch();
          const auto phase = response.value("phase").toString();
          bad = phase == "unavailable" || phase == "stale" ||
                preparation->property("terminalConnection").toBool();
          if (setupFirstData < 0 &&
              !client.marketplaceSearchResults().isEmpty())
            setupFirstData = setup.elapsed();
          return bad || preparation->property("firstResultsReady").toBool();
        },
        180000));
    if (bad)
      QVERIFY(progress("setup_unavailable"));
    QVERIFY2(!bad, "actual protected connection or setup checks failed");
    const auto setupReady = setup.elapsed();
    QVERIFY(progress("setup_ready", -1, setupFirstData, setupReady));
    QVERIFY(setupFirstData >= 0 && checkedCards(client));
    QVERIFY(preparation && preparation->property("firstPage").toBool());
    const auto preparedQuery =
        client.marketplaceSearch().value("query_id").toString();
    QVERIFY(!preparedQuery.isEmpty());
    QElapsedTimer handoff;
    handoff.start();
    QVERIFY(root->setProperty("browsing", true));
    QImage initialFrame;
    const bool painted = until(
        [&] {
          return cardFrame(view, root, client.marketplaceSearchResults(),
                           &initialFrame);
        },
        10000);
    QJsonObject paintDiagnostic;
    if (!painted) {
      auto *card = visualItem(qobject_cast<QQuickItem *>(root),
                              "communityMarketplaceCard");
      auto *label = visualItem(card, "communityCardName");
      const auto point = card ? card->mapToScene(QPointF()) : QPointF();
      paintDiagnostic = {
          {"checked_rows", client.marketplaceSearchResults().size()},
          {"visual_card", card != nullptr},
          {"visual_label", label != nullptr},
          {"card_visible", card && card->isVisible()},
          {"card_x", point.x()},
          {"card_y", point.y()},
          {"card_width", card ? card->width() : 0},
          {"card_height", card ? card->height() : 0},
          {"window_width", view.width()},
          {"window_height", view.height()}};
      view.grabWindow().save(m_directory + "/handoff-failed.png");
    }
    QVERIFY2(
        painted,
        qPrintable(
            QJsonDocument(paintDiagnostic).toJson(QJsonDocument::Compact)));
    const auto handoffFrameMs = handoff.elapsed();
    QVERIFY(progress("handoff_frame", -1, handoffFrameMs));
    QCOMPARE(client.marketplaceSearch().value("query_id").toString(),
             preparedQuery);
    QVERIFY(initialFrame.save(m_directory + "/prepared-first-card.png"));
    auto *community = visualItem(qobject_cast<QQuickItem *>(root),
                                 "communityMarketplaceView");
    QVERIFY(community && community->property("viewActive").toBool());
    auto *visualRoot = qobject_cast<QQuickItem *>(root);
    auto *field = visualItem(visualRoot, "communitySearchText");
    auto *button = visualItem(visualRoot, "communitySearchButton");
    auto *movies = visualItem(visualRoot, "communityTag_movies");
    auto *live = visualItem(visualRoot, "communityTag_live");
    QVERIFY(field && button && movies && live);

    // First usable results do not mean the whole twenty-row page is warm.
    // Keep that remaining work visible and out of the warm-query samples.
    QVERIFY(progress("remaining_page_started"));
    QVERIFY(until(
        [&] {
          return client.marketplaceSearch().value("phase").toString() ==
                     "ready" &&
                 !client.marketplaceSearchLoading() &&
                 client.marketplaceSearchResults().size() == 20;
        },
        180000));
    QVERIFY(checkedCards(client));
    QCOMPARE(client.marketplaceSearch().value("query_id").toString(),
             preparedQuery);
    QVERIFY(progress("remaining_page_ready", -1, -1, setup.elapsed()));

    QList<qint64> firstFrames, fullQueries;
    for (int n = 0; n < 32; ++n) {
      Sample sample;
      QVERIFY(progress("warm_started", n));
      QVERIFY(measure(
          client, view, root, [&] { return click(view, button); }, "", {}, 20,
          sample, "warm"));
      QVERIFY(sample.firstFrameMs >= 0);
      firstFrames.append(sample.firstFrameMs);
      fullQueries.append(sample.readyMs);
      QVERIFY(progress("warm_ready", n, sample.firstFrameMs, sample.readyMs));
    }
    if (!m_playbackItem.isEmpty())
      QVERIFY2(exercisePlayback(client, view, root, button, live, field),
               "actual baseline/loaded playback or marketplace interaction failed");
    Sample filter;
    QVERIFY(progress("live_filter_started"));
    QVERIFY(measure(
        client, view, root, [&] { return click(view, live); }, "", {"live"}, 20,
        filter));
    Sample text;
    QVERIFY(progress("text_started", -1, filter.firstFrameMs, filter.readyMs));
    qint64 typingFrameMs = -1;
    QVERIFY(measure(
        client, view, root,
        [&] { return type(view, field, m_name, typingFrameMs); }, m_name,
        {"live"}, 1, text));
    Sample exact;
    QVERIFY(progress("exact_started", -1, text.firstFrameMs, text.readyMs));
    qint64 exactTypingFrameMs = -1;
    QVERIFY(measure(
        client, view, root,
        [&] { return type(view, field, m_exact, exactTypingFrameMs); }, m_exact,
        {"live"}, 1, exact));
    Sample empty;
    QVERIFY(progress("empty_filter_started", -1, exact.firstFrameMs,
                     exact.readyMs));
    qint64 clearFrameMs = -1;
    QVERIFY(measure(
        client, view, root,
        [&] {
          return type(view, field, "", clearFrameMs) && click(view, movies);
        },
        "", {"movies"}, 0, empty));

    // A real pending peer search must not disable input or wait out its
    // discovery deadline before a replacement query can be submitted.
    QVERIFY(progress("pending_search_started", -1, -1, empty.readyMs));
    QVERIFY(click(view, button));
    QVERIFY(until(
        [&] {
          return client.marketplaceSearch().value("searching_peers").toBool();
        },
        15000));
    QVERIFY(field->isEnabled() && live->isEnabled());
    Sample replacement;
    QVERIFY(progress("replacement_started"));
    qint64 pendingTypingFrameMs = -1;
    QVERIFY(measure(
        client, view, root,
        [&] {
          return type(view, field, m_name, pendingTypingFrameMs) &&
                 click(view, live);
        },
        m_name, {"live"}, 1, replacement));
    QVERIFY(checkedCards(client));
    QImage finalFrame;
    QVERIFY(
        cardFrame(view, root, client.marketplaceSearchResults(), &finalFrame));
    QVERIFY(finalFrame.save(m_directory + "/replacement-first-card.png"));
    QVERIFY(progress("complete", -1, replacement.firstFrameMs,
                     replacement.readyMs));

    const auto firstP95 = p95(firstFrames), readyP95 = p95(fullQueries);
    const QJsonObject result{
        {"schema_version", 1},
        {"stage", "protected_desktop_result"},
        {"fixture_only", true},
        {"real_http", true},
        {"normal_login", true},
        {"packaged_qml", true},
        {"software_renderer", true},
        {"catalog_rows", 20},
        {"warm_samples", 32},
        {"setup_first_checked_data_ms", setupFirstData},
        {"setup_ready_ms", setupReady},
        {"setup_to_first_card_frame_ms", handoffFrameMs},
        {"warm_first_card_p95_ms", firstP95},
        {"warm_full_search_p95_ms", readyP95},
        {"live_filter_first_card_ms", filter.firstFrameMs},
        {"live_filter_ready_ms", filter.readyMs},
        {"text_ready_ms", text.readyMs},
        {"exact_ready_ms", exact.readyMs},
        {"empty_filter_ready_ms", empty.readyMs},
        {"pending_replacement_ready_ms", replacement.readyMs},
        {"typing_frame_ms", typingFrameMs},
        {"pending_typing_frame_ms", pendingTypingFrameMs},
        {"warm_first_card_1s_budget_met", firstP95 <= 1000},
        {"warm_200ms_budget_met",
         readyP95 <= 200 && filter.readyMs <= 200 && text.readyMs <= 200 &&
             exact.readyMs <= 200 && empty.readyMs <= 200},
        {"simulated_support_only", true},
        {"real_paid_credentials", 0},
        {"excludes",
         "full app navigation, physical display latency, playback, peer "
         "package transfer, real billing, 10k catalog and soak"}};
    std::fprintf(
        stdout, "ELIXIR_MARKETPLACE_DESKTOP_RESULT %s\n",
        QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
    // Keep the native parent's exact existing result contract. The local-only
    // milestone is a separate bounded diagnostic, never a faster substitute
    // for the original full-query timing or its honest budget flags above.
    const QJsonObject localProgress{
        {"schema_version", 1}, {"fixture_only", true},
        {"scope", "ordinary_local_search_only"},
        {"empty_filter_local_complete_ms", empty.localCompleteMs},
        {"empty_filter_peers_pending_at_local_completion", empty.peersPendingAtLocalCompletion},
        {"empty_filter_peer_lookup_ready_ms", empty.readyMs},
        {"network_complete", false}};
    std::fprintf(stdout, "ELIXIR_MARKETPLACE_LOCAL_QUERY_PROGRESS_RESULT %s\n",
        QJsonDocument(localProgress).toJson(QJsonDocument::Compact).constData());
    std::fflush(stdout);
    client.clearMarketplaceSearch();
  }

  void protected_customer_first_run_and_catalog_install_update() {
    if (!QCoreApplication::arguments().contains(
            QStringLiteral("protected_customer_first_run_and_catalog_install_update")))
      QSKIP("explicit fresh customer setup fixture and function selection required");
    m_customerSetup = true;
    m_catalogInstallation = true;
    protected_install_and_manual_update_controls();
    m_catalogInstallation = false;
    m_customerSetup = false;
  }

  void protected_catalog_install_and_manual_update_controls() {
    if (!QCoreApplication::arguments().contains(
            QStringLiteral("protected_catalog_install_and_manual_update_controls")))
      QSKIP("explicit catalog installation fixture and function selection required");
    m_catalogInstallation = true;
    protected_install_and_manual_update_controls();
    m_catalogInstallation = false;
  }

  void protected_install_and_manual_update_controls() {
    // Never consume the cold-page fixture a second time in an ordinary run.
    // This case requires its own explicit selection and fresh owned stdin.
    if (!QCoreApplication::arguments().contains(
            QStringLiteral("protected_install_and_manual_update_controls"))
        && !(m_catalogInstallation && QCoreApplication::arguments().contains(
            QStringLiteral("protected_catalog_install_and_manual_update_controls")))
        && !(m_customerSetup && QCoreApplication::arguments().contains(
            QStringLiteral("protected_customer_first_run_and_catalog_install_update"))))
      QSKIP("explicit installation fixture and function selection required");
    readFixture(true);
    if (!m_fixtureRead)
      return;
    ApiClient client;
    client.setBaseUrl(m_url);
    QSignalSpy loggedIn(&client, &ApiClient::loginSucceeded);
    QSignalSpy loginFailed(&client, &ApiClient::loginFailed);
    client.login(m_email, QStringLiteral("fixture-password-only"));
    QVERIFY(until([&] { return !loggedIn.isEmpty() || !loginFailed.isEmpty(); }, 15000));
    QCOMPARE(loggedIn.count(), 1);
    QVERIFY(loginFailed.isEmpty());
    QCOMPARE(client.homeRole(), QString("owner"));
    QCOMPARE(client.activeProfileType(), QString("account"));

    QElapsedTimer original;
    original.start();
    const auto remaining = [&] { return int(std::max<qint64>(0, 18 * 60 * 1000 - original.elapsed())); };
    if (m_customerSetup) {
      prepareCustomerProvider(client, std::min(600000, remaining()));
      QVERIFY(m_customerPrepared);
      QCOMPARE(client.marketplaceSearch().value("query_id").toString(),
               m_customerPreparedQuery);
    } else {
      // This entry point starts without a prepared setup page.
      client.startMarketplaceSearch(m_exact, {});
      qint64 nextPoll = 0;
      bool sourceFailed = false;
      QVERIFY(until([&] {
        const auto phase = client.marketplaceSearch().value("phase").toString();
        sourceFailed = phase == "unavailable" || phase == "stale";
        if (sourceFailed || (phase == "ready" && !client.marketplaceSearchLoading()))
          return true;
        if (original.elapsed() >= nextPoll && !client.marketplaceSearchLoading()) {
          nextPoll = original.elapsed() + 1000;
          client.pollMarketplaceSearch();
        }
        return false;
      }, std::min(600000, remaining())));
      QVERIFY(!sourceFailed && checkedCards(client));
    }
    QCOMPARE(client.marketplaceSearchResults().size(), 1);
    QVERIFY(progress("installation_first_card_verified"));
    bool setupQueryReplaced = false;
    bool reusedPreparedQuery = false;
    const auto watchSetup = connect(&client, &ApiClient::marketplaceSearchChanged, &client, [&] {
      // Expiry hides the ID in the stale presentation; that is not a new
      // search and does not undo an already accepted installation request.
      const auto queryId = client.marketplaceSearch().value("query_id").toString();
      if (m_customerSetup && !reusedPreparedQuery && !queryId.isEmpty()
          && queryId != m_customerPreparedQuery)
        setupQueryReplaced = true;
    });

    QQuickView view;
    view.resize(1100, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty("apiClient", &client);
    QQmlComponent shell(view.engine());
    shell.setData(m_catalogInstallation ? catalogInstallationShell : installationShell,
                  QUrl("qualification:/installation.qml"));
    QVERIFY(until([&] { return shell.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(shell.isReady(), qPrintable(shell.errorString()));
    auto *root = qobject_cast<QQuickItem *>(shell.create());
    QVERIFY(root);
    view.setContent(QUrl("qualification:/installation.qml"), &shell, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    QVERIFY(root->property(m_catalogInstallation ? "canManage" : "owner").toBool());
    auto *pane = visualItem(root, "marketplaceInstallationPane");
    auto *reference = visualItem(root, "marketplaceDeveloperReferenceText");
    QVERIFY(pane && (m_catalogInstallation || reference));
    QString instance;
    bool catalogContinuation = false;
    for (int n = 0; n < 2; ++n) {
      QVERIFY(remaining() > 0);
      if (m_catalogInstallation) {
        if (n == 1) {
          // The owner of the ORIGINAL private host advances its signed head.
          // This marker coordinates the test only; the server still verifies
          // the real catalog card/source and every installation independently.
          QVERIFY(progress("catalog_update_requested", n));
          QVERIFY(until([&] { return catalogAdvanceReady(); }, std::min(60000, remaining())));
        }
        if (m_customerSetup && n == 0) {
          // Open the shipped browse view with the original checked setup page.
          // It may still be preparing other entries; don't force a second query.
          QVERIFY(until([&] {
            return setupQueryReplaced || (root->property("initialRequestAttempted").toBool()
                && checkedCards(client) && cardFrame(view, root, client.marketplaceSearchResults()));
          }, std::min(10000, remaining())));
          QVERIFY(!setupQueryReplaced);
          QCOMPARE(client.marketplaceSearch().value("query_id").toString(),
                   m_customerPreparedQuery);
        } else {
          auto *text = visualItem(root, "communitySearchText");
          qint64 frame = -1;
          QVERIFY(text && type(view, text, m_exact, frame));
          QVERIFY(installationClick(view, root, "communitySearchButton"));
          QVERIFY(catalogSearchReady(client, std::min(180000, remaining())));
        }
        if (n == 1 && client.marketplaceSearchResults().first().toMap()
                          .value("release_id").toString() == m_releases.first()) {
          // One normal continuation asks community peers after the local card.
          // No direct reference, injected listing or repeated query-to-green.
          QVERIFY(checkedCards(client));
          QVERIFY(installationClick(view, root, "communityNextPage"));
          QVERIFY(catalogSearchReady(client, std::min(180000, remaining())));
          catalogContinuation = true;
        }
        m_expected[m_exact] = m_releases.at(n);
        QVERIFY(checkedCards(client));
        QCOMPARE(client.marketplaceSearchResults().size(), 1);
        QVERIFY(installationClick(view, root, "communityReviewInstallation"));
        QVERIFY(progress("catalog_card_review_selected", n));
      } else {
      // Inject the bounded paste value without putting it on the OS clipboard.
      QVERIFY(reference->setProperty("text", m_publications.at(n)));
      QSignalSpy referenceErrors(&client, &ApiClient::requestFailedDetailed);
      bool referenceStarted = false;
      const auto referenceChange = connect(
          &client, &ApiClient::marketplaceInstallationChanged, &client, [&] {
            referenceStarted |= client.marketplaceDirectReferenceLoading();
          });
      QVERIFY(installationClick(view, root, "marketplaceCheckDeveloperReference"));
      bool referenceRejected = false;
      int referenceStatus = 0;
      const auto referenceFinished = until([&] {
        for (const auto &row : referenceErrors) {
          if (row.at(0).toString() == "/api/v1/marketplace/import") {
            referenceRejected = true;
            referenceStatus = row.at(1).toMap().value("status").toInt();
          }
        }
        referenceRejected |= !client.marketplaceInstallationNotice().isEmpty();
        return referenceRejected || (!client.marketplaceDirectReferenceLoading()
            && !client.marketplaceDirectReference().value("reference_id").toString().isEmpty());
      }, std::min(150000, remaining()));
      disconnect(referenceChange);
      if (!referenceFinished || referenceRejected) {
        const auto category = !referenceStarted ? "request_not_started"
            : referenceRejected ? "request_or_preview_rejected" : "deadline";
        // Closed category/status only: no response message, pasted publication,
        // credentials, provider address or private fixture data enters stdout.
        std::fprintf(stdout, "ELIXIR_MARKETPLACE_REFERENCE_FAILURE category=%s status=%d version_index=%d\n",
                     category, referenceStatus, n);
        std::fflush(stdout);
        QVERIFY(progress("direct_reference_failed", n));
        const auto capture = view.grabWindow();
        QVERIFY(!capture.isNull());
        QVERIFY(capture.save(m_directory + "/reference-failure.png"));
      }
      QVERIFY2(referenceFinished && !referenceRejected,
               "Signed-reference check failed; see closed category/status and private capture.");
      QCOMPARE(client.marketplaceDirectReference().value("release_id").toString(), m_releases.at(n));
      QVERIFY(installationClick(view, root, "marketplaceInspectDeveloperReference"));
      }
      QVERIFY(until([&] { return pane->property("reviewAvailable").toBool()
          && !client.marketplaceInstallationLoading(); }, std::min(90000, remaining())));
      if (m_catalogInstallation) {
        auto selected = pane->property("selectedListing");
        if (selected.metaType() == QMetaType::fromType<QJSValue>())
          selected = selected.value<QJSValue>().toVariant();
        const auto listing = selected.toMap();
        QCOMPARE(listing.value("release_id").toString(), m_releases.at(n));
        QVERIFY(listing.value("direct_reference").toString().isEmpty());
      }
      if (n == 1) {
        auto choiceValue = pane->property("choices");
        if (choiceValue.metaType() == QMetaType::fromType<QJSValue>())
          choiceValue = choiceValue.value<QJSValue>().toVariant();
        const auto choices = choiceValue.toList();
        int chosen = -1;
        for (int i = 0; i < choices.size(); ++i)
          if (choices.at(i).toMap().value("instance_id").toString() == instance)
            chosen = i;
        QVERIFY(chosen > 0);
        QVERIFY(installationClick(view, root, "marketplaceTargetChoice"));
        QTest::keyClick(&view, Qt::Key_Home);
        for (int i = 0; i < chosen; ++i)
          QTest::keyClick(&view, Qt::Key_Down);
        QTest::keyClick(&view, Qt::Key_Return);
        QVERIFY(until([&] { return pane->property("selectedTargetInstance").toString() == instance
            && pane->property("chosenTargetIndex").toInt() == chosen
            && visualItem(root, "marketplaceTargetChoice")->property("currentIndex").toInt() == chosen; }, 5000));
      }
      if (!m_catalogInstallation)
        QVERIFY(installationClick(view, root, "marketplaceUnqualifiedConsent"));
      if (m_customerSetup && n == 0) {
        QVERIFY(!setupQueryReplaced);
        QCOMPARE(client.marketplaceSearch().value("query_id").toString(),
                 m_customerPreparedQuery);
      }
      QVERIFY(installationClick(view, root, "marketplaceStartInstallation"));
      QVERIFY(progress("installation_review_started", n));
      QVERIFY(installationPhase(client, "awaiting_approval", remaining()));
      if (m_customerSetup && n == 0) {
        QVERIFY(!setupQueryReplaced);
        // Require the actual server request to carry the checked first-page
        // query even if the browse receipt expired during package review.
        const auto initial = client.marketplaceInstallation().value("initial_request").toMap();
        QCOMPARE(initial.value("query_id").toString(), m_customerPreparedQuery);
        QCOMPARE(initial.value("extension_id").toString(), m_exact);
        QCOMPARE(initial.value("release_id").toString(), m_releases.at(n));
        QVERIFY(!initial.contains("direct_reference") && !initial.contains("upload_source"));
        reusedPreparedQuery = true;
        disconnect(watchSetup);
        QVERIFY(progress("installation_review_used_prepared_page", n));
      }
      auto *automatic = visualItem(root, "marketplaceAutomaticUpdates");
      QVERIFY(automatic && !automatic->property("checked").toBool());
      QVERIFY(installationClick(view, root, "marketplaceApproveInstallation"));
      QVERIFY(installationPhase(client, "awaiting_setup", remaining()));
      QVERIFY(installationClick(view, root, "marketplaceSubmitSetup"));
      QVERIFY(installationPhase(client, "awaiting_commit", remaining()));
      QVERIFY(installationClick(view, root, "marketplaceActivateInstallation"));
      QVERIFY(installationPhase(client, "activated", remaining()));
      const auto operation = client.marketplaceInstallation();
      QCOMPARE(operation.value("release_id").toString(), m_releases.at(n));
      const auto configured = operation.value("configured_instance").toString();
      QVERIFY(!configured.isEmpty());
      if (n == 0)
        instance = configured;
      else
        QCOMPARE(configured, instance);
      const auto capture = m_directory + QString("/manual-v%1-activated.png").arg(n + 1);
      QVERIFY(!QFile::exists(capture));
      QVERIFY(view.grabWindow().save(capture));
      QVERIFY(QFile::setPermissions(capture, QFileDevice::ReadOwner | QFileDevice::WriteOwner));
      QVERIFY(progress("installation_version_activated", n, -1, original.elapsed()));
    }
    const QJsonObject result{{"schema_version", 1}, {"fixture_only", true},
      {"normal_login", true}, {"real_http", true}, {"packaged_qml", true},
      {"versions_activated", 2}, {"same_instance", true}, {"automatic_opt_in_selected", false},
      {"catalog_cards_used", m_catalogInstallation}, {"developer_reference_used", !m_catalogInstallation},
      {"catalog_continuation_used", catalogContinuation},
      {"customer_first_run_completed", m_customerPrepared},
      {"setup_query_reused_for_install", reusedPreparedQuery},
      {"first_run_controls_to_checked_page_ms", m_customerFirstPageMs},
      {"consent_to_checked_page_ms", m_customerConsentPageMs},
      {"excludes", "native invocation, transport attestation, public discovery, real billing, playback, latency and scale"}};
    std::fprintf(stdout, "ELIXIR_MARKETPLACE_INSTALLATION_UI_RESULT %s\n",
      QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
    std::fflush(stdout);
    client.clearMarketplaceSearch();
  }

private:
  void prepareCustomerProvider(ApiClient &client, int budget) {
    m_customerPrepared = false;
    m_customerPreparedQuery.clear();
    QVERIFY(budget > 0);
    QElapsedTimer elapsed; elapsed.start();
    const auto remaining = [&] { return int(std::max<qint64>(0, budget - elapsed.elapsed())); };
    QVERIFY(progress("provider_first_run_started"));
    QQuickView view;
    view.resize(1100, 900);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty("apiClient", &client);
    QQmlComponent component(view.engine());
    component.setData(customerFirstRunShell, QUrl("qualification:/customer-first-run.qml"));
    QVERIFY(until([&] { return component.status() != QQmlComponent::Loading; }, std::min(5000, remaining())));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    auto *root = qobject_cast<QQuickItem *>(component.create());
    QVERIFY(root);
    view.setContent(QUrl("qualification:/customer-first-run.qml"), &component, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *settings = visualItem(root, "marketplaceSettingsView");
    auto *preparation = visualItem(root, "marketplaceBrowsePreparation");
    QVERIFY(settings && preparation);
    QVERIFY(until([&] { return settings->property("loaded").toBool()
        && client.marketplaceSettings().value("runtime_fresh").toBool()
        && !client.marketplaceSettingsLoading(); }, std::min(15000, remaining())));
    const auto initial = client.marketplaceSettings();
    QCOMPARE(initial.value("settings").toMap().value("revision").toInt(), 0);
    const auto provider = initial.value("provider_setup").toMap();
    QCOMPARE(provider.value("schema_version").toInt(), 1);
    QCOMPARE(provider.value("revision").toInt(), 0);
    QVERIFY(!provider.value("enabled").toBool() && !provider.value("consent_current").toBool());
    QVERIFY(!preparation->property("firstResultsReady").toBool());
    auto *contribution = visualItem(root, "marketplaceContributionSwitch");
    auto *consent = visualItem(root, "marketplaceProviderConsent");
    auto *enable = visualItem(root, "marketplaceProviderEnable");
    QVERIFY(contribution && contribution->property("checked").toBool());
    QVERIFY(consent && !consent->property("checked").toBool());
    QVERIFY(enable && !enable->isEnabled());
    // Private qualification must not enable public contribution. Select Off
    // through the normal shipped control, not a pre-saved database/API value.
    QVERIFY(installationClick(view, root, "marketplaceContributionSwitch"));
    QVERIFY(installationClick(view, root, "marketplaceSaveButton"));
    QVERIFY(until([&] { const auto snapshot = client.marketplaceSettings().value("settings").toMap();
      return !client.marketplaceSettingsLoading() && snapshot.value("revision").toInt() == 1
          && snapshot.value("preferences").toMap().value("contribution").toString() == "off";
    }, std::min(15000, remaining())));
    QVERIFY(progress("provider_first_run_preferences_saved"));
    QVERIFY(!consent->property("checked").toBool() && !enable->isEnabled());
    QVERIFY(installationClick(view, root, "marketplaceProviderConsent"));
    QVERIFY(until([&] { return enable->isEnabled(); }, std::min(1000, remaining())));
    const auto consentStarted = elapsed.elapsed();
    QVERIFY(installationClick(view, root, "marketplaceProviderEnable"));
    QVERIFY(until([&] { const auto current = client.marketplaceSettings().value("provider_setup").toMap();
      return !client.marketplaceConnectionSaving() && current.value("revision").toInt() == 1
          && current.value("enabled").toBool() && current.value("consent_current").toBool();
    }, std::min(20000, remaining())));
    QVERIFY(progress("provider_first_run_consent_saved"));
    bool failed = false;
    QVERIFY(until([&] {
      const auto phase = client.marketplaceSearch().value("phase").toString();
      const auto startup = client.marketplaceSettings().value("startup").toMap();
      failed = phase == "unavailable" || phase == "stale"
          || (client.marketplaceSettings().value("runtime_fresh").toBool()
              && !startup.value("retry_owner_present").toBool());
      return failed || preparation->property("firstResultsReady").toBool();
    }, remaining()));
    QVERIFY2(!failed, "original provider/setup checks became unavailable; do not retry the fixture");
    QVERIFY(checkedCards(client) && !client.marketplaceSearchResults().isEmpty());
    QVERIFY(preparation->property("connected").toBool());
    QVERIFY(preparation->property("firstPage").toBool());
    m_customerPreparedQuery = client.marketplaceSearch().value("query_id").toString();
    QVERIFY(!m_customerPreparedQuery.isEmpty());
    QCOMPARE(client.marketplaceSettings().value("settings").toMap().value("preferences").toMap()
                 .value("contribution").toString(), QString("off"));
    const auto capture = m_directory + "/provider-first-checked-page.png";
    QVERIFY(!QFile::exists(capture) && view.grabWindow().save(capture));
    QVERIFY(QFile::setPermissions(capture, QFileDevice::ReadOwner | QFileDevice::WriteOwner));
    m_customerFirstPageMs = elapsed.elapsed();
    m_customerConsentPageMs = m_customerFirstPageMs - consentStarted;
    QVERIFY(progress("provider_first_run_checked_page", -1, m_customerConsentPageMs, m_customerFirstPageMs));
    m_customerPrepared = true;
  }

  bool catalogAdvanceReady() const {
    const auto path = m_directory + "/catalog-update-ready.json";
    const QFileInfo info(path);
    if (!info.exists() || !info.isFile() || info.isSymLink() || info.size() > 128
        || info.canonicalPath() != m_directory)
      return false;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;
    const auto value = QJsonDocument::fromJson(file.read(129)).object();
    return value.size() == 3 && value.value("schema_version") == 1
        && value.value("fixture_only") == true && value.value("version_index") == 1;
  }
  bool catalogSearchReady(ApiClient &client, int milliseconds) {
    bool failed = false;
    const auto finished = until([&] {
      const auto phase = client.marketplaceSearch().value("phase").toString();
      failed = phase == "unavailable" || phase == "stale";
      return failed || (phase == "ready" && !client.marketplaceSearchLoading());
    }, milliseconds);
    const bool ready = finished && !failed && client.marketplaceSearchResults().size() == 1;
    if (!ready) {
      const auto search = client.marketplaceSearch();
      const auto phase = search.value("phase").toString();
      const QStringList allowed{"checking", "ready", "unavailable", "stale"};
      // Closed phase/counters only: no text, cursor, IDs, notices or sources.
      qWarning().noquote() << QJsonDocument(QJsonObject{
          {"stage", "catalog_search_failed"},
          {"phase", phase.isEmpty() ? QStringLiteral("none")
                      : allowed.contains(phase) ? phase : QStringLiteral("unsupported")},
          {"finished", finished}, {"loading", client.marketplaceSearchLoading()},
          {"rows", int(client.marketplaceSearchResults().size())},
          {"checked", search.value("checked").toInt()},
          {"omitted", search.value("omitted").toInt()},
          {"pending", search.value("pending").toInt()}}).toJson(QJsonDocument::Compact);
    }
    return ready;
  }
  bool installationClick(QQuickView &view, QQuickItem *root, const char *name) {
    auto *item = visualItem(root, QString::fromLatin1(name));
    if (!item || !item->isVisible() || !item->isEnabled())
      return false;
    // Both the developer-reference Flickable and the shipped catalog's nested
    // ScrollView must scroll their actual viewport, not an unrelated root.
    int depth = 0;
    for (auto *parent = item->parentItem(); parent && depth++ < 24; parent = parent->parentItem()) {
      if (!parent->property("contentY").isValid() || !parent->property("contentHeight").isValid()) continue;
      const auto rect = item->mapRectToItem(parent, item->boundingRect());
      if (rect.top() < 0 || rect.bottom() > parent->height()) {
        const auto maximum = std::max(0.0, parent->property("contentHeight").toDouble() - parent->height());
        parent->setProperty("contentY", std::clamp(parent->property("contentY").toDouble() + rect.top() - 24.0, 0.0, maximum));
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
      }
    }
    return click(view, item);
  }
  bool installationPhase(ApiClient &client, const QString &wanted, int milliseconds) {
    bool failed = false;
    const auto finished = milliseconds > 0 && until([&] {
      const auto phase = client.marketplaceInstallation().value("phase").toString();
      failed = QStringList{"stopped", "cancelled", "recovery_required"}.contains(phase)
          || !client.marketplaceInstallationNotice().isEmpty();
      return failed || (phase == wanted && !client.marketplaceInstallationLoading());
    }, milliseconds);
    if (!finished || failed) {
      // Closed diagnostics only. Never print a peer's text, IDs, source,
      // credentials, publication, payload or the raw installation notice.
      const auto installation = client.marketplaceInstallation();
      const QStringList phases{"selecting", "awaiting_approval", "preparing",
                               "awaiting_setup", "awaiting_commit", "activated",
                               "stopped", "cancelled", "recovery_required"};
      const auto closed = [](const QString &value, const QStringList &allowed) {
        return value.isEmpty() ? QStringLiteral("none")
                              : allowed.contains(value) ? value : QStringLiteral("unsupported");
      };
      const auto status = installation.value("latest_action").toMap().value("status").toString();
      qWarning().noquote() << QJsonDocument(QJsonObject{
          {"stage", "installation_phase_failed"},
          {"wanted", closed(wanted, phases)},
          {"observed", closed(installation.value("phase").toString(), phases)},
          {"operation_present", !installation.isEmpty()},
          {"notice_present", !client.marketplaceInstallationNotice().isEmpty()},
          {"action_status", closed(status, {"pending", "acknowledged", "rejected"})}})
          .toJson(QJsonDocument::Compact);
    }
    return finished && !failed;
  }
  bool progress(const char *stage, int sample = -1, qint64 frame = -1,
                qint64 ready = -1) {
    // Closed stages/counters only, never input, IDs, endpoints or credentials.
    const auto bytes = QJsonDocument(QJsonObject{{"stage", stage},
                                                 {"sample", sample},
                                                 {"first_frame_ms", frame},
                                                 {"ready_ms", ready}})
                           .toJson(QJsonDocument::Compact) +
                       '\n';
    return m_progress.write(bytes) == bytes.size() && m_progress.flush();
  }

  bool checkedCards(const ApiClient &client) const {
    const auto rows = client.marketplaceSearchResults();
    if (rows.size() > 20)
      return false;
    QSet<QString> seen;
    for (const auto &value : rows) {
      const auto row = value.toMap();
      const auto id = row.value("extension_id").toString();
      const auto support = row.value("support").toMap();
      if (!m_expected.contains(id) || seen.contains(id) ||
          row.value("release_id") != m_expected.value(id) ||
          !row.value("metadata_only").toBool() ||
          support.value("verified_supporters").toInt() != 5 ||
          !support.value("discovery_qualified").toBool() ||
          support.value("is_global_total").toBool())
        return false;
      seen.insert(id);
    }
    return true;
  }

  bool measure(ApiClient &client, QQuickView &view, QObject *root,
               const std::function<bool()> &trigger, const QString &text,
               const QStringList &tags, int count, Sample &sample,
               const char *timingArm = nullptr) {
    const auto fail = [&](const char *reason, qint64 elapsedMs) {
      const auto phase = client.marketplaceSearch().value("phase").toString();
      const auto known = QStringList{"checking", "ready", "unavailable", "stale"};
      const auto data =
          QJsonDocument(QJsonObject{
                            {"stage", "desktop_search_measure_failed"},
                            {"reason", reason},
                            {"phase", known.contains(phase)
                                          ? phase : QStringLiteral("other")},
                            {"rows", client.marketplaceSearchResults().size()},
                            {"expected", count},
                            {"loading", client.marketplaceSearchLoading()},
                            {"elapsed_ms", elapsedMs},
                            {"first_frame_ms", sample.firstFrameMs},
                            {"ready_ms", sample.readyMs}})
              .toJson(QJsonDocument::Compact);
      std::fprintf(stdout, "ELIXIR_MARKETPLACE_MEASURE_FAILURE %s\n",
                   data.constData());
      std::fflush(stdout);
      return false;
    };
    if (!until([&] { return !client.marketplaceSearchLoading(); }, 20000))
      return fail("previous_request_busy", -1);
    const auto old = client.marketplaceSearch().value("query_id").toString();
    QElapsedTimer elapsed;
    elapsed.start();
    // Diagnostic only on the protected fixture executable. Capture the
    // existing model notifications; do not add polls or alter their cadence.
    const bool tracePolls = timingArm &&
        qEnvironmentVariableIntValue("ELIXIR_MARKETPLACE_SEARCH_PAIR_TIMING") == 1;
    QString traceQuery;
    QJsonArray reads;
    qint64 nextRead = -1;
    bool traceIncomplete = false;
    QObject traceScope;
    if (tracePolls) {
      QObject::connect(&client, &ApiClient::marketplaceSearchChanged, &traceScope, [&] {
        const auto response = client.marketplaceSearch();
        const auto id = response.value("query_id").toString();
        if (id.isEmpty() || id == old || traceIncomplete)
          return;
        if (traceQuery.isEmpty())
          traceQuery = id;
        if (traceQuery != id) {
          traceIncomplete = true;
          return;
        }
        const auto now = elapsed.nsecsElapsed() / 1000;
        if (client.marketplaceSearchLoading()) {
          if (nextRead < 0)
            nextRead = now;
          return;
        }
        if (!reads.isEmpty() && nextRead < 0)
          return; // Unrelated presentation notification, not a settled read.
        const auto phase = response.value("phase").toString();
        const int cards = client.marketplaceSearchAvailableCount();
        if (reads.size() == 8 || cards < 0 || cards > 20 ||
            (phase != "checking" && phase != "ready")) {
          traceIncomplete = true;
          return;
        }
        // The initial GET begins before the query ID reaches the model.
        reads.append(QJsonObject{{"begin_us", nextRead}, {"end_us", now},
                                 {"phase", phase}, {"cards", cards}});
        nextRead = -1;
      });
    }
    if (!trigger())
      return fail("trigger_failed", elapsed.elapsed());
    const char *failure = nullptr;
    QString readyQuery;
    const bool finished = until(
        [&] {
          const auto response = client.marketplaceSearch();
          const auto id = response.value("query_id").toString();
          if (id.isEmpty() || id == old)
            return false;
          if (!readyQuery.isEmpty() && id != readyQuery) {
            failure = "query_replaced_before_frame";
            return true;
          }
          const auto query = response.value("query").toMap();
          // The server echoes NFKC/lowercase/space-normalized search text.
          // Fixture input is explicitly ASCII, so these Qt transforms agree.
          if (query.value("text").toString() != text.toLower().simplified() ||
              query.value("tags").toStringList() != tags) {
            failure = "query_mismatch";
            return true;
          }
          const auto phase = response.value("phase").toString();
          if (phase == "unavailable" || phase == "stale") {
            failure = "query_unavailable_or_stale";
            return true;
          }
          if (!checkedCards(client)) {
            failure = "unverified_card";
            return true;
          }
          if (sample.localCompleteMs < 0 && response.value("local_page_complete").toBool()) {
            sample.localCompleteMs = elapsed.elapsed();
            sample.peersPendingAtLocalCompletion = phase == "checking";
          }
          if (sample.firstFrameMs < 0 &&
              !client.marketplaceSearchResults().isEmpty() &&
              cardFrame(view, root, client.marketplaceSearchResults()))
            sample.firstFrameMs = elapsed.elapsed();
          if (phase == "ready" && !client.marketplaceSearchLoading()) {
            if (client.marketplaceSearchResults().size() != count) {
              failure = "ready_row_count_mismatch";
              return true;
            }
            if (count == 1 && client.marketplaceSearchResults()
                                      .first()
                                      .toMap()
                                      .value("extension_id")
                                      .toString() != m_exact) {
              failure = "ready_card_identity_mismatch";
              return true;
            }
            if (sample.readyMs < 0) {
              sample.readyMs = elapsed.elapsed();
              readyQuery = id;
            }
            if (count == 0 || sample.firstFrameMs >= 0)
              return true;
            // The native HTTP model can be ready one event turn before QML
            // lays out and paints the new card. Record both clocks, and still
            // require a real verified frame within a bounded window.
            if (elapsed.elapsed() - sample.readyMs >= 1500) {
              failure = "card_frame_not_painted_after_ready";
              return true;
            }
          }
          return false;
        },
        180000);
    if (failure)
      return fail(failure, elapsed.elapsed());
    if (!finished || sample.readyMs < 0 || (count > 0 && sample.firstFrameMs < 0))
      return fail("query_or_frame_timeout", elapsed.elapsed());
    if (tracePolls && !traceQuery.isEmpty()) {
      // Hash the synthetic query nonce for offline joins. No input, path,
      // publisher, token or raw ID reaches the desktop progress file.
      const auto key = QCryptographicHash::hash(traceQuery.toUtf8(), QCryptographicHash::Sha256).toHex();
      const auto event = QJsonObject{{"stage", "desktop_search_poll_timing"},
                                     {"arm", QString::fromLatin1(timingArm)},
                                     {"query_hash", QString::fromLatin1(key)},
                                     {"first_frame_ms", sample.firstFrameMs},
                                     {"ready_ms", sample.readyMs},
                                     {"incomplete", traceIncomplete || nextRead >= 0},
                                     {"reads", reads}};
      const auto bytes = QJsonDocument(event).toJson(QJsonDocument::Compact) + '\n';
      if (m_progress.write(bytes) != bytes.size() || !m_progress.flush())
        return fail("poll_timing_write_failed", elapsed.elapsed());
    }
    return true;
  }

  bool type(QQuickView &view, QQuickItem *field, const QString &text,
            qint64 &frameMs) {
    if (!field || !field->isEnabled())
      return false;
    QElapsedTimer elapsed;
    elapsed.start();
    field->forceActiveFocus();
    QTest::keySequence(&view, QKeySequence(QKeySequence::SelectAll));
    QTest::keyClick(&view, Qt::Key_Backspace, Qt::NoModifier, 0);
    for (const auto c : text)
      QTest::keyClick(&view, c.toLatin1(), Qt::NoModifier, 0);
    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    if (field->property("text").toString() != text ||
        view.grabWindow().isNull())
      return false;
    frameMs = elapsed.elapsed();
    return true;
  }

  bool exercisePlayback(ApiClient &client, QQuickView &view, QObject *root,
                        QQuickItem *button, QQuickItem *live, QQuickItem *field) {
    QNetworkAccessManager network;
    const QUrl base(m_url);
    const auto closedCode = [](const QString &value) {
      return QRegularExpression("^[a-z][a-z0-9_]{0,95}$").match(value).hasMatch()
          ? value : QStringLiteral("other");
    };
    const auto fail = [&](const char *stage, QJsonObject counters = {}) {
      counters.insert("schema_version", 1);
      counters.insert("stage", stage);
      counters.insert("fixture_only", true);
      // Closed stage, protocol enums and numeric counters only. Never dump a
      // response body, source URL, session ID, token or raw server message.
      std::fprintf(stdout, "ELIXIR_MARKETPLACE_PLAYBACK_DIAGNOSTIC %s\n",
          QJsonDocument(counters).toJson(QJsonDocument::Compact).constData());
      std::fflush(stdout);
      return false;
    };
    const char *requestStage = "unclassified_media_request";
    auto ownedUrl = [&](const QUrl &url) {
      return url.isValid() && url.scheme() == "http" && url.host() == "127.0.0.1"
          && url.port() == base.port() && url.userInfo().isEmpty() && url.fragment().isEmpty();
    };
    auto get = [&](const QUrl &url, QByteArray &bytes, qint64 &ms,
                   const std::function<bool()> &during = {}) {
      if (!ownedUrl(url)) return fail("unowned_media_url");
      QNetworkRequest request(url);
      request.setRawHeader("Authorization", QByteArray("Bearer ") + client.authToken().toUtf8());
      request.setTransferTimeout(15000);
      request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
      QElapsedTimer timer; timer.start();
      QScopedPointer<QNetworkReply> reply(network.get(request));
      reply->setReadBufferSize(4 * 1024 * 1024 + 1);
      bool overflow = false;
      auto collect = [&] {
        bytes += reply->readAll();
        if (bytes.size() > 4 * 1024 * 1024) { overflow = true; reply->abort(); }
      };
      QObject::connect(reply.data(), &QIODevice::readyRead, reply.data(), collect);
      const bool interaction = !during || during();
      const bool finished = until([&] { return reply->isFinished(); }, 16000);
      collect(); ms = timer.elapsed();
      if (!finished) reply->abort();
      const bool ok = interaction && finished && !overflow && reply->error() == QNetworkReply::NoError
          && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 200
          && !bytes.isEmpty();
      return ok || fail(requestStage, {{"http_status", reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt()},
          {"network_error", int(reply->error())}, {"finished", finished}, {"overflow", overflow},
          {"bytes", bytes.size()}, {"interaction", interaction}});
    };
    auto childUrl = [&](const QUrl &parent, const QByteArray &body, QUrl &child) {
      if (!body.startsWith("#EXTM3U")) return false;
      for (const auto &raw : body.split('\n')) {
        const auto line = raw.trimmed();
        if (!line.isEmpty() && !line.startsWith('#')) {
          child = parent.resolved(QUrl(QString::fromUtf8(line)));
          return ownedUrl(child);
        }
      }
      return false;
    };
    struct EndSession {
      ApiClient &client; QString id;
      ~EndSession() { if (!id.isEmpty()) client.endSessionBlocking(id, 10000); }
    };
    struct Phase { qint64 start = -1, seek = -1; QList<qint64> segments; } baseline, loaded;
    QList<qint64> loadedFrames, loadedQueries;
    qint64 filterMs = -1, textMs = -1, typingMs = -1;
    client.setNetworkType("lan");
    client.setClientCapabilities({{"profile_id", "web_chromium"}, {"profile_version", 5},
                                  {"app_version", "0.1.0"}, {"quality_mode", "original"}});
    for (int phase = 0; phase < 2; ++phase) {
      const bool busy = phase == 1;
      auto &timing = busy ? loaded : baseline;
      if (!progress(busy ? "playback_loaded_started" : "playback_baseline_started")) return false;
      QSignalSpy started(&client, &ApiClient::playbackStarted);
      QSignalSpy failed(&client, &ApiClient::playbackFailed);
      QElapsedTimer start; start.start();
      client.startPlayback(m_playbackItem, m_playbackFile);
      if (!until([&] { return !started.isEmpty() || !failed.isEmpty(); }, 15000)
          || started.size() != 1 || !failed.isEmpty()) {
        const auto error = failed.isEmpty() ? QVariantMap{} : failed.last().first().toMap();
        return fail("playback_start_response_failed", {{"http_status", error.value("status").toInt()},
            {"code", closedCode(error.value("code").toString())}, {"started", started.size()}, {"failed", failed.size()}});
      }
      const auto info = started.first().first().toMap();
      if (!progress("playback_start_response_received")) return false;
      if (info.value("mode") != "direct_stream" || info.value("delivery") != "hls_fmp4")
        return fail("unexpected_playback_plan", {{"mode", closedCode(info.value("mode").toString())},
            {"delivery", closedCode(info.value("delivery").toString())},
            {"decision_reason", closedCode(info.value("decision_reason").toString())}});
      EndSession session{client, info.value("session_id").toString()};
      if (session.id.isEmpty()) return false;
      const auto master = base.resolved(QUrl(info.value("stream_url").toString()));
      QByteArray masterBody; qint64 ignoredMs;
      auto queryWhileStarting = [&] {
        if (!busy) return true;
        Sample sample;
        return measure(client, view, root, [&] { return click(view, button); }, "", {}, 20, sample);
      };
      requestStage = "initial_playlist_request_failed";
      if (!get(master, masterBody, ignoredMs, queryWhileStarting)) return false;
      if (!progress("playback_initial_playlist_received")) return false;
      timing.start = start.elapsed();
      QUrl playlist;
      if (masterBody.contains("#EXTINF:")) playlist = master;
      else if (!childUrl(master, masterBody, playlist)) return fail("initial_playlist_shape_failed");
      QSet<QString> seen;
      auto fetchSegments = [&](int minimum) {
        QElapsedTimer wait; wait.start();
        while (timing.segments.size() < minimum && wait.elapsed() < 15000) {
          QByteArray body; qint64 ms;
          requestStage = "media_playlist_request_failed";
          if (!get(playlist, body, ms)) return false;
          if (!body.startsWith("#EXTM3U")) return fail("media_playlist_shape_failed");
          const QRegularExpression map("#EXT-X-MAP:URI=\"([^\"]+)\"");
          const auto match = map.match(QString::fromUtf8(body));
          if (!match.hasMatch()) return fail("media_init_reference_missing");
          QByteArray init;
          requestStage = "media_init_request_failed";
          if (!get(playlist.resolved(QUrl(match.captured(1))), init, ms)) return false;
          if (!init.contains("ftyp")) return fail("media_init_shape_failed");
          for (const auto &raw : body.split('\n')) {
            const auto line = QString::fromUtf8(raw.trimmed());
            if (line.isEmpty() || line.startsWith('#') || seen.contains(line)) continue;
            const auto url = playlist.resolved(QUrl(line));
            QByteArray segment;
            requestStage = "media_segment_request_failed";
            if (!get(url, segment, ms)) return false;
            if (!segment.contains("moof") || !segment.contains("mdat"))
              return fail("media_segment_shape_failed", {{"bytes", segment.size()},
                  {"playlist_body", segment.startsWith("#EXTM3U")},
                  {"file_type_box", segment.contains("ftyp")}, {"movie_box", segment.contains("moov")},
                  {"segment_type_box", segment.contains("styp")}, {"fragment_box", segment.contains("moof")},
                  {"media_data_box", segment.contains("mdat")},
                  {"playlist_path", url.path().endsWith(".m3u8")}, {"init_path", url.path().endsWith(".mp4")},
                  {"fragment_path", url.path().endsWith(".m4s")},
                  {"transport_stream_sync", !segment.isEmpty() && quint8(segment[0]) == 0x47}});
            seen.insert(line); timing.segments.append(ms);
            if (timing.segments.size() >= minimum) break;
          }
          if (timing.segments.size() < minimum) QTest::qWait(100);
        }
        return timing.segments.size() >= minimum || fail("distinct_media_delivery_deadline",
            {{"received", timing.segments.size()}, {"required", minimum}});
      };
      if (!fetchSegments(2)) return false;
      if (!progress("playback_initial_segments_received")) return false;
      if (busy) {
        for (int n = 0; n < 32; ++n) {
          Sample sample;
          if (!measure(client, view, root, [&] { return click(view, button); }, "", {}, 20,
                       sample, "loaded")) return false;
          loadedFrames.append(sample.firstFrameMs); loadedQueries.append(sample.readyMs);
          if (n % 8 == 7 && !fetchSegments(timing.segments.size() + 1)) return false;
        }
        Sample filter, text;
        if (!measure(client, view, root, [&] { return click(view, live); }, "", {"live"}, 20, filter)) return false;
        filterMs = filter.readyMs;
        if (!measure(client, view, root, [&] { return type(view, field, m_name, typingMs); }, m_name, {"live"}, 1, text)) return false;
        textMs = text.readyMs;
        Sample reset; qint64 resetTyping;
        if (!measure(client, view, root, [&] { return type(view, field, "", resetTyping) && click(view, live); }, "", {}, 20, reset)) return false;
      }
      QSignalSpy seekDone(&client, &ApiClient::seekCompleted);
      QSignalSpy seekFailed(&client, &ApiClient::seekFailed);
      QElapsedTimer seek; seek.start();
      // The first normal end may save a 60-second resume point. The loaded
      // phase must perform a different real seek, not seek to that same point.
      client.seekPlayback(session.id, busy ? 120.0 : 60.0);
      if (busy) {
        Sample sample;
        if (!measure(client, view, root, [&] { return click(view, button); }, "", {}, 20, sample)) return false;
      }
      if (!until([&] { return !seekDone.isEmpty() || !seekFailed.isEmpty(); }, 15000)
          || seekDone.size() != 1 || !seekFailed.isEmpty()) return fail("playback_seek_response_failed");
      if (!progress("playback_seek_response_received")) return false;
      timing.seek = seek.elapsed();
      QByteArray afterSeek;
      requestStage = "seek_playlist_request_failed";
      if (!get(master, afterSeek, ignoredMs)) return false;
      if (afterSeek.contains("#EXTINF:")) playlist = master;
      else if (!childUrl(master, afterSeek, playlist)) return fail("seek_playlist_shape_failed");
      seen.clear();
      if (!fetchSegments(timing.segments.size() + 2)) return false;
      if (!client.endSessionBlocking(session.id, 10000)) return fail("normal_session_retirement_failed");
      session.id.clear();
      if (timing.start > 15000 || timing.seek > 15000) return fail("playback_timing_bound_exceeded");
    }
    const QJsonObject result{
      {"schema_version",1},{"stage","protected_playback_result"},{"fixture_only",true},
      {"normal_playback_api",true},{"actual_hls_downloads",true},
      {"baseline_start_ms",baseline.start},{"baseline_seek_ms",baseline.seek},
      {"baseline_segment_p95_ms",p95(baseline.segments)},{"baseline_segments",baseline.segments.size()},
      {"loaded_start_ms",loaded.start},{"loaded_seek_ms",loaded.seek},
      {"loaded_segment_p95_ms",p95(loaded.segments)},{"loaded_segments",loaded.segments.size()},
      {"loaded_ui_first_card_p95_ms",p95(loadedFrames)},{"loaded_ui_full_search_p95_ms",p95(loadedQueries)},
      {"loaded_ui_samples",32},{"loaded_filter_ms",filterMs},{"loaded_text_ms",textMs},
      {"typing_frame_ms",typingMs},{"sessions_ended",2},
      {"excludes","physical decoder/display/audio QoE, relay contribution, 10k catalog, off-site peers and full privacy/platform/soak qualification"}};
    std::fprintf(stdout,"ELIXIR_MARKETPLACE_PLAYBACK_RESULT %s\n",QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
    std::fflush(stdout);
    return progress("playback_complete");
  }

  QString m_url, m_email, m_directory, m_name, m_exact, m_playbackItem, m_playbackFile;
  QStringList m_publications, m_releases;
  QMap<QString, QString> m_expected;
  QTemporaryDir m_settings;
  QFile m_progress;
  bool m_fixtureRead = false;
  bool m_catalogInstallation = false;
  bool m_customerSetup = false;
  bool m_customerPrepared = false;
  QString m_customerPreparedQuery;
  qint64 m_customerFirstPageMs = -1;
  qint64 m_customerConsentPageMs = -1;
};

int main(int argc, char **argv) {
  qputenv("QT_QUICK_BACKEND", "software");
  // Per-request development chatter can exhaust the bounded capture during
  // slow preparation. Keep failures/warnings and the private stage trace.
  QLoggingCategory::setFilterRules(QStringLiteral("default.info=false"));
  QGuiApplication application(argc, argv);
  QQuickStyle::setStyle("Fusion");
  QFontDatabase::addApplicationFont(":/fonts/OpenSans.ttf");
  QFontDatabase::addApplicationFont(":/fonts/OpenSans-Italic.ttf");
  QGuiApplication::setFont(QFont("Open Sans"));
  qmlRegisterSingletonType(QUrl("qrc:/qml/Theme.qml"), "Elixir", 1, 0, "Theme");
  int result;
  {
    RealServerMarketplaceTests tests;
    // The native cold-page parent historically launches this fixture child
    // without argv. Select its one case explicitly rather than accidentally
    // running unrelated install fixtures that require different stdin frames.
    // Test executable only; no endpoint, principal or product permission.
    QByteArray fixtureCase = qgetenv("ELIXIR_MARKETPLACE_DESKTOP_CASE");
    if (argc == 1 && !fixtureCase.isEmpty()) {
      if (fixtureCase != "protected_setup_search_render_and_replacement") {
        std::fprintf(stderr, "Unsupported private desktop fixture case\n");
        result = 2;
      } else {
        char *selected[] = {argv[0], fixtureCase.data(), nullptr};
        result = QTest::qExec(&tests, 2, selected);
      }
    } else {
      result = QTest::qExec(&tests, argc, argv);
    }
  }
  // All engines/windows are gone before clearing the registrations they use.
  qmlClearTypeRegistrations();
  QFontDatabase::removeAllApplicationFonts();
  return result;
}

#include "RealServerMarketplaceTests.moc"
