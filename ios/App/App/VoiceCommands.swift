import Foundation
import Capacitor
import AVFoundation
import Speech

@objc(VoiceCommandsPlugin)
public class VoiceCommandsPlugin: CAPPlugin, CAPBridgedPlugin {

    // Capacitor 7 bridge metadata
    public let identifier = "VoiceCommandsPlugin"
    public let jsName = "VoiceCommands"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise)
    ]
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var suspendedForTTS = false

    public override func load() {
        super.load()
        print("✅ VoiceCommandsPlugin loaded into Capacitor bridge")

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onTTSWillSpeak),
                                               name: .zenTTSWillSpeak,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onTTSDidFinish),
                                               name: .zenTTSDidFinish,
                                               object: nil)
    }

    // MARK: - JS API

    @objc func start(_ call: CAPPluginCall) {
        requestPermissionsIfNeeded { granted in
            if !granted {
                call.reject("Permissions for microphone / speech not granted")
                return
            }

            DispatchQueue.main.async {
                do {
                    try self.startListening()
                    call.resolve()
                } catch {
                    call.reject("Failed to start listening: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        stopListening(deactivateSession: false)

        call.resolve()
    }
    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(["available": true])
    }


    // MARK: - Permissions

    private func requestPermissionsIfNeeded(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var micOK = false
        var speechOK = false

        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            micOK = granted
            group.leave()
        }

        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechOK = (status == .authorized)
            group.leave()
        }

        group.notify(queue: .main) { completion(micOK && speechOK) }
    }

    // MARK: - Audio Session (LISTENING)

    private func configureAudioSessionForListening() {
        let session = AVAudioSession.sharedInstance()
        do {
            // ✅ Do NOT call setCategory here.
            // AppDelegate owns the audio session category/options.
            try session.setActive(true)

            // ✅ Re-apply “never route to CarPlay” every time we start listening
            enforceNoCarPlayOutput()

            print("🎤 [VoiceCommands] Audio session activated for listening (no category override)")
        } catch {
            print("❌ [VoiceCommands] AudioSession activate error: \(error)")
        }
    }

    private func enforceNoCarPlayOutput() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        let hasCarAudio = outputs.contains { $0.portType == .carAudio }

        // If CarPlay/car head-unit is the route, force iPhone speaker.
        if hasCarAudio {
            do {
                try session.overrideOutputAudioPort(.speaker)
                print("🚗🔇 [VoiceCommands] Car audio detected → forcing iPhone speaker")
            } catch {
                print("❌ [VoiceCommands] Failed to override output:", error)
            }
        } else {
            // Remove override so AirPods/headphones work normally when connected
            do {
                try session.overrideOutputAudioPort(.none)
            } catch { }
        }
    }


    // MARK: - Listening

    private func startListening() throws {
        stopListening(deactivateSession: false)

        configureAudioSessionForListening()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "VoiceCommands", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                self.notifyListeners("speechResult", data: [
                    "text": result.bestTranscription.formattedString,
                    "isFinal": result.isFinal
                ])
            }

            if let error = error {
                print("Speech recognition error: \(error)")
            }
        }
    }

    private func stopListening(deactivateSession: Bool) {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - TTS coordination

    @objc private func onTTSWillSpeak() {
        if audioEngine.isRunning {
            suspendedForTTS = true
            // Stop listening but DON'T deactivate session (prevents volume shift + sluggishness)
            stopListening(deactivateSession: false)
        }
    }

    @objc private func onTTSDidFinish() {
        guard suspendedForTTS else { return }
        suspendedForTTS = false

        // Let the system settle before re-activating the mic session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            try? self.startListening()
        }
    }
}
