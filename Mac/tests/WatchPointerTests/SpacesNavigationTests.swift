import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import WatchPointer

final class SpacesNavigationTests: XCTestCase {
    func testAdjacentSpaceShortcutHasTheFullHIDKeySequence() throws {
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]

        for arrow in [kVK_LeftArrow, kVK_RightArrow] {
            let events = try XCTUnwrap(SpacesNavigation.events(for: arrow))

            XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
            XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) },
                           [kVK_Control, arrow, arrow, kVK_Control].map(Int64.init))
            XCTAssertEqual(events.map(\.flags), [.maskControl, arrowFlags, arrowFlags, []])
            XCTAssertTrue(events.allSatisfy {
                $0.getIntegerValueField(.eventSourceStateID) == Int64(CGEventSourceStateID.hidSystemState.rawValue)
            })
        }
    }

    func testRejectsOtherKeys() {
        XCTAssertNil(SpacesNavigation.events(for: kVK_UpArrow))
    }
}
