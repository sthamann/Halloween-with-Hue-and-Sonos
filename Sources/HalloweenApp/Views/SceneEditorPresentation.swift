import SwiftUI
import HalloweenCore
#if os(macOS)
import AppKit

@MainActor private final class StudioWindow: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?
    private var closed: (() -> Void)?
    func show(store: AppStore, scene: HorrorScene, closed: @escaping () -> Void) {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        self.closed = closed
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1450, height: 950), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.value("Spukstudio")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SceneEditorView(store: store, scene: scene, closeEditor: { [weak self] in self?.window?.close() }).preferredColorScheme(.dark))
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("HauntSceneStudio")
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) {
        let old = window
        window = nil
        closed?(); closed = nil
        // Release SwiftUI after AppKit finishes the close callback.
        DispatchQueue.main.async { old?.contentView = nil }
    }
}
private struct StudioPresenter: ViewModifier {
    @Binding var item: HorrorScene?
    let store: AppStore
    @StateObject private var controller = StudioWindow()
    func body(content: Content) -> some View {
        content.onChange(of: item?.id) { _, id in
            if id != nil, let scene = item { controller.show(store: store, scene: scene) { item = nil } }
            else { controller.close() }
        }
    }
}

/// Window-scoped shortcuts. Text editors keep their standard copy/paste/delete behavior.
struct StudioShortcuts: NSViewRepresentable {
    var focusRequest: Int
    var copy: () -> Void
    var paste: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
    final class Coordinator {
        var actions: StudioShortcuts
        weak var view: NSView?
        var monitor: Any?
        var lastFocusRequest = 0
        init(_ actions: StudioShortcuts) { self.actions = actions }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
    final class ShortcutView: NSView { override var acceptsFirstResponder: Bool { true } }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView {
        let view = ShortcutView(); context.coordinator.view = view
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator = context.coordinator] event in
            guard let coordinator, let window = coordinator.view?.window, event.window === window,
                  window.attachedSheet == nil, !(window.firstResponder is NSTextView) else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c": coordinator.actions.copy()
                case "v": coordinator.actions.paste()
                case "d": coordinator.actions.duplicate()
                default: return event
                }
                return nil
            }
            if flags.isEmpty && (event.keyCode == 51 || event.keyCode == 117) { coordinator.actions.delete(); return nil }
            return event
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.actions = self
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor); coordinator.monitor = nil }
    }
}
#endif
extension View {
    @ViewBuilder func sceneEditor(item: Binding<HorrorScene?>, store: AppStore) -> some View {
        #if os(macOS)
        modifier(StudioPresenter(item: item, store: store))
        #else
        sheet(item: item) { scene in SceneEditorView(store: store, scene: scene) }
        #endif
    }
}
