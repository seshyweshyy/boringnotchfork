//
//  LiquidGlassMusicWidget.swift
//  boringNotch
//
//  The SwiftUI view rendered inside LiquidGlassWidgetWindow.
//  Sits near the bottom-centre of the screen, above the user profile icon,
//  matching Alcove's lock screen widget position.
//

import SwiftUI
import Defaults

struct LiquidGlassMusicWidget: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.playerColorTinting) var playerColorTinting

    @State private var displayedArt: NSImage = MusicManager.shared.albumArt
    @State private var rotationDegrees: Double = 0
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.25 : nil)) { timeline in
            let elapsed: Double = {
                guard musicManager.isPlaying else { return musicManager.elapsedTime }
                let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                return min(max(musicManager.elapsedTime + delta * musicManager.playbackRate, 0),
                           musicManager.songDuration)
            }()
            let progress: Double = musicManager.songDuration > 0
                ? elapsed / musicManager.songDuration : 0

            ZStack {
                // Blurred album art — very subtle, mostly transparent glass
                Image(nsImage: displayedArt)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .saturation(1.4)
                    .brightness(-0.15)
                    .scaleEffect(1.15)
                    .opacity(0.55) // keep it subtle so the glass reads as glass
                    .clipped()

                // Primary glass layer — thinner/more transparent than before
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.75)
                    .environment(\.colorScheme, .dark)

                // Very subtle dark fill so text stays readable
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.15))

                // Shimmer border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.25),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )

                HStack(spacing: 12) {
                    albumArtThumbnail
                    VStack(alignment: .leading, spacing: 5) {
                        songInfo
                        progressBar(progress: dragging ? sliderValue : progress)
                        transportControls
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            // Layered shadows for depth
            .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 12)
            .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
            .frame(width: 320, height: 94)
            .onChange(of: elapsed) { _, e in
                if !dragging {
                    sliderValue = musicManager.songDuration > 0 ? e / musicManager.songDuration : 0
                }
            }
        }
        .onChange(of: musicManager.artFlipSignal) { _, signal in
            let dir: Double = signal.direction == .forward ? 1 : -1
            withAnimation(.easeIn(duration: 0.15)) { rotationDegrees = dir * 90 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                displayedArt = signal.art
                rotationDegrees = dir * -90
                withAnimation(.easeOut(duration: 0.15)) { rotationDegrees = 0 }
            }
        }
    }

    private var albumArtThumbnail: some View {
        Image(nsImage: displayedArt)
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .rotation3DEffect(.degrees(rotationDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
    }

    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(musicManager.songTitle.isEmpty ? "Not Playing" : musicManager.songTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(musicManager.artistName.isEmpty ? "—" : musicManager.artistName)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(
                    playerColorTinting
                        ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.7)
                        : Color.white.opacity(0.6)
                )
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 2.5)
                Capsule()
                    .fill(
                        playerColorTinting
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : Color.white.opacity(0.85)
                    )
                    .frame(width: geo.size.width * max(0, min(progress, 1)), height: 2.5)
            }
            .frame(height: 2.5)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        sliderValue = max(0, min(value.location.x / geo.size.width, 1))
                    }
                    .onEnded { _ in
                        MusicManager.shared.seek(to: sliderValue * musicManager.songDuration)
                        dragging = false
                    }
            )
        }
        .frame(height: 2.5)
    }

    private var transportControls: some View {
        HStack(spacing: 18) {
            controlButton(icon: "backward.fill") { MusicManager.shared.previousTrack() }
            controlButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", size: 14) {
                MusicManager.shared.playPause()
            }
            controlButton(icon: "forward.fill") { MusicManager.shared.nextTrack() }
        }
    }

    private func controlButton(icon: String, size: CGFloat = 11, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
