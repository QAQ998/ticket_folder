import Foundation

enum PosterCacheStore {
    private static let folderName = "PosterCache"

    static func cachePoster(from remoteURL: URL?) async throws -> String? {
        guard let remoteURL else { return nil }
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        let directory = try posterDirectory()
        let filename = "\(UUID().uuidString).jpg"
        try data.write(to: directory.appending(path: filename), options: [.atomic])
        return filename
    }

    static func localURL(for filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        guard let directory = try? posterDirectory() else { return nil }
        return directory.appending(path: filename)
    }

    static func delete(_ filename: String?) {
        guard let filename, let directory = try? posterDirectory() else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: filename))
    }

    private static func posterDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: folderName, directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: directory.path()) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
