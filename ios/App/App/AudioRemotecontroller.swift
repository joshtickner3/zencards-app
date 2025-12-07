import Foundation
import MediaPlayer

/// Handles mapping "next track" button taps to SRS ratings:
/// 1 tap  = "easy"
/// 2 taps = "good"
/// 3 taps = "hard"
/// 4 taps = "again"
final class AudioRemoteController {

    static let shared = AudioRemoteController()

    private let commandCenter = MPRemoteCommandCenter.shared()

    // How many times we've seen next-track tapped within the window
    private var ratingTapCount: Int = 0
    // Time of the last tap
    private var lastTapTime: TimeInterval = 0
    // How long we wait (in seconds) to decide the final tap count
    private let tapWindow: TimeInterval = 1.2

    /// Called when a rating is chosen: "again", "hard", "good", "easy"
    var onRatingChosen: ((String) -> Void)?

    private init() {}

    // Call this once from VoiceCommands.load()
    func configureRemoteCommands() {
        // Disable commands we don't care about
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false

        // Enable next-track for rating taps
        commandCenter.nextTrackCommand.isEnabled = true

        // Reset state
        ratingTapCount = 0
        lastTapTime = 0

        // Remove any old handlers first to avoid duplicates
        commandCenter.nextTrackCommand.removeTarget(nil)

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.handleNextTrackTap()
            return .success
        }
    }

    // Call this when you're done (e.g. VoiceCommands.stop)
    func teardownRemoteCommands() {
        commandCenter.nextTrackCommand.removeTarget(nil)
        ratingTapCount = 0
        lastTapTime = 0
    }

    // MARK: - Tap logic

    private func handleNextTrackTap() {
        let now = Date().timeIntervalSince1970

        // If too much time has passed since the last tap, start a new sequence
        if now - lastTapTime > tapWindow {
            ratingTapCount = 0
        }

        ratingTapCount += 1
        lastTapTime = now

        let currentCount = ratingTapCount

        // After tapWindow seconds with no new taps, decide on a rating
        DispatchQueue.main.asyncAfter(deadline: .now() + tapWindow) { [weak self] in
            guard let self = self else { return }

            // Only fire if the tap count hasn't changed in this window
            guard self.ratingTapCount == currentCount else { return }

            let rating: String
            switch currentCount {
            case 1:
                rating = "easy"
            case 2:
                rating = "good"
            case 3:
                rating = "hard"
            case 4:
                rating = "again"
            default:
                // If they tap more than 4 times, just treat it as "good"
                rating = "good"
            }

            // Reset counters for the next sequence
            self.ratingTapCount = 0
            self.lastTapTime = 0

            // Notify the plugin / JS
            self.onRatingChosen?(rating)
        }
    }
}
