#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QJsonObject>
#include <QUrl>
#include <QVariant>
#include <functional>

class QJsonDocument;

class ApiClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString authToken READ authToken WRITE setAuthToken NOTIFY authTokenChanged)
    Q_PROPERTY(QString accessTokenExpiresAt READ accessTokenExpiresAt WRITE setAccessTokenExpiresAt NOTIFY accessTokenExpiresAtChanged)
    Q_PROPERTY(QVariantMap clientCapabilities READ clientCapabilities WRITE setClientCapabilities NOTIFY clientCapabilitiesChanged)
    Q_PROPERTY(QString networkType READ networkType WRITE setNetworkType NOTIFY networkTypeChanged)
    Q_PROPERTY(QVariantList extensionsInstalled READ extensionsInstalled NOTIFY extensionsCatalogChanged)
    Q_PROPERTY(QVariantList extensionsAvailable READ extensionsAvailable NOTIFY extensionsCatalogChanged)
    Q_PROPERTY(QVariantList extensionsCore READ extensionsCore NOTIFY extensionsCatalogChanged)
    Q_PROPERTY(QVariantList extensionsInstances READ extensionsInstances NOTIFY extensionsInstancesChanged)
    Q_PROPERTY(QVariantList extensionsSecrets READ extensionsSecrets NOTIFY extensionsSecretsChanged)
    Q_PROPERTY(QVariantMap extensionsPlan READ extensionsPlan NOTIFY extensionsPlanChanged)
    Q_PROPERTY(QVariantList extensionsPlanConflicts READ extensionsPlanConflicts NOTIFY extensionsPlanChanged)
    Q_PROPERTY(QString extensionsPlanId READ extensionsPlanId NOTIFY extensionsPlanChanged)
    Q_PROPERTY(QVariantMap extensionsRun READ extensionsRun NOTIFY extensionsRunChanged)
    Q_PROPERTY(QVariantList extensionsRunSteps READ extensionsRunSteps NOTIFY extensionsRunChanged)
    Q_PROPERTY(QString extensionsRunId READ extensionsRunId NOTIFY extensionsRunChanged)
    Q_PROPERTY(QVariantList extensionsRuns READ extensionsRuns NOTIFY extensionsRunsChanged)
    Q_PROPERTY(QVariantMap extensionsReconcileRun READ extensionsReconcileRun NOTIFY extensionsReconcileRunChanged)
    Q_PROPERTY(QVariantList extensionsDesiredBlueprints READ extensionsDesiredBlueprints NOTIFY extensionsDesiredBlueprintsChanged)
    Q_PROPERTY(QVariantList extensionsStatusItems READ extensionsStatusItems NOTIFY extensionsStatusSummaryChanged)
    Q_PROPERTY(int extensionsNeedsAttentionCount READ extensionsNeedsAttentionCount NOTIFY extensionsStatusSummaryChanged)
    Q_PROPERTY(QVariantMap extensionsRuntimeStatus READ extensionsRuntimeStatus NOTIFY extensionsStatusSummaryChanged)
    Q_PROPERTY(QVariantMap extensionControlSurface READ extensionControlSurface NOTIFY extensionControlSurfaceChanged)
    Q_PROPERTY(bool extensionControlLoading READ extensionControlLoading NOTIFY extensionControlLoadingChanged)
    Q_PROPERTY(QString extensionsLastRefreshedAt READ extensionsLastRefreshedAt NOTIFY extensionsLastRefreshedAtChanged)
    Q_PROPERTY(QString extensionsLastRefreshSuccessAt READ extensionsLastRefreshSuccessAt NOTIFY extensionsLastRefreshSuccessAtChanged)
    Q_PROPERTY(QString extensionsLastRefreshError READ extensionsLastRefreshError NOTIFY extensionsLastRefreshErrorChanged)
    Q_PROPERTY(bool extensionsAutoWireEnabled READ extensionsAutoWireEnabled NOTIFY extensionsAutoWireStatusChanged)
    Q_PROPERTY(QString extensionsAutoWirePendingPlanId READ extensionsAutoWirePendingPlanId NOTIFY extensionsAutoWireStatusChanged)
    Q_PROPERTY(QString extensionsAutoWirePendingReason READ extensionsAutoWirePendingReason NOTIFY extensionsAutoWireStatusChanged)
    Q_PROPERTY(int extensionsAutoWirePendingConflicts READ extensionsAutoWirePendingConflicts NOTIFY extensionsAutoWireStatusChanged)
    Q_PROPERTY(QString extensionsDownloaderProfile READ extensionsDownloaderProfile NOTIFY extensionsDownloaderSettingsChanged)
    Q_PROPERTY(QString extensionsDownloaderDefaultProfile READ extensionsDownloaderDefaultProfile NOTIFY extensionsDownloaderSettingsChanged)
    Q_PROPERTY(QString extensionsDownloaderProfileSource READ extensionsDownloaderProfileSource NOTIFY extensionsDownloaderSettingsChanged)
    Q_PROPERTY(QString extensionsDownloaderProfileUpdatedAt READ extensionsDownloaderProfileUpdatedAt NOTIFY extensionsDownloaderSettingsChanged)
    Q_PROPERTY(int extensionsDownloaderPendingUpdateCount READ extensionsDownloaderPendingUpdateCount NOTIFY extensionsDownloaderSettingsChanged)
    Q_PROPERTY(QVariantList extensionsDownloaderProfileOptions READ extensionsDownloaderProfileOptions NOTIFY extensionsDownloaderSettingsChanged)
    Q_PROPERTY(QVariantList extensionsDownloaderTelemetry READ extensionsDownloaderTelemetry NOTIFY extensionsDownloaderSettingsChanged)
    Q_PROPERTY(QVariantMap mediaFindResult READ mediaFindResult NOTIFY mediaFindResultChanged)
    Q_PROPERTY(bool mediaFindLoading READ mediaFindLoading NOTIFY mediaFindLoadingChanged)
    Q_PROPERTY(QVariantMap mediaManagerPreferences READ mediaManagerPreferences NOTIFY mediaManagerPreferencesChanged)
    Q_PROPERTY(QVariantMap mediaAddResult READ mediaAddResult NOTIFY mediaAddResultChanged)
    Q_PROPERTY(bool mediaAddLoading READ mediaAddLoading NOTIFY mediaAddLoadingChanged)
    Q_PROPERTY(QVariantMap mediaAcquisitionStatus READ mediaAcquisitionStatus NOTIFY mediaAcquisitionChanged)
    Q_PROPERTY(QVariantList mediaAcquisitionItems READ mediaAcquisitionItems NOTIFY mediaAcquisitionChanged)
    Q_PROPERTY(int mediaAcquisitionActiveCount READ mediaAcquisitionActiveCount NOTIFY mediaAcquisitionChanged)
    Q_PROPERTY(int mediaAcquisitionDownloadingCount READ mediaAcquisitionDownloadingCount NOTIFY mediaAcquisitionChanged)
    Q_PROPERTY(int mediaAcquisitionNeedsAttentionCount READ mediaAcquisitionNeedsAttentionCount NOTIFY mediaAcquisitionChanged)

