import SwiftUI

@main
struct GetUpPhoneApp: App {
    @StateObject private var wake = WakeController.shared

    var body: some Scene {
        WindowGroup {
            PhoneRootView().environmentObject(wake)
        }
    }
}
