import Foundation
import XCTest
@testable import WatchPointer

final class LocalInputCipherTests: XCTestCase {
    private let key = Data(repeating: 1, count: 32)
    private let challenge = Data(repeating: 2, count: 16)
    private let frame = Data([2])

    func testEnvelopeAuthenticatesKeyChallengeAndContents() throws {
        let cipher = try XCTUnwrap(LocalInputCipher(keyData: key))
        let envelope = try XCTUnwrap(cipher.seal(frame, challenge: challenge))
        XCTAssertEqual(envelope.count, frame.count + LocalInputCipher.overhead)
        XCTAssertEqual(cipher.open(envelope, challenge: challenge), frame)
        XCTAssertNotEqual(cipher.seal(frame, challenge: challenge), envelope)

        let otherCipher = try XCTUnwrap(LocalInputCipher(keyData: Data(repeating: 3, count: 32)))
        XCTAssertNil(otherCipher.open(envelope, challenge: challenge))
        XCTAssertNil(cipher.open(envelope, challenge: Data(repeating: 3, count: 16)))

        var modified = envelope
        modified[modified.index(before: modified.endIndex)] ^= 1
        XCTAssertNil(cipher.open(modified, challenge: challenge))
    }

    func testAcceptsOnlyValidLengths() throws {
        XCTAssertNil(LocalInputCipher(keyData: key.dropLast()))
        let cipher = try XCTUnwrap(LocalInputCipher(keyData: key))
        let maximumFrame = Data(repeating: 0, count: 512 - LocalInputCipher.overhead)
        let envelope = try XCTUnwrap(cipher.seal(maximumFrame, challenge: challenge))
        XCTAssertEqual(envelope.count, 512)
        XCTAssertEqual(cipher.open(envelope, challenge: challenge), maximumFrame)
        XCTAssertNil(cipher.seal(maximumFrame + frame, challenge: challenge))
        XCTAssertNil(cipher.seal(Data(), challenge: challenge))
        XCTAssertNil(cipher.seal(frame, challenge: challenge.dropLast()))
        XCTAssertNil(cipher.open(envelope, challenge: challenge.dropLast()))
        XCTAssertNil(cipher.open(envelope + frame, challenge: challenge))
        XCTAssertNil(cipher.open(envelope.prefix(LocalInputCipher.overhead), challenge: challenge))
    }

    func testSuccessfulAuthenticationConsumesOnlyTheMatchingChallenge() throws {
        let cipher = try XCTUnwrap(LocalInputCipher(keyData: key))
        let central = UUID(), otherCentral = UUID()
        var challenges = LocalInputChallenges()
        let localChallenge = try XCTUnwrap(challenges.issue(for: central, now: 0))
        let otherChallenge = try XCTUnwrap(challenges.issue(for: otherCentral, now: 0))
        XCTAssertEqual(localChallenge.count, LocalInputCipher.challengeLength)
        XCTAssertNotEqual(localChallenge, otherChallenge)

        let envelope = try XCTUnwrap(cipher.seal(frame, challenge: localChallenge))
        let otherEnvelope = try XCTUnwrap(cipher.seal(frame, challenge: otherChallenge))
        XCTAssertNil(challenges.open(envelope, for: otherCentral, now: 1, cipher: cipher))
        XCTAssertEqual(challenges.open(otherEnvelope, for: otherCentral, now: 1, cipher: cipher), frame)
        XCTAssertEqual(challenges.open(envelope, for: central, now: 1, cipher: cipher), frame)
        XCTAssertNil(challenges.open(envelope, for: central, now: 1, cipher: cipher))
    }

    func testReplacementExpiryRemovalAndCapacity() throws {
        let cipher = try XCTUnwrap(LocalInputCipher(keyData: key))
        let central = UUID()
        var challenges = LocalInputChallenges()
        let original = try XCTUnwrap(challenges.issue(for: central, now: 0))
        for _ in 0..<7 {
            XCTAssertNotNil(challenges.issue(for: UUID(), now: 0))
        }
        XCTAssertNil(challenges.issue(for: UUID(), now: 1))

        let replacement = try XCTUnwrap(challenges.issue(for: central, now: 1))
        XCTAssertNotEqual(original, replacement)
        let originalEnvelope = try XCTUnwrap(cipher.seal(frame, challenge: original))
        let replacementEnvelope = try XCTUnwrap(cipher.seal(frame, challenge: replacement))
        XCTAssertNil(challenges.open(originalEnvelope, for: central, now: 1, cipher: cipher))
        XCTAssertNotNil(challenges.issue(for: UUID(), now: 15))
        XCTAssertNil(challenges.open(replacementEnvelope, for: central, now: 16, cipher: cipher))

        let renewed = try XCTUnwrap(challenges.issue(for: central, now: 16))
        let renewedEnvelope = try XCTUnwrap(cipher.seal(frame, challenge: renewed))
        challenges.remove(for: central)
        XCTAssertNil(challenges.open(renewedEnvelope, for: central, now: 16, cipher: cipher))
    }
}
