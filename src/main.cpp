#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtQml>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QUrl>
#include <QDateTime>

#include "backend/ApiClient.h"
#include "backend/ControlPlaneClient.h"
#include "backend/LibraryModel.h"
#include "backend/MpvItem.h"
#include "backend/PlayerController.h"
#include "backend/ServerDiscovery.h"
#include "backend/SessionManager.h"

int main(int argc, char *argv[]) {
    qputenv("QSG_RHI_BACKEND", "opengl");
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName("ElixirMedia");
    QCoreApplication::setApplicationName("Elixir");

    QQuickStyle::setStyle("Fusion");

    SessionManager sessionManager;
    ApiClient apiClient;
    ControlPlaneClient controlPlaneClient;
    LibraryModel libraryModel;
    PlayerController playerController;
    ServerDiscovery serverDiscovery;

    const QString expiry = sessionManager.accessTokenExpiresAt();
    if (!sessionManager.authToken().isEmpty() && !expiry.isEmpty()) {
        const QDateTime expiresAt = QDateTime::fromString(expiry, Qt::ISODate);
        if (expiresAt.isValid() && expiresAt < QDateTime::currentDateTimeUtc()) {
            sessionManager.clearAuth();
        }
    }
    const QString controlExpiry = sessionManager.controlPlaneExpiresAt();
    if (!sessionManager.controlPlaneToken().isEmpty() && !controlExpiry.isEmpty()) {
        const QDateTime expiresAt = QDateTime::fromString(controlExpiry, Qt::ISODate);
        if (expiresAt.isValid() && expiresAt < QDateTime::currentDateTimeUtc()) {
            sessionManager.clearControlPlaneAuth();
        }
    }

    qmlRegisterType<MpvItem>("Elixir.Mpv", 1, 0, "MpvItem");
    qmlRegisterSingletonType(QUrl(QStringLiteral("qrc:/qml/Theme.qml")), "Elixir", 1, 0, "Theme");

    apiClient.setBaseUrl(sessionManager.baseUrl());
    apiClient.setAuthToken(sessionManager.authToken());
    apiClient.setAccessTokenExpiresAt(sessionManager.accessTokenExpiresAt());
    apiClient.setNetworkType(sessionManager.networkType());
    controlPlaneClient.setBaseUrl(sessionManager.registryUrl());
    controlPlaneClient.setAuthToken(sessionManager.controlPlaneToken());
    controlPlaneClient.setAccessTokenExpiresAt(sessionManager.controlPlaneExpiresAt());
    serverDiscovery.setRegistryBaseUrl(sessionManager.registryUrl());
    serverDiscovery.setAuthToken(sessionManager.controlPlaneToken());
    serverDiscovery.setPreferredNetworkType(sessionManager.networkType());

    auto syncClientCapabilities = [&]() {
        QVariantMap caps;
        caps.insert("max_resolution", sessionManager.playbackMaxResolution());
        caps.insert("max_bitrate_bps", sessionManager.playbackMaxBitrateBps());
        caps.insert("supported_containers", sessionManager.playbackSupportedContainers());
        caps.insert("supported_video_codecs", sessionManager.playbackSupportedVideoCodecs());
        caps.insert("supported_audio_codecs", sessionManager.playbackSupportedAudioCodecs());
        apiClient.setClientCapabilities(caps);
    };
    syncClientCapabilities();

    QObject::connect(&sessionManager, &SessionManager::baseUrlChanged, &apiClient, [&]() {
        apiClient.setBaseUrl(sessionManager.baseUrl());
    });
    QObject::connect(&sessionManager, &SessionManager::authTokenChanged, &apiClient, [&]() {
        apiClient.setAuthToken(sessionManager.authToken());
    });
    QObject::connect(&sessionManager, &SessionManager::accessTokenExpiresAtChanged, &apiClient, [&]() {
        apiClient.setAccessTokenExpiresAt(sessionManager.accessTokenExpiresAt());
    });
    QObject::connect(&sessionManager, &SessionManager::networkTypeChanged, &apiClient, [&]() {
        apiClient.setNetworkType(sessionManager.networkType());
    });
    QObject::connect(&sessionManager, &SessionManager::registryUrlChanged, &serverDiscovery, [&]() {
        serverDiscovery.setRegistryBaseUrl(sessionManager.registryUrl());
    });
    QObject::connect(&sessionManager, &SessionManager::registryUrlChanged, &controlPlaneClient, [&]() {
        controlPlaneClient.setBaseUrl(sessionManager.registryUrl());
    });
    QObject::connect(&sessionManager, &SessionManager::controlPlaneTokenChanged, &controlPlaneClient, [&]() {
        controlPlaneClient.setAuthToken(sessionManager.controlPlaneToken());
    });
    QObject::connect(&sessionManager, &SessionManager::controlPlaneExpiresAtChanged, &controlPlaneClient, [&]() {
        controlPlaneClient.setAccessTokenExpiresAt(sessionManager.controlPlaneExpiresAt());
    });
    QObject::connect(&sessionManager, &SessionManager::controlPlaneTokenChanged, &serverDiscovery, [&]() {
        serverDiscovery.setAuthToken(sessionManager.controlPlaneToken());
    });
    QObject::connect(&sessionManager, &SessionManager::networkTypeChanged, &serverDiscovery, [&]() {
        serverDiscovery.setPreferredNetworkType(sessionManager.networkType());
    });
    QObject::connect(&sessionManager, &SessionManager::playbackMaxResolutionChanged, &apiClient, syncClientCapabilities);
    QObject::connect(&sessionManager, &SessionManager::playbackMaxBitrateBpsChanged, &apiClient, syncClientCapabilities);
    QObject::connect(&sessionManager, &SessionManager::playbackSupportedContainersChanged, &apiClient, syncClientCapabilities);
    QObject::connect(&sessionManager, &SessionManager::playbackSupportedVideoCodecsChanged, &apiClient, syncClientCapabilities);
    QObject::connect(&sessionManager, &SessionManager::playbackSupportedAudioCodecsChanged, &apiClient, syncClientCapabilities);

    QObject::connect(&apiClient, &ApiClient::authTokenChanged, &sessionManager, [&]() {
        sessionManager.setAuthToken(apiClient.authToken());
    });
    QObject::connect(&apiClient, &ApiClient::accessTokenExpiresAtChanged, &sessionManager, [&]() {
        sessionManager.setAccessTokenExpiresAt(apiClient.accessTokenExpiresAt());
    });
    QObject::connect(&controlPlaneClient, &ControlPlaneClient::authTokenChanged, &sessionManager, [&]() {
        sessionManager.setControlPlaneToken(controlPlaneClient.authToken());
    });
    QObject::connect(&controlPlaneClient, &ControlPlaneClient::accessTokenExpiresAtChanged, &sessionManager, [&]() {
        sessionManager.setControlPlaneExpiresAt(controlPlaneClient.accessTokenExpiresAt());
    });

    QObject::connect(&apiClient, &ApiClient::libraryReceived, &libraryModel, &LibraryModel::setItems);

    playerController.setApiClient(&apiClient);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("apiClient", &apiClient);
    engine.rootContext()->setContextProperty("controlPlaneClient", &controlPlaneClient);
    engine.rootContext()->setContextProperty("libraryModel", &libraryModel);
    engine.rootContext()->setContextProperty("playerController", &playerController);
    engine.rootContext()->setContextProperty("serverDiscovery", &serverDiscovery);
    engine.rootContext()->setContextProperty("sessionManager", &sessionManager);

    const QUrl url(QStringLiteral("qrc:/qml/main.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
