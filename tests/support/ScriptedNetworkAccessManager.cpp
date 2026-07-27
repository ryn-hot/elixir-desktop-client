#include "ScriptedNetworkAccessManager.h"

#include <QIODevice>
#include <QPointer>

#include <algorithm>
#include <cstring>
#include <utility>

ScriptedNetworkReply::ScriptedNetworkReply(
    const QNetworkRequest &request,
    QNetworkAccessManager::Operation operation,
    ScriptedHttpResponse response,
    DeterministicScheduler &scheduler,
    QObject *parent)
    : QNetworkReply(parent)
    , m_response(std::move(response)) {
    setRequest(request);
    setUrl(request.url());
    setOperation(operation);
    setAttribute(QNetworkRequest::HttpStatusCodeAttribute, m_response.statusCode);
    for (const auto &[name, value] : m_response.headers) {
        setRawHeader(name, value);
    }
    open(QIODevice::ReadOnly | QIODevice::Unbuffered);
    QPointer<ScriptedNetworkReply> guarded(this);
    scheduler.schedule(m_response.delayMs, [guarded]() {
        if (guarded) {
            guarded->complete();
        }
    });
}

void ScriptedNetworkReply::abort() {
    if (m_terminal) {
        return;
    }
    finishWithError(QNetworkReply::OperationCanceledError, QStringLiteral("scripted request cancelled"));
}

bool ScriptedNetworkReply::isSequential() const {
    return true;
}

qint64 ScriptedNetworkReply::bytesAvailable() const {
    return static_cast<qint64>(m_response.body.size() - m_offset) + QNetworkReply::bytesAvailable();
}

qint64 ScriptedNetworkReply::readData(char *data, qint64 maxLength) {
    if (maxLength <= 0 || m_offset >= m_response.body.size()) {
        return m_terminal ? -1 : 0;
    }
    const auto available = m_response.body.size() - m_offset;
    const auto count = std::min<qint64>(maxLength, available);
    std::memcpy(data, m_response.body.constData() + m_offset, static_cast<std::size_t>(count));
    m_offset += count;
    return count;
}

void ScriptedNetworkReply::complete() {
    if (m_terminal) {
        return;
    }
    if (m_response.networkError != QNetworkReply::NoError) {
        finishWithError(
            m_response.networkError,
            m_response.errorString.isEmpty() ? QStringLiteral("scripted network error")
                                             : m_response.errorString);
        return;
    }
    m_terminal = true;
    setFinished(true);
    emit metaDataChanged();
    if (!m_response.body.isEmpty()) {
        emit readyRead();
    }
    emit finished();
}

void ScriptedNetworkReply::finishWithError(
    QNetworkReply::NetworkError code,
    const QString &message) {
    if (m_terminal) {
        return;
    }
    m_terminal = true;
    m_response.body.clear();
    m_offset = 0;
    setError(code, message);
    setFinished(true);
    emit errorOccurred(code);
    emit finished();
}

ScriptedNetworkAccessManager::ScriptedNetworkAccessManager(
    DeterministicScheduler &scheduler,
    QObject *parent)
    : QNetworkAccessManager(parent)
    , m_scheduler(scheduler) {}

void ScriptedNetworkAccessManager::enqueue(ScriptedHttpResponse response) {
    m_responses.push_back(std::move(response));
}

const QList<CapturedNetworkRequest> &ScriptedNetworkAccessManager::capturedRequests() const noexcept {
    return m_requests;
}

std::size_t ScriptedNetworkAccessManager::pendingResponseCount() const noexcept {
    return m_responses.size();
}

QNetworkReply *ScriptedNetworkAccessManager::createRequest(
    Operation operation,
    const QNetworkRequest &request,
    QIODevice *outgoingData) {
    CapturedNetworkRequest captured;
    captured.operation = operation;
    captured.url = request.url();
    captured.transferTimeoutMs = request.transferTimeout();
    for (const auto &name : request.rawHeaderList()) {
        captured.headers.append({name, request.rawHeader(name)});
    }
    if (outgoingData) {
        captured.body = outgoingData->readAll();
    }
    m_requests.append(std::move(captured));

    ScriptedHttpResponse response;
    if (m_responses.empty()) {
        response.statusCode = 0;
        response.networkError = QNetworkReply::ProtocolUnknownError;
        response.errorString = QStringLiteral("no scripted response is available");
    } else {
        response = std::move(m_responses.front());
        m_responses.pop_front();
    }
    return new ScriptedNetworkReply(request, operation, std::move(response), m_scheduler, this);
}
