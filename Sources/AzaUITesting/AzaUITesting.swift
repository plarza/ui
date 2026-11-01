import XCTest

/// Helpers for end-to-end UI tests on the Simulator.
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

    /// Waits for `element` to exist and returns it, failing the test at the caller's line if it never does.
    @discardableResult
    func wait(_ element: XCUIElement, _ timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(poll(timeout) { element.exists }, "\(element) never appeared", file: file, line: line)
        return element
    }
}

public extension XCUIApplication {
    /// Launch arguments that answer the aza sign-in screen as skipped.
    static let skipSignIn = ["-aza.decided", "YES"]

    /// Launches with the sign-in screen answered, and signed in to the sample profile if asked.
    func launchPastSignIn(signedIn: Bool = false) {
        launchArguments += Self.skipSignIn
        if signedIn { launchEnvironment["AZA_SIGNED_IN"] = "1" }
        launch()
    }
}
