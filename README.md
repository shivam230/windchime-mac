# Windchime for macOS (native) 🎐

A native **SwiftUI / AppKit** rewrite of
[Windchime](https://github.com/shivam230/windchime), built for the **Mac App
Store**.

The cross-platform [Tauri version](https://github.com/shivam230/windchime)
can't go on the Mac App Store, because making a *webview* transparent on macOS
needs a private API that Apple rejects. A **native** window is transparent with
fully *public* APIs (`NSWindow.isOpaque = false`, `backgroundColor = .clear`),
so this version is App-Store-eligible — same floating, see-through chime, done
the compliant way.

## Status — work in progress

- [x] **Stage A** — transparent floating window + ported physics (wind field,
      bell pendulums, ring timing), rendered with SwiftUI Canvas
- [ ] **Stage B** — sound synthesis (AVAudioEngine)
- [ ] **Stage C** — blow-at-mic detection (AVAudioEngine + FFT)
- [ ] **Stage D** — controls, drag, resize, Open at Login
- [ ] **Stage E** — `.app` bundle, sandbox + mic entitlement, App Store listing

## Run

Requires the Swift toolchain (comes with Xcode or the Command Line Tools).

```bash
swift run -c release
```

Keys (temporary until the on-screen controls land): **1 / 2 / 3** switch wind
level (calm / breeze / windy), **Esc** quits.

## License

MIT
