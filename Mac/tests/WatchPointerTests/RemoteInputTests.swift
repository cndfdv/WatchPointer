import Foundation
import XCTest
@testable import WatchPointer

final class RemoteInputTests: XCTestCase {
    func testCommandFramesContainOnlyTheExpectedPayload() {
        XCTAssertEqual(RemoteInputPacket(data: Data([2])), .browserBack)
        XCTAssertEqual(RemoteInputPacket(data: Data([3])), .browserForward)
        XCTAssertEqual(RemoteInputPacket(data: Data([4])), .spaceLeft)
        XCTAssertEqual(RemoteInputPacket(data: Data([5])), .spaceRight)
        XCTAssertNil(RemoteInputPacket(data: Data([2, 1])))
        XCTAssertNil(RemoteInputPacket(data: Data([10])))
        XCTAssertEqual(RemoteInputPacket(data: Data([1]) + Data("012345".utf8)), .pair("012345"))
        XCTAssertNil(RemoteInputPacket(data: Data([1]) + Data("12345a".utf8)))
        XCTAssertNil(RemoteInputPacket(data: Data([1]) + Data("١٢٣٤٥٦".utf8)))
    }

    func testTabAndMissionControlFramesRequireExactlyOneByte() {
        let commands: [(UInt8, RemoteInputPacket)] = [
            (7, .browserTabPrevious), (8, .browserTabNext), (9, .missionControl),
        ]
        for (kind, command) in commands {
            let packet = RemoteInputPacket(data: Data([kind]))
            XCTAssertEqual(packet, command)
            XCTAssertNil(RemoteInputPacket(data: Data([kind, 0])))
        }
    }

    func testTabAndMissionControlCommandsRequirePairingAndRespectRevocation() throws {
        let watch = UUID(), other = UUID()
        var access = RemoteInputAuthorization()
        let packets = try (7...9).map { kind in
            try XCTUnwrap(RemoteInputPacket(data: Data([kind])))
        }

        for packet in packets {
            XCTAssertEqual(access.authorize(packet, from: watch, now: 10), .unpaired)
        }
        access.beginPairing(code: "012345", now: 10)
        XCTAssertEqual(access.authorize(.pair("012345"), from: watch, now: 11), .paired)
        for packet in packets {
            XCTAssertEqual(access.authorize(packet, from: watch, now: 12), .allowed)
            XCTAssertEqual(access.authorize(packet, from: other, now: 12), .unpaired)
        }
        access.forget()
        for packet in packets {
            XCTAssertEqual(access.authorize(packet, from: watch, now: 13), .unpaired)
        }
    }

    func testDictationValidatesTextAndByteLength() {
        let spoken = "Привет, мир 👋🏽"
        XCTAssertEqual(RemoteInputPacket(data: Data([6]) + Data(spoken.utf8)), .text(spoken))
        XCTAssertNotNil(RemoteInputPacket(data: Data([6]) + Data(repeating: 65, count: 511)))
        XCTAssertNil(RemoteInputPacket(data: Data([6]) + Data(repeating: 65, count: 512)))
        XCTAssertNil(RemoteInputPacket(data: Data([6])))
        XCTAssertNil(RemoteInputPacket(data: Data([6, 255])))
        XCTAssertNil(RemoteInputPacket(data: Data([6]) + Data("   ".utf8)))
        XCTAssertNil(RemoteInputPacket(data: Data([6]) + Data("line\nnext".utf8)))
        XCTAssertNil(RemoteInputPacket(data: Data([6]) + Data("tab\tkey".utf8)))
    }

    func testFocusedDictationFramesAndAuthorization() {
        let id = UUID(uuidString: "00010203-0405-0607-0809-0A0B0C0D0E0F")!
        let bytes = Data(0..<16)
        let watch = UUID()
        var paired = RemoteInputAuthorization(pairedCentral: watch)
        for (frame, expected) in [
            (Data([10]) + bytes, RemoteInputPacket.dictationBegin(id)),
            (Data([11]) + bytes + Data("Привет".utf8), .dictationFinish(id, "Привет")),
            (Data([12]) + bytes, .dictationCancel(id)),
        ] {
            XCTAssertEqual(RemoteInputPacket(data: frame), expected)
            XCTAssertEqual(paired.authorize(expected, from: watch, now: 0), .allowed)
            XCTAssertEqual(paired.authorize(expected, from: UUID(), now: 0), .unpaired)
        }
        XCTAssertNil(RemoteInputPacket(data: Data([10]) + bytes.dropLast()))
        XCTAssertNil(RemoteInputPacket(data: Data([12]) + bytes + Data([0])))
        XCTAssertNil(RemoteInputPacket(data: Data([11]) + bytes))
        XCTAssertNil(RemoteInputPacket(data: Data([11]) + bytes + Data([0xFF])))
        XCTAssertNil(RemoteInputPacket(data: Data([11]) + bytes + Data("a\u{2028}b".utf8)))
        XCTAssertNotNil(RemoteInputPacket(data: Data([11]) + bytes + Data(repeating: 65, count: 495)))
        XCTAssertNil(RemoteInputPacket(data: Data([11]) + bytes + Data(repeating: 65, count: 496)))
    }

