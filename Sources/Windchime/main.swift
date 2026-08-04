import AppKit
import SwiftUI
import ServiceManagement

// Native transparent floating widget — public AppKit/SwiftUI APIs only.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let audio = AudioEngine()
audio.volume = 0.7
audio.start()

let engine = ChimeEngine()
engine.onStrike = { freq, vel, pan in audio.strike(freq, vel, pan) }
engine.start()

// Breath detection — feeds the wind field, so blowing rings the chimes.
// Off by default (privacy); the user turns it on with the mic button.
let mic = MicDetector()
mic.onLevel = { lvl in engine.micLevel = lvl }

let controller = AppController(engine: engine, audio: audio, mic: mic)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 190, height: 250),
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
window.minSize = NSSize(width: 110, height: 150)

let hosting = NSHostingView(rootView: RootView(controller: controller))
hosting.layer?.backgroundColor = NSColor.clear.cgColor
window.contentView = hosting
controller.window = window
// Remember where the user last left the widget; center only on first ever run.
let frameKey = "WindchimeMain"
let hadSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame \(frameKey)") != nil
window.setFrameAutosaveName(frameKey)
if !hadSavedFrame { window.center() }
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

// Right-click anywhere on the widget → Open at Login / Quit.
let menuActions = MenuActions()
NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { e in
    let menu = NSMenu()
    let login = NSMenuItem(title: "Open at Login", action: #selector(MenuActions.toggleLogin), keyEquivalent: "")
    login.target = menuActions
    login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    menu.addItem(login)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit Windchime", action: #selector(MenuActions.quit), keyEquivalent: "")
    quit.target = menuActions
    menu.addItem(quit)
    if let view = window.contentView { NSMenu.popUpContextMenu(menu, with: e, for: view) }
    return nil
}

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
    if e.keyCode == 53 ||
        (e.modifierFlags.contains(.command) && e.charactersIgnoringModifiers == "q") {
        NSApp.terminate(nil)
        return nil
    }
    return e
}

app.run()
