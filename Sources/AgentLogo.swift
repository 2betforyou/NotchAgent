import SwiftUI

/// Small vector marks that identify each agent next to its usage. Drawn in code (no bundled
/// artwork) and kept simple so they stay legible at 12–20 pt.
struct AgentLogo: View {
    let kind: AgentKind
    var size: CGFloat = 18
    var body: some View {
        Group {
            switch kind {
            case .claude: ClaudeMark().fill(Palette.claude)
            case .gemini:
                GeminiMark().fill(LinearGradient(colors: [Palette.gemini, Color(red: 0.57, green: 0.47, blue: 0.78)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            case .codex: OpenAIMark().stroke(Palette.codex, style: StrokeStyle(lineWidth: size * 0.085, lineJoin: .round))
            case .shell: Image(systemName: "terminal").resizable().scaledToFit().foregroundStyle(Palette.mint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension AgentLogo {
    /// Menus render images, not SwiftUI shapes; rasterize the mark once per agent.
    @MainActor private static var menuIcons: [AgentKind: NSImage] = [:]
    @MainActor static func menuIcon(_ kind: AgentKind) -> Image {
        if kind == .shell { return Image(systemName: "terminal") }
        if let cached = menuIcons[kind] { return Image(nsImage: cached) }
        let renderer = ImageRenderer(content: AgentLogo(kind: kind, size: 16))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return Image(systemName: kind.symbol) }
        menuIcons[kind] = image
        return Image(nsImage: image)
    }
}

/// Claude's radial burst: chunky rounded rays of alternating length.
struct ClaudeMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2
        let rays = 12, width = r * 0.24
        for i in 0..<rays {
            let length = r * (i.isMultiple(of: 2) ? 1.0 : 0.8)
            let ray = CGRect(x: -width / 2, y: -length, width: width, height: length)
            let t = CGAffineTransform(translationX: rect.midX, y: rect.midY).rotated(by: CGFloat(i) * 2 * .pi / CGFloat(rays))
            p.addPath(Path(roundedRect: ray, cornerRadius: width / 2).applying(t))
        }
        return p
    }
}

/// Gemini's four-pointed sparkle with concave sides.
struct GeminiMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        let points = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)]
        p.move(to: points[0])
        for i in 1...4 { p.addQuadCurve(to: points[i % 4], control: c) }
        p.closeSubpath()
        return p
    }
}

/// Simplified OpenAI knot: six rounded links around a hexagonal hole, each offset tangentially
/// so neighbours interlace instead of meeting at the center.
struct OpenAIMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(rect.width, rect.height)
        let link = CGRect(x: -s * 0.13, y: -s * 0.47, width: s * 0.26, height: s * 0.36)
        for i in 0..<6 {
            let t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .rotated(by: CGFloat(i) * .pi / 3)
                .translatedBy(x: s * 0.1, y: 0)
            p.addPath(Path(roundedRect: link, cornerRadius: s * 0.13).applying(t))
        }
        return p
    }
}

/// Logo with the agent's name, stacked in cards or side by side in one-line strips.
struct AgentBadge: View {
    let kind: AgentKind
    var stacked = true
    /// When set, a "5분 전" line under the name says how fresh the numbers are.
    var updatedAt: Date? = nil
    var body: some View {
        let name = kind == .claude ? "Claude" : kind.name
        Group {
            if stacked {
                VStack(spacing: 5) {
                    AgentLogo(kind: kind, size: 20)
                    Text(name).font(.caption2.weight(.semibold))
                    if let updatedAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(UsageAge.label(since: updatedAt, now: context.date))
                                .font(.system(size: 9)).foregroundStyle(Palette.muted)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
                .frame(width: 46)
            } else {
                HStack(spacing: 6) {
                    AgentLogo(kind: kind, size: 13)
                    Text(name).font(.caption.weight(.semibold))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
