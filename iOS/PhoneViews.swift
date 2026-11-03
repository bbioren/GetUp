import SwiftUI
import Combine

struct PhoneRootView: View {
    @EnvironmentObject var wake: WakeController
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if wake.isChallengeActive { ChallengeView() } else { SetupView() }
        }
        .onReceive(timer) { _ in wake.tick() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { wake.tick() } }
        .onAppear { wake.tick() }
    }
}

struct SetupView: View {
    @EnvironmentObject var wake: WakeController

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Wake at", selection: $wake.wakeTime, displayedComponents: .hourAndMinute)
                    Stepper("Walk \(wake.stepTarget) steps", value: $wake.stepTarget, in: 10...500, step: 10)
                } footer: {
                    Text("The alarm rings again every 90 seconds until you've walked this many steps with your phone.")
                }

                Section {
                    Toggle("Stay-up check", isOn: $wake.stayUpEnabled)
                    if wake.stayUpEnabled {
                        Stepper("After \(wake.stayUpMinutes) min", value: $wake.stayUpMinutes, in: 5...30, step: 5)
                        Stepper("Need \(wake.stayUpSteps) more steps", value: $wake.stayUpSteps, in: 25...500, step: 25)
                    }
                } footer: {
                    Text("After you turn off the alarm, it rings again later unless you've kept walking around.")
                }

                Section {
                    if let p = wake.pending {
                        Label(p.kind == .wake
                              ? "Rings \(p.firesAt.formatted(date: .abbreviated, time: .shortened))"
                              : "Stay-up check at \(p.firesAt.formatted(date: .omitted, time: .shortened))",
                              systemImage: "alarm.fill")
                            .foregroundStyle(.green)
                        if wake.canDisarm {
                            Button("Turn off alarm", role: .destructive) { Task { await wake.disarm() } }
                        }
                    } else {
                        Button("Set alarm") { Task { await wake.arm() } }
                            .bold()
                    }
                    if let err = wake.errorMessage {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("GetUp")
        }
    }
}

struct ChallengeView: View {
    @EnvironmentObject var wake: WakeController

    var body: some View {
        let target = wake.pending?.target ?? 1
        VStack(spacing: 20) {
            Spacer()
            Text(wake.pending?.kind == .stayUp ? "Still up?" : "GET UP")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(.orange)
            Text("\(min(wake.steps, target)) / \(target)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text("steps").font(.title3).foregroundStyle(.secondary)
            ProgressView(value: Double(min(wake.steps, target)), total: Double(target))
                .tint(.orange)
                .scaleEffect(y: 3)
                .padding(.horizontal, 40)
            Text("Walk around with your phone. The alarm keeps coming back until you hit the goal.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            if let err = wake.errorMessage {
                Text(err).foregroundStyle(.red).font(.footnote).padding(.horizontal)
            }
            Spacer()
            Text("Hold anywhere for 10 s for emergency stop")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 10) { Task { await wake.forceStop() } }
    }
}
