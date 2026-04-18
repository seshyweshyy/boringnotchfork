//
//  AlbumArtBackgroundWindow.swift
//  boringNotch
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI

// MARK: - SkyLight transition window (lock screen only)

/// Used while the screen is locked to cover the wallpaper swap with a smooth fade.
/// Level is mainMenu + 1 so it sits below the notch and widget (both at mainMenu + 3).
private final class GradientTransitionWindow: BoringNotchSkyLightWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        isMovable = false
        sharingType = .none
        ignoresMouseEvents = true
    }
}

// MARK: - Desktop cover window (used on unlock only)

/// A regular (non-SkyLight) NSPanel shown on the desktop right after unlock.
/// Covers the wallpaper restore so the gradient appears to fade out rather
/// than abruptly swap. Screen-saver level ensures it appears above all apps.
private final class GradientDesktopCoverWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Shared gradient view

private struct StaticGradientView: View {
    let image: NSImage
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .ignoresSafeArea()
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let albumArtBackgroundShouldShow = Notification.Name("albumArtBackgroundShouldShow")
    static let albumArtBackgroundShouldHide = Notification.Name("albumArtBackgroundShouldHide")
    static let lockScreenProfileShouldHide  = Notification.Name("lockScreenProfileShouldHide")
    static let lockScreenProfileShouldShow  = Notification.Name("lockScreenProfileShouldShow")
}

// MARK: - Controller

final class AlbumArtBackgroundWindowController {
    static let shared = AlbumArtBackgroundWindowController()
    private init() {}

    // Original wallpaper state — saved once, restored on collapse or unlock
    private var savedWallpaperURL:     URL?
    private var savedWallpaperOptions: [NSWorkspace.DesktopImageOptionKey: Any]?
    private var savedWallpaperScreen:  NSScreen?

    // Set synchronously the moment we decide to swap, so rapid re-entrant
    // calls cannot overwrite savedWallpaperOptions with the gradient's options.
    private var isWallpaperReplaced = false

    private var currentTempURL: URL?
    private var lastRenderedColors: [NSColor] = []

    // Cancels the async 0.25s block inside hide() if hideForUnlock() fires first
    private var pendingHideWorkItem: DispatchWorkItem?

    private var artChangeCancellable: AnyCancellable?
    private var transitionWindow: GradientTransitionWindow?
    private var desktopCoverWindow: GradientDesktopCoverWindow?

    // MARK: - Public API

    func prepare(on screen: NSScreen) {}
    func updateScreen(_ screen: NSScreen) {}

    /// Called when isExpanded becomes true (on the lock screen).
    func show() {
        guard let screen = NSScreen.main else { return }

        if !isWallpaperReplaced {
            savedWallpaperURL     = NSWorkspace.shared.desktopImageURL(for: screen)
            savedWallpaperOptions = NSWorkspace.shared.desktopImageOptions(for: screen)
            savedWallpaperScreen  = screen
            isWallpaperReplaced   = true   // lock in immediately — before any async work
        }

        if artChangeCancellable == nil {
            artChangeCancellable = MusicManager.shared.$artFlipSignal
                .dropFirst()
                .sink { [weak self] _ in
                    self?.updateWallpaperForCurrentSong()
                }
        }

        applyGradient(for: MusicManager.shared.albumArt, on: screen, animated: true)
    }

