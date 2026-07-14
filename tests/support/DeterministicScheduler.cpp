#include "DeterministicScheduler.h"

#include <algorithm>
#include <limits>
#include <stdexcept>
#include <utility>

std::int64_t DeterministicScheduler::nowMs() const noexcept {
    return m_nowMs;
}

std::size_t DeterministicScheduler::pendingCount() const noexcept {
    return static_cast<std::size_t>(std::count_if(
        m_events.cbegin(), m_events.cend(), [](const Event &event) { return !event.cancelled; }));
}

DeterministicScheduler::EventId DeterministicScheduler::schedule(
    std::int64_t delayMs,
    std::function<void()> callback) {
    if (delayMs < 0 || !callback) {
        throw std::invalid_argument("deterministic event must have a nonnegative delay and callback");
    }
    if (delayMs > std::numeric_limits<std::int64_t>::max() - m_nowMs) {
        throw std::overflow_error("deterministic event deadline overflow");
    }
    if (m_nextOrder == std::numeric_limits<std::uint64_t>::max()) {
        throw std::overflow_error("deterministic event ordering exhausted");
    }
    const auto id = m_nextId++;
    if (id == 0 || m_nextId == 0) {
        throw std::overflow_error("deterministic event identifier exhausted");
    }
    const auto order = m_nextOrder++;
    m_events.push_back(Event{id, m_nowMs + delayMs, order, std::move(callback), false});
    return id;
}

bool DeterministicScheduler::cancel(EventId eventId) noexcept {
    const auto event = std::find_if(m_events.begin(), m_events.end(), [eventId](const Event &value) {
        return value.id == eventId && !value.cancelled;
    });
    if (event == m_events.end()) {
        return false;
    }
    event->cancelled = true;
    event->callback = {};
    return true;
}

void DeterministicScheduler::advance(std::int64_t elapsedMs) {
    if (elapsedMs < 0) {
        throw std::invalid_argument("deterministic time cannot move backward");
    }
    if (elapsedMs > std::numeric_limits<std::int64_t>::max() - m_nowMs) {
        throw std::overflow_error("deterministic clock overflow");
    }
    m_nowMs += elapsedMs;
    runDue();
}

void DeterministicScheduler::runDue() {
    while (true) {
        const auto next = std::min_element(
            m_events.begin(), m_events.end(), [](const Event &left, const Event &right) {
                if (left.cancelled != right.cancelled) {
                    return !left.cancelled;
                }
                if (left.dueMs != right.dueMs) {
                    return left.dueMs < right.dueMs;
                }
                return left.order < right.order;
            });
        if (next == m_events.end() || next->cancelled || next->dueMs > m_nowMs) {
            break;
        }
        auto callback = std::move(next->callback);
        m_events.erase(next);
        callback();
    }
    m_events.erase(
        std::remove_if(m_events.begin(), m_events.end(), [](const Event &event) {
            return event.cancelled;
        }),
        m_events.end());
}
