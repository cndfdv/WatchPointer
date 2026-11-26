import AppKit

setvbuf(stdout, nil, _IONBF, 0) // show log lines immediately

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
app.delegate = controller
app.run()
