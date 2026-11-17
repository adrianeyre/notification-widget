import Foundation
import UniformTypeIdentifiers

/// Custom Alert sound files, copied into the app's support folder (ALR-11).
public struct CustomSoundLibrary: Sendable {
    /// AIFF, WAV, MP3 and M4A.
    public static let allowedTypes: [UTType] = [.aiff, .wav, .mp3, .mpeg4Audio]
    public static let allowedExtensions: Set<String> = ["aif", "aiff", "wav", "mp3", "m4a"]

    public enum ImportError: Error, Equatable {
        case unsupportedType(String)
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// ~/Library/Application Support/Notification Widget/Sounds
    public static func standard() throws -> CustomSoundLibrary {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return CustomSoundLibrary(folder: support.appending(path: "Notification Widget/Sounds", directoryHint: .isDirectory))
    }

    /// Copies `source` into the folder and returns a reference to the copy. A file with
    /// the same name gets a numbered name, so earlier choices keep working.
    public func importSound(from source: URL) throws -> AlertSoundReference {
        let ext = source.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else { throw ImportError.unsupportedType(ext) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let base = source.deletingPathExtension().lastPathComponent
        var name = source.lastPathComponent
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: name).path) {
            name = "\(base) \(counter).\(source.pathExtension)"
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: folder.appending(path: name))
        return .file(name)
    }

    /// Where a custom sound lives, or `nil` for a system sound or a file that's gone.
    public func url(for sound: AlertSoundReference) -> URL? {
        guard case .file(let name) = sound else { return nil }
        let url = folder.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The custom sounds already imported, by name.
    public func importedSounds() -> [AlertSoundReference] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { Self.allowedExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { .file($0) }
    }
}
