import AppKit
import AVFAudio

/// Provides haptic and audio feedback for key presses.
/// Respects user preferences stored in SettingsManager.
final class FeedbackEngine {

    static let shared = FeedbackEngine()

    // MARK: - Audio

    private var audioEngine: AVAudioEngine?
    private var playerNodes: [AVAudioPlayerNode] = []
    private var keyClickBuffer: AVAudioPCMBuffer?
    private var currentNodeIndex = 0
    private let nodePoolSize = 4
    private var isAudioReady = false

    // MARK: - Haptic

    private let hapticPerformer = NSHapticFeedbackManager.defaultPerformer

    // MARK: - Setup

    private init() {
        setupAudio()
    }

    private func setupAudio() {
        let engine = AVAudioEngine()

        // Use the engine's output format so everything is compatible
        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)

        // Try bundled sound first, then generate a synthetic click
        let buffer: AVAudioPCMBuffer?
        if let url = Bundle.main.url(forResource: "key-click", withExtension: "wav"),
           let file = try? AVAudioFile(forReading: url) {
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            if let buf {
                try? file.read(into: buf)
                buffer = buf
            } else {
                buffer = Self.generateSyntheticClick(format: outputFormat)
            }
        } else {
            buffer = Self.generateSyntheticClick(format: outputFormat)
        }

        guard let buffer else { return }

        let format = buffer.format

        for _ in 0..<nodePoolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            playerNodes.append(player)
        }

        do {
            engine.prepare()
            try engine.start()
            for player in playerNodes {
                player.play()
            }
            self.audioEngine = engine
            self.keyClickBuffer = buffer
            isAudioReady = true
        } catch {
            // Audio setup failed — degrade gracefully, no sound
            isAudioReady = false
        }
    }

    /// Generates a synthetic key-click sound (~30ms).
    private static func generateSyntheticClick(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let channels = format.channelCount
        let duration: Double = 0.03  // 30ms — long enough to be clearly audible
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }

        buffer.frameLength = frameCount

        guard let data = buffer.floatChannelData else { return nil }

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // Attack: sharp initial transient; Decay: fast exponential falloff
            let envelope = min(1.0, t * 8000) * exp(-t * 200)
            // Mix of high-frequency tick + low thud for a mechanical keyboard sound
            let highTick = sin(2 * .pi * 4000 * t) * 0.5
            let midTone = sin(2 * .pi * 1000 * t) * 0.3
            let lowThud = sin(2 * .pi * 200 * t) * 0.2
            let sample = Float((highTick + midTone + lowThud) * envelope * 0.7)

            // Write to all channels
            for ch in 0..<Int(channels) {
                data[ch][i] = sample
            }
        }

        return buffer
    }

    // MARK: - Play Feedback

    /// Play combined haptic + audio feedback for a key press down.
    func playKeyDownFeedback(settings: SettingsManager) {
        if settings.hapticFeedbackEnabled {
            playHaptic()
        }
        if settings.soundFeedbackEnabled {
            playKeyClick(volume: settings.soundVolume)
        }
    }

    /// Play lighter feedback for key release.
    func playKeyUpFeedback(settings: SettingsManager) {
        if settings.hapticFeedbackEnabled {
            playHaptic()
        }
        if settings.soundFeedbackEnabled {
            // Softer click on release
            playKeyClick(volume: settings.soundVolume * 0.5)
        }
    }

    private func playHaptic() {
        hapticPerformer.perform(.generic, performanceTime: .now)
    }

    private func playKeyClick(volume: Float) {
        guard isAudioReady, let buffer = keyClickBuffer else { return }

        let player = playerNodes[currentNodeIndex]
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        currentNodeIndex = (currentNodeIndex + 1) % nodePoolSize
    }
}
