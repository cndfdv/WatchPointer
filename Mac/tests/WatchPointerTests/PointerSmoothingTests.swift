import Foundation
import XCTest
@testable import WatchPointer

final class PointerSmoothingTests: XCTestCase {
    func testBalancedReducesSyntheticRestMovement() {
        for frequencies in [(5.0, 9.0), (13.0, 21.0)] {
            let signal: (Double) -> Double = { time in
                2 * sin(2 * .pi * frequencies.0 * time) + 1.2 * sin(2 * .pi * frequencies.1 * time)
            }
            let classic = rms(replay(.classic, signal).dropFirst(240))
            let balanced = rms(replay(.balanced, signal).dropFirst(240))
            XCTAssertLessThan(balanced, classic * 0.95)
        }
    }

    func testBalancedRespondsAtLeastAsQuicklyToFastAndSmallMoves() throws {
        for (distance, duration) in [(300.0, 0.18), (72.0, 0.7), (13.0, 0.7)] {
            let signal: (Double) -> Double = { time in
                distance * min(max((time - 1) / duration, 0), 1)
            }
            let classic = try XCTUnwrap(replay(.classic, signal).firstIndex { $0 >= distance / 2 })
            let balanced = try XCTUnwrap(replay(.balanced, signal).firstIndex { $0 >= distance / 2 })
            XCTAssertLessThanOrEqual(balanced, classic)
        }
    }

    private func replay(_ mode: PointerSmoothing, _ input: (Double) -> Double) -> [Double] {
        var filter = OneEuroFilter()
        filter.smoothing = mode
        var target = 0.0
        var shown = 0.0
        let follow = 1 - exp(-1.0 / 240 / 0.005)
        var frames: [Double] = []
        for tick in 0...4800 {
            if tick.isMultiple(of: 12) {
                target = filter(input(Double(tick) / 1200), dt: tick == 0 ? 0 : 0.01)
            }
            if tick.isMultiple(of: 5) {
                let next = shown + (target - shown) * follow
                if abs(next - shown) > 0.05 { shown = next }
                frames.append(shown)
            }
        }
        return frames
    }

    private func rms(_ points: ArraySlice<Double>) -> Double {
        sqrt(points.reduce(0) { $0 + $1 * $1 } / Double(points.count))
    }
}
