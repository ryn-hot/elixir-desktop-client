#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtQml>
#include <QQuickStyle>

#include "backend/ApiClient.h"
#include "backend/LibraryModel.h"
#include "backend/MpvItem.h"
#include "backend/PlayerController.h"
#include "backend/SessionManager.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName("ElixirMedia");
    QCoreApplication::setApplicationName("Elixir");

    QQuickStyle::setStyle("Fusion");

    SessionManager sessionManager;
    ApiClient apiClient;
    LibraryModel libraryModel;
    PlayerController playerController;

    qmlRegisterType<MpvItem>("Elixir.Mpv", 1, 0, "MpvItem");

    apiClient.setBaseUrl(sessionManager.baseUrl());
    apiClient.setAuthToken(sessionManager.authToken());
    apiClient.setNetworkType(sessionManager.networkType());

    QObject::connect(&sessionManager, &SessionManager::baseUrlChanged, &apiClient, [&]() {
        apiClient.setBaseUrl(sessionManager.baseUrl());
    });
    QObject::connect(&sessionManager, &SessionManager::authTokenChanged, &apiClient, [&]() {
        apiClient.setAuthToken(sessionManager.authToken());
    });
    QObject::connect(&sessionManager, &SessionManager::networkTypeChanged, &apiClient, [&]() {
        apiClient.setNetworkType(sessionManager.networkType());
    });

    QObject::connect(&apiClient, &ApiClient::authTokenChanged, &sessionManager, [&]() {
        sessionManager.setAuthToken(apiClient.authToken());
    });

    QObject::connect(&apiClient, &ApiClient::libraryReceived, &libraryModel, &LibraryModel::setItems);

    playerController.setApiClient(&apiClient);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("apiClient", &apiClient);
    engine.rootContext()->setContextProperty("libraryModel", &libraryModel);
    engine.rootContext()->setContextProperty("playerController", &playerController);
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
