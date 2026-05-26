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
    private let apiKey: String

    init(apiKey: String = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? "") {
        self.apiKey = apiKey
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func searchMovies(query: String) async throws -> [TMDBMovieSearchResult] {
        guard isConfigured else { throw TMDBError.missingAPIKey }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var components = URLComponents(url: baseURL.appending(path: "search/movie"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: "zh-CN"),
            URLQueryItem(name: "include_adult", value: "false")
        ]

        let response: SearchResponse = try await get(components.url!)
        return response.results
    }

    func metadata(for id: Int) async throws -> (details: TMDBMovieDetails, director: String) {
        guard isConfigured else { throw TMDBError.missingAPIKey }

        let detailsURL: URL = {
            var components = URLComponents(url: baseURL.appending(path: "movie/\(id)"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "language", value: "zh-CN")
            ]
            return components.url!
        }()

        let creditsURL: URL = {
            var components = URLComponents(url: baseURL.appending(path: "movie/\(id)/credits"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "language", value: "zh-CN")
            ]
            return components.url!
        }()

        async let details: TMDBMovieDetails = get(detailsURL)
        async let credits: TMDBCredits = get(creditsURL)
        return try await (details, credits.director)
    }

    func posterURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return imageBaseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TMDBError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct SearchResponse: Decodable {
        let results: [TMDBMovieSearchResult]
    }
}

enum TMDBError: LocalizedError {
    case missingAPIKey
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "还没有配置 TMDB API Key，可以先手动填写电影资料。"
        case .requestFailed:
            "电影资料暂时获取失败，可以稍后再试或手动填写。"
        }
    }
}
