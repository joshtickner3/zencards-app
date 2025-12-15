import Foundation
import Capacitor
import AVFoundation

@objc(NativeTTS)
public class NativeTTS: CAPPlugin, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()

    public override func load() {
        super.load()
        synthesizer.delegate = self
        // ✅ Don’t lock the session category here.
        // VoiceCommands may need playAndRecord; we’ll switch to playback only when speaking.
    }

    private func configureSessionForTTS() {
        let session = AVAudioSession.sharedInstance()
        do {
            // ✅ Playback-focused session for loud/clean TTS
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [
                    .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
        } catch {
            print("❌ NativeTTS: Failed to configure AVAudioSession for TTS: \(error)")
        }
    }

    @objc func speak(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        if text.isEmpty {
            call.reject("Missing 'text' parameter")
            return
        }
        
        let session = AVAudioSession.sharedInstance()
        do {
            // Force a strong "speech playback" session for the utterance
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("❌ NativeTTS: speak() audio session set failed: \(error)")
        }


        // ✅ Ensure session is in playback mode right before speaking
        configureSessionForTTS()

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

    @objc func stop(_ call: CAPPluginCall) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        call.resolve()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("NativeTTS: finished utterance")
    }
}
