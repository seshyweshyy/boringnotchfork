//
//  AlbumArtBackgroundWindow.swift
//  boringNotch
//
//  A low-level full-screen window that renders a blurred, animated album art
//  gradient behind the lock screen UI (clock, login) but above the wallpaper.
//  Shown only when the expanded album art view is active.
//

import AppKit
import SwiftUI
import Combine

// MARK: - Window

class AlbumArtBackgroundWindow: BoringNotchSkyLightWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        // Sit just above the wallpaper, below the login UI and widget window
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        isMovable = false
        sharingType = .none
    }
}

// MARK: - Background View

private struct AlbumArtBackgroundView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var displayedArt: NSImage = MusicManager.shared.albumArt
    @State private var isVisible: Bool = false

    var body: some View {
        ZStack {
            Image(nsImage: displayedArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.3)  // push art past all edges before blurring
                .blur(radius: 60)
                .saturation(1.8)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.5), value: isVisible)
        .onReceive(NotificationCenter.default.publisher(for: .albumArtBackgroundShouldShow)) { _ in
            withAnimation { isVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .albumArtBackgroundShouldHide)) { _ in
            withAnimation { isVisible = false }
        }
        .onChange(of: musicManager.artFlipSignal) { _, signal in
            withAnimation(.easeInOut(duration: 0.4)) {
                displayedArt = signal.art
            }
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let albumArtBackgroundShouldShow = Notification.Name("albumArtBackgroundShouldShow")
    static let albumArtBackgroundShouldHide = Notification.Name("albumArtBackgroundShouldHide")
}

// MARK: - Controller

class AlbumArtBackgroundWindowController {
    static let shared = AlbumArtBackgroundWindowController()
    private var window: AlbumArtBackgroundWindow?
    private init() {}

    func show(on screen: NSScreen) {
        if window == nil {
            let win = AlbumArtBackgroundWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            win.contentView = NSHostingView(rootView: AlbumArtBackgroundView())
            window = win
        }
        guard let win = window else { return }
        win.setFrame(screen.frame, display: false)
        win.enableSkyLight()
        win.orderFrontRegardless()
    }

    func hide() {
        guard let win = window else { return }
        win.disableSkyLight()
        win.orderOut(nil)
        window = nil
    }

    func updateScreen(_ screen: NSScreen) {
        window?.setFrame(screen.frame, display: true)
    }
}
