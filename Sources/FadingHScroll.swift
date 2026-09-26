import AppKit
import SwiftUI

/// Horizontal strip for tabs and folder chips: no scroll bar, but it keeps `target` in view,
/// fades only the edges that hide content, and scrolls with an ordinary (vertical) mouse wheel.
struct FadingHScroll<Content: View>: View {
    var target: AnyHashable?
    @ViewBuilder var content: () -> Content
    @State private var viewport: CGFloat = 0
    @State private var contentFrame: CGRect = .zero
    @State private var space = UUID()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                content()
                    .background(HorizontalWheel.Marker())
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ContentFrameKey.self, value: geo.frame(in: .named(space)))
                    })
            }
            .coordinateSpace(name: space)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { viewport = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in viewport = width }
            })
            .onPreferenceChange(ContentFrameKey.self) { contentFrame = $0 }
            .mask(fadeMask)
            .onAppear { if let target { proxy.scrollTo(target) } }
            .onChange(of: target) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target) }
            }
        }
    }
    private var fadeMask: some View {
        let hiddenLeading = contentFrame.minX < -1
        let hiddenTrailing = viewport > 0 && contentFrame.maxX > viewport + 1
        return HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(hiddenLeading ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(hiddenTrailing ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28)
        }
    }
}

private struct ContentFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Mouse wheels only send vertical deltas; over a marked strip they scroll it sideways.
@MainActor
enum HorizontalWheel {
    private static let strips = NSHashTable<NSScrollView>.weakObjects()
    private static var monitor: Any?

    struct Marker: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { MarkerView() }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }
    final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, let scrollView = enclosingScrollView { HorizontalWheel.register(scrollView) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    static func register(_ scrollView: NSScrollView) {
        strips.add(scrollView)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { handle(event) ? nil : event }
        }
    }
    static var registered: [NSScrollView] { strips.allObjects }

    /// Returns true when the event was used to scroll a strip.
    static func handle(_ event: NSEvent) -> Bool {
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard abs(dy) > abs(dx), let window = event.window else { return false }
        let point = event.locationInWindow
        for strip in strips.allObjects where strip.window === window {
            guard strip.convert(strip.bounds, to: nil).contains(point) else { continue }
            return scroll(strip, by: dy * (event.hasPreciseScrollingDeltas ? 1 : 10))
        }
        return false
    }
    @discardableResult
    static func scroll(_ strip: NSScrollView, by delta: CGFloat) -> Bool {
        guard let document = strip.documentView else { return false }
        let clip = strip.contentView
        let maxX = document.frame.width - clip.bounds.width
        guard maxX > 0 else { return false } // nothing hidden: let the event through
        var origin = clip.bounds.origin
        origin.x = min(maxX, max(0, origin.x - delta))
        clip.scroll(to: origin)
        strip.reflectScrolledClipView(clip)
        return true
    }
}
