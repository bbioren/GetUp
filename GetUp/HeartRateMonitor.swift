import Foundation
import HealthKit

/// Live heart rate via a workout session. The watch only streams heart rate
/// to apps during a workout session; outside one you get a reading every few
/// minutes. The session is always discarded, so nothing is saved to Health.
/// Bonus: a running workout session keeps the app alive, so the alarm can keep
/// buzzing past the ~30 min smart-alarm limit.
final class HeartRateMonitor: NSObject {
    static let hrType = HKQuantityType(.heartRate)
    static let restingType = HKQuantityType(.restingHeartRate)
    private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    let store = HKHealthStore()
    var onBPM: ((Double) -> Void)?
    var onFailure: ((Error) -> Void)?

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var isRunning: Bool { session != nil }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: [Self.hrType, Self.restingType])
    }

    /// Your heart rate while asleep: median of the last 3 hours of readings,
    /// falling back to your latest resting heart rate, then to 60.
    func sleepingBaseline() async -> Double {
        let now = Date()
        let recent = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-3 * 3600), end: now)
        let q = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.hrType, predicate: recent)],
            sortDescriptors: [])
        if let samples = try? await q.result(for: store), !samples.isEmpty {
            let bpm = samples.map { $0.quantity.doubleValue(for: Self.bpmUnit) }.sorted()
            return bpm[bpm.count / 2]
        }
        let r = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.restingType)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        if let latest = try? await r.result(for: store).first {
            return latest.quantity.doubleValue(for: Self.bpmUnit)
        }
        return 60
    }

    func start() throws {
        guard session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .mixedCardio
        config.locationType = .indoor

        let s = try HKWorkoutSession(healthStore: store, configuration: config)
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        s.delegate = self
        b.delegate = self
        session = s
        builder = b

        let now = Date()
        s.startActivity(with: now)
        b.beginCollection(withStart: now) { _, _ in }
    }

    func stop() {
        guard let s = session, let b = builder else { return }
        session = nil
        builder = nil
        s.end()
        b.endCollection(withEnd: Date()) { _, _ in b.discardWorkout() }
    }
}

extension HeartRateMonitor: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        guard types.contains(Self.hrType),
              let q = b.statistics(for: Self.hrType)?.mostRecentQuantity() else { return }
        let bpm = q.doubleValue(for: Self.bpmUnit)
        DispatchQueue.main.async { self.onBPM?(bpm) }
    }

    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}

    func workoutSession(_ s: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            if self.session === s { self.session = nil; self.builder = nil }
            self.onFailure?(error)
        }
    }
}
