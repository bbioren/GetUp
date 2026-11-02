import SwiftUI

/// Companion iPhone app. It only exists so the watch app can be installed
/// through the iPhone; the alarm itself runs entirely on the watch.
@main
struct GetUpPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                Text("GetUp lives on your Apple Watch").font(.title2.bold())
                Text("If it isn't on your watch yet: open the Watch app on this iPhone, scroll to Available Apps, and tap Install next to GetUp.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
    }
}
