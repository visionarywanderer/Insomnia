import Foundation

/// An active keep-awake session. `endsAt` is the only thing that keeps sleep
/// disabled; everything else is bookkeeping.
struct Session: Codable, Equatable, Sendable {
    var startedAt: Date
    var endsAt: Date
    /// Every extension applied, in order, in seconds.
    var extensions: [TimeInterval]
    /// Started by Auto mode: it ends when the agents are done, and `endsAt`
    /// is only its ceiling. Absent (nil) for a timed session and in files
    /// written before Auto existed.
    var auto: Bool?

    init(startedAt: Date, endsAt: Date, extensions: [TimeInterval] = [], auto: Bool? = nil) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.extensions = extensions
        self.auto = auto
    }

    var isAuto: Bool { auto == true }

    /// Seconds left until `endsAt`, never negative.
    func remaining(at now: Date) -> TimeInterval {
        SessionMath.remaining(until: endsAt, at: now)
    }

    /// True once `now` reaches `endsAt`.
    func isExpired(at now: Date) -> Bool {
        SessionMath.isExpired(endsAt: endsAt, at: now)
    }

    /// Shape of the menu bar countdown, derived from the session's span so it
    /// survives a relaunch without another persisted field. Because
    /// `remaining` never exceeds this span, the shape always has room for the
    /// value. An extension widens the span and can promote the shape, which
    /// is a one-off change at a user action, never a per-tick one.
    var countdownShape: CountdownShape {
        CountdownShape(initialDuration: endsAt.timeIntervalSince(startedAt))
    }
}
