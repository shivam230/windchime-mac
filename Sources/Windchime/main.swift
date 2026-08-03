import AppKit
import SwiftUI

// Native transparent floating widget — public AppKit/SwiftUI APIs only.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let audio = AudioEngine()
audio.volume = 0.7
audio.start()

let engine = ChimeEngine()
engine.onStrike = { freq, vel, pan in audio.strike(freq, vel, pan) }
engine.start()

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 300),
    styleMask: [.borderless, .resizable],
    backing: .buffered,
    defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.level = .floating
window.isMovableByWindowBackground = true
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
window.minSize = NSSize(width: 120, height: 165)

let hosting = NSHostingView(rootView: ChimeView(engine: engine))
hosting.layer?.backgroundColor = NSColor.clear.cgColor
window.contentView = hosting
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
    if e.keyCode == 53 ||
        (e.modifierFlags.contains(.command) && e.charactersIgnoringModifiers == "q") {
        NSApp.terminate(nil)
        return nil
    }
    // number keys 1/2/3 switch wind level (temporary, until controls land)
    if let c = e.charactersIgnoringModifiers, let n = Int(c), (1...3).contains(n) {
        engine.setWind(n - 1)
        return nil
    }
    return e
}

app.run()
