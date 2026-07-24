#include "backend/ApiClient.h"
#include "backend/CredentialStore.h"
#include "backend/SessionManager.h"

#include <QDateTime>
#include <QCoreApplication>
#include <QFile>
#include <QHash>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QPointer>
#include <QSettings>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>
#include <algorithm>
#include <functional>

namespace {
const QString kSessionId = QStringLiteral("10000000-0000-4000-8000-000000000001");
const QString kHomeId = QStringLiteral("20000000-0000-4000-8000-000000000002");
const QString kProfileId = QStringLiteral("30000000-0000-4000-8000-000000000003");
const QString kSecondProfileId = QStringLiteral("40000000-0000-4000-8000-000000000004");

class MemoryCredentialStore final : public CredentialStore {
public:
    CredentialReadResult read(const QString &service, const QString &account) override {
        const QString key = service + '|' + account;
        if (!values.contains(key)) {
            return {CredentialStoreStatus::NotFound, QString(), QString()};
        }
        return {CredentialStoreStatus::Success, values.value(key), QString()};
    }

    CredentialStoreStatus write(
        const QString &service,
        const QString &account,
        const QString &value,
        QString *error) override {
        values.insert(service + '|' + account, value);
        if (error) {
            error->clear();
        }
        return CredentialStoreStatus::Success;
    }

    CredentialStoreStatus remove(
        const QString &service,
        const QString &account,
        QString *error) override {
        const bool removed = values.remove(service + '|' + account) > 0;
        if (error) {
            error->clear();
        }
        return removed ? CredentialStoreStatus::Success : CredentialStoreStatus::NotFound;
    }

    bool isSecure() const override {
        return true;
    }

    QHash<QString, QString> values;
};

struct HttpRequest {
    QByteArray method;
    QByteArray path;
    QHash<QByteArray, QByteArray> headers;
    QByteArray body;
};

struct HttpResponse {
    int status = 200;
    QByteArray body = "{}";
    int delayMs = 0;
    QHash<QByteArray, QByteArray> headers;
};

class FakeHttpServer final : public QTcpServer {
public:
    using Handler = std::function<HttpResponse(const HttpRequest &)>;

    explicit FakeHttpServer(QObject *parent = nullptr)
        : QTcpServer(parent) {
        connect(this, &QTcpServer::newConnection, this, [this]() {
            while (hasPendingConnections()) {
                QTcpSocket *socket = nextPendingConnection();
                m_buffers.insert(socket, QByteArray());
                connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
                    m_buffers[socket].append(socket->readAll());
                    parseRequests(socket);
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
                connect(socket, &QObject::destroyed, this, [this, socket]() {
                    m_buffers.remove(socket);
                });
            }
        });
    }

    bool start() {
        return listen(QHostAddress::LocalHost, 0);
    }

    QString baseUrl() const {
        return QStringLiteral("http://127.0.0.1:%1").arg(serverPort());
    }

    void setHandler(Handler handler) {
        m_handler = std::move(handler);
    }

    const QList<HttpRequest> &requests() const {
        return m_requests;
    }

    int countPath(const QByteArray &path) const {
        return std::count_if(m_requests.cbegin(), m_requests.cend(), [&path](const HttpRequest &request) {
            return request.path == path;
        });
    }

private:
    void parseRequests(QTcpSocket *socket) {
        QByteArray &buffer = m_buffers[socket];
        const qsizetype headerEnd = buffer.indexOf("\r\n\r\n");
        if (headerEnd < 0) {
            return;
        }
        const QList<QByteArray> headerLines = buffer.left(headerEnd).split('\n');
        if (headerLines.isEmpty()) {
            socket->disconnectFromHost();
            return;
        }
        const QList<QByteArray> requestLine = headerLines.first().trimmed().split(' ');
        if (requestLine.size() < 2) {
            socket->disconnectFromHost();
            return;
        }
        HttpRequest request;
        request.method = requestLine.at(0);
        request.path = requestLine.at(1);
        int contentLength = 0;
        for (qsizetype index = 1; index < headerLines.size(); ++index) {
            const QByteArray line = headerLines.at(index).trimmed();
            const qsizetype separator = line.indexOf(':');
            if (separator <= 0) {
                continue;
            }
            const QByteArray name = line.left(separator).trimmed().toLower();
            const QByteArray value = line.mid(separator + 1).trimmed();
            request.headers.insert(name, value);
            if (name == "content-length") {
                contentLength = value.toInt();
            }
        }
        const qsizetype totalLength = headerEnd + 4 + contentLength;
        if (buffer.size() < totalLength) {
            return;
        }
        request.body = buffer.mid(headerEnd + 4, contentLength);
        buffer.remove(0, totalLength);
        m_requests.push_back(request);
        const HttpResponse response = m_handler ? m_handler(request) : HttpResponse{};
        QPointer<QTcpSocket> guardedSocket(socket);
        QTimer::singleShot(response.delayMs, this, [guardedSocket, response]() {
            if (!guardedSocket || guardedSocket->state() == QAbstractSocket::UnconnectedState) {
                return;
            }
            const QByteArray reason = response.status >= 200 && response.status < 300
                ? QByteArray("OK")
                : QByteArray("Error");
            QByteArray payload;
            payload += "HTTP/1.1 " + QByteArray::number(response.status) + ' ' + reason + "\r\n";
            payload += "Content-Type: application/json\r\n";
            payload += "Cache-Control: no-store\r\n";
            payload += "Connection: close\r\n";
            for (auto it = response.headers.cbegin(); it != response.headers.cend(); ++it) {
                payload += it.key() + ": " + it.value() + "\r\n";
            }
            payload += "Content-Length: " + QByteArray::number(response.body.size()) + "\r\n\r\n";
            payload += response.body;
            guardedSocket->write(payload);
            guardedSocket->disconnectFromHost();
        });
    }

