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
    private let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private let imageBaseURL = URL(string: "https://image.tmdb.org/t/p/w500")!
    private let credential: String

    init(apiKey: String = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? "") {
        self.credential = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !credential.isEmpty && credential != "$(TMDB_API_KEY)"
    }

    func searchMovies(query: String) async throws -> [TMDBMovieSearchResult] {
        guard isConfigured else { throw TMDBError.missingAPIKey }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

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
        return imageBaseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func cachePoster(for details: TMDBMovieDetails) async throws -> String? {
        try await PosterCacheStore.cachePoster(from: posterURL(for: details.posterPath))
    }

    private func authorizedQueryItems(_ queryItems: [URLQueryItem]) -> [URLQueryItem] {
        guard !usesBearerToken else {
            return queryItems
        }
        return [URLQueryItem(name: "api_key", value: credential)] + queryItems
    }

    private var usesBearerToken: Bool {
        credential.contains(".") || credential.hasPrefix("eyJ")
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        if usesBearerToken {
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
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
}

enum TMDBError: LocalizedError {
    case missingAPIKey
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "还没有配置 TMDB API Key。配置后即可搜索电影、补全导演年份并缓存海报。"
        case .requestFailed:
            "电影资料暂时获取失败，可以稍后再试或手动填写。"
        case .invalidResponse:
            "电影资料返回格式暂时无法识别，可以稍后再试或手动填写。"
        }
    }
}
