import Foundation
import Capacitor
import AVFoundation

@objc(NativeTTS)
public class NativeTTS: CAPPlugin, AVSpeechSynthesizerDelegate {

    // Keep synthesizer on main thread (avoids Sendable/concurrency warnings)
    @MainActor private let synthesizer = AVSpeechSynthesizer()

    // 👇 NEW: silent keep-alive audio player
    private var keepAlivePlayer: AVAudioPlayer?

    public override func load() {
        super.load()
        Task { @MainActor in
            synthesizer.delegate = self
        }
    }

    private func configureSessionForTTS() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Simple, background-safe playback config
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            print("✅ NativeTTS: audio session ready")
        } catch {
            print("❌ NativeTTS: Failed to configure session: \(error)")
        }
    }

    // 👇 NEW: start silent looping audio to keep background session alive
    private func startKeepAliveAudio() {
        // Already running?
        if let player = keepAlivePlayer {
            if !player.isPlaying {
                player.play()
            }
            return
        }

        // NOTE: change the extension here if your file is not .m4a
        guard let url = Bundle.main.url(forResource: "1-second-of-silence 2",
                                        withExtension: "mp3") else {
            print("⚠️ NativeTTS: could not find 1-second-of-silence 2.mp3 in bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1      // loop forever
            player.volume = 0.0            // totally silent
            player.prepareToPlay()
            player.play()
            keepAlivePlayer = player
            print("✅ NativeTTS: keep-alive audio started")
        } catch {
            print("❌ NativeTTS: keep-alive audio error: \(error)")
        }
    }

    // 👇 NEW: stop the silent audio
    private func stopKeepAliveAudio() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        print("ℹ️ NativeTTS: keep-alive audio stopped")
    }

    @objc func speak(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        if text.isEmpty {
            call.reject("Missing 'text' parameter")
            return
        }

        // Stop STT while TTS plays
        NotificationCenter.default.post(name: .zenTTSWillSpeak, object: nil)

        configureSessionForTTS()

        // 👇 NEW: start silent loop so audio stays alive in background
        startKeepAliveAudio()

        // JS is sending a rate around 0.5–2.0 — map that safely
        let jsRate = call.getFloat("rate") ?? 1.0
        let jsVol  = call.getFloat("volume") ?? 1.0

        Task { @MainActor in
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }

            let utterance = AVSpeechUtterance(string: text)

            // ✅ Map 0.5–2.0 from JS into iOS' allowed range
            let base = AVSpeechUtteranceDefaultSpeechRate
            let mapped = base * jsRate
            utterance.rate = min(
                max(mapped, AVSpeechUtteranceMinimumSpeechRate),
                AVSpeechUtteranceMaximumSpeechRate
            )

            utterance.volume = max(0.0, min(jsVol, 1.0))

            synthesizer.speak(utterance)

            // Resolve immediately – JS already uses generation guards
            call.resolve()
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        Task { @MainActor in
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            // 👇 NEW: stop the silent audio when JS tells us to stop
            stopKeepAliveAudio()

            NotificationCenter.default.post(name: .zenTTSDidFinish, object: nil)
            call.resolve()
        }
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        // 👇 NEW: stop silent audio when speech naturally finishes
        stopKeepAliveAudio()

        NotificationCenter.default.post(name: .zenTTSDidFinish, object: nil)
    }
}