public:
    explicit ApiClient(QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &value);

    QString authToken() const;
    void setAuthToken(const QString &value);

    QString accessTokenExpiresAt() const;
    void setAccessTokenExpiresAt(const QString &value);
    Q_INVOKABLE bool accessTokenExpired(int skewSeconds = 0) const;
    Q_INVOKABLE void expireAuth(const QString &message = QString());

    QVariantMap clientCapabilities() const;
    void setClientCapabilities(const QVariantMap &value);

    QString networkType() const;
    void setNetworkType(const QString &value);

    QVariantList extensionsInstalled() const;
    QVariantList extensionsAvailable() const;
    QVariantList extensionsCore() const;
    QString extensionsLastRefreshedAt() const;
    QString extensionsLastRefreshSuccessAt() const;
    QString extensionsLastRefreshError() const;
    QVariantList extensionsInstances() const;
    QVariantList extensionsSecrets() const;
    QVariantMap extensionsPlan() const;
    QVariantList extensionsPlanConflicts() const;
    QString extensionsPlanId() const;
    QVariantMap extensionsRun() const;
    QVariantList extensionsRunSteps() const;
    QString extensionsRunId() const;
    QVariantList extensionsRuns() const;
    QVariantMap extensionsReconcileRun() const;
    QVariantList extensionsDesiredBlueprints() const;
    QVariantList extensionsStatusItems() const;
    int extensionsNeedsAttentionCount() const;
    QVariantMap extensionsRuntimeStatus() const;
    QVariantMap extensionControlSurface() const;
    bool extensionControlLoading() const;
    bool extensionsAutoWireEnabled() const;
    QString extensionsAutoWirePendingPlanId() const;
    QString extensionsAutoWirePendingReason() const;
    int extensionsAutoWirePendingConflicts() const;
    QString extensionsDownloaderProfile() const;
    QString extensionsDownloaderDefaultProfile() const;
    QString extensionsDownloaderProfileSource() const;
    QString extensionsDownloaderProfileUpdatedAt() const;
    int extensionsDownloaderPendingUpdateCount() const;
    QVariantList extensionsDownloaderProfileOptions() const;
    QVariantList extensionsDownloaderTelemetry() const;
    QVariantMap mediaFindResult() const;
    bool mediaFindLoading() const;
    QVariantMap mediaManagerPreferences() const;
    QVariantMap mediaAddResult() const;
    bool mediaAddLoading() const;
    QVariantMap mediaAcquisitionStatus() const;
    QVariantList mediaAcquisitionItems() const;
    int mediaAcquisitionActiveCount() const;
    int mediaAcquisitionDownloadingCount() const;
    int mediaAcquisitionNeedsAttentionCount() const;

    Q_INVOKABLE void login(const QString &email, const QString &password);
    Q_INVOKABLE void signup(const QString &email, const QString &password);
    Q_INVOKABLE void startPasswordReset(const QString &email);
    Q_INVOKABLE void completePasswordReset(const QString &token, const QString &newPassword);
    Q_INVOKABLE void fetchLibrary();
    Q_INVOKABLE void fetchMediaDetails(const QString &mediaItemId);
    Q_INVOKABLE void deleteLibraryItem(const QString &mediaItemId, bool stopTracking = false);
    Q_INVOKABLE void deleteEpisode(const QString &episodeId, bool blockInElixir = false);
    Q_INVOKABLE void restoreEpisode(const QString &episodeId);
    Q_INVOKABLE void restoreBlockedEpisodes(const QString &mediaItemId);
    Q_INVOKABLE void fetchSeasons(const QString &seriesId);
    Q_INVOKABLE void fetchSeasonDetail(const QString &seasonId);
    Q_INVOKABLE void fetchEpisodes(const QString &seasonId);
    Q_INVOKABLE void startPlayback(const QString &mediaItemId, const QString &preferredFileId);
    Q_INVOKABLE void seekPlayback(const QString &sessionId, double seconds);
    Q_INVOKABLE void pollSession(const QString &sessionId);
    Q_INVOKABLE void endSession(const QString &sessionId);
    Q_INVOKABLE void runScan(bool forceMetadata);
    Q_INVOKABLE void fetchReviewQueue(const QString &status, int limit, int offset);
    Q_INVOKABLE void fetchReviewQueueDetail(const QString &reviewId);
    Q_INVOKABLE void applyReviewMatch(const QString &reviewId, const QString &libraryType, const QVariantMap &externalIds, const QString &normalizedKey = QString());
    Q_INVOKABLE void fetchExtensionsCatalog();
    Q_INVOKABLE void refreshExtensionsCatalog();
    Q_INVOKABLE void installExtension(const QString &downloadUrl);
    Q_INVOKABLE void installExtensionSource(const QString &downloadUrl, const QString &packagePath = QString());
    Q_INVOKABLE void enableExtension(const QString &extensionId);
    Q_INVOKABLE void disableExtension(const QString &extensionId);
    Q_INVOKABLE void uninstallExtension(const QString &extensionId);
    Q_INVOKABLE void fetchExtensionInstances(const QString &extensionId = QString());
    Q_INVOKABLE void createExtensionInstance(const QString &extensionId, const QString &instanceName, const QString &configJson);
    Q_INVOKABLE void updateExtensionInstanceConfig(const QString &instanceId, const QString &configJson);
    Q_INVOKABLE void setExtensionInstanceEnabled(const QString &instanceId, bool enabled);
    Q_INVOKABLE void deleteExtensionInstance(const QString &instanceId);
    Q_INVOKABLE void rollbackExtensionInstance(const QString &instanceId);
    Q_INVOKABLE void createSecret(const QString &scope, const QString &scopeId, const QString &key, const QString &value, bool rotatable = false);
    Q_INVOKABLE void createInstanceSecret(const QString &instanceId, const QString &key, const QString &value, bool rotatable = false);
    Q_INVOKABLE void fetchInstanceSecrets(const QString &instanceId = QString());
    Q_INVOKABLE void rotateSecret(const QString &secretId, const QString &value = QString());
    Q_INVOKABLE void applyBlueprintPlan(const QString &blueprintId, const QString &paramsJson = QString());
    Q_INVOKABLE void confirmExtensionsPlan(const QString &planId, const QVariantList &decisions = QVariantList());
    Q_INVOKABLE void cancelExtensionsPlan(const QString &planId);
    Q_INVOKABLE void fetchExtensionRunDetail(const QString &runId);
    Q_INVOKABLE void fetchExtensionRuns(int limit = 20);
    Q_INVOKABLE void clearExtensionRuns();
    Q_INVOKABLE void fetchLatestReconcileRun();
    Q_INVOKABLE void reconcileNow();
    Q_INVOKABLE void resetExtensionsRuntime();
    Q_INVOKABLE void fetchDesiredBlueprints(const QString &applied = QString());
    Q_INVOKABLE void clearDesiredBlueprints(const QString &applied = QString());
    Q_INVOKABLE void fetchExtensionStatusSummary();
    Q_INVOKABLE void fetchExtensionControlSurface(const QString &extensionId);
    Q_INVOKABLE void updateExtensionControlSurfaceSettings(const QString &extensionId, const QVariantMap &values);
    Q_INVOKABLE void invokeExtensionControlAction(
        const QString &extensionId,
        const QString &actionId,
        const QVariantMap &params = QVariantMap());
    Q_INVOKABLE void fetchAutoWireStatus();
    Q_INVOKABLE void setAutoWireEnabled(bool enabled);
    Q_INVOKABLE void fetchAutoWirePlan();
    Q_INVOKABLE void fetchDownloaderProfile();
    Q_INVOKABLE void updateDownloaderProfile(const QString &profile);
    Q_INVOKABLE void findMedia(
        const QString &query,
        const QString &mediaType,
        const QVariantList &providerIds = QVariantList());
    Q_INVOKABLE void addMediaToManager(
        const QString &mediaType,
        const QVariantMap &item,
        const QString &managerProviderId = QString(),
        const QVariantMap &options = QVariantMap());
    Q_INVOKABLE void fetchManagerPreferences();
    Q_INVOKABLE void updateManagerPreferences(
        const QString &movieProviderId,
        const QString &seriesProviderId,
        const QString &animeProviderId);
    Q_INVOKABLE void fetchMediaAcquisition(int limit = 12);
    Q_INVOKABLE void findAnotherRelease(const QString &intentId);

