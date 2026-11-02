# GetUp: Apple Watch alarm you can't turn off from bed

## Setup (once Xcode is installed)
1. Xcode → File → New → Project → watchOS → App. Name it `GetUp`, Interface SwiftUI, "Watch-only App".
2. Delete the generated `ContentView.swift` and `GetUpApp.swift`, then drag in the 4 files from `GetUp/`.
3. Select the Watch target → Signing & Capabilities → sign in with your Apple ID (a free account works).
4. Click + Capability → Background Modes → set Session Type to **Smart Alarm**.
5. Info tab → add `NSMotionUsageDescription` = "Counts your steps/jumping jacks to turn off the alarm".
6. Pair your watch (via iPhone), turn on Developer Mode on the watch, select it as the run destination, then hit Run.

## Tuning
Jumping-jack sensitivity is set by the constants at the top of `ChallengeTracker.swift`.
