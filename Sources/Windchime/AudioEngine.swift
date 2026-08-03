import Foundation
import AVFoundation
import os

// Bell synthesis — a Swift/AVAudioEngine port of renderer/audio.js.
// Each strike is a small stack of inharmonic partials (real brass-bell mode
// ratios 1 : 2.71 : 4.95) with exponential decay envelopes, plus a filtered
// noise "knock" at the moment of contact, fed through a reverb. All generated
// live in an AVAudioSourceNode render callback — no samples.
final class AudioEngine {
    private let rate: Double = 44100
    private let engine = AVAudioEngine()
    private var srcNode: AVAudioSourceNode!
    private let reverb = AVAudioUnitReverb()

    // main thread appends strikes; audio thread drains them (brief lock only).
    private let lockPtr = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var pending: [(Double, Double, Double)] = []   // freq, vel, pan
    private var voices: [Voice] = []
    private var rng: UInt64 = 0x9E3779B97F4A7C15

    var volume: Double = 0.7 {
        didSet { engine.mainMixerNode.outputVolume = Float(volume) }
    }

    private struct Partial { var phase: Double; var inc: Double; var amp: Double; var decay: Double }

    private struct Voice {
        var partials: [Partial]
        var knockAmp: Double
        var knockDecay: Double
        var knockLeft: Int
        // biquad bandpass (normalized coeffs) + state, for the knock
        var b0: Double; var b1: Double; var b2: Double; var a1: Double; var a2: Double
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var lGain: Double; var rGain: Double
        var age = 0

        mutating func sample(noise: Double) -> Double {
            var s = 0.0
            for i in partials.indices {
                s += sin(partials[i].phase) * partials[i].amp
                partials[i].phase += partials[i].inc
                partials[i].amp *= partials[i].decay
            }
            if knockLeft > 0 {
                let y = b0 * noise + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = noise; y2 = y1; y1 = y
                s += y * knockAmp
                knockAmp *= knockDecay
                knockLeft -= 1
            }
            age += 1
            return s
        }

        var finished: Bool {
            knockLeft <= 0 && partials.allSatisfy { $0.amp < 0.00005 }
        }
    }

    init() {
        lockPtr.initialize(to: os_unfair_lock())
        setup()
    }

    private func setup() {
        engine.attach(reverb)
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 32

        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        srcNode = AVAudioSourceNode(format: fmt) { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self = self else { return noErr }
            return self.render(Int(frameCount), abl)
        }
        engine.attach(srcNode)
        engine.connect(srcNode, to: reverb, format: fmt)
        engine.connect(reverb, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = Float(volume)
    }

    func start() {
        engine.prepare()
        do { try engine.start() } catch { NSLog("Windchime audio start failed: \(error)") }
    }

    func strike(_ freq: Double, _ vel: Double, _ pan: Double) {
        os_unfair_lock_lock(lockPtr)
        pending.append((freq, vel, pan))
        os_unfair_lock_unlock(lockPtr)
    }

    // fast lock-free noise for the audio thread (xorshift), −1...1
    private func nextNoise() -> Double {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Double(Int64(bitPattern: rng)) / Double(Int64.max)
    }

    private func makeVoice(_ freq: Double, _ vel0: Double, _ pan0: Double) -> Voice {
        let vel = max(0.05, min(1, vel0))
        let level = pow(vel, 1.35) * 0.42
        let decay = 1.3 * (0.7 + 0.5 * vel)
        let detune = 1 + (nextNoise() * 0.002)
        let specs: [(Double, Double, Double)] = [(1, 1, 1), (2.71, 0.38, 0.55), (4.95, 0.16, 0.35)]
        var partials: [Partial] = []
        for (ratio, amp, dMul) in specs {
            let f = freq * ratio * detune
            if f > 14000 { continue }
            let a0 = level * amp
            let dur = max(0.08, decay * dMul)
            let dps = pow(0.0001 / a0, 1.0 / (dur * rate))
            partials.append(Partial(phase: 0, inc: 2 * .pi * f / rate, amp: a0, decay: dps))
        }
        // knock bandpass (RBJ cookbook, constant skirt gain)
        let fc = min(9000, freq * 2.71)
        let w0 = 2 * .pi * fc / rate
        let alpha = sin(w0) / (2 * 1.4)
        let a0f = 1 + alpha
        let knockAmp = level * 0.2
        let knockDecay = pow(0.0001 / max(knockAmp, 1e-6), 1.0 / (0.05 * rate))
        let pan = max(-1, min(1, pan0))
        let ang = (pan + 1) * 0.25 * .pi   // equal-power pan
        return Voice(
            partials: partials, knockAmp: knockAmp, knockDecay: knockDecay,
            knockLeft: Int(0.06 * rate),
            b0: alpha / a0f, b1: 0, b2: -alpha / a0f,
            a1: (-2 * cos(w0)) / a0f, a2: (1 - alpha) / a0f,
            lGain: cos(ang), rGain: sin(ang))
    }

    private func render(_ frames: Int, _ abl: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        os_unfair_lock_lock(lockPtr)
        let reqs = pending
        pending.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(lockPtr)
        for r in reqs where voices.count < 40 { voices.append(makeVoice(r.0, r.1, r.2)) }

        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        let L = bufs[0].mData!.assumingMemoryBound(to: Float.self)
        let R = bufs[1].mData!.assumingMemoryBound(to: Float.self)
        let maxAge = Int(4 * rate)

        for frame in 0..<frames {
            let noise = nextNoise()
            var l = 0.0, r = 0.0
            for i in voices.indices {
                let s = voices[i].sample(noise: noise)
                l += s * voices[i].lGain
                r += s * voices[i].rGain
            }
            L[frame] = Float(tanh(l))   // gentle soft-limit
            R[frame] = Float(tanh(r))
        }
        voices.removeAll { $0.age > maxAge || $0.finished }
        return noErr
    }
}
