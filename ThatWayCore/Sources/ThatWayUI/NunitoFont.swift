//
//  NunitoFont.swift
//  ThatWayUI
//
//  The bundled Nunito variable font and its named weight instances (Nunito-Regular … Nunito-Black).
//  The font file ships inside this package and is registered at launch by `ThatWayFonts.register()`
//  (call it once from each app's init), so the iPhone and the watch use exactly the same font.
//  Built on `Font.custom(_:size:relativeTo:)` so labels scale with Dynamic Type.
//

import SwiftUI
import CoreText

public enum ThatWayFonts {
    /// Registers the bundled Nunito font for this process. Safe to call more than once.
    public static func register() {
        guard let url = Bundle.module.url(forResource: "Nunito", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

public enum NunitoWeight: CGFloat {
    case regular = 400
    case semibold = 600
    case bold = 700
    case extraBold = 800
    case black = 900

    /// The PostScript name of this weight's named instance inside the variable font.
    public var postScriptName: String {
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

public enum Nunito {
    public static func font(_ size: CGFloat, _ weight: NunitoWeight) -> Font {
        // `CTFontCreateWithName` quietly substitutes a default font when the name isn't registered, so
        // confirm the named instance is really the one we asked for before using it.
        let ct = CTFontCreateWithName(weight.postScriptName as CFString, size, nil)
        guard (CTFontCopyPostScriptName(ct) as String) == weight.postScriptName else {
            return .system(size: size, weight: weight.systemFallback)
        }
        return .custom(weight.postScriptName, size: size, relativeTo: relativeStyle(for: size))
    }

    /// Picks a Dynamic Type text style whose own scaling curve roughly matches how a
    /// label of this base size ought to grow.
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

public extension Font {
    static func nunito(_ size: CGFloat, _ weight: NunitoWeight) -> Font {
        Nunito.font(size, weight)
    }
}
