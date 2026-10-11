//
//  ContentView.swift
//  DiskDude
//
//  Reconstructed from metadata: ContentView holds the EnvironmentObject
//  and ColorScheme; layout = TopBar (tab bar with matched geometry) over
//  the active tab's content, with the CleanupQueueView sheet and
//  InspectorView trailing panel.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQueue = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider()
            HStack(spacing: 0) {
                mainContent
                if viewModel.showInspector {
                    Divider()
                    InspectorView()
                        .frame(width: 300)
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .sheet(isPresented: $showQueue) {
            CleanupQueueView()
        }
        .onAppear {
            viewModel.refreshDiskInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chooseScanFolder)) { _ in
            chooseFolder()
        }
        .environment(\.showQueueSheet, $showQueue)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.tab {
        case .explore:
            if case .scanning(let files) = viewModel.status {
                ScanningView(filesScanned: files,
                             bytesScanned: viewModel.scannedBytes,
                             currentPath: viewModel.currentScanPath)
            } else if viewModel.root != nil {
                ExploreView()
                    .id(viewModel.generation)
            } else {
                EmptyScanView()
            }
        case .duplicates:
            DuplicatesView()
        case .applications:
            AppUninstallerView()
        case .monitor:
            MonitorView()
        case .snapshots:
            SnapshotsView()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "DiskDude measures the size of files in the folder you pick. Nothing is moved or deleted unless you confirm it."
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.scan(root: url)
        }
    }
}

private struct ShowQueueSheetKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var showQueueSheet: Binding<Bool> {
        get { self[ShowQueueSheetKey.self] }
        set { self[ShowQueueSheetKey.self] = newValue }
    }
}
