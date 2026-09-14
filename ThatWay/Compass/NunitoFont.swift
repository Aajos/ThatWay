//
//  NunitoFont.swift
//  ThatWay
//
//  Loads the bundled Nunito variable font and instances specific weights
//  (400/600/700/800/900) from its `wght` axis, matching the design's type scale.
//

import SwiftUI
import CoreText

enum NunitoWeight: CGFloat {
    case regular = 400
    case semibold = 600
    case bold = 700
    case extraBold = 800
    case black = 900
}

enum Nunito {
    /// TrueType 'wght' axis tag (the four ASCII bytes 'w','g','h','t' packed big-endian).
    private static let weightAxisTag = 0x77676874

    private static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "Nunito", withExtension: "ttf") else { return false }
        var error: Unmanaged<CFError>?
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }()

    static func font(_ size: CGFloat, _ weight: NunitoWeight) -> Font {
        guard registered else { return .system(size: size, weight: systemFallback(weight)) }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Nunito",
            kCTFontVariationAttribute: [weightAxisTag: weight.rawValue],
        ] as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return Font(ctFont)
    }

    private static func systemFallback(_ weight: NunitoWeight) -> Font.Weight {
        switch weight {
        case .regular: return .regular
        case .semibold: return .semibold
        case .bold: return .bold
        case .extraBold: return .heavy
        case .black: return .black
        }
    }
}

extension Font {
    static func nunito(_ size: CGFloat, _ weight: NunitoWeight) -> Font {
        Nunito.font(size, weight)
    }
}
