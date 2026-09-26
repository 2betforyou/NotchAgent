import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drag-to-reorder for tabs and folder chips. Items move live as the pointer passes over
/// their neighbours. The payload uses a private type so a drop on the terminal is ignored
/// instead of typing an identifier into the shell.
extension UTType {
    static let notchAgentReorder = UTType(exportedAs: "app.notchagent.reorder")
}

extension View {
    func reorderable<ID: Hashable>(_ id: ID, dragging: Binding<ID?>, move: @escaping (ID, ID) -> Void) -> some View {
        onDrag {
            dragging.wrappedValue = id
            DragEnd.watch { dragging.wrappedValue = nil }
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.notchAgentReorder.identifier, visibility: .ownProcess) { done in
                done(Data(), nil); return nil
            }
            return provider
        }
        .onDrop(of: [.notchAgentReorder], delegate: ReorderDropDelegate(item: id, dragging: dragging, move: move))
    }
}

struct ReorderDropDelegate<ID: Hashable>: DropDelegate {
    let item: ID
    @Binding var dragging: ID?
    let move: (ID, ID) -> Void
    func dropEntered(info: DropInfo) {
        guard let dragged = dragging, dragged != item else { return }
        withAnimation(Motion.snappy) { move(dragged, item) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
}

/// SwiftUI reports no end for a drag that is cancelled or dropped elsewhere; clear the
/// "dragging" look as soon as the mouse button is released.
@MainActor
enum DragEnd {
    private static var timer: Timer?
    static func watch(_ ended: @escaping () -> Void) {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { t in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons == 0 else { return }
                t.invalidate()
                ended()
            }
        }
        RunLoop.main.add(t, forMode: .common) // keeps firing during the drag's event tracking
        timer = t
    }
}
