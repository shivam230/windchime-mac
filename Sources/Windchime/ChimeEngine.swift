import Foundation
import QuartzCore
import Combine

// The simulation — a faithful Swift port of the web app's renderer/app.js:
// a wind field drives each bell as a damped pendulum; a bell "rings" when it
// swings hard enough, gated so the rate/feel matches the wind level.

struct Bell {
    var az: Double            // angle around the ring
    var omega: Double         // pendulum natural frequency
    var freq: Double          // musical pitch (Hz)
    var swing: Double = 0
    var swingV: Double = 0
    var glow: Double = 0      // 0..1 flash right after a strike
    var ripple: Double = 0    // 0..1 expanding ring after a strike
    var nextOk: Double = 0    // earliest sim-time this bell may ring again
    var last: Double = -9
}

// A drifting speck that visualizes the (invisible) wind. Normalized 0…1 space
// so the view can scale it to any window size.
struct Mote {
    var x: Double
    var y: Double
    var vx: Double
    var life: Double
    var wob: Double
}

struct WindLevel {
    let id: String
    let label: String
    let base: Double
    let pumpMul: Double
    let thresh: Double
    let gateMin: Double
    let gateRand: Double
    let perBellMin: Double
    let perBellRand: Double
    let gustMin: Double
    let gustMax: Double
    let gustAmp: Double
}

final class ChimeEngine: ObservableObject {
    // Bumped every physics tick (60 Hz). The view observes this to repaint,
    // so drawing stays alive even when the widget isn't the focused window
    // (unlike TimelineView(.animation), which pauses when unfocused).
    @Published private(set) var frame: Int = 0
    // Himalayan brass bells (G6 A6 C7 D7 E7)
    private let notes = [1567.98, 1760.0, 2093.0, 2349.32, 2637.02]

    let winds = [
        WindLevel(id: "calm",   label: "Calm",   base: 0.17, pumpMul: 0.75, thresh: 2.3,
                  gateMin: 3.5, gateRand: 11, perBellMin: 3.0, perBellRand: 8.0,
                  gustMin: 6, gustMax: 16, gustAmp: 1.6),
        WindLevel(id: "breeze", label: "Breeze", base: 0.36, pumpMul: 1.15, thresh: 2.3,
                  gateMin: 1.1, gateRand: 3.6, perBellMin: 1.4, perBellRand: 5.0,
                  gustMin: 6, gustMax: 16, gustAmp: 1.6),
        WindLevel(id: "windy",  label: "Windy",  base: 0.62, pumpMul: 1.9, thresh: 2.3,
                  gateMin: 0.45, gateRand: 1.7, perBellMin: 0.7, perBellRand: 2.5,
                  gustMin: 3, gustMax: 8, gustAmp: 2.4),
    ]

    var windIndex = 1
    var micLevel = 0.0                 // 0..1, fed by MicDetector later
    var onStrike: ((Double, Double, Double) -> Void)?  // freq, vel, pan

    private(set) var bells: [Bell] = []
    private(set) var motes: [Mote] = []

    // wind field state
    private var fx = 0.0, fz = 0.0, pump = 0.0, gust = 0.0
    private var gustAmp = 0.0, gustDur = 1.0, gustT = 99.0, nextGust = 3.0

    // ring-rate gates
    private var nextWindOk = 2.0
    private var recentRings: [Double] = []

    private var timer: Timer?
    private var tickCount = 0
    private var lastT = CACurrentMediaTime()
    var simT: Double { CACurrentMediaTime() }

    init() { buildBells() }

    private func buildBells() {
        let n = notes.count
        // Same shuffle as the web build so neighbouring bells aren't neighbouring
        // notes; frequency/omega key off the note index, not the position.
        let order = [0, 3, 1, 4, 2]
        bells = (0..<n).map { i in
            let noteIdx = order[i]
            let az = Double(i) / Double(n) * .pi * 2 + 0.55
            let omega = 2 * .pi * (0.5 + 0.35 * Double((noteIdx * 7919) % 100) / 100)
            return Bell(az: az, omega: omega, freq: notes[noteIdx],
                        nextOk: Double.random(in: 0...3))
        }
    }

