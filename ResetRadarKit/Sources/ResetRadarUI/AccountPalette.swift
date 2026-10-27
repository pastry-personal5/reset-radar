import Foundation
import SwiftUI

public enum AccountPaletteFamily: String, Sendable, Equatable {
    case lavender
    case mint
    case peach
}

public enum AccountPaletteAppearance: Sendable {
    case light
    case lightIncreased
    case dark
    case darkIncreased
}

public struct PaletteRGB: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var color: Color { Color(red: red, green: green, blue: blue) }

    public func contrastRatio(with other: PaletteRGB) -> Double {
        let bright = max(luminance, other.luminance)
        let dark = min(luminance, other.luminance)
        return (bright + 0.05) / (dark + 0.05)
    }

    private var luminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    private static func linear(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

/// Stable pastel family assigned by the global account number, independent of display order and
/// allowance state. The first version supports three simultaneous accounts; later numbers cycle
/// without changing the established #1 through #3 mapping.
public struct AccountPalette: Sendable, Equatable {
    public let family: AccountPaletteFamily

    public init(accountNumber: Int) {
        family =
            switch ((max(accountNumber, 1) - 1) % 3) + 1 {
            case 1: .lavender
            case 2: .mint
            default: .peach
            }
    }

    public func surface(_ appearance: AccountPaletteAppearance) -> PaletteRGB {
        colors(appearance).surface
    }

    public func foreground(_ appearance: AccountPaletteAppearance) -> PaletteRGB {
        colors(appearance).foreground
    }

    private func colors(_ appearance: AccountPaletteAppearance) -> PaletteColors {
        switch family {
        case .lavender: Self.lavender(appearance)
        case .mint: Self.mint(appearance)
        case .peach: Self.peach(appearance)
        }
    }

    private static func lavender(_ appearance: AccountPaletteAppearance) -> PaletteColors {
        switch appearance {
        case .light:
            PaletteColors(
                surface: PaletteRGB(red: 0.88, green: 0.82, blue: 0.98),
                foreground: PaletteRGB(red: 0.20, green: 0.12, blue: 0.32))
        case .lightIncreased:
            PaletteColors(
                surface: PaletteRGB(red: 0.94, green: 0.91, blue: 1.00),
                foreground: PaletteRGB(red: 0.12, green: 0.05, blue: 0.22))
        case .dark:
            PaletteColors(
                surface: PaletteRGB(red: 0.26, green: 0.19, blue: 0.38),
                foreground: PaletteRGB(red: 0.95, green: 0.91, blue: 1.00))
        case .darkIncreased:
            PaletteColors(
                surface: PaletteRGB(red: 0.18, green: 0.10, blue: 0.30),
                foreground: PaletteRGB(red: 1.00, green: 0.97, blue: 1.00))
        }
    }

    private static func mint(_ appearance: AccountPaletteAppearance) -> PaletteColors {
        switch appearance {
        case .light:
            PaletteColors(
                surface: PaletteRGB(red: 0.78, green: 0.94, blue: 0.86),
                foreground: PaletteRGB(red: 0.08, green: 0.27, blue: 0.18))
        case .lightIncreased:
            PaletteColors(
                surface: PaletteRGB(red: 0.88, green: 0.98, blue: 0.92),
                foreground: PaletteRGB(red: 0.02, green: 0.19, blue: 0.10))
        case .dark:
            PaletteColors(
                surface: PaletteRGB(red: 0.12, green: 0.32, blue: 0.23),
                foreground: PaletteRGB(red: 0.88, green: 1.00, blue: 0.93))
        case .darkIncreased:
            PaletteColors(
                surface: PaletteRGB(red: 0.06, green: 0.23, blue: 0.14),
                foreground: PaletteRGB(red: 0.95, green: 1.00, blue: 0.97))
        }
    }

    private static func peach(_ appearance: AccountPaletteAppearance) -> PaletteColors {
        switch appearance {
        case .light:
            PaletteColors(
                surface: PaletteRGB(red: 0.98, green: 0.85, blue: 0.76),
                foreground: PaletteRGB(red: 0.31, green: 0.15, blue: 0.08))
        case .lightIncreased:
            PaletteColors(
                surface: PaletteRGB(red: 1.00, green: 0.91, blue: 0.84),
                foreground: PaletteRGB(red: 0.24, green: 0.08, blue: 0.02))
        case .dark:
            PaletteColors(
                surface: PaletteRGB(red: 0.38, green: 0.22, blue: 0.14),
                foreground: PaletteRGB(red: 1.00, green: 0.93, blue: 0.87))
        case .darkIncreased:
            PaletteColors(
                surface: PaletteRGB(red: 0.28, green: 0.12, blue: 0.06),
                foreground: PaletteRGB(red: 1.00, green: 0.97, blue: 0.92))
        }
    }

    private struct PaletteColors {
        let surface: PaletteRGB
        let foreground: PaletteRGB
    }
}
