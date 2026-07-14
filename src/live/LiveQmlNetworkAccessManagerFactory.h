#pragma once

#include <QQmlNetworkAccessManagerFactory>
#include <QUrl>

class ApiClient;

class LiveQmlNetworkAccessManagerFactory final
    : public QQmlNetworkAccessManagerFactory {
public:
  explicit LiveQmlNetworkAccessManagerFactory(ApiClient *authClient);

  [[nodiscard]] QNetworkAccessManager *create(QObject *parent) override;
  [[nodiscard]] static bool isSameOriginArtwork(const QUrl &url,
                                                const QUrl &baseUrl);

private:
  ApiClient *m_authClient{nullptr};
};
