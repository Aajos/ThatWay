//
//  NunitoFont.swift
//  ThatWay
//
//  Loads the bundled Nunito variable font and uses its named weight instances
//  (they ship inside the variable font as their own PostScript names — Nunito-Regular,
//  Nunito-SemiBold, Nunito-Bold, Nunito-ExtraBold, Nunito-Black) matching the design's
//  type scale. Built on `Font.custom(_:size:relativeTo:)` rather than a raw CoreText
//  instance so every label in the app automatically scales with the system's Dynamic
//  Type accessibility setting — no per-view plumbing required.
//

import SwiftUI
import UIKit

enum NunitoWeight: CGFloat {
    case regular = 400
    case semibold = 600
    case bold = 700
    case extraBold = 800
    case black = 900

    /// The PostScript name of this weight's named instance inside the variable font.
    var postScriptName: String {
        switch self {
        case .regular: return "Nunito-Regular"
        case .semibold: return "Nunito-SemiBold"
        case .bold: return "Nunito-Bold"
        case .extraBold: return "Nunito-ExtraBold"
        case .black: return "Nunito-Black"
        }
    }

    fileprivate var systemFallback: Font.Weight {
        switch self {
        case .regular: return .regular
        case .semibold: return .semibold
        case .bold: return .bold
        case .extraBold: return .heavy
        case .black: return .black
        }
    }
}

enum Nunito {
    /// The accessibility text-size slider's current boost, added to every Nunito size
    /// app-wide on top of whatever the system's own Dynamic Type setting already scales
    /// it by. `AppModel.extraTextSize` writes it on every change, and since practically
    /// every screen holds `@EnvironmentObject var app: AppModel`, that same `@Published`
    /// write already forces those views to re-evaluate `body` (and so re-read this) on
    /// its own, with no extra plumbing needed at each individual `.nunito(...)` call site.
    static var extraSize: CGFloat = 0

    static func font(_ size: CGFloat, _ weight: NunitoWeight) -> Font {
        let size = size + extraSize
        // Nunito.ttf is registered at launch via Info.plist's UIAppFonts — no runtime
        // CTFontManagerRegisterFontsForURL call needed (and calling it again here would
        // just report "already registered" as failure, which used to make this silently
        // fall back to a plain fixed-size system font that ignores Dynamic Type entirely).
        // Checking UIFont directly instead confirms the named instance is actually usable.
        guard UIFont(name: weight.postScriptName, size: size) != nil else {
            return .system(size: size, weight: weight.systemFallback)
        }
        return .custom(weight.postScriptName, size: size, relativeTo: relativeStyle(for: size))
    }

    /// Picks a Dynamic Type text style whose own scaling curve roughly matches how a
    /// label of this base size ought to grow — so a tiny caption and a big headline
    /// don't scale by the exact same ratio as accessibility sizes go up.
    private static func relativeStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11: return .caption2
        case ..<13: return .caption
        case ..<15: return .footnote
        case ..<16: return .subheadline
        case ..<18: return .callout
        case ..<20: return .body
        case ..<22: return .title3
        case ..<26: return .title2
        case ..<32: return .title
        default: return .largeTitle
        }
    }
}

extension Font {
    static func nunito(_ size: CGFloat, _ weight: NunitoWeight) -> Font {
        Nunito.font(size, weight)
    }
}
