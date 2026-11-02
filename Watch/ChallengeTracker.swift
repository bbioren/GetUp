import Foundation
import CoreMotion

enum ChallengeKind: String, CaseIterable, Identifiable {
    case heartRate
    case steps
    case jumpingJacks

    var id: String { rawValue }
    var label: String {
        switch self {
        case .heartRate: "Heart rate"
        case .steps: "Steps"
        case .jumpingJacks: "Jumping jacks"
        }
    }
    var unit: String {
        switch self {
        case .heartRate: "bpm"
        case .steps: "steps"
        case .jumpingJacks: "jacks"
        }
    }
}

/// Runs the wake-up challenge and calls `onDone` once it is beaten.
/// - heartRate: get above (sleeping HR + boost) and hold it for `holdSeconds`
/// - steps: CMPedometer step count
/// - jumpingJacks: accelerometer peak counting
final class ChallengeTracker: ObservableObject {
    @Published private(set) var kind: ChallengeKind = .heartRate
    @Published private(set) var progress = 0.0          // 0...1 for the progress bar

    // steps / jumping jacks
    @Published private(set) var count = 0
    @Published private(set) var target = 0

    // heart rate
    @Published private(set) var bpm: Double?
    @Published private(set) var baselineBPM: Double?
    @Published private(set) var targetBPM: Double?
    @Published private(set) var heldSeconds = 0.0
    @Published private(set) var errorMessage: String?
    let holdSeconds = 30.0
    private let dipTolerance = 5.0   // once holding, a dip this small doesn't reset the timer
    private var aboveSince: Date?

    let heartRate = HeartRateMonitor()
    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    private var onDone: (() -> Void)?
    private var finished = false

    // Jumping-jack detector. Tune if reps are missed / double counted.
    private let peakThreshold = 1.3
    private let resetThreshold = 0.35
    private let minRepInterval = 0.45
    private var armedForRep = true
    private var lastRep = Date.distantPast

    func start(kind: ChallengeKind, target: Int, hrBoost: Double, onDone: @escaping () -> Void) {
        stop()
        self.kind = kind
        self.target = target
        self.onDone = onDone
        count = 0; progress = 0; heldSeconds = 0; aboveSince = nil
        bpm = nil; targetBPM = nil; errorMessage = nil
        finished = false

        // Always run the workout session while ringing: it keeps the app alive
        // (so the alarm can't time out) and feeds live heart rate.
        startHeartRate(boost: hrBoost)

        switch kind {
        case .heartRate: break
        case .steps where CMPedometer.isStepCountingAvailable(): startSteps()
        default: self.kind = .jumpingJacks; startJacks()
        }
    }

    /// Restart the workout session if it wasn't allowed to start in the background.
    func ensureHeartRateRunning(boost: Double) {
        guard onDone != nil, !heartRate.isRunning else { return }
        startHeartRate(boost: boost)
    }

    func stop() {
        heartRate.stop()
        heartRate.onBPM = nil
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
        onDone = nil
    }

    /// Steps taken since `date` (used by the stay-up check).
    func steps(since date: Date, completion: @escaping (Int) -> Void) {
        guard CMPedometer.isStepCountingAvailable() else { return completion(0) }
        pedometer.queryPedometerData(from: date, to: Date()) { data, _ in
            let n = data?.numberOfSteps.intValue ?? 0
            DispatchQueue.main.async { completion(n) }
        }
    }

    // MARK: - Heart rate

    private func startHeartRate(boost: Double) {
        heartRate.onBPM = { [weak self] in self?.handleBPM($0) }
        heartRate.onFailure = { [weak self] in self?.heartRateFailed($0) }
        do {
            try heartRate.start()
        } catch {
            heartRateFailed(error)
        }
        if targetBPM == nil {
            Task { @MainActor in
                let base = await heartRate.sleepingBaseline()
                self.baselineBPM = base
                self.targetBPM = (base + boost).rounded()
            }
        }
    }

    private func heartRateFailed(_ error: Error) {
        guard kind == .heartRate, !finished else { return }
        errorMessage = "No heart rate (\(error.localizedDescription)). Switched to steps."
        kind = .steps
        target = 50
        startSteps()
    }

    private func handleBPM(_ value: Double) {
        bpm = value
        guard kind == .heartRate, !finished, let goal = targetBPM else { return }
        let holding = aboveSince != nil
        if value >= goal || (holding && value >= goal - dipTolerance) {
            if aboveSince == nil { aboveSince = Date() }
            heldSeconds = Date().timeIntervalSince(aboveSince!)
        } else {
            aboveSince = nil
            heldSeconds = 0
        }
        progress = min(heldSeconds / holdSeconds, 1)
        if heldSeconds >= holdSeconds { finish() }
    }

    // MARK: - Steps / jumping jacks

    private func startSteps() {
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.reportCount(steps) }
        }
    }

    private func startJacks() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.userAcceleration else { return }
            let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if self.armedForRep, mag > self.peakThreshold,
               Date().timeIntervalSince(self.lastRep) > self.minRepInterval {
                self.armedForRep = false
                self.lastRep = Date()
                self.reportCount(self.count + 1)
            } else if mag < self.resetThreshold {
                self.armedForRep = true
            }
        }
    }

    private func reportCount(_ n: Int) {
        guard !finished, kind != .heartRate else { return }
        count = min(n, target)
        progress = target > 0 ? Double(count) / Double(target) : 1
        if n >= target { finish() }
    }

    private func finish() {
        finished = true
        let done = onDone
        stop()
        done?()
    }
}
