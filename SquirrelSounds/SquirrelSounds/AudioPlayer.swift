import AVFoundation
import SwiftUI

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ sound: AnimalSound) {
        if currentID == sound.id, let player {
            if player.isPlaying { pause() }
            else {
                if player.currentTime >= player.duration { player.currentTime = 0 }
                isPlaying = player.play()
            }
            return
        }
        stop()
        guard let url = sound.localURL else {
            error = "This recording hasn’t been added yet. You can read its details and visit the original source."
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            player = next
            currentID = sound.id
            duration = next.duration
            isPlaying = next.play()
            if !isPlaying { error = "The recording could not be played." }
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let player = self.player else { return }
                    self.progress = player.currentTime
                    self.isPlaying = player.isPlaying
                }
            }
        } catch {
            self.error = "Unable to play this recording. Please try again."
            stop()
        }
    }

    func seek(to time: Double) {
        player?.currentTime = min(max(time, 0), duration)
        progress = player?.currentTime ?? 0
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        currentID = nil
        isPlaying = false
        progress = 0
        duration = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
