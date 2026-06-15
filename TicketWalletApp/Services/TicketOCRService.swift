import UIKit
@preconcurrency import Vision

struct TicketOCRLine {
    let text: String
    let alternatives: [String]
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Float
}

struct TicketOCRResult {
    let lines: [TicketOCRLine]

    var rawText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    var spatialText: String {
        [
            "按视觉行分组：\n\(rowGroupedText)",
            "按从上到下、从左到右排序的文本块：\n\(lineText)"
        ].joined(separator: "\n\n")
    }

    var judgeSpatialText: String {
        "按视觉行分组：\n\(rowGroupedText)"
    }

    private var lineText: String {
        lines.enumerated()
            .map { Self.formattedLine(number: $0.offset + 1, line: $0.element) }
            .joined(separator: "\n")
    }

    private var rowGroupedText: String {
        let rows = Self.groupedRows(lines)
        return rows.enumerated()
            .map { rowIndex, rowLines in
                let content = rowLines.enumerated()
                    .map { lineIndex, line in
                        Self.formattedLine(number: lineIndex + 1, line: line)
                    }
                    .joined(separator: " | ")
                return "[row:\(rowIndex + 1)] \(content)"
            }
            .joined(separator: "\n")
    }

    var isSparse: Bool {
        lines.count < 3
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f", value * 100)
    }

    private static func confidence(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private static func formattedLine(number: Int, line: TicketOCRLine) -> String {
        let position = "x:\(percent(line.x)), y:\(percent(line.y)), w:\(percent(line.width)), h:\(percent(line.height))"
        let alternatives: String
        if line.alternatives.isEmpty {
            alternatives = ""
        } else {
            alternatives = " alternatives:[\(line.alternatives.joined(separator: " / "))]"
        }
        return "[#\(number) \(position), confidence:\(confidence(line.confidence))] \(line.text)\(alternatives)"
    }

    private static func groupedRows(_ lines: [TicketOCRLine]) -> [[TicketOCRLine]] {
        var rows: [[TicketOCRLine]] = []
        for line in lines {
            guard let lastRow = rows.indices.last else {
                rows.append([line])
                continue
            }

            let rowY = rows[lastRow].map(\.y).reduce(0, +) / Double(rows[lastRow].count)
            let threshold = max(line.height, rows[lastRow].map(\.height).max() ?? line.height) * 0.85
            if abs(line.y - rowY) <= threshold {
                rows[lastRow].append(line)
                rows[lastRow].sort { $0.x < $1.x }
            } else {
                rows.append([line])
            }
        }
        return rows
    }
}

struct TicketOCRService {
    func recognizeText(in image: UIImage) async throws -> String {
        try await recognize(in: image).rawText
    }

    func recognize(in image: UIImage) async throws -> TicketOCRResult {
        guard let normalizedImage = image.normalizedForOCR(),
              let cgImage = normalizedImage.cgImage else {
            throw OCRError.invalidImage
        }

        let orientation = CGImagePropertyOrientation(normalizedImage.imageOrientation)
        var allLines: [TicketOCRLine] = []
        for region in OCRRegion.ticketRegions {
            guard let croppedImage = cgImage.cropping(to: region.pixelRect(in: cgImage)) else { continue }
            for profile in OCRProfile.ticketProfiles {
                let lines = try await recognize(
                    cgImage: croppedImage,
                    orientation: orientation,
                    profile: profile,
                    region: region
                )
                allLines.append(contentsOf: lines)
            }
        }
        return TicketOCRResult(lines: Self.sortedSpatially(Self.mergedVariants(allLines)))
    }

    private func recognize(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        profile: OCRProfile,
        region: OCRRegion
    ) async throws -> [TicketOCRLine] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation -> TicketOCRLine? in
                    let candidates = observation.topCandidates(3)
                    guard let candidate = candidates.first else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    let alternatives = candidates
                        .dropFirst()
                        .map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0 != text }

                    let box = observation.boundingBox
                    return TicketOCRLine(
                        text: text,
                        alternatives: Array(alternatives.prefix(2)),
                        x: region.x + (box.minX * region.width),
                        y: region.y + ((1 - box.maxY) * region.height),
                        width: box.width * region.width,
                        height: box.height * region.height,
                        confidence: candidate.confidence
                    )
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = profile.usesLanguageCorrection
            request.recognitionLanguages = profile.recognitionLanguages
            request.customWords = profile.customWords
            request.minimumTextHeight = profile.minimumTextHeight

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func mergedVariants(_ lines: [TicketOCRLine]) -> [TicketOCRLine] {
        var clusters: [[TicketOCRLine]] = []
        for line in lines {
            if let index = clusters.firstIndex(where: { cluster in
                cluster.contains { existing in
                    areSameVisualTextBlock(existing, line)
                }
            }) {
                clusters[index].append(line)
            } else {
                clusters.append([line])
            }
        }

        return clusters.map(mergedCluster)
    }

