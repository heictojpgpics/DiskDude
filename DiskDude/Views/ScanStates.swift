//
//  ScanStates.swift
//  DiskDude
//
//  EmptyScanView and ScanningView (recovered strings: hero title
//  "Map every byte on your Mac", tagline "A quick scan builds nine ways
//  to look at your disk. Nothing is ever deleted without you.",
//  "Choose Folder…", progress path).
//

import SwiftUI

struct EmptyScanView: View {
    @EnvironmentObject private var viewModel: ScanViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 33))
                .foregroundStyle(theme.ink)
            Text("Map every byte on your Mac")
                .font(.system(size: 26, weight: .bold))
            Text("A quick scan builds nine ways to look at your disk. Nothing is ever deleted without you.")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                ForEach(viewModel.recents, id: \.self) { url in
                    Button {
                        viewModel.scan(root: url)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10.5))
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.chip))
                    }
                    .buttonStyle(.plain)
                }
            }

            OutlineButton(title: "Choose Folder…",
                          systemImage: "folder.badge.plus",
                          height: 38,
                          fontSize: 13,
) {
                NotificationCenter.default.post(name: .chooseScanFolder, object: nil)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanningView: View {
    let filesScanned: Int
    let bytesScanned: Int64
    let currentPath: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(filesScanned % 100), total: 100)
                .frame(width: 320)
            Text("\(filesScanned.formatted()) files · \(formatBytes(bytesScanned))")
                .font(.system(size: 15, weight: .semibold))
            Text(currentPath)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 480)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.chip))
            Button("Cancel") {
                NotificationCenter.default.post(name: .cancelScan, object: nil)
            }
            .buttonStyle(LinkButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let cancelScan = Notification.Name("DiskDudeCancelScan")
}
