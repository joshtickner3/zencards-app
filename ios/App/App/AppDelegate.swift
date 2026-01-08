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

        // Configure audio so we’re allowed to play in the background
        configureAudioSession()

        // Ask for mic + speech permissions
        requestPermissions()

        // Enable pinch-zoom in the Capacitor WKWebView (iOS app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard
                let bridgeVC = self?.window?.rootViewController as? CAPBridgeViewController,
                let webView = bridgeVC.webView
            else { return }

            webView.scrollView.isScrollEnabled = true
            webView.scrollView.pinchGestureRecognizer?.isEnabled = true
        }

        return true
    }

    // MARK: - Permissions

    private func requestPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Microphone permission granted? \(granted)")
        }

        SFSpeechRecognizer.requestAuthorization { status in
            print("Speech recognition authorization: \(status.rawValue)")
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothA2DP, .duckOthers]
            )

            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("✅ Background audio session configured")
        } catch {
            print("❌ Audio session error: \(error)")
        }
    }

    // Keep the audio session configured when we go to background / foreground.
    func applicationDidEnterBackground(_ application: UIApplication) {
        configureAudioSession()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        configureAudioSession()
    }

    // MARK: - URL / Deep Link Handling (Capacitor)

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }
}
