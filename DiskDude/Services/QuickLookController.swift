import Foundation
import AppKit
import Quartz

/// QuickLook bridge (metadata-verified: subclass of QLPreviewPanel with
/// @objc numberOfPreviewItems(in:), previewPanel(_:previewItemAtIndex:),
/// init, .cxx_destruct). Serves as its own data source.
final class QuickLookController: QLPreviewPanel, QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    var url: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItem index: Int) -> QLPreviewItem {
        (url ?? URL(fileURLWithPath: "/")) as NSURL
    }

    /// Reveal the QuickLook panel for the selected file
    /// (sharedPreviewPanel -> setDataSource -> reloadData -> makeKeyAndOrderFront,
    /// recovered from the import call sequence).
    static func show(url: URL?) {
        guard let panel = QLPreviewPanel.shared else { return }
        let controller = QuickLookController.shared
        controller.url = url
        panel.dataSource = controller
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    static let shared: QuickLookController = {
        QuickLookController()
    }()

    static func hide() {
        if let panel = QLPreviewPanel.shared {
            panel.orderOut(nil)
        }
    }
}
