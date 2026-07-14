#pragma once

#include <cstdint>
#include <functional>
#include <vector>

class DeterministicScheduler final {
public:
    using EventId = std::uint64_t;

    [[nodiscard]] std::int64_t nowMs() const noexcept;
    [[nodiscard]] std::size_t pendingCount() const noexcept;

    EventId schedule(std::int64_t delayMs, std::function<void()> callback);
    bool cancel(EventId eventId) noexcept;
    void advance(std::int64_t elapsedMs);
    void runDue();

private:
    struct Event {
        EventId id;
        std::int64_t dueMs;
        std::uint64_t order;
        std::function<void()> callback;
        bool cancelled;
    };

    std::int64_t m_nowMs{0};
    EventId m_nextId{1};
    std::uint64_t m_nextOrder{0};
    std::vector<Event> m_events;
};
