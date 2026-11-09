// Run the production bootstrap, real models and main.qml. Only the explicitly
// injected volatile vault/private settings/log paths differ. No fake API,
// session, permissions, listing, verification or install result is supplied.
#include "ClientApplication.h"
#include "backend/ApiClient.h"
#include "backend/CredentialStore.h"
#include "backend/SessionManager.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QJSValue>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QKeySequence>
#include <QMap>
#include <QProcessEnvironment>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>
#include <QUrl>
#include <QtQml>

#include <algorithm>
#include <cstdio>
#include <functional>
#include <memory>
#ifdef Q_OS_UNIX
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace {
class VolatileFixtureVault final : public CredentialStore {
public:
  CredentialReadResult read(const QString &service,
                            const QString &account) override {
    ++reads;
    const auto key = service + '\n' + account;
    if (!values.contains(key))
      return {CredentialStoreStatus::NotFound, {}, {}};
    return {CredentialStoreStatus::Success, values.value(key), {}};
  }
  CredentialStoreStatus write(const QString &service, const QString &account,
                              const QString &value, QString *) override {
    values.insert(service + '\n' + account, value);
    return CredentialStoreStatus::Success;
  }
  CredentialStoreStatus remove(const QString &service, const QString &account,
                               QString *) override {
    values.remove(service + '\n' + account);
    return CredentialStoreStatus::Success;
  }
  // Test-only, process-local storage. This does NOT qualify the OS vault.
  bool isSecure() const override { return true; }
  int reads = 0;
  QMap<QString, QString> values;
};
struct Fixture {
  bool live = false;
  QString server = QStringLiteral("http://127.0.0.1:1");
  QString email, extension, release, captures, privateRoot;
  std::shared_ptr<VolatileFixtureVault> vault =
      std::make_shared<VolatileFixtureVault>();
} fixture;

bool until(const std::function<bool()> &predicate, int milliseconds) {
  QElapsedTimer elapsed;
  elapsed.start();
  do {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    if (predicate())
      return true;
    QTest::qWait(10);
  } while (elapsed.elapsed() < milliseconds);
  return predicate();
}
// Private qualification data only: finite states/counts, never response bodies,
// query/publisher IDs, addresses, credentials, paths or peer-supplied errors.
QJsonObject setupState(const QVariantMap &search, const QVariantMap &settings,
                       int checked) {
  const auto closed = [](const QVariant &value, const QStringList &allowed) {
    const auto text = value.toString();
    return allowed.contains(text) ? text : QStringLiteral("unknown");
  };
  const auto preparation = search.value("preparation").toMap();
  const auto startup = settings.value("startup").toMap();
  return {
      {"phase", closed(search.value("phase"),
                       {"checking", "ready", "unavailable", "stale"})},
      {"preparation_phase", closed(preparation.value("phase"),
                                   {"checking", "discovering", "waiting",
                                    "complete", "limited", "unavailable"})},
      {"runtime_status",
       closed(settings.value("runtime_status"),
              {"running", "not_connected", "starting", "failed", "stopped"})},
      {"runtime_fresh", settings.value("runtime_fresh").toBool()},
      {"startup_configured", startup.value("configured").toBool()},
      {"startup_retry_owner", startup.value("retry_owner_present").toBool()},
      {"startup_retry_after_seconds",
       startup.value("retry_after_seconds").isNull()
           ? -1
           : std::clamp(startup.value("retry_after_seconds").toInt(), 0, 300)},
      {"checked_listings", std::clamp(checked, 0, 20)},
      {"pending", std::clamp(search.value("pending").toInt(), 0, 20)},
      {"omitted", std::clamp(search.value("omitted").toInt(), 0, 20)},
      {"examined", std::clamp(preparation.value("examined").toInt(), 0, 10000)},
      {"received",
       std::clamp(preparation.value("received").toInt(), 0, 10240)}};
}
QQuickItem *visual(QQuickItem *root, const QString &name) {
  if (!root)
    return nullptr;
  if (root->objectName() == name)
    return root;
  for (auto *child : root->childItems())
    if (auto *found = visual(child, name))
      return found;
  return nullptr;
}
QVariantMap map(QVariant value) {
  if (value.metaType() == QMetaType::fromType<QJSValue>())
    value = value.value<QJSValue>().toVariant();
  return value.toMap();
}
bool privateDirectory(const QString &path) {
  const QFileInfo info(path);
  if (!info.isAbsolute() || !info.isDir() || info.isSymLink() ||
      info.canonicalFilePath() != QDir::cleanPath(path))
    return false;
#ifdef Q_OS_UNIX
  struct stat status{};
  const auto bytes = QFile::encodeName(path);
  return ::lstat(bytes.constData(), &status) == 0 && S_ISDIR(status.st_mode) &&
         status.st_uid == ::getuid() && (status.st_mode & 0077) == 0;
#else
  return true; // Unix ownership gates are separately exercised on Unix runners.
#endif
}
bool readFixture() {
  QFile input;
  if (!input.open(stdin, QIODevice::ReadOnly))
    return false;
  constexpr int maximum = 160 * 1024;
  QByteArray bytes;
  while (bytes.size() <= maximum) {
    const auto chunk = input.read(maximum + 1 - bytes.size());
    if (chunk.isEmpty())
      break;
    bytes += chunk;
  }
  if (bytes.isEmpty() || bytes.size() > maximum)
    return false;
  QJsonParseError error;
  const auto document = QJsonDocument::fromJson(bytes, &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return false;
  const auto object = document.object();
  if (object.value("schema_version") != 1 ||
      object.value("fixture_only") != true ||
      object.value("purpose") != "installation" ||
      object.value("provider_setup_required") != true ||
      object.value("password") != "fixture-password-only")
    return false;
  const QUrl url(object.value("server_url").toString());
  if (!url.isValid() || url.scheme() != "http" || url.host() != "127.0.0.1" ||
      url.port() <= 0 || !url.userInfo().isEmpty() || !url.path().isEmpty() ||
      !url.query().isEmpty() || !url.fragment().isEmpty())
    return false;
  fixture.email = object.value("email").toString();
  if (!fixture.email.endsWith("@management.example.test") ||
      fixture.email.size() > 127)
    return false;
  const auto entries = object.value("expected").toArray();
  if (entries.size() != 1)
    return false;
  fixture.extension =
      entries.first().toObject().value("extension_id").toString();
  fixture.release = entries.first().toObject().value("release_id").toString();
  if (!QRegularExpression("^elx:[a-z2-7]{52}/[a-z0-9][a-z0-9-]{0,63}$")
           .match(fixture.extension)
           .hasMatch() ||
      !QRegularExpression("^sha256:[a-f0-9]{64}$")
           .match(fixture.release)
           .hasMatch())
    return false;
  fixture.captures = QFileInfo(object.value("capture_directory").toString())
                         .canonicalFilePath();
  if (!privateDirectory(fixture.captures))
    return false;
  const auto temporary = QFileInfo(QDir::tempPath()).canonicalFilePath() + '/';
  const auto sharedTemporary =
      QFileInfo(QStringLiteral("/tmp")).canonicalFilePath() + '/';
  if (!fixture.captures.startsWith(temporary) &&
      (sharedTemporary == "/" || !fixture.captures.startsWith(sharedTemporary)))
    return false;
  fixture.server = url.toString();
  return true;
}
} // namespace

class FullApplicationMarketplaceTests final : public QObject {
  Q_OBJECT
private slots:
  void initTestCase() {
    QVERIFY(until(
        [&] {
          for (auto *candidate : QGuiApplication::topLevelWindows())
            if (candidate->objectName() == "elixirApplication")
              window = qobject_cast<QQuickWindow *>(candidate);
          return window != nullptr;
        },
        5000));
    window->resize(1280, 1000);
    window->requestActivate();
    QVERIFY(QTest::qWaitForWindowExposed(window));
    QVERIFY(QTest::qWaitForWindowActive(window));
    auto *engine = qmlEngine(window);
    QVERIFY(engine && engine->rootContext());
    const auto context = engine->rootContext();
    client = qobject_cast<ApiClient *>(
        context->contextProperty("apiClient").value<QObject *>());
    session = qobject_cast<SessionManager *>(
        context->contextProperty("sessionManager").value<QObject *>());
    QVERIFY(client && session);
    // These MUST be the objects assembled by main.cpp, not replacements.
    for (const auto *name :
         {"controlPlaneClient", "libraryModel", "playerController",
          "serverDiscovery", "liveApiClient", "liveCatalogModel",
          "livePlayerController"})
      QVERIFY(context->contextProperty(QString::fromLatin1(name))
                  .value<QObject *>());
    QCOMPARE(client->baseUrl(), fixture.server);
    QCOMPARE(session->baseUrl(), fixture.server);
    QVERIFY(client->authToken().isEmpty() && !client->hasRefreshToken());
    QVERIFY(session->authToken().isEmpty() && !session->hasRefreshToken());
    QVERIFY(fixture.vault->reads > 0 && fixture.vault->values.isEmpty());
    QVERIFY(privateDirectory(fixture.privateRoot));
    QCOMPARE(currentPage(), QString("connectView"));
    QVERIFY(item("connectAccountEmail") && item("connectAccountPassword") &&
            item("connectSignIn"));
    QVERIFY(client->marketplaceSearchResults().isEmpty());
    QVERIFY(!item("communityMarketplaceCard"));
  }

  void offline_real_bootstrap_is_credential_isolated() {
    QVERIFY(!fixture.live);
    QVERIFY(until([&] { return !window->grabWindow().isNull(); }, 5000));
    // Observe an actual event-loop turn, rather than approving startup solely
    // from successful QML construction before deferred work runs.
    QTest::qWait(100);
    QCOMPARE(currentPage(), QString("connectView"));
    QVERIFY(client->authToken().isEmpty() && !client->hasRefreshToken());
    QVERIFY(client->marketplaceSearchResults().isEmpty());
    QVERIFY(fixture.vault->values.isEmpty());
    QVERIFY(until([&] { return navigationIdle(); }, 5000));
    const auto diagnostic = setupState(
        {{"phase", "https://private.invalid/secret"},
         {"preparation",
          QVariantMap{{"phase", "credential"}, {"examined", -9}}},
         {"token", "private-token"},
         {"pending", 999999}},
        {{"runtime_status", "192.0.2.1"}, {"credentials", "private-token"}},
        99);
    QCOMPARE(diagnostic.value("phase").toString(), QString("unknown"));
    QCOMPARE(diagnostic.value("preparation_phase").toString(),
             QString("unknown"));
    QCOMPARE(diagnostic.value("runtime_status").toString(), QString("unknown"));
    QCOMPARE(diagnostic.value("examined").toInt(), 0);
    QCOMPARE(diagnostic.value("pending").toInt(), 20);
    QCOMPARE(diagnostic.value("checked_listings").toInt(), 20);
    const auto serialized =
        QJsonDocument(diagnostic).toJson(QJsonDocument::Compact);
    QVERIFY(!serialized.contains("private") &&
            !serialized.contains("192.0.2.1"));
    // Test the click helper against pending Layout polish in the real window,
    // without credentials, fake marketplace authority or network actions.
    QQmlComponent geometry(qmlEngine(window));
    geometry.setData(R"QML(
      import QtQuick 6.5
      import QtQuick.Controls 6.5
      import QtQuick.Layouts 6.5
      Item {
        anchors.fill: parent
        property int presses: 0
        ColumnLayout {
          anchors.fill: parent
          Item { Layout.fillHeight: true }
          RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Button {
              objectName: "fixtureGeometryButton"; text: "Geometry fixture"
              onClicked: parent.parent.parent.presses++
            }
            Item { Layout.fillWidth: true }
          }
          Item { Layout.fillHeight: true }
        }
      }
    )QML",
                     QUrl("qualification:/click-geometry.qml"));
    QVERIFY(until([&] { return geometry.status() != QQmlComponent::Loading; },
                  5000));
    QVERIFY2(geometry.isReady(), qPrintable(geometry.errorString()));
    auto *geometryRoot =
        qobject_cast<QQuickItem *>(geometry.createWithInitialProperties(
            {{"parent", QVariant::fromValue(currentPageItem())}}));
    QVERIFY(geometryRoot);
    // A resize invalidates Layout coordinates. The helper must paint BEFORE
    // mapping the new click point, then receive the actual button signal.
    window->resize(960, 720);
    QVERIFY(click("fixtureGeometryButton"));
    QCOMPARE(geometryRoot->property("presses").toInt(), 1);
    delete geometryRoot;
  }

  void protected_owner_setup_navigation_and_install_opt_in() {
    QVERIFY(fixture.live);
    progress.setFileName(fixture.captures + "/progress.jsonl");
    QVERIFY(progress.open(QIODevice::WriteOnly | QIODevice::NewOnly));
    QVERIFY(progress.setPermissions(QFileDevice::ReadOwner |
                                    QFileDevice::WriteOwner));
    QElapsedTimer original;
    original.start();
    QSignalSpy loggedIn(client, &ApiClient::loginSucceeded);
    QSignalSpy loginFailed(client, &ApiClient::loginFailed);
    QVERIFY(type("connectAccountEmail", fixture.email));
    QVERIFY(type("connectAccountPassword", "fixture-password-only"));
    QVERIFY(click("connectSignIn"));
    QVERIFY(until([&] { return !loggedIn.isEmpty() || !loginFailed.isEmpty(); },
                  15000));
    QVERIFY(loggedIn.size() == 1 && loginFailed.isEmpty());
    QVERIFY(until(
        [&] {
          return currentPage() == "marketplaceSetupView" &&
                 client->homeRole() == "owner" &&
                 client->activeProfileType() == "account" &&
                 item("marketplaceSettingsView") &&
                 item("marketplaceSettingsView")->property("loaded").toBool() &&
                 client->marketplaceSettings()
                     .value("runtime_fresh")
                     .toBool() &&
                 !client->marketplaceSettingsLoading();
        },
        20000));
    QVERIFY(mark("provider_first_run_started"));
    const auto initial = client->marketplaceSettings();
    QCOMPARE(initial.value("settings").toMap().value("revision").toInt(), 0);
    QVERIFY(!initial.value("provider_setup").toMap().value("enabled").toBool());
    QVERIFY(item("marketplaceSetupBrowse") &&
            item("marketplaceContributionSwitch") &&
            item("marketplaceProviderConsent") &&
            item("marketplaceProviderEnable"));
    QVERIFY(!item("marketplaceSetupBrowse")->isEnabled());
    QVERIFY(
        item("marketplaceContributionSwitch")->property("checked").toBool());
    QVERIFY(!item("marketplaceProviderConsent")->property("checked").toBool());
    QVERIFY(!item("marketplaceProviderEnable")->isEnabled());
    // This private qualification must NOT advertise or seed fixture material.
    QVERIFY(click("marketplaceContributionSwitch"));
    QVERIFY(click("marketplaceSaveButton"));
    QVERIFY(until(
        [&] {
          return !client->marketplaceSettingsLoading() &&
                 client->marketplaceSettings()
                         .value("settings")
                         .toMap()
                         .value("preferences")
                         .toMap()
                         .value("contribution")
                         .toString() == "off";
        },
        15000));
    QVERIFY(mark("provider_first_run_preferences_saved"));
    QVERIFY(click("marketplaceProviderConsent"));
    QVERIFY(until(
        [&] { return item("marketplaceProviderEnable")->isEnabled(); }, 1000));
    QVERIFY(click("marketplaceProviderEnable"));
    QVERIFY(until(
        [&] {
          const auto provider =
              client->marketplaceSettings().value("provider_setup").toMap();
          return !client->marketplaceConnectionSaving() &&
                 provider.value("enabled").toBool() &&
                 provider.value("consent_current").toBool();
        },
        20000));
    QVERIFY(mark("provider_first_run_consent_saved"));
    bool unavailable = false, diagnosticsSaved = true;
    int stateChanges = 0;
    QByteArray lastState;
    const auto observeSetup = [&] {
      auto state =
          setupState(client->marketplaceSearch(), client->marketplaceSettings(),
                     client->marketplaceSearchAvailableCount());
      const auto *preparation = item("marketplaceBrowsePreparation");
      state.insert("terminal_empty",
                   preparation &&
                       preparation->property("terminalEmpty").toBool());
      state.insert("terminal_connection",
                   preparation &&
                       preparation->property("terminalConnection").toBool());
      const auto bytes = QJsonDocument(state).toJson(QJsonDocument::Compact);
      if (bytes != lastState && stateChanges < 32) {
        diagnosticsSaved =
            mark("provider_first_run_state", state) && diagnosticsSaved;
        lastState = bytes;
        ++stateChanges;
      }
      return state;
    };
    const bool firstPageFinished = until(
        [&] {
          const auto state = observeSetup();
          const auto phase =
              client->marketplaceSearch().value("phase").toString();
          unavailable = phase == "unavailable" || phase == "stale" ||
                        state.value("terminal_empty").toBool() ||
                        state.value("terminal_connection").toBool();
          return !diagnosticsSaved || unavailable ||
                 (item("marketplaceSetupBrowse") &&
                  item("marketplaceSetupBrowse")->isEnabled());
        },
        600000);
    QVERIFY(mark("provider_first_run_wait_finished", observeSetup()));
    if (!firstPageFinished || unavailable)
      QVERIFY(capture("full-app-first-page-not-ready.png"));
    QVERIFY(diagnosticsSaved);
    QVERIFY(firstPageFinished);
    QVERIFY2(!unavailable, "original protected setup ended without a checked "
                           "page; no fixture retry");
    QVERIFY(checkedCard());
    const auto preparedQuery = client->marketplaceSearch().value("query_id");
    QVERIFY(mark("provider_first_run_checked_page"));
    QVERIFY(capture("full-app-checked-setup.png"));
    QVERIFY(click("marketplaceSetupBrowse"));
    QVERIFY(until(
        [&] {
          return currentPage() == "communityMarketplaceView" &&
                 item("communityReviewInstallation") &&
                 item("communityReviewInstallation")->isEnabled();
        },
        15000));
    QCOMPARE(client->marketplaceSearch().value("query_id"), preparedQuery);
    QVERIFY(checkedCard());
    QVERIFY(mark("full_application_prepared_marketplace_opened"));
    // Actual sidebar handlers, StackView transitions, lazy Extensions loader
    // and Settings composition; no test-created shell or fabricated model.
    QVERIFY(click("navigation_home"));
    QVERIFY(until([&] { return currentPage() == "homeView"; }, 15000));
    QVERIFY(click("navigation_settings"));
    QVERIFY(until([&] { return currentPage() == "settingsView"; }, 15000));
    QVERIFY(click("navigation_extensions"));
    QVERIFY(until(
        [&] {
          return currentPage() == "extensionsView" &&
                 item("communityMarketplaceButton") &&
                 item("communityMarketplaceButton")->isEnabled();
        },
        15000));
    QVERIFY(click("communityMarketplaceButton"));
    QVERIFY(until(
        [&] {
          return currentPage() == "communityMarketplaceView" &&
                 item("communityReviewInstallation") &&
                 item("communityReviewInstallation")->isEnabled();
        },
        180000));
    QVERIFY(checkedCard());
    QVERIFY(click("communityReviewInstallation"));
    QVERIFY(until(
        [&] {
          return item("marketplaceInstallationPane") &&
                 item("marketplaceInstallationPane")
                     ->property("reviewAvailable")
                     .toBool() &&
                 !client->marketplaceInstallationLoading();
        },
        90000));
    const auto selected =
        map(item("marketplaceInstallationPane")->property("selectedListing"));
    QCOMPARE(selected.value("extension_id").toString(), fixture.extension);
    QCOMPARE(selected.value("release_id").toString(), fixture.release);
    QVERIFY(selected.value("direct_reference").toString().isEmpty());
    QVERIFY(click("marketplaceStartInstallation"));
    QVERIFY(phase("awaiting_approval", 180000));
    QVERIFY(item("marketplaceAutomaticUpdates") &&
            !item("marketplaceAutomaticUpdates")->property("checked").toBool());
    QVERIFY(click("marketplaceAutomaticUpdates"));
    QVERIFY(item("marketplaceAutomaticUpdates")->property("checked").toBool());
    QVERIFY(click("marketplaceApproveInstallation"));
    QVERIFY(phase("awaiting_setup", 180000));
    QVERIFY(click("marketplaceSubmitSetup"));
    QVERIFY(phase("awaiting_commit", 180000));
    QVERIFY(click("marketplaceActivateInstallation"));
    QVERIFY(phase("activated", 180000));
    const auto operation = client->marketplaceInstallation();
    QCOMPARE(operation.value("release_id").toString(), fixture.release);
    QVERIFY(!operation.value("configured_instance").toString().isEmpty());
    QVERIFY(capture("full-app-opted-in-activated.png"));
    QVERIFY(mark("full_application_initial_version_activated"));
    // Durable opt-in persistence and subsequent unattended execution require
    // independent server evidence; clicking a checked box alone proves neither.
    const QJsonObject result{{"schema_version", 1},
                             {"fixture_only", true},
                             {"production_bootstrap", true},
                             {"main_qml", true},
                             {"real_http", true},
                             {"normal_login", true},
                             {"isolated_credentials", true},
                             {"first_run_controls", true},
                             {"home_settings_extensions_navigation", true},
                             {"catalog_card_install", true},
                             {"automatic_opt_in_submitted", true},
                             {"activated_versions", 1},
                             {"elapsed_ms", original.elapsed()},
                             {"durable_opt_in_independently_verified", false},
                             {"unattended_update", false},
                             {"native_invocation", false},
                             {"public_distribution", false},
                             {"real_paid_credentials", 0},
                             {"performance_qualified", false}};
    std::fprintf(
        stdout, "ELIXIR_MARKETPLACE_FULL_APPLICATION_RESULT %s\n",
        QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
    std::fflush(stdout);
  }

private:
  bool navigationIdle() const {
    const auto *stack = window->property("navigationStack").value<QObject *>();
    return stack && !stack->property("busy").toBool();
  }
  QQuickItem *currentPageItem() const {
    auto *stack = window->property("navigationStack").value<QObject *>();
    return stack ? qobject_cast<QQuickItem *>(
                       stack->property("currentItem").value<QObject *>())
                 : nullptr;
  }
  QQuickItem *item(const QString &name) const {
    // StackView retains earlier pages, sometimes during transitions. Resolve
    // page controls only inside the actual current page, never a duplicate in
    // an inactive Extensions/Settings instance behind it. Sidebar is shared.
    return visual(name.startsWith("navigation_") ? window->contentItem()
                                                 : currentPageItem(),
                  name);
  }
  QString currentPage() const {
    auto *page = currentPageItem();
    return page ? page->objectName() : QString();
  }
  bool click(const QString &name) {
    // Session replies can precede Qt.callLater/polish in the real setup parent.
    // Wait for the SAME control to become interactive; do not invoke its signal
    // directly or change its enabled/visible state to manufacture a click.
    QQuickItem *target = nullptr;
    if (!until(
            [&] {
              target = item(name);
              return navigationIdle() && target && target->isVisible() &&
                     target->isEnabled() && target->width() > 0 &&
                     target->height() > 0;
            },
            5000)) {
      const auto *setup = item("marketplaceSetupView");
      qWarning().noquote()
          << QJsonDocument(
                 QJsonObject{{"stage", "full_app_control_not_interactive"},
                             {"control", name},
                             {"navigation_idle", navigationIdle()},
                             {"present", target != nullptr},
                             {"visible", target && target->isVisible()},
                             {"enabled", target && target->isEnabled()},
                             {"application_active",
                              QGuiApplication::applicationState() ==
                                  Qt::ApplicationActive},
                             {"setup_offered",
                              setup && setup->property("offered").toBool()},
                             {"setup_active",
                              setup && setup->property("active").toBool()},
                             {"setup_can_manage",
                              setup && setup->property("canManage").toBool()}})
                 .toJson(QJsonDocument::Compact);
      return false;
    }
    int depth = 0;
    for (auto *parent = target->parentItem(); parent && depth++ < 32;
         parent = parent->parentItem()) {
      if (!parent->property("contentY").isValid() ||
          !parent->property("contentHeight").isValid())
        continue;
      const auto rect = target->mapRectToItem(parent, target->boundingRect());
      if (rect.top() < 0 || rect.bottom() > parent->height()) {
        const auto maximum =
            std::max(0.0, parent->property("contentHeight").toDouble() -
                              parent->height());
        parent->setProperty("contentY",
                            std::clamp(parent->property("contentY").toDouble() +
                                           rect.top() - 24.0,
                                       0.0, maximum));
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
      }
    }
    // Layout polish may move the target; never map before this actual paint.
    if (window->grabWindow().isNull())
      return false;
    const auto point =
        target->mapToScene(QPointF(target->width() / 2, target->height() / 2))
            .toPoint();
    if (!QRect(QPoint(), window->size()).contains(point))
      return false;
    QSignalSpy clicked(target, SIGNAL(clicked()));
    if (!clicked.isValid())
      return false;
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, point, 0);
    if (until([&] { return !clicked.isEmpty(); }, 1000))
      return true;
    if (fixture.live)
      capture("unclicked-" + name + ".png");
    return false;
  }
  bool type(const QString &name, const QString &value) {
    auto *field = item(name);
    if (!field || !field->isVisible() || !field->isEnabled())
      return false;
    field->forceActiveFocus();
    QTest::keySequence(window, QKeySequence(QKeySequence::SelectAll));
    QTest::keyClick(window, Qt::Key_Backspace, Qt::NoModifier, 0);
    for (auto c : value)
      QTest::keyClick(window, c.toLatin1(), Qt::NoModifier, 0);
    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    return field->property("text").toString() == value;
  }
  bool phase(const QString &wanted, int milliseconds) {
    bool failed = false;
    const bool done = until(
        [&] {
          const auto phase =
              client->marketplaceInstallation().value("phase").toString();
          failed =
              QStringList{"stopped", "cancelled", "recovery_required"}.contains(
                  phase);
          return failed ||
                 (!client->marketplaceInstallationLoading() && phase == wanted);
        },
        milliseconds);
    return done && !failed;
  }
  bool checkedCard() const {
    const auto rows = client->marketplaceSearchResults();
    if (rows.size() != 1)
      return false;
    const auto row = rows.first().toMap();
    const auto support = row.value("support").toMap();
    return row.value("extension_id") == fixture.extension &&
           row.value("release_id") == fixture.release &&
           row.value("metadata_only").toBool() &&
           support.value("discovery_qualified").toBool() &&
           support.value("verified_supporters").toInt() == 5 &&
           !support.value("is_global_total").toBool();
  }
  bool capture(const QString &name) {
    const auto path = fixture.captures + '/' + name;
    const auto image = window->grabWindow();
    return !QFile::exists(path) && !image.isNull() && image.save(path) &&
           QFile::setPermissions(path, QFileDevice::ReadOwner |
                                           QFileDevice::WriteOwner);
  }
  bool mark(const QString &stage, QJsonObject fields = {}) {
    fields.insert("stage", stage);
    fields.insert("sample", -1);
    const auto bytes =
        QJsonDocument(fields).toJson(QJsonDocument::Compact) + '\n';
    return progress.write(bytes) == bytes.size() && progress.flush();
  }
  QQuickWindow *window = nullptr;
  ApiClient *client = nullptr;
  SessionManager *session = nullptr;
  QFile progress;
};

