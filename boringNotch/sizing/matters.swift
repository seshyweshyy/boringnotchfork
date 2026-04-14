//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20

let openNotchSize: CGSize = .init(width: 640, height: 190)
// Add a wider size specifically for the home view
let openNotchHomeSize: CGSize = .init(width: 680, height: 190)

let windowSize: CGSize = .init(width: openNotchHomeSize.width, height: openNotchHomeSize.height + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 39), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 18.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}

/// Computes the open notch width for the home view based on which widgets are active.
func computedOpenNotchHomeWidth(
    showMusic: Bool,
    showCalendar: Bool,
    showMirror: Bool,
    cameraExpanded: Bool,
    cameraAvailable: Bool
) -> CGFloat {
    let showCam = showMirror && cameraAvailable && cameraExpanded
    let showCal = showCalendar

    // Widget widths (approximate, matching NotchHomeView layout)
    let musicWidth: CGFloat = showMusic ? 280 : 0
    let calWidth: CGFloat   = showCal   ? (showCam ? 185 : 230) : 0
    let camWidth: CGFloat   = showCam   ? 100 : 0

    // Divider + spacing
    var dividers: CGFloat = 0
    if showMusic && (showCal || showCam) { dividers += 1 }
    let dividerWidth: CGFloat = 1
    let spacing: CGFloat = (showCam && showCal) ? 10 : 15
    let panelCount = (showMusic ? 1 : 0) + (showCal ? 1 : 0) + (showCam ? 1 : 0)
    let spacingTotal = panelCount > 1 ? spacing * CGFloat(panelCount - 1) + dividers * dividerWidth : 0

    let contentWidth = musicWidth + calWidth + camWidth + spacingTotal
    // Add horizontal padding (matching ContentView's cornerRadius padding * 2 + layout padding * 2)
    let horizontalPad: CGFloat = 78
    let computed = contentWidth + horizontalPad
    return max(computed, openNotchSize.width) // never narrower than shelf width
}
