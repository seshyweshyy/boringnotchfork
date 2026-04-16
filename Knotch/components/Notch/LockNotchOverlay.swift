//
//  LockNotchOverlay.swift
//  boringNotch
//
//  Lock icon that appears inside the closed notch when the
//  screen is locked.  When unlocked it plays a smooth scale+fade transition
//  back to the normal notch appearance.
//

import SwiftUI

// MARK: - Animator (ported from Atoll's LockIconAnimator)

/// Drives a 0 → 1 progress value with eased async stepping.
/// progress == 1.0 → locked (shackle closed)
/// progress == 0.0 → unlocked (shackle open)
@MainActor
final class LockIconAnimator: ObservableObject {
    @Published private(set) var progress: CGFloat

    private var animationTask: Task<Void, Never>?
    private let animationDuration: TimeInterval = 0.35
    private let animationSteps: Int = 48

    init(initiallyLocked: Bool) {
        progress = initiallyLocked ? 1.0 : 0.0
    }

    deinit {
        animationTask?.cancel()
    }

    func update(isLocked: Bool, animated: Bool = true) {
        let target: CGFloat = isLocked ? 1.0 : 0.0

        if !animated {
            animationTask?.cancel()
            progress = target
            return
        }

        guard abs(progress - target) > 0.0005 else {
            progress = target
            return
        }

        animationTask?.cancel()

        let startProgress = progress
        let delta = target - startProgress
        let stepNanoseconds = UInt64((animationDuration / Double(animationSteps)) * 1_000_000_000)

        animationTask = Task { [weak self] in
            guard let self else { return }
            for step in 0...animationSteps {
                if Task.isCancelled { return }
                if step > 0 { try? await Task.sleep(nanoseconds: stepNanoseconds) }
                let fraction = Double(step) / Double(animationSteps)
                let eased = 1.0 - pow(1.0 - max(0, min(1, fraction)), 3)
                progress = startProgress + CGFloat(eased) * delta
            }
            progress = target
        }
    }
}

// MARK: - Icon view (SF Symbols fallback; matches Atoll's LockIconProgressView)

struct LockIconProgressView: View {
    var progress: CGFloat           // 1.0 = locked, 0.0 = unlocked
    var iconColor: Color = .white

    var body: some View {
        Image(systemName: progress >= 0.5 ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(iconColor.opacity(0.75 + 0.10 * Double(1.0 - progress)))
            .scaleEffect(0.85 + 0.15 * Double(progress))
            .animation(.smooth(duration: 0.2), value: progress)
    }
}

// MARK: - Overlay wrapper used by ContentView

struct LockNotchOverlay: View {
    @ObservedObject var animator: LockIconAnimator

    var body: some View {
        LockIconProgressView(progress: animator.progress)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.6).combined(with: .opacity),
                    removal:   .scale(scale: 0.6).combined(with: .opacity)
                )
            )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var animator = LockIconAnimator(initiallyLocked: true)
        var body: some View {
            ZStack {
                Color.black
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(width: 185, height: 38)
                LockNotchOverlay(animator: animator)
            }
            .frame(width: 300, height: 80)
            .background(Color.gray.opacity(0.2))
            .onTapGesture { animator.update(isLocked: animator.progress < 0.5) }
        }
    }
    return PreviewWrapper()
}

