#pragma once

#include "DeterministicScheduler.h"

#include <QByteArray>
#include <QList>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QString>
#include <QUrl>

#include <deque>

struct ScriptedHttpResponse {
    int statusCode{200};
    QList<QPair<QByteArray, QByteArray>> headers;
    QByteArray body;
    std::int64_t delayMs{0};
    QNetworkReply::NetworkError networkError{QNetworkReply::NoError};
    QString errorString;
};

struct CapturedNetworkRequest {
    QNetworkAccessManager::Operation operation{QNetworkAccessManager::GetOperation};
    QUrl url;
    QList<QPair<QByteArray, QByteArray>> headers;
    QByteArray body;
    int transferTimeoutMs{0};
};

class ScriptedNetworkReply final : public QNetworkReply {
    Q_OBJECT

public:
    ScriptedNetworkReply(
        const QNetworkRequest &request,
        QNetworkAccessManager::Operation operation,
        ScriptedHttpResponse response,
        DeterministicScheduler &scheduler,
        QObject *parent = nullptr);

    void abort() override;
    [[nodiscard]] bool isSequential() const override;
    [[nodiscard]] qint64 bytesAvailable() const override;

protected:
    qint64 readData(char *data, qint64 maxLength) override;

private:
    void complete();
    void finishWithError(QNetworkReply::NetworkError code, const QString &message);

    ScriptedHttpResponse m_response;
    qsizetype m_offset{0};
    bool m_terminal{false};
};

class ScriptedNetworkAccessManager final : public QNetworkAccessManager {
    Q_OBJECT

public:
    explicit ScriptedNetworkAccessManager(
        DeterministicScheduler &scheduler,
        QObject *parent = nullptr);

    void enqueue(ScriptedHttpResponse response);
    [[nodiscard]] const QList<CapturedNetworkRequest> &capturedRequests() const noexcept;
    [[nodiscard]] std::size_t pendingResponseCount() const noexcept;

protected:
    QNetworkReply *createRequest(
        Operation operation,
        const QNetworkRequest &request,
        QIODevice *outgoingData = nullptr) override;

private:
    DeterministicScheduler &m_scheduler;
    std::deque<ScriptedHttpResponse> m_responses;
    QList<CapturedNetworkRequest> m_requests;
};
