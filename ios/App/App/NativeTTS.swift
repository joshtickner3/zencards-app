import Foundation
import Capacitor
import AVFoundation

@objc(NativeTTS)
public class NativeTTS: CAPPlugin, AVSpeechSynthesizerDelegate {

    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()

    public override func load() {
        super.load()
        synthesizer.delegate = self
    }

    private func configureSessionForTTS() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            try session.setActive(true, options: [])
            // If you want to force speaker when NOT using AirPods:
            // try session.overrideOutputAudioPort(.speaker)
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

        // Tell VoiceCommands to stop listening while TTS plays
        NotificationCenter.default.post(name: .zenTTSWillSpeak, object: nil)

        configureSessionForTTS()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = call.getFloat("rate") ?? AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = call.getFloat("volume") ?? 1.0

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        synthesizer.speak(utterance)
        call.resolve()
    }

    @objc func stop(_ call: CAPPluginCall) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        NotificationCenter.default.post(name: .zenTTSDidFinish, object: nil)
        call.resolve()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        NotificationCenter.default.post(name: .zenTTSDidFinish, object: nil)
    }
}
