#include "backend/ApiClient.h"
#include "backend/CredentialStore.h"
#include "backend/SessionManager.h"

#include <QDateTime>
#include <QCoreApplication>
#include <QCryptographicHash>
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
#include <QUuid>
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

QJsonObject marketplacePreferences(const QString &mode = QStringLiteral("auto")) {
    return {{"schema_version",1},{"contribution",mode},{"metering","unknown"},
        {"contribution_disclosure_version",QJsonValue::Null},
        {"paid_support_consent",false},{"issuer_disclosure_version",QJsonValue::Null}};
}
QJsonObject marketplaceResponse(int revision = 0, const QJsonObject &preferences = marketplacePreferences()) {
    return {{"settings",QJsonObject{{"revision",revision},{"preferences",preferences}}},
        {"contribution_disclosure_version",1},{"contribution_disclosure","Bounded optional contribution."},
        {"issuer_disclosure_version",1},{"issuer_disclosure","Elixir sees the requesting account and extension."},
        {"runtime_status","not_connected"}};
}
const QString kMarketplaceQueryId = QStringLiteral("60000000-0000-4000-8000-000000000006");
QJsonObject marketplaceCard(int index = 0) {
    return {{"extension_id", "elx:" + QString(52, 'a') + "/extension-" + QString::number(index)},
        {"release_id", "sha256:" + QString(64, 'a')}, {"name", "Example " + QString::number(index)},
        {"publisher", "Example publisher"}, {"version", "1.0.0"}, {"description", "Public source extension"},
        {"media_tags", QJsonArray{"movies"}}, {"metadata_only", true}, {"ranking_partial", true},
        {"support", QJsonObject{{"verified_supporters",5},{"weighted_score",5},
            {"discovery_qualified",true},{"capped",false},{"is_global_total",false},
            {"valid_until", static_cast<double>(QDateTime::currentSecsSinceEpoch() + 3600)}}}};
}
QJsonObject marketplaceSearchResponse(const QJsonArray &cards = QJsonArray{marketplaceCard()}, int ttl = 120) {
    return {{"schema_version",1},{"query_id",kMarketplaceQueryId},{"phase","ready"},
        {"query",QJsonObject{{"text","example"},{"tags",QJsonArray{"movies"}},{"limit",20}}},
        {"results",cards},{"checked",cards.size()},{"omitted",0},{"pending",0},
        {"next_cursor",QJsonValue::Null},{"network_complete",false},
        {"ranking_partial",true},{"metadata_only",true},{"valid_for_seconds",ttl}};
}
HttpResponse marketplaceQueryAccepted() {
    return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"query_id",kMarketplaceQueryId}}).toJson(),0};
}
QJsonObject marketplaceTargetResponse() {
    return {{"schema_version",1},{"extension_id",marketplaceCard().value("extension_id")},
        {"new_instance",QJsonObject{{"expected_revision",0},{"controls",QJsonObject{{"kind","absent"}}}}},
        {"instances",QJsonArray{}},{"next_cursor",QJsonValue::Null},{"installation_ready",false},{"review_available",false}};
}
const QString kMarketplaceOperationId = QStringLiteral("70000000-0000-4000-8000-000000000007");
QJsonObject marketplaceOriginalRequest() {
    return {{"schema_version",1},{"query_id",kMarketplaceQueryId},
        {"extension_id",marketplaceCard().value("extension_id")},{"release_id",marketplaceCard().value("release_id")},
        {"target",QJsonObject{{"kind","new"},{"name","Original target"}}},
        {"expected_revision",0},{"mutation_id","90000000-0000-4000-8000-000000000009"},
        {"controls",QJsonObject{{"kind","absent"}}}};
}
QJsonObject marketplaceOperationResponse() {
    return {{"schema_version",1},{"operation_id",kMarketplaceOperationId},
        {"release_id",marketplaceCard().value("release_id")},{"phase","queued"},
        {"review_id",QJsonValue::Null},{"approval_revision",QJsonValue::Null},
        {"preparation",QJsonValue::Null},{"review",QJsonValue::Null},
        {"configured_instance",QJsonValue::Null},{"revision",QJsonValue::Null},
        {"available_actions",QJsonArray{"cancel"}},{"latest_action",QJsonValue::Null},
        {"activation_request_id",QJsonValue::Null},{"cancellation_request_id",QJsonValue::Null},
        {"installation_ready",false},{"initial_request",marketplaceOriginalRequest()}};
}
QJsonObject marketplaceOwnerSession() {
    auto value=sessionResponse();
    value.insert("active_profile_type","account");
    value.insert("active_profile_name","Owner");
    value.insert("capabilities",QJsonArray{"settings_manage","extensions_manage","server_admin","secrets_manage"});
    return value;
}
QJsonObject marketplacePublication() {
    QFile file(QFINDTESTDATA("../../crates/elixir_marketplace/tests/fixtures/protocol-v1.json"));
    if (!file.open(QIODevice::ReadOnly)) return {};
    const auto fixture=QJsonDocument::fromJson(file.readAll()).object();
    return {{"schema_version",1},{"publisher",fixture.value("publisher")},{"release",fixture.value("release")},{"head",fixture.value("head")}};
}
QString marketplaceHash(const QJsonObject &value) {
    return "sha256:"+QString::fromLatin1(QCryptographicHash::hash(QJsonDocument(value).toJson(QJsonDocument::Compact),QCryptographicHash::Sha256).toHex());
}
QJsonObject marketplacePublicationPreview(const QJsonObject &publication,int ttl=120) {
    const auto p=publication.value("release").toObject().value("payload").toObject();
    return {{"schema_version",1},{"reference_id",marketplaceHash(publication)},{"extension_id",p.value("extension_id")},
        {"release_id",marketplaceHash(p)},{"publisher_id",p.value("extension_id").toString().mid(4,52)},
        {"name",p.value("display_name")},{"publisher",p.value("publisher_name")},{"version",p.value("version")},
        {"description",p.value("description")},{"media_tags",p.value("media_tags")},{"runtime_profile",p.value("runtime_profile")},
        {"stable",true},{"signatures_verified",true},{"security_tracked",false},{"metadata_only",true},
        {"discovery_qualified",false},{"source_verified",false},{"install_available",false},{"valid_for_seconds",ttl},
        {"warning","Signatures do not prove safe code. Nothing installed."}};
}
void marketplacePhase(QJsonObject &operation, const QString &phase, const QJsonArray &actions) {
    operation.insert("phase",phase); operation.insert("available_actions",actions);
}
void marketplaceReview(QJsonObject &operation) {
    operation.insert("review_id","sha256:"+QString(64,'b'));
    operation.insert("approval_revision",0);
    operation.insert("review",QJsonObject{{"release_id",operation.value("release_id")},
        {"manifest_sha256","sha256:"+QString(64,'c')},
        {"scope",QJsonObject{{"policy_version",1},
            {"extension_id",operation.value("initial_request").toObject().value("extension_id")},
            {"runtime_profile","source-js-v1"},{"permissions",QJsonArray{}},{"secret_keys",QJsonArray{"api_key"}},
            {"authority_contract","sha256:"+QString(64,'d')},
            {"runtime",QJsonObject{{"memory_bytes",128*1024*1024},{"cpu_millicores",100},{"pids",64},
                {"temporary_mounts",QJsonArray{QJsonObject{{"path","/tmp"},{"bytes",8*1024*1024}}}}}}}}});
}
} // namespace

