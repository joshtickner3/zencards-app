import Foundation
import Capacitor
import AVFoundation

@objc(NativeTTS)
public class NativeTTS: CAPPlugin, AVSpeechSynthesizerDelegate {

    // Keep synthesizer on main thread (avoids Sendable/concurrency warnings)
    @MainActor private let synthesizer = AVSpeechSynthesizer()

    public override func load() {
        super.load()
        Task { @MainActor in
            synthesizer.delegate = self
        }
    }

    private func configureSessionForTTS() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Strong, clean playback session (NO ducking)
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            try session.setActive(true, options: [])
        } catch {
            print("❌ NativeTTS: Failed to configure session: \(error)")
        }
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

        let rate = call.getFloat("rate") ?? AVSpeechUtteranceDefaultSpeechRate
        let vol  = call.getFloat("volume") ?? 1.0

        Task { @MainActor in
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = rate
            utterance.volume = vol

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

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        NotificationCenter.default.post(name: .zenTTSDidFinish, object: nil)
    }
}
