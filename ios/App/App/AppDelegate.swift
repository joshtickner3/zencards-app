import UIKit
import Capacitor
import AVFoundation
import Speech

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTaskRenewalTimer: Timer?

    // MARK: - App Launch
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Configure audio so we're allowed to play in the background
        configureAudioSession()

        // Ask for mic + speech permissions
        requestPermissions()

        // Enable pinch-zoom in the Capacitor WKWebView (iOS app)
        // Enable pinch-zoom...
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

    // MARK: - Background Execution

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("📱 [AppDelegate] App entered background")
        // Request background execution time to keep audio session alive
        // Renew every 2.5 minutes to keep it alive indefinitely while audio plays
        beginBackgroundTask()
        startBackgroundTaskRenewal()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        print("📱 [AppDelegate] App will enter foreground")
        // Clean up background task when returning to foreground
        stopBackgroundTaskRenewal()
        endBackgroundTask()
    }

    private func beginBackgroundTask() {
        // End any existing task first
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
        }
        
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "ZenCardsAudioPlayback") { [weak self] in
            print("�� [AppDelegate] Background task expiration handler called")
            self?.endBackgroundTask()
        }
        print("🔄 [AppDelegate] Background task started: \(backgroundTaskId.rawValue)")
    }

    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            print("🛑 [AppDelegate] Background task ended: \(backgroundTaskId.rawValue)")
            backgroundTaskId = .invalid
        }
    }

    private func startBackgroundTaskRenewal() {
        backgroundTaskRenewalTimer?.invalidate()
        
        print("⏰ [AppDelegate] Starting background task renewal timer")
        // Renew every 2.5 minutes (150 seconds) to keep background execution alive
        backgroundTaskRenewalTimer = Timer.scheduledTimer(withTimeInterval: 150.0, repeats: true) { [weak self] _ in
            print("🔄 [AppDelegate] Timer: Renewing background task...")
            self?.endBackgroundTask()
            self?.beginBackgroundTask()
        }
    }

    private func stopBackgroundTaskRenewal() {
        print("⏸ [AppDelegate] Stopping background task renewal timer")
        backgroundTaskRenewalTimer?.invalidate()
        backgroundTaskRenewalTimer = nil
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
            // Aggressive background audio configuration
            try session.setCategory(
                .playback,
                mode: .default,
                options: [
                    .duckOthers,              // Lower volume of other apps
                    .interruptSpokenAudioAndMixWithOthers  // Don't stop other audio, just mix
                ]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("✅ Background audio session configured (aggressive mode)")
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
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }
}
