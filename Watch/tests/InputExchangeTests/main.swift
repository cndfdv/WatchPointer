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