    Handler m_handler;
    QHash<QTcpSocket *, QByteArray> m_buffers;
    QList<HttpRequest> m_requests;
};

QByteArray jsonBody(const QJsonObject &object) {
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

QString futureTimestamp() {
    return QDateTime::currentDateTimeUtc().addSecs(3600).toString(Qt::ISODateWithMs);
}

QJsonObject tokenResponse(
    const QString &accessToken,
    const QString &refreshToken,
    const QString &profileId = kProfileId,
    const QString &profileName = QStringLiteral("Owner")) {
    return {
        {"access_token", accessToken},
        {"access_expires_at", futureTimestamp()},
        {"refresh_token", refreshToken},
        {"refresh_expires_at", QDateTime::currentDateTimeUtc().addDays(30).toString(Qt::ISODateWithMs)},
        {"token_type", "bearer"},
        {"session_id", kSessionId},
        {"home_id", kHomeId},
        {"profile_id", profileId},
        {"role", "owner"},
        {"profile", QJsonObject{
            {"id", profileId},
            {"display_name", profileName},
            {"profile_type", "account"},
        }},
    };
}

QJsonObject sessionResponse(
    const QString &profileId = kProfileId,
    const QString &profileName = QStringLiteral("Owner"),
    qint64 revision = 1) {
    return {
        {"user_id", "50000000-0000-4000-8000-000000000005"},
        {"session_id", kSessionId},
        {"home_id", kHomeId},
        {"active_profile_id", profileId},
        {"role", "owner"},
        {"capability_revision", revision},
        {"capabilities", QJsonArray{"library_read", "live_browse", "live_play"}},
        {"profile", QJsonObject{
            {"id", profileId},
            {"display_name", profileName},
            {"profile_type", "account"},
        }},
        {"access_expires_at", futureTimestamp()},
        {"session_expires_at", QDateTime::currentDateTimeUtc().addDays(30).toString(Qt::ISODateWithMs)},
        {"remember_device", true},
    };
}

const HttpRequest *findRequest(const QList<HttpRequest> &requests, const QByteArray &path, int ordinal = 0) {
    int seen = 0;
    for (const HttpRequest &request : requests) {
        if (request.path == path && seen++ == ordinal) {
            return &request;
        }
    }
    return nullptr;
}
} // namespace

class AuthTransportTests final : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        QVERIFY(m_settingsDirectory.isValid());
        QCoreApplication::setOrganizationName(QStringLiteral("ElixirA13Tests"));
        QCoreApplication::setApplicationName(QStringLiteral("ElixirAuthTransportTests"));
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory.path());
    }

    void init() {
        QSettings settings;
        settings.clear();
        settings.sync();
    }

    void a13_refresh_token_is_vaulted_and_server_scoped() {
        auto store = std::make_shared<MemoryCredentialStore>();
        SessionManager manager(store);
        const QString serverA = QStringLiteral("http://127.0.0.1:41001");
        const QString serverB = QStringLiteral("http://127.0.0.1:41002");

        manager.setBaseUrl(serverA);
        manager.setRefreshToken(QStringLiteral("refresh-secret-a"));
        manager.setAuthToken(QStringLiteral("access-a"));
        manager.setAccessTokenExpiresAt(futureTimestamp());
        manager.setSessionId(kSessionId);
        manager.setHomeId(kHomeId);
        manager.setActiveProfileId(kProfileId);
        QVERIFY(manager.hasRefreshToken());
        QVERIFY(manager.secureCredentialStorage());

        QSettings settings;
        for (const QString &key : settings.allKeys()) {
            QVERIFY2(
                !settings.value(key).toString().contains(QStringLiteral("refresh-secret-a")),
                qPrintable(key));
        }
        QFile settingsFile(settings.fileName());
        if (settingsFile.open(QIODevice::ReadOnly)) {
            QVERIFY(!settingsFile.readAll().contains("refresh-secret-a"));
        }

        manager.setBaseUrl(serverB);
        QVERIFY(manager.authToken().isEmpty());
        QVERIFY(manager.sessionId().isEmpty());
        QVERIFY(!manager.hasRefreshToken());
        manager.setRefreshToken(QStringLiteral("refresh-secret-b"));
        manager.setBaseUrl(serverA);
        QCOMPARE(manager.refreshToken(), QStringLiteral("refresh-secret-a"));
        QVERIFY(manager.authToken().isEmpty());
        manager.clearAuth();
        QVERIFY(!manager.hasRefreshToken());

        manager.setBaseUrl(serverB);
        QCOMPARE(manager.refreshToken(), QStringLiteral("refresh-secret-b"));
    }

    void a13_expiry_queues_requests_behind_one_rotating_refresh() {
        FakeHttpServer server;
        QVERIFY(server.start());
        server.setHandler([](const HttpRequest &request) {
            if (request.path == "/api/v1/auth/refresh") {
                return HttpResponse{200, jsonBody(tokenResponse("access-2", "refresh-2")), 20};
            }
            if (request.path == "/api/v1/auth/session") {
                return HttpResponse{200, jsonBody(sessionResponse()), 0};
            }
            if (request.path == "/api/v1/library/items") {
                return HttpResponse{200, "[]", 0};
            }
            return HttpResponse{404, R"({"message":"not found"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("access-1"));
        client.setAccessTokenExpiresAt(QDateTime::currentDateTimeUtc().addSecs(-1).toString(Qt::ISODateWithMs));
        client.setRefreshToken(QStringLiteral("refresh-1"));
        QSignalSpy libraries(&client, &ApiClient::libraryReceived);
        QSignalSpy expired(&client, &ApiClient::authExpired);

        client.fetchLibrary();
        client.fetchLibrary();
        client.fetchLibrary();
        QTRY_COMPARE_WITH_TIMEOUT(libraries.count(), 3, 5000);
        QCOMPARE(expired.count(), 0);
        QCOMPARE(server.countPath("/api/v1/auth/refresh"), 1);
        QCOMPARE(server.countPath("/api/v1/auth/session"), 1);
        QCOMPARE(server.countPath("/api/v1/library/items"), 3);
        QCOMPARE(client.authToken(), QStringLiteral("access-2"));
        QCOMPARE(client.refreshToken(), QStringLiteral("refresh-2"));
        for (int index = 0; index < 3; ++index) {
            const HttpRequest *request = findRequest(server.requests(), "/api/v1/library/items", index);
            QVERIFY(request);
            QCOMPARE(request->headers.value("authorization"), QByteArray("Bearer access-2"));
        }
        const HttpRequest *refresh = findRequest(server.requests(), "/api/v1/auth/refresh");
        QVERIFY(refresh);
        QCOMPARE(
            QJsonDocument::fromJson(refresh->body).object().value("refresh_token").toString(),
            QStringLiteral("refresh-1"));
    }

    void a13_unauthorized_request_refreshes_and_replays_once() {
        FakeHttpServer server;
        QVERIFY(server.start());
        int libraryAttempts = 0;
        server.setHandler([&libraryAttempts](const HttpRequest &request) {
            if (request.path == "/api/v1/library/items") {
                ++libraryAttempts;
                return libraryAttempts == 1
                    ? HttpResponse{401, R"({"message":"expired"})", 0}
                    : HttpResponse{200, "[]", 0};
            }
            if (request.path == "/api/v1/auth/refresh") {
                return HttpResponse{200, jsonBody(tokenResponse("access-2", "refresh-2")), 0};
            }
            if (request.path == "/api/v1/auth/session") {
                return HttpResponse{200, jsonBody(sessionResponse()), 0};
            }
            return HttpResponse{404, R"({"message":"not found"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("access-1"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        client.setRefreshToken(QStringLiteral("refresh-1"));
        QSignalSpy libraries(&client, &ApiClient::libraryReceived);
        QSignalSpy expired(&client, &ApiClient::authExpired);
        client.fetchLibrary();
        QTRY_COMPARE_WITH_TIMEOUT(libraries.count(), 1, 5000);
        QCOMPARE(expired.count(), 0);
        QCOMPARE(server.countPath("/api/v1/library/items"), 2);
        QCOMPARE(server.countPath("/api/v1/auth/refresh"), 1);
        QCOMPARE(findRequest(server.requests(), "/api/v1/library/items", 0)->headers.value("authorization"), QByteArray("Bearer access-1"));
        QCOMPARE(findRequest(server.requests(), "/api/v1/library/items", 1)->headers.value("authorization"), QByteArray("Bearer access-2"));
    }

    void a13_refresh_failure_clears_auth_and_fails_the_queue() {
        FakeHttpServer server;
        QVERIFY(server.start());
        server.setHandler([](const HttpRequest &request) {
            if (request.path == "/api/v1/auth/refresh") {
                return HttpResponse{401, R"({"message":"device revoked"})", 0};
            }
            return HttpResponse{500, R"({"message":"unexpected"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("access-1"));
        client.setAccessTokenExpiresAt(QDateTime::currentDateTimeUtc().addSecs(-1).toString(Qt::ISODateWithMs));
        client.setRefreshToken(QStringLiteral("refresh-1"));
        QSignalSpy expired(&client, &ApiClient::authExpired);
        QSignalSpy failures(&client, &ApiClient::requestFailed);
        client.fetchLibrary();
        client.fetchLibrary();
        QTRY_COMPARE_WITH_TIMEOUT(expired.count(), 1, 5000);
        QVERIFY(failures.count() >= 3);
        QCOMPARE(server.countPath("/api/v1/auth/refresh"), 1);
        QCOMPARE(server.countPath("/api/v1/library/items"), 0);
        QVERIFY(client.authToken().isEmpty());
        QVERIFY(client.refreshToken().isEmpty());
    }

    void a13_replayed_unauthorized_request_does_not_refresh_twice() {
        FakeHttpServer server;
        QVERIFY(server.start());
        server.setHandler([](const HttpRequest &request) {
            if (request.path == "/api/v1/library/items") {
                return HttpResponse{401, R"({"message":"revoked"})", 0};
            }
            if (request.path == "/api/v1/auth/refresh") {
                return HttpResponse{200, jsonBody(tokenResponse("access-2", "refresh-2")), 0};
            }
            if (request.path == "/api/v1/auth/session") {
                return HttpResponse{200, jsonBody(sessionResponse()), 0};
            }
            return HttpResponse{404, R"({"message":"not found"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("access-1"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        client.setRefreshToken(QStringLiteral("refresh-1"));
        QSignalSpy expired(&client, &ApiClient::authExpired);
        client.fetchLibrary();
        QTRY_COMPARE_WITH_TIMEOUT(expired.count(), 1, 5000);
        QCOMPARE(server.countPath("/api/v1/library/items"), 2);
        QCOMPARE(server.countPath("/api/v1/auth/refresh"), 1);
        QVERIFY(client.authToken().isEmpty());
        QVERIFY(client.refreshToken().isEmpty());
    }

    void a13_authenticated_redirect_is_not_followed() {
        FakeHttpServer destination;
        FakeHttpServer origin;
        QVERIFY(destination.start());
        QVERIFY(origin.start());
        destination.setHandler([](const HttpRequest &) {
            return HttpResponse{200, "[]", 0};
        });
        const QByteArray location = (destination.baseUrl() + "/capture").toUtf8();
        origin.setHandler([location](const HttpRequest &) {
            return HttpResponse{
                302,
                R"({"message":"redirect"})",
                0,
                {{"Location", location}},
            };
        });

        ApiClient client;
        client.setBaseUrl(origin.baseUrl());
        client.setAuthToken(QStringLiteral("access-1"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        QSignalSpy failures(&client, &ApiClient::requestFailed);
        client.fetchLibrary();
        QTRY_VERIFY_WITH_TIMEOUT(failures.count() >= 1, 5000);
        QCOMPARE(origin.countPath("/api/v1/library/items"), 1);
        QCOMPARE(destination.requests().size(), 0);
    }

    void a13_login_profile_switch_logout_and_server_switch_reset_state() {
        FakeHttpServer server;
        QVERIFY(server.start());
        server.setHandler([](const HttpRequest &request) {
            if (request.path == "/api/v1/auth/login") {
                return HttpResponse{200, jsonBody(tokenResponse("access-1", "refresh-1")), 0};
            }
            if (request.path == "/api/v1/auth/session") {
                return HttpResponse{200, jsonBody(sessionResponse()), 0};
            }
            if (request.path == "/api/v1/profiles") {
                return HttpResponse{200, jsonBody(QJsonObject{{"profiles", QJsonArray{
                    QJsonObject{{"id", kProfileId}, {"display_name", "Owner"}},
                    QJsonObject{{"id", kSecondProfileId}, {"display_name", "Guest"}},
                }}}), 0};
            }
            if (request.path == QByteArray("/api/v1/profiles/") + kSecondProfileId.toUtf8() + "/select") {
                return HttpResponse{200, jsonBody(sessionResponse(kSecondProfileId, "Guest", 2)), 50};
            }
            if (request.path == "/api/v1/auth/logout") {
                return HttpResponse{200, R"("ok")", 0};
            }
            if (request.path == "/api/v1/library/items") {
                return HttpResponse{200, "[]", 500};
            }
            return HttpResponse{404, R"({"message":"not found"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("stale-access"));
        QSignalSpy loggedIn(&client, &ApiClient::loginSucceeded);
        QSignalSpy profiles(&client, &ApiClient::profilesReceived);
        QSignalSpy selected(&client, &ApiClient::profileSelected);
        QSignalSpy loggedOut(&client, &ApiClient::logoutCompleted);
        client.login(QStringLiteral("owner@example.test"), QStringLiteral("password"));
        QTRY_COMPARE_WITH_TIMEOUT(loggedIn.count(), 1, 5000);
        QCOMPARE(client.activeProfileId(), kProfileId);
        QCOMPARE(client.capabilityRevision(), 1);
        const HttpRequest *login = findRequest(server.requests(), "/api/v1/auth/login");
        QVERIFY(login);
        QVERIFY(!login->headers.contains("authorization"));

        client.fetchProfiles();
        QTRY_COMPARE_WITH_TIMEOUT(profiles.count(), 1, 5000);
        QCOMPARE(client.profiles().size(), 2);
        client.selectProfile(kSecondProfileId, QString());
        QSignalSpy transitionFailures(&client, &ApiClient::requestFailed);
        client.fetchLibrary();
        QTRY_VERIFY_WITH_TIMEOUT(transitionFailures.count() >= 1, 1000);
        QCOMPARE(server.countPath("/api/v1/library/items"), 0);
        QTRY_COMPARE_WITH_TIMEOUT(selected.count(), 1, 5000);
        QCOMPARE(client.activeProfileId(), kSecondProfileId);
        QCOMPARE(client.activeProfileName(), QStringLiteral("Guest"));

        client.logout();
        QTRY_COMPARE_WITH_TIMEOUT(loggedOut.count(), 1, 5000);
        QVERIFY(client.authToken().isEmpty());
        QVERIFY(client.refreshToken().isEmpty());

        client.setAuthToken(QStringLiteral("server-a-access"));
        client.setRefreshToken(QStringLiteral("server-a-refresh"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        QSignalSpy libraries(&client, &ApiClient::libraryReceived);
        client.fetchLibrary();
        client.setBaseUrl(QStringLiteral("http://127.0.0.1:9"));
        QTest::qWait(650);
        QCOMPARE(libraries.count(), 0);
        QVERIFY(client.authToken().isEmpty());
        QVERIFY(client.refreshToken().isEmpty());
    }

    void n12_live_egress_status_and_cas_mutation_are_strict() {
        FakeHttpServer server;
        QVERIFY(server.start());
        const QJsonObject status{
            {"enabled", true},
            {"ready", true},
            {"activeBindings", 2},
            {"availableCapacity", 6},
            {"defaultPolicy", QJsonObject{
                {"mode", "off"},
                {"policyId", QJsonValue::Null},
                {"allowFallback", false},
            }},
            {"profiles", QJsonArray{
                QJsonObject{
                    {"id", "warp-default"},
                    {"name", "WARP"},
                    {"kind", "warp"},
                    {"selectableByProfiles", true},
                },
            }},
            {"assignments", QJsonArray{
                QJsonObject{
                    {"id", "70000000-0000-4000-8000-000000000007"},
                    {"scopeType", "profile"},
                    {"scopeKey", kProfileId},
                    {"mode", "prefer_protected"},
                    {"policyId", "warp-default"},
                    {"allowFallback", true},
                    {"revision", 7},
                },
            }},
        };
        server.setHandler([status](const HttpRequest &request) {
            if (request.path != "/api/v1/live/admin/egress") {
                return HttpResponse{404, R"({"message":"not found"})", 0};
            }
            if (request.method == "GET") {
                return HttpResponse{
                    200,
                    jsonBody(QJsonObject{{"data", status}}),
                    0,
                };
            }
            if (request.method == "PUT") {
                return HttpResponse{200, R"({"data":{"revision":8}})", 0};
            }
            return HttpResponse{405, R"({"message":"method not allowed"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("live-admin-access"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        QSignalSpy changed(&client, &ApiClient::liveEgressChanged);
        QSignalSpy failures(&client, &ApiClient::requestFailed);

        client.fetchLiveEgressStatus();
        QTRY_COMPARE_WITH_TIMEOUT(changed.count(), 1, 5000);
        QCOMPARE(client.liveEgressStatus().value("ready").toBool(), true);
        QCOMPARE(client.liveEgressStatus().value("availableCapacity").toInt(), 6);
        QCOMPARE(server.countPath("/api/v1/live/admin/egress"), 1);

        client.updateLiveEgressPolicy(
            QStringLiteral("profile"),
            kProfileId,
            QStringLiteral("prefer_protected"),
            QStringLiteral("warp-default"),
            true,
            7);
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath("/api/v1/live/admin/egress"), 3, 5000);
        QCOMPARE(failures.count(), 0);
        const HttpRequest *mutation = findRequest(
            server.requests(), "/api/v1/live/admin/egress", 1);
        QVERIFY(mutation);
        QCOMPARE(mutation->method, QByteArray("PUT"));
        QCOMPARE(
            mutation->headers.value("authorization"),
            QByteArray("Bearer live-admin-access"));
        QCOMPARE(
            QJsonDocument::fromJson(mutation->body).object(),
            QJsonObject({
                {"scopeType", "profile"},
                {"scopeId", kProfileId},
                {"mode", "prefer_protected"},
                {"policyId", "warp-default"},
                {"allowFallback", true},
                {"expectedRevision", 7},
            }));

        client.updateLiveEgressPolicy(
            QStringLiteral("server_default"),
            QString(),
            QStringLiteral("require_protected"),
            QStringLiteral("warp-default"),
            true,
            0);
        QCOMPARE(failures.count(), 1);
        QCOMPARE(server.countPath("/api/v1/live/admin/egress"), 3);
    }

    void acquisition_polling_coalesces_overlapping_requests() {
        FakeHttpServer server;
        QVERIFY(server.start());
        const QByteArray acquisitionPath = "/api/v1/find/acquisition?limit=12";
        const QByteArray releasesPath =
            "/api/v1/acquisition/releases?state=review_required&limit=50";
        server.setHandler([acquisitionPath, releasesPath](const HttpRequest &request) {
            if (request.path == acquisitionPath && request.method == "GET") {
                return HttpResponse{
                    200,
                    jsonBody(QJsonObject{
                        {"items", QJsonArray{}},
                        {"activeCount", 0},
                        {"downloadingCount", 0},
                        {"needsAttentionCount", 0},
                    }),
                    150,
                };
            }
            if (request.path == releasesPath && request.method == "GET") {
                return HttpResponse{
                    200,
                    jsonBody(QJsonObject{{"releases", QJsonArray{}}}),
                    150,
                };
            }
            return HttpResponse{404, R"({"message":"not found"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("owner-access"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        QSignalSpy failures(&client, &ApiClient::requestFailed);

        for (int index = 0; index < 10; ++index) {
            client.fetchMediaAcquisition();
            client.fetchAcquisitionReleases(QStringLiteral("review_required"), QString(), 50);
        }

        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(acquisitionPath), 1, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(releasesPath), 1, 5000);
        QTest::qWait(75);
        QCOMPARE(server.countPath(acquisitionPath), 1);
        QCOMPARE(server.countPath(releasesPath), 1);

        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(acquisitionPath), 2, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(releasesPath), 2, 5000);
        QTest::qWait(225);
        QCOMPARE(server.countPath(acquisitionPath), 2);
        QCOMPARE(server.countPath(releasesPath), 2);
        QCOMPARE(failures.count(), 0);

        client.fetchMediaAcquisition();
        client.fetchAcquisitionReleases(QStringLiteral("review_required"), QString(), 50);
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(acquisitionPath), 3, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(releasesPath), 3, 5000);
        QTest::qWait(175);
        QCOMPARE(failures.count(), 0);
    }

    void extension_uninstall_is_single_flight() {
        FakeHttpServer server;
        QVERIFY(server.start());
        const QString extensionId = QStringLiteral("elixir.live.sports_streams");
        const QByteArray catalogPath = "/api/v1/extensions/catalog";
        const QByteArray uninstallPath =
            "/api/v1/extensions/elixir.live.sports_streams/uninstall";
        int catalogRequestCount = 0;
        server.setHandler([
            &catalogRequestCount, catalogPath, uninstallPath, extensionId
        ](const HttpRequest &request) {
            if (request.path == catalogPath && request.method == "GET") {
                ++catalogRequestCount;
                const bool staleInstalledResponse = catalogRequestCount <= 2;
                const QJsonArray installed = staleInstalledResponse
                    ? QJsonArray{QJsonObject{
                        {"extension_id", extensionId},
                        {"name", "Sports Streams"},
                        {"version", "0.2.3"},
                        {"enabled", true},
                    }}
                    : QJsonArray{};
                return HttpResponse{
                    200,
                    jsonBody(QJsonObject{
                        {"installed", installed},
                        {"available", QJsonArray{}},
                        {"core_extensions", QJsonArray{}},
                    }),
                    catalogRequestCount == 2 ? 250 : 0,
                };
            }
            if (request.path == uninstallPath && request.method == "POST") {
                return HttpResponse{200, R"({"deleted":true})", 50};
            }
            if (request.path == "/api/v1/extensions/instances"
                && request.method == "GET") {
                return HttpResponse{200, "[]", 0};
            }
            if (request.path == "/api/v1/extensions/status-summary"
                && request.method == "GET") {
                return HttpResponse{200, "{}", 0};
            }
            return HttpResponse{404, R"({"message":"not found"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("owner-access"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        QSignalSpy uninstalled(&client, &ApiClient::extensionUninstalled);
        QSignalSpy failures(&client, &ApiClient::requestFailed);

        client.fetchExtensionsCatalog();
        QTRY_COMPARE_WITH_TIMEOUT(client.extensionsInstalled().size(), 1, 5000);

        client.fetchExtensionsCatalog();
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(catalogPath), 2, 5000);
        client.uninstallExtension(extensionId);
        client.uninstallExtension(extensionId);

        QCOMPARE(client.extensionUninstallingIds(), QStringList{extensionId});
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(uninstallPath), 1, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(uninstalled.count(), 1, 5000);
        QCOMPARE(client.extensionUninstallingIds(), QStringList{});
        QCOMPARE(client.extensionsInstalled().size(), 0);
        QCOMPARE(uninstalled.first().at(0).toString(), extensionId);
        QCOMPARE(uninstalled.first().at(1).toString(), QStringLiteral("Sports Streams"));
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(catalogPath), 3, 5000);

        QTest::qWait(300);
        QCOMPARE(client.extensionsInstalled().size(), 0);
        QCOMPARE(server.countPath(uninstallPath), 1);
        QCOMPARE(failures.count(), 0);
    }

    void lpi2_extension_account_setup_uses_exact_instance_paths() {
        FakeHttpServer server;
        QVERIFY(server.start());
        const QString extensionId = QStringLiteral("example.live");
        const QString instanceId =
            QStringLiteral("80000000-0000-4000-8000-000000000008");
        const QString setupId =
            QStringLiteral("90000000-0000-4000-8000-000000000009");
        const QByteArray controlPath = QByteArray(
            "/api/v1/extensions/example.live/control-surface?instanceId=")
            + instanceId.toUtf8();
        const QByteArray actionPath = QByteArray(
            "/api/v1/extensions/example.live/control-surface/actions/disconnect_live_account?instanceId=")
            + instanceId.toUtf8();
        const QByteArray setupPath = QByteArray(
            "/api/v1/extensions/example.live/instances/")
            + instanceId.toUtf8() + "/account-setup";
        const QByteArray statusPath = setupPath + "/" + setupId.toUtf8();
        const QJsonObject surface{
            {"extensionId", extensionId},
            {"instanceId", instanceId},
            {"sections", QJsonArray{}},
            {"actions", QJsonArray{}},
        };
        server.setHandler([
            controlPath, actionPath, setupPath, statusPath, surface,
            extensionId, instanceId, setupId
        ](const HttpRequest &request) {
            if (request.path == controlPath && request.method == "GET") {
                return HttpResponse{200, jsonBody(surface), 0};
            }
            if (request.path == controlPath && request.method == "PUT") {
                return HttpResponse{200, jsonBody(surface), 0};
            }
            if (request.path == actionPath && request.method == "POST") {
                return HttpResponse{
                    200,
                    jsonBody(QJsonObject{
                        {"success", true},
                        {"message", "Account disconnected."},
                        {"controlSurface", surface},
                    }),
                    0,
                };
            }
            if (request.path == setupPath && request.method == "POST") {
                return HttpResponse{
                    200,
                    jsonBody(QJsonObject{
                        {"setupId", setupId},
                        {"extensionId", extensionId},
                        {"instanceId", instanceId},
                        {"configureUrl", "https://provider.example/configure"},
                    }),
                    0,
                };
            }
            if (request.path == statusPath && request.method == "GET") {
                return HttpResponse{
                    200,
                    jsonBody(QJsonObject{
                        {"setupId", setupId},
                        {"extensionId", extensionId},
                        {"instanceId", instanceId},
                        {"status", "completed"},
                        {"completed", true},
                    }),
                    0,
                };
            }
            return HttpResponse{404, R"({"message":"not found"})", 0};
        });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("owner-access"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        QSignalSpy surfaceChanged(&client, &ApiClient::extensionControlSurfaceChanged);
        QSignalSpy settingsUpdated(
            &client, &ApiClient::extensionControlSettingsUpdated);
        QSignalSpy actionCompleted(&client, &ApiClient::extensionControlActionCompleted);
        QSignalSpy setupStarted(&client, &ApiClient::extensionAccountSetupStarted);
        QSignalSpy setupStatus(&client, &ApiClient::extensionAccountSetupStatusReceived);
        QSignalSpy setupCompleted(&client, &ApiClient::extensionAccountSetupCompleted);
        QSignalSpy failures(&client, &ApiClient::requestFailed);

        client.fetchExtensionControlSurfaceForInstance(extensionId, instanceId);
        QTRY_COMPARE_WITH_TIMEOUT(surfaceChanged.count(), 1, 5000);
        client.updateExtensionControlSurfaceSettingsForInstance(
            extensionId,
            instanceId,
            QVariantMap{
                {"plutoPassword", "plain-password"},
                {"plutoUsername", "viewer@example.com"},
            });
        QTRY_COMPARE_WITH_TIMEOUT(settingsUpdated.count(), 1, 5000);
        QCOMPARE(settingsUpdated.first().at(0).toString(), extensionId);
        QCOMPARE(settingsUpdated.first().at(1).toString(), instanceId);
        QCOMPARE(
            settingsUpdated.first().at(2).toStringList(),
            QStringList({"plutoPassword", "plutoUsername"}));
        client.invokeExtensionControlActionForInstance(
            extensionId,
            instanceId,
            QStringLiteral("disconnect_live_account"));
        QTRY_COMPARE_WITH_TIMEOUT(actionCompleted.count(), 1, 5000);
        client.startExtensionAccountSetup(extensionId, instanceId);
        QTRY_COMPARE_WITH_TIMEOUT(setupStarted.count(), 1, 5000);
        QCOMPARE(setupStarted.first().at(2).toString(), setupId);
        client.checkExtensionAccountSetup(extensionId, instanceId, setupId);
        QTRY_COMPARE_WITH_TIMEOUT(setupStatus.count(), 1, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(setupCompleted.count(), 1, 5000);
        QCOMPARE(setupStatus.first().at(3).toBool(), true);
        QCOMPARE(failures.count(), 0);

        QCOMPARE(server.countPath(controlPath), 2);
        QCOMPARE(server.countPath(actionPath), 1);
        QCOMPARE(server.countPath(setupPath), 1);
        QCOMPARE(server.countPath(statusPath), 1);
        for (const HttpRequest &request : server.requests()) {
            QCOMPARE(request.headers.value("authorization"),
                     QByteArray("Bearer owner-access"));
        }
        const HttpRequest *action = findRequest(server.requests(), actionPath);
        QVERIFY(action);
        QCOMPARE(QJsonDocument::fromJson(action->body).object(), QJsonObject{});
        const HttpRequest *settingsUpdate =
            findRequest(server.requests(), controlPath, 1);
        QVERIFY(settingsUpdate);
        const QJsonObject expectedSettingsUpdate{
            {
                "values",
                QJsonObject{
                    {"plutoPassword", "plain-password"},
                    {"plutoUsername", "viewer@example.com"},
                },
            },
        };
        QCOMPARE(
            QJsonDocument::fromJson(settingsUpdate->body).object(),
            expectedSettingsUpdate);
    }

    void lpi2_extension_control_ignores_stale_surface_after_account_save() {
        FakeHttpServer server;
        QVERIFY(server.start());
        const QString extensionId = QStringLiteral("example.live");
        const QString instanceId =
            QStringLiteral("80000000-0000-4000-8000-000000000008");
        const QByteArray controlPath = QByteArray(
            "/api/v1/extensions/example.live/control-surface?instanceId=")
            + instanceId.toUtf8();
        const QJsonObject staleSurface{
            {"extensionId", extensionId},
            {"instanceId", instanceId},
            {"status", QJsonObject{{"health", "needs_setup"}}},
            {"sections", QJsonArray{}},
        };
        const QJsonObject connectedSurface{
            {"extensionId", extensionId},
            {"instanceId", instanceId},
            {"status", QJsonObject{{"health", "healthy"}}},
            {"sections", QJsonArray{}},
        };
        server.setHandler(
            [controlPath, staleSurface, connectedSurface](const HttpRequest &request) {
                if (request.path != controlPath) {
                    return HttpResponse{404, R"({"message":"not found"})", 0};
                }
                if (request.method == "GET") {
                    return HttpResponse{200, jsonBody(staleSurface), 250};
                }
                if (request.method == "PUT") {
                    return HttpResponse{200, jsonBody(connectedSurface), 0};
                }
                return HttpResponse{405, R"({"message":"method not allowed"})", 0};
            });

        ApiClient client;
        client.setBaseUrl(server.baseUrl());
        client.setAuthToken(QStringLiteral("owner-access"));
        client.setAccessTokenExpiresAt(futureTimestamp());
        QSignalSpy settingsUpdated(
            &client, &ApiClient::extensionControlSettingsUpdated);
        QSignalSpy failures(&client, &ApiClient::requestFailed);

        client.fetchExtensionControlSurfaceForInstance(extensionId, instanceId);
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(controlPath), 1, 5000);
        client.updateExtensionControlSurfaceSettingsForInstance(
            extensionId,
            instanceId,
            QVariantMap{
                {"plutoPassword", "plain-password"},
                {"plutoUsername", "viewer@example.com"},
            });

        QTRY_COMPARE_WITH_TIMEOUT(settingsUpdated.count(), 1, 5000);
        QCOMPARE(
            client.extensionControlSurface()
                .value("status").toMap()
                .value("health").toString(),
            QStringLiteral("healthy"));
        QTest::qWait(350);
        QCOMPARE(
            client.extensionControlSurface()
                .value("status").toMap()
                .value("health").toString(),
            QStringLiteral("healthy"));
        QCOMPARE(client.extensionControlLoading(), false);
        QCOMPARE(server.countPath(controlPath), 2);
        QCOMPARE(failures.count(), 0);
    }

private:
    QTemporaryDir m_settingsDirectory;
};

QTEST_GUILESS_MAIN(AuthTransportTests)

#include "AuthTransportTests.moc"
