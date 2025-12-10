import UIKit
import Capacitor
import AVFoundation
import Speech

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    // MARK: - App Launch
    func application(9
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Configure audio so WebView / TTS can keep playing in the background
        configureAudioSession()

        // Ask for microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Microphone permission granted? \(granted)")
        }

        // Ask for speech-recognition permission
        SFSpeechRecognizer.requestAuthorization { status in
            print("Speech recognition authorization: \(status.rawValue)")
        }

        return true
    }

    // MARK: - Audio Session
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .duckOthers]
            )
            try session.setActive(true)
            print("✅ AppDelegate: AVAudioSession configured for background playback")
        } catch {
            print("❌ AppDelegate: Failed to configure AVAudioSession: \(error)")
        }
    }

    // MARK: - URL / Deep Link Handling (Capacitor)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        return ApplicationDelegateProxy.shared.application(
            app,
            open: url,
            options: options
        )
    }
}
