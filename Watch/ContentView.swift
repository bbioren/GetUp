import SwiftUI

struct RootView: View {
    @EnvironmentObject var alarm: AlarmManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if alarm.isRinging { RingingView() } else { SetupView() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { alarm.appBecameActive() }
        }
        .task { await alarm.tracker.heartRate.requestAuthorization() }
    }
}

struct SetupView: View {
    @EnvironmentObject var alarm: AlarmManager

    var body: some View {
        Form {
            DatePicker("Wake at", selection: $alarm.alarmTime, displayedComponents: .hourAndMinute)

            Picker("Challenge", selection: $alarm.challenge) {
                ForEach(ChallengeKind.allCases) { Text($0.label).tag($0) }
            }

            if alarm.challenge == .heartRate {
                Stepper(value: $alarm.hrBoost, in: 10...80, step: 5) {
                    Text("+\(alarm.hrBoost) bpm for 30s")
                }
            } else {
                Stepper(value: $alarm.target, in: 5...500, step: 5) {
                    Text("\(alarm.target) \(alarm.challenge.unit)")
                }
            }

            Section("Stay-up check") {
                Toggle("Enabled", isOn: $alarm.stayUpEnabled)
                if alarm.stayUpEnabled {
                    Stepper(value: $alarm.stayUpMinutes, in: 5...30, step: 5) {
                        Text("After \(alarm.stayUpMinutes) min")
                    }
                    Stepper(value: $alarm.stayUpSteps, in: 25...500, step: 25) {
                        Text("Need \(alarm.stayUpSteps) steps")
                    }
                }
            }

            Section {
                if let when = alarm.scheduledFor {
                    Text(alarm.purpose == .wake
                         ? "Rings \(when.formatted(date: .abbreviated, time: .shortened))"
                         : "Stay-up check at \(when.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.green)
                    if alarm.canDisarm {
                        Button("Disarm", role: .destructive) { alarm.disarm() }
                    }
                } else {
                    Button("Arm alarm") { alarm.arm() }.tint(.orange)
                }
                if let err = alarm.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("GetUp")
    }
}

struct RingingView: View {
    @EnvironmentObject var alarm: AlarmManager
    @EnvironmentObject var tracker: ChallengeTracker

    var body: some View {
        VStack(spacing: 6) {
            Text("GET UP").font(.title2.bold()).foregroundStyle(.orange)

            if tracker.kind == .heartRate {
                Text(tracker.bpm.map { "\(Int($0))" } ?? "--")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                Text(tracker.targetBPM.map { "goal \(Int($0)) bpm · \(Int(tracker.heldSeconds))/\(Int(tracker.holdSeconds))s" }
                     ?? "reading heart rate…")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("\(tracker.count)/\(tracker.target)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                Text(tracker.kind.unit).foregroundStyle(.secondary)
            }

            ProgressView(value: tracker.progress).tint(.orange)

            if let err = tracker.errorMessage {
                Text(err).font(.system(size: 10)).foregroundStyle(.red)
            }
            Text("Hold 10s for emergency stop")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .onLongPressGesture(minimumDuration: 10) { alarm.forceStop() }
    }
}
