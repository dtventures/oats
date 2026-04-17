import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular) // show in Dock + App Switcher

let delegate = AppDelegate()
app.delegate = delegate
app.run()