    func start() {
        lastT = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func setWind(_ i: Int) {
        windIndex = ((i % winds.count) + winds.count) % winds.count
        // react immediately: open the gate and stir the bells
        nextWindOk = min(nextWindOk, simT + 0.4)
        let kick = winds[windIndex].pumpMul
        for k in bells.indices { bells[k].swingV += Double.random(in: -1...1) * kick * 2.4 }
    }

    // ---- cursor interaction (ported from the web pointerForces) ----
    var viewW: Double = 190
    var viewH: Double = 250

    private func fireBell(_ i: Int, vel: Double, swingImpulse: Double) {
        guard canRing() else { return }
        let pan = max(-0.7, min(0.7, sin(bells[i].az) * 0.6))
        onStrike?(bells[i].freq, vel, pan)
        recentRings.append(simT)
        bells[i].glow = 1
        bells[i].ripple = 0.01
        bells[i].last = simT
        bells[i].swingV += swingImpulse
    }

    // Brushing the cursor across the bells strums them (faster = louder).
    func brush(x: Double, y: Double, vx: Double, vy: Double) {
        let sp = (vx * vx + vy * vy).squareRoot()
        if sp < 320 { return }
        let u = min(viewW / 190, viewH / 250)
        let cx = viewW / 2
        let ringPx = min(viewW * 0.24, 58 * u)
        let y0 = viewH * 0.085
        let left = cx - ringPx - 30 * u, right = cx + ringPx + 30 * u
        if x < left - 30 || x > right + 30 || y < y0 || y > viewH * 0.85 + 30 { return }
        let hitW = 16 * u
        for i in bells.indices {
            let tx = cx + sin(bells[i].az) * ringPx + bells[i].swing * u * 1.6
            if abs(x - tx) < hitW && simT - bells[i].last > 0.17 {
                let vel = min(0.85, 0.14 + sp / 3200)
                fireBell(i, vel: vel, swingImpulse: (vx >= 0 ? 1.0 : -1.0) * (2 + sp / 350))
            }
        }
    }

    // Clicking rings the nearest bell.
    func tap(x: Double, y: Double) {
        let u = min(viewW / 190, viewH / 250)
        let cx = viewW / 2
        let ringPx = min(viewW * 0.24, 58 * u)
        var best = -1
        var bestD = 1e9
        for i in bells.indices {
            let tx = cx + sin(bells[i].az) * ringPx + bells[i].swing * u * 1.6
            let d = abs(x - tx)
            if d < bestD { bestD = d; best = i }
        }
        if best >= 0 && bestD < 26 * u && simT - bells[best].last > 0.12 {
            fireBell(best, vel: 0.5, swingImpulse: 3)
        }
    }

    private func smooth(_ t: Double, _ s: Double) -> Double {
        (sin(t * 0.9 + s) + sin(t * 2.33 + s * 1.7) + sin(t * 0.37 + s * 0.31)) / 3
    }

    private func canRing(_ n: Int = 1) -> Bool {
        recentRings = recentRings.filter { simT - $0 < 2.2 }
        return recentRings.count + n <= 3
    }

    private func tick() {
        let now = CACurrentMediaTime()
        var dt = now - lastT
        lastT = now
        if dt > 0.05 { dt = 0.05 }
        let t = now
        let w = winds[windIndex]

        // ---- wind field ----
        gustT += dt
        if t > nextGust {
            gustAmp = w.base * w.gustAmp * (1 + Double.random(in: 0...1))
            gustDur = 1.6 + Double.random(in: 0...2)
            gustT = 0
            nextGust = t + w.gustMin + Double.random(in: 0...(w.gustMax - w.gustMin))
        }
        gust = 0
        if gustT < gustDur {
            let p = gustT / gustDur
            gust = gustAmp * pow(sin(.pi * p), 2)
        }
        let turb = 0.8 + 0.35 * smooth(t * 0.9, 5.2)
        let base = w.base * (0.3 + 0.7 * (0.5 + 0.5 * smooth(t * 0.13, 1.1)))
        let speed = (base + gust) * turb
        pump = w.base * w.pumpMul * (0.55 + 0.45 * (0.5 + 0.5 * smooth(t * 0.21, 3.3)))
             + micLevel * 0.5 + gust * 0.35
        let dirA = 0.7 * sin(t * 0.05) + 0.35 * sin(t * 0.131 + 2)
        fx = speed * cos(dirA * 0.6)
        fz = speed * sin(dirA) * 0.5

        // ---- bells ----
        for i in bells.indices {
            var b = bells[i]
            let drive = fx * (0.5 + 0.13 * Double(i))
                      + fz * 0.2 * sin(b.az)
                      + pump * 7 * sin(t * b.omega + b.az)
            let a = drive * 2.2 - b.omega * b.omega * b.swing - 0.7 * b.swingV
            b.swingV += a * dt
            b.swing += b.swingV * dt

            if abs(b.swingV) > w.thresh && t > b.nextOk
                && (t > nextWindOk || micLevel > 0.2) && canRing() {
                let vel = min(0.5, 0.1 + abs(b.swingV) / 55)
                let pan = max(-0.7, min(0.7, sin(b.az) * 0.6))
                onStrike?(b.freq, vel, pan)
                recentRings.append(t)
                b.glow = 1
                b.ripple = 0.01
                b.last = t
                b.nextOk = t + w.perBellMin + pow(Double.random(in: 0...1), 1.5) * w.perBellRand
                nextWindOk = t + w.gateMin + pow(Double.random(in: 0...1), 1.6) * w.gateRand
            }
            b.glow = max(0, b.glow - dt * 1.6)
            if b.ripple > 0 { b.ripple = (b.ripple + dt * 2 > 1) ? 0 : b.ripple + dt * 2 }
            bells[i] = b
        }

        // ---- wind motes: only shown for your BREATH (mic on + blowing) ----
        // Not spawned by the ambient/idle wind — they exist to visualize the
        // real airflow you're adding, so they stay hidden otherwise.
        let intensity = micLevel
        if intensity > 0.16 && motes.count < 18 && Double.random(in: 0...1) < intensity * 0.5 {
            motes.append(Mote(x: -0.05,
                              y: 0.18 + Double.random(in: 0...0.55),
                              vx: 0.15 + Double.random(in: 0...1) * 0.5 * (0.4 + intensity),
                              life: 1,
                              wob: Double.random(in: 0...6)))
        }
        for i in motes.indices {
            motes[i].x += motes[i].vx * dt * (0.6 + speed)
            motes[i].y += sin(t * 3 + motes[i].wob) * 0.05 * dt
            motes[i].life -= dt * 0.5
        }
        motes.removeAll { $0.life <= 0 || $0.x > 1.1 }

        // Physics runs at 60 Hz (accurate strike timing), but we only trigger a
        // repaint every other tick — 30 fps is plenty for the gentle motion and
        // roughly halves CPU / battery from the transparent-window compositing.
        tickCount &+= 1
        if tickCount & 1 == 0 { frame &+= 1 }
    }
}
