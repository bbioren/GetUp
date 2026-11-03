import Foundation
import AlarmKit
import CoreMotion
import SwiftUI

struct GetUpAlarmData: AlarmMetadata {}

/// One "ring until you walk" challenge: a chain of system alarms every
/// `ringSpacing` seconds starting at `firesAt`. Pressing Stop on one alarm only
/// buys you until the next; the whole chain is cancelled once you've walked
/// `target` steps since `countFrom`.
struct PendingChallenge: Codable, Equatable {
    enum Kind: String, Codable { case wake, stayUp }
    var kind: Kind
    var firesAt: Date
    var countFrom: Date
    var target: Int
    var alarmIDs: [UUID]
}

@MainActor
final class WakeController: ObservableObject {
    static let shared = WakeController()

    // Settings
    @Published var wakeTime: Date { didSet { saveSettings() } }
    @Published var stepTarget: Int { didSet { saveSettings() } }
    @Published var stayUpEnabled: Bool { didSet { saveSettings() } }
    @Published var stayUpMinutes: Int { didSet { saveSettings() } }
    @Published var stayUpSteps: Int { didSet { saveSettings() } }

    // State
    @Published private(set) var pending: PendingChallenge? { didSet { savePending() } }
    @Published private(set) var steps = 0
    @Published var errorMessage: String?

    private let ringCount = 40              // 40 alarms x 90 s = 1 hour of ringing
    private let ringSpacing: TimeInterval = 90
    private let pedometer = CMPedometer()
    private var counting = false
    private var completing = false

    init() {
        let d = UserDefaults.standard
        wakeTime = d.object(forKey: "wakeTime") as? Date
            ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        stepTarget = d.object(forKey: "stepTarget") as? Int ?? 50
        stayUpEnabled = d.object(forKey: "stayUpEnabled") as? Bool ?? true
        stayUpMinutes = d.object(forKey: "stayUpMinutes") as? Int ?? 10
        stayUpSteps = d.object(forKey: "stayUpSteps") as? Int ?? 100
        if let data = d.data(forKey: "pending") {
            pending = try? JSONDecoder().decode(PendingChallenge.self, from: data)
        }
    }

    /// True once the alarm time has passed (or for a stay-up check, right away).
    var isChallengeActive: Bool {
        guard let p = pending else { return false }
        return p.kind == .stayUp || Date() >= p.firesAt
    }

    var canDisarm: Bool { pending?.kind == .wake && !isChallengeActive }

    // MARK: - Arming

    func arm() async {
        let date = nextWakeDate()
        await schedule(kind: .wake, firesAt: date, countFrom: date, target: stepTarget)
    }

    func disarm() async {
        guard canDisarm else { return }
        await cancelPending()
    }

    /// Emergency stop (10 s long-press), e.g. if you're sick. Re-arms for tomorrow.
    func forceStop() async {
        await cancelPending()
        await arm()
    }

    private func schedule(kind: PendingChallenge.Kind, firesAt: Date, countFrom: Date, target: Int) async {
        await cancelPending()
        errorMessage = nil
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            guard state == .authorized else {
                errorMessage = "Alarms are off for GetUp. Turn them on in Settings → Apps → GetUp."
                return
            }
            var ids: [UUID] = []
            for i in 0..<ringCount {
                let id = UUID()
                let at = firesAt.addingTimeInterval(Double(i) * ringSpacing)
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration(at: at, kind: kind))
                ids.append(id)
            }
            pending = PendingChallenge(kind: kind, firesAt: firesAt, countFrom: countFrom,
                                       target: target, alarmIDs: ids)
        } catch {
            errorMessage = "Couldn't set alarm: \(error.localizedDescription)"
        }
    }

    private func configuration(at date: Date, kind: PendingChallenge.Kind)
        -> AlarmManager.AlarmConfiguration<GetUpAlarmData> {
        let title: LocalizedStringResource = kind == .wake ? "GET UP. Walk to turn this off." : "Still up? Walk to turn this off."
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
            secondaryButton: AlarmButton(text: "Open GetUp", textColor: .white, systemImageName: "figure.walk"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: GetUpAlarmData(),
                                         tintColor: .orange)
        return .alarm(schedule: .fixed(date), attributes: attributes,
                      secondaryIntent: OpenGetUpIntent(), sound: .default)
    }

    private func cancelPending() async {
        stopCounting()
        guard let p = pending else { return }
        for id in p.alarmIDs {
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
        }
        pending = nil
    }

    private func nextWakeDate() -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: wakeTime)
        return cal.nextDate(after: .now, matching: hm, matchingPolicy: .nextTime)!
    }

    // MARK: - Step counting

    /// Called every few seconds by the UI; starts counting once the challenge is live.
    func tick() {
        if isChallengeActive && !counting { startCounting() }
        objectWillChange.send()
    }

    private func startCounting() {
        guard let p = pending, CMPedometer.isStepCountingAvailable() else {
            errorMessage = "Step counting isn't available. Allow Motion & Fitness for GetUp in Settings."
            return
        }
        counting = true
        steps = 0
        // Delivers cumulative steps since countFrom, including ones already taken.
        pedometer.startUpdates(from: p.countFrom) { [weak self] data, _ in
            let n = data?.numberOfSteps.intValue ?? 0
            Task { @MainActor in self?.handleSteps(n) }
        }
    }

    private func stopCounting() {
        pedometer.stopUpdates()
        counting = false
        steps = 0
    }

    private func handleSteps(_ n: Int) {
        steps = n
        guard let p = pending, isChallengeActive, n >= p.target, !completing else { return }
        completing = true
        Task {
            await complete(p)
            completing = false
        }
    }

    private func complete(_ p: PendingChallenge) async {
        await cancelPending()
        if p.kind == .wake && stayUpEnabled {
            let now = Date()
            await schedule(kind: .stayUp,
                           firesAt: now.addingTimeInterval(Double(stayUpMinutes) * 60),
                           countFrom: now, target: stayUpSteps)
        } else {
            await arm()   // done for today; set tomorrow's alarm
        }
    }

    // MARK: - Persistence

    private func saveSettings() {
        let d = UserDefaults.standard
        d.set(wakeTime, forKey: "wakeTime")
        d.set(stepTarget, forKey: "stepTarget")
        d.set(stayUpEnabled, forKey: "stayUpEnabled")
        d.set(stayUpMinutes, forKey: "stayUpMinutes")
        d.set(stayUpSteps, forKey: "stayUpSteps")
    }

    private func savePending() {
        let d = UserDefaults.standard
        if let p = pending, let data = try? JSONEncoder().encode(p) {
            d.set(data, forKey: "pending")
        } else {
            d.removeObject(forKey: "pending")
        }
    }
}
