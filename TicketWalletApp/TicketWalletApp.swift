import SwiftData
import SwiftUI

@main
struct TicketWalletApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: MovieRecord.self)
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }

        #if DEBUG
        DebugTicketRecognitionRunner.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}

#if DEBUG
private enum DebugTicketRecognitionRunner {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--ticket-recognition-demo"),
              arguments.indices.contains(flagIndex + 1) else {
            return
        }

        let imagePath = arguments[flagIndex + 1]
        let outputPath = outputPath(from: arguments) ?? URL(fileURLWithPath: imagePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ticket-recognition-result.txt")
            .path

        write("", to: outputPath)
        Task {
            do {
                guard let image = UIImage(contentsOfFile: imagePath) else {
                    appendMarked("ERROR", "Unable to load image at path: \(imagePath)", to: outputPath)
                    return
                }

                let ocr = try await TicketOCRService().recognize(in: image)
                appendMarked("OCR", ocr.spatialText, to: outputPath)

                let service = TicketLLMRecognitionService()
                let rawResponse = try await service.debugRawResponse(fromSpatialOCR: ocr)
                appendMarked("MODEL_RAW", rawResponse, to: outputPath)

                let finalResult = try await service.recognizeTicket(fromSpatialOCR: ocr)
                let metadata = await movieMetadata(for: finalResult)
                let encoded = DebugTicketRecognitionPayload(from: finalResult, metadata: metadata)
                let data = try JSONEncoder.debugPrettyPrinted.encode(encoded)
                appendMarked("FINAL_RESULT", String(decoding: data, as: UTF8.self), to: outputPath)
            } catch {
                appendMarked("ERROR", error.localizedDescription, to: outputPath)
            }
        }
    }

    private static func movieMetadata(for result: TicketLLMRecognitionResult) async -> MovieMetadata? {
        let service = MovieMetadataService()
        guard service.isConfigured else { return nil }

        let queries = ([result.movieTitle, result.originalTitle] + result.candidateLines)
            .map(cleanedMovieMetadataQuery)
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { partialResult, query in
                if !partialResult.contains(query) {
                    partialResult.append(query)
                }
            }

        return try? await service.metadata(for: Array(queries.prefix(5)))
    }

    private static func cleanedMovieMetadataQuery(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        let noisePatterns = [
            #"\d{4}[-/.年]\d{1,2}"#,
            #"\d{1,2}[:：]\d{2}"#,
            #"\d+排.*座"#,
            #"\d{3,}"#
        ]
        if noisePatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            return ""
        }

        let noiseWords = [
            "影院", "影城", "影厅", "Cinema", "Galaxy", "座位", "票价", "服务费",
            "手续费", "取票", "售票", "票号", "工号", "副券", "扫码", "HALL",
            "TIME", "SEAT", "PRICE", "SERVICE", "CHARGE", "KIOSK"
        ]
        if noiseWords.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return ""
        }

        let removablePatterns = [
            #"[（(][^）)]*(2D|3D|4D|IMAX|CINITY|中国巨幕|杜比|国语|原版|数字|中文|字幕)[^）)]*[）)]"#,
            #"中文\s*[234]D"#,
            #"数字\s*[234]D"#,
            #"IMAX|CINITY|Cinity|中国巨幕|杜比全景声|杜比|全景声|国语|原版|中字|中文字幕|中文|英语|日语|韩语"#,
            #"[234]D"#
        ]
        for pattern in removablePatterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        text = text.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= 2 && text.count <= 24 ? text : ""
    }

    private static func outputPath(from arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: "--ticket-recognition-output"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return arguments[flagIndex + 1]
    }

    private static func appendMarked(_ marker: String, _ content: String, to path: String) {
        append("APP_CHAIN_\(marker)_BEGIN\n\(content)\nAPP_CHAIN_\(marker)_END\n", to: path)
    }

    private static func write(_ content: String, to path: String) {
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            print("APP_CHAIN_FILE_WRITE_ERROR \(error.localizedDescription)")
        }
    }

    private static func append(_ content: String, to path: String) {
        guard let data = content.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path),
           let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            write(content, to: path)
        }
    }
}

private struct DebugTicketRecognitionPayload: Encodable {
    let isMovieTicket: Bool
    let confidence: Double
    let shouldRequestManualReview: Bool
    let posterSideInfo: DebugPosterSideInfoPayload
    let movieTitle: String
    let originalTitle: String
    let year: String
    let director: String
    let watchedAt: String
    let cinema: String
    let hall: String
    let seat: String
    let ticketPrice: String
    let candidateLines: [String]

    init(from result: TicketLLMRecognitionResult, metadata: MovieMetadata?) {
        isMovieTicket = result.isMovieTicket
        confidence = result.confidence
        shouldRequestManualReview = result.shouldRequestManualReview
        posterSideInfo = DebugPosterSideInfoPayload(result: result, metadata: metadata)
        movieTitle = result.movieTitle
        originalTitle = metadata?.originalTitle ?? result.originalTitle
        year = metadata?.year ?? result.year
        director = metadata?.director ?? result.director
        watchedAt = result.watchedAt.map(Self.dateFormatter.string(from:)) ?? ""
        cinema = result.cinema
        hall = result.hall
        seat = result.seat
        ticketPrice = result.ticketPrice
        candidateLines = result.candidateLines
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct DebugPosterSideInfoPayload: Encodable {
    let title: String
    let releaseDate: String
    let director: String
    let runtime: String
    let doubanRating: String

    init(result: TicketLLMRecognitionResult, metadata: MovieMetadata?) {
        title = metadata?.title ?? result.movieTitle
        releaseDate = metadata?.releaseDate ?? ""
        director = metadata?.director ?? result.director
        runtime = metadata?.runtimeMinutes.map { "\($0) 分钟" } ?? ""
        doubanRating = metadata?.doubanRating ?? ""
    }
}

private extension JSONEncoder {
    static var debugPrettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
#endif
