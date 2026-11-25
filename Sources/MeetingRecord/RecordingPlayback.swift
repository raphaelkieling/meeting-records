import AVFoundation
import Combine

@MainActor
final class RecordingPlayback: ObservableObject {
    @Published private(set) var activeID: UUID?
    @Published private(set) var error: String?

    private var requestID: UUID?
    private var preparation: Task<Void, Never>?
    private var player: AVPlayer?
    private var observations = Set<AnyCancellable>()

    func toggle(_ recordingID: UUID, store: MeetingStore) {
        if activeID == recordingID {
            stop()
            return
        }
        play(recordingID, store: store)
    }

    func play(_ recordingID: UUID, store: MeetingStore, startOffset: Int64 = 0) {
        stop()
        let request = UUID()
        requestID = request
        activeID = recordingID
        preparation = Task { [weak self] in
            do {
                let segments = try await store.audioSegments(for: recordingID)
                let root = try await store.recordingRoot()
                let (composition, mix) = try await Self.makeComposition(segments: segments, root: root)
                guard let self, requestID == request else { return }

                let item = AVPlayerItem(asset: composition)
                item.audioMix = mix
                observe(item, request: request)
                let player = AVPlayer(playerItem: item)
                self.player = player
                if startOffset > 0 {
                    await player.seek(to: CMTime(value: startOffset, timescale: 1_000_000_000),
                                      toleranceBefore: .zero, toleranceAfter: .zero)
                }
                guard requestID == request else { return }
                player.play()
            } catch {
                self?.finish(request, error: error.localizedDescription)
            }
        }
    }

    func stop() {
        requestID = nil
        preparation?.cancel()
        preparation = nil
        observations.removeAll()
        player?.pause()
        player = nil
        activeID = nil
        error = nil
    }

    private func finish(_ request: UUID, error: String? = nil) {
        guard requestID == request else { return }
        stop()
        if let error { self.error = "Could not play recording. \(error)" }
    }

    private func observe(_ item: AVPlayerItem, request: UUID) {
        item.publisher(for: \.status)
            .filter { $0 == .failed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                self?.finish(request, error: item?.error?.localizedDescription ?? PlaybackError.unreadable.localizedDescription)
            }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.finish(request) }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                let error = event.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                self?.finish(request, error: error?.localizedDescription ?? PlaybackError.unreadable.localizedDescription)
            }
            .store(in: &observations)
    }

    static func makeComposition(segments: [AudioSegment], root: URL) async throws -> (AVMutableComposition, AVAudioMix) {
        guard !segments.isEmpty else { throw PlaybackError.noAudio }
        let composition = AVMutableComposition()
        var lanes: [AVMutableCompositionTrack] = []
        for source in AudioSegment.Source.allCases {
            let clips = segments.filter { $0.source == source }
            guard !clips.isEmpty else { continue }
            guard let lane = composition.addMutableTrack(withMediaType: .audio,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw PlaybackError.unreadable }

            lanes.append(lane)
            var end = CMTime.zero
            for clip in clips {
                try Task.checkCancellation()
                let (asset, track, range, offset) = try await clipTiming(clip, root: root)
                defer { withExtendedLifetime(asset) {} }
                // Keep the earlier clip if adjacent checkpoints from one source overlap.
                let start = max(end, offset)
                let prefix = start - offset
                guard prefix < range.duration else { continue }
                if start > end {
                    lane.insertEmptyTimeRange(CMTimeRange(start: end, end: start))
                }
                let duration = range.duration - prefix
                try lane.insertTimeRange(CMTimeRange(start: range.start + prefix, duration: duration),
                                         of: track, at: start)
                end = start + duration
            }
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = lanes.map { track in
            let input = AVMutableAudioMixInputParameters(track: track)
            input.setVolume(lanes.count > 1 ? 0.5 : 1, at: .zero)
            return input
        }
        return (composition, mix)
    }

    nonisolated static func savedDuration(segments: [AudioSegment], root: URL) async throws -> TimeInterval {
        guard !segments.isEmpty else { throw PlaybackError.noAudio }
        var end = CMTime.zero
        for clip in segments {
            try Task.checkCancellation()
            let (_, _, range, offset) = try await clipTiming(clip, root: root)
            end = max(end, offset + range.duration)
        }
        return end.seconds
    }

    nonisolated private static func clipTiming(_ clip: AudioSegment, root: URL) async throws
        -> (AVURLAsset, AVAssetTrack, CMTimeRange, CMTime) {
        let path = clip.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard clip.startOffset >= 0, clip.frameCount > 0,
              path.count == 4, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw PlaybackError.unreadable }

        let asset = AVURLAsset(url: root.appendingPathComponent(clip.relativePath))
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw PlaybackError.unreadable
        }
        let range = try await track.load(.timeRange)
        guard range.duration.isNumeric, range.duration > .zero else { throw PlaybackError.unreadable }

        let offset = CMTime(value: clip.startOffset, timescale: 1_000_000_000)
        return (asset, track, range, offset)
    }

    private enum PlaybackError: LocalizedError {
        case noAudio, unreadable

        var errorDescription: String? {
            switch self {
            case .noAudio: "This recording has no saved audio."
            case .unreadable: "A saved audio clip is unavailable or unreadable."
            }
        }
    }
}
