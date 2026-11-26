import Foundation

let swipe = Data([2])
let dictated = Data([6]) + Data("Привет".utf8)
let version = Data([1])

var exchange = WatchInputExchange()
precondition(exchange.begin(swipe, hasPairingRead: true) == .read)
precondition(exchange.begin(dictated, hasPairingRead: true) == nil)
precondition(!exchange.isWriting)
precondition(exchange.receivedRead(nil) == nil)
precondition(!exchange.isWriting)
exchange.finish(invalidateRead: true)

precondition(exchange.begin(swipe, hasPairingRead: true) == .read)
precondition(exchange.receivedRead(Data([2])) == nil)
precondition(!exchange.isWriting)
exchange.finish(invalidateRead: true)

precondition(exchange.begin(swipe, hasPairingRead: true) == .read)
precondition(exchange.receivedRead(version) == swipe)
precondition(exchange.isWriting)
precondition(exchange.receivedRead(version) == nil)
exchange.finish()

precondition(exchange.begin(dictated, hasPairingRead: true) == .write(dictated))
exchange.finish(invalidateRead: true)
precondition(exchange.begin(swipe, hasPairingRead: true) == .read)
exchange = WatchInputExchange()
precondition(exchange.receivedRead(version) == nil)

// An older Mac still requires an encrypted write. There is no pairing read to request.
precondition(exchange.begin(swipe, hasPairingRead: false) == .write(swipe))
exchange.finish()

let challenge = Data(repeating: 7, count: 16)
let envelope = Data([8, 9])
let seal: (Data, Data) -> Data? = { frame, input in
    frame == swipe && input == challenge ? envelope : nil
}
precondition(exchange.begin(swipe, hasPairingRead: true, seal: seal) == .read)
precondition(exchange.receivedRead(Data([1])) == nil)
precondition(!exchange.isWriting)
precondition(exchange.receivedRead(challenge) == envelope)
precondition(exchange.receivedRead(challenge) == nil)
exchange.finish()
precondition(exchange.begin(swipe, hasPairingRead: true, seal: seal) == .read)
print("Encrypted input exchange checks passed.")

let sessionID = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
let session = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                    0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
precondition(WatchDictation.begin(sessionID) == Data([10]) + session)
precondition(WatchDictation.cancel(sessionID) == Data([12]) + session)
precondition(WatchDictation.finish(sessionID, text: "Привет\n🌍") ==
             Data([11]) + session + Data("Привет 🌍".utf8))
precondition(WatchDictation.finish(sessionID, text: "    \n") == nil)
precondition(WatchDictation.finish(sessionID, text: "a\u{0000}b") == nil)
precondition(WatchDictation.manual("Привет\n🌍") == Data([6]) + Data("Привет 🌍".utf8))
precondition(WatchDictation.finish(sessionID, text: String(repeating: "é", count: 247) + "x")?.count == 512)
precondition(WatchDictation.finish(sessionID, text: String(repeating: "é", count: 248))?.count == 513)
precondition(WatchDictation.Kind.manual.insertsText && WatchDictation.Kind.finish.insertsText)
precondition(!WatchDictation.Kind.begin.insertsText && !WatchDictation.Kind.cancel.insertsText)
print("Focused dictation frame checks passed.")
