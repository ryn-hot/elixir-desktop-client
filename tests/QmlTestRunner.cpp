#include <QFile>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
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
  }
};

QUICK_TEST_MAIN_WITH_SETUP(elixir_qml, QmlTestSetup)

#include "QmlTestRunner.moc"
