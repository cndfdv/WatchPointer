import CoreGraphics

func point(_ x: CGFloat, _ y: CGFloat = 0) -> CGPoint { CGPoint(x: x, y: y) }

var tap = PadGesture<Int>()
tap.record(1, at: point(10), active: true)
tap.record(1, at: point(12), active: false)
precondition(tap.finish() == .click, "A small amount of finger movement must still click")

var hold = PadGesture<Int>()
hold.record(1, at: point(10), active: true)
precondition(hold.beginHold(), "A stationary hold must start a drag")
hold.record(1, at: point(44), active: false)
var interruptedHold = hold
precondition(hold.finish() == .drop, "A drag moving horizontally must end with a drop")
precondition(hold.cancel() == nil, "A completed drag must already have been released")
precondition(interruptedHold.cancel() == .drop && interruptedHold.cancel() == nil,
             "Cancellation must release an active drag once")

for direction in [-1.0, 1.0] {
    var swipe = PadGesture<Int>()
    swipe.record(1, at: point(50), active: true)
    swipe.record(1, at: point(50 + direction * 10), active: true)
    precondition(!swipe.beginHold(), "A moving finger must not start a drag")
    swipe.record(1, at: point(50 + direction * 40), active: false)
    precondition(swipe.finish() == .swipe(direction > 0 ? .browserTabPrevious : .browserTabNext),
                 "One finger must select the corresponding browser tab")
    precondition(swipe.finish() == nil, "A completed gesture must send only one command")
}

for end in [point(14, -40), point(14, 40), point(28, 30), point(24)] {
    var invalid = PadGesture<Int>()
    invalid.record(1, at: point(10), active: true)
    invalid.record(1, at: end, active: false)
    precondition(invalid.finish() == nil, "A vertical, diagonal or short swipe must not trigger a tab or click")
}

func pair(first: CGPoint, second: CGPoint, overlap: Bool = true) -> PadGesture<Int> {
    var gesture = PadGesture<Int>()
    gesture.record(1, at: point(50, 60), active: true)
    if !overlap { gesture.record(1, at: first, active: false) }
    gesture.record(2, at: point(80, 60), active: true)
    if overlap { gesture.recordOverlap() }
    gesture.record(1, at: first, active: false)
    gesture.record(2, at: second, active: true)
    gesture.record(2, at: second, active: false)
    return gesture
}

var right = pair(first: point(90, 60), second: point(120, 63))
precondition(right.finish() == .swipe(.spaceLeft), "Two fingers right must select the previous Space")
var left = pair(first: point(10, 60), second: point(40, 63))
precondition(left.finish() == .swipe(.spaceRight), "Two fingers left must select the next Space")
var up = pair(first: point(50, 24), second: point(82, 22))
precondition(up.finish() == .swipe(.missionControl), "Staggered release must still open Mission Control")
precondition(up.finish() == nil, "A staggered release must send only one command")

var opposed = pair(first: point(90, 60), second: point(40, 61))
precondition(opposed.finish() == nil, "Opposite directions must not change Spaces")
var diagonal = pair(first: point(88, 21), second: point(120, 22))
precondition(diagonal.finish() == nil, "Diagonal movement must not open Mission Control or change Spaces")
var down = pair(first: point(50, 100), second: point(82, 100))
precondition(down.finish() == nil, "Two fingers down must not open Mission Control")
var separate = pair(first: point(50, 24), second: point(82, 22), overlap: false)
precondition(separate.finish() == nil, "Two contacts that never overlapped must not open Mission Control")
var cancelled = pair(first: point(50, 24), second: point(82, 22))
precondition(cancelled.cancel() == nil && cancelled.finish() == nil, "Cancelled touches must not send a command")

var three = PadGesture<Int>()
for finger in 1...3 { three.record(finger, at: point(CGFloat(finger * 20), 60), active: true) }
three.recordOverlap()
for finger in 1...3 { three.record(finger, at: point(CGFloat(finger * 20), 20), active: false) }
precondition(three.finish() == nil, "A third touch must not send a one- or two-finger command")

print("Pad gesture checks passed.")