    /// Called when isExpanded becomes false normally (user collapses on lock screen).
    /// Uses the SkyLight transition window to fade gracefully.
    func hide() {
        artChangeCancellable = nil

        guard isWallpaperReplaced,
              let url    = savedWallpaperURL,
              let screen = savedWallpaperScreen ?? NSScreen.main
        else {
            isWallpaperReplaced = false
            return
        }

        if let image = renderGradient(colors: lastRenderedColors, size: screen.frame.size) {
            presentTransitionWindow(image: image, on: screen)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try NSWorkspace.shared.setDesktopImageURL(
                    url,
                    for: screen,
                    options: self.savedWallpaperOptions ?? [:]
                )
            } catch {}

            self.isWallpaperReplaced   = false
            self.savedWallpaperURL     = nil
            self.savedWallpaperOptions = nil
            self.savedWallpaperScreen  = nil
            self.lastRenderedColors    = []

            if let tmp = self.currentTempURL {
                try? FileManager.default.removeItem(at: tmp)
                self.currentTempURL = nil
            }

            self.dismissTransitionWindow(animated: true)
        }
        pendingHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Called exclusively from KnotchApp.onScreenUnlocked.
    /// Cancels any in-progress hide(), restores the wallpaper immediately,
    /// then covers the desktop with a gradient panel that fades out — giving
    /// the "collapse first" visual without being able to block macOS's unlock.
    func hideForUnlock() {
        artChangeCancellable = nil

        // Cancel any pending delayed restore from a concurrent hide() call
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil

        // SkyLight transition window is no longer visible on the desktop — dismiss immediately
        dismissTransitionWindow(animated: false)

        guard isWallpaperReplaced,
              let url    = savedWallpaperURL,
              let screen = savedWallpaperScreen ?? NSScreen.main
        else {
            isWallpaperReplaced = false
            return
        }

        // Show the desktop cover immediately so the wallpaper restore is invisible
        if let image = renderGradient(colors: lastRenderedColors, size: screen.frame.size) {
            showDesktopCover(image: image, on: screen)
        }

        // Restore wallpaper synchronously — the cover hides the swap
        do {
            try NSWorkspace.shared.setDesktopImageURL(
                url,
                for: screen,
                options: savedWallpaperOptions ?? [:]
            )
        } catch {}

        isWallpaperReplaced   = false
        savedWallpaperURL     = nil
        savedWallpaperOptions = nil
        savedWallpaperScreen  = nil
        lastRenderedColors    = []

        if let tmp = currentTempURL {
            try? FileManager.default.removeItem(at: tmp)
            currentTempURL = nil
        }

        // Small pause then fade out — gives the impression of the gradient dissolving away
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.fadeOutDesktopCover()
        }
    }

    // MARK: - Private: gradient update on song change

    private func updateWallpaperForCurrentSong() {
        guard isWallpaperReplaced, let screen = savedWallpaperScreen ?? NSScreen.main else { return }
        applyGradient(for: MusicManager.shared.albumArt, on: screen, animated: false)
    }

    // MARK: - Private: core gradient apply

    private func applyGradient(for art: NSImage, on screen: NSScreen, animated: Bool) {
        art.dominantColors(count: 3) { [weak self] nsColors in
            guard let self else { return }

            let adjusted = nsColors.map { c -> NSColor in
                let srgb = c.usingColorSpace(.sRGB) ?? c
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                return NSColor(
                    hue: h,
                    saturation: min(s * 1.4, 1.0),
                    brightness: max(b - 0.2, 0.0),
                    alpha: a
                )
            }
            self.lastRenderedColors = adjusted

            guard let image   = self.renderGradient(colors: adjusted, size: screen.frame.size),
                  let tempURL = self.writeTempImage(image)
            else { return }

            let swap = {
                if let old = self.currentTempURL { try? FileManager.default.removeItem(at: old) }
                self.currentTempURL = tempURL

                do {
                    try NSWorkspace.shared.setDesktopImageURL(
                        tempURL,
                        for: screen,
                        options: [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue]
                    )
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    self.currentTempURL = nil
                    if animated { self.dismissTransitionWindow(animated: false) }
                }
            }

            if animated {
                self.presentTransitionWindow(image: image, on: screen)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    swap()
                    self.dismissTransitionWindow(animated: true)
                }
            } else {
                swap()
            }
        }
    }

    // MARK: - Private: SkyLight transition window (lock screen)

    private func presentTransitionWindow(image: NSImage, on screen: NSScreen) {
        let win: GradientTransitionWindow
        if let existing = transitionWindow {
            win = existing
        } else {
            win = GradientTransitionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            transitionWindow = win
        }
        win.setFrame(screen.frame, display: false)
        win.contentView = NSHostingView(rootView: StaticGradientView(image: image))
        win.alphaValue  = 0
        win.enableSkyLight()
        win.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration       = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().alphaValue = 1
        }
    }

    private func dismissTransitionWindow(animated: Bool) {
        guard let win = transitionWindow else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration       = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.disableSkyLight()
                win.orderOut(nil)
            })
        } else {
            win.alphaValue = 0
            win.disableSkyLight()
            win.orderOut(nil)
        }
    }

    // MARK: - Private: desktop cover window (unlock path)

    private func showDesktopCover(image: NSImage, on screen: NSScreen) {
        let win = GradientDesktopCoverWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.contentView = NSHostingView(rootView: StaticGradientView(image: image))
        win.orderFrontRegardless()
        desktopCoverWindow = win
    }

    private func fadeOutDesktopCover() {
        guard let win = desktopCoverWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration       = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
            self.desktopCoverWindow = nil
        })
    }

    // MARK: - Private: image rendering

    private func renderGradient(colors: [NSColor], size: CGSize) -> NSImage? {
        let w = max(1, Int(size.width))
        let h = max(1, Int(size.height))

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let fullRect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(fullRect)

        if !colors.isEmpty {
            let cgColors = colors.map(\.cgColor) as CFArray
            var locations: [CGFloat]
            switch colors.count {
            case 1:  locations = [0.0]
            case 2:  locations = [0.0, 1.0]
            default: locations = [0.0, 0.5, 1.0]
            }
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: cgColors,
                locations: &locations
            ) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: CGFloat(h)),
                    end:   CGPoint(x: CGFloat(w), y: 0),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        }

        ctx.setFillColor(NSColor.white.withAlphaComponent(0.02).cgColor)
        ctx.fill(fullRect)

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }

    private func writeTempImage(_ image: NSImage) -> URL? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return url
    }
}
