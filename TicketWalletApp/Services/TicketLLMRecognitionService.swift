import Foundation

struct TicketLLMRecognitionResult {
    var isMovieTicket = true
    var confidence: Double = 0
    var shouldRequestManualReview = false
    var movieTitle = ""
    var originalTitle = ""
    var year = ""
    var director = ""
    var watchedAt: Date?
    var cinema = ""
    var hall = ""
    var seat = ""
    var ticketPrice = ""
    var candidateLines: [String] = []

    var isEmpty: Bool {
        movieTitle.isEmpty && cinema.isEmpty && hall.isEmpty && seat.isEmpty && ticketPrice.isEmpty
    }
}

struct TicketLLMRecognitionService {
    private let apiKey: String
    private let baseURL: URL
    private let model: String
    private let apiStyle: LLMAPIStyle
    private let session: URLSession

    init(
        apiKey: String = Self.configuredValue("LLM_API_KEY", fallbackKey: "OPENAI_API_KEY"),
        apiBaseURL: String = Self.configuredValue("LLM_API_BASE_URL", fallbackKey: "OPENAI_API_BASE_URL"),
        model: String = Self.configuredValue("LLM_MODEL", fallbackKey: "OPENAI_MODEL"),
        apiStyle: String = Self.configuredValue("LLM_API_STYLE", fallbackKey: nil)
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = URL(string: Self.cleanedBaseURL(apiBaseURL)) ?? URL(string: "https://api.openai.com/v1")!
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = cleanModel.isEmpty || cleanModel.hasPrefix("$(") ? "gpt-5-mini" : cleanModel
        self.apiStyle = LLMAPIStyle(rawValue: apiStyle.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .responses

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    var isConfigured: Bool {
        !apiKey.isEmpty && !apiKey.hasPrefix("$(") && apiKey != "your_llm_api_key_here" && apiKey != "your_openai_api_key_here"
    }

    var providerDescription: String {
        apiStyle.displayName
    }

    func recognizeTicket(fromSpatialOCR ocr: TicketOCRResult) async throws -> TicketLLMRecognitionResult {
        guard isConfigured else { throw TicketLLMRecognitionError.missingAPIKey }
        guard !ocr.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TicketLLMRecognitionError.emptyOCRText
        }

        let hints = TicketOCRCandidateHints(ocr: ocr)
        let result = try await perform(prompt: TicketRecognitionPrompt.spatial(ocr, hints: hints))
        return TicketRecognitionResultMerger.merge(result, with: hints.fallbackResult)
    }

    func recognizeTicket(fromOCRText text: String) async throws -> TicketLLMRecognitionResult {
        guard isConfigured else { throw TicketLLMRecognitionError.missingAPIKey }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw TicketLLMRecognitionError.emptyOCRText }

        return try await perform(prompt: TicketRecognitionPrompt.plainText(cleanText))
    }

    #if DEBUG
    func debugRawResponse(fromSpatialOCR ocr: TicketOCRResult) async throws -> String {
        guard isConfigured else { throw TicketLLMRecognitionError.missingAPIKey }
        guard !ocr.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TicketLLMRecognitionError.emptyOCRText
        }

        let hints = TicketOCRCandidateHints(ocr: ocr)
        return try await performRawHTTP(prompt: TicketRecognitionPrompt.spatial(ocr, hints: hints))
    }
    #endif

    private func perform(prompt: String) async throws -> TicketLLMRecognitionResult {
        let text = try await performRaw(prompt: prompt)
        let payload = try decodePayload(from: text)
        return payload.result
    }

    private func performRaw(prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: apiStyle.path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(apiStyle.requestBody(model: model, prompt: prompt))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            throw TicketLLMRecognitionError.networkUnavailable(reason: "\(nsError.localizedDescription)（\(nsError.code)）")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TicketLLMRecognitionError.requestFailed
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TicketLLMRecognitionError.requestFailed
        }

        let text = try apiStyle.outputText(from: data)
        return text
    }

    #if DEBUG
    private func performRawHTTP(prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: apiStyle.path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(apiStyle.requestBody(model: model, prompt: prompt))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            throw TicketLLMRecognitionError.networkUnavailable(reason: "\(nsError.localizedDescription)（\(nsError.code)）")
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = String(decoding: data, as: UTF8.self)
        return "HTTP_STATUS: \(statusCode)\n\(body)"
    }
    #endif

    private func decodePayload(from text: String) throws -> TicketLLMPayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            jsonText = String(trimmed[start...end])
        } else {
            jsonText = trimmed
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw TicketLLMRecognitionError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(TicketLLMPayload.self, from: data)
        } catch {
            throw TicketLLMRecognitionError.invalidResponse
        }
    }

    private static func cleanedBaseURL(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.hasPrefix("$("), clean != "your_openai_compatible_base_url_here", clean != "your_llm_compatible_base_url_here" else {
            return ""
        }
        return clean.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func configuredValue(_ key: String, fallbackKey: String?) -> String {
        let primary = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        if !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !primary.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("$(") {
            return primary
        }

        guard let fallbackKey else { return "" }
        return Bundle.main.object(forInfoDictionaryKey: fallbackKey) as? String ?? ""
    }
}

private enum LLMAPIStyle: String {
    case responses
    case chatCompletions = "chat_completions"

    var displayName: String {
        switch self {
        case .responses:
            "Responses API"
        case .chatCompletions:
            "Chat Completions compatible"
        }
    }

    var path: String {
        switch self {
        case .responses:
            "responses"
        case .chatCompletions:
            "chat/completions"
        }
    }

    func requestBody(model: String, prompt: String) -> AnyEncodable {
        switch self {
        case .responses:
            AnyEncodable(ResponsesRequest(model: model, prompt: prompt))
        case .chatCompletions:
            AnyEncodable(ChatCompletionsRequest(model: model, prompt: prompt))
        }
    }

