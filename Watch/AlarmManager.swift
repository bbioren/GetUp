import Foundation
import WatchKit

/// Schedules a watchOS "smart alarm" session. When it fires, the watch buzzes
/// until the wake challenge is beaten. Then a "stay-up check" fires N minutes
/// later: if you haven't walked enough since, it rings again.
@MainActor
final class AlarmManager: NSObject, ObservableObject {
    static let shared = AlarmManager()

    enum Purpose: String { case wake, stayUpCheck }

    // Settings
    @Published var alarmTime: Date { didSet { save() } }
    @Published var challenge: ChallengeKind { didSet { save() } }
    @Published var target: Int { didSet { save() } }            // steps / jacks
    @Published var hrBoost: Int { didSet { save() } }           // bpm above sleeping HR
    @Published var stayUpEnabled: Bool { didSet { save() } }
    @Published var stayUpMinutes: Int { didSet { save() } }
    @Published var stayUpSteps: Int { didSet { save() } }

    // State
    @Published private(set) var scheduledFor: Date?
    @Published private(set) var purpose: Purpose = .wake
    @Published private(set) var isRinging = false
    @Published private(set) var lastError: String?

    let tracker = ChallengeTracker()
    private var session: WKExtendedRuntimeSession?
    private var hapticTimer: Timer?
    private var completedAt: Date? {
        get { UserDefaults.standard.object(forKey: "completedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "completedAt") }
    }

    var isArmed: Bool { scheduledFor != nil }
    /// Disarming is blocked while ringing or while a stay-up check is pending.
    var canDisarm: Bool { !isRinging && purpose == .wake }

    override init() {
        let d = UserDefaults.standard
        alarmTime = d.object(forKey: "alarmTime") as? Date
            ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        challenge = ChallengeKind(rawValue: d.string(forKey: "challenge") ?? "") ?? .heartRate
        target = d.object(forKey: "target") as? Int ?? 50
        hrBoost = d.object(forKey: "hrBoost") as? Int ?? 30
        stayUpEnabled = d.object(forKey: "stayUpEnabled") as? Bool ?? true
        stayUpMinutes = d.object(forKey: "stayUpMinutes") as? Int ?? 10
        stayUpSteps = d.object(forKey: "stayUpSteps") as? Int ?? 100
        super.init()
    }

    // MARK: - Scheduling

    func arm() { schedule(at: nextFireDate(), purpose: .wake) }

    func disarm() {
        guard canDisarm else { return }
        session?.invalidate()
        session = nil
        scheduledFor = nil
    }

    private func schedule(at date: Date, purpose: Purpose) {
        session?.invalidate()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: date)
        session = s
        scheduledFor = date
        self.purpose = purpose
        lastError = nil
    }

    private func nextFireDate() -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: alarmTime)
        return cal.nextDate(after: .now, matching: hm, matchingPolicy: .nextTime)!
    }

    // MARK: - Firing

    fileprivate func sessionStarted(_ s: WKExtendedRuntimeSession) {
        guard s === session else { return }
        scheduledFor = nil

        if purpose == .stayUpCheck, !isRinging {
            let since = completedAt ?? Date().addingTimeInterval(-Double(stayUpMinutes) * 60)
            tracker.steps(since: since) { [weak self] steps in
                guard let self else { return }
                if steps >= self.stayUpSteps {
                    WKInterfaceDevice.current().play(.success)   // you're up, all done
                    self.session?.invalidate()
                    self.session = nil
                    self.arm()
                } else {
                    self.startRinging()
                }
            }
        } else {
            startRinging()
        }
    }

    private func startRinging() {
        if !isRinging {
            isRinging = true
            tracker.start(kind: challenge, target: target, hrBoost: Double(hrBoost)) { [weak self] in
                Task { @MainActor in self?.challengeCompleted() }
            }
        }
        // Smart-alarm haptics; repeat until the session is invalidated.
        session?.notifyUser(hapticType: .notification) { haptic in
            haptic.pointee = .notification
            return 2.0
        }
        // Backup buzzer for when the smart-alarm session has ended but the
        // workout session is keeping the app alive.
        hapticTimer?.invalidate()
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            Task { @MainActor in
                if AlarmManager.shared.session == nil {
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }
    }

    private func stopRinging() {
        isRinging = false
        hapticTimer?.invalidate()
        hapticTimer = nil
        tracker.stop()
        session?.invalidate()
        session = nil
    }

    private func challengeCompleted() {
        stopRinging()
        WKInterfaceDevice.current().play(.success)
        if stayUpEnabled {
            completedAt = Date()
            schedule(at: Date().addingTimeInterval(Double(stayUpMinutes) * 60), purpose: .stayUpCheck)
        } else {
            arm()
        }
    }

    /// Emergency stop (10 s long-press on the ringing screen), e.g. if you're sick.
    func forceStop() {
        stopRinging()
        arm()
    }

    /// Called when the app comes to the foreground.
    func appBecameActive() {
        if isRinging { tracker.ensureHeartRateRunning(boost: Double(hrBoost)) }
    }

    fileprivate func sessionEnded(_ s: WKExtendedRuntimeSession, error: Error?) {
        guard s === session else { return }   // an old session we already replaced
        session = nil
        if let error { lastError = error.localizedDescription }

        // The smart-alarm session ended (30 min cap / system alert dismissed)
        // while still ringing. If the workout session is keeping us alive the
        // backup buzzer carries on; otherwise start another alarm session.
        if isRinging, !tracker.heartRate.isRunning {
            schedule(at: Date().addingTimeInterval(5), purpose: purpose)
        } else if !isRinging {
            scheduledFor = nil
        }
    }

    // MARK: - Persistence

    private func save() {
        let d = UserDefaults.standard
        d.set(alarmTime, forKey: "alarmTime")
        d.set(challenge.rawValue, forKey: "challenge")
        d.set(target, forKey: "target")
        d.set(hrBoost, forKey: "hrBoost")
        d.set(stayUpEnabled, forKey: "stayUpEnabled")
        d.set(stayUpMinutes, forKey: "stayUpMinutes")
        d.set(stayUpSteps, forKey: "stayUpSteps")
    }
}

extension AlarmManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        Task { @MainActor in self.sessionStarted(s) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ s: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        Task { @MainActor in self.sessionEnded(s, error: error) }
    }
}
