#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QMutex>
#include <QMutexLocker>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSGRendererInterface>
#include <QStandardPaths>
#include <QStringList>
#include <QTextStream>
#include <QTimer>
#include <QUrl>
#include <QtGlobal>
#include <QtQml>

#include "backend/ApiClient.h"
#include "backend/ControlPlaneClient.h"
#include "backend/LibraryModel.h"
#include "backend/LivePlayerController.h"
#include "backend/MpvItem.h"
#include "backend/PlayerController.h"
#include "backend/ServerDiscovery.h"
#include "backend/SessionManager.h"
#include "live/LiveApiClient.h"
#include "live/LiveCatalogModel.h"
#include "live/LiveQmlNetworkAccessManagerFactory.h"

namespace {
QFile *g_logFile = nullptr;
QMutex g_logMutex;

QString logLevelName(QtMsgType type) {
  switch (type) {
  case QtDebugMsg:
    return "DEBUG";
  case QtInfoMsg:
    return "INFO";
  case QtWarningMsg:
    return "WARN";
  case QtCriticalMsg:
    return "CRITICAL";
  case QtFatalMsg:
    return "FATAL";
  }
  return "LOG";
}

QString redactSensitiveLogText(QString text) {
  static const QRegularExpression querySecret(
      QStringLiteral("((?:[?&;]|\\b)(?:session|sid|token|access_token|x-plex-"
                     "token)=)([^\\s&;\\\"']+)"),
      QRegularExpression::CaseInsensitiveOption);
  static const QRegularExpression bearerSecret(
      QStringLiteral("(Bearer\\s+)([^\\s\\\"']+)"),
      QRegularExpression::CaseInsensitiveOption);

  text.replace(querySecret, QStringLiteral("\\1[redacted]"));
  text.replace(bearerSecret, QStringLiteral("\\1[redacted]"));
  return text;
}

void logMessageHandler(QtMsgType type, const QMessageLogContext &context,
                       const QString &msg) {
  const QString timestamp =
      QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
  const QString level = logLevelName(type);
  const QString category =
      QString::fromUtf8(context.category ? context.category : "");
  QString line = redactSensitiveLogText(
      QString("%1 [%2] %3: %4").arg(timestamp, level, category, msg));
  if (context.file && context.line > 0) {
    line.append(QString(" (%1:%2)").arg(context.file).arg(context.line));
  }

  {
    QMutexLocker locker(&g_logMutex);
    if (g_logFile && g_logFile->isOpen()) {
      QTextStream out(g_logFile);
      out << line << '\n';
      out.flush();
    }
  }
  fprintf(stderr, "%s\n", line.toUtf8().constData());
  if (type == QtFatalMsg) {
    abort();
  }
}

void initLogging() {
  const QString logDir =
      QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
  if (!logDir.isEmpty()) {
    QDir().mkpath(logDir);
    const QString logPath = logDir + "/client.log";
    g_logFile = new QFile(logPath);
    g_logFile->open(QIODevice::Append | QIODevice::Text);
  }
  qInstallMessageHandler(logMessageHandler);
  qInfo() << "Elixir client logging to"
          << (g_logFile ? g_logFile->fileName() : "stderr");
}

void loadFonts() {
  if (QFontDatabase::addApplicationFont(":/fonts/OpenSans.ttf") < 0) {
    qWarning() << "Failed to load Open Sans font resource";
  }
  if (QFontDatabase::addApplicationFont(":/fonts/OpenSans-Italic.ttf") < 0) {
    qWarning() << "Failed to load Open Sans italic font resource";
  }
  QGuiApplication::setFont(QFont(QStringLiteral("Open Sans")));
}
} // namespace

