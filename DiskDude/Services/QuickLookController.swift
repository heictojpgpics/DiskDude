//
//  QuickLookController.swift
//  DiskDude
//
//  Reconstructed from ObjC metadata: QuickLookController subclasses
//  QLPreviewPanel with numberOfPreviewItems(in:),
//  previewPanel(_:previewItemAt:) and an `url` ivar.
//

import Foundation
import AppKit
import Quartz

final class QuickLookController: QLPreviewPanel {

    var url: URL?

    override func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    override func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let url else { return nil }
        return url as NSURL
    }

    /// Reveal the QuickLook panel for the selected file
    /// (sharedPreviewPanel → setDataSource → reloadData → makeKeyAndOrderFront,
    /// recovered from the import call sequence).
    static func show(url: URL?) {
        guard let panel = QLPreviewPanel.sharedPreviewPanel(for: .mouse) else { return }
        let controller = QuickLookController.shared
        controller.url = url
        panel.dataSource = controller
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    static let shared: QuickLookController = {
        let c = QuickLookController()
        return c
    }()

    static func hide() {
        if let panel = QLPreviewPanel.sharedPreviewPanel(for: .mouse) {
            panel.orderOut(nil)
        }
    }
}
