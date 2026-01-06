import UIKit
import Capacitor
import AVFoundation
import Speech

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    // MARK: - App Launch
    func application(
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

        // ✅ Enable pinch-zoom in the Capacitor WKWebView (iOS app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let bridgeVC = self.window?.rootViewController as? CAPBridgeViewController,
               let webView = bridgeVC.webView {
                webView.scrollView.isScrollEnabled = true
                webView.scrollView.pinchGestureRecognizer?.isEnabled = true
            }
        }

        return true
    }

    // MARK: - Audio Session
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothA2DP]
            )
            try session.setActive(true)
            print("✅ Global audio session set")
        } catch {
            print("❌ Audio session error: \(error)")
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
