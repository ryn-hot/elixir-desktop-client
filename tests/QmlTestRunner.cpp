#include <QFile>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickStyle>
#include <QUrl>
#include <QtQml>
#include <QtQuickTest/quicktest.h>

class QmlTestSetup final : public QObject {
  Q_OBJECT

public slots:
  void applicationAvailable() {
    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/OpenSans.ttf"));
    QFontDatabase::addApplicationFont(
        QStringLiteral(":/fonts/OpenSans-Italic.ttf"));
    QGuiApplication::setFont(QFont(QStringLiteral("Open Sans")));
    const QString themePath = QStringLiteral(QUICK_TEST_SOURCE_DIR) +
                              QStringLiteral("/../../src/qml/Theme.qml");
    qmlRegisterSingletonType(QUrl::fromLocalFile(themePath), "Elixir", 1, 0,
                             "Theme");
  }

  void qmlEngineAvailable(QQmlEngine *engine) {
    QFile golden(QStringLiteral(QUICK_TEST_SOURCE_DIR) +
                 QStringLiteral("/../goldens/live-accessibility-tree.json"));
    if (!golden.open(QIODevice::ReadOnly)) {
      qFatal("Unable to open the Live accessibility golden");
    }
    QJsonParseError parseError;
    const QJsonDocument goldenDocument =
        QJsonDocument::fromJson(golden.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError ||
        !goldenDocument.isObject()) {
      qFatal("Unable to parse the Live accessibility golden");
    }
    engine->rootContext()->setContextProperty(
        QStringLiteral("liveAccessibilityGolden"),
        goldenDocument.object().toVariantMap());
    engine->rootContext()->setContextProperty(
        QStringLiteral("c12CaptureDir"),
        qEnvironmentVariable("ELIXIR_C12_CAPTURE_DIR"));
    engine->rootContext()->setContextProperty(
        QStringLiteral("marketplaceCaptureDir"),
        qEnvironmentVariable("ELIXIR_MARKETPLACE_CAPTURE_DIR"));
    // Match ApiClient's QJsonObject::toVariantMap() projection, including the
    // native nested empty tag list. A JS-only mock can hide Qt list-conversion
    // problems in the setup-to-browse handoff.
    engine->rootContext()->setContextProperty(
        QStringLiteral("marketplacePreparedSearchFixture"),
        QJsonObject{
            {QStringLiteral("phase"), QStringLiteral("ready")},
            {QStringLiteral("query_id"),
             QStringLiteral("70000000-0000-4000-8000-000000000008")},
            {QStringLiteral("query"),
             QJsonObject{{QStringLiteral("text"), QString()},
                         {QStringLiteral("tags"), QJsonArray{}},
                         {QStringLiteral("limit"), 20}}},
            {QStringLiteral("preparation"), QJsonObject{
                {QStringLiteral("schema_version"), 1}, {QStringLiteral("phase"), QStringLiteral("waiting")},
                {QStringLiteral("scope"), QStringLiteral("current_local_catalog")},
                {QStringLiteral("examined"), 43}, {QStringLiteral("available"), 40},
                {QStringLiteral("omitted"), 3}, {QStringLiteral("pages"), 3},
                {QStringLiteral("received"), 60},
                {QStringLiteral("local_pass_complete"), false}, {QStringLiteral("network_complete"), false},
                {QStringLiteral("metadata_only"), true}}}}
            .toVariantMap());
  }
};

QUICK_TEST_MAIN_WITH_SETUP(elixir_qml, QmlTestSetup)

#include "QmlTestRunner.moc"