    func testFocusedDictationSessionsRequireMatchingLiveTokenAndAreOneShot() {
        let id = UUID(), unrelated = UUID()
        var sessions = FocusedDictationSession<String>()
        sessions.begin(id, target: "field", now: 10)
        sessions.cancel(unrelated)
        XCTAssertNil(sessions.take(unrelated, now: 20))
        XCTAssertEqual(sessions.take(id, now: 20), "field")
        XCTAssertNil(sessions.take(id, now: 21))

        sessions.begin(id, target: "field", now: 30)
        XCTAssertNil(sessions.take(id, now: 150))

        sessions.begin(id, target: "field", now: 151)
        sessions.cancel(id)
        XCTAssertNil(sessions.take(id, now: 152))

        sessions.begin(id, target: "field", now: 153)
        sessions.begin(unrelated, target: "new field", now: 154)
        XCTAssertNil(sessions.take(id, now: 155))
        XCTAssertEqual(sessions.take(unrelated, now: 156), "new field")
    }

    func testLongWriteReassemblesOnlyContiguousFragmentsFromOnePeer() {
        let watch = UUID(), characteristic = UUID()
        let payload = Data([6]) + Data("Привет".utf8)
        let first = RemoteInputFragment(centralID: watch, characteristicID: characteristic, offset: 0, value: payload.prefix(2))
        let rest = payload.dropFirst(2)
        let second = RemoteInputFragment(centralID: watch, characteristicID: characteristic, offset: 2, value: rest)
        let otherWatch = RemoteInputFragment(centralID: UUID(), characteristicID: characteristic, offset: 2, value: rest)
        let otherCharacteristic = RemoteInputFragment(centralID: watch, characteristicID: UUID(), offset: 2, value: rest)
        let gap = RemoteInputFragment(centralID: watch, characteristicID: characteristic, offset: 3, value: rest)
        let overlap = RemoteInputFragment(centralID: watch, characteristicID: characteristic, offset: 1, value: rest)
        XCTAssertEqual(RemoteInputPacket.assemble([second, first]), .text("Привет"))
        XCTAssertNil(RemoteInputPacket.assemble([first, otherWatch]))
        XCTAssertNil(RemoteInputPacket.assemble([first, otherCharacteristic]))
        XCTAssertNil(RemoteInputPacket.assemble([first, gap]))
        XCTAssertNil(RemoteInputPacket.assemble([first, overlap]))
    }

    func testPairingIsRequiredAndRevocationStopsNewCommands() {
        let watch = UUID(), other = UUID()
        var access = RemoteInputAuthorization()

        XCTAssertEqual(access.authorize(.browserBack, from: watch, now: 10), .unpaired)
        access.beginPairing(code: "012345", now: 10)
        XCTAssertEqual(access.authorize(.pair("012345"), from: watch, now: 11), .paired)
        XCTAssertEqual(access.authorize(.text("hi"), from: watch, now: 12), .allowed)
        XCTAssertEqual(access.authorize(.spaceRight, from: other, now: 12), .unpaired)
        XCTAssertEqual(access.authorize(.pair("012345"), from: other, now: 12), .invalidCode)
        access.forget()
        XCTAssertEqual(access.authorize(.browserForward, from: watch, now: 13), .unpaired)
    }

    func testPairingCodeExpiresAndStopsWorkingAfterFiveWrongAttempts() {
        let watch = UUID()
        var access = RemoteInputAuthorization()

        access.beginPairing(code: "123456", now: 10)
        XCTAssertEqual(access.authorize(.pair("123456"), from: watch, now: 131), .invalidCode)
        access.beginPairing(code: "123456", now: 132)
        for _ in 1...5 {
            XCTAssertEqual(access.authorize(.pair("999999"), from: watch, now: 133), .invalidCode)
        }
        XCTAssertEqual(access.authorize(.pair("123456"), from: watch, now: 134), .invalidCode)
        XCTAssertNil(access.pairedCentral)
        access.beginPairing(code: "654321", now: 135)
        XCTAssertEqual(access.authorize(.pair("654321"), from: watch, now: 136), .paired)
    }
}
