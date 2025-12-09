import Foundation
import Capacitor
import AVFoundation

@objc(NativeTTS)
public class NativeTTS: CAPPlugin, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()

    public override func load() {
        super.load()
        synthesizer.delegate = self

        // Make sure audio session is ready for playback.
        // Safe to do here even though AppDelegate configures it too.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .duckOthers]
            )
            try session.setActive(true)
            print("✅ NativeTTS: AVAudioSession ready for TTS")
        } catch {
            print("❌ NativeTTS: Failed to configure AVAudioSession: \(error)")
        }
    }

    // MARK: - Plugin methods

    /// Speak text using AVSpeechSynthesizer
    @objc func speak(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        if text.isEmpty {
            call.reject("Missing 'text' parameter")
            return
        }

        let rate = call.getFloat("rate") ?? AVSpeechUtteranceDefaultSpeechRate
        let volume = call.getFloat("volume") ?? 1.0

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.volume = volume

        synthesizer.speak(utterance)
        call.resolve()
    }

    /// Stop speaking immediately
    @objc func stop(_ call: CAPPluginCall) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        call.resolve()
    }

    // Optional: delegate callback just for logging
    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        print("NativeTTS: finished utterance")
    }
}
