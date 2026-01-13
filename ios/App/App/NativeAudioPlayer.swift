import Foundation
import Capacitor
import AVFoundation
import MediaPlayer

@objc(NativeAudioPlayerPlugin)
public class NativeAudioPlayerPlugin: CAPPlugin, CAPBridgedPlugin {

    // MARK: - Capacitor 7 bridge metadata

    public let identifier = "NativeAudioPlayerPlugin"
    public let jsName = "NativeAudioPlayer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setQueue",   returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enqueue",    returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play",       returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause",      returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "skipToNext", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop",       returnType: CAPPluginReturnPromise),
        // simple debug method to prove the bridge works
        CAPPluginMethod(name: "debugPing",  returnType: CAPPluginReturnPromise)
    ]


    // MARK: - State

    private var player: AVQueuePlayer?
    private var currentIndex: Int = 0

    // MARK: - Lifecycle

    public override func load() {
        super.load()
        print("🎧 [NativeAudioPlayer] load() – plugin constructed and added to bridge")

        configureAudioSession()
        setupRemoteCommandCenter()
        registerPlayerObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("🧹 [NativeAudioPlayer] deinit – observers removed")
    }

    // MARK: - Audio Session

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            print("🎧 [NativeAudioPlayer] configureAudioSession() called")

            // Minimal, safe playback configuration
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            print("✅ [NativeAudioPlayer] AVAudioSession configured")
            print("   category=\(session.category.rawValue), mode=\(session.mode.rawValue)")

            let route = session.currentRoute
            print("🔊 [NativeAudioPlayer] Current output route: \(route)")
            for output in route.outputs {
                print("   ↳ portType=\(output.portType.rawValue), name=\(output.portName)")
            }
        } catch {
            print("❌ [NativeAudioPlayer] AudioSession error: \(error)")
        }
    }


    // MARK: - Remote controls

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            print("▶️ [NativeAudioPlayer] Remote playCommand")
            self?.player?.play()
            self?.notifyListeners("remoteCommand", data: ["type": "play"])
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            print("⏸ [NativeAudioPlayer] Remote pauseCommand")
            self?.player?.pause()
            self?.notifyListeners("remoteCommand", data: ["type": "pause"])
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            print("⏭ [NativeAudioPlayer] Remote nextTrackCommand")
            self?.skipToNextInternal()
            self?.notifyListeners("remoteCommand", data: ["type": "next"])
            return .success
        }

        print("🎛 [NativeAudioPlayer] RemoteCommandCenter configured")
    }

    // MARK: - Notifications

    private func registerPlayerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidFinishPlaying(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemFailedToPlayToEnd(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )

        print("🔔 [NativeAudioPlayer] Registered AVPlayerItem notifications")
    }

    @objc private func itemDidFinishPlaying(_ notification: Notification) {
        currentIndex += 1
        print("✅ [NativeAudioPlayer] Item finished – new index: \(currentIndex)")
        notifyListeners("trackEnded", data: ["index": currentIndex])
    }

    @objc private func itemFailedToPlayToEnd(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            print("❌ [NativeAudioPlayer] Item failed to play: \(error.localizedDescription)")
        } else {
            print("❌ [NativeAudioPlayer] Item failed to play (no error info)")
        }
    }

    private func skipToNextInternal() {
        guard let player = player else {
            print("⚠️ [NativeAudioPlayer] skipToNextInternal called but player is nil")
            return
        }

        player.advanceToNextItem()
        currentIndex += 1
        print("⏭ [NativeAudioPlayer] skipToNextInternal – index now \(currentIndex)")
        notifyListeners("trackEnded", data: ["index": currentIndex])
    }

    // MARK: - Plugin methods (called from JS)

    /// Simple "are we alive?" method
    @objc func debugPing(_ call: CAPPluginCall) {
        print("🔔 [NativeAudioPlayer] debugPing() from JS")
        call.resolve([
            "ok": true,
            "message": "NativeAudioPlayer is reachable from JS"
        ])
    }

    @objc func setQueue(_ call: CAPPluginCall) {
        guard let urls = call.getArray("urls", String.self), !urls.isEmpty else {
            print("⚠️ [NativeAudioPlayer] setQueue: missing or empty urls")
            call.reject("Missing or empty urls")
            return
        }

        print("🎧 [NativeAudioPlayer] setQueue() called with \(urls.count) urls")
        urls.forEach { print("   ↳ queue URL: \($0)") }

        DispatchQueue.main.async {
            self.currentIndex = 0

            // Build AVPlayerItems from the REAL URLs we got from JS
            let items: [AVPlayerItem] = urls.compactMap { urlString in
                guard let url = URL(string: urlString) else {
                    print("⚠️ [NativeAudioPlayer] Invalid URL in setQueue: \(urlString)")
                    return nil
                }
                return AVPlayerItem(url: url)
            }

            guard !items.isEmpty else {
                print("❌ [NativeAudioPlayer] setQueue: no valid URLs after parsing")
                call.reject("No valid URLs in queue")
                return
            }

            let player = AVQueuePlayer(items: items)
            player.actionAtItemEnd = .advance
            player.automaticallyWaitsToMinimizeStalling = false

            self.player = player

            // Optional: set Now Playing info for Control Center tile
            if let first = items.first {
                let infoCenter = MPNowPlayingInfoCenter.default()
                let duration = CMTimeGetSeconds(first.asset.duration)
                infoCenter.nowPlayingInfo = [
                    MPMediaItemPropertyTitle: "ZenCards Audio",
                    MPMediaItemPropertyPlaybackDuration: duration,
                    MPNowPlayingInfoPropertyElapsedPlaybackTime: 0
                ]
            }

            print("✅ [NativeAudioPlayer] Queue created with \(items.count) AVPlayerItems")
            call.resolve()
        }
    }

    @objc func enqueue(_ call: CAPPluginCall) {
        guard let urls = call.getArray("urls", String.self), !urls.isEmpty else {
            print("⚠️ [NativeAudioPlayer] enqueue: missing or empty urls")
            call.reject("Missing or empty urls")
            return
        }

        print("🎧 [NativeAudioPlayer] enqueue() called with \(urls.count) urls")

        DispatchQueue.main.async {
            guard let player = self.player else {
                print("⚠️ [NativeAudioPlayer] enqueue called but player is nil – call setQueue first")
                call.reject("Queue not initialized. Call setQueue first.")
                return
            }

            for urlString in urls {
                guard let url = URL(string: urlString) else {
                    print("⚠️ [NativeAudioPlayer] Invalid URL string in enqueue: \(urlString)")
                    continue
                }
                print("   ↳ enqueue URL: \(url.absoluteString)")
                let item = AVPlayerItem(url: url)
                player.insert(item, after: nil)
            }

            call.resolve()
        }
    }

    @objc func play(_ call: CAPPluginCall) {
        print("▶️ [NativeAudioPlayer] play() called from JS")
        
        configureAudioSession()

        DispatchQueue.main.async {
            guard let player = self.player else {
                print("⚠️ [NativeAudioPlayer] play called but player is nil – did you call setQueue?")
                call.reject("No queue set – call setQueue first")
                return
            }

            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("⚠️ [NativeAudioPlayer] Could not re-activate audio session: \(error)")
            }
            player.volume = 1.0
            player.play()
            print("✅ [NativeAudioPlayer] player.play() – rate now: \(player.rate)")
            call.resolve()
        }
    }

    @objc func pause(_ call: CAPPluginCall) {
        print("⏸ [NativeAudioPlayer] pause() called from JS")

        DispatchQueue.main.async {
            self.player?.pause()
            call.resolve()
        }
    }

    @objc func skipToNext(_ call: CAPPluginCall) {
        print("⏭ [NativeAudioPlayer] skipToNext() called from JS")

        DispatchQueue.main.async {
            self.skipToNextInternal()
            call.resolve()
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        print("⏹ [NativeAudioPlayer] stop() called from JS")

        DispatchQueue.main.async {
            guard let player = self.player else {
                print("⚠️ [NativeAudioPlayer] stop called but player is nil")
                call.resolve()
                return
            }

            player.pause()
            player.removeAllItems()
            self.currentIndex = 0
            print("✅ [NativeAudioPlayer] player stopped and queue cleared")
            call.resolve()
        }
    }
}