signals:
    void baseUrlChanged();
    void authTokenChanged();
    void accessTokenExpiresAtChanged();
    void clientCapabilitiesChanged();
    void networkTypeChanged();
    void extensionsCatalogChanged();
    void extensionsInstancesChanged();
    void extensionsSecretsChanged();
    void extensionsPlanChanged();
    void extensionsRunChanged();
    void extensionsRunsChanged();
    void extensionsReconcileRunChanged();
    void extensionsDesiredBlueprintsChanged();
    void extensionsStatusSummaryChanged();
    void extensionControlSurfaceChanged();
    void extensionControlLoadingChanged();
    void extensionsLastRefreshedAtChanged();
    void extensionsLastRefreshSuccessAtChanged();
    void extensionsLastRefreshErrorChanged();
    void extensionsAutoWireStatusChanged();
    void extensionsDownloaderSettingsChanged();
    void mediaFindResultChanged();
    void mediaFindLoadingChanged();
    void mediaManagerPreferencesChanged();
    void mediaAddResultChanged();
    void mediaAddLoadingChanged();
    void mediaAcquisitionChanged();
    void extensionsRuntimeResetCompleted(const QString &status, const QString &message);
    void extensionControlActionCompleted(
        const QString &extensionId,
        const QString &actionId,
        const QString &message);
    void secretRotated(const QString &secretId, const QString &value);
    void desiredBlueprintsCleared(int deleted);
    void runsCleared(int deleted);

    void loginSucceeded();
    void loginFailed(const QString &error);
    void authExpired(const QString &message);
    void passwordResetStarted(const QString &token, const QString &expiresAt);
    void passwordResetCompleted();
    void passwordResetFailed(const QString &error);
    void libraryReceived(const QVariantList &items);
    void mediaDetailsReceived(const QVariantMap &details);
    void mediaItemDeleted(const QString &mediaItemId, const QVariantMap &result);
    void episodeDeleted(const QString &episodeId, const QVariantMap &result);
    void episodeRestored(const QString &episodeId, const QVariantMap &result);
    void blockedEpisodesRestored(const QString &mediaItemId, const QVariantMap &result);
    void seasonsReceived(const QString &seriesId, const QVariantList &seasons);
    void seasonDetailReceived(const QString &seasonId, const QVariantMap &detail);
    void episodesReceived(const QString &seasonId, const QVariantList &episodes);
    void playbackStarted(const QVariantMap &info);
    void sessionPolled(const QVariantMap &info);
    void seekCompleted(const QString &sessionId, double positionSeconds);
    void seekFailed(const QString &sessionId, const QString &error);
    void scanCompleted();
    void reviewQueueReceived(const QVariantList &items);
    void reviewDetailReceived(const QVariantMap &detail);
    void reviewApplied(const QString &reviewId);
    void requestFailed(const QString &endpoint, const QString &error);

