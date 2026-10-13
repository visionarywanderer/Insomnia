import XCTest
@testable import Insomnia

final class DurationParserTests: XCTestCase {
    // MARK: Popover "Until" time

    /// "Until 07:00" means the next 07:00: later today, or tomorrow when it
    /// has passed. The date part of the picker never matters.
    @MainActor
    func testUntilPicksTheNextOccurrenceOfThatTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Rome"))
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        XCTAssertEqual(StatusPopoverView.duration(until: at(1, 7, 0), now: at(13, 23, 0), calendar: calendar), 8 * 3600)
        XCTAssertEqual(StatusPopoverView.duration(until: at(1, 23, 30), now: at(13, 22, 0), calendar: calendar), 90 * 60)
        XCTAssertEqual(StatusPopoverView.duration(until: at(1, 22, 0), now: at(13, 22, 0), calendar: calendar), 24 * 3600, "the same minute means tomorrow")
    }

    // MARK: DurationParser (settings presets)

    func testParserUnits() {
        XCTAssertEqual(DurationParser.seconds(from: "30m"), 1_800)
        XCTAssertEqual(DurationParser.seconds(from: "2h"), 7_200)
        XCTAssertEqual(DurationParser.seconds(from: "3d"), 3 * 86_400)
        XCTAssertEqual(DurationParser.seconds(from: "1h30m"), 5_400)
        XCTAssertEqual(DurationParser.seconds(from: " 1d 2h 3m "), 86_400 + 7_200 + 180)
        XCTAssertEqual(DurationParser.seconds(from: "45"), 45 * 60, "bare numbers are minutes")
        XCTAssertEqual(DurationParser.seconds(from: "2H"), 7_200)
    }

    func testParserRejectsGarbage() {
        XCTAssertNil(DurationParser.seconds(from: ""))
        XCTAssertNil(DurationParser.seconds(from: "abc"))
        XCTAssertNil(DurationParser.seconds(from: "0m"))
        XCTAssertNil(DurationParser.seconds(from: "0"))
        XCTAssertNil(DurationParser.seconds(from: "2x"))
        XCTAssertNil(DurationParser.seconds(from: "h"))
        XCTAssertNil(DurationParser.seconds(from: "2h5"))
    }

    func testParserRejectsOverflowInsteadOfTrapping() {
        let huge = String(Int.max)
        XCTAssertNil(DurationParser.seconds(from: huge))          // bare minutes × 60
        XCTAssertNil(DurationParser.seconds(from: huge + "d"))    // unit multiply
        XCTAssertNil(DurationParser.seconds(from: "9223372036854775d 1d")) // addition
        XCTAssertNil(DurationParser.seconds(from: "99999999999999999999h")) // Int(...) fails
        XCTAssertEqual(DurationParser.seconds(from: "1d 2h"), 93_600)
    }
}