class AuthTransportTests final : public QObject {
    Q_OBJECT

private slots:
    void marketplace_direct_reference_preserves_exact_publication_and_original_retry_without_search_promotion() {
        FakeHttpServer server; QVERIFY(server.start());
        const auto publication=marketplacePublication(); QVERIFY(!publication.isEmpty());
        const auto preview=marketplacePublicationPreview(publication); QJsonObject original,receivedPreview;
        QList<QJsonObject> starts;bool fail=true;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if (request.path=="/api/v1/marketplace/import") {
                receivedPreview=QJsonDocument::fromJson(request.body).object();return {200,QJsonDocument(preview).toJson(),0};
            }
            if (request.path=="/api/v1/marketplace/install/targets") {
                auto page=marketplaceTargetResponse();page.insert("extension_id",preview.value("extension_id"));page.insert("review_available",true);
                return {200,QJsonDocument(page).toJson(),0};
            }
            if (request.path=="/api/v1/marketplace/installations/direct") {
                original=QJsonDocument::fromJson(request.body).object();starts.append(original);
                if (fail) return {503,"{}",0};
                return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation_id",kMarketplaceOperationId}}).toJson(),0};
            }
            auto initial=marketplaceOriginalRequest();initial.insert("query_id",original.value("request_id"));
            initial.insert("extension_id",preview.value("extension_id"));initial.insert("release_id",preview.value("release_id"));
            initial.insert("target",original.value("target"));initial.insert("mutation_id",original.value("mutation_id"));
            initial.insert("direct_reference",preview.value("reference_id"));
            auto operation=marketplaceOperationResponse();operation.insert("initial_request",initial);operation.insert("release_id",preview.value("release_id"));
            return {200,QJsonDocument(operation).toJson(),0};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");client.setSessionState(marketplaceOwnerSession().toVariantMap());
        client.previewMarketplaceDirectReference(QString::fromUtf8(QJsonDocument(publication).toJson(QJsonDocument::Compact)));
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceDirectReferenceLoading(),5000);
        QCOMPARE(receivedPreview,publication);QCOMPARE(client.marketplaceDirectReference().value("reference_id"),preview.value("reference_id").toVariant());
        QVERIFY(client.marketplaceSearchResults().isEmpty());client.fetchMarketplaceDirectInstallTargets();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(client.marketplaceInstallTargets().value("extension_id"),preview.value("extension_id").toVariant());
        client.startMarketplaceDirectInstallation("Developer","",false);QCOMPARE(starts.size(),0);
        client.startMarketplaceDirectInstallation("Developer","",true);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(starts.size(),1);QVERIFY(client.marketplaceInstallationHasOriginalStart());
        client.clearMarketplaceDirectReference();fail=false;client.retryMarketplaceInstallationStart();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(starts.size(),2);QCOMPARE(starts[0],starts[1]);QCOMPARE(original.value("publication").toObject(),publication);
        QCOMPARE(original.value("accepted_reference"),preview.value("reference_id"));QCOMPARE(original.value("accept_unqualified"),QJsonValue(true));
        QVERIFY(!original.contains("query_id"));QVERIFY(!original.contains("upload_source"));
        QCOMPARE(client.marketplaceInstallation().value("initial_request").toMap().value("direct_reference"),preview.value("reference_id").toVariant());
        client.retryMarketplaceInstallationStart();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(starts.size(),3);QCOMPARE(starts[0],starts[2]);
        QCOMPARE(server.countPath("/api/v1/marketplace/search"),0);QCOMPARE(server.countPath("/api/v1/marketplace/installations"),0);
    }
    void marketplace_direct_preview_rejects_promotion_and_cleared_or_expired_observations() {
        FakeHttpServer server;QVERIFY(server.start());const auto publication=marketplacePublication();QVERIFY(!publication.isEmpty());
        auto preview=marketplacePublicationPreview(publication);int delay=0;
        server.setHandler([&](const HttpRequest &)->HttpResponse{return {200,QJsonDocument(preview).toJson(),delay};});
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");client.setSessionState(marketplaceOwnerSession().toVariantMap());
        const auto bytes=QString::fromUtf8(QJsonDocument(publication).toJson(QJsonDocument::Compact));
        preview.insert("discovery_qualified",true);client.previewMarketplaceDirectReference(bytes);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceDirectReferenceLoading(),5000);QVERIFY(client.marketplaceDirectReference().isEmpty());
        preview=marketplacePublicationPreview(publication);delay=150;client.previewMarketplaceDirectReference(bytes);client.clearMarketplaceDirectReference();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceDirectReferenceLoading(),5000);QVERIFY(client.marketplaceDirectReference().isEmpty());
        delay=0;preview=marketplacePublicationPreview(publication,1);client.previewMarketplaceDirectReference(bytes);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceDirectReferenceLoading(),5000);QVERIFY(!client.marketplaceDirectReference().isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(client.marketplaceDirectReference().isEmpty(),2000);
        const auto before=server.requests().size();client.previewMarketplaceDirectReference(QString(65537,'x'));QCOMPARE(server.requests().size(),before);
    }
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

    void marketplace_search_is_authenticated_bounded_and_stable_until_explicit_refresh() {
        FakeHttpServer server; QVERIFY(server.start());
        int reads=0; QJsonObject body; QByteArray authorization;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            authorization=request.headers.value("authorization");
            if(request.method=="POST") {
                body=QJsonDocument::fromJson(request.body).object();
                return marketplaceQueryAccepted();
            }
            const QJsonArray cards=++reads==1?QJsonArray{marketplaceCard(0)}
                :reads==2?QJsonArray{marketplaceCard(1),marketplaceCard(0)}:QJsonArray{marketplaceCard(1)};
            return {200,QJsonDocument(marketplaceSearchResponse(cards)).toJson(),20};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.startMarketplaceSearch("example",{"movies"});
        client.startMarketplaceSearch("ignored while busy",{});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(authorization,QByteArray("Bearer owner-token"));
        QCOMPARE(body.value("query").toObject().value("limit").toInt(),20);
        QVERIFY(!body.contains("cursor"));
        QCOMPARE(server.countPath("/api/v1/marketplace/search"),1);
        QCOMPARE(client.marketplaceSearchResults().size(),1);
        client.pollMarketplaceSearch(); client.pollMarketplaceSearch();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(reads,2);
        QCOMPARE(client.marketplaceSearchAvailableCount(),2);
        QCOMPARE(client.marketplaceSearchResults().size(),2);
        QCOMPARE(client.marketplaceSearchResults()[0].toMap().value("name").toString(),QString("Example 0"));
        QCOMPARE(client.marketplaceSearchResults()[1].toMap().value("name").toString(),QString("Example 1"));
        client.acceptMarketplaceSearchResults();
        QCOMPARE(client.marketplaceSearchResults().size(),2);
        QCOMPARE(client.marketplaceSearchResults()[0].toMap().value("name").toString(),QString("Example 1"));
        client.pollMarketplaceSearch();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(client.marketplaceSearchResults().size(),1);
        QCOMPARE(client.marketplaceSearchResults()[0].toMap().value("name").toString(),QString("Example 1"));
    }

    void marketplace_search_result_notifications_ignore_progress_but_keep_row_and_clear_changes() {
        FakeHttpServer server; QVERIFY(server.start());
        auto page = marketplaceSearchResponse(QJsonArray{marketplaceCard()});
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            return request.method == "POST" ? marketplaceQueryAccepted()
                : HttpResponse{200, QJsonDocument(page).toJson(), 0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        QSignalSpy rows(&client, &ApiClient::marketplaceSearchResultsChanged);
        QSignalSpy status(&client, &ApiClient::marketplaceSearchChanged);
        client.startMarketplaceSearch("example", {});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(), 5000);
        QCOMPARE(client.marketplaceSearchResults().size(), 1);
        QCOMPARE(rows.count(), 1);
        rows.clear(); status.clear();
        for (int pass = 0; pass < 3; ++pass) {
            page.insert("phase", pass % 2 ? "ready" : "checking");
            page.insert("pending", pass % 2 ? 0 : 1);
            client.pollMarketplaceSearch();
            QVERIFY(client.marketplaceSearchLoading());
            QCOMPARE(rows.count(), 0); // Loading alone never resets cards.
            QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(), 5000);
            QCOMPARE(client.marketplaceSearchResults().size(), 1);
            QCOMPARE(rows.count(), 0); // Same checked rows, changed progress.
        }
        QVERIFY(status.count() >= 6);
        client.acceptMarketplaceSearchResults();
        QCOMPARE(rows.count(), 0); // Unchanged explicit refresh is also cheap.
        auto changed = marketplaceCard();
        changed.insert("description", "Updated checked metadata");
        page = marketplaceSearchResponse(QJsonArray{changed});
        client.pollMarketplaceSearch();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(), 5000);
        QCOMPARE(rows.count(), 1);
        QCOMPARE(client.marketplaceSearchResults()[0].toMap().value("description").toString(),
                 QString("Updated checked metadata"));
        rows.clear();
        page = marketplaceSearchResponse(QJsonArray{});
        client.pollMarketplaceSearch();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(), 5000);
        QVERIFY(client.marketplaceSearchResults().isEmpty());
        QCOMPARE(rows.count(), 1); // Missing/withdrawn rows disappear promptly.
        page = marketplaceSearchResponse(QJsonArray{marketplaceCard()});
        client.pollMarketplaceSearch();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(), 5000);
        rows.clear();
        client.clearMarketplaceSearch();
        QVERIFY(client.marketplaceSearchResults().isEmpty());
        QCOMPARE(rows.count(), 1);
    }

    void marketplace_peer_discovery_progress_is_nonfinal_and_accepts_legacy_responses() {
        FakeHttpServer server; QVERIFY(server.start());
        auto page=marketplaceSearchResponse(QJsonArray{});
        page.insert("phase","checking"); page.insert("searching_peers",true);
        page.insert("local_page_complete",true);
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            return request.method=="POST"?marketplaceQueryAccepted():HttpResponse{200,QJsonDocument(page).toJson(),0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.startMarketplaceSearch("example",{});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("checking"));
        QCOMPARE(client.marketplaceSearch().value("searching_peers").toBool(),true);
        QCOMPARE(client.marketplaceSearch().value("local_page_complete").toBool(),true);
        QCOMPARE(client.marketplaceSearch().value("network_complete").toBool(),false);
        QVERIFY(client.marketplaceSearchResults().isEmpty());
        page.insert("phase","ready"); page.insert("searching_peers",false);
        client.pollMarketplaceSearch();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("ready"));
        QCOMPARE(client.marketplaceSearch().value("searching_peers").toBool(),false);
        // Existing servers need not send this presentation-only field.
        page.remove("searching_peers"); page.remove("local_page_complete"); client.pollMarketplaceSearch();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("ready"));
    }

    void marketplace_catalog_preparation_is_independent_of_fresh_first_page_cards() {
        FakeHttpServer server; QVERIFY(server.start());
        QJsonObject requestBody; int reads=0;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method=="POST") { requestBody=QJsonDocument::fromJson(request.body).object(); return marketplaceQueryAccepted(); }
            const bool complete=++reads>2;
            auto page=marketplaceSearchResponse(QJsonArray{marketplaceCard()});
            page.insert("query",QJsonObject{{"text",""},{"tags",QJsonArray{}},{"limit",20}});
            page.insert("phase","ready");
            page.insert("preparation",QJsonObject{{"schema_version",1},{"phase",complete?"complete":"waiting"},
                {"scope","current_local_catalog"},{"examined",43},{"available",40},{"omitted",3},{"pages",3},
                {"received",60},{"local_pass_complete",complete},{"network_complete",false},{"metadata_only",true}});
            return {200,QJsonDocument(page).toJson(),0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.startMarketplaceSearch("",{},"",true);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(requestBody.value("prepare_catalog"),QJsonValue(true));
        QCOMPARE(client.marketplaceSearchResults().size(),1);
        QCOMPARE(client.marketplaceSearch().value("preparation").toMap().value("phase").toString(),QString("waiting"));
        client.pollMarketplaceSearch(); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(client.marketplaceSearchResults().size(),1);
        QCOMPARE(client.marketplaceSearch().value("preparation").toMap().value("examined").toInt(),43);
        QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("ready"));
        QCOMPARE(client.marketplaceSearch().value("preparation").toMap().value("local_pass_complete").toBool(),false);
        client.pollMarketplaceSearch(); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(client.marketplaceSearchResults().size(),1);
        QCOMPARE(client.marketplaceSearch().value("preparation").toMap().value("local_pass_complete").toBool(),true);
        client.startMarketplaceSearch("mixed",{},"",true);
        QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("unavailable"));
        QCOMPARE(server.countPath("/api/v1/marketplace/search"),1);
    }

    void marketplace_background_preparation_failure_does_not_erase_checked_cards() {
        FakeHttpServer server; QVERIFY(server.start());
        QString phase="limited";
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method=="POST") return marketplaceQueryAccepted();
            auto page=marketplaceSearchResponse(QJsonArray{marketplaceCard()});
            page.insert("preparation",QJsonObject{{"schema_version",1},{"phase",phase},
                {"scope","current_local_catalog"},{"examined",0},{"available",0},{"omitted",0},{"pages",0},
                {"received",0},{"local_pass_complete",false},{"network_complete",false},{"metadata_only",true}});
            return {200,QJsonDocument(page).toJson(),0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        for(const auto &state:QStringList{"limited","unavailable","discovering","checking","waiting"}) {
            phase=state;
            client.startMarketplaceSearch("",{},"",true);
            QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
            QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("ready"));
            QCOMPARE(client.marketplaceSearchResults().size(),1);
            QCOMPARE(client.marketplaceSearch().value("preparation").toMap().value("local_pass_complete").toBool(),false);
        }
    }

    void marketplace_catalog_preparation_rejects_missing_forged_or_oversized_progress() {
        FakeHttpServer server; QVERIFY(server.start());
        auto reply=marketplaceSearchResponse();
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method=="POST") return marketplaceQueryAccepted();
            return {200,QJsonDocument(reply).toJson(),0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        QJsonObject valid{{"schema_version",1},{"phase","complete"},{"scope","current_local_catalog"},
            {"examined",43},{"available",40},{"omitted",3},{"pages",3},{"local_pass_complete",true},
            {"received",60},{"network_complete",false},{"metadata_only",true}};
        QList<QJsonObject> cases{QJsonObject{}};
        for(const auto &change:QList<QPair<QString,QJsonValue>>{{"network_complete",true},{"examined",10001},
            {"pages",513},{"received",10241},{"available",41},{"local_pass_complete",false},{"phase","waiting"},{"scope","entire_network"}}) {
            auto invalid=valid; invalid.insert(change.first,change.second); cases.append(invalid);
        }
        for(const auto &progress:cases) {
            reply=marketplaceSearchResponse();
            if(!progress.isEmpty()) reply.insert("preparation",progress);
            client.startMarketplaceSearch("",{},"",true);
            QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
            QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("unavailable"));
            QVERIFY(client.marketplaceSearchResults().isEmpty());
        }
    }

    void marketplace_search_old_context_and_cleared_queries_cannot_restore_results() {
        FakeHttpServer server; QVERIFY(server.start());
        server.setHandler([](const HttpRequest &request)->HttpResponse {
            if(request.method=="POST") return marketplaceQueryAccepted();
            return {200,QJsonDocument(marketplaceSearchResponse()).toJson(),150};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        const auto path="/api/v1/marketplace/search/"+kMarketplaceQueryId;
        client.startMarketplaceSearch("example",{});
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(path.toUtf8()),1,5000);
        client.setSessionState(QVariantMap{{"session_id",kSessionId},{"home_id",kHomeId},{"active_profile_id",kProfileId}});
        QTest::qWait(200);
        QVERIFY(client.marketplaceSearchResults().isEmpty());
        QVERIFY(client.marketplaceSearch().isEmpty());
        QVERIFY(!client.marketplaceSearchLoading());
        client.startMarketplaceSearch("example",{});
        QTRY_COMPARE_WITH_TIMEOUT(server.countPath(path.toUtf8()),2,5000);
        client.clearMarketplaceSearch();
        QTest::qWait(200);
        QVERIFY(client.marketplaceSearchResults().isEmpty());
        QVERIFY(client.marketplaceSearch().isEmpty());
    }

    void marketplace_search_expiry_hides_cards_without_polling_and_counts_network_latency() {
        FakeHttpServer server;QVERIFY(server.start());
        int delay=0;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method=="POST")return marketplaceQueryAccepted();
            return {200,QJsonDocument(marketplaceSearchResponse(QJsonArray{marketplaceCard()},1)).toJson(),delay};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        QSignalSpy rows(&client, &ApiClient::marketplaceSearchResultsChanged);
        client.startMarketplaceSearch("example",{});
        QTRY_COMPARE_WITH_TIMEOUT(client.marketplaceSearchResults().size(),1,5000);
        const auto populatedSignals = rows.count();
        QTRY_VERIFY_WITH_TIMEOUT(client.marketplaceSearchResults().isEmpty(),2000);
        // The getter expires immediately; the queued Qt timer notification
        // arrives on the next event-loop turn, not necessarily the same one.
        QTRY_VERIFY_WITH_TIMEOUT(rows.count() > populatedSignals, 500);
        QCOMPARE(client.marketplaceSearchAvailableCount(),0);
        QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("stale"));
        QCOMPARE(server.requests().size(),2);
        delay=1100;
        client.startMarketplaceSearch("example",{});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QVERIFY(client.marketplaceSearchResults().isEmpty());
        QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("stale"));
    }

    void marketplace_search_rejects_bad_scores_schema_filters_and_oversized_transport() {
        FakeHttpServer server;QVERIFY(server.start());
        QJsonObject page=marketplaceSearchResponse();
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            return request.method=="POST"?marketplaceQueryAccepted():HttpResponse{200,QJsonDocument(page).toJson(),0};
        });
        QList<QJsonObject> cases;
        const auto badCard=[&](const char *field,const QJsonValue &value) {
            auto card=marketplaceCard();card.insert(field,value);
            cases.append(marketplaceSearchResponse(QJsonArray{card}));
        };
        for(const auto &field:{"weighted_score","verified_supporters"}) {
            auto support=marketplaceCard().value("support").toObject();support.insert(field,999999);
            badCard("support",support);
        }
        auto support=marketplaceCard().value("support").toObject();support.insert("is_global_total",true);badCard("support",support);
        support.insert("is_global_total",false);support.insert("capped",true);badCard("support",support);
        badCard("metadata_only",false);badCard("name",QString());
        badCard("media_tags",QJsonArray{"movies","live"});
        cases.append(marketplaceSearchResponse(QJsonArray{marketplaceCard(),marketplaceCard()}));
        for(const auto &entry:QList<QPair<QString,QJsonValue>>{{"schema_version",1.5},{"query_id",kSessionId},
            {"valid_for_seconds",301},{"next_cursor",QString(129,'x')},{"network_complete",true},
            {"padding",QString(256*1024,'x')},{"searching_peers",1},{"searching_peers",true},
            {"local_page_complete",1},{"local_page_complete",QStringLiteral("true")}}) {
            auto invalid=marketplaceSearchResponse();invalid.insert(entry.first,entry.second);cases.append(invalid);
        }
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        for(const auto &invalid:cases) {
            page=invalid;client.startMarketplaceSearch("example",{});
            QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
            QCOMPARE(client.marketplaceSearch().value("phase").toString(),QString("unavailable"));
            QVERIFY(client.marketplaceSearchResults().isEmpty());
        }
        const auto before=server.requests().size();
        client.startMarketplaceSearch("example",{"live","movies"});
        client.startMarketplaceSearch(QString(257,'x'),{});
        client.startMarketplaceSearch("example",{},"bad/cursor");
        QCOMPARE(server.requests().size(),before);
        auto connector=marketplaceCard();connector.insert("media_tags",QJsonArray{});
        page=marketplaceSearchResponse(QJsonArray{connector});client.startMarketplaceSearch("example",{});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(client.marketplaceSearchResults().size(),1);
    }

    void marketplace_current_card_target_reads_do_not_wait_for_status_poll_but_disappear_on_withdrawal() {
        FakeHttpServer server; QVERIFY(server.start());
        bool refreshing=false;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.path=="/api/v1/marketplace/search") return marketplaceQueryAccepted();
            if(request.path.startsWith("/api/v1/marketplace/search/"))
                return {200,QJsonDocument(marketplaceSearchResponse(refreshing?QJsonArray{}:QJsonArray{marketplaceCard()})).toJson(),refreshing?200:0};
            if(request.path=="/api/v1/marketplace/install/targets")
                return {200,QJsonDocument(marketplaceTargetResponse()).toJson(),0};
            return {400,"{}",0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.startMarketplaceSearch("example",{"movies"});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QCOMPARE(client.marketplaceSearchResults().size(),1);
        refreshing=true;
        client.pollMarketplaceSearch();
        QVERIFY(client.marketplaceSearchLoading());
        client.fetchMarketplaceInstallTargets(marketplaceCard().value("extension_id").toString());
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),1000);
        QVERIFY(client.marketplaceSearchLoading());
        QVERIFY(!client.marketplaceInstallTargets().isEmpty());
        QCOMPARE(server.countPath("/api/v1/marketplace/install/targets"),1);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QVERIFY(client.marketplaceSearchResults().isEmpty());
        QVERIFY(client.marketplaceInstallTargets().isEmpty());
        QCOMPARE(server.countPath("/api/v1/marketplace/installations"),0);
    }

    void marketplace_target_reads_use_checked_cards_and_reject_changed_or_unbounded_control_snapshots() {
        FakeHttpServer server; QVERIFY(server.start());
        auto page = marketplaceTargetResponse();
        bool listed=true;
        QJsonObject requestBody; QByteArray authorization;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if (request.path == "/api/v1/marketplace/search") return marketplaceQueryAccepted();
            if (request.path.startsWith("/api/v1/marketplace/search/"))
                return {200,QJsonDocument(marketplaceSearchResponse(listed?QJsonArray{marketplaceCard()}:QJsonArray{})).toJson(),0};
            requestBody=QJsonDocument::fromJson(request.body).object();
            authorization=request.headers.value("authorization");
            return {200,QJsonDocument(page).toJson(),20};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        const auto extension=marketplaceCard().value("extension_id").toString();
        client.fetchMarketplaceInstallTargets(extension);
        QCOMPARE(server.requests().size(),0);
        client.startMarketplaceSearch("example",{"movies"});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        client.fetchMarketplaceInstallTargets(extension); client.fetchMarketplaceInstallTargets(extension);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(server.countPath("/api/v1/marketplace/install/targets"),1);
        QCOMPARE(authorization,QByteArray("Bearer owner-token"));
        QCOMPARE(requestBody,QJsonObject({{"schema_version",1},{"extension_id",extension}}));
        QCOMPARE(client.marketplaceInstallTargets().value("new_instance").toMap().value("expected_revision").toInt(),0);
        QCOMPARE(client.marketplaceInstallTargets().value("installation_ready").toBool(),false);
        // Existing, pending and paginated choices remain DATA; the client
        // echoes their observed cursor, never inventing a newer revision.
        page.insert("new_instance",QJsonObject{{"expected_revision",0},{"controls",QJsonObject{{"kind","new_instance"},{"extension_revision",7}}}});
        QJsonArray rows;
        for(int n=0;n<20;++n) {
            const auto id=QString("80000000-0000-4000-8000-%1").arg(n+1,12,16,QChar('0'));
            rows.append(QJsonObject{{"instance_id",id},{"name",QString("Target %1").arg(n)},
                {"enabled",false},{"expected_revision",2},{"pending",n==0},
                {"controls",n==0?QJsonValue(QJsonValue::Null):QJsonValue(QJsonObject{{"kind","existing"},{"extension_revision",7},{"instance_revision",9}})}});
        }
        const QJsonObject observedCursor{{"instance_id",rows.last().toObject().value("instance_id")},{"extension_revision",7}};
        page.insert("instances",rows); page.insert("next_cursor",observedCursor);
        client.fetchMarketplaceInstallTargets(extension);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(client.marketplaceInstallTargets().value("instances").toList().size(),20);
        QCOMPARE(client.marketplaceInstallTargets().value("next_cursor").toMap(),observedCursor.toVariantMap());
        page.insert("instances",QJsonArray{rows.last()}); page.insert("next_cursor",QJsonValue::Null);
        client.fetchMarketplaceInstallTargets(extension,observedCursor.toVariantMap());
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(client.marketplaceInstallTargets().value("instances").toList().size(),1);
        QCOMPARE(requestBody.value("after").toObject(),observedCursor);
        for (const auto &fault : {QString("schema"),QString("unknown"),QString("control"),QString("revision"),QString("cursor"),QString("count"),QString("review_type"),QString("legacy_ready")}) {
            page=marketplaceTargetResponse();
            if(fault=="schema") page.insert("schema_version",2);
            if(fault=="unknown") page.insert("native_owner",true);
            if(fault=="control") page.insert("new_instance",QJsonObject{{"expected_revision",0},{"controls",QJsonObject{{"kind","absent"},{"revision",1}}}});
            if(fault=="revision") page.insert("new_instance",QJsonObject{{"expected_revision",1},{"controls",QJsonObject{{"kind","absent"}}}});
            if(fault=="cursor") page.insert("next_cursor",QJsonObject{{"instance_id",kMarketplaceOperationId},{"extension_revision",1}});
            if(fault=="count") { QJsonArray entries; for(int n=0;n<21;++n) entries.append(QJsonObject{}); page.insert("instances",entries); }
            if(fault=="review_type") page.insert("review_available","true");
            if(fault=="legacy_ready") page.insert("installation_ready",true);
            client.fetchMarketplaceInstallTargets(extension);
            QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
            QVERIFY2(client.marketplaceInstallTargets().isEmpty(),qPrintable(fault));
            QVERIFY(!client.marketplaceInstallationNotice().isEmpty());
        }
        page=marketplaceTargetResponse(); client.fetchMarketplaceInstallTargets(extension);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        listed=false; client.pollMarketplaceSearch();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        QVERIFY(client.marketplaceInstallTargets().isEmpty());
        client.clearMarketplaceSearch(); QVERIFY(client.marketplaceInstallTargets().isEmpty());
    }

    void marketplace_current_operation_reads_are_versioned_offline_capable_and_retain_only_the_original_id_after_errors() {
        FakeHttpServer server; QVERIFY(server.start());
        auto operation=marketplaceOperationResponse();
        QJsonValue current=operation; bool fail=false; QByteArray authorization;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            authorization=request.headers.value("authorization");
            if(fail) return {503,"{}",0};
            if(request.path.endsWith("/current")) return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation",current}}).toJson(),20};
            return {200,QJsonDocument(operation).toJson(),20};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.fetchCurrentMarketplaceInstallation(); client.fetchCurrentMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(server.countPath("/api/v1/marketplace/installations/current"),1);
        QCOMPARE(client.marketplaceInstallation().value("operation_id").toString(),kMarketplaceOperationId);
        QCOMPARE(authorization,QByteArray("Bearer owner-token"));
        client.clearMarketplaceSearch(); QVERIFY(!client.marketplaceInstallation().isEmpty());
        fail=true; client.pollMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(client.marketplaceInstallation().isEmpty());
        fail=false; client.pollMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(client.marketplaceInstallation().value("operation_id").toString(),kMarketplaceOperationId);
        QCOMPARE(server.countPath(("/api/v1/marketplace/installations/"+kMarketplaceOperationId).toUtf8()),2);
        operation.insert("available_actions",QJsonArray{"activate","activate"}); client.pollMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(client.marketplaceInstallation().isEmpty());
        current=QJsonValue::Null; client.fetchCurrentMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        const auto before=server.requests().size(); client.pollMarketplaceInstallation();
        QCOMPARE(server.requests().size(),before);
        for(const auto &request:server.requests()) QCOMPARE(request.method,QByteArray("GET"));
    }

    void marketplace_owner_reads_reject_late_context_responses_expired_cards_and_oversized_transport() {
        FakeHttpServer server; QVERIFY(server.start());
        bool huge=false; int delay=150;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(huge) return {200,QByteArray(128*1024+1,'x'),0};
            if(request.path=="/api/v1/marketplace/search") return marketplaceQueryAccepted();
            if(request.path.startsWith("/api/v1/marketplace/search/")) return {200,QJsonDocument(marketplaceSearchResponse(QJsonArray{marketplaceCard()},1)).toJson(),0};
            if(request.path=="/api/v1/marketplace/install/targets") return {200,QJsonDocument(marketplaceTargetResponse()).toJson(),1200};
            return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation",marketplaceOperationResponse()}}).toJson(),delay};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.fetchCurrentMarketplaceInstallation(); client.clearMarketplaceInstallation();
        QTest::qWait(200); QVERIFY(client.marketplaceInstallation().isEmpty());
        delay=0; client.fetchCurrentMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(!client.marketplaceInstallation().isEmpty());
        huge=true; client.pollMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(client.marketplaceInstallation().isEmpty());
        huge=false; client.startMarketplaceSearch("example",{"movies"});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        client.fetchMarketplaceInstallTargets(marketplaceCard().value("extension_id").toString());
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(client.marketplaceInstallTargets().isEmpty());
        client.fetchCurrentMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(!client.marketplaceInstallation().isEmpty());
        client.setBaseUrl("http://127.0.0.1:1");
        QVERIFY(client.marketplaceInstallation().isEmpty());
    }

    void marketplace_reviews_reject_unsupported_access_and_resource_shapes_before_actions() {
        FakeHttpServer server; QVERIFY(server.start());
        auto valid=marketplaceOperationResponse(); marketplaceReview(valid);
        marketplacePhase(valid,"awaiting_approval",QJsonArray{"approve","cancel"});
        auto response=valid;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method!="GET") return {503,"{}",0};
            return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation",response}}).toJson(),0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.setSessionState(marketplaceOwnerSession().toVariantMap());
        client.fetchCurrentMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(!client.marketplaceInstallation().isEmpty());
        QList<QJsonObject> invalid;
        const auto review=valid.value("review").toObject(), scope=review.value("scope").toObject();
        const auto badScope=[&](const QString &field,const QJsonValue &value) {
            auto changed=scope; changed.insert(field,value); auto badReview=review; badReview.insert("scope",changed);
            auto bad=valid; bad.insert("review",badReview); invalid.append(bad);
        };
        badScope("policy_version",2); badScope("unexpected",true);
        badScope("extension_id","elx:"+QString(52,'b')+"/foreign");
        badScope("runtime_profile","source-js-v2"); badScope("runtime_profile","declarative-v1");
        badScope("authority_contract","unverified");
        badScope("permissions",QJsonArray{"unreviewed.permission"});
        badScope("permissions",QJsonArray{"network.egress","network.egress"});
        badScope("permissions",QJsonArray{"runtime.manage_containers","network.egress"});
        badScope("secret_keys","api_key"); badScope("secret_keys",QJsonArray{"bad/key"});
        badScope("secret_keys",QJsonArray{"api_key","api_key"});
        QJsonArray tooMany; for(int i=0;i<65;i++) tooMany.append("key"+QString::number(i));
        badScope("secret_keys",tooMany); badScope("runtime",QJsonValue::Null);
        const auto resource=scope.value("runtime").toObject();
        const auto badResource=[&](const QString &field,const QJsonValue &value) {
            auto changed=resource; changed.insert(field,value); badScope("runtime",changed);
        };
        badResource("memory_bytes",4097.0*1024*1024); badResource("memory_bytes",128*1024*1024+0.5);
        badResource("cpu_millicores",8001); badResource("pids",513); badResource("state_bytes",17*1024*1024);
        badResource("unexpected",true); badResource("temporary_mounts",QJsonArray{});
        badResource("temporary_mounts",QJsonArray{QJsonObject{{"path","/data"},{"bytes",8*1024*1024}}});
        badResource("temporary_mounts",QJsonArray{QJsonObject{{"path","/tmp"},{"bytes",128*1024*1024}}});
        auto extra=review; extra.insert("credentials",QJsonObject{});
        auto bad=valid; bad.insert("review",extra); invalid.append(bad);
        for(const auto &candidate:invalid) {
            response=candidate; client.fetchCurrentMarketplaceInstallation();
            QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
            QVERIFY(client.marketplaceInstallation().isEmpty());
            client.approveMarketplaceInstallation(false); client.submitMarketplaceInstallationSetup({});
        }
        for(const auto &request:server.requests()) QCOMPARE(request.method,QByteArray("GET"));
        response=valid; client.fetchCurrentMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(!client.marketplaceInstallation().isEmpty());
    }

    void marketplace_install_lifecycle_builds_only_observed_inputs_and_does_not_cache_setup_values() {
        // HTTP transport/schema fixture only, NOT native/permission authority.
        FakeHttpServer server; QVERIFY(server.start());
        auto page=marketplaceTargetResponse(); auto operation=marketplaceOperationResponse();
        QJsonObject start,approval,setup,activation; QJsonArray requests;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.path=="/api/v1/marketplace/search") return marketplaceQueryAccepted();
            if(request.path.startsWith("/api/v1/marketplace/search/")) return {200,QJsonDocument(marketplaceSearchResponse()).toJson(),0};
            if(request.path=="/api/v1/marketplace/install/targets") return {200,QJsonDocument(page).toJson(),0};
            if(request.path=="/api/v1/marketplace/installations") {
                start=QJsonDocument::fromJson(request.body).object(); operation.insert("initial_request",start);
                marketplaceReview(operation); marketplacePhase(operation,"awaiting_approval",QJsonArray{"approve","cancel"});
                return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation_id",kMarketplaceOperationId}}).toJson(),20};
            }
            if(request.method=="POST") {
                const auto action=QJsonDocument::fromJson(request.body).object().value("request").toObject();
                requests.append(action); const auto kind=action.value("action").toString();
                if(kind=="approve") { approval=action; marketplacePhase(operation,"awaiting_setup",QJsonArray{"setup","cancel"}); }
                if(kind=="setup") { setup=action; marketplacePhase(operation,"awaiting_commit",QJsonArray{"activate","cancel"}); }
                if(kind=="activate") { activation=action; operation.insert("activation_request_id",action.value("mutation_id")); marketplacePhase(operation,"activated",QJsonArray{}); }
                const QJsonObject receipt{{"request_id",action.value("mutation_id")},{"kind",kind},{"status","acknowledged"}};
                operation.insert("latest_action",receipt);
                return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation_id",kMarketplaceOperationId},{"receipt",receipt}}).toJson(),20};
            }
            if(request.path.endsWith("/current")) return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation",operation}}).toJson(),0};
            return {200,QJsonDocument(operation).toJson(),0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.setSessionState(marketplaceOwnerSession().toVariantMap());
        QCOMPARE(client.homeRole(),QString("owner")); QCOMPARE(client.activeProfileType(),QString("account"));
        const auto card=marketplaceCard(); const auto extension=card.value("extension_id").toString(), release=card.value("release_id").toString();
        client.startMarketplaceSearch("example",{"movies"});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        client.fetchMarketplaceInstallTargets(extension);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        client.startMarketplaceInstallation(extension,release,"A");
        QCOMPARE(server.countPath("/api/v1/marketplace/installations"),0);
        page.remove("review_available"); client.fetchMarketplaceInstallTargets(extension);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(!client.marketplaceInstallTargets().isEmpty());
        client.startMarketplaceInstallation(extension,release,"Legacy read-only server");
        QCOMPARE(server.countPath("/api/v1/marketplace/installations"),0);
        page.insert("review_available",true); client.fetchMarketplaceInstallTargets(extension);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        client.startMarketplaceInstallation(extension,release,QString(129,'x'));
        QCOMPARE(server.countPath("/api/v1/marketplace/installations"),0);
        client.startMarketplaceInstallation(extension,release,"Exact target");
        client.startMarketplaceInstallation(extension,release,"Do not queue another");
        // The server can accept the selected query before its browse receipt
        // expires. Removing the browse state while awaiting the response must
        // not replace or invalidate the original installation request.
        client.clearMarketplaceSearch();
        QVERIFY(client.marketplaceSearch().isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(server.countPath("/api/v1/marketplace/installations"),1);
        QCOMPARE(start.value("query_id").toString(),kMarketplaceQueryId);
        QCOMPARE(start.value("target").toObject().value("name").toString(),QString("Exact target"));
        QCOMPARE(start.value("expected_revision").toInt(),0);
        QCOMPARE(start.value("controls").toObject(),QJsonObject({{"kind","absent"}}));
        QVERIFY(!start.contains("review_available"));
        QVERIFY(!start.contains("installation_ready"));
        QCOMPARE(client.marketplaceInstallation().value("initial_request").toMap(),start.toVariantMap());
        client.approveMarketplaceInstallation(false);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(approval.value("review_id"),operation.value("review_id"));
        QCOMPARE(approval.value("expected_revision").toInt(),0); QVERIFY(approval.value("automatic_updates").isBool());
        QVERIFY(!approval.value("automatic_updates").toBool());
        const auto before=requests.size();
        client.submitMarketplaceInstallationSetup({{"unapproved","never-send"}});
        client.submitMarketplaceInstallationSetup({{"api_key",QString(65537,'x')}});
        QCOMPARE(requests.size(),before);
        client.submitMarketplaceInstallationSetup({{"api_key","setup-private-lifecycle"}});
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        const auto change=setup.value("credentials").toArray().first().toObject();
        QCOMPARE(change.value("key").toString(),QString("api_key"));
        QCOMPARE(change.value("value").toString(),QString("setup-private-lifecycle"));
        QVERIFY(!QJsonDocument(QJsonObject::fromVariantMap(client.marketplaceInstallation())).toJson().contains("setup-private-lifecycle"));
        const auto count=requests.size(); client.retryMarketplaceInstallationAction(); QCOMPARE(requests.size(),count);
        QVERIFY(client.marketplaceInstallationNotice().contains("not cached"));
        client.activateMarketplaceInstallation();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        const auto original=activation; client.retryMarketplaceInstallationAction();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(activation,original);
        QCOMPARE(client.marketplaceInstallation().value("phase").toString(),QString("activated"));
    }

    void marketplace_unknown_start_and_reconnected_cancellation_retry_only_original_mutations() {
        FakeHttpServer server; QVERIFY(server.start());
        auto page=marketplaceTargetResponse(); page.insert("review_available",true);
        auto operation=marketplaceOperationResponse(); QJsonObject original; QJsonArray starts,cancels;
        const QString cancellation="a0000000-0000-4000-8000-00000000000a";
        bool accepted=false;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.path=="/api/v1/marketplace/search") return marketplaceQueryAccepted();
            if(request.path.startsWith("/api/v1/marketplace/search/")) return {200,QJsonDocument(marketplaceSearchResponse()).toJson(),0};
            if(request.path=="/api/v1/marketplace/install/targets") return {200,QJsonDocument(page).toJson(),0};
            if(request.path=="/api/v1/marketplace/installations") {
                const auto body=QJsonDocument::fromJson(request.body).object(); starts.append(body);
                if(!accepted) { original=body; accepted=true; return {503,"{}",0}; }
                operation.insert("initial_request",original); marketplacePhase(operation,"preparing",QJsonArray{"cancel"});
                return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation_id",kMarketplaceOperationId}}).toJson(),0};
            }
            if(request.method=="POST") {
                const auto action=QJsonDocument::fromJson(request.body).object().value("request").toObject(); cancels.append(action);
                marketplacePhase(operation,"cancelled",QJsonArray{});
                const QJsonObject receipt{{"request_id",action.value("mutation_id")},{"kind","cancel"},{"status","acknowledged"}};
                operation.insert("latest_action",receipt);
                return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation_id",kMarketplaceOperationId},{"receipt",receipt}}).toJson(),0};
            }
            if(request.path.endsWith("/current")) return {200,QJsonDocument(QJsonObject{{"schema_version",1},{"operation",operation}}).toJson(),0};
            return {200,QJsonDocument(operation).toJson(),0};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token"); client.setSessionState(marketplaceOwnerSession().toVariantMap());
        const auto extension=marketplaceCard().value("extension_id").toString(), release=marketplaceCard().value("release_id").toString();
        client.startMarketplaceSearch("example",{"movies"}); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSearchLoading(),5000);
        client.fetchMarketplaceInstallTargets(extension); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        client.startMarketplaceInstallation(extension,release,"Original"); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QVERIFY(client.marketplaceInstallationHasOriginalStart());
        client.startMarketplaceInstallation(extension,release,"Replacement is forbidden"); QCOMPARE(starts.size(),1);
        client.retryMarketplaceInstallationStart(); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceInstallationLoading(),5000);
        QCOMPARE(starts.size(),2); QCOMPARE(starts[0],starts[1]);
        operation.insert("cancellation_request_id",cancellation); marketplacePhase(operation,"recovery_required",QJsonArray{"cancel"});
        ApiClient reconnected; reconnected.setBaseUrl(server.baseUrl()); reconnected.setAuthToken("owner-token"); reconnected.setSessionState(marketplaceOwnerSession().toVariantMap());
        reconnected.fetchCurrentMarketplaceInstallation(); QTRY_VERIFY_WITH_TIMEOUT(!reconnected.marketplaceInstallationLoading(),5000);
        QCOMPARE(reconnected.marketplaceInstallation().value("initial_request").toMap(),original.toVariantMap());
        reconnected.cancelMarketplaceInstallation(); QTRY_VERIFY_WITH_TIMEOUT(!reconnected.marketplaceInstallationLoading(),5000);
        QCOMPARE(cancels.first().toObject().value("mutation_id").toString(),cancellation);
        const auto request=cancels.first(); reconnected.retryMarketplaceInstallationAction();
        QTRY_VERIFY_WITH_TIMEOUT(!reconnected.marketplaceInstallationLoading(),5000);
        QCOMPARE(cancels.last(),request);
    }

    void marketplace_status_poll_keeps_preferences_but_never_failed_or_malformed_health() {
        FakeHttpServer server;QVERIFY(server.start());
        auto response=marketplaceResponse(7,marketplacePreferences("off"));
        response.insert("startup",QJsonObject{{"configured",true},{"retry_owner_present",true},{"retry_after_seconds",240}});
        int status=200,delay=0;
        server.setHandler([&](const HttpRequest &)->HttpResponse{return {status,QJsonDocument(response).toJson(),delay};});
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        client.setSessionState(marketplaceOwnerSession().toVariantMap());
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        const auto settings=client.marketplaceSettings().value("settings");
        QCOMPARE(client.marketplaceSettings().value("startup").toMap().value("retry_after_seconds").toInt(),240);
        delay=80;
        const auto count=server.requests().size();
        client.pollMarketplaceSettings();client.pollMarketplaceSettings();
        QCOMPARE(client.marketplaceSettings().value("settings"),settings);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(server.requests().size(),count+1);
        status=503;delay=0;
        client.pollMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(client.marketplaceSettings().value("settings"),settings);
        QVERIFY(!client.marketplaceSettings().value("runtime_fresh").toBool());
        QVERIFY(!client.marketplaceSettings().contains("startup"));
        QCOMPARE(client.marketplaceSettings().value("runtime_status").toString(),QString("unknown"));
        status=200;
        auto startup=response.value("startup").toObject();startup.insert("retry_after_seconds",301);response.insert("startup",startup);
        client.pollMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(client.marketplaceSettings().value("settings"),settings);
        QVERIFY(!client.marketplaceSettings().value("runtime_fresh").toBool());
        startup.insert("retry_after_seconds",10);response.insert("startup",startup);
        client.pollMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QVERIFY(client.marketplaceSettings().value("runtime_fresh").toBool());
        QCOMPARE(client.marketplaceSettings().value("startup").toMap().value("retry_after_seconds").toInt(),10);
        delay=80;client.pollMarketplaceSettings();client.setAuthToken(QString());
        QTest::qWait(150);QVERIFY(client.marketplaceSettings().isEmpty());
    }

    void marketplace_provider_choice_requires_current_consent_and_sends_no_identity_or_native_configuration() {
        FakeHttpServer server; QVERIFY(server.start());
        auto response=marketplaceResponse(1,marketplacePreferences("off"));
        response.insert("provider_setup",QJsonObject{{"schema_version",1},{"revision",0},{"enabled",false},
            {"consent_current",false},{"consent_version","elixir-marketplace-warp-v1"}});
        QList<QJsonObject> submitted;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method=="GET")return {200,QJsonDocument(response).toJson(),0};
            if(request.method!="PATCH" || request.path!="/api/v1/marketplace/connection/provider")return {500,"{}",0};
            const auto body=QJsonDocument::fromJson(request.body).object(); submitted.append(body);
            auto setup=response.value("provider_setup").toObject();
            setup.insert("revision",setup.value("revision").toInt()+1);
            setup.insert("enabled",body.value("enabled"));setup.insert("consent_current",body.value("enabled"));
            response.insert("provider_setup",setup);
            return {200,QJsonDocument(response).toJson(),60};
        });
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.saveMarketplaceProviderSetup(true,"elixir-marketplace-warp-v1"); QCOMPARE(submitted.size(),0);
        client.setSessionState(marketplaceOwnerSession().toVariantMap());
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        client.saveMarketplaceProviderSetup(true,""); QCOMPARE(submitted.size(),0);
        client.saveMarketplaceProviderSetup(true,"elixir-marketplace-warp-v1");
        client.saveMarketplaceProviderSetup(true,"elixir-marketplace-warp-v1");
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceConnectionSaving(),5000);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(submitted.size(),1);
        QCOMPARE(submitted[0].keys(),QStringList({"consent_version","enabled","expected_revision","mutation_id","schema_version"}));
        QCOMPARE(submitted[0].value("expected_revision"),QJsonValue(0));
        QVERIFY(!QUuid(submitted[0].value("mutation_id").toString()).isNull());
        QVERIFY(client.marketplaceSettings().value("provider_setup").toMap().value("enabled").toBool());
        QCOMPARE(client.marketplaceSettings().value("runtime_status").toString(),QString("not_connected"));
        client.saveMarketplaceProviderSetup(false,"");
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceConnectionSaving(),5000);
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(submitted.size(),2);
        QCOMPARE(submitted[1].value("expected_revision"),QJsonValue(1));
        QVERIFY(submitted[1].value("consent_version").isNull());
        QVERIFY(!client.marketplaceSettings().value("provider_setup").toMap().value("enabled").toBool());
    }

    void marketplace_provider_status_rejects_extra_authority_and_late_old_account_mutations() {
        FakeHttpServer server;QVERIFY(server.start());
        auto response=marketplaceResponse(1,marketplacePreferences("off"));
        auto setup=QJsonObject{{"schema_version",1},{"revision",0},{"enabled",false},
            {"consent_current",false},{"consent_version","elixir-marketplace-warp-v1"}};
        response.insert("provider_setup",setup);int mutations=0;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method=="GET")return {200,QJsonDocument(response).toJson(),0};
            mutations++;auto accepted=response;auto chosen=setup;chosen.insert("revision",1);
            chosen.insert("enabled",true);chosen.insert("consent_current",true);accepted.insert("provider_setup",chosen);
            return {200,QJsonDocument(accepted).toJson(),150};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        client.setSessionState(marketplaceOwnerSession().toVariantMap());
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QVERIFY(client.marketplaceSettings().value("runtime_fresh").toBool());
        auto invalid=setup;invalid.insert("protected",true);response.insert("provider_setup",invalid);
        client.pollMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QVERIFY(!client.marketplaceSettings().value("runtime_fresh").toBool());
        QVERIFY(!client.marketplaceSettings().contains("provider_setup"));
        client.saveMarketplaceProviderSetup(true,"elixir-marketplace-warp-v1");QCOMPARE(mutations,0);
        response.insert("provider_setup",setup);client.pollMarketplaceSettings();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        client.saveMarketplaceProviderSetup(true,"elixir-marketplace-warp-v1");
        QTRY_COMPARE_WITH_TIMEOUT(mutations,1,5000);
        client.setAuthToken(QString());QTest::qWait(200);
        QVERIFY(client.marketplaceSettings().isEmpty());QVERIFY(!client.marketplaceConnectionSaving());
    }

    void marketplace_connection_retry_is_authenticated_bounded_and_does_not_claim_readiness() {
        FakeHttpServer server;QVERIFY(server.start());QJsonObject submitted;QByteArray authorization;int posts=0;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method=="GET")return {200,QJsonDocument(marketplaceResponse()).toJson(),0};
            if(request.path!="/api/v1/marketplace/connection/retry")return {500,"{}",0};
            submitted=QJsonDocument::fromJson(request.body).object();authorization=request.headers.value("authorization");posts++;
            return {200,R"({"schema_version":1,"requested":true})",80};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        client.retryMarketplaceConnection();QCOMPARE(posts,0);
        client.setSessionState(marketplaceOwnerSession().toVariantMap());
        client.retryMarketplaceConnection();client.retryMarketplaceConnection();client.saveMarketplaceWireguard("must-not-send");
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceConnectionSaving(),5000);
        QCOMPARE(posts,1);QCOMPARE(submitted,QJsonObject({{"schema_version",1}}));
        QCOMPARE(authorization,QByteArray("Bearer owner-token"));
        QVERIFY(client.marketplaceConnectionNotice().contains("Retry requested"));
        QVERIFY(!client.marketplaceConnectionNotice().contains("protected connection confirmed"));
        client.retryMarketplaceConnection();client.setAuthToken(QString());
        QTest::qWait(150);QVERIFY(client.marketplaceConnectionNotice().isEmpty());
        QVERIFY(!client.marketplaceConnectionSaving());
    }

    void marketplace_settings_cas_is_bearer_authenticated_and_not_optimistic() {
        FakeHttpServer server; QVERIFY(server.start());
        QJsonObject body; QByteArray authorization;
        server.setHandler([&](const HttpRequest &request) -> HttpResponse {
            if (request.method=="GET") return {200,QJsonDocument(marketplaceResponse()).toJson(),0};
            body=QJsonDocument::fromJson(request.body).object(); authorization=request.headers.value("authorization");
            return {200,QJsonDocument(marketplaceResponse(1,body.value("preferences").toObject())).toJson(),100};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        QSignalSpy saved(&client,&ApiClient::marketplaceSettingsSaved);
        client.fetchMarketplaceSettings();client.fetchMarketplaceSettings();
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(server.requests().size(),1);
        client.saveMarketplaceSettings(marketplacePreferences("off").toVariantMap());
        QCOMPARE(saved.count(),0);
        QCOMPARE(client.marketplaceSettings().value("settings").toMap().value("revision").toInt(),0);
        QTRY_COMPARE_WITH_TIMEOUT(saved.count(),1,5000);
        QCOMPARE(authorization,QByteArray("Bearer owner-token"));
        QCOMPARE(body.value("expected_revision").toInt(),0);
        QVERIFY(!QUuid(body.value("mutation_id").toString()).isNull());
        QVERIFY(!body.value("preferences").toObject().value("paid_support_consent").toBool());
        QCOMPARE(client.marketplaceSettings().value("settings").toMap().value("revision").toInt(),1);
    }

    void marketplace_connection_import_is_purpose_bound_without_switching_or_caching_credentials() {
        FakeHttpServer server;QVERIFY(server.start());QJsonObject submitted;int posts=0;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.method=="GET")return {200,QJsonDocument(marketplaceResponse()).toJson(),0};
            submitted=QJsonDocument::fromJson(request.body).object();posts++;
            return {200,R"({"profile":{"id":"marketplace-network","scope":"marketplace_network","kind":"wireguard_config","enabled":true,"strict":true},"checks":[],"blocker":null})",80};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        client.setSessionState(marketplaceOwnerSession().toVariantMap());
        client.saveMarketplaceWireguard(" dedicated-private-config ");client.saveMarketplaceWireguard("duplicate");
        QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceConnectionSaving(),5000);QCOMPARE(posts,1);
        QCOMPARE(submitted.value("purpose").toString(),QString("marketplace_network"));
        QCOMPARE(submitted.value("profileId").toString(),QString("marketplace-network"));
        QCOMPARE(submitted.value("config").toString(),QString("dedicated-private-config"));
        QVERIFY(!submitted.contains("gatewayImage"));QVERIFY(!submitted.contains("forwardedPort"));
        QVERIFY(client.marketplaceConnectionNotice().contains("Configuration saved"));
        QVERIFY(!client.marketplaceConnectionNotice().contains("dedicated-private-config"));
        for(const auto &request:server.requests())QVERIFY(!request.path.contains("switch"));
        client.setAuthToken(QString());QVERIFY(client.marketplaceConnectionNotice().isEmpty());
        client.saveMarketplaceWireguard("signed-out secret");QTest::qWait(20);QCOMPARE(posts,1);
    }

    void marketplace_connection_rejects_stale_context_and_wrong_purpose_success() {
        FakeHttpServer server;QVERIFY(server.start());
        server.setHandler([](const HttpRequest &request)->HttpResponse {
            if(request.method=="GET")return {200,QJsonDocument(marketplaceResponse()).toJson(),0};
            return {200,R"({"profile":{"id":"marketplace-network","scope":"managed_downloaders","kind":"wireguard_config","enabled":true,"strict":true},"blocker":null})",100};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        client.setSessionState(marketplaceOwnerSession().toVariantMap());
        client.saveMarketplaceWireguard("private-config");QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceConnectionSaving(),5000);
        QVERIFY(client.marketplaceConnectionNotice().contains("not confirmed"));
        client.saveMarketplaceWireguard("private-config");client.setAuthToken(QString());
        QTest::qWait(150);QVERIFY(client.marketplaceConnectionNotice().isEmpty());QVERIFY(!client.marketplaceConnectionSaving());
    }

    void marketplace_conflict_requires_reload_without_retry_or_positive_cached_state() {
        FakeHttpServer server;QVERIFY(server.start());
        server.setHandler([](const HttpRequest &request)->HttpResponse {
            if(request.method=="GET")return {200,QJsonDocument(marketplaceResponse()).toJson(),0};
            return {409,R"({"code":"conflict","message":"reload"})",0};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        QSignalSpy failures(&client,&ApiClient::requestFailed);
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        client.saveMarketplaceSettings(marketplacePreferences("off").toVariantMap());
        QTRY_COMPARE_WITH_TIMEOUT(failures.count(),1,5000);
        QVERIFY(client.marketplaceSettings().isEmpty());
        client.saveMarketplaceSettings(marketplacePreferences("off").toVariantMap());
        QCOMPARE(server.requests().size(),2);
    }

    void marketplace_auth_retry_keeps_the_exact_mutation_id_and_preferences() {
        FakeHttpServer server;QVERIFY(server.start());
        QList<QByteArray> bodies;
        server.setHandler([&](const HttpRequest &request)->HttpResponse {
            if(request.path=="/api/v1/auth/refresh")
                return {200,QJsonDocument(tokenResponse("fresh-token","refresh-2")).toJson(),0};
            if(request.path=="/api/v1/auth/session")
                return {200,QJsonDocument(sessionResponse()).toJson(),0};
            if(request.method=="GET")return {200,QJsonDocument(marketplaceResponse()).toJson(),0};
            bodies.append(request.body);
            if(bodies.size()==1)return {401,R"({"message":"refresh"})",0};
            const auto preferences=QJsonDocument::fromJson(request.body).object().value("preferences").toObject();
            return {200,QJsonDocument(marketplaceResponse(1,preferences)).toJson(),0};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        client.setRefreshToken("refresh-1");client.setAccessTokenExpiresAt(futureTimestamp());
        client.setSessionState(QVariantMap{{"session_id",kSessionId},{"home_id",kHomeId},
            {"active_profile_id",kProfileId},{"active_profile_name","Owner"},{"active_profile_type","account"},
            {"role","owner"},{"capability_revision",1},
            {"capabilities",QStringList{"library_read","live_browse","live_play"}}});
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QSignalSpy saved(&client,&ApiClient::marketplaceSettingsSaved);
        client.saveMarketplaceSettings(marketplacePreferences("off").toVariantMap());
        QTRY_COMPARE_WITH_TIMEOUT(saved.count(),1,5000);
        QCOMPARE(bodies.size(),2);
        QCOMPARE(bodies[0],bodies[1]);
        QCOMPARE(server.countPath("/api/v1/auth/refresh"),1);
    }

    void marketplace_stale_context_reply_and_oversized_response_cannot_restore_settings() {
        FakeHttpServer server;QVERIFY(server.start());
        bool oversized=false;
        server.setHandler([&](const HttpRequest &)->HttpResponse {
            auto response=marketplaceResponse();
            if(oversized)response.insert("issuer_disclosure",QString(32000,'x'));
            return {200,QJsonDocument(response).toJson(),100};
        });
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        client.fetchMarketplaceSettings();
        client.setSessionState(QVariantMap{{"session_id",kSessionId},{"home_id",kHomeId},{"active_profile_id",kProfileId}});
        QTest::qWait(250);
        QVERIFY(client.marketplaceSettings().isEmpty());
        QVERIFY(!client.marketplaceSettingsLoading());
        oversized=true;QSignalSpy failures(&client,&ApiClient::requestFailed);
        client.fetchMarketplaceSettings();
        QTRY_VERIFY_WITH_TIMEOUT(failures.count()>0,5000);
        QVERIFY(client.marketplaceSettings().isEmpty());
        QVERIFY(!client.marketplaceSettingsLoading());
    }

    void marketplace_runtime_ack_requires_matching_revision_and_noncontributing_off_roles() {
        FakeHttpServer server;QVERIFY(server.start());
        const QJsonObject consumer{{"consumer",true},{"catalog",false},{"routing",false}};
        auto response=marketplaceResponse(1,marketplacePreferences("off"));
        response.insert("runtime_status","running");response.insert("participation_applied",true);
        QJsonObject state{{"phase","running"},{"preferences_revision",2},
            {"desired_roles",consumer},{"applied_roles",consumer},{"package_sharing_active",false}};
        response.insert("runtime",QJsonObject{{"phase","running"},{"participation",state}});
        server.setHandler([&](const HttpRequest &)->HttpResponse{return {200,QJsonDocument(response).toJson(),0};});
        ApiClient client;client.setBaseUrl(server.baseUrl());client.setAuthToken("owner-token");
        QSignalSpy failures(&client,&ApiClient::requestFailed);
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(failures.count(),1);QVERIFY(client.marketplaceSettings().isEmpty());
        state.insert("preferences_revision",1);
        auto serving=consumer;serving.insert("catalog",true);
        state.insert("desired_roles",serving);state.insert("applied_roles",serving);
        response.insert("runtime",QJsonObject{{"phase","running"},{"participation",state}});
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(failures.count(),2);QVERIFY(client.marketplaceSettings().isEmpty());
        state.insert("desired_roles",consumer);state.insert("applied_roles",consumer);
        response.insert("runtime",QJsonObject{{"phase","running"},{"participation",state}});
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(failures.count(),2);QVERIFY(!client.marketplaceSettings().isEmpty());
        response.insert("runtime_status","stopped");response.insert("participation_applied",false);
        state.insert("phase","stopped");
        response.insert("runtime",QJsonObject{{"phase","stopped"},{"participation",state}});
        client.fetchMarketplaceSettings();QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(failures.count(),3);QVERIFY(client.marketplaceSettings().isEmpty());
    }

    void marketplace_catalog_progress_schema_and_age_validation_fail_closed() {
        FakeHttpServer server; QVERIFY(server.start());
        auto response = marketplaceResponse(1,marketplacePreferences("auto"));
        const QJsonObject consumer{{"consumer",true},{"catalog",false},{"routing",false}};
        QJsonObject progress{{"phase","waiting"},{"observed_seconds",0},{"last_peer_page_seconds",40},
            {"last_peer_scan_seconds",60},{"last_page_examined",0}};
        QJsonObject state{{"phase","running"},{"preferences_revision",1},{"desired_roles",consumer},
            {"applied_roles",consumer},{"package_sharing_active",false},{"catalog",progress}};
        response.insert("runtime_status","running"); response.insert("participation_applied",false);
        response.insert("runtime",QJsonObject{{"phase","running"},{"participation",state}});
        server.setHandler([&](const HttpRequest &)->HttpResponse {return {200,QJsonDocument(response).toJson(),0};});
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        QSignalSpy failures(&client,&ApiClient::requestFailed);
        const auto read = [&]() {client.fetchMarketplaceSettings();};
        read(); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(failures.count(),0); QVERIFY(!client.marketplaceSettings().isEmpty());
        QList<QJsonObject> invalid;
        auto bad = progress; bad.insert("ready",true); invalid.append(bad);
        bad = progress; bad.insert("last_page_examined",21); invalid.append(bad);
        bad = progress; bad.insert("observed_seconds",-1); invalid.append(bad);
        bad = progress; bad.insert("observed_seconds",QJsonValue::Null); invalid.append(bad);
        bad = progress; bad.insert("last_peer_page_seconds",QJsonValue::Null); invalid.append(bad);
        bad = progress; bad.insert("last_peer_scan_seconds",20); invalid.append(bad);
        bad = progress; bad.insert("phase","ready"); invalid.append(bad);
        bad = progress; bad.insert("observed_seconds",0.5); invalid.append(bad);
        bad = progress; bad.insert("peer","must-not-be-exposed"); invalid.append(bad);
        int rejected = 0;
        for (const auto &value : invalid) {
            state.insert("catalog",value);
            response.insert("runtime",QJsonObject{{"phase","running"},{"participation",state}});
            read(); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
            QCOMPARE(failures.count(),++rejected); QVERIFY(client.marketplaceSettings().isEmpty());
        }
        progress.insert("observed_seconds",31); state.insert("catalog",progress);
        response.insert("runtime",QJsonObject{{"phase","running"},{"participation",state}});
        read(); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QCOMPARE(failures.count(),rejected);
        QCOMPARE(client.marketplaceSettings().value("runtime").toMap().value("participation").toMap()
            .value("catalog").toMap().value("phase").toString(),QString("unavailable"));
    }

    void marketplace_runtime_progress_expires_without_erasing_preferences_or_crossing_sessions() {
        FakeHttpServer server; QVERIFY(server.start());
        auto response = marketplaceResponse(1,marketplacePreferences("auto"));
        const QJsonObject roles{{"consumer",true},{"catalog",false},{"routing",false}};
        const QJsonObject catalog{{"phase","waiting"},{"observed_seconds",0},{"last_peer_page_seconds",40},
            {"last_peer_scan_seconds",60},{"last_page_examined",5}};
        const QJsonObject state{{"phase","running"},{"preferences_revision",1},{"desired_roles",roles},
            {"applied_roles",roles},{"package_sharing_active",false},{"catalog",catalog}};
        response.insert("runtime_status","running"); response.insert("participation_applied",false);
        response.insert("runtime",QJsonObject{{"phase","running"},{"participation",state}});
        server.setHandler([&](const HttpRequest &)->HttpResponse {return {200,QJsonDocument(response).toJson(),80};});
        ApiClient client; client.setBaseUrl(server.baseUrl()); client.setAuthToken("owner-token");
        client.fetchMarketplaceSettings(); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QVERIFY(client.marketplaceSettings().value("runtime_fresh").toBool());
        const auto saved = client.marketplaceSettings().value("settings");
        QVERIFY(client.marketplaceSettings().value("runtime").toMap().value("participation").toMap()
            .value("catalog").toMap().value("last_peer_page_seconds").toDouble() >= 41);
        auto *expiry = client.findChild<QTimer *>("marketplaceRuntimeFreshness"); QVERIFY(expiry);
        QVERIFY(expiry->isActive()); QVERIFY(expiry->interval() <= 30000 && expiry->interval() > 29000);
        QCOMPARE(expiry->timerType(),Qt::PreciseTimer);
        expiry->start(1); // Exercise the real callback without a 30-second fixture sleep.
        QTRY_VERIFY(!client.marketplaceSettings().value("runtime_fresh").toBool());
        QCOMPARE(client.marketplaceSettings().value("settings"),saved);
        QVERIFY(!client.marketplaceSettings().contains("runtime"));
        client.fetchMarketplaceSettings(); QTRY_VERIFY_WITH_TIMEOUT(!client.marketplaceSettingsLoading(),5000);
        QVERIFY(expiry->isActive());
        client.setAuthToken(QString());
        QVERIFY(!expiry->isActive()); QVERIFY(client.marketplaceSettings().isEmpty());
        bool loggedOutDuringNotification = false;
        connect(&client,&ApiClient::marketplaceSettingsChanged,&client,[&]() {
            if (!loggedOutDuringNotification && client.marketplaceSettings().value("runtime_fresh").toBool()) {
                loggedOutDuringNotification = true; client.setAuthToken(QString());
            }
        });
        client.setAuthToken("replacement-token"); client.fetchMarketplaceSettings();
        QTRY_VERIFY_WITH_TIMEOUT(loggedOutDuringNotification,5000);
        QVERIFY(client.marketplaceSettings().isEmpty()); QVERIFY(!expiry->isActive());
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
