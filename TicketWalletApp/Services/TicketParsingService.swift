import Foundation

struct TicketParsingService {
    func parse(_ text: String) -> TicketDraft {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var draft = TicketDraft()
        draft.movieTitle = inferTitle(from: lines)
        draft.watchedAt = inferDate(from: text) ?? .now
        draft.cinema = firstLine(containing: ["影院", "影城", "Cinema", "CINEMA"], in: lines)
        draft.hall = firstLine(containing: ["厅", "Hall", "HALL"], in: lines)
        draft.seat = firstLine(containing: ["座", "排", "Seat", "SEAT"], in: lines)
        draft.ticketPrice = inferPrice(from: text)
        return draft
    }

    private func inferTitle(from lines: [String]) -> String {
        let ignored = ["影院", "影城", "厅", "座", "排", "时间", "票价", "订单", "取票", "电影票"]
        return lines.first { line in
            line.count >= 2 && !ignored.contains { line.localizedCaseInsensitiveContains($0) }
        } ?? ""
    }

    private func firstLine(containing keywords: [String], in lines: [String]) -> String {
        lines.first { line in
            keywords.contains { line.localizedCaseInsensitiveContains($0) }
        } ?? ""
    }

    private func inferPrice(from text: String) -> String {
        let pattern = #"([¥￥]\s?\d+(\.\d{1,2})?|\d+(\.\d{1,2})?\s?元)"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return "" }
        return String(text[match])
    }

    private func inferDate(from text: String) -> Date? {
        let patterns = [
            #"20\d{2}[-/.年]\d{1,2}[-/.月]\d{1,2}日?\s+\d{1,2}:\d{2}"#,
            #"20\d{2}[-/.年]\d{1,2}[-/.月]\d{1,2}日?"#
        ]

        for pattern in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let raw = String(text[range])
                .replacingOccurrences(of: "年", with: "-")
                .replacingOccurrences(of: "月", with: "-")
                .replacingOccurrences(of: "日", with: "")
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ".", with: "-")

            for format in ["yyyy-M-d H:mm", "yyyy-MM-dd H:mm", "yyyy-M-d", "yyyy-MM-dd"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = format
                if let date = formatter.date(from: raw) {
                    return date
                }
            }
        }

        return nil
    }
}
