import Foundation
import Capacitor
import AVFoundation
import Speech
import MediaPlayer

@objc(VoiceCommands)
public class VoiceCommands: CAPPlugin {

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var suspendedForTTS = false
    private var hasMicPermission = false
    private var hasSpeechPermission = false
   


    // Remote control helper (AudioRemoteController.swift)
    private let remoteController = AudioRemoteController.shared

    // Called once when the plugin is loaded
    public override func load() {
            super.load()

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(onTTSWillSpeak),
                                                   name: .zenTTSWillSpeak,
                                                   object: nil)

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(onTTSDidFinish),
                                                   name: .zenTTSDidFinish,
                                                   object: nil)

            remoteController.onRatingChosen = { [weak self] rating in
                guard let self = self else { return }
                self.notifyListeners("remoteRating", data: ["rating": rating])
            }
            remoteController.configureRemoteCommands()
        }

        @objc private func onTTSWillSpeak() {
            if audioEngine.isRunning {
                suspendedForTTS = true
                stopListening()
            }
        }

        @objc private func onTTSDidFinish() {
            guard suspendedForTTS else { return }
            suspendedForTTS = false
            try? startListening()
        }


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
        remoteController.teardownRemoteCommands()
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

    /// Show something in the system Now Playing center (CarPlay / BT head units).
    private func setNowPlayingInfo(title: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "ZenCards",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
    }

    /// Configure the audio session so:
    /// - we can record (for STT)
    /// - audio keeps using AirPods / Bluetooth / CarPlay
    /// - we do NOT force output back to the phone speaker
    private func configureAudioSessionForZenCards() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP
                ]
            )

            // Prefer the built-in mic so AirPods stay in A2DP playback (no "call mode" volume drop)
            if let builtInMic = audioSession.availableInputs?
                .first(where: { $0.portType == .builtInMic }) {
                try audioSession.setPreferredInput(builtInMic)
            }

            try audioSession.setActive(true, options: [])
            setNowPlayingInfo(title: "Studying flashcards")
        } catch {
            print("AudioSession config error: \(error)")
        }
    }


    // MARK: - Listening

    private func startListening() throws {
        // Reset any existing recognition first
        stopListening()

        // Configure the audio session before starting the engine
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

              
            }

            if let error = error {
                print("Speech recognition error: \(error)")
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
}
