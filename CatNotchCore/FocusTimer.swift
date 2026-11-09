import Foundation

/// One focus session's countdown. It has no clock of its own: every call is given `now`, so it is
/// tested without waiting and survives the app being busy.
public struct FocusTimer: Equatable, Sendable {
    public enum Phase: Sendable {
        case idle, running, paused, finished

        /// What the tile and Settings call the session in this phase.
        public var title: String {
            switch self {
            case .idle: "Focus"
            case .running: "Focusing"
            case .paused: "Paused"
            case .finished: "Done"
            }
        }

        /// What the one control does in this phase.
        public var action: String {
            switch self {
            case .idle: "Start"
            case .running: "Pause"
            case .paused: "Resume"
            case .finished: "Again"
            }
        }
    }

    public private(set) var phase = Phase.idle
    /// The full length of the current session in seconds, so progress can be drawn.
    public private(set) var duration: TimeInterval = 0
    private var deadline = Date.distantPast // while running
    private var left: TimeInterval = 0      // while paused

    public init() {}

    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle, .finished: 0
        case .running: max(0, deadline.timeIntervalSince(now))
        case .paused: left
        }
    }

    /// How much of the session has passed, 0 to 1.
    public func progress(at now: Date) -> Double {
        switch phase {
        case .idle: 0
        case .finished: 1
        case .running, .paused: duration > 0 ? 1 - remaining(at: now) / duration : 0
        }
    }

    /// Begins a new session, whatever came before. An empty length does nothing.
    public mutating func start(minutes: Double, at now: Date) {
        let seconds = FocusLength.seconds(minutes)
        guard seconds > 0 else { return }
        duration = TimeInterval(seconds)
        deadline = now.addingTimeInterval(duration)
        phase = .running
    }

    public mutating func pause(at now: Date) {
        guard phase == .running else { return }
        left = remaining(at: now)
        phase = .paused
    }

    public mutating func resume(at now: Date) {
        guard phase == .paused else { return }
        deadline = now.addingTimeInterval(left)
        phase = .running
    }

    /// The one control: start, pause or resume, by phase. A session already past its time finishes first,
    /// so a late Pause cannot freeze it at 0:00. Returns the finished session to log, if there was one.
    public mutating func toggle(minutes: Double, at now: Date) -> FocusSession? {
        if let done = tick(at: now) { return done }
        switch phase {
        case .running: pause(at: now)
        case .paused: resume(at: now)
        case .idle, .finished: start(minutes: minutes, at: now)
        }
        return nil
    }

    public mutating func reset() {
        self = FocusTimer()
    }

    /// Finishes the session if its time is up. Returns the session to log, once, on that edge.
    public mutating func tick(at now: Date) -> FocusSession? {
        guard phase == .running, now >= deadline else { return nil }
        phase = .finished
        // Logged when it ran out, not when the app noticed (after a sleep that could be another day).
        return FocusSession(at: deadline.timeIntervalSince1970 * 1000, minutes: (duration / 60).rounded())
    }
}

/// The session lengths on offer, in minutes, and how they read. Fractions are legal (1.5 is 1:30).
public enum FocusLength {
    public static let all: [Double] = [1, 2, 5, 10, 15, 20, 25, 30, 45, 60]

    public static func seconds(_ minutes: Double) -> Int { Int((minutes * 60).rounded()) }

    /// "25:00".
    public static func format(_ minutes: Double) -> String { clock(seconds: Double(seconds(minutes))) }

    /// Time left as "m:ss", rounded up so a running session never shows 0:00.
    public static func clock(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// The lengths for a picker, plus a saved length that is not one of them (an imported custom one).
    public static func options(including minutes: Double) -> [Double] {
        all.contains(minutes) ? all : (all + [minutes]).sorted()
    }
}

extension StoreData {
    /// The session length, saved under the Electron key `focusMinutes`. Unset or unusable means 25.
    public var focusMinutes: Double {
        get {
            if case .number(let m)? = settings["focusMinutes"], m > 0, m <= 24 * 60 { m } else { 25 } // a day at most, so an odd import cannot overflow
        }
        set { settings["focusMinutes"] = .number(newValue) }
    }

    /// Sessions that ended today and their minutes.
    public func focusToday(now: Date = Date(), calendar: Calendar = .current) -> (sessions: Int, minutes: Double) {
        let today = focusLog.filter { calendar.isDate(Date(timeIntervalSince1970: $0.at / 1000), inSameDayAs: now) }
        return (today.count, today.reduce(0) { $0 + $1.minutes })
    }
}

extension CatNotchStore {
    /// Sessions older than this are dropped; the log is for the recent past.
    static let keepDays = 90

    /// Adds a finished session to the log and saves it.
    public func logFocus(_ session: FocusSession, now: Date = Date()) {
        let cutoff = now.timeIntervalSince1970 * 1000 - Double(Self.keepDays) * 86_400_000
        update { $0.focusLog = $0.focusLog.filter { $0.at > cutoff } + [session] }
    }
}
