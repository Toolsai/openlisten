import AVFoundation
import MediaPlayer
import Combine
import OpenListenCore

@MainActor
final class AudioPlayer: ObservableObject {
    @Published var currentID: UUID?
    @Published var isPlaying = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    private let player = AVPlayer()
    private let library: LibraryStore
    private var queue: [UUID] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var statusObserver: NSKeyValueObservation?
    private var savedAt: Double = 0
    private var interruptedPlayback = false

    init(library: LibraryStore) {
        self.library = library
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in self?.isPlaying = player.timeControlStatus == .playing; self?.updateNowPlaying() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, time.seconds.isFinite else { return }
                self.elapsed = max(0, time.seconds)
                if let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 { self.duration = seconds }
                if abs(self.elapsed - self.savedAt) >= 5 { self.savePosition() }
                self.updateNowPlaying()
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .began {
                    let wasPlaying = self.isPlaying
                    self.pause(); self.interruptedPlayback = wasPlaying
                } else {
                    let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                    if self.interruptedPlayback && options.contains(.shouldResume) { self.resume() }
                    self.interruptedPlayback = false
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause(); self?.error = "音檔無法繼續播放，請重新下載。" }
        })
        configureCommands()
    }

    var current: AudioItem? { library.snapshot.items.first { $0.id == currentID } }

    func play(_ item: AudioItem, in ids: [UUID]) {
        guard item.localFilename != nil, FileManager.default.fileExists(atPath: LocalFiles.audio(item.id).path) else {
            error = "請先將這項音訊下載到手機。"; return
        }
        savePosition()
        queue = ids.filter { id in library.snapshot.items.contains { $0.id == id && $0.localFilename != nil } }
        if !queue.contains(item.id) { queue = [item.id] }
        currentID = item.id
        elapsed = item.position ?? 0; savedAt = elapsed; duration = item.duration ?? 0
        let asset = AVPlayerItem(url: LocalFiles.audio(item.id))
        player.replaceCurrentItem(with: asset)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: asset, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = 0; self.savePosition(); self.next()
            }
        }
        if elapsed > 0 { player.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600)) }
        resume()
    }

    func resume() {
        guard currentID != nil else { return }
        if duration > 0 && player.currentTime().seconds >= duration - 0.1 { seek(0) }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player.play(); isPlaying = true; updateNowPlaying()
        } catch { self.error = "未能啟動播放：\(error.localizedDescription)" }
    }

    func pause() {
        interruptedPlayback = false
        player.pause(); isPlaying = false; savePosition(); updateNowPlaying()
    }

    func toggle() { isPlaying ? pause() : resume() }

    func stop() {
        pause(); player.replaceCurrentItem(with: nil); currentID = nil; elapsed = 0; duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next() {
        guard let currentID, let index = queue.firstIndex(of: currentID), index + 1 < queue.count,
              let item = library.snapshot.items.first(where: { $0.id == queue[index + 1] }) else { pause(); return }
        play(item, in: queue)
    }

    func previous() {
        if elapsed > 3 { seek(0); return }
        guard let currentID, let index = queue.firstIndex(of: currentID), index > 0,
              let item = library.snapshot.items.first(where: { $0.id == queue[index - 1] }) else { seek(0); return }
        play(item, in: queue)
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        elapsed = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600))
        savePosition(); updateNowPlaying()
    }

    func savePosition() {
        if let currentID { library.updatePosition(currentID, seconds: elapsed); savedAt = elapsed }
    }

    private func updateNowPlaying() {
        guard let item = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: item.title, MPMediaItemPropertyArtist: item.channel,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private func configureCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }
}
