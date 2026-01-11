import Foundation
import Capacitor
import AVFoundation
import MediaPlayer

@objc(NativeAudioPlayerPlugin)
public class NativeAudioPlayerPlugin: CAPPlugin {

    private var player = AVQueuePlayer()
    private var currentIndex: Int = 0

    public override func load() {
        super.load()
        print("✅ NativeAudioPlayerPlugin loaded into Capacitor bridge")
        configureAudioSession()
        setupRemoteCommandCenter()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            print("AudioSession error: \(error)")
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            self?.notifyListeners("remoteCommand", data: ["type": "play"])
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            self?.notifyListeners("remoteCommand", data: ["type": "pause"])
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNextInternal()
            self?.notifyListeners("remoteCommand", data: ["type": "next"])
            return .success
        }
    }

    @objc private func itemDidFinishPlaying(_ notification: Notification) {
        currentIndex += 1
        notifyListeners("trackEnded", data: ["index": currentIndex])
    }

    private func skipToNextInternal() {
        player.advanceToNextItem()
        currentIndex += 1
        notifyListeners("trackEnded", data: ["index": currentIndex])
    }

    // MARK: Plugin methods called from JS

    @objc func setQueue(_ call: CAPPluginCall) {
        guard let urls = call.getArray("urls", String.self) else {
            call.reject("Missing urls")
            return
        }

        player.removeAllItems()
        currentIndex = 0

        for urlString in urls {
            if let url = URL(string: urlString) {
                let item = AVPlayerItem(url: url)
                player.insert(item, after: nil)
            }
        }

        call.resolve()
    }

    @objc func enqueue(_ call: CAPPluginCall) {
        guard let urls = call.getArray("urls", String.self) else {
            call.reject("Missing urls")
            return
        }

        for urlString in urls {
            if let url = URL(string: urlString) {
                let item = AVPlayerItem(url: url)
                player.insert(item, after: nil)
            }
        }

        call.resolve()
    }

    @objc func play(_ call: CAPPluginCall) {
        player.play()
        call.resolve()
    }

    @objc func pause(_ call: CAPPluginCall) {
        player.pause()
        call.resolve()
    }

    @objc func skipToNext(_ call: CAPPluginCall) {
        skipToNextInternal()
        call.resolve()
    }
}
