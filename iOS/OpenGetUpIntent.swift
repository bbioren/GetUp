import AppIntents

/// The "Open GetUp" button on the alarm screen. Opens the app so you can do the challenge.
struct OpenGetUpIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open GetUp"
    static var openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}