private:
    using SuccessHandler = std::function<void(const QJsonDocument &)>;
    using ErrorHandler = std::function<void(const QString &)>;

    QString normalizeBaseUrl(const QString &value) const;
    QUrl makeUrl(const QString &path) const;
    void updateExtensionsCatalog(const QJsonObject &obj);
    void updateExtensionsPlan(const QJsonObject &obj);
    void updateExtensionsRun(const QJsonObject &obj);
    void updateExtensionStatusSummary(const QJsonObject &obj);
    void updateExtensionControlSurfaceState(const QJsonObject &obj);
    void updateDownloaderProfileState(const QJsonObject &obj);
    void updateMediaAcquisitionState(const QJsonObject &obj);
    void sendRequest(
        const QString &method,
        const QString &path,
        const QJsonObject &body,
        const SuccessHandler &onSuccess,
        const ErrorHandler &onError = ErrorHandler(),
        bool allowNonJson = false);

    QNetworkAccessManager m_manager;
    QString m_baseUrl;
    QString m_authToken;
    QString m_accessTokenExpiresAt;
    QVariantMap m_clientCapabilities;
    QString m_networkType;
    QVariantList m_extensionsInstalled;
    QVariantList m_extensionsAvailable;
    QVariantList m_extensionsCore;
    QVariantList m_extensionsInstances;
    QVariantList m_extensionsSecrets;
    QVariantMap m_extensionsPlan;
    QVariantList m_extensionsPlanConflicts;
    QString m_extensionsPlanId;
    QVariantMap m_extensionsRun;
    QVariantList m_extensionsRunSteps;
    QString m_extensionsRunId;
    QVariantList m_extensionsRuns;
    QVariantMap m_extensionsReconcileRun;
    QVariantList m_extensionsDesiredBlueprints;
    QVariantList m_extensionsStatusItems;
    int m_extensionsNeedsAttentionCount = 0;
    QVariantMap m_extensionsRuntimeStatus;
    QVariantMap m_extensionControlSurface;
    bool m_extensionControlLoading = false;
    QString m_extensionsLastRefreshedAt;
    QString m_extensionsLastRefreshSuccessAt;
    QString m_extensionsLastRefreshError;
    bool m_extensionsAutoWireEnabled = true;
    QString m_extensionsAutoWirePendingPlanId;
    QString m_extensionsAutoWirePendingReason;
    int m_extensionsAutoWirePendingConflicts = 0;
    QString m_extensionsDownloaderProfile;
    QString m_extensionsDownloaderDefaultProfile;
    QString m_extensionsDownloaderProfileSource;
    QString m_extensionsDownloaderProfileUpdatedAt;
    int m_extensionsDownloaderPendingUpdateCount = 0;
    QVariantList m_extensionsDownloaderProfileOptions;
    QVariantList m_extensionsDownloaderTelemetry;
    QVariantMap m_mediaFindResult;
    bool m_mediaFindLoading = false;
    quint64 m_mediaFindRequestId = 0;
    QVariantMap m_mediaManagerPreferences;
    QVariantMap m_mediaAddResult;
    bool m_mediaAddLoading = false;
    QVariantMap m_mediaAcquisitionStatus;
    QVariantList m_mediaAcquisitionItems;
    int m_mediaAcquisitionActiveCount = 0;
    int m_mediaAcquisitionDownloadingCount = 0;
    int m_mediaAcquisitionNeedsAttentionCount = 0;
};
