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
        draft.cinema = inferCinema(from: lines)
        draft.hall = firstLine(containing: ["厅", "Hall", "HALL"], in: lines)
        draft.seat = firstLine(containing: ["座", "排", "Seat", "SEAT"], in: lines)
        draft.ticketPrice = inferPrice(from: text)
        return draft
    }

    private func inferTitle(from lines: [String]) -> String {
        for line in lines {
            guard let title = cleanedTitleCandidate(from: line) else { continue }
            return title
        }
        return ""
    }

    private func inferCinema(from lines: [String]) -> String {
        firstLine(containing: cinemaKeywords, in: lines)
    }

    private func firstLine(containing keywords: [String], in lines: [String]) -> String {
        lines.first { line in
            keywords.contains { line.localizedCaseInsensitiveContains($0) }
        } ?? ""
    }

    private func cleanedTitleCandidate(from line: String) -> String? {
        let candidate = stripTitleLabel(from: normalized(line))
        guard isLikelyMovieTitle(candidate) else { return nil }
        return candidate
    }

    private func stripTitleLabel(from line: String) -> String {
        let labels = ["影片名称", "电影名称", "影片名", "电影名", "片名", "影片", "电影"]
        for label in labels {
            if line.localizedCaseInsensitiveContains(label),
               let separatorRange = line.range(of: #"[:：]\s*"#, options: .regularExpression) {
                return String(line[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return line
    }

    private func isLikelyMovieTitle(_ line: String) -> Bool {
        let normalized = normalized(line)
        guard normalized.count >= 2 else { return false }
        guard !isTicketingPlatformLine(normalized) else { return false }
        guard !isCinemaLine(normalized) else { return false }
        guard !containsAny(titleNoiseKeywords, in: normalized) else { return false }
        guard !matchesAny(titleNoisePatterns, in: normalized) else { return false }
        return true
    }

    private func isTicketingPlatformLine(_ line: String) -> Bool {
        containsAny(ticketingPlatformKeywords, in: line)
    }

    private func isCinemaLine(_ line: String) -> Bool {
        containsAny(cinemaKeywords, in: line)
    }

    private func containsAny(_ keywords: [String], in line: String) -> Bool {
        keywords.contains { line.localizedCaseInsensitiveContains($0) }
    }

    private func matchesAny(_ patterns: [String], in line: String) -> Bool {
        patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
    }

    private func normalized(_ line: String) -> String {
        line
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var ticketingPlatformKeywords: [String] {
        [
            "猫眼", "淘票票", "大麦", "美团", "大众点评", "格瓦拉", "糯米",
            "娱票儿", "微票儿", "时光网", "票星球", "保利票务", "抖音电影",
            "支付宝", "微信支付", "微信电影票", "QQ电影票", "京东电影",
            "电影演出", "电影票", "取票码", "取票号", "出票平台"
        ]
    }

    private var cinemaKeywords: [String] {
        [
            "影院", "影城", "影厅", "电影院", "电影城", "电影公园", "Cinema", "CINEMA",
            "万达", "寰映", "CGV", "英皇", "百川", "百老汇", "Broadway", "UME",
            "博纳", "Bona", "金逸", "橙天嘉禾", "嘉禾", "中影", "星美", "耀莱",
            "卢米埃", "Lumiere", "SFC", "上影", "大地", "横店", "幸福蓝海",
            "保利", "珠影", "太平洋", "华谊兄弟", "华夏", "完美世界", "星轶",
            "杜比影院", "Dolby Cinema", "金逸影城",
            "万象影城", "卢米埃影城", "CGV影城", "英皇电影城"
        ]
    }

    private var titleNoiseKeywords: [String] {
        [
            "厅", "号厅", "影厅", "座", "排", "时间", "场次", "开场", "放映",
            "票价", "金额", "售价", "服务费", "订单", "订单号", "手机号",
            "会员", "卖品", "小食", "套餐", "二维码", "条形码", "验证码",
            "取票", "检票", "入场", "请提前", "禁止", "退改签", "儿童票",
            "学生票", "张数", "座位", "普通厅", "巨幕厅", "激光厅"
        ]
    }

    private var titleNoisePatterns: [String] {
        [
            #"^\d{1,2}[:：]\d{2}$"#,
            #"^\d{1,2}[:：]\d{2}\s+20\d{2}[-/.年]\d{1,2}[-/.月]\d{1,2}"#,
            #"^20\d{2}[-/.年]\d{1,2}[-/.月]\d{1,2}"#,
            #"^\d+(\.\d{1,2})?\s*元$"#,
            #"^[¥￥]\s*\d+(\.\d{1,2})?$"#,
            #"^\d+\s*排\s*\d+\s*座$"#,
            #"^\d+\s*号?厅$"#,
            #"^(IMAX|CINITY|杜比|杜比全景声|国语|原版|中字|字幕|中文|数字|2D|3D|4D|中国巨幕|\s)+$"#,
            #"^[A-Z0-9]{6,}$"#
        ]
    }
}
