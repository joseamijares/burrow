import AppKit
import SwiftUI

/// The tokens from the Paper file "Burrow — Mac cleaner (powered by Mole)",
/// page "Burrow v2 — Jamak style" (Jamak Memory style), with the prototype's dark values.
public enum Ink {
    static func c(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let v = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
    public static let paper = c(0xF0F0E9, 0x141615)
    public static let panel = c(0xF7F7F3, 0x1A1D1B)
    public static let sage = c(0xE1E7DC, 0x25302B)
    public static let ink = c(0x151716, 0xECEDE6)
    public static let ink2 = c(0x2A2D2B, 0xD5D8D2)
    public static let muted = c(0x595D5A, 0xA4ABA5)
    public static let muted2 = c(0x6B706C, 0x8F9690)
    public static let rule = c(0xBAC3BC, 0x343C36)
    public static let ruleStrong = c(0x7B877E, 0x5E6A61)
    public static let divider = c(0xC7CCC7, 0x2C332E)
    public static let deepSage = c(0x31564E, 0x93C7B3)
    public static let electric = c(0xA8EEEF, 0x1C4A4C)
    public static let onElectric = c(0x151716, 0xE6FBFB)
    public static let onElectricMuted = c(0x315B5C, 0xA8D9DA)
    public static let cyan = Color(red: 0, green: 0xD1 / 255, blue: 0xF1 / 255)
    public static let neg = c(0xA1282E, 0xF08C8C)
    public static let negGround = c(0xF9E8E5, 0x3A2020)
    public static let warn = c(0x7A5A12, 0xE4C57D)
    public static let warnGround = c(0xF1EAD3, 0x342D1B)
    public static let button = c(0x151716, 0xECEDE6)
    public static let onButton = c(0xF0F0E9, 0x141615)
}

public enum Typo {
    /// Schibsted Grotesk (bundled), falling back to Helvetica Neue.
    public static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .custom("Schibsted Grotesk", size: size).weight(weight) }
    public static func body(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font { .custom("Helvetica Neue", size: size).weight(weight) }
    public static func mono(_ size: CGFloat = 12, _ weight: Font.Weight = .regular) -> Font { .custom("JetBrains Mono", size: size).weight(weight) }
}

// MARK: - Building blocks

struct PrimaryButton: ButtonStyle {
    var danger = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(14, .medium))
            .padding(.horizontal, 16).frame(height: 36)
            .foregroundStyle(danger ? Ink.paper : Ink.onButton)
            .background(danger ? Ink.neg : Ink.button, in: RoundedRectangle(cornerRadius: 2))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

struct GhostButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(14, .medium))
            .padding(.horizontal, 16).frame(height: 36)
            .foregroundStyle(Ink.ink)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.ruleStrong))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

struct LinkButton: ButtonStyle {
    var negative = false
    var size: CGFloat = 14
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(size, .medium))
            .foregroundStyle(negative ? Ink.neg : Ink.ink)
            .underline(!negative, color: Ink.ink.opacity(0.6))
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

struct Checkbox: View {
    enum State { case on, off, mixed }
    var state: State
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(state == .on ? Ink.ink : state == .mixed ? Ink.ruleStrong : Color.clear)
                RoundedRectangle(cornerRadius: 2)
                    .stroke(state == .off ? Ink.ruleStrong : Color.clear, lineWidth: 1.5)
                if state != .off {
                    Image(systemName: state == .on ? "checkmark" : "minus").font(.system(size: 9, weight: .heavy)).foregroundStyle(Ink.paper)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(state == .on ? "checked" : state == .mixed ? "mixed" : "unchecked")
    }
    init(_ on: Bool, action: @escaping () -> Void) { state = on ? .on : .off; self.action = action }
    init(state: State, action: @escaping () -> Void) { self.state = state; self.action = action }
}

struct Tag: View {
    enum Tone { case ok, warn, neg, plain }
    var text: String
    var tone: Tone = .ok
    var body: some View {
        Text(text).font(Typo.body(12, .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(tone == .warn ? Ink.warn : tone == .neg ? Ink.neg : tone == .plain ? Ink.muted : Ink.deepSage)
            .background(tone == .warn ? Ink.warnGround : tone == .neg ? Ink.negGround : tone == .plain ? Color.clear : Ink.sage, in: RoundedRectangle(cornerRadius: 2))
            .fixedSize()
    }
}

struct SectionHead<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(title).font(Typo.display(24, .medium)).tracking(-0.6)
                Spacer()
                trailing.font(Typo.body(14)).foregroundStyle(Ink.muted)
            }
            .padding(.bottom, 12)
            Rectangle().fill(Ink.ink).frame(height: 1)
        }
    }
}

