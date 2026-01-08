import Foundation
import Capacitor
import AVFoundation

@objc(NativeTTS)
public class NativeTTS: CAPPlugin, AVSpeechSynthesizerDelegate {

    // Keep synthesizer on main thread
    @MainActor private let synthesizer = AVSpeechSynthesizer()

    // Silent player to keep the audio session alive in background
    private var keepAlivePlayer: AVAudioPlayer?

    // MARK: - Plugin lifecycle

    public override func load() {
        super.load()

        Task { @MainActor in
            synthesizer.delegate = self
        }

        // Start silent audio once so iOS always treats the app as “audio playing”
        startKeepAliveAudio()
    }

    // MARK: - Audio session

    private func configureSessionForTTS() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Must match your background Audio capability
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            print("✅ NativeTTS: audio session ready")
        } catch {
            print("❌ NativeTTS: Failed to configure session: \(error)")
        }
    }

    // Loop a 1-second silent file to keep the session alive in background
    private func startKeepAliveAudio() {
        // Already playing? nothing to do
        if keepAlivePlayer?.isPlaying == true { return }

        guard let url = Bundle.main.url(forResource: "1-second-of-silence-2",
                                        withExtension: "mp3") else {
            print("❌ NativeTTS: could not find 1-second-of-silence-2.mp3 in bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1      // infinite loop
            player.volume = 0.0            // completely silent
            player.prepareToPlay()
            player.play()
            keepAlivePlayer = player
            print("✅ NativeTTS: keep-alive audio started")
        } catch {
            print("❌ NativeTTS: keep-alive audio error: \(error)")
        }
    }

    // MARK: - Public API (called from JS)

    @objc func speak(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        if text.isEmpty {
            call.reject("Missing 'text' parameter")
            return
        }

        // Stop STT while TTS plays
        NotificationCenter.default.post(name: .zenTTSWillSpeak, object: nil)

        // Ensure audio session + silent audio are active
        configureSessionForTTS()
        startKeepAliveAudio()

        let jsRate = call.getFloat("rate") ?? 1.0
        let jsVol  = call.getFloat("volume") ?? 1.0

        Task { @MainActor in
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }

            let utterance = AVSpeechUtterance(string: text)

            // Map 0.5–2.0 style JS rates into Apple’s allowed range
            let base = AVSpeechUtteranceDefaultSpeechRate
            let mapped = base * jsRate
            utterance.rate = min(
                max(mapped, AVSpeechUtteranceMinimumSpeechRate),
                AVSpeechUtteranceMaximumSpeechRate
            )

            utterance.volume = max(0.0, min(jsVol, 1.0))

            synthesizer.speak(utterance)
            call.resolve()
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        Task { @MainActor in
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            NotificationCenter.default.post(name: .zenTTSDidFinish, object: nil)
            call.resolve()
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        NotificationCenter.default.post(name: .zenTTSDidFinish, object: nil)
    }
}
