import SwiftUI
import AVKit

/// Video der Einzelansicht wie bei Apple: eigene Leiste (Filmstreifen zum Spulen, Ton, AirPlay) statt der
/// AVKit-Standardknöpfe. Ein Player für das gerade gezeigte Video; Seite und Leisten lesen denselben Zustand.
@MainActor @Observable
final class VideoState {
    private(set) var id = ""
    private(set) var player: AVPlayer?
    private(set) var playing = false
    var muted = false { didSet { player?.isMuted = muted } }
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    /// Standbilder für den Filmstreifen (vom Server-Video, in kleiner Größe)
    private(set) var frames: [UIImage] = []
    /// Zeitlupe (120/240 fps): wird verlangsamt abgespielt wie bei Apple
    private(set) var slowMo: SlowMo?
    /// Beim Ziehen am Filmstreifen nicht vom Player überschreiben lassen
    @ObservationIgnored var scrubbing = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var framesTask: Task<Void, Never>?

    /// Neues Video zeigen (alter Player wird angehalten und freigegeben).
    func attach(_ asset: Asset) {
        guard asset.id != id else { return }
        stop()
        id = asset.id
        duration = Double(asset.durationMs ?? 0) / 1000
        guard let url = ImmichClient.shared.videoURL(asset.id) else { return }
        let av = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ImmichClient.shared.authHeaders])
        let p = AVPlayer(playerItem: AVPlayerItem(asset: av))
        p.isMuted = muted
        player = p
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, !self.scrubbing else { return }
                self.time = t.seconds
                if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
            }
        }
        observeEnd(p)
        loadFrames(av)
        let want = asset.id
        Task { [weak self] in
            guard let s = await SlowMo.detect(av), let comp = try? await s.composition(av) else { return }
            guard let self, self.id == want, let p = self.player else { return }
            let resume = self.playing
            p.replaceCurrentItem(with: SlowMo.item(comp))
            self.slowMo = s
            self.duration = (try? await comp.load(.duration).seconds) ?? self.duration
            self.observeEnd(p)
            if resume { p.play() }
        }
    }

    private func observeEnd(_ p: AVPlayer) {
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playing = false }
        }
    }

    func play() {
        guard let p = player else { return }
        // am Ende: von vorn (wie Apple)
        if duration > 0, time >= duration - 0.15 { p.seek(to: .zero); time = 0 }
        p.play(); playing = true
    }
    func pause() { player?.pause(); playing = false }
    func toggle() { playing ? pause() : play() }

    func seek(fraction f: Double) {
        guard let p = player, duration > 0 else { return }
        let t = max(0, min(1, f)) * duration
        time = t
        p.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player?.pause()
        if let o = timeObserver { player?.removeTimeObserver(o) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        timeObserver = nil; endObserver = nil
        framesTask?.cancel(); framesTask = nil
        player = nil; playing = false; time = 0; frames = []; id = ""; slowMo = nil
    }

    /// ~14 Standbilder gleichmäßig über das Video (Bereichsanfragen an den Server, nicht das ganze Video).
    private func loadFrames(_ av: AVURLAsset) {
        let want = id, count = 14
        framesTask = Task { [weak self] in
            let gen = AVAssetImageGenerator(asset: av)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 160, height: 160)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            guard let d = try? await av.load(.duration).seconds, d.isFinite, d > 0 else { return }
            let times = (0..<count).map { CMTime(seconds: d * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
            var out: [UIImage] = []
            for await r in gen.images(for: times) {
                if Task.isCancelled { return }
                if let img = try? r.image { out.append(UIImage(cgImage: img)) }
                if out.count % 4 == 0 || out.count == count {
                    guard let self, self.id == want else { return }
                    self.frames = out
                }
            }
            if let self, self.id == want { self.frames = out }
        }
    }
}

/// Bildfläche für den Player (ohne AVKit-Knöpfe).
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer?
    func makeUIView(context: Context) -> PlayerLayerView { PlayerLayerView() }
    func updateUIView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
        v.playerLayer.videoGravity = .resizeAspect
    }
    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Leiste unter dem Video: Wiedergabe/Pause + Filmstreifen mit Abspielkopf, Ziehen spult (wie Apple).
struct VideoScrubber: View {
    @Bindable var video: VideoState
    @State private var wasPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            Button { video.toggle() } label: {
                Image(systemName: video.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(video.playing ? String(localized: "Pause") : String(localized: "Wiedergabe"))
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        if video.frames.isEmpty {
                            Color(white: 0.2)
                        } else {
                            ForEach(Array(video.frames.enumerated()), id: \.offset) { _, f in
                                Image(uiImage: f).resizable().scaledToFill()
                                    .frame(width: w / CGFloat(video.frames.count), height: 40).clipped()
                            }
                        }
                    }
                    .frame(width: w, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    // Abspielkopf
                    RoundedRectangle(cornerRadius: 2).fill(.white)
                        .frame(width: 4, height: 50)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .offset(x: video.duration > 0 ? CGFloat(video.time / video.duration) * (w - 4) : 0)
                }
                .frame(height: 50)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !video.scrubbing { video.scrubbing = true; wasPlaying = video.playing; video.pause() }
                        video.seek(fraction: Double(g.location.x / w))
                    }
                    .onEnded { _ in video.scrubbing = false; if wasPlaying { video.play() } })
            }
            .frame(height: 50)
            Text(Fmt.duration(Int(max(0, video.duration - video.time) * 1000)))
                .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .shadow(radius: 3)
                .frame(width: 44)
        }
        .padding(.horizontal, 16)
    }
}

/// AirPlay-Knopf (Video auf Fernseher/Lautsprecher).
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white; v.activeTintColor = .systemBlue
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
