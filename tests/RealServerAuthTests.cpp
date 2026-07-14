#include "backend/ApiClient.h"

#include <QSignalSpy>
#include <QTest>
#include <QVariantMap>

namespace {
QString requiredEnvironment(const char *name) {
    return qEnvironmentVariable(name).trimmed();
}

QVariantMap profileById(const QVariantList &profiles, const QString &profileId) {
    for (const QVariant &entry : profiles) {
        const QVariantMap profile = entry.toMap();
        if (profile.value(QStringLiteral("id")).toString() == profileId) {
            return profile;
        }
    }
    return {};
}
} // namespace

class RealServerAuthTests final : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        m_serverUrl = requiredEnvironment("ELIXIR_A15_SERVER_URL");
        m_email = requiredEnvironment("ELIXIR_A15_EMAIL");
        m_password = requiredEnvironment("ELIXIR_A15_PASSWORD");
        m_ownerProfileId = requiredEnvironment("ELIXIR_A15_OWNER_PROFILE_ID");
        m_managedProfileId = requiredEnvironment("ELIXIR_A15_MANAGED_PROFILE_ID");
        m_managedPin = requiredEnvironment("ELIXIR_A15_MANAGED_PIN");

        QVERIFY2(!m_serverUrl.isEmpty(), "ELIXIR_A15_SERVER_URL is required");
        QVERIFY2(!m_email.isEmpty(), "ELIXIR_A15_EMAIL is required");
        QVERIFY2(!m_password.isEmpty(), "ELIXIR_A15_PASSWORD is required");
        QVERIFY2(!m_ownerProfileId.isEmpty(), "ELIXIR_A15_OWNER_PROFILE_ID is required");
        QVERIFY2(!m_managedProfileId.isEmpty(), "ELIXIR_A15_MANAGED_PROFILE_ID is required");
        QVERIFY2(!m_managedPin.isEmpty(), "ELIXIR_A15_MANAGED_PIN is required");
    }

    void a15_real_server_refresh_profile_restore_and_logout() {
        ApiClient client;
        client.setBaseUrl(m_serverUrl);
        QSignalSpy loginSucceeded(&client, &ApiClient::loginSucceeded);
        QSignalSpy loginFailed(&client, &ApiClient::loginFailed);
        client.login(m_email, m_password);
        QTRY_COMPARE_WITH_TIMEOUT(loginSucceeded.count(), 1, 10000);
        QCOMPARE(loginFailed.count(), 0);
        QCOMPARE(client.activeProfileId(), m_ownerProfileId);
        QCOMPARE(client.activeProfileType(), QStringLiteral("account"));
        QCOMPARE(client.homeRole(), QStringLiteral("owner"));
        QVERIFY(client.capabilities().contains(QStringLiteral("live_browse")));
        QVERIFY(client.capabilities().contains(QStringLiteral("live_play")));
        QVERIFY(client.capabilities().contains(QStringLiteral("live_manage")));
        QVERIFY(client.capabilities().contains(QStringLiteral("extensions_manage")));
        QVERIFY(client.capabilities().contains(QStringLiteral("secrets_manage")));
        QVERIFY(!client.authToken().isEmpty());
        QVERIFY(!client.refreshToken().isEmpty());

        QSignalSpy profilesReceived(&client, &ApiClient::profilesReceived);
        client.fetchProfiles();
        QTRY_COMPARE_WITH_TIMEOUT(profilesReceived.count(), 1, 10000);
        const QVariantMap ownerProfile = profileById(client.profiles(), m_ownerProfileId);
        const QVariantMap managedProfile = profileById(client.profiles(), m_managedProfileId);
        QVERIFY(!ownerProfile.isEmpty());
        QVERIFY(!managedProfile.isEmpty());
        QCOMPARE(ownerProfile.value(QStringLiteral("role")).toString(), QStringLiteral("owner"));
        QCOMPARE(managedProfile.value(QStringLiteral("role")).toString(), QStringLiteral("viewer"));
        QCOMPARE(managedProfile.value(QStringLiteral("has_pin")).toBool(), true);

        QSignalSpy selectionFailures(&client, &ApiClient::requestFailed);
        client.selectProfile(m_managedProfileId, QStringLiteral("9999"));
        QTRY_COMPARE_WITH_TIMEOUT(selectionFailures.count(), 1, 10000);
        QCOMPARE(client.activeProfileId(), m_ownerProfileId);
        QCOMPARE(selectionFailures.at(0).at(0).toString(), QStringLiteral("/api/v1/profiles/%1/select").arg(m_managedProfileId));

        QSignalSpy managedSelected(&client, &ApiClient::profileSelected);
        client.selectProfile(m_managedProfileId, m_managedPin);
        QTRY_COMPARE_WITH_TIMEOUT(managedSelected.count(), 1, 10000);
        QCOMPARE(client.activeProfileId(), m_managedProfileId);
        QCOMPARE(client.activeProfileType(), QStringLiteral("managed"));
        QCOMPARE(client.homeRole(), QStringLiteral("viewer"));
        QVERIFY(client.capabilities().contains(QStringLiteral("library_read")));
        QVERIFY(client.capabilities().contains(QStringLiteral("media_play")));
        QVERIFY(client.capabilities().contains(QStringLiteral("live_browse")));
        QVERIFY(client.capabilities().contains(QStringLiteral("live_play")));
        QVERIFY(!client.capabilities().contains(QStringLiteral("live_manage")));
        QVERIFY(!client.capabilities().contains(QStringLiteral("extensions_manage")));
        QVERIFY(!client.capabilities().contains(QStringLiteral("secrets_manage")));

        QSignalSpy managedProfilesReceived(&client, &ApiClient::profilesReceived);
        client.fetchProfiles();
        QTRY_COMPARE_WITH_TIMEOUT(managedProfilesReceived.count(), 1, 10000);
        QCOMPARE(
            profileById(client.profiles(), m_ownerProfileId)
                .value(QStringLiteral("role"))
                .toString(),
            QStringLiteral("owner"));

        const QString accessBeforeRefresh = client.authToken();
        const QString refreshBeforeRotation = client.refreshToken();
        client.refreshAuth();
        QTRY_VERIFY_WITH_TIMEOUT(
            !client.refreshInFlight() && client.refreshToken() != refreshBeforeRotation,
            10000);
        QVERIFY(client.authToken() != accessBeforeRefresh);
        QCOMPARE(client.activeProfileId(), m_managedProfileId);
        QCOMPARE(client.homeRole(), QStringLiteral("viewer"));

        QSignalSpy ownerSelected(&client, &ApiClient::profileSelected);
        client.selectProfile(m_ownerProfileId);
        QTRY_COMPARE_WITH_TIMEOUT(ownerSelected.count(), 1, 10000);
        QCOMPARE(client.activeProfileId(), m_ownerProfileId);
        QCOMPARE(client.homeRole(), QStringLiteral("owner"));
        QVERIFY(client.capabilities().contains(QStringLiteral("live_manage")));

        ApiClient restored;
        restored.setBaseUrl(m_serverUrl);
        restored.setRefreshToken(client.refreshToken());
        QSignalSpy restoredSignal(&restored, &ApiClient::sessionRestored);
        QSignalSpy restoreFailed(&restored, &ApiClient::sessionRestoreFailed);
        restored.restoreSession();
        QTRY_COMPARE_WITH_TIMEOUT(restoredSignal.count(), 1, 10000);
        QCOMPARE(restoreFailed.count(), 0);
        QCOMPARE(restored.activeProfileId(), m_ownerProfileId);
        QCOMPARE(restored.homeRole(), QStringLiteral("owner"));
        QVERIFY(!restored.authToken().isEmpty());
        QVERIFY(!restored.refreshToken().isEmpty());

        QSignalSpy logoutCompleted(&restored, &ApiClient::logoutCompleted);
        restored.logout();
        QTRY_COMPARE_WITH_TIMEOUT(logoutCompleted.count(), 1, 10000);
        QVERIFY(restored.authToken().isEmpty());
        QVERIFY(restored.refreshToken().isEmpty());
        QVERIFY(restored.activeProfileId().isEmpty());
    }

private:
    QString m_serverUrl;
    QString m_email;
    QString m_password;
    QString m_ownerProfileId;
    QString m_managedProfileId;
    QString m_managedPin;
};

QTEST_GUILESS_MAIN(RealServerAuthTests)

#include "RealServerAuthTests.moc"