int main(int argc, char *argv[]) {
  qputenv("QSG_RHI_BACKEND", "opengl");
  QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

  QGuiApplication app(argc, argv);
  QCoreApplication::setOrganizationName("ElixirMedia");
  QCoreApplication::setApplicationName("Elixir");
  QCoreApplication::setApplicationVersion("0.1.0");

  QQuickStyle::setStyle("Fusion");
  initLogging();
  loadFonts();
  qInfo() << "Elixir client starting"
          << QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

  SessionManager sessionManager;
  const QString automationBaseUrl =
      qEnvironmentVariable("ELIXIR_CLIENT_BASE_URL").trimmed();
  const QString automationAuthToken =
      qEnvironmentVariable("ELIXIR_CLIENT_AUTH_TOKEN").trimmed();
  const QString automationAccessExpiresAt =
      qEnvironmentVariable("ELIXIR_CLIENT_ACCESS_TOKEN_EXPIRES_AT").trimmed();
  const QString automationNetworkType =
      qEnvironmentVariable("ELIXIR_CLIENT_NETWORK_TYPE").trimmed();
  const QString automationAutoplayMediaId =
      qEnvironmentVariable("ELIXIR_CLIENT_AUTOPLAY_MEDIA_ITEM_ID").trimmed();
  const QString automationAutoplayFileId =
      qEnvironmentVariable("ELIXIR_CLIENT_AUTOPLAY_MEDIA_FILE_ID").trimmed();
  const QString automationAutoplayEpisodeId =
      qEnvironmentVariable("ELIXIR_CLIENT_AUTOPLAY_EPISODE_ID").trimmed();
  const QString automationActions =
      qEnvironmentVariable("ELIXIR_CLIENT_AUTOMATION_ACTIONS").trimmed();
  const QString automationCaptureDir =
      qEnvironmentVariable("ELIXIR_PLAYBACK_AUTOMATION_CAPTURE_DIR").trimmed();
  const QString automationCapabilitiesJson =
      qEnvironmentVariable("ELIXIR_CLIENT_CAPABILITIES_JSON").trimmed();
  if (!automationBaseUrl.isEmpty()) {
    sessionManager.setBaseUrlRuntimeOverride(automationBaseUrl);
    sessionManager.setRegistryUrlRuntimeOverride(automationBaseUrl);
  }
  if (!automationAuthToken.isEmpty()) {
    sessionManager.setAuthTokenRuntimeOverride(automationAuthToken);
  }
  if (!automationAccessExpiresAt.isEmpty()) {
    sessionManager.setAccessTokenExpiresAtRuntimeOverride(
        automationAccessExpiresAt);
  }
  if (!automationNetworkType.isEmpty()) {
    sessionManager.setNetworkTypeRuntimeOverride(automationNetworkType);
  }

  ApiClient apiClient;
  ControlPlaneClient controlPlaneClient;
  LibraryModel libraryModel;
  PlayerController playerController;
  ServerDiscovery serverDiscovery;
  LiveApiClient liveApiClient(&apiClient);
  LiveCatalogModel liveCatalogModel(&liveApiClient);
  LivePlayerController livePlayerController(&liveApiClient);
  QObject::connect(
      &apiClient, &ApiClient::extensionAccountSetupCompleted,
      &liveCatalogModel,
      [&liveCatalogModel](const QString &, const QString &, const QString &) {
        liveCatalogModel.refreshIndex();
        QTimer::singleShot(1500, &liveCatalogModel,
                           [&liveCatalogModel]() {
                             liveCatalogModel.refreshIndex();
                           });
      });

  const QString controlExpiry = sessionManager.controlPlaneExpiresAt();
  if (!sessionManager.controlPlaneToken().isEmpty() &&
      !controlExpiry.isEmpty()) {
    const QDateTime expiresAt =
        QDateTime::fromString(controlExpiry, Qt::ISODate);
    if (expiresAt.isValid() && expiresAt < QDateTime::currentDateTimeUtc()) {
      sessionManager.clearControlPlaneAuth();
    }
  }

  qmlRegisterType<MpvItem>("Elixir.Mpv", 1, 0, "MpvItem");
  qmlRegisterSingletonType(QUrl(QStringLiteral("qrc:/qml/Theme.qml")), "Elixir",
                           1, 0, "Theme");

  apiClient.setBaseUrl(sessionManager.baseUrl());
  apiClient.setAuthToken(sessionManager.authToken());
  apiClient.setAccessTokenExpiresAt(sessionManager.accessTokenExpiresAt());
  apiClient.setRefreshToken(sessionManager.refreshToken());
  apiClient.setSessionState(sessionManager.sessionState());
  apiClient.setNetworkType(sessionManager.networkType());
  libraryModel.setBaseUrl(sessionManager.baseUrl());
  controlPlaneClient.setBaseUrl(sessionManager.registryUrl());
  controlPlaneClient.setAuthToken(sessionManager.controlPlaneToken());
  controlPlaneClient.setAccessTokenExpiresAt(
      sessionManager.controlPlaneExpiresAt());
  serverDiscovery.setRegistryBaseUrl(sessionManager.registryUrl());
  serverDiscovery.setAuthToken(sessionManager.controlPlaneToken());
  serverDiscovery.setPreferredNetworkType(sessionManager.networkType());

  auto syncClientCapabilities = [&]() {
    QVariantMap caps;
    caps.insert("profile_id", "native_mpv_desktop");
    caps.insert("profile_version", 5);
    caps.insert("client_kind", "native_mpv");
    caps.insert("direct_play_preferred", true);
    caps.insert("quality_mode", sessionManager.playbackQualityMode());
    caps.insert("abr_support_type", "mpv");
    caps.insert("max_resolution", sessionManager.playbackMaxResolution());
    caps.insert("max_bitrate_bps", sessionManager.playbackMaxBitrateBps());
    caps.insert("supported_containers",
                sessionManager.playbackSupportedContainers());
    caps.insert("supported_video_codecs",
                sessionManager.playbackSupportedVideoCodecs());
    caps.insert("supported_audio_codecs",
                sessionManager.playbackSupportedAudioCodecs());
    caps.insert("supported_subtitle_codecs",
                QStringList({"srt", "webvtt", "ass", "ssa", "mov_text", "pgs",
                             "dvd_subtitle"}));
    caps.insert("supported_hls_segment_types", QStringList({"mpegts", "fmp4"}));
    caps.insert("supports_hdr", true);
    caps.insert("supports_hdr10_plus", true);
    caps.insert("supports_dolby_vision", false);
    caps.insert("supports_server_side_hls_seek", true);
    caps.insert("supports_auth_headers_for_media", true);
    caps.insert("supports_native_text_subtitles", true);
    caps.insert("strict_h264_profile_limits", false);
    caps.insert("subtitle_burn_policy", "automatic");
    caps.insert("subtitle_rendering", "native");
    caps.insert("ass_complexity_support", "native");
    caps.insert("image_subtitle_support", "native_or_burn_in");
    caps.insert("forced_subtitle_policy", "matching_audio");
    caps.insert("default_subtitle_policy",
                sessionManager.subtitleMode() == "off" ? "disabled"
                                                       : "media_default");
    caps.insert("subtitle_mode", sessionManager.subtitleMode());
    caps.insert("preferred_subtitle_language", sessionManager.subtitleLang());
    caps.insert("preferred_subtitle_title", sessionManager.subtitleTitle());
    caps.insert("app_version", QCoreApplication::applicationVersion());
    if (!automationCapabilitiesJson.isEmpty()) {
      QJsonParseError parseError;
      const QJsonDocument doc = QJsonDocument::fromJson(
          automationCapabilitiesJson.toUtf8(), &parseError);
      if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "Ignoring invalid ELIXIR_CLIENT_CAPABILITIES_JSON"
                   << parseError.errorString();
      } else {
        const QJsonObject overrides = doc.object();
        for (auto it = overrides.constBegin(); it != overrides.constEnd();
             ++it) {
          caps.insert(it.key(), it.value().toVariant());
        }
      }
    }
    apiClient.setClientCapabilities(caps);
  };
  syncClientCapabilities();

  QObject::connect(&sessionManager, &SessionManager::baseUrlChanged, &apiClient,
                   [&]() { apiClient.setBaseUrl(sessionManager.baseUrl()); });
  QObject::connect(
      &sessionManager, &SessionManager::baseUrlChanged, &libraryModel,
      [&]() { libraryModel.setBaseUrl(sessionManager.baseUrl()); });
  QObject::connect(
      &sessionManager, &SessionManager::authTokenChanged, &apiClient,
      [&]() { apiClient.setAuthToken(sessionManager.authToken()); });
  QObject::connect(&sessionManager,
                   &SessionManager::accessTokenExpiresAtChanged, &apiClient,
                   [&]() {
                     apiClient.setAccessTokenExpiresAt(
                         sessionManager.accessTokenExpiresAt());
                   });
  QObject::connect(
      &sessionManager, &SessionManager::refreshTokenChanged, &apiClient,
      [&]() { apiClient.setRefreshToken(sessionManager.refreshToken()); });
  QObject::connect(
      &sessionManager, &SessionManager::networkTypeChanged, &apiClient,
      [&]() { apiClient.setNetworkType(sessionManager.networkType()); });
  QObject::connect(&sessionManager, &SessionManager::registryUrlChanged,
                   &serverDiscovery, [&]() {
                     serverDiscovery.setRegistryBaseUrl(
                         sessionManager.registryUrl());
                   });
  QObject::connect(
      &sessionManager, &SessionManager::registryUrlChanged, &controlPlaneClient,
      [&]() { controlPlaneClient.setBaseUrl(sessionManager.registryUrl()); });
  QObject::connect(&sessionManager, &SessionManager::controlPlaneTokenChanged,
                   &controlPlaneClient, [&]() {
                     controlPlaneClient.setAuthToken(
                         sessionManager.controlPlaneToken());
                   });
  QObject::connect(&sessionManager,
                   &SessionManager::controlPlaneExpiresAtChanged,
                   &controlPlaneClient, [&]() {
                     controlPlaneClient.setAccessTokenExpiresAt(
                         sessionManager.controlPlaneExpiresAt());
                   });
  QObject::connect(&sessionManager, &SessionManager::controlPlaneTokenChanged,
                   &serverDiscovery, [&]() {
                     serverDiscovery.setAuthToken(
                         sessionManager.controlPlaneToken());
                   });
  QObject::connect(&sessionManager, &SessionManager::networkTypeChanged,
                   &serverDiscovery, [&]() {
                     serverDiscovery.setPreferredNetworkType(
                         sessionManager.networkType());
                   });
  QObject::connect(&sessionManager, &SessionManager::playbackQualityModeChanged,
                   &apiClient, syncClientCapabilities);
  QObject::connect(&sessionManager,
                   &SessionManager::playbackMaxResolutionChanged, &apiClient,
                   syncClientCapabilities);
  QObject::connect(&sessionManager,
                   &SessionManager::playbackMaxBitrateBpsChanged, &apiClient,
                   syncClientCapabilities);
  QObject::connect(&sessionManager,
                   &SessionManager::playbackSupportedContainersChanged,
                   &apiClient, syncClientCapabilities);
  QObject::connect(&sessionManager,
                   &SessionManager::playbackSupportedVideoCodecsChanged,
                   &apiClient, syncClientCapabilities);
  QObject::connect(&sessionManager,
                   &SessionManager::playbackSupportedAudioCodecsChanged,
                   &apiClient, syncClientCapabilities);
  QObject::connect(&sessionManager, &SessionManager::subtitleModeChanged,
                   &apiClient, syncClientCapabilities);
  QObject::connect(&sessionManager, &SessionManager::subtitleLangChanged,
                   &apiClient, syncClientCapabilities);
  QObject::connect(&sessionManager, &SessionManager::subtitleTitleChanged,
                   &apiClient, syncClientCapabilities);

  QObject::connect(
      &apiClient, &ApiClient::authTokenChanged, &sessionManager,
      [&]() { sessionManager.setAuthToken(apiClient.authToken()); });
  QObject::connect(&apiClient, &ApiClient::accessTokenExpiresAtChanged,
                   &sessionManager, [&]() {
                     sessionManager.setAccessTokenExpiresAt(
                         apiClient.accessTokenExpiresAt());
                   });
  QObject::connect(
      &apiClient, &ApiClient::refreshTokenChanged, &sessionManager,
      [&]() { sessionManager.setRefreshToken(apiClient.refreshToken()); });
  bool syncingSessionState = false;
  QObject::connect(&apiClient, &ApiClient::sessionStateChanged, &sessionManager,
                   [&]() {
                     if (syncingSessionState) {
                       return;
                     }
                     syncingSessionState = true;
                     sessionManager.setSessionState(apiClient.sessionState());
                     syncingSessionState = false;
                   });
  QObject::connect(&sessionManager, &SessionManager::sessionStateChanged,
                   &apiClient, [&]() {
                     if (syncingSessionState) {
                       return;
                     }
                     syncingSessionState = true;
                     apiClient.setSessionState(sessionManager.sessionState());
                     syncingSessionState = false;
                   });
  QObject::connect(&controlPlaneClient, &ControlPlaneClient::authTokenChanged,
                   &sessionManager, [&]() {
                     sessionManager.setControlPlaneToken(
                         controlPlaneClient.authToken());
                   });
  QObject::connect(&controlPlaneClient,
                   &ControlPlaneClient::accessTokenExpiresAtChanged,
                   &sessionManager, [&]() {
                     sessionManager.setControlPlaneExpiresAt(
                         controlPlaneClient.accessTokenExpiresAt());
                   });

  QObject::connect(&apiClient, &ApiClient::libraryReceived, &libraryModel,
                   &LibraryModel::setItems);

  playerController.setApiClient(&apiClient);
  QObject::connect(&app, &QCoreApplication::aboutToQuit, &app, [&]() {
    livePlayerController.stop();
    const QString sessionId = playerController.sessionId();
    if (!sessionId.isEmpty()) {
      qInfo() << "Ending playback session during shutdown" << sessionId;
      apiClient.endSessionBlocking(sessionId, 1500);
    }
  });

  LiveQmlNetworkAccessManagerFactory liveQmlNetworkFactory(&apiClient);
  QQmlApplicationEngine engine;
  engine.setNetworkAccessManagerFactory(&liveQmlNetworkFactory);
  QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app,
                   [](const QList<QQmlError> &warnings) {
                     for (const auto &warning : warnings) {
                       qWarning().noquote()
                           << "QML warning:" << warning.toString();
                     }
                   });
  engine.rootContext()->setContextProperty("apiClient", &apiClient);
  engine.rootContext()->setContextProperty("controlPlaneClient",
                                           &controlPlaneClient);
  engine.rootContext()->setContextProperty("libraryModel", &libraryModel);
  engine.rootContext()->setContextProperty("liveCatalogModel",
                                           &liveCatalogModel);
  engine.rootContext()->setContextProperty("liveApiClient", &liveApiClient);
  engine.rootContext()->setContextProperty("livePlayerController",
                                           &livePlayerController);
  engine.rootContext()->setContextProperty("playerController",
                                           &playerController);
  engine.rootContext()->setContextProperty("playbackAutomationActions",
                                           automationActions);
  engine.rootContext()->setContextProperty("playbackAutomationCaptureDir",
                                           automationCaptureDir);
  engine.rootContext()->setContextProperty("serverDiscovery", &serverDiscovery);
  engine.rootContext()->setContextProperty("sessionManager", &sessionManager);

  const QUrl url(QStringLiteral("qrc:/qml/main.qml"));
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreated, &app,
      [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl) {
          QCoreApplication::exit(-1);
        }
      },
      Qt::QueuedConnection);
  engine.load(url);

  if (!automationAutoplayMediaId.isEmpty()) {
    QTimer::singleShot(
        0, &app,
        [&apiClient, automationAutoplayMediaId, automationAutoplayFileId,
         automationAutoplayEpisodeId]() {
          if (!automationAutoplayEpisodeId.isEmpty()) {
            qInfo() << "Automation autoplay starting episode playback"
                    << automationAutoplayMediaId << automationAutoplayEpisodeId;
            apiClient.startEpisodePlayback(automationAutoplayMediaId,
                                           automationAutoplayEpisodeId);
          } else {
            qInfo() << "Automation autoplay starting media playback"
                    << automationAutoplayMediaId << automationAutoplayFileId;
            apiClient.startPlayback(automationAutoplayMediaId,
                                    automationAutoplayFileId);
          }
        });
  }

  return app.exec();
}
