import UIKit
import Capacitor
import AVFoundation
import Speech

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTaskTimer: DispatchSourceTimer?
    private let backgroundQueue = DispatchQueue(label: "com.zencards.background-task")

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
        beginBackgroundTaskWithRenewal()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        print("�� [AppDelegate] App will enter foreground")
        endBackgroundTaskWithRenewal()
    }

    private func beginBackgroundTaskWithRenewal() {
        // End any existing task and timer first
        endBackgroundTaskWithRenewal()
        
        // Start initial background task
        beginBackgroundTask()
        
        // Create a GCD timer (more reliable than NSTimer for background tasks)
        let timer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        timer.schedule(deadline: .now() + 150, repeating: 150.0, leeway: .seconds(5))
        
        timer.setEventHandler { [weak self] in
            print("🔄 [AppDelegate] GCD Timer: Renewing background task...")
            self?.endBackgroundTask()
            self?.beginBackgroundTask()
        }
        
        backgroundTaskTimer = timer
        timer.resume()
        
        print("⏰ [AppDelegate] Starting background task renewal with GCD (every 150s)")
    }

    private func endBackgroundTaskWithRenewal() {
        print("⏸ [AppDelegate] Stopping background task and timer")
        
        // Cancel the timer
        if let timer = backgroundTaskTimer {
            timer.cancel()
            backgroundTaskTimer = nil
        }
        
        // End the background task
        endBackgroundTask()
    }

    private func beginBackgroundTask() {
        // End any existing task first to avoid warnings
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
        }
        
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "ZenCardsAudioPlayback") { [weak self] in
            print("🛑 [AppDelegate] Background task expiration handler fired")
            // Immediately start a new one to keep going
            self?.beginBackgroundTask()
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
            // Use .playAndRecord so we can handle BOTH playback and voice input
            // This is essential for hands-free mode where audio plays while listening for commands
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .defaultToSpeaker,  // route to speaker not receiver
                    .duckOthers         // duck other audio
                ]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("✅ [AppDelegate] Background audio session configured for .playAndRecord")
        } catch {
            print("❌ [AppDelegate] Audio session error: \(error)")
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
