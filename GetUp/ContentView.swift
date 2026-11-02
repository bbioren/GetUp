import SwiftUI

struct RootView: View {
    @EnvironmentObject var alarm: AlarmManager

    var body: some View {
        if alarm.isRinging { RingingView() } else { SetupView() }
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

            Stepper(value: $alarm.target, in: 5...500, step: 5) {
                Text("\(alarm.target) \(alarm.challenge.unit)")
            }

            if let when = alarm.scheduledFor {
                Text("Rings \(when.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.green)
                Button("Disarm", role: .destructive) { alarm.disarm() }
            } else {
                Button("Arm alarm") { alarm.arm() }.tint(.orange)
            }

            if let err = alarm.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("GetUp")
    }
}

struct RingingView: View {
    @EnvironmentObject var alarm: AlarmManager
    @EnvironmentObject var tracker: ChallengeTracker

    var body: some View {
        VStack(spacing: 8) {
            Text("GET UP").font(.title2.bold()).foregroundStyle(.orange)
            Text("\(tracker.progress)/\(tracker.target)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
            Text(tracker.kind.unit).foregroundStyle(.secondary)
            ProgressView(value: Double(tracker.progress), total: Double(max(tracker.target, 1)))
                .tint(.orange)
            Text("Hold 10s for emergency stop")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding()
        .onLongPressGesture(minimumDuration: 10) { alarm.forceStop() }
    }
}
