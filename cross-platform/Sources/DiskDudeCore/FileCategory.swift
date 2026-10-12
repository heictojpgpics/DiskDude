//
//  FileCategory.swift
//  DiskDudeCore
//
//  Byte-exact port of DiskDude 1.0.1's extension tables, recovered from
//  __cstring (the original stores each list as ONE space-separated
//  literal and splits at runtime). Order matters: video -> audio ->
//  image -> document -> developer -> archive -> other, exactly as the
//  binary's match cascade.
//

import Foundation

public enum FileCategory: String, CaseIterable, Sendable {
    case video, audio, image, document, developer, archive, other, folder, app

    /// Exact space-separated literals from the binary.
    public static let videoExtensions = "mp4 mov m4v mkv avi wmv flv webm mpg mpeg 3gp mts m2ts vob"
    public static let audioExtensions = "mp3 wav aac m4a flac ogg aiff aif alac wma opus mid midi caf m4b"
    public static let imageExtensions = "jpg jpeg png gif heic heif tiff tif bmp webp svg raw cr2 cr3 nef arw dng psd ai sketch fig ico icns exr"
    public static let documentExtensions = "pdf doc docx xls xlsx ppt pptx key pages numbers txt rtf md csv epub odt ods odp html htm tex"
    public static let developerExtensions = "swift m mm h c cc cpp hpp js mjs cjs ts tsx jsx json py pyc rb go rs java kt class jar o a dylib so node wasm map lock yml yaml toml xml sh zsh css scss less gradle pbxproj storyboard xib sql php vue svelte dart lua r ipynb tsbuildinfo d"
    public static let archiveExtensions = "zip gz tgz tar bz2 xz 7z rar dmg iso pkg xip zst lz4 cab"
    public static let otherExtensions = "plist log db sqlite sqlite3 sqlite-wal sqlite-shm db-wal db-shm wal shm cache dat ldb idx pack vmdk img sparseimage sparsebundle asar"

    public var title: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .image: return "Images"
        case .document: return "Documents"
        case .developer: return "Developer"
        case .archive: return "Archives"
        case .other: return "Other"
        case .folder: return "Folders"
        case .app: return "Apps"
        }
    }

    private static func matches(_ extensions: String, _ ext: String) -> Bool {
        extensions.split(separator: " ").contains { $0 == Substring(ext) }
    }

    /// Categorize by file extension (binary-verified cascade order).
    public static func category(forExtension ext: String) -> FileCategory {
        let e = ext.lowercased()
        if matches(videoExtensions, e) { return .video }
        if matches(audioExtensions, e) { return .audio }
        if matches(imageExtensions, e) { return .image }
        if matches(documentExtensions, e) { return .document }
        if matches(developerExtensions, e) { return .developer }
        if matches(archiveExtensions, e) { return .archive }
        if matches(otherExtensions, e) { return .other }
        return .other
    }

    /// The 64 KB minimum threshold recovered from the duplicate finder
    /// (`cmp x, 0x10000`): files below this are never hashed.
    public static let duplicateMinimumBytes: Int64 = 64 * 1024
}
