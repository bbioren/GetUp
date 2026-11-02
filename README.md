# GetUp: Apple Watch alarm you can't turn off from bed

The alarm buzzes until you beat a wake-up challenge:

- **Heart rate** (default): get above your sleeping heart rate + 30 bpm and hold it for 30 s.
- **Steps** or **jumping jacks**: hit a count.

Then a **stay-up check** fires 10 minutes later. If you haven't walked about 100 steps by then, it rings again.

Heart rate comes from a workout session that is thrown away when it ends, so nothing is saved to Health. The workout session also keeps the app alive, so the alarm can keep buzzing past the watch's ~30 min smart-alarm limit.

Emergency stop: hold the ringing screen for 10 s.

## Build
```
brew install xcodegen
xcodegen generate
open GetUp.xcodeproj
```
In Xcode, set Team on both targets, pick your iPhone as the run destination, and press Run. Then open the Watch app on the iPhone → Available Apps → Install GetUp. (The iPhone app is just a carrier for the watch app.)
