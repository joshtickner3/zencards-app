import Foundation
import Capacitor
import AVFoundation
import Speech
import MediaPlayer

@objc(VoiceCommandsPlugin)
public class VoiceCommandsPlugin: CAPPlugin {


    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var suspendedForTTS = false

    private let remoteController = AudioRemoteController.shared

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
            self?.notifyListeners("remoteRating", data: ["rating": rating])
        }
        remoteController.configureRemoteCommands()
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
        stopListening(deactivateSession: true)
        remoteController.teardownRemoteCommands()
        call.resolve()
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
            // IMPORTANT: record-only session while listening
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("AudioSession listening config error: \(error)")
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
        let recordingFormat = inputNode.outputFormat(forBus: 0)

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

        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
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
