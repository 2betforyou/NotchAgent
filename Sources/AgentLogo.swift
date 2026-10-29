import SwiftUI

/// Bundled first-party marks. See THIRD-PARTY-NOTICES.md for provenance.
struct AgentLogo: View {
    let kind: AgentKind
    var size: CGFloat = 18
    var body: some View {
        Group {
            switch kind {
            case .claude, .gemini, .codex:
                if let image = Self.artwork[kind] {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            case .shell: Image(systemName: "terminal").resizable().scaledToFit().foregroundStyle(Palette.mint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension AgentLogo {
    @MainActor static let artwork: [AgentKind: NSImage] = {
        var images: [AgentKind: NSImage] = [:]
        for kind in [AgentKind.codex, .claude, .gemini] {
            if kind == .codex {
                images[kind] = NSImage(named: "CodexLogo")
                continue
            }
            if let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "png"),
               let image = NSImage(contentsOf: url) { images[kind] = image }
        }
        return images
    }()
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
