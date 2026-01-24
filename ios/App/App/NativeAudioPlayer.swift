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
    private var updateNowPlayingTimer: Timer?

    // MARK: - Lifecycle
    public override func load() {
        super.load()
        print("🎧 [NativeAudioPlayer] load() – plugin constructed and added to bridge")

        // Do NOT change the global audio session here.
        setupRemoteCommandCenter()
        registerPlayerObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("🧹 [NativeAudioPlayer] deinit – observers removed")
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
        updateNowPlayingInfo()
        notifyListeners("trackEnded", data: ["index": currentIndex])
    }

    // MARK: - Now Playing Info (for Control Center & Lock Screen)

    private func startNowPlayingUpdates() {
        updateNowPlayingInfo()
        
        // Update every 0.5 seconds while playing
        updateNowPlayingTimer?.invalidate()
        updateNowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    private func stopNowPlayingUpdates() {
        updateNowPlayingTimer?.invalidate()
        updateNowPlayingTimer = nil
    }

    private func updateNowPlayingInfo() {
        guard let player = player else { return }
        
        let infoCenter = MPNowPlayingInfoCenter.default()
        
        // Get current item duration
        var duration: Double = 0
        if let currentItem = player.currentItem {
            duration = CMTimeGetSeconds(currentItem.asset.duration)
            if duration.isNaN || duration.isInfinite {
                duration = 0
            }
        }
        
        // Get current playback time
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let playbackTime = currentTime.isNaN || currentTime.isInfinite ? 0 : currentTime
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: "ZenCards Study Session",
            MPMediaItemPropertyArtist: "ZenCards",
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playbackTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate
        ]
        
        infoCenter.nowPlayingInfo = nowPlayingInfo
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
            // CRITICAL: Configure audio session BEFORE creating the player
            // This ensures the audio routing is set up correctly
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(
                    .playback,
                    mode: .default,
                    options: [.duckOthers]
                )
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                print("🔊 [NativeAudioPlayer] Audio session pre-configured in setQueue()")
            } catch {
                print("⚠️ [NativeAudioPlayer] Audio session setup in setQueue failed: \(error)")
            }
            
            self.currentIndex = 0

            var items: [AVPlayerItem] = []

            for urlString in urls {
                if let u = URL(string: urlString) {
                    print("   ↳ enqueue URL: \(u)")
                    items.append(AVPlayerItem(url: u))
                } else {
                    print("⚠️ [NativeAudioPlayer] Bad URL in setQueue: \(urlString)")
                }
            }

            guard !items.isEmpty else {
                print("❌ [NativeAudioPlayer] No valid URLs after parsing")
                call.reject("No valid URLs to play")
                return
            }

            let player = AVQueuePlayer(items: items)
            player.actionAtItemEnd = .advance
            player.automaticallyWaitsToMinimizeStalling = false
            player.volume = 1.0  // Ensure volume is not muted
            self.player = player

            // CRITICAL: Ensure player is configured for background playback
            // These must be set BEFORE calling play()
            player.preventsDisplaySleepDuringVideoPlayback = false
            
            // Now Playing info (for Control Center tile)
            if let first = items.first {
                let infoCenter = MPNowPlayingInfoCenter.default()
                let duration = CMTimeGetSeconds(first.asset.duration)
                infoCenter.nowPlayingInfo = [
                    MPMediaItemPropertyTitle: "ZenCards Study Session",
                    MPNowPlayingInfoPropertyIsLiveStream: false,
                    MPMediaItemPropertyPlaybackDuration: duration,
                    MPNowPlayingInfoPropertyElapsedPlaybackTime: 0
                ]
            }
            
            // Log queue setup for debugging
            print("✅ [NativeAudioPlayer] Queue created with \(items.count) AVPlayerItem(s)")
            print("   ↳ actionAtItemEnd: advance")
            print("   ↳ automaticallyWaitsToMinimizeStalling: false")
            print("   ↳ player.volume: \(player.volume)")
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

        DispatchQueue.main.async {
            guard let player = self.player else {
                print("⚠️ [NativeAudioPlayer] play called but player is nil – did you call setQueue?")
                call.reject("No queue set – call setQueue first")
                return
            }

            // Configure audio session for background playback
            do {
                let session = AVAudioSession.sharedInstance()
                
                // CRITICAL: Use .playback category (NOT .playAndRecord which conflicts with VoiceCommands)
                // Only use options that don't conflict with other categories
                try session.setCategory(
                    .playback,
                    mode: .default,
                    options: [.duckOthers]  // Just duck other apps, nothing else
                )
                
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                print("✅ [NativeAudioPlayer] Audio session configured for background playback")
                
                // Debug: Check audio routing
                let outputs = session.currentRoute.outputs
                print("🔊 [NativeAudioPlayer] Audio outputs: \(outputs.count)")
                for output in outputs {
                    print("   ↳ Output: \(output.portType.rawValue) (\(output.portName))")
                }
            } catch {
                print("⚠️ [NativeAudioPlayer] Audio session setup failed: \(error)")
            }

            // Verify player state before playing
            print("📊 [NativeAudioPlayer] Player state before play():")
            print("   ↳ volume: \(player.volume)")
            print("   ↳ rate: \(player.rate)")
            print("   ↳ timeControlStatus: \(player.timeControlStatus.rawValue)")
            if let currentItem = player.currentItem {
                print("   ↳ currentItem duration: \(CMTimeGetSeconds(currentItem.duration))")
                print("   ↳ currentItem status: \(currentItem.status.rawValue)")
            }
            
            player.volume = 1.0
            player.play()
            self.startNowPlayingUpdates()
            print("✅ [NativeAudioPlayer] player.play() – rate now: \(player.rate)")
            print("   ↳ timeControlStatus: \(player.timeControlStatus.rawValue)")
            call.resolve()
        }
    }

    @objc func pause(_ call: CAPPluginCall) {
        print("⏸ [NativeAudioPlayer] pause() called from JS")

        DispatchQueue.main.async {
            self.player?.pause()
            self.stopNowPlayingUpdates()
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
            self.stopNowPlayingUpdates()
            
            // Clear Now Playing info
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            
            print("✅ [NativeAudioPlayer] player stopped and queue cleared")
            call.resolve()
        }
    }
}

