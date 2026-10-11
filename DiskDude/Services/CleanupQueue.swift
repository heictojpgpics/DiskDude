//
//  CleanupQueue.swift
//  DiskDude
//
//  Reconstructed from reflection metadata + decompiled logic.
//  Observable queue of items staged for deletion; moving to the
//  Trash uses NSWorkspace.recycle (recovered: 4 callsites).
//

import Foundation
import Combine
import AppKit

/// Items the user staged for deletion. Nothing is ever deleted without
/// explicit confirmation — items go to the Trash, not permanent deletion.
final class CleanupQueue: ObservableObject {

    struct Item: Identifiable, Hashable {
        let id: UUID
        let url: URL
        var size: Int64
        let reason: String

        init(id: UUID = UUID(), url: URL, size: Int64, reason: String) {
            self.id = id
            self.url = url
            self.size = size
            self.reason = reason
        }
    }

    @Published private(set) var items: [Item] = []

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    var count: Int { items.count }

    func contains(url: URL) -> Bool {
        items.contains { $0.url == url }
    }

    /// Stage an item ("Add to Cleanup Queue", "Keep this, stage the rest").
    func add(url: URL, size: Int64, reason: String) {
        guard !contains(url: url) else { return }
        items.append(Item(url: url, size: size, reason: reason))
    }

    /// Unstage an item ("Remove from cleanup").
    func remove(url: URL) {
        items.removeAll { $0.url == url }
    }

    func removeAll() {
        items.removeAll()
    }

    func toggle(url: URL, size: Int64, reason: String) {
        if contains(url: url) {
            remove(url: url)
        } else {
            add(url: url, size: size, reason: reason)
        }
    }

    /// Move every staged item to the Trash. Items go to the Trash, not
    /// permanent deletion — you can still recover them from there.
    /// Returns (movedCount, failedItems).
    @discardableResult
    func moveToTrash() async -> (Int, [Item]) {
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return (0, []) }
        var failed: [Item] = []
        var moved = 0
        // NSWorkspace.recycle — recovered from imports (recycleURLs:completionHandler:)
        let nsurls = urls as [NSURL]
        let succeeded = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            NSWorkspace.shared.recycle(nsurls) { error in
                cont.resume(returning: error == nil)
            }
        }
        if succeeded {
            moved = items.count
        } else {
            failed = items
        }
        if failed.isEmpty {
            items.removeAll()
        }
        return (moved, failed)
    }

    /// Reveal the first staged item in Finder (activateFileViewerSelectingURLs).
    func revealInFinder() {
        guard let first = items.first else { return }
        NSWorkspace.shared.activateFileViewerSelectingURLs([first.url])
    }
}
