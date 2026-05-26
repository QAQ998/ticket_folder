import UIKit

enum TicketImageStore {
    private static let folderName = "TicketImages"

    static func save(_ image: UIImage) throws -> String {
        let directory = try imageDirectory()
        let filename = "\(UUID().uuidString).jpg"
        let url = directory.appending(path: filename)

        guard let data = image.jpegData(compressionQuality: 0.86) else {
            throw ImageStoreError.encodingFailed
        }

        try data.write(to: url, options: [.atomic])
        return filename
    }

    static func image(named filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        guard let directory = try? imageDirectory() else { return nil }
        return UIImage(contentsOfFile: directory.appending(path: filename).path())
    }

    static func delete(_ filename: String?) {
        guard let filename, let directory = try? imageDirectory() else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: filename))
    }

    private static func imageDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .documentDirectory,
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

enum ImageStoreError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "无法保存图片，请重新选择一张票根照片。"
    }
}
