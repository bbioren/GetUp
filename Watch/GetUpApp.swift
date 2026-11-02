import SwiftUI

@main
struct GetUpApp: App {
    @StateObject private var alarm = AlarmManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(alarm)
                .environmentObject(alarm.tracker)
        }
    }
}
