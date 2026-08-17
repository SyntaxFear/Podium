import Foundation

public enum PodiumPaths {
    /// Application Support/Podium/podium.sqlite (directory created on demand).
    /// Pass `under:` to relocate (tests).
    public static func databaseURL(under base: URL? = nil) throws -> URL {
        let root = try base ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = root.appending(path: "Podium", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "podium.sqlite")
    }
}
