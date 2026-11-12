import SwiftUI

struct Palette {
    var dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var background: Color { Color(hex: dark ? 0x201F1D : 0xF8F5EF) }
    var sidebar: Color { Color(hex: dark ? 0x262522 : 0xF0EBE2) }
    var panel: Color { Color(hex: dark ? 0x2B2A27 : 0xFFFDFA) }
    var ink: Color { Color(hex: dark ? 0xEEE9DF : 0x3B362F) }
    var secondary: Color { Color(hex: dark ? 0xB3ADA2 : 0x847B6F) }
    var faint: Color { Color(hex: dark ? 0x827C73 : 0xA49B8F) }
    var line: Color { Color(hex: dark ? 0x413E38 : 0xE8E1D6) }
    var selected: Color { Color(hex: dark ? 0x39352F : 0xF3EDE2) }
    var accent: Color { Color(hex: dark ? 0xD3C1A7 : 0x806A50) }
    var button: Color { Color(hex: dark ? 0xE5DAC7 : 0x494339) }
    var onButton: Color { Color(hex: dark ? 0x292720 : 0xFFF9EF) }
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

struct Surface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        content.background(Palette(scheme).panel)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette(scheme).line, lineWidth: 1))
    }
}

struct QuietButton: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette(scheme).ink).padding(.horizontal, 13).padding(.vertical, 9)
            .background(Palette(scheme).selected.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CheckMark: View {
    @Environment(\.colorScheme) private var scheme
    var selected: Bool
    var mixed: Bool = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(selected ? Palette(scheme).accent : Color.clear)
            RoundedRectangle(cornerRadius: 5).stroke(selected ? Palette(scheme).accent : Palette(scheme).faint.opacity(0.5), lineWidth: 1.2)
            if selected { Image(systemName: mixed ? "minus" : "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette(scheme).panel) }
        }.frame(width: 18, height: 18)
    }
}

struct MemoryCardArt: View {
    @Environment(\.colorScheme) private var scheme
    var small = false
    var body: some View {
        let p = Palette(scheme)
        ZStack {
            Ellipse().fill(p.line.opacity(0.5)).frame(width: 116, height: 19).offset(y: 53)
            card(p, label: "little moments").rotationEffect(.degrees(-12)).offset(x: -17, y: -3)
            card(p, label: "files / memories").rotationEffect(.degrees(9)).offset(x: 18, y: 3)
            Image(systemName: "sparkle").font(.system(size: 18, weight: .light)).foregroundStyle(p.accent.opacity(0.65)).offset(x: 70, y: -42)
            Circle().fill(p.accent.opacity(0.35)).frame(width: 4).offset(x: -68, y: 17)
        }.frame(width: 172, height: 136).scaleEffect(small ? 0.73 : 1)
    }
    private func card(_ p: Palette, label: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<6) { _ in RoundedRectangle(cornerRadius: 1.5).fill(p.accent.opacity(0.4)).frame(width: 6, height: 13) }
            }.padding(.top, 8)
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Image(systemName: "sun.horizon").font(.system(size: 23, weight: .ultraLight))
                Text(label).font(.system(size: 6.5, weight: .medium, design: .rounded))
            }.foregroundStyle(p.accent).frame(maxWidth: .infinity).frame(height: 50).background(p.selected)
            Spacer(minLength: 7)
        }.frame(width: 76, height: 104).background(p.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.accent.opacity(0.35), lineWidth: 1.3))
            .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.06), radius: 8, x: 0, y: 4)
    }
}
