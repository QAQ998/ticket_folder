import Foundation

struct TMDBMovieSearchResult: Identifiable, Decodable, Hashable {
    let id: Int
    let title: String
    let originalTitle: String?
    let releaseDate: String?
    let posterPath: String?
    let overview: String?

    var year: String {
        String((releaseDate ?? "").prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case overview
    }
}

struct TMDBMovieDetails: Decodable {
    let id: Int
    let title: String
    let originalTitle: String?
    let releaseDate: String?
    let posterPath: String?

    var year: String {
        String((releaseDate ?? "").prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
    }
}

struct TMDBMovieMetadata {
    let details: TMDBMovieDetails
    let director: String
    let posterLocalPath: String?
}

struct TMDBCredits: Decodable {
    let crew: [CrewMember]

    struct CrewMember: Decodable {
        let name: String
        let job: String
    }

    var director: String {
        crew
            .filter { $0.job == "Director" }
            .map(\.name)
            .joined(separator: ", ")
    }
}

struct TMDBClient {
    private let baseURL: URL
    private let imageBaseURL: URL
    private let credential: String
    private let usesProxy: Bool
    private let session: URLSession

    init(
        apiKey: String = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? "",
        apiBaseURL: String = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_BASE_URL") as? String ?? "",
        imageBaseURL: String = Bundle.main.object(forInfoDictionaryKey: "TMDB_IMAGE_BASE_URL") as? String ?? ""
    ) {
        self.credential = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIBaseURL = Self.cleanedConfiguredURL(apiBaseURL)
        let cleanImageBaseURL = Self.cleanedConfiguredURL(imageBaseURL)
        self.baseURL = URL(string: cleanAPIBaseURL) ?? URL(string: "https://api.themoviedb.org/3")!
        self.imageBaseURL = URL(string: cleanImageBaseURL) ?? URL(string: "https://image.tmdb.org/t/p/w500")!
        self.usesProxy = !cleanAPIBaseURL.isEmpty
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    var isConfigured: Bool {
        usesProxy || (!credential.isEmpty && credential != "$(TMDB_API_KEY)")
    }

    func searchMovies(query: String) async throws -> [TMDBMovieSearchResult] {
        guard isConfigured else { throw TMDBError.missingAPIKey }
        let queries = searchQueries(for: query)
        guard !queries.isEmpty else { return [] }

        for candidate in queries {
            let results = try await searchMoviesOnce(query: candidate)
            if !results.isEmpty {
                return results
            }
        }

        return []
    }

    private func searchMoviesOnce(query: String) async throws -> [TMDBMovieSearchResult] {
        var components = URLComponents(url: baseURL.appending(path: "search/movie"), resolvingAgainstBaseURL: false)!
        components.queryItems = authorizedQueryItems([
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: "zh-CN"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "region", value: "CN")
        ])

        let response: SearchResponse = try await request(components.url!)
        return response.results.filter { !$0.title.isEmpty }
    }

    private func searchQueries(for query: String) -> [String] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizedMovieQuery(raw)
        var seen = Set<String>()

        return [raw, normalized]
            .filter { !$0.isEmpty }
            .filter { candidate in
                if seen.contains(candidate) { return false }
                seen.insert(candidate)
                return true
            }
    }

    private func normalizedMovieQuery(_ query: String) -> String {
        var text = query

        let patterns = [
            #"[（(][^）)]*(2D|3D|4D|IMAX|CINITY|中国巨幕|杜比|国语|原版|数字|中文|字幕)[^）)]*[）)]"#,
            #"中文\s*[234]D"#,
            #"数字\s*[234]D"#,
            #"IMAX|CINITY|Cinity|中国巨幕|杜比全景声|杜比|全景声|国语|原版|中字|中文字幕|中文|英语|日语|韩语"#,
            #"[234]D"#
        ]

        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        text = text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let separators = CharacterSet(charactersIn: "｜|/／,，;；")
        if let first = text.components(separatedBy: separators).first {
            text = first.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    func metadata(for id: Int) async throws -> TMDBMovieMetadata {
        guard isConfigured else { throw TMDBError.missingAPIKey }

        let detailsURL: URL = {
            var components = URLComponents(url: baseURL.appending(path: "movie/\(id)"), resolvingAgainstBaseURL: false)!
            components.queryItems = authorizedQueryItems([
                URLQueryItem(name: "language", value: "zh-CN")
            ])
            return components.url!
        }()

        let creditsURL: URL = {
            var components = URLComponents(url: baseURL.appending(path: "movie/\(id)/credits"), resolvingAgainstBaseURL: false)!
            components.queryItems = authorizedQueryItems([
                URLQueryItem(name: "language", value: "zh-CN")
            ])
            return components.url!
        }()

        async let fetchedDetails: TMDBMovieDetails = request(detailsURL)
        async let fetchedCredits: TMDBCredits = request(creditsURL)
        let (details, credits) = try await (fetchedDetails, fetchedCredits)
        let posterPath = try await cachePoster(for: details)
        return TMDBMovieMetadata(details: details, director: credits.director, posterLocalPath: posterPath)
    }

    func posterURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return imageBaseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func cachePoster(for details: TMDBMovieDetails) async throws -> String? {
        try await PosterCacheStore.cachePoster(from: posterURL(for: details.posterPath))
    }

    private func authorizedQueryItems(_ queryItems: [URLQueryItem]) -> [URLQueryItem] {
        guard !usesProxy, !usesBearerToken else {
            return queryItems
        }
        return [URLQueryItem(name: "api_key", value: credential)] + queryItems
    }

    private var usesBearerToken: Bool {
        credential.contains(".") || credential.hasPrefix("eyJ")
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        if !usesProxy, usesBearerToken {
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            let host = request.url?.host() ?? "unknown"
            print("TMDB network error: \(host) \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
            throw TMDBError.networkUnavailable(reason: "\(nsError.localizedDescription)（\(host)，\(nsError.code)）")
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TMDBError.requestFailed
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TMDBError.invalidResponse
        }
    }

    private struct SearchResponse: Decodable {
        let results: [TMDBMovieSearchResult]
    }

    private static func cleanedConfiguredURL(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.hasPrefix("$("), clean != "your_proxy_url_here" else {
            return ""
        }
        return clean
    }
}

enum TMDBError: LocalizedError {
    case missingAPIKey
    case requestFailed
    case invalidResponse
    case networkUnavailable(reason: String? = nil)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "还没有配置电影资料源。配置后即可搜索电影并补全年份、导演和海报。"
        case .requestFailed:
            "电影资料暂时获取失败，可以稍后再试或手动填写。"
        case .invalidResponse:
            "电影资料返回格式暂时无法识别，可以稍后再试或手动填写。"
        case .networkUnavailable(let reason):
            if let reason, !reason.isEmpty {
                "无法连接电影资料源：\(reason)"
            } else {
                "无法连接电影资料源。请检查手机网络、VPN 或代理设置后再试。"
            }
        }
    }
}
