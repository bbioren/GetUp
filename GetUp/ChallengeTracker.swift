import Foundation
import CoreMotion

enum ChallengeKind: String, CaseIterable, Identifiable {
    case steps
    case jumpingJacks

    var id: String { rawValue }
    var label: String { self == .steps ? "Steps" : "Jumping jacks" }
    var unit: String { self == .steps ? "steps" : "jacks" }
}

/// Counts steps (CMPedometer) or jumping jacks (accelerometer peaks) and
/// calls `onDone` once the target is reached.
final class ChallengeTracker: ObservableObject {
    @Published private(set) var progress = 0
    @Published private(set) var target = 0
    @Published private(set) var kind: ChallengeKind = .steps

    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    private var onDone: (() -> Void)?
    private var finished = false

    // Jumping-jack detector state. Tune these if reps are missed / double counted.
    private let peakThreshold = 1.3   // g of user acceleration that counts as the "up" swing
    private let resetThreshold = 0.35 // must drop below this before the next rep counts
    private let minRepInterval = 0.45 // seconds; nobody does jacks faster than this
    private var armedForRep = true
    private var lastRep = Date.distantPast

    func start(kind: ChallengeKind, target: Int, onDone: @escaping () -> Void) {
        stop()
        self.kind = kind
        self.target = target
        self.progress = 0
        self.finished = false
        self.onDone = onDone

        switch kind {
        case .steps where CMPedometer.isStepCountingAvailable():
            startSteps()
        default:
            self.kind = .jumpingJacks
            startJacks()
        }
    }

    func stop() {
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
        onDone = nil
    }

    private func startSteps() {
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.report(steps) }
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
                self.report(self.progress + 1)
            } else if mag < self.resetThreshold {
                self.armedForRep = true
            }
        }
    }

    private func report(_ count: Int) {
        guard !finished else { return }
        progress = min(count, target)
        if count >= target {
            finished = true
            let done = onDone
            stop()
            done?()
        }
    }
}
