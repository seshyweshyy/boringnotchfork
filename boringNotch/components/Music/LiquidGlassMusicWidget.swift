//
//  LiquidGlassMusicWidget.swift
//  boringNotch
//
//  A "liquid glass" floating music card shown on the lock screen
//  (or whenever the sneak peek style is set to .liquidGlass).
//  Mirrors Alcove's aesthetic: blurred album art background,
//  frosted pill shape, song/artist text, progress bar, and controls.
//

import SwiftUI
import Defaults

// MARK: - Main widget view

struct LiquidGlassMusicWidget: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.playerColorTinting) var playerColorTinting

    // Progress tracking (same pattern as MusicSliderView)
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

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
                // ── Blurred album art background ──────────────────────────
                albumArtBlurBackground

                // ── Glass surface ─────────────────────────────────────────
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)

                // ── Subtle border shimmer ─────────────────────────────────
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.20),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )

                // ── Content ───────────────────────────────────────────────
                HStack(spacing: 12) {
                    albumArtThumbnail

                    VStack(alignment: .leading, spacing: 6) {
                        songInfo
                        progressBar(progress: dragging ? sliderValue : progress)
                        transportControls
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
            .frame(width: 340, height: 100)
            // Update slider state from timeline
            .onChange(of: elapsed) { _, e in
                if !dragging { sliderValue = musicManager.songDuration > 0 ? e / musicManager.songDuration : 0 }
            }
        }
    }

    // MARK: Subviews

    private var albumArtBlurBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .scaledToFill()
            .blur(radius: 28)
            .saturation(1.6)
            .brightness(-0.1)
            .scaleEffect(1.1) // prevent blur edges showing
            .clipped()
    }

    private var albumArtThumbnail: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(musicManager.songTitle.isEmpty ? "Not Playing" : musicManager.songTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(musicManager.artistName.isEmpty ? "—" : musicManager.artistName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    playerColorTinting
                        ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.7)
                        : Color.white.opacity(0.65)
                )
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 3)

                // Fill
                Capsule()
                    .fill(
                        playerColorTinting
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : Color.white
                    )
                    .frame(width: geo.size.width * max(0, min(progress, 1)), height: 3)
            }
            .frame(height: 3)
            // Drag to seek
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        lastDragged = Date()
                        sliderValue = max(0, min(value.location.x / geo.size.width, 1))
                    }
                    .onEnded { _ in
                        MusicManager.shared.seek(to: sliderValue * musicManager.songDuration)
                        dragging = false
                    }
            )
        }
        .frame(height: 3)
    }

    private var transportControls: some View {
        HStack(spacing: 20) {
            glassButton(icon: "backward.fill") {
                MusicManager.shared.previousTrack()
            }
            glassButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", size: 15) {
                MusicManager.shared.playPause()
            }
            glassButton(icon: "forward.fill") {
                MusicManager.shared.nextTrack()
            }
        }
    }

    private func glassButton(icon: String, size: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Container: positions the widget below the notch on lock screen

struct LiquidGlassMusicWidgetContainer: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Spacer so widget sits ~8 pt below the notch pill
            Spacer()
                .frame(height: 8)

            if musicManager.isPlaying || !musicManager.isPlayerIdle {
                LiquidGlassMusicWidget()
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.88, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.88, anchor: .top).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: musicManager.isPlaying)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LiquidGlassMusicWidget()
    }
    .frame(width: 400, height: 200)
}
