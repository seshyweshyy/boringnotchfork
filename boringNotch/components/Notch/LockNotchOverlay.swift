//
//  LockNotchOverlay.swift
//  boringNotch
//
//  Lock icon that appears inside the closed notch when the
//  screen is locked.  When unlocked it plays a smooth scale+fade transition
//  back to the normal notch appearance.
//

import SwiftUI

// MARK: - Lock state icon

/// Renders the SF-Symbol lock icon centered inside the closed notch pill.
/// Animates between locked (lock.fill) and a brief unlocked flash (lock.open.fill)
/// before fading out entirely, mirroring Alcove's behaviour.
struct LockNotchOverlay: View {

    /// Drives the full lock/unlock animation cycle.
    let isLocked: Bool

    // Internal phases so we can run the two-step unlock animation.
    @State private var showingIcon: Bool = false
    @State private var isUnlocking: Bool = false   // true during the "flash open lock" phase

    // Keep previous value so we can distinguish lock→unlock vs the initial render.
    @State private var previouslyLocked: Bool = false

    var body: some View {
        Group {
            if showingIcon {
                Image(systemName: isUnlocking ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isUnlocking
                            ? Color.white.opacity(0.55)
                            : Color.white.opacity(0.75)
                    )
                    .scaleEffect(isUnlocking ? 0.85 : 1.0)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .opacity),
                            removal:   .scale(scale: 0.6).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: showingIcon)
        .animation(.spring(response: 0.30, dampingFraction: 0.65), value: isUnlocking)
        .onChange(of: isLocked) { _, newLocked in
            if newLocked {
                // Screen just locked — pop the lock icon in.
                isUnlocking = false
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    showingIcon = true
                }
            } else {
                // Screen just unlocked — flash the open-lock, then fade out.
                isUnlocking = true
                // After a short display of the open lock, fade everything out.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.80)) {
                        showingIcon = false
                    }
                    // Reset the unlocking flag once the fade is done.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        isUnlocking = false
                    }
                }
            }
        }
        .onAppear {
            // If we appear while already locked (e.g. app launch on lock screen),
            // show the icon immediately without animation.
            if isLocked {
                showingIcon = true
                isUnlocking = false
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var locked = true
        var body: some View {
            ZStack {
                Color.black
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(width: 185, height: 38)

                LockNotchOverlay(isLocked: locked)
            }
            .frame(width: 300, height: 80)
            .background(Color.gray.opacity(0.2))
            .onTapGesture { locked.toggle() }
        }
    }
    return PreviewWrapper()
}