    private static func areSameVisualTextBlock(_ lhs: TicketOCRLine, _ rhs: TicketOCRLine) -> Bool {
        let centerXDistance = abs((lhs.x + lhs.width / 2) - (rhs.x + rhs.width / 2))
        let centerYDistance = abs((lhs.y + lhs.height / 2) - (rhs.y + rhs.height / 2))
        let heightDistance = abs(lhs.height - rhs.height)
        let verticalThreshold = max(lhs.height, rhs.height) * 0.80
        let horizontalThreshold = max(max(lhs.width, rhs.width) * 0.20, 0.018)

        return centerYDistance <= verticalThreshold &&
            centerXDistance <= horizontalThreshold &&
            heightDistance <= max(lhs.height, rhs.height) * 0.90
    }

    private static func mergedCluster(_ cluster: [TicketOCRLine]) -> TicketOCRLine {
        let best = cluster.max { lhs, rhs in
            score(line: lhs) < score(line: rhs)
        } ?? cluster[0]
        let alternativeTexts = uniqueTexts(
            cluster.flatMap { [$0.text] + $0.alternatives },
            excluding: best.text,
            limit: 5
        )
        return TicketOCRLine(
            text: best.text,
            alternatives: alternativeTexts,
            x: best.x,
            y: best.y,
            width: best.width,
            height: best.height,
            confidence: best.confidence
        )
    }

    private static func score(line: TicketOCRLine) -> Double {
        let compactCount = line.text.replacingOccurrences(of: " ", with: "").count
        let lengthBonus = min(Double(compactCount), 16) * 0.018
        let semanticBonus = semanticTicketScore(line.text) * 0.05
        return Double(line.confidence) + lengthBonus + semanticBonus
    }

    private static func semanticTicketScore(_ text: String) -> Double {
        let keywords = ["票价", "座位", "影厅", "时间", "影片", "MOVIE", "HALL", "SEAT", "PRICE", "DTS", "IMAX", "排", "座", ":"]
        return Double(keywords.filter { text.localizedCaseInsensitiveContains($0) }.count)
    }

    private static func uniqueTexts(_ values: [String], excluding excluded: String, limit: Int) -> [String] {
        let normalizedExcluded = normalizedForDedup(excluded)
        var seen = Set([normalizedExcluded])
        var result: [String] = []
        for value in values.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            let normalized = normalizedForDedup(value)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(value)
            if result.count >= limit { break }
        }
        return result
    }

    private static func normalizedForDedup(_ text: String) -> String {
        text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "：", with: ":")
            .lowercased()
    }

    private static func sortedSpatially(_ lines: [TicketOCRLine]) -> [TicketOCRLine] {
        lines.sorted { lhs, rhs in
            let rowThreshold = max(lhs.height, rhs.height) * 0.65
            if abs(lhs.y - rhs.y) > rowThreshold {
                return lhs.y < rhs.y
            }
            return lhs.x < rhs.x
        }
    }
}

private struct OCRProfile {
    let recognitionLanguages: [String]
    let usesLanguageCorrection: Bool
    let minimumTextHeight: Float
    let customWords: [String]

    static let ticketProfiles: [OCRProfile] = [
        OCRProfile(
            recognitionLanguages: ["zh-Hans", "zh-Hant", "en-US"],
            usesLanguageCorrection: true,
            minimumTextHeight: 0.006,
            customWords: ticketCustomWords
        ),
        OCRProfile(
            recognitionLanguages: ["zh-Hans", "en-US", "zh-Hant"],
            usesLanguageCorrection: false,
            minimumTextHeight: 0.004,
            customWords: ticketCustomWords
        )
    ]

    private static let ticketCustomWords = [
        "电影", "影片", "影厅", "影院", "影城", "票价", "座位", "票类",
        "放映时间", "开场时间", "观影时间", "取票时间", "售票时间",
        "DTS:X", "DIS:X", "IMAX", "CINITY", "临境音", "杜比", "巨幕",
        "PRICE", "SEAT", "HALL", "TIME", "MOVIE", "TICKET", "SELLING",
        "RMB", "SERVICE", "CHARGE", "KIOSK", "Galaxy", "Cinema"
    ]
}

private struct OCRRegion {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    static let ticketRegions: [OCRRegion] = [
        OCRRegion(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
        OCRRegion(x: 0.00, y: 0.20, width: 0.72, height: 0.55),
        OCRRegion(x: 0.66, y: 0.10, width: 0.34, height: 0.78),
        OCRRegion(x: 0.30, y: 0.34, width: 0.42, height: 0.26),
        OCRRegion(x: 0.66, y: 0.50, width: 0.34, height: 0.36)
    ]

    func pixelRect(in image: CGImage) -> CGRect {
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        return CGRect(
            x: x * imageWidth,
            y: y * imageHeight,
            width: width * imageWidth,
            height: height * imageHeight
        ).integral
    }
}

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "这张图片暂时无法识别，请换一张更清晰的票根照片。"
    }
}

private extension UIImage {
    func normalizedForOCR() -> UIImage? {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
