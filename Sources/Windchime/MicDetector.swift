import Foundation
import AVFoundation
import Accelerate

// Breath detector — a Swift/Accelerate port of renderer/mic.js.
// Blowing across a mic is heavy broadband LOW-frequency rumble; speech and
// typing sit mostly in the mids. We score (low-band − ½·mid-band) energy
// against a slowly-adapting noise floor (fast fall, slow rise), so a breath
// reads as a gust but a conversation doesn't. Audio is analysed and discarded.
final class MicDetector {
    private let engine = AVAudioEngine()
    private let fftSize = 2048
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup?
    private var window: [Float]

    private var lowFloor: Double = 0.04
    private var midFloor: Double = 0.04
    private(set) var level: Double = 0
    private var running = false

    var onLevel: ((Double) -> Void)?

    init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    var isActive: Bool { running }

    func start() {
        guard !running else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self = self, granted else { return }
            DispatchQueue.main.async { self.beginTap() }
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        level = 0
        onLevel?(0)
    }

    private func beginTap() {
        let input = engine.inputNode
        let fmt = input.inputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else { return }
        let rate = fmt.sampleRate
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: fmt) { [weak self] buf, _ in
            self?.process(buf, rate: rate)
        }
        engine.prepare()
        do { try engine.start(); running = true }
        catch { NSLog("Windchime mic start failed: \(error)") }
    }

    private func bandAvg(_ mags: [Float], _ fromHz: Double, _ toHz: Double, _ binHz: Double) -> Double {
        let a = max(1, Int(fromHz / binHz))
        let b = min(mags.count - 1, Int(ceil(toHz / binHz)))
        if b < a { return 0 }
        var sum: Double = 0
        for i in a...b { sum += Double(mags[i]) }
        return sum / Double(b - a + 1)
    }

    private func process(_ buf: AVAudioPCMBuffer, rate: Double) {
        guard let ch = buf.floatChannelData?[0], let setup = fftSetup else { return }
        let n = min(Int(buf.frameLength), fftSize)
        if n < fftSize / 2 { return }

        var samples = [Float](repeating: 0, count: fftSize)
        for i in 0..<n { samples[i] = ch[i] }
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        let half = fftSize / 2
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)

        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }
        // normalize magnitudes to a roughly 0..1 range comparable to the web
        // build's getByteFrequencyData scale
        var scale = Float(1.0 / Double(fftSize))
        vDSP_vsmul(mags, 1, &scale, &mags, 1, vDSP_Length(half))

        let binHz = rate / Double(fftSize)
        let low = bandAvg(mags, 30, 250, binHz)
        let mid = bandAvg(mags, 450, 2200, binHz)

        // adaptive room floor: fall fast, rise slowly
        lowFloor += (low - lowFloor) * (low < lowFloor ? 0.3 : 0.0015)
        midFloor += (mid - midFloor) * (mid < midFloor ? 0.3 : 0.0015)

        let excess = max(0, low - lowFloor) - 0.5 * max(0, mid - midFloor) - 0.02
        let target = min(1, max(0, excess / 0.18))

        // fast attack, slow release
        level += (target - level) * (target > level ? 0.35 : 0.05)
        let out = level
        DispatchQueue.main.async { self.onLevel?(out) }
    }
}
