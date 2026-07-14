#include "backend/ApiClient.h"
#include "backend/LivePlayerController.h"
#include "backend/MpvItem.h"
#include "live/LiveApiClient.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlComponent>
#include <QQuickView>
#include <QSGRendererInterface>
#include <QSettings>
#include <QSignalSpy>
#include <QTest>
#include <QTimer>
#include <QtQml>

#include <algorithm>
#include <functional>

namespace {

QString requiredEnvironment(const char *name) {
  return qEnvironmentVariable(name).trimmed();
}

bool waitUntil(const std::function<bool()> &predicate, int timeoutMs) {
  QElapsedTimer elapsed;
  elapsed.start();
  while (elapsed.elapsed() < timeoutMs) {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
    if (predicate()) {
      return true;
    }
    QTest::qWait(25);
  }
  return predicate();
}

QByteArray fileSha256(const QString &path) {
  QFile input(path);
  if (!input.open(QIODevice::ReadOnly)) {
    return {};
  }
  QCryptographicHash hash(QCryptographicHash::Sha256);
  if (!hash.addData(&input)) {
    return {};
  }
  return hash.result();
}

bool hasVisiblePixels(const QImage &image) {
  if (image.isNull()) {
    return false;
  }
  const QImage pixels = image.convertToFormat(QImage::Format_RGB32);
  for (int y = 0; y < pixels.height(); y += 8) {
    for (int x = 0; x < pixels.width(); x += 8) {
      const QColor color = pixels.pixelColor(x, y);
      if (color.red() > 16 || color.green() > 16 || color.blue() > 16) {
        return true;
      }
    }
  }
  return false;
}

QVariantMap observation(MpvItem *player) {
  const QVariant timePosition = player->getProperty(QStringLiteral("time-pos"));
  const QVariant duration = player->getProperty(QStringLiteral("duration"));
  const QVariant cacheTime =
      player->getProperty(QStringLiteral("demuxer-cache-time"));
  bool positionValid = false;
  bool durationValid = false;
  bool cacheValid = false;
  const double position = timePosition.toDouble(&positionValid);
  const double total = duration.toDouble(&durationValid);
  const double cache = cacheTime.toDouble(&cacheValid);
  double distance = 0.0;
  if (positionValid && cacheValid && cache >= position) {
    distance = cache - position;
  } else if (positionValid && durationValid && total >= position) {
    distance = total - position;
  }

  QVariantList audioTracks;
  QVariantList subtitleTracks;
  const QVariantList tracks =
      player->getProperty(QStringLiteral("track-list")).toList();
  for (const QVariant &entry : tracks) {
    const QVariantMap track = entry.toMap();
    const QString type = track.value(QStringLiteral("type")).toString();
    QVariantMap normalized{
        {QStringLiteral("id"), track.value(QStringLiteral("id")).toString()},
        {QStringLiteral("label"),
         track.value(QStringLiteral("title")).toString()},
        {QStringLiteral("language"),
         track.value(QStringLiteral("lang")).toString()},
        {QStringLiteral("title"),
         track.value(QStringLiteral("title")).toString()},
        {QStringLiteral("selected"),
         track.value(QStringLiteral("selected")).toBool()},
    };
    if (type == QStringLiteral("audio")) {
      audioTracks.push_back(normalized);
    } else if (type == QStringLiteral("sub")) {
      subtitleTracks.push_back(normalized);
    }
  }

  return {
      {QStringLiteral("coreIdle"),
       player->getProperty(QStringLiteral("core-idle")).toBool()},
      {QStringLiteral("pausedForCache"),
       player->getProperty(QStringLiteral("paused-for-cache")).toBool()},
      {QStringLiteral("paused"),
       player->getProperty(QStringLiteral("pause")).toBool()},
      {QStringLiteral("eofReached"),
       player->getProperty(QStringLiteral("eof-reached")).toBool()},
      {QStringLiteral("distanceFromLiveEdgeSeconds"), distance},
      {QStringLiteral("audioTracks"), audioTracks},
      {QStringLiteral("subtitleTracks"), subtitleTracks},
      {QStringLiteral("audioTrackId"),
       player->getProperty(QStringLiteral("aid")).toString()},
      {QStringLiteral("subtitleTrackId"),
       player->getProperty(QStringLiteral("sid")).toString()},
  };
}

QVariantList tracksOfType(MpvItem *player, const QString &type) {
  QVariantList result;
  const QVariantList tracks =
      player->getProperty(QStringLiteral("track-list")).toList();
  for (const QVariant &entry : tracks) {
    const QVariantMap track = entry.toMap();
    if (track.value(QStringLiteral("type")).toString() == type) {
      result.append(track);
    }
  }
  return result;
}

struct StreamFixture {
  QString id;
  QString key;
};

} // namespace

