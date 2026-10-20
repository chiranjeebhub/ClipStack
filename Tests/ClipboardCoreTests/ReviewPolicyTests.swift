import XCTest
@testable import ClipboardCore

final class ReviewPolicyTests: XCTestCase {
    private let policy = ReviewPolicy()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func testWaitsForAWeekAndEnoughUses() {
        XCTAssertFalse(policy.shouldRequest(firstLaunch: daysAgo(6.9), uses: 100, lastPromptedVersion: nil, currentVersion: "1.2", now: now))
        XCTAssertFalse(policy.shouldRequest(firstLaunch: daysAgo(30), uses: 19, lastPromptedVersion: nil, currentVersion: "1.2", now: now))
        XCTAssertTrue(policy.shouldRequest(firstLaunch: daysAgo(7), uses: 20, lastPromptedVersion: nil, currentVersion: "1.2", now: now))
    }

    func testAsksOncePerVersion() {
        XCTAssertFalse(policy.shouldRequest(firstLaunch: daysAgo(30), uses: 50, lastPromptedVersion: "1.2", currentVersion: "1.2", now: now))
        XCTAssertTrue(policy.shouldRequest(firstLaunch: daysAgo(30), uses: 50, lastPromptedVersion: "1.1", currentVersion: "1.2", now: now))
    }
}
