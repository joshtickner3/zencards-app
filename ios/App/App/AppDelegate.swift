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

            // ✅ Register custom plugins here

            // Existing zoom behavior
            webView.scrollView.isScrollEnabled = true
            webView.scrollView.pinchGestureRecognizer?.isEnabled = true
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        enforcePreferredRouting()
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
            // Use playAndRecord so:
            // - you can use the mic (hands-free)
            // - you can override output to speaker when CarPlay tries to hijack
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [
                    .defaultToSpeaker,
                    .allowBluetooth,        // allows AirPods/BT mics
                    .allowBluetoothA2DP     // high-quality BT audio (AirPods)
                    // (no .allowAirPlay)
                    // (no .duckOthers)
                    // (mixWithOthers optional; leave off unless you want to mix with other apps)
                ]
            )

            try session.setActive(true)
            print("🔊 [AppDelegate] Audio session configured: playAndRecord + measurement")

        } catch {
            print("❌ [AppDelegate] Audio session error: \(error)")
        }

        // Keep routing correct if CarPlay connects mid-session
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        // Let GPS/Siri interrupt us; we can resume after
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        // Apply initial routing rule right away
        enforcePreferredRouting()

    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            print("🛑 [Audio] Interrupted (GPS/Siri/etc). You may pause TTS here if needed.")
            // Optional: post a notification to your JS/web layer to pause audio

        case .ended:
            enforcePreferredRouting()

            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            print("✅ [Audio] Interruption ended. shouldResume=\(options.contains(.shouldResume))")

            // Optional: resume if your player was running and shouldResume is true

        @unknown default:
            break
        }
    }


    @objc private func handleRouteChange(_ notification: Notification) {
        enforcePreferredRouting()
    }

    private func enforcePreferredRouting() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        let hasCarPlay = outputs.contains { $0.portType == .carAudio }

        do {
            if hasCarPlay {
                // Block CarPlay → force speaker
                try session.overrideOutputAudioPort(.speaker)
                print("🚗🔇 [Audio] CarPlay detected → forcing iPhone speaker")
            } else {
                // Allow normal routing:
                // - Headphones/AirPods if connected
                // - Otherwise speaker (because of .defaultToSpeaker)
                try session.overrideOutputAudioPort(.none)
                print("✅ [Audio] No CarPlay → normal routing (headphones if present, else speaker)")
            }
        } catch {
            print("❌ [Audio] Output override failed:", error)
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
