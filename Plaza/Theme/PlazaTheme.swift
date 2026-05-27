// PlazaTheme.swift
// Design tokens de Plaza: colores adaptativos, tipografías personalizadas, espaciado y componente PlTag.

import SwiftUI
import UIKit

// MARK: - Colors

extension Color {
    static let plFg      = Color(light: 0x0e0c0a, dark: 0xf5f2ec)
    static let plMuted   = Color(light: 0x5c544a, dark: 0xa09888)
    static let plDim     = Color(light: 0x8e8675, dark: 0x7a7268)
    static let plHair    = Color(light: 0xd6cfbf, dark: 0x2e2a24)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}

// MARK: - Fonts

extension Font {
    static func plDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Bricolage Grotesque", size: size, relativeTo: size >= 32 ? .largeTitle : .title).weight(weight)
    }
    static func plSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Bricolage Grotesque", size: size, relativeTo: size >= 16 ? .body : .caption).weight(weight)
    }
    static func plSerifItalic(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif).italic()
    }
    static func plMono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    // Estilo tipo Playbill: serif condensado bold para encabezados de tarjeta
    static func plPlaybill(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .serif)
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable {
    case plaza, multicolor

    var displayName: String {
        switch self {
        case .plaza:      return "Plaza"
        case .multicolor: return "Multicolor"
        }
    }

    var cardLeft: Color {
        switch self {
        case .plaza:      return Color(light: 0xC4714A, dark: 0xD48A65)
        case .multicolor: return Color(light: 0xD63BAA, dark: 0xE855BE) // magenta
        }
    }

    var cardCenter: Color {
        switch self {
        case .plaza:      return Color(light: 0xD4A44C, dark: 0xE0B862)
        case .multicolor: return Color(light: 0x1BBCD6, dark: 0x28CCE8) // cyan
        }
    }

    var cardRight: Color {
        switch self {
        case .plaza:      return Color(light: 0xE8C57A, dark: 0xC8A24A)
        case .multicolor: return Color(light: 0xF2C408, dark: 0xF0D040) // amarillo cálido
        }
    }

    var accent: Color {
        switch self {
        case .plaza:      return Color(light: 0xc5832b, dark: 0xd4923a)
        case .multicolor: return Color(light: 0xD63BAA, dark: 0xE855BE) // magenta como CTA
        }
    }

    var bg: Color {
        switch self {
        case .plaza:      return Color(light: 0xFBF8F1, dark: 0x1C1814)
        case .multicolor: return Color(light: 0xF8F8FA, dark: 0x111114)
        }
    }

    var surface: Color {
        switch self {
        case .plaza:      return Color(light: 0xF3EEE2, dark: 0x242018)
        case .multicolor: return Color(light: 0xEEEEF2, dark: 0x1E1E24)
        }
    }

    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "plaza_theme") ?? "") ?? .plaza
    }
}

// MARK: - Card Colors (theme-aware)

extension Color {
    static var plBg: Color      { AppTheme.current.bg }
    static var plSurface: Color { AppTheme.current.surface }
    static var plAccent: Color  { AppTheme.current.accent }
    static var plCardLeft: Color   { AppTheme.current.cardLeft }
    static var plCardCenter: Color { AppTheme.current.cardCenter }
    static var plCardRight: Color  { AppTheme.current.cardRight }
}

// MARK: - iPad Sidebar Environment

private struct IPadSidebarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isIPadSidebar: Bool {
        get { self[IPadSidebarKey.self] }
        set { self[IPadSidebarKey.self] = newValue }
    }
}

// MARK: - Spacing

enum PlSpace {
    static let gutter: CGFloat = 22
    static let cardRadius: CGFloat = 14
    static let sectionSpacing: CGFloat = 28
}

// MARK: - Tag (mono uppercase label)

struct PlTag: View {
    let text: String
    var color: Color = .plMuted
    var body: some View {
        Text(text.uppercased())
            .font(.plMono(10))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}
