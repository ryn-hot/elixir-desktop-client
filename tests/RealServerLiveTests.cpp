#include "backend/ApiClient.h"
#include "live/LiveApiClient.h"
#include "live/LiveCatalogModel.h"

#include <QDateTime>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QTest>

namespace {

QString requiredEnvironment(const char *name) {
  return qEnvironmentVariable(name).trimmed();
}

QVariantMap catalogById(const QVariantList &catalogs,
                        const QString &catalogId) {
  for (const QVariant &entry : catalogs) {
    const QVariantMap catalog = entry.toMap();
    if (catalog.value(QStringLiteral("catalogId")).toString() == catalogId) {
      return catalog;
    }
  }
  return {};
}

} // namespace

class RealServerLiveTests final : public QObject {
  Q_OBJECT

private slots:
  void initTestCase() {
    m_serverUrl = requiredEnvironment("ELIXIR_G20_SERVER_URL");
    m_email = requiredEnvironment("ELIXIR_G20_EMAIL");
    m_password = requiredEnvironment("ELIXIR_G20_PASSWORD");
    QVERIFY2(!m_serverUrl.isEmpty(), "ELIXIR_G20_SERVER_URL is required");
    QVERIFY2(!m_email.isEmpty(), "ELIXIR_G20_EMAIL is required");
    QVERIFY2(!m_password.isEmpty(), "ELIXIR_G20_PASSWORD is required");
  }

  void g20_real_server_fixture_browse_refresh_details_and_logout() {
    ApiClient auth;
    auth.setBaseUrl(m_serverUrl);
    QSignalSpy loginSucceeded(&auth, &ApiClient::loginSucceeded);
    QSignalSpy loginFailed(&auth, &ApiClient::loginFailed);
    auth.login(m_email, m_password);
    QTRY_COMPARE_WITH_TIMEOUT(loginSucceeded.count(), 1, 10000);
    QCOMPARE(loginFailed.count(), 0);
    QVERIFY(auth.capabilities().contains(QStringLiteral("live_browse")));
    QVERIFY(!auth.authToken().isEmpty());
    QVERIFY(!auth.refreshToken().isEmpty());

    LiveApiClient api(&auth);
    LiveCatalogModel model(&api);
    QSignalSpy errors(&api, &LiveApiClient::requestFailed);
    model.refreshIndex();
    QTRY_VERIFY_WITH_TIMEOUT(!model.catalogIndexLoading(), 10000);
    QCOMPARE(model.providers().size(), 2);
    QVERIFY(!model.catalogs().isEmpty());
    QVERIFY(model.partial());
    QCOMPARE(model.errors().size(), 1);
    QCOMPARE(
        model.errors().first().toMap().value(QStringLiteral("code")).toString(),
        QStringLiteral("LIVE_PROVIDER_UNAVAILABLE"));

    const QVariantMap events =
        catalogById(model.catalogs(), QStringLiteral("events"));
    QVERIFY2(!events.isEmpty(), "The fixture events catalog was not returned");
    const QString providerId =
        events.value(QStringLiteral("providerId")).toString();
    model.selectCatalog(providerId, QStringLiteral("events"));
    QTRY_VERIFY_WITH_TIMEOUT(!model.pageLoading(), 10000);
    QVERIFY(model.rowCount() > 0);
    const QModelIndex first = model.index(0);
    const QString itemKey =
        model.data(first, LiveCatalogModel::ItemKeyRole).toString();
    QVERIFY(QRegularExpression(QStringLiteral("^[A-Za-z0-9._~-]{16,2048}$"))
                .match(itemKey)
                .hasMatch());
    QVERIFY(!itemKey.contains(QStringLiteral("event-live")));
    const QVariantMap poster =
        model.data(first, LiveCatalogModel::PosterRole).toMap();
    if (!poster.isEmpty()) {
      QVERIFY(poster.value(QStringLiteral("url"))
                  .toString()
                  .startsWith(QStringLiteral("/api/v1/live/artwork/")));
    }

    model.loadItem(providerId, itemKey);
    QTRY_VERIFY_WITH_TIMEOUT(!model.itemLoading(), 10000);
    QVERIFY(!model.selectedItem().isEmpty());
    QVERIFY(!model.selectedStreams().isEmpty());
    const QVariantMap stream = model.selectedStreams().first().toMap();
    QVERIFY(
        QRegularExpression(QStringLiteral("^[A-Za-z0-9._~-]{16,2048}$"))
            .match(stream.value(QStringLiteral("streamOptionKey")).toString())
            .hasMatch());
    QVERIFY(!stream.contains(QStringLiteral("url")));

    const QString refreshBeforeRotation = auth.refreshToken();
    auth.setAccessTokenExpiresAt(
        QDateTime::currentDateTimeUtc().addSecs(-1).toString(Qt::ISODate));
    model.refreshIndex();
    QTRY_VERIFY_WITH_TIMEOUT(
        !auth.refreshInFlight() && !model.catalogIndexLoading(), 10000);
    QVERIFY(!auth.authToken().isEmpty());
    QVERIFY(QDateTime::fromString(auth.accessTokenExpiresAt(), Qt::ISODate) >
            QDateTime::currentDateTimeUtc());
    QVERIFY(auth.refreshToken() != refreshBeforeRotation);
    QCOMPARE(errors.count(), 0);

    QSignalSpy logoutCompleted(&auth, &ApiClient::logoutCompleted);
    auth.logout();
    QTRY_COMPARE_WITH_TIMEOUT(logoutCompleted.count(), 1, 10000);
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 0, 10000);
    QVERIFY(model.providers().isEmpty());
    QVERIFY(model.catalogs().isEmpty());
    QVERIFY(model.selectedItem().isEmpty());
  }

private:
  QString m_serverUrl;
  QString m_email;
  QString m_password;
};

QTEST_GUILESS_MAIN(RealServerLiveTests)

#include "RealServerLiveTests.moc"