namespace {
void scheduleTests() {
  QTimer::singleShot(0, QCoreApplication::instance(), [] {
    FullApplicationMarketplaceTests tests;
    const QStringList arguments{
        QStringLiteral("elixir-marketplace-full-app-tests"),
        fixture.live
            ? QStringLiteral(
                  "protected_owner_setup_navigation_and_install_opt_in")
            : QStringLiteral("offline_real_bootstrap_is_credential_isolated")};
    QCoreApplication::exit(QTest::qExec(&tests, arguments));
  });
}
} // namespace
Q_COREAPP_STARTUP_FUNCTION(scheduleTests)

int main(int argc, char *argv[]) {
  if (argc != 2 || (QByteArray(argv[1]) != "--offline" &&
                    QByteArray(argv[1]) != "--protected" &&
                    QByteArray(argv[1]) != "--validate-input"))
    return 2;
  fixture.live = QByteArray(argv[1]) != "--offline";
  // Inherited production automation must never override the explicit fixture
  // URL or introduce real credentials/playback into this test process.
  const auto environment = QProcessEnvironment::systemEnvironment();
  for (const auto &key : environment.keys())
    if ((key.startsWith("ELIXIR_CLIENT_") ||
         key.startsWith("ELIXIR_PLAYBACK_")) &&
        !environment.value(key).isEmpty())
      return 2;
#ifdef Q_OS_UNIX
  ::umask(0077);
#endif
  if (fixture.live && !readFixture())
    return 2;
  // Shape/ownership only: no app, settings, vault, logging or network action.
  if (QByteArray(argv[1]) == "--validate-input")
    return 0;
  QTemporaryDir settings;
  if (!settings.isValid())
    return 2;
  settings.setAutoRemove(false); // Retain diagnostics, including failed runs.
  fixture.privateRoot = QFileInfo(settings.path()).canonicalFilePath();
  if (!privateDirectory(fixture.privateRoot))
    return 2;
  QSettings::setDefaultFormat(QSettings::IniFormat);
  QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                     fixture.privateRoot);
  QSettings::setPath(QSettings::IniFormat, QSettings::SystemScope,
                     fixture.privateRoot + "/system");
  QSettings preferences(QSettings::IniFormat, QSettings::UserScope,
                        "ElixirMedia", "Elixir");
  preferences.setFallbacksEnabled(false);
  preferences.setValue("session/baseUrl", fixture.server);
  preferences.setValue("session/registryUrl", fixture.server);
  preferences.sync();
  if (preferences.status() != QSettings::NoError)
    return 2;
  std::fprintf(stdout, "ELIXIR_MARKETPLACE_FULL_APPLICATION_DIAGNOSTICS %s\n",
               QFile::encodeName(fixture.privateRoot).constData());
  std::fflush(stdout);
  int applicationArgc = 1;
  char *applicationArgv[] = {argv[0], nullptr};
  return runClientApplication(applicationArgc, applicationArgv,
                              {fixture.vault, fixture.privateRoot});
}

#include "FullApplicationMarketplaceTests.moc"
