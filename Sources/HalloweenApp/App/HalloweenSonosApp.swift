import SwiftUI
import HalloweenCore
#if os(macOS)
import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); if let url = Bundle.main.url(forResource: "Haunt", withExtension: "icns"), let image = NSImage(contentsOf: url) { NSApp.applicationIconImage = image }; NSApp.activate(ignoringOtherApps: true) }
}
#endif
@main struct HalloweenSonosApp: App {
    @StateObject private var store = AppStore()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .tint(.orange)
                .preferredColorScheme(.dark)
                .task {
                    #if SWIFT_PACKAGE
                    let bundle = Bundle.main.bundlePath.hasSuffix(".app") ? Bundle.main : Bundle.module
                    #else
                    let bundle = Bundle.main
                    #endif
                    do {
                        let (catalog, urls) = try SoundLibrary.load(bundle: bundle)
                        store.configureSounds(urls, catalog: catalog)
                    } catch { store.error = error.localizedDescription }
                    if store.speakers.isEmpty && !store.scanning { await store.scan() }
                }
                #if os(macOS)
                .frame(minWidth: 980, minHeight: 700)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1580, height: 1000)
        .commands {
            CommandGroup(after: .newItem) { Button(L10n.value("Geräte suchen")) { Task { await store.scan() } }.keyboardShortcut("r", modifiers: .command).disabled(store.playback.running || store.scanning) }
            CommandMenu("Halloween") { Button(L10n.value("Szene stoppen")) { store.stopAll() }.keyboardShortcut(".", modifiers: .command) }
        }
        #endif
    }
}