class RealServerLivePlaybackTests final : public QObject {
  Q_OBJECT

private slots:
  void initTestCase() {
    m_serverUrl = requiredEnvironment("ELIXIR_G30_SERVER_URL");
    m_email = requiredEnvironment("ELIXIR_G30_EMAIL");
    m_password = requiredEnvironment("ELIXIR_G30_PASSWORD");
    m_providerId = requiredEnvironment("ELIXIR_G30_PROVIDER_ID");
    m_itemKey = requiredEnvironment("ELIXIR_G30_ITEM_KEY");
    m_tlsCa = requiredEnvironment("ELIXIR_G30_TLS_CA");
    m_captureDir = requiredEnvironment("ELIXIR_G30_CAPTURE_DIR");
    const QByteArray streamsJson =
        qgetenv("ELIXIR_G30_STREAMS_JSON").trimmed();

    QVERIFY2(!m_serverUrl.isEmpty(), "ELIXIR_G30_SERVER_URL is required");
    QVERIFY2(!m_email.isEmpty(), "ELIXIR_G30_EMAIL is required");
    QVERIFY2(!m_password.isEmpty(), "ELIXIR_G30_PASSWORD is required");
    QVERIFY2(!m_providerId.isEmpty(), "ELIXIR_G30_PROVIDER_ID is required");
    QVERIFY2(!m_itemKey.isEmpty(), "ELIXIR_G30_ITEM_KEY is required");
    QVERIFY2(QFileInfo::exists(m_tlsCa), "ELIXIR_G30_TLS_CA must exist");
    QVERIFY2(QDir().mkpath(m_captureDir),
             "ELIXIR_G30_CAPTURE_DIR could not be created");

    QJsonParseError error;
    const QJsonDocument document =
        QJsonDocument::fromJson(streamsJson, &error);
    QCOMPARE(error.error, QJsonParseError::NoError);
    QVERIFY(document.isArray());
    for (const QJsonValue &entry : document.array()) {
      const QJsonObject object = entry.toObject();
      m_streams.push_back({object.value(QStringLiteral("id")).toString(),
                           object.value(QStringLiteral("key")).toString()});
    }
    QVERIFY2(!m_streams.isEmpty(), "at least one Live stream is required");
    QVERIFY2(m_streams.size() <= 8, "Live playback gate stream count is bounded");

    QCoreApplication::setOrganizationName(QStringLiteral("ElixirG30"));
    QCoreApplication::setApplicationName(QStringLiteral("LivePlaybackGate"));
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                       m_captureDir + QStringLiteral("/settings"));
    QSettings().clear();
    qmlRegisterType<MpvItem>("Elixir.Mpv", 1, 0, "MpvItem");
  }

  void g30_real_server_direct_protocol_matrix_has_moving_frames() {
    ApiClient auth;
    auth.setBaseUrl(m_serverUrl);
    QSignalSpy loginSucceeded(&auth, &ApiClient::loginSucceeded);
    QSignalSpy loginFailed(&auth, &ApiClient::loginFailed);
    auth.login(m_email, m_password);
    QVERIFY(waitUntil([&]() { return loginSucceeded.count() == 1; }, 10000));
    QCOMPARE(loginFailed.count(), 0);
    QVERIFY(auth.capabilities().contains(QStringLiteral("live_play")));

    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QQuickView view;
    view.setColor(Qt::black);
    view.resize(640, 360);
    QQmlComponent component(view.engine());
    component.setData(R"QML(
      import QtQuick 6.5
      import Elixir.Mpv 1.0
      Item {
        width: 640
        height: 360
        MpvItem { objectName: "g30Mpv"; anchors.fill: parent }
      }
    )QML",
                      QUrl(QStringLiteral("g30:/player.qml")));
    QVERIFY(waitUntil(
        [&]() { return component.status() != QQmlComponent::Loading; }, 5000));
    QVERIFY2(component.isReady(), qPrintable(component.errorString()));
    QObject *root = component.create();
    QVERIFY2(root, qPrintable(component.errorString()));
    view.setContent(QUrl(QStringLiteral("g30:/player.qml")), &component, root);
    view.show();
    QVERIFY(QTest::qWaitForWindowExposed(&view));
    auto *player = root->findChild<MpvItem *>(QStringLiteral("g30Mpv"));
    QVERIFY(player);
    player->setPropertyAsync(QStringLiteral("tls-ca-file"), m_tlsCa);
    player->setPropertyAsync(QStringLiteral("tls-verify"), true);
    player->setPropertyAsync(QStringLiteral("loop-file"), QStringLiteral("inf"));
    player->setPropertyAsync(QStringLiteral("ao"), QStringLiteral("null"));

    LiveApiClient api(&auth);
    LivePlayerController controller(&api);
    QVERIFY(controller.attachPlayer(player));
    QSignalSpy requestFailures(&api, &LiveApiClient::requestFailed);
    QSignalSpy sessionEnded(&api, &LiveApiClient::sessionEnded);
    QTimer observationTimer;
    observationTimer.setInterval(100);
    connect(&observationTimer, &QTimer::timeout, &controller,
            [&]() { controller.observeMpv(observation(player)); });
    observationTimer.start();

    int expectedEnded = 0;
    bool refreshedDuringPlayback = false;
    bool dvrCertified = false;
    bool sourceSwitchCertified = false;
    bool tracksCertified = false;
    bool preferencesRecovered = false;
    for (const StreamFixture &stream : m_streams) {
      controller.start(m_providerId, m_itemKey, stream.key,
                       QStringLiteral("G30 %1").arg(stream.id));
      const bool sessionStarted = waitUntil(
          [&]() { return !controller.sessionId().isEmpty(); }, 10000);
      const QString requestMessage = requestFailures.isEmpty()
                                         ? QString()
                                         : requestFailures.last()
                                               .at(3)
                                               .toMap()
                                               .value(QStringLiteral("message"))
                                               .toString();
      QVERIFY2(sessionStarted,
               qPrintable(QStringLiteral(
                              "session did not start for %1: %2 (%3)")
                              .arg(stream.id, controller.errorCode(),
                                   requestMessage)));
      const auto playbackDiagnostics = [&]() {
        const QVariant configuredHeaders =
            player->getProperty(QStringLiteral("http-header-fields"));
        return QStringLiteral(
                   "state=%1 error=%2 delivery=%3 authHeader=%4 coreIdle=%5 "
                   "pausedForCache=%6 fileFormat=%7 path=%8 playbackUrl=%9 "
                   "headerType=%10 headerCount=%11")
            .arg(controller.state(), controller.errorCode(),
                 player->delivery(),
                 player->authorizationHeaderActive() ? QStringLiteral("yes")
                                                     : QStringLiteral("no"),
                 player->getProperty(QStringLiteral("core-idle")).toString(),
                 player->getProperty(QStringLiteral("paused-for-cache"))
                     .toString(),
                 player->getProperty(QStringLiteral("file-format")).toString(),
                 player->getProperty(QStringLiteral("path")).toString(),
                 controller.playbackUrl(),
                 QString::fromUtf8(configuredHeaders.typeName()),
                 QString::number(configuredHeaders.toList().size()));
      };
      QVERIFY2(waitUntil(
                   [&]() {
                     bool valid = false;
                     const double position =
                         player->getProperty(QStringLiteral("time-pos"))
                             .toDouble(&valid);
                     return valid && position >= 0.35 &&
                            controller.state() == QStringLiteral("playing");
                   },
                   15000),
               qPrintable(QStringLiteral("mpv did not play %1: %2")
                              .arg(stream.id, playbackDiagnostics())));

      if (stream.id == QStringLiteral("hls")) {
        QVERIFY(controller.seekable());
        QCOMPARE(controller.windowSeconds(), 4);
        player->setPropertyAsync(QStringLiteral("pause"), true);
        QVERIFY(waitUntil(
            [&]() {
              controller.observeMpv(observation(player));
              return controller.state() == QStringLiteral("paused");
            },
            3000));
        const double beforeSeek =
            player->getProperty(QStringLiteral("time-pos")).toDouble();
        const double targetPosition = std::max(0.0, beforeSeek - 1.0);
        const double seekDelta =
            controller.seekDeltaForWindowPosition(targetPosition);
        player->commandAsync(QStringList{QStringLiteral("seek"),
                                         QString::number(seekDelta, 'f', 3),
                                         QStringLiteral("relative"),
                                         QStringLiteral("exact")});
        QVERIFY(waitUntil(
            [&]() {
              return player->getProperty(QStringLiteral("time-pos"))
                         .toDouble() <=
                     targetPosition + 0.2;
            },
            3000));
        player->commandAsync(QStringList{QStringLiteral("seek"),
                                         QStringLiteral("100"),
                                         QStringLiteral("absolute-percent"),
                                         QStringLiteral("exact")});
        QVERIFY(waitUntil(
            [&]() {
              bool valid = false;
              const double position =
                  player->getProperty(QStringLiteral("time-pos"))
                      .toDouble(&valid);
              return valid && position >= 3.5;
            },
            3000));
        player->setPropertyAsync(QStringLiteral("pause"), false);
        dvrCertified = true;

        const QVariantList sources = controller.availableSources();
        QCOMPARE(sources.size(), 2);
        const QVariantMap backup = sources.at(1).toMap();
        QCOMPARE(backup.value(QStringLiteral("quality")).toString(),
                 QStringLiteral("720p"));
        controller.switchSource(
            backup.value(QStringLiteral("sourceKey")).toString());
        QVERIFY(waitUntil(
            [&]() {
              return controller.state() == QStringLiteral("playing") &&
                     controller.selectedSourceLabel() ==
                         QStringLiteral("Direct Backup") &&
                     controller.selectedSourceQuality() ==
                         QStringLiteral("720p");
            },
            10000));
        QVERIFY(!controller.seekable());
        sourceSwitchCertified = true;
      }

      if (stream.id == QStringLiteral("progressive")) {
        QVERIFY(waitUntil(
            [&]() {
              return tracksOfType(player, QStringLiteral("audio")).size() >= 2 &&
                     !tracksOfType(player, QStringLiteral("sub")).isEmpty();
            },
            5000));
        const QVariantList audio =
            tracksOfType(player, QStringLiteral("audio"));
        const QVariantList subtitles =
            tracksOfType(player, QStringLiteral("sub"));
        const QString alternateAudio =
            audio.at(1).toMap().value(QStringLiteral("id")).toString();
        const QString captions =
            subtitles.first().toMap().value(QStringLiteral("id")).toString();
        const qint64 revisionBeforeTracks = controller.revision();
        player->setPropertyAsync(QStringLiteral("aid"), alternateAudio);
        controller.selectTrack(QStringLiteral("audio"), alternateAudio);
        player->setPropertyAsync(QStringLiteral("sid"), captions);
        controller.selectTrack(QStringLiteral("subtitle"), captions);
        QVERIFY(waitUntil(
            [&]() {
              controller.observeMpv(observation(player));
              return player->getProperty(QStringLiteral("aid")).toString() ==
                         alternateAudio &&
                     player->getProperty(QStringLiteral("sid")).toString() ==
                         captions &&
                     controller.revision() >= revisionBeforeTracks + 2;
            },
            5000));
        tracksCertified = true;
      }

      if (stream.id == QStringLiteral("mpegts") && tracksCertified) {
        QCOMPARE(controller.preferredAudioTrack()
                     .value(QStringLiteral("language"))
                     .toString(),
                 QStringLiteral("spa"));
        QCOMPARE(controller.preferredSubtitleTrack()
                     .value(QStringLiteral("language"))
                     .toString(),
                 QStringLiteral("eng"));
        preferencesRecovered = true;
      }

      if (!refreshedDuringPlayback) {
        const QString refreshBefore = auth.refreshToken();
        auth.setAccessTokenExpiresAt(
            QDateTime::currentDateTimeUtc().addSecs(-1).toString(Qt::ISODate));
        controller.sendHeartbeatNow();
        QVERIFY(waitUntil(
            [&]() {
              return !auth.refreshInFlight() &&
                     auth.refreshToken() != refreshBefore;
            },
            10000));
        QVERIFY(controller.state() != QStringLiteral("failed"));
        refreshedDuringPlayback = true;
      }

      const QString firstPath =
          QStringLiteral("%1/%2-a.png").arg(m_captureDir, stream.id);
      const QString secondPath =
          QStringLiteral("%1/%2-b.png").arg(m_captureDir, stream.id);
      const QImage first = view.grabWindow();
      QVERIFY(!first.isNull());
      QVERIFY(hasVisiblePixels(first));
      QVERIFY(first.save(firstPath, "PNG"));
      const double firstPosition =
          player->getProperty(QStringLiteral("time-pos")).toDouble();
      QVERIFY(waitUntil(
          [&]() {
            return player->getProperty(QStringLiteral("time-pos")).toDouble() >=
                   firstPosition + 0.45;
          },
          5000));
      const QImage second = view.grabWindow();
      QVERIFY(!second.isNull());
      QVERIFY(hasVisiblePixels(second));
      QVERIFY(second.save(secondPath, "PNG"));
      QCOMPARE(first.size(), second.size());
      QVERIFY(first.width() >= 320);
      QVERIFY(first.height() >= 180);
      const QByteArray firstHash = fileSha256(firstPath);
      const QByteArray secondHash = fileSha256(secondPath);
      QVERIFY(!firstHash.isEmpty());
      QVERIFY(!secondHash.isEmpty());
      QVERIFY2(firstHash != secondHash,
               qPrintable(QStringLiteral("decoded frames did not move for %1")
                              .arg(stream.id)));

      ++expectedEnded;
      controller.stop();
      player->commandAsync(QStringList{QStringLiteral("stop")});
      QVERIFY(waitUntil(
          [&]() { return sessionEnded.count() >= expectedEnded; }, 10000));
      QCOMPARE(controller.state(), QStringLiteral("ended"));
      QCOMPARE(controller.sessionId(), QString());
    }

    observationTimer.stop();
    QCOMPARE(requestFailures.count(), 0);
    QVERIFY(refreshedDuringPlayback);
    QVERIFY(dvrCertified);
    QVERIFY(sourceSwitchCertified);
    QVERIFY(tracksCertified);
    QVERIFY(preferencesRecovered);
    QSignalSpy logoutCompleted(&auth, &ApiClient::logoutCompleted);
    auth.logout();
    QVERIFY(waitUntil([&]() { return logoutCompleted.count() == 1; }, 10000));
    view.close();
  }

private:
  QString m_serverUrl;
  QString m_email;
  QString m_password;
  QString m_providerId;
  QString m_itemKey;
  QString m_tlsCa;
  QString m_captureDir;
  QList<StreamFixture> m_streams;
};

int main(int argc, char **argv) {
#if defined(Q_OS_MACOS)
  qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("cocoa"));
#elif defined(Q_OS_WIN)
  qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("windows"));
#endif
  qputenv("QSG_RHI_BACKEND", QByteArrayLiteral("opengl"));
  QGuiApplication application(argc, argv);
  RealServerLivePlaybackTests tests;
  return QTest::qExec(&tests, argc, argv);
}

#include "RealServerLivePlaybackTests.moc"