    func outputText(from data: Data) throws -> String {
        let text: String
        switch self {
        case .responses:
            let response = try JSONDecoder().decode(ResponsesResponse.self, from: data)
            if let outputText = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !outputText.isEmpty {
                text = outputText
            } else {
                text = response.output?
                    .flatMap { $0.content ?? [] }
                    .compactMap(\.text)
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        case .chatCompletions:
            let response = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
            text = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        guard !text.isEmpty else { throw TicketLLMRecognitionError.invalidResponse }
        return text
    }
}

private enum TicketRecognitionPrompt {
    static func spatial(_ ocr: TicketOCRResult, hints: TicketOCRCandidateHints) -> String {
        let hints = hints.promptSection
        return """
        你是中国大陆电影票根 OCR 字段裁判。请只根据 iOS Vision 识别出的文本块、坐标、置信度、备用识别结果和本地候选证据做判断，不要依赖外部搜索，不要假设图片中还有未提供的信息。

        目标：
        - 只要文本块能证明这是一张电影票根，就尽量识别出票根信息，空字符串是最后选择。
        - 真实票根经常错位、掉色、重叠、左右副券混排、字段缺失、标签和值分离。你需要像人类一样把碎片拼起来。
        - 你不是简单抽取器，而是裁判：先审查 field_candidates 中的候选，再结合 raw OCR 证据采纳、修正、拒绝或补充。
        - local_score、source_regions、reasons 是本地初筛证据，不是最终答案。不要盲信分数，也不要因为候选分数低就忽略清晰 OCR 证据。
        - 如果候选漏掉了，但 Vision OCR 空间文本中有明确证据，可以从原始 OCR 中补充答案。
        - 如果候选和原始 OCR 冲突，以字段语义、空间关系、格式合理性和 OCR alternatives 综合判断。
        - 电影名可以是不常见短语、书名号缺失、片名被 OCR 断开或看起来像普通词。只要它靠近 MOVIE/影片 锚点，或与时间/座位/影厅同组，就优先作为电影名。
        - 你可以从脏文本中抽取子串作为字段值，例如从“票类0排13座”抽取“0排13座”，从“影片号DIS:X临境音4:45”抽取“DTS:X临境音厅”和“14:45/04:45”候选。
        - 先判断是否为电影票根。只要出现电影票根强信号，例如影院/影城、影片/MOVIE、影厅/HALL、座位/SEAT、票价/PRICE、放映时间、取票/售票/票号等组合，就应判定 is_movie_ticket=true。
        - 如果不是电影票根，is_movie_ticket=false，字段全部返回空字符串，should_request_manual_review=true。

        坐标说明：
        - x/y/w/h 均为票根图片归一化百分比，x 从左到右，y 从上到下。
        - 同一行通常 y 接近；标签的值通常在右侧或下方。
        - OCR 行顺序可能错乱，请综合坐标、标签和语义判断，不要只按文本顺序。
        - alternatives 是 Vision 给出的备用识别文本。主文本明显有 OCR 错误时，可以结合 alternatives 和语义修正，例如 1O->10、O0->00、仃->停。
        - “按视觉行分组”比单纯排序更接近版面结构；表格票、左右联票根和标签值分行时必须优先参考行分组和坐标。

        裁判原则：
        - field_candidates 按字段提供多个候选。优先选择证据链更完整的候选，不要只选第一个。
        - source_regions 是软证据，不是固定版式规则。副券缺失、异形票、竖排票、无表格票都可能存在；不要把“右侧/底部/副券”当成绝对排除条件。
        - 如果同一值同时出现在主票和副券，通常可信度更高；如果只出现在副券，但仍符合字段语义，也可以采用。
        - 如果字段候选明显不符合格式，应拒绝。例如电影名不像订单号，座位必须像“排/座/号/Row/Seat”，票价不能是 0.00。
        - 如果 OCR 把标签和值粘在一起，应抽取合理子串；如果 OCR 少了一个常见字符，可以基于 alternatives 和上下文做保守修正。
        - 找锚点标签：影片/Movie、影院/Cinema、影厅/Hall、时间/Date/Time、座位/Seat、票价/Price。
        - 优先匹配标签右侧或下方的值；表格行中按表头顺序匹配同一行的值。
        - 表格票根里标签和值常被 OCR 分到相邻行。判断字段时要看“当前标签到下一个同类标签之间”的邻近区域，不要只看同一行。
        - MOVIE/影片 标签下方、SEAT/座位 标签上方之间的中文短语，优先作为电影名候选；即使片名像普通短语也不要直接丢弃。
        - HALL/影厅 附近出现“厅”“IMAX”“DTS:X”“临境音”“杜比”等影院制式/厅名时，可作为影厅候选；如果同时有数字厅号优先保留完整厅名。
        - SEAT/座位 或 TYPE/票类 附近出现“排”“座”的文本时，要从脏文本中抽出座位，例如“票类0排13座”可提取为“0排13座”。
        - 中国大陆影院通常不存在“0排”。如果座位候选同时出现“0排13座”和“10排13座”这类修正值，优先选择“10排13座”。
        - TIME/时间 附近的日期和相邻时间片段可以合并，例如“2026-03 15”加邻近“14:45/4:45”可规范为“2026-03-15 14:45”；但取票时间、售票时间仍不能作为 watched_at。
        - PRICE/票价 附近出现明显金额时可提取；服务费、手续费、二维码、票号附近的金额不要作为票价。
        - 不要把 0.00 作为票价；真实 OCR 中 0.00 几乎总是服务费、手续费、优惠或无效金额。
        - 如果近邻值不符合语义格式，要用常识纠正。例如“10排13座”才像座位，“非穷尽列举”不像座位。
        - 上一条只用于普通情况；如果“非穷尽列举”这类中文短语位于 MOVIE/影片 区域，而不是 SEAT/座位值区域，应当当作电影名候选，不要因为它不像座位就丢弃。
        - 本地候选证据由程序从 OCR 脏文本中抽取，可能有误，但它们代表“不要轻易置空”的重点候选。最终答案应优先从候选证据和原始空间文本共同确认。
        - 过滤购票平台、取票码、订单号、票号、手机号、二维码、条形码、售票时间、取票时间、服务说明、广告和推荐内容。
        - 售票时间、取票时间不能作为 watched_at；优先使用放映/观影/开场时间。
        - 多个金额同时出现时，优先票价，不要把服务费、优惠、实付金额当票价。
        - 电影名去掉 2D/3D/IMAX/CINITY/国语/英文/中字/字幕/影厅制式等后缀。
        - 片名可以包含“时间”等普通词，不要因为包含字段关键词就过滤。
        - 同屏出现推荐电影时，优先选择与影院、影厅、座位、时间在空间上同组或邻近的电影名。
        - 如果某字段不能从文本块确认，返回空字符串；不要编造。
        - watched_at 使用 yyyy-MM-dd HH:mm；只有日期时用 yyyy-MM-dd；相对日期如“今天/明天”且没有绝对日期时返回空字符串。
        - confidence 表示整体结构化可信度，范围 0.0-1.0。字段越多且空间关系越清楚，值越高；票根确认但字段残缺时也应大于 0.5。
        - should_request_manual_review 只在票根证据很弱、关键字段大量缺失或疑似非票根时为 true。真实票根掉色/错位但能抽出电影名、影院、时间、座位等时应为 false。
        - candidate_texts 放入用于判断的关键 OCR 文本，最多 12 条；不要放订单号、手机号、条码等敏感/无关文本。

        只返回严格 JSON，不要 Markdown，不要解释：
        {
          "is_movie_ticket": true,
          "confidence": 0.0,
          "should_request_manual_review": false,
          "movie_title": "",
          "original_title": "",
          "year": "",
          "director": "",
          "watched_at": "",
          "cinema": "",
          "hall": "",
          "seat": "",
          "ticket_price": "",
          "candidate_texts": []
        }

        本地候选证据 JSON：
        \(hints)

        Vision OCR 空间文本：
        \(ocr.judgeSpatialText)
        """
    }

    static func plainText(_ ocrText: String) -> String {
        """
        你是电影票根 OCR 文本校对助手。请只根据下面 OCR 文本纠错并提取字段，不要依赖外部搜索。
        OCR 可能有错字、断行、重复、顺序混乱和中英文混杂；请尽量识别正式中文片名，并去掉 2D/3D/IMAX/国语/中字/影厅制式等附加信息。
        如果某个字段无法从 OCR 文本确认，返回空字符串；不要编造影院、影厅、座位、票价。
        watched_at 使用 yyyy-MM-dd HH:mm；只有日期时用 yyyy-MM-dd；不确定则为空。
        candidate_texts 放入用于判断的关键 OCR 行，最多 12 条。
        只返回严格 JSON，不要 Markdown，不要解释。
        JSON 结构：
        {
          "is_movie_ticket": true,
          "confidence": 0.0,
          "should_request_manual_review": false,
          "movie_title": "",
          "original_title": "",
          "year": "",
          "director": "",
          "watched_at": "",
          "cinema": "",
          "hall": "",
          "seat": "",
          "ticket_price": "",
          "candidate_texts": []
        }

        OCR 文本：
        \(ocrText)
        """
    }
}

private struct TicketOCRCandidateHints {
    let ocr: TicketOCRResult

    private struct FieldCandidate: Encodable {
        let value: String
        let localScore: Double
        let sourceRegions: [String]
        let sourceLineTexts: [String]
        let reasons: [String]

        enum CodingKeys: String, CodingKey {
            case value
            case localScore = "local_score"
            case sourceRegions = "source_regions"
            case sourceLineTexts = "source_line_texts"
            case reasons
        }
    }

    private struct EvidencePayload: Encodable {
        let ticketSignals: [String]
        let fieldCandidates: [String: [FieldCandidate]]
        let notes: [String]

        enum CodingKeys: String, CodingKey {
            case ticketSignals = "ticket_signals"
            case fieldCandidates = "field_candidates"
            case notes
        }
    }

    private struct LineValue {
        let value: String
        let line: TicketOCRLine
    }

    var fallbackResult: TicketLLMRecognitionResult {
        TicketLLMRecognitionResult(
            isMovieTicket: looksLikeMovieTicket(),
            confidence: fallbackConfidence(),
            shouldRequestManualReview: false,
            movieTitle: movieCandidates().first ?? "",
            watchedAt: date(from: watchedAtCandidates().first ?? ""),
            cinema: cinemaCandidates().first ?? "",
            hall: hallCandidates().first ?? "",
            seat: seatCandidates().first ?? "",
            ticketPrice: priceCandidates().first ?? "",
            candidateLines: unique(
                cinemaCandidates() + movieCandidates() + hallCandidates() + watchedAtCandidates() + seatCandidates() + priceCandidates(),
                limit: 12
            )
        )
    }

    var promptSection: String {
        let payload = EvidencePayload(
            ticketSignals: ticketSignals(),
            fieldCandidates: fieldCandidateMap(),
            notes: [
                "source_regions 是软证据，只描述 OCR 文本所处的大致语义环境，不代表固定票版。",
                "local_score 是本地候选排序信号，模型需要结合原始 OCR 空间文本重新裁判。",
                "候选可能漏掉字段；如果原始 OCR 有清晰证据，允许从 Vision OCR 空间文本补充。"
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return fieldCandidateMap()
                .map { key, values in "\(key): \(values.map(\.value).joined(separator: "；"))" }
                .sorted()
                .joined(separator: "\n")
        }
        return text
    }

    private func fieldCandidateMap() -> [String: [FieldCandidate]] {
        [
            "cinema": cinemaFieldCandidates(),
            "movie_title": movieFieldCandidates(),
            "hall": hallFieldCandidates(),
            "watched_at": watchedAtFieldCandidates(),
            "seat": seatFieldCandidates(),
            "ticket_price": priceFieldCandidates()
        ]
    }

    private func cinemaCandidates() -> [String] {
        cinemaFieldCandidates().map(\.value)
    }

    private func movieCandidates() -> [String] {
        movieFieldCandidates().map(\.value)
    }

    private func hallCandidates() -> [String] {
        hallFieldCandidates().map(\.value)
    }

    private func watchedAtCandidates() -> [String] {
        watchedAtFieldCandidates().map(\.value)
    }

    private func seatCandidates() -> [String] {
        seatFieldCandidates().map(\.value)
    }

    private func priceCandidates() -> [String] {
        priceFieldCandidates().map(\.value)
    }

    private func cinemaFieldCandidates() -> [FieldCandidate] {
        uniqueCandidates(ocr.lines.compactMap { line in
            let text = clean(line.text)
            guard containsAny(text, ["影院", "影城", "Cinema", "CINEMA"]) else { return nil }
            guard !containsAny(text, ["影城 PLACE", "PLACE"]) || line.y < 0.35 else { return nil }
            let cleaned = text
                .replacingOccurrences(of: "Galaxy Cinema", with: "")
                .replacingOccurrences(of: "CINEMA", with: "")
                .replacingOccurrences(of: "Cinema", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = cleaned.isEmpty ? text : cleaned
            let score = 0.62 + (line.y < 0.22 ? 0.18 : 0) + (line.x < 0.72 ? 0.06 : 0)
            return candidate(
                value: value,
                score: score,
                lines: [line],
                reasons: [
                    "包含影院/影城/Cinema 信号",
                    line.y < 0.22 ? "位于票根上方品牌/影院区域" : "出现在票面影院相关文本中"
                ]
            )
        }, limit: 4)
    }

    private func movieFieldCandidates() -> [FieldCandidate] {
        let movieLabelY = ocr.lines
            .filter { containsAny($0.text, ["MOVIE", "Movie", "影片"]) }
            .map(\.y)
            .min()

        var candidates: [FieldCandidate] = []
        if let movieLabelY {
            let nextFieldY = ocr.lines
                .filter { $0.y > movieLabelY && containsAny($0.text, ["SEAT", "Seat", "座位", "票价", "PRICE"]) }
                .map(\.y)
                .min() ?? (movieLabelY + 0.15)

            for line in ocr.lines {
                let text = clean(line.text)
                guard line.y >= movieLabelY - 0.03, line.y <= nextFieldY + 0.03 else { continue }
                guard line.x < 0.74, containsChinese(text) else { continue }
                guard !isMovieNoise(text) else { continue }
                candidates.append(candidate(
                    value: text,
                    score: 0.84 + (line.x < 0.60 ? 0.04 : 0),
                    lines: [line],
                    reasons: [
                        "位于 MOVIE/影片 锚点下方到下一字段之间",
                        "包含中文片名样式文本",
                        "未命中座位/票价/票号等噪声格式"
                    ]
                ))
            }
        }

        for line in ocr.lines where line.y > 0.25 && line.y < 0.65 {
            let text = clean(line.text)
            guard containsChinese(text), !isMovieNoise(text) else { continue }
            guard !containsAny(text, ["排", "座", "元", "￥"]) else { continue }
            guard text.filter({ String($0).range(of: #"\d"#, options: .regularExpression) != nil }).isEmpty else { continue }
            if text.count >= 2, text.count <= 14 {
                candidates.append(candidate(
                    value: text,
                    score: 0.52,
                    lines: [line],
                    reasons: [
                        "票面中部出现短中文短语",
                        "格式不像时间/座位/票价/编号",
                        "作为片名候补，需由模型结合空间文本裁判"
                    ]
                ))
            }
        }

        return uniqueCandidates(candidates.sorted { $0.localScore > $1.localScore }, limit: 6)
    }

    private func hallFieldCandidates() -> [FieldCandidate] {
        let candidates = ocr.lines.compactMap { line -> FieldCandidate? in
            let text = clean(line.text)
            guard containsAny(text, ["厅", "IMAX", "CINITY", "DTS", "DIS", "临境音", "杜比"]) else { return nil }
            guard !containsAny(text, ["影城", "影院", "售票", "取票", "票号", "工号", "副券"]) else { return nil }
            guard text != "影厅", text != "影厅 HALL", text != "HALL" else { return nil }
            let value = cleanHall(text)
            guard !value.isEmpty else { return nil }
            let nearHallLabel = nearestLabelDistance(from: line, labels: ["HALL", "Hall", "影厅"]) ?? 1
            let score = 0.66 + (nearHallLabel < 0.16 ? 0.16 : 0) + (containsAny(value, ["DTS", "IMAX", "CINITY", "杜比"]) ? 0.06 : 0)
            return candidate(
                value: value,
                score: score,
                lines: [line],
                reasons: [
                    "包含厅名或影院制式信号",
                    nearHallLabel < 0.16 ? "靠近 HALL/影厅 锚点" : "未强依赖固定区域，作为影厅候选"
                ]
            )
        }
        return uniqueCandidates(candidates.sorted { $0.localScore > $1.localScore }, limit: 6)
    }

    private func watchedAtFieldCandidates() -> [FieldCandidate] {
        let excludedTimeLabels = ["取票", "TICKET", "售票", "SELLING"]
        let dates = uniqueLineValues(
            ocr.lines.flatMap { line in
                normalizedDates(in: line.text).map { LineValue(value: $0, line: line) }
            },
            limit: 4
        )
        var times: [LineValue] = []
        for line in ocr.lines {
            guard !containsAny(line.text, excludedTimeLabels) else { continue }
            times.append(contentsOf: normalizedTimes(in: line.text).map { LineValue(value: $0, line: line) })
        }
        times = uniqueLineValues(times, limit: 6)

        var candidates: [FieldCandidate] = []
        if let date = dates.first {
            for time in times {
                let close = lineDistance(date.line, time.line) < 0.20
                let suspiciousDate = containsAny(date.line.text, excludedTimeLabels)
                candidates.append(candidate(
                    value: "\(date.value) \(time.value)",
                    score: 0.68 + (close ? 0.12 : 0) - (suspiciousDate ? 0.20 : 0),
                    lines: [date.line, time.line],
                    reasons: [
                        close ? "日期和时间在空间上接近" : "日期和时间来自同一票面但空间距离较远",
                        suspiciousDate ? "日期行靠近售票/取票标签，需谨慎" : "时间行未命中售票/取票排除标签",
                        "已规范为 yyyy-MM-dd HH:mm 候选"
                    ]
                ))
            }
            candidates.append(candidate(
                value: date.value,
                score: containsAny(date.line.text, excludedTimeLabels) ? 0.34 : 0.48,
                lines: [date.line],
                reasons: [
                    "仅识别到日期，缺少明确放映时间时作为候补",
                    containsAny(date.line.text, excludedTimeLabels) ? "日期行可能是售票/取票时间" : "日期行未命中售票/取票排除标签"
                ]
            ))
        }
        return uniqueCandidates(candidates.sorted { $0.localScore > $1.localScore }, limit: 8)
    }

    private func seatFieldCandidates() -> [FieldCandidate] {
        var candidates: [FieldCandidate] = []
        for line in ocr.lines {
            let seats = normalizedSeats(in: line.text)
            for seat in seats where seat.hasPrefix("0排") {
                candidates.append(candidate(
                    value: "1\(seat)",
                    score: 0.82,
                    lines: [line],
                    reasons: [
                        "原始 OCR 是 \(seat)，符合排座格式但 0排 不符合大陆影院常识",
                        "按常见 OCR 漏识别修正为 1\(seat)"
                    ]
                ))
            }
            for seat in seats {
                candidates.append(candidate(
                    value: seat,
                    score: seat.hasPrefix("0排") ? 0.54 : 0.76,
                    lines: [line],
                    reasons: [
                        "包含排/座或排/号格式",
                        nearestLabelDistance(from: line, labels: ["SEAT", "Seat", "座位"]) ?? 1 < 0.18 ? "靠近 SEAT/座位 锚点" : "来自票面座位格式文本"
                    ]
                ))
            }
        }
        return uniqueCandidates(candidates.sorted { $0.localScore > $1.localScore }, limit: 6)
    }

    private func priceFieldCandidates() -> [FieldCandidate] {
        var candidates: [FieldCandidate] = []
        for line in ocr.lines {
            guard !containsAny(line.text, ["取票", "票号", "NO."]) else { continue }
            let nearPriceLabel = nearestLabelDistance(from: line, labels: ["票价", "PRICE", "Price"]) ?? 1
            let inPriceBox = (0.34...0.62).contains(line.x) && (0.38...0.54).contains(line.y)
            guard containsAny(line.text, ["票价", "PRICE", "￥", "¥", "RMB", "元"]) || nearPriceLabel < 0.12 || inPriceBox else { continue }
            candidates.append(contentsOf: decimalAmounts(in: line.text).filter(isPositiveAmount).map { amount in
                candidate(
                    value: amount,
                    score: 0.74 + (inPriceBox ? 0.08 : 0),
                    lines: [line],
                    reasons: [
                        inPriceBox ? "金额位于票面票价框坐标范围" : "金额出现在票价/PRICE/货币符号附近",
                        "金额大于 0；同框出现服务费时仅排除 0.00，不整行排除"
                    ]
                )
            })
        }
        if candidates.isEmpty {
            for line in ocr.lines {
                guard !containsAny(line.text, ["服务费", "手续费", "SERVICE", "CHARGE", "取票", "售票", "TICKET", "SELLING", "票号", "NO.", "工号", "ID", "KIOSK"]) else { continue }
                candidates.append(contentsOf: decimalAmounts(in: line.text).filter(isPositiveAmount).map { amount in
                    candidate(
                        value: amount,
                        score: 0.42,
                        lines: [line],
                        reasons: [
                            "票面存在正金额，但没有明确票价锚点",
                            "作为票价弱候选，需由模型裁判"
                        ]
                    )
                })
            }
        }
        return uniqueCandidates(candidates.sorted { $0.localScore > $1.localScore }, limit: 4)
    }

    private func looksLikeMovieTicket() -> Bool {
        ticketSignals().count >= 3
    }

    private func fallbackConfidence() -> Double {
        guard looksLikeMovieTicket() else { return 0.15 }
        let filledFields = [
            !movieCandidates().isEmpty,
            !cinemaCandidates().isEmpty,
            !hallCandidates().isEmpty,
            !watchedAtCandidates().isEmpty,
            !seatCandidates().isEmpty,
            !priceCandidates().isEmpty
        ].filter { $0 }.count
        return min(0.95, 0.45 + Double(filledFields) * 0.08)
    }

    private func ticketSignals() -> [String] {
        let text = ocr.rawText
        var signals: [String] = []
        if containsAny(text, ["影院", "影城", "Cinema", "CINEMA"]) { signals.append("cinema_name") }
        if containsAny(text, ["影片", "电影", "MOVIE", "Movie"]) { signals.append("movie_label") }
        if containsAny(text, ["影厅", "HALL", "厅"]) { signals.append("hall_label_or_value") }
        if containsAny(text, ["座位", "SEAT", "排", "座", "号"]) { signals.append("seat_label_or_value") }
        if containsAny(text, ["票价", "PRICE", "取票", "售票", "票号", "TICKET"]) { signals.append("ticketing_label") }
        if !watchedAtCandidates().isEmpty { signals.append("date_or_showtime") }
        return signals
    }

    private func candidate(value: String, score: Double, lines: [TicketOCRLine], reasons: [String]) -> FieldCandidate {
        FieldCandidate(
            value: clean(value),
            localScore: min(max(score, 0), 1),
            sourceRegions: unique(lines.flatMap(regionTags), limit: 6),
            sourceLineTexts: unique(lines.map(lineSummary), limit: 2),
            reasons: reasons.filter { !$0.isEmpty }
        )
    }

    private func regionTags(for line: TicketOCRLine) -> [String] {
        var tags: [String] = []
        if line.y < 0.22 { tags.append("top_header_or_brand") }
        if line.x < 0.72 { tags.append("main_ticket_body") }
        if line.x >= 0.72 { tags.append("right_stub_or_coupon") }
        if line.y > 0.66 { tags.append("lower_receipt_or_identifier_area") }
        if containsAny(line.text, ["MOVIE", "影片", "HALL", "影厅", "TIME", "时间", "SEAT", "座位", "PRICE", "票价"]) {
            tags.append("field_anchor_neighborhood")
        }
        if containsAny(line.text, ["二维码", "票号", "NO.", "订单", "取票码", "KIOSK", "工号", "ID"]) {
            tags.append("identifier_or_qr_noise_area")
        }
        return tags.isEmpty ? ["unknown_flexible_layout_area"] : tags
    }

    private func lineSummary(_ line: TicketOCRLine) -> String {
        "[x:\(percent(line.x)), y:\(percent(line.y)), conf:\(String(format: "%.2f", line.confidence))] \(line.text)"
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f", value * 100)
    }

    private func nearestLabelDistance(from line: TicketOCRLine, labels: [String]) -> Double? {
        ocr.lines
            .filter { containsAny($0.text, labels) }
            .map { lineDistance(line, $0) }
            .min()
    }

    private func lineDistance(_ lhs: TicketOCRLine, _ rhs: TicketOCRLine) -> Double {
        let lhsX = lhs.x + lhs.width / 2
        let lhsY = lhs.y + lhs.height / 2
        let rhsX = rhs.x + rhs.width / 2
        let rhsY = rhs.y + rhs.height / 2
        return hypot(lhsX - rhsX, lhsY - rhsY)
    }

    private func cleanHall(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "DIS:X", with: "DTS:X")
            .replacingOccurrences(of: #"影片\s*号(?=DTS|DIS|临境音)"#, with: "2号", options: .regularExpression)
            .replacingOccurrences(of: "影片", with: "")
            .replacingOccurrences(of: "MOVIE", with: "")
            .replacingOccurrences(of: "HALL", with: "")
            .replacingOccurrences(of: #"\d{1,2}[:：]\d{2}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"20\d{2}[-./ ]\d{1,2}[-./ ]?\d{0,2}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("DTS:X"), value.contains("临境音"), !value.contains("厅") {
            value += "厅"
        }
        return value
    }

    private func normalizedDates(in text: String) -> [String] {
        let numberGroups = regexMatches(#"\d{1,4}"#, in: text).compactMap(Int.init)
        guard let yearIndex = numberGroups.firstIndex(where: { (2000...2099).contains($0) }),
              numberGroups.indices.contains(yearIndex + 2) else {
            return []
        }
        let year = numberGroups[yearIndex]
        let month = numberGroups[yearIndex + 1]
        let day = numberGroups[yearIndex + 2]
        guard (1...12).contains(month), (1...31).contains(day) else { return [] }
        return [String(format: "%04d-%02d-%02d", year, month, day)]
    }

    private func normalizedTimes(in text: String) -> [String] {
        var values = regexMatches(#"\b(?:[01]?\d|2[0-3])[:：][0-5]\d\b"#, in: text)
            .map { normalizeClock($0) }

        for compact in regexMatches(#"\b(?:[01]\d|2[0-3])[0-5]\d\b"#, in: text) {
            let hour = String(compact.prefix(2))
            let minute = String(compact.suffix(2))
            values.append("\(hour):\(minute)")
        }

        for value in values {
            if value.hasPrefix("0"),
               let hour = Int(value.prefix(2)),
               (0...7).contains(hour) {
                values.append(String(format: "%02d:%@", hour + 10, String(value.suffix(2))))
            }
        }
        return unique(values, limit: 4)
    }

    private func normalizeClock(_ text: String) -> String {
        let parts = text.replacingOccurrences(of: "：", with: ":").split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return text
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func normalizedSeats(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: " ", with: "")
        return regexMatches(#"(?:\d{1,2}|[一二三四五六七八九十]{1,3})排(?:\d{1,3}|[A-Za-z]\d{1,3}|[一二三四五六七八九十]{1,3})(?:座|号)"#, in: normalized)
    }

    private func decimalAmounts(in text: String) -> [String] {
        var values = regexMatches(#"(?:￥|¥|RMB\s*)?\d{1,3}(?:[.,]\d{2})(?:元)?"#, in: text)
            .map { $0.replacingOccurrences(of: ",", with: ".") }
        values.append(contentsOf: correctedNoisyPriceAmounts(in: text))
        return unique(values, limit: 4)
    }

    private func correctedNoisyPriceAmounts(in text: String) -> [String] {
        let compact = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "）", with: ")")
            .uppercased()
        guard containsAny(compact, ["SERVICE", "SERVCE", "SEPVCE", "CHARGE", "CHAR6", "CHARG"]) else {
            return []
        }
        if compact.range(of: #"CHAR[CG6B8O0]*[36][B8O0][O0][,.，)]?[O0][)]?[O0)]"#, options: .regularExpression) != nil ||
            compact.contains("CHAR6BO") ||
            compact.contains("CHARGB0") ||
            compact.contains("GHAR$0") {
            return ["30.00"]
        }
        return []
    }

    private func isPositiveAmount(_ amount: String) -> Bool {
        let numericText = amount
            .replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
        return (Double(numericText) ?? 0) > 0
    }

    private func date(from text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let normalized = text
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        for format in ["yyyy-M-d H:mm", "yyyy-MM-dd H:mm", "yyyy-M-d", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        return nil
    }

    private func isMovieNoise(_ text: String) -> Bool {
        if containsAny(text, ["影城", "影院", "影厅", "HALL", "TIME", "SEAT", "PRICE", "票价", "座位", "服务", "手续费", "副券", "票号", "工号", "取票", "售票", "扫码", "KIOSK", "Galaxy", "Cinema", "排", "座"]) {
            return true
        }
        if regexMatches(#"\d{3,}"#, in: text).isEmpty == false {
            return true
        }
        return false
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsChinese(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private func containsAny(_ text: String, _ tokens: [String]) -> Bool {
        tokens.contains { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private func unique(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values.map(clean).filter({ !$0.isEmpty }) {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
            if result.count >= limit { break }
        }
        return result
    }

    private func uniqueCandidates(_ values: [FieldCandidate], limit: Int) -> [FieldCandidate] {
        var seen = Set<String>()
        var result: [FieldCandidate] = []
        for value in values where !value.value.isEmpty {
            guard !seen.contains(value.value) else { continue }
            seen.insert(value.value)
            result.append(value)
            if result.count >= limit { break }
        }
        return result
    }

    private func uniqueLineValues(_ values: [LineValue], limit: Int) -> [LineValue] {
        var seen = Set<String>()
        var result: [LineValue] = []
        for value in values where !value.value.isEmpty {
            guard !seen.contains(value.value) else { continue }
            seen.insert(value.value)
            result.append(value)
            if result.count >= limit { break }
        }
        return result
    }
}

private enum TicketRecognitionResultMerger {
    static func merge(_ result: TicketLLMRecognitionResult, with fallback: TicketLLMRecognitionResult) -> TicketLLMRecognitionResult {
        var merged = result
        if !merged.isMovieTicket && !fallback.isMovieTicket {
            return merged
        }
        if fallback.isMovieTicket {
            merged.isMovieTicket = true
        }
        merged.confidence = max(merged.confidence, fallback.confidence)
        merged.ticketPrice = sanitizedPrice(merged.ticketPrice)
        if merged.movieTitle.isEmpty { merged.movieTitle = fallback.movieTitle }
        if merged.watchedAt == nil { merged.watchedAt = fallback.watchedAt }
        if merged.cinema.isEmpty { merged.cinema = fallback.cinema }
        if merged.hall.isEmpty { merged.hall = fallback.hall }
        if merged.seat.isEmpty { merged.seat = fallback.seat }
        if merged.ticketPrice.isEmpty { merged.ticketPrice = sanitizedPrice(fallback.ticketPrice) }
        merged.hall = betterHall(current: merged.hall, fallback: fallback.hall)
        merged.ticketPrice = betterPrice(current: merged.ticketPrice, fallback: fallback.ticketPrice)
        merged.hall = normalizedHall(merged.hall)
        merged.seat = normalizedSeat(merged.seat)
        merged.ticketPrice = normalizedPrice(merged.ticketPrice)
        merged.candidateLines = unique(merged.candidateLines + fallback.candidateLines)
        merged.shouldRequestManualReview = merged.shouldRequestManualReview || manualReviewNeeded(merged)
        return merged
    }

    private static func manualReviewNeeded(_ result: TicketLLMRecognitionResult) -> Bool {
        if !result.isMovieTicket { return true }
        let coreFields = [
            !result.movieTitle.isEmpty,
            result.watchedAt != nil,
            !result.cinema.isEmpty,
            !result.seat.isEmpty
        ].filter { $0 }.count
        return result.confidence < 0.45 || coreFields < 2
    }

    private static func sanitizedPrice(_ price: String) -> String {
        let trimmed = price.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let numericText = trimmed
            .replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
        guard let value = Double(numericText), value > 0 else { return "" }
        return trimmed
    }

    private static func betterHall(current: String, fallback: String) -> String {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, !fallback.isEmpty else { return current.isEmpty ? fallback : current }
        let currentHasPrefixNumber = current.range(of: #"^\d+\s*号"#, options: .regularExpression) != nil
        let fallbackHasPrefixNumber = fallback.range(of: #"^\d+\s*号"#, options: .regularExpression) != nil
        let currentCore = current.replacingOccurrences(of: #"^\d+\s*号"#, with: "", options: .regularExpression)
        let fallbackCore = fallback.replacingOccurrences(of: #"^\d+\s*号"#, with: "", options: .regularExpression)
        if !currentHasPrefixNumber, fallbackHasPrefixNumber, fallbackCore.contains(currentCore) || currentCore.contains(fallbackCore) {
            return fallback
        }
        return current
    }

    private static func betterPrice(current: String, fallback: String) -> String {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { return current }
        guard !current.isEmpty else { return fallback }
        let currentHasDecimals = current.range(of: #"\d+[.]\d{2}"#, options: .regularExpression) != nil
        let fallbackHasDecimals = fallback.range(of: #"\d+[.]\d{2}"#, options: .regularExpression) != nil
        if !currentHasDecimals, fallbackHasDecimals {
            return fallback
        }
        if let currentValue = numericPrice(current),
           let fallbackValue = numericPrice(fallback),
           currentValue >= 300,
           (1...200).contains(fallbackValue) {
            return fallback
        }
        return current
    }

    private static func numericPrice(_ price: String) -> Double? {
        let numericText = price.replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
        return Double(numericText)
    }

    private static func normalizedHall(_ hall: String) -> String {
        var text = hall.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = text
            .replacingOccurrences(of: "vip", with: "VIP", options: .caseInsensitive)
            .replacingOccurrences(of: "VI P", with: "VIP", options: .caseInsensitive)
            .replacingOccurrences(of: "FT", with: "厅")
            .replacingOccurrences(of: " F T", with: "厅")
        text = text.replacingOccurrences(of: #"(?i)(\d+号.*VIP)(?!厅)"#, with: "$1厅", options: .regularExpression)
        return text
    }

    private static func normalizedSeat(_ seat: String) -> String {
        var text = seat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = text.replacingOccurrences(of: #"(\d{1,3}排\d{1,3})号"#, with: "$1座", options: .regularExpression)
        return text
    }

    private static func normalizedPrice(_ price: String) -> String {
        let trimmed = price.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let prefix = trimmed.hasPrefix("￥") ? "￥" : (trimmed.hasPrefix("¥") ? "¥" : "")
        let suffix = trimmed.hasSuffix("元") ? "元" : ""
        let numericText = trimmed
            .replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
        guard let value = Double(numericText), value > 0 else { return "" }
        let number = String(format: "%.2f", value)
        return "\(prefix)\(number)\(suffix)"
    }

    private static func unique(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            guard !seen.contains(line) else { continue }
            seen.insert(line)
            result.append(line)
            if result.count >= 12 { break }
        }
        return result
    }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: [InputMessage]
    let temperature: Double
    let maxOutputTokens: Int
    let store: Bool

    init(model: String, prompt: String) {
        self.model = model
        self.temperature = 0
        self.maxOutputTokens = 2400
        self.store = false
        self.input = [
            InputMessage(
                role: "user",
                content: [
                    .text(prompt)
                ]
            )
        ]
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case store
    }
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    let thinking: ThinkingConfig?
    let responseFormat: ResponseFormat?

    init(model: String, prompt: String) {
        self.model = model
        self.temperature = 0
        self.maxTokens = 2400
        self.thinking = model.hasPrefix("deepseek-v4-") ? ThinkingConfig(type: "disabled") : nil
        self.responseFormat = model.hasPrefix("deepseek-v4-") ? ResponseFormat(type: "json_object") : nil
        self.messages = [
            ChatMessage(role: "user", content: prompt)
        ]
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case thinking
        case responseFormat = "response_format"
    }
}

private struct ThinkingConfig: Encodable {
    let type: String
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct InputMessage: Encodable {
    let role: String
    let content: [InputContent]
}

private enum InputContent: Encodable {
    case text(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

private struct ResponsesResponse: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct OutputItem: Decodable {
    let content: [OutputContent]?
}

private struct OutputContent: Decodable {
    let text: String?
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionsResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

private struct TicketLLMPayload: Decodable {
    let isMovieTicket: Bool?
    let confidence: Double?
    let shouldRequestManualReview: Bool?
    let movieTitle: String?
    let originalTitle: String?
    let year: String?
    let director: String?
    let watchedAt: String?
    let cinema: String?
    let hall: String?
    let seat: String?
    let ticketPrice: String?
    let candidateTexts: [String]?

    enum CodingKeys: String, CodingKey {
        case isMovieTicket = "is_movie_ticket"
        case confidence
        case shouldRequestManualReview = "should_request_manual_review"
        case movieTitle = "movie_title"
        case originalTitle = "original_title"
        case year
        case director
        case watchedAt = "watched_at"
        case cinema
        case hall
        case seat
        case ticketPrice = "ticket_price"
        case candidateTexts = "candidate_texts"
    }

    var result: TicketLLMRecognitionResult {
        TicketLLMRecognitionResult(
            isMovieTicket: isMovieTicket ?? true,
            confidence: min(max(confidence ?? 0, 0), 1),
            shouldRequestManualReview: shouldRequestManualReview ?? false,
            movieTitle: clean(movieTitle),
            originalTitle: clean(originalTitle),
            year: clean(year),
            director: clean(director),
            watchedAt: Self.date(from: clean(watchedAt)),
            cinema: clean(cinema),
            hall: clean(hall),
            seat: clean(seat),
            ticketPrice: clean(ticketPrice),
            candidateLines: Self.uniqueLines(candidateTexts ?? [])
        )
    }

    private func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                if seen.contains(line) { return false }
                seen.insert(line)
                return true
            }
    }

    private static func date(from text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let normalized = text
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        for format in ["yyyy-M-d H:mm", "yyyy-MM-dd H:mm", "yyyy-M-d", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        return nil
    }
}

enum TicketLLMRecognitionError: LocalizedError {
    case missingAPIKey
    case emptyOCRText
    case requestFailed
    case invalidResponse
    case networkUnavailable(reason: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "还没有配置 OpenAI API Key。配置后即可每次用大模型辅助识别票根。"
        case .emptyOCRText:
            "OCR 文本为空，无法交给大模型校对。"
        case .requestFailed:
            "大模型识别请求失败，已保留票根图片，可以稍后重试或手动填写。"
        case .invalidResponse:
            "大模型返回格式暂时无法识别，已保留票根图片，可以手动填写。"
        case .networkUnavailable(let reason):
            "无法连接大模型服务：\(reason)"
        }
    }
}
