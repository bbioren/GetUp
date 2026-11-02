import Foundation
import WatchKit

/// Schedules a watchOS "smart alarm" extended runtime session. When it fires,
/// the watch buzzes every couple of seconds and does not stop until the
/// wake-up challenge is completed.
@MainActor
final class AlarmManager: NSObject, ObservableObject {
    static let shared = AlarmManager()

    @Published var alarmTime: Date { didSet { save() } }
    @Published var challenge: ChallengeKind { didSet { save() } }
    @Published var target: Int { didSet { save() } }

    @Published private(set) var scheduledFor: Date?
    @Published private(set) var isRinging = false
    @Published private(set) var lastError: String?

    let tracker = ChallengeTracker()
    private var session: WKExtendedRuntimeSession?

    var isArmed: Bool { scheduledFor != nil }

    override init() {
        let d = UserDefaults.standard
        alarmTime = d.object(forKey: "alarmTime") as? Date
            ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        challenge = ChallengeKind(rawValue: d.string(forKey: "challenge") ?? "") ?? .steps
        target = d.object(forKey: "target") as? Int ?? 50
        super.init()
    }

    // MARK: - Scheduling

    func arm() { schedule(at: nextFireDate()) }

    func disarm() {
        guard !isRinging else { return }  // no cheating once it is going off
        session?.invalidate()
        session = nil
        scheduledFor = nil
    }

    private func schedule(at date: Date) {
        session?.invalidate()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: date)
        session = s
        scheduledFor = date
        lastError = nil
    }

    private func nextFireDate() -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: alarmTime)
        return cal.nextDate(after: .now, matching: hm, matchingPolicy: .nextTime)!
    }

    // MARK: - Ringing

    fileprivate func startRinging(_ s: WKExtendedRuntimeSession) {
        guard s === session else { return }
        if !isRinging {
            isRinging = true
            tracker.start(kind: challenge, target: target) { [weak self] in
                Task { @MainActor in self?.challengeCompleted() }
            }
        }
        // Repeats until the session is invalidated (or hits the ~30 min system cap).
        s.notifyUser(hapticType: .notification) { haptic in
            haptic.pointee = .notification
            return 2.0
        }
    }

    /// Emergency stop (long-press on the ringing screen), e.g. if you're sick.
    func forceStop() {
        tracker.stop()
        challengeCompleted()
    }

    private func challengeCompleted() {
        isRinging = false
        WKInterfaceDevice.current().play(.success)
        session?.invalidate()
        session = nil
        arm()  // re-arm for tomorrow
    }

    fileprivate func sessionEnded(_ s: WKExtendedRuntimeSession,
                                  reason: WKExtendedRuntimeSessionInvalidationReason,
                                  error: Error?) {
        guard s === session else { return }  // an old session we already replaced
        session = nil
        scheduledFor = nil

        if let error { lastError = error.localizedDescription }

        // Still ringing but the system ended the session (30 min cap or
        // dismissed from the system alert): try to start another one right away.
        if isRinging {
            schedule(at: Date().addingTimeInterval(5))
        }
    }

    // MARK: - Persistence

    private func save() {
        let d = UserDefaults.standard
        d.set(alarmTime, forKey: "alarmTime")
        d.set(challenge.rawValue, forKey: "challenge")
        d.set(target, forKey: "target")
    }
}

extension AlarmManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        Task { @MainActor in self.startRinging(s) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ s: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        Task { @MainActor in self.sessionEnded(s, reason: reason, error: error) }
    }
}
