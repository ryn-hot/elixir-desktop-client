#include "support/DeterministicScheduler.h"
#include "support/ScriptedNetworkAccessManager.h"

#include <QBuffer>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSignalSpy>
#include <QTest>

#include <stdexcept>
#include <vector>

class TestFoundationTests final : public QObject {
    Q_OBJECT

private slots:
    void schedulerOrdersEqualDeadlinesAndNestedEvents();
    void schedulerRejectsBackwardTimeAndCancelsEvents();
    void scriptedReplyIsDelayedCapturesRequestAndReturnsMetadata();
    void scriptedReplyCancellationIsTerminalAndIdempotent();
    void missingScriptFailsDeterministically();
};

void TestFoundationTests::schedulerOrdersEqualDeadlinesAndNestedEvents() {
    DeterministicScheduler scheduler;
    std::vector<int> order;
    scheduler.schedule(20, [&]() { order.push_back(3); });
    scheduler.schedule(10, [&]() {
        order.push_back(1);
        scheduler.schedule(0, [&]() { order.push_back(2); });
    });
    scheduler.advance(9);
    QCOMPARE(order.size(), std::size_t{0});
    scheduler.advance(1);
    QCOMPARE(order, std::vector<int>({1, 2}));
    scheduler.advance(10);
    QCOMPARE(order, std::vector<int>({1, 2, 3}));
    QCOMPARE(scheduler.nowMs(), std::int64_t{20});
    QCOMPARE(scheduler.pendingCount(), std::size_t{0});
}

void TestFoundationTests::schedulerRejectsBackwardTimeAndCancelsEvents() {
    DeterministicScheduler scheduler;
    bool called = false;
    const auto event = scheduler.schedule(1, [&]() { called = true; });
    QVERIFY(scheduler.cancel(event));
    QVERIFY(!scheduler.cancel(event));
    scheduler.advance(1);
    QVERIFY(!called);
    QVERIFY_THROWS_EXCEPTION(std::invalid_argument, scheduler.advance(-1));
}

void TestFoundationTests::scriptedReplyIsDelayedCapturesRequestAndReturnsMetadata() {
    DeterministicScheduler scheduler;
    ScriptedNetworkAccessManager network(scheduler);
    ScriptedHttpResponse scripted;
    scripted.statusCode = 206;
    scripted.headers.append(
        qMakePair(QByteArrayLiteral("content-type"), QByteArrayLiteral("application/json")));
    scripted.body = R"({"ok":true})";
    scripted.delayMs = 25;
    network.enqueue(scripted);

    QNetworkRequest request(QUrl(QStringLiteral("https://fixture.invalid/live?page=1")));
    request.setRawHeader("authorization", "Bearer test-only");
    auto *reply = network.get(request);
    QSignalSpy finished(reply, &QNetworkReply::finished);
    scheduler.advance(24);
    QCOMPARE(finished.count(), 0);
    scheduler.advance(1);
    QCOMPARE(finished.count(), 1);
    QCOMPARE(reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(), 206);
    QCOMPARE(reply->header(QNetworkRequest::ContentTypeHeader).toString(), QStringLiteral("application/json"));
    QCOMPARE(reply->readAll(), QByteArray(R"({"ok":true})"));
    QCOMPARE(network.pendingResponseCount(), std::size_t{0});
    QCOMPARE(network.capturedRequests().size(), 1);
    QCOMPARE(network.capturedRequests().constFirst().url, request.url());
    QCOMPARE(network.capturedRequests().constFirst().operation, QNetworkAccessManager::GetOperation);
}

void TestFoundationTests::scriptedReplyCancellationIsTerminalAndIdempotent() {
    DeterministicScheduler scheduler;
    ScriptedNetworkAccessManager network(scheduler);
    ScriptedHttpResponse scripted;
    scripted.body = "late";
    scripted.delayMs = 100;
    network.enqueue(scripted);
    auto *reply = network.get(QNetworkRequest(QUrl(QStringLiteral("https://fixture.invalid/slow"))));
    QSignalSpy finished(reply, &QNetworkReply::finished);
    QSignalSpy errors(reply, &QNetworkReply::errorOccurred);
    reply->abort();
    reply->abort();
    QCOMPARE(finished.count(), 1);
    QCOMPARE(errors.count(), 1);
    QCOMPARE(reply->error(), QNetworkReply::OperationCanceledError);
    scheduler.advance(100);
    QCOMPARE(finished.count(), 1);
    QCOMPARE(reply->readAll(), QByteArray());
}

void TestFoundationTests::missingScriptFailsDeterministically() {
    DeterministicScheduler scheduler;
    ScriptedNetworkAccessManager network(scheduler);
    auto *reply = network.get(QNetworkRequest(QUrl(QStringLiteral("https://fixture.invalid/missing"))));
    QSignalSpy finished(reply, &QNetworkReply::finished);
    scheduler.runDue();
    QCOMPARE(finished.count(), 1);
    QCOMPARE(reply->error(), QNetworkReply::ProtocolUnknownError);
    QCOMPARE(network.capturedRequests().size(), 1);
}

QTEST_GUILESS_MAIN(TestFoundationTests)

#include "TestFoundationTests.moc"
