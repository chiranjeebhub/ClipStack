import XCTest
@testable import ClipboardCore

final class ContentClassifierTests: XCTestCase {
    func testLinks() {
        XCTAssertEqual(ContentClassifier.classify("https://developer.apple.com/documentation"), .link)
        XCTAssertEqual(ContentClassifier.classify("  http://example.com/a?b=c  "), .link)
        XCTAssertEqual(ContentClassifier.classify("mailto:team@example.com"), .link)
        XCTAssertEqual(ContentClassifier.classify("see https://example.com"), .text)
        XCTAssertEqual(ContentClassifier.classify("https://"), .text)
    }

    func testColors() {
        XCTAssertEqual(ContentClassifier.classify("#FF6B35"), .color)
        XCTAssertEqual(ContentClassifier.classify("#fff"), .color)
        XCTAssertEqual(ContentClassifier.classify("#11223344"), .color)
        XCTAssertEqual(ContentClassifier.classify("#GGGGGG"), .text)
        XCTAssertEqual(ContentClassifier.classify("FF6B35"), .text)
    }

    func testCode() {
        let swift = """
        func applicationDidFinishLaunching(_ note: Notification) {
            let monitor = PasteboardMonitor(interval: 0.5)
            monitor.start()
        }
        """
        XCTAssertEqual(ContentClassifier.classify(swift), .code)
        XCTAssertEqual(ContentClassifier.classify("const x = items.map((i) => i.id);"), .code)
    }

    func testProseIsText() {
        XCTAssertEqual(ContentClassifier.classify("Let’s sync on the onboarding flow tomorrow at 10"), .text)
        XCTAssertEqual(ContentClassifier.classify("Let me know if the class is on.\nThanks!"), .text)
    }
}
