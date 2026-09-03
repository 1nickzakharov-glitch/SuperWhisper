import AppKit
import Darwin

// Enable unbuffered logging to terminal
setlinebuf(stdout)
setlinebuf(stderr)

print("🌟 [SuperWhisper] main.swift starting...")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
