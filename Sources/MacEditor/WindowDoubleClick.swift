import SwiftUI
import AppKit

/// Marks a background area (sidebar header / empty space) where a double-click zooms the window.
struct DoubleClickZoomZone: NSViewRepresentable {
    final class ZoneView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { WindowDoubleClick.zones.add(self) } else { WindowDoubleClick.zones.remove(self) }
        }
        // Never intercept events itself; the local event monitor does the work.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> ZoneView { ZoneView() }
    func updateNSView(_ nsView: ZoneView, context: Context) {}
}

/// Local NSEvent monitor: double-click in the titlebar/toolbar strip or in a marked zone
/// performs the system "double-click a window's title bar" action (zoom / minimize / none).
enum WindowDoubleClick {
    static let zones = NSHashTable<NSView>.weakObjects()
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            handle(event) ? nil : event
        }
    }

    /// Returns true if the event was consumed.
    private static func handle(_ event: NSEvent) -> Bool {
        guard event.clickCount == 2,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              let window = event.window,
              window.sheetParent == nil,
              window.styleMask.contains(.titled),
              window.styleMask.contains(.resizable),
              !(window is NSPanel) else { return false }

        let p = event.locationInWindow
        let inTitlebar = p.y > window.contentLayoutRect.maxY && !isOverControl(p, in: window)
        let inZone = zones.allObjects.contains { zone in
            guard zone.window === window, !zone.isHiddenOrHasHiddenAncestor else { return false }
            return zone.convert(zone.bounds, to: nil).contains(p)
        }
        guard inTitlebar || inZone else { return false }

        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
            window.miniaturize(nil)
        case "None":
            return inZone ? true : false   // titlebar: let the system do nothing as usual
        default:                            // "Maximize", "Fill" or unset
            window.zoom(nil)
        }
        return true
    }

    /// True if the point is over a button / control / toolbar item in the titlebar area.
    private static func isOverControl(_ p: NSPoint, in window: NSWindow) -> Bool {
        guard let frameView = window.contentView?.superview else { return false }
        let local = frameView.convert(p, from: nil)
        var v = frameView.hitTest(local)
        while let view = v, view !== frameView {
            if view is NSControl || view is NSTextView { return true }
            let name = NSStringFromClass(type(of: view))
            if name.contains("Button") || name.contains("ItemViewer") || name.contains("SearchField")
                || name.contains("Segmented") || name.contains("PlatformView") {
                return true
            }
            v = view.superview
        }
        return false
    }
}
