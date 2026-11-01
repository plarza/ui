import XCTest

public extension XCTestCase {
    /// Checks every 0.1 s. XCTest's own waits check about once a second, which made every step cost a second.
    @discardableResult
    func poll(_ timeout: TimeInterval = 6, _ done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !done() {
            if Date() > end { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return true
    }

    /// Waits for `element` and returns it, failing at the caller's line if it never appears.
    @discardableResult
    func wait(_ element: XCUIElement, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(poll(timeout) { element.exists }, "\(element) never appeared", file: file, line: line)
        return element
    }
}

public extension XCUIApplication {
    /// Launches as on first launch: at the sign-in screen, signed out.
    func launchAtSignIn() {
        launchArguments += ["-signInAnswered", "NO", "-account", "none"]
        launch()
    }

    /// Launches with the sign-in screen skipped, or signed in to the sample profile.
    func launchPastSignIn(signedIn: Bool = false) {
        launchArguments += ["-signInAnswered", "YES"]
        if signedIn { launchEnvironment["SAMPLE_ACCOUNT"] = "1" }
        launch()
    }
}