extension SectionHead where Trailing == Text {
    init(_ title: String, _ trailing: String = "") { self.title = title; self.trailing = Text(trailing) }
}

struct RuledRow<Content: View>: View {
    var minHeight: CGFloat = 50
    var rule = true
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) { content }
                .frame(minHeight: minHeight)
                .padding(.vertical, 6)
            if rule { Rectangle().fill(Ink.rule).frame(height: 1) }
        }
    }
}

struct SizeText: View {
    var bytes: Double
    var width: CGFloat = 84
    var strong = false
    var body: some View {
        Text(bytes > 0 ? Fmt.bytes(bytes) : "–")
            .font(Typo.mono(13, strong ? .medium : .regular)).monospacedDigit()
            .frame(width: width, alignment: .trailing)
    }
}

struct Meter: View {
    var fraction: Double
    var color: Color = Ink.ink
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Ink.sage)
                Rectangle().fill(color).frame(width: max(2, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
        .frame(minWidth: 60)
    }
}

struct Banner<Actions: View>: View {
    var text: String
    var info = false
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(spacing: 12) {
            Text(text).font(Typo.body(13)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .foregroundStyle(info ? Ink.ink : Ink.warn)
        .background(info ? Ink.sage : Ink.warnGround, in: RoundedRectangle(cornerRadius: 2))
    }
}

struct Progress: View {
    var text: String
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(text).font(Typo.body(14)).foregroundStyle(Ink.muted)
        }
        .padding(.vertical, 16)
    }
}

struct Empty: View {
    var text: String
    var body: some View {
        Text(text).font(Typo.body(15)).foregroundStyle(Ink.muted).padding(.vertical, 28).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Lede: View {
    var text: String
    var size: CGFloat = 15
    var body: some View {
        Text(text).font(Typo.body(size)).lineSpacing(size == 15 ? 7 : 4).foregroundStyle(Ink.muted)
            .frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}

/// Page head: big title, lede, optional controls at the right.
struct PageHead<Controls: View>: View {
    var title: String
    var lede: String
    @ViewBuilder var controls: Controls
    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Typo.display(48, .heavy)).tracking(-1.9).lineLimit(2).minimumScaleFactor(0.6)
                Lede(text: lede)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controls
        }
    }
}

/// The Tunnel mark: concentric arches and the cyan square.
struct TunnelMark: View {
    var size: CGFloat = 26
    var body: some View {
        Canvas { ctx, s in
            let k = s.width / 26
            func arch(_ x0: CGFloat, _ r: CGFloat, _ top: CGFloat, _ color: Color, close: Bool = false) {
                var p = Path()
                p.move(to: CGPoint(x: x0 * k, y: 23 * k))
                p.addLine(to: CGPoint(x: x0 * k, y: top * k))
                p.addArc(center: CGPoint(x: (x0 + r) * k, y: top * k), radius: r * k, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.addLine(to: CGPoint(x: (x0 + 2 * r) * k, y: 23 * k))
                if close { p.closeSubpath() }
                ctx.stroke(p, with: .color(color), lineWidth: 2.4 * k)
            }
            arch(3, 9, 12, Ink.ink, close: true)
            arch(7.4, 4.6, 13, Ink.deepSage)
            arch(10.9, 1.1, 13.4, Ink.ink)
            ctx.fill(Path(CGRect(x: 21.6 * k, y: 0.6 * k, width: 3.6 * k, height: 3.6 * k)), with: .color(Ink.cyan))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The cyan chip beside big numbers.
struct ChipSquare: View {
    var body: some View {
        Rectangle().fill(Ink.electric).frame(width: 32, height: 32).rotationEffect(.degrees(-12))
    }
}

struct BigNumber: View {
    var value: String
    var negative = false
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(value).font(Typo.display(112, .heavy)).tracking(-5).foregroundStyle(negative ? Ink.neg : Ink.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
            ChipSquare().padding(.top, 12)
        }
    }
}
