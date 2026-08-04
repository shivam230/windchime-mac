import SwiftUI
import AppKit
import ServiceManagement

// Bridges the SwiftUI controls to the engine / audio / mic / window.
final class AppController: ObservableObject {
    let engine: ChimeEngine
    let audio: AudioEngine
    let mic: MicDetector
    weak var window: NSWindow?

    @Published var windLabel: String
    @Published var micActive = false
    @Published var pinned = true
    @Published var volume: Double { didSet { audio.volume = volume } }

    private let minW: CGFloat = 110, minH: CGFloat = 150

    init(engine: ChimeEngine, audio: AudioEngine, mic: MicDetector) {
        self.engine = engine
        self.audio = audio
        self.mic = mic
        self.windLabel = engine.winds[engine.windIndex].label
        self.volume = audio.volume
    }

    func cycleWind() {
        engine.setWind(engine.windIndex + 1)
        windLabel = engine.winds[engine.windIndex].label
    }
    func toggleMic() {
        if mic.isActive { mic.stop(); micActive = false }
        else { mic.start(); micActive = true }
    }
    func togglePin() {
        pinned.toggle()
        window?.level = pinned ? .floating : .normal
    }
    func moveBy(_ dx: CGFloat, _ dy: CGFloat) {
        guard let w = window else { return }
        var o = w.frame.origin
        o.x += dx
        o.y -= dy            // screen origin is bottom-left; drag down = lower
        w.setFrameOrigin(o)
    }
    func resizeBy(_ dx: CGFloat, _ dy: CGFloat) {
        guard let w = window else { return }
        var f = w.frame
        let newW = max(minW, f.size.width + dx)
        let newH = max(minH, f.size.height + dy)
        f.origin.y -= (newH - f.size.height)   // keep the top edge fixed
        f.size = NSSize(width: newW, height: newH)
        w.setFrame(f, display: true)
    }
    func quit() { NSApp.terminate(nil) }
}

// Right-click menu actions (needs an NSObject for target/action).
final class MenuActions: NSObject {
    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch { NSLog("Windchime login item: \(error)") }
    }
    @objc func quit() { NSApp.terminate(nil) }
}

struct RootView: View {
    @ObservedObject var controller: AppController
    @State private var hover = false
    @State private var moveStartMouse: CGPoint? = nil
    @State private var moveStartOrigin: CGPoint? = nil
    @State private var lastPtr: CGPoint? = nil
    @State private var lastPtrT = Date()
    @State private var ptrV = CGSize.zero
    private let accent = Color(red: 0.851, green: 0.678, blue: 0.322)

    var body: some View {
        GeometryReader { geo in
            let barY = ChimeView.chimeBottomY(geo.size) + 18   // just under the bells
            ZStack(alignment: .topLeading) {
                // Drag the chime to move the window; tap a bell to ring it.
                ChimeView(engine: controller.engine)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        // Track the ABSOLUTE screen mouse position, not window-
                        // relative translation, so moving the window can't feed
                        // back into the measurement (which caused the runaway).
                        DragGesture(minimumDistance: 4)
                            .onChanged { _ in
                                guard let w = controller.window else { return }
                                if moveStartMouse == nil {
                                    moveStartMouse = NSEvent.mouseLocation
                                    moveStartOrigin = w.frame.origin
                                }
                                if let sm = moveStartMouse, let so = moveStartOrigin {
                                    let cur = NSEvent.mouseLocation
                                    w.setFrameOrigin(NSPoint(x: so.x + (cur.x - sm.x),
                                                             y: so.y + (cur.y - sm.y)))
                                }
                            }
                            .onEnded { _ in
                                moveStartMouse = nil
                                moveStartOrigin = nil
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture(coordinateSpace: .local)
                            .onEnded { v in
                                controller.engine.viewW = Double(geo.size.width)
                                controller.engine.viewH = Double(geo.size.height)
                                controller.engine.tap(x: Double(v.location.x), y: Double(v.location.y))
                            }
                    )
                controlBar
                    .position(x: geo.size.width / 2, y: barY)
                    .opacity(hover ? 1 : 0)
                    .allowsHitTesting(hover)
                DragHandle(system: "arrow.down.right") { dx, dy in controller.resizeBy(dx, dy) }
                    .position(x: geo.size.width - 12, y: barY + 22)   // just under the toolbar
                    .opacity(hover ? 1 : 0)
                    .allowsHitTesting(hover)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 0.25), value: hover)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc):
                    hover = true
                    let now = Date()
                    if let lp = lastPtr {
                        let dt = max(0.004, now.timeIntervalSince(lastPtrT))
                        ptrV = CGSize(width: ptrV.width * 0.5 + Double(loc.x - lp.x) / dt * 0.5,
                                      height: ptrV.height * 0.5 + Double(loc.y - lp.y) / dt * 0.5)
                    }
                    lastPtr = loc
                    lastPtrT = now
                    controller.engine.viewW = Double(geo.size.width)
                    controller.engine.viewH = Double(geo.size.height)
                    controller.engine.brush(x: Double(loc.x), y: Double(loc.y),
                                            vx: Double(ptrV.width), vy: Double(ptrV.height))
                case .ended:
                    hover = false
                    lastPtr = nil
                    ptrV = .zero
                }
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 3) {
            Button(action: controller.cycleWind) {
                HStack(spacing: 4) {
                    Image(systemName: "wind")
                    Text(controller.windLabel).font(.system(size: 10, weight: .medium))
                }
            }
            Divider().frame(height: 12)
            Button(action: controller.toggleMic) {
                Image(systemName: controller.micActive ? "mic.fill" : "mic")
                    .foregroundColor(controller.micActive ? accent : .white.opacity(0.8))
            }
            Slider(value: $controller.volume, in: 0...1).frame(width: 48).tint(accent)
            Button(action: controller.togglePin) {
                Image(systemName: controller.pinned ? "pin.fill" : "pin")
                    .foregroundColor(controller.pinned ? accent : .white.opacity(0.8))
            }
            Divider().frame(height: 12)
            Button(action: controller.quit) {
                Image(systemName: "xmark").foregroundColor(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
        .fixedSize()
    }
}

// A grab handle that reports incremental deltas from the ABSOLUTE screen mouse
// position, so resizing the window can't feed back into the measurement.
struct DragHandle: View {
    let system: String
    let onDrag: (CGFloat, CGFloat) -> Void   // dx right+, dy down+
    @State private var lastMouse: CGPoint? = nil

    var body: some View {
        Image(systemName: system)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white.opacity(0.55))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        let cur = NSEvent.mouseLocation
                        if let lm = lastMouse {
                            onDrag(cur.x - lm.x, -(cur.y - lm.y))   // screen y is bottom-up
                        }
                        lastMouse = cur
                    }
                    .onEnded { _ in lastMouse = nil }
            )
    }
}
