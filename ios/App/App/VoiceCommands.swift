import Foundation
import Capacitor
import AVFoundation
import Speech

@objc(VoiceCommands)
public class VoiceCommands: CAPPlugin {

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var hasMicPermission = false
    private var hasSpeechPermission = false

    // MARK: - JS API

    // Called from JS to start listening
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

    // Called from JS to stop listening
    @objc func stop(_ call: CAPPluginCall) {
        stopListening()
        call.resolve()
    }

    // MARK: - Permissions

    private func requestPermissionsIfNeeded(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var micOK = false
        var speechOK = false

        // Microphone
        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            micOK = granted
            group.leave()
        }

        // Speech recognition
        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                speechOK = true
            default:
                speechOK = false
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.hasMicPermission = micOK
            self.hasSpeechPermission = speechOK
            completion(micOK && speechOK)
        }
    }

    // MARK: - Audio Session

    /// Configure the audio session so:
    /// - we can record (for STT)
    /// - audio keeps using AirPods / Bluetooth when connected
    /// - we do NOT force output back to the phone speaker
    private func configureAudioSessionForZenCards() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .duckOthers   // optional: gently lower other audio
                ]
            )

            // Don't overrideOutputAudioPort(.speaker) — that would force phone speaker.
            try audioSession.setActive(true, options: [])
        } catch {
            print("AudioSession config error: \(error)")
        }
    }

    // MARK: - Listening

    private func startListening() throws {
        // Reset any existing recognition first
        stopListening()

        // VERY IMPORTANT: configure the audio session before starting the engine
        configureAudioSessionForZenCards()

        // Create a new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(
                domain: "VoiceCommands",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"]
            )
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Remove any previous taps
        inputNode.removeTap(onBus: 0)

        // Install a new tap to feed audio into the recognition request
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) { [weak self] (buffer, _) in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Start the recognition task
        recognitionTask = speechRecognizer?.recognitionTask(
            with: recognitionRequest
        ) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString

                // Notify JS about speech results
                self.notifyListeners("speechResult", data: [
                    "text": text,
                    "isFinal": result.isFinal
                ])

                if result.isFinal {
                    self.restartListening()
                }
            }

            if let error = error {
                print("Speech recognition error: \(error)")
                self.restartListening()
            }
        }
    }

    private func stopListening() {
        // Stop recognition task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Stop recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        // Deactivate audio session so the system can route audio normally again
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func restartListening() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            do {
                try self.startListening()
            } catch {
                print("Failed to restart listening: \(error)")
            }
        }
    }
}
