# GetUp: an alarm you can't turn off from bed

**iPhone app (current):** at your wake time it starts a system alarm (AlarmKit, iOS 26+) that breaks through silent mode and repeats every 90 seconds for an hour. Pressing Stop only buys you 90 seconds. The alarms stop for good once you've walked your step goal (default 50) with the phone. 10 minutes later a stay-up check rings again unless you've walked about 100 more steps.

Emergency stop: hold the challenge screen for 10 s.

**Watch app (`Watch/`, on hold):** a heart-rate version that compiles but couldn't be installed with a free Apple account (the watch never connected to Xcode). It's kept for later.

## Build
```
brew install xcodegen
xcodegen generate
open GetUp.xcodeproj
```
Set your Team in project.yml (or in Xcode), pick your iPhone as the run destination, and press Run. On the phone, trust the developer in Settings → General → VPN & Device Management.
