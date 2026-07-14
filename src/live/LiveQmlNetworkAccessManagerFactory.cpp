#include "LiveQmlNetworkAccessManagerFactory.h"

#include "backend/ApiClient.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QUrl>

namespace {

int effectivePort(const QUrl &url) {
  if (url.port() >= 0) {
    return url.port();
  }
  return url.scheme().compare(QStringLiteral("https"), Qt::CaseInsensitive) == 0
             ? 443
             : 80;
}

bool isLiveArtworkRequest(const QUrl &url, const ApiClient *authClient) {
  if (!authClient || authClient->authToken().isEmpty()) {
    return false;
  }
  return LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
      url, QUrl(authClient->baseUrl()));
}

class LiveQmlNetworkAccessManager final : public QNetworkAccessManager {
public:
  LiveQmlNetworkAccessManager(ApiClient *authClient, QObject *parent)
      : QNetworkAccessManager(parent), m_authClient(authClient) {}

protected:
  QNetworkReply *createRequest(Operation operation,
                               const QNetworkRequest &original,
                               QIODevice *outgoingData) override {
    QNetworkRequest request(original);
    if (operation == GetOperation &&
        isLiveArtworkRequest(request.url(), m_authClient)) {
      request.setRawHeader("Authorization",
                           QByteArrayLiteral("Bearer ") +
                               m_authClient->authToken().toUtf8());
      request.setRawHeader("Accept",
                           "image/avif,image/webp,image/png,image/jpeg");
      request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                           QNetworkRequest::ManualRedirectPolicy);
      request.setTransferTimeout(15'000);
    }
    return QNetworkAccessManager::createRequest(operation, request,
                                                outgoingData);
  }

private:
  ApiClient *m_authClient{nullptr};
};

} // namespace

LiveQmlNetworkAccessManagerFactory::LiveQmlNetworkAccessManagerFactory(
    ApiClient *authClient)
    : m_authClient(authClient) {}

bool LiveQmlNetworkAccessManagerFactory::isSameOriginArtwork(
    const QUrl &url, const QUrl &baseUrl) {
  static const QString prefix = QStringLiteral("/api/v1/live/artwork/");
  return url.isValid() && baseUrl.isValid() && url.userInfo().isEmpty() &&
         !url.hasQuery() && url.fragment().isEmpty() &&
         url.path().startsWith(prefix) && url.path().size() > prefix.size() &&
         url.scheme().compare(baseUrl.scheme(), Qt::CaseInsensitive) == 0 &&
         url.host().compare(baseUrl.host(), Qt::CaseInsensitive) == 0 &&
         effectivePort(url) == effectivePort(baseUrl);
}

QNetworkAccessManager *
LiveQmlNetworkAccessManagerFactory::create(QObject *parent) {
  return new LiveQmlNetworkAccessManager(m_authClient, parent);
}
