import Foundation

struct MovieMetadata: Identifiable {
    var title: String
    var originalTitle: String
    var year: String
    var releaseDate: String
    var director: String
    var runtimeMinutes: Int?
    var doubanRating: String
    var tmdbRating: Double?
    var tmdbId: Int?
    var posterLocalPath: String?
    var source: String

    var id: String {
        [source, title, originalTitle, releaseDate]
            .joined(separator: "|")
    }

    var hasRequiredMovieInfo: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !releaseDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !director.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            runtimeMinutes != nil &&
            !doubanRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MovieMetadataService {
    private let doubanClient = DoubanMovieClient()
    private let tmdbClient = TMDBClient()

    var isConfigured: Bool {
        doubanClient.isConfigured || tmdbClient.isConfigured
    }

    var isDoubanConfigured: Bool {
        doubanClient.isConfigured
    }

    func metadata(for queries: [String]) async throws -> MovieMetadata {
        guard !queries.isEmpty else { throw MovieMetadataError.emptyQuery }

        var doubanMetadata: MovieMetadata?
        var providerError: Error?
        if doubanClient.isConfigured {
            do {
                doubanMetadata = try await firstMetadata(from: doubanClient, queries: queries)
                if let doubanMetadata, doubanMetadata.hasRequiredMovieInfo {
                    return doubanMetadata
                }
            } catch {
                providerError = error
            }
        }

        var tmdbMetadata: MovieMetadata?
        if tmdbClient.isConfigured {
            do {
                tmdbMetadata = try await firstTMDBMetadata(queries: queries)
            } catch {
                providerError = error
            }
        }

        if var merged = doubanMetadata {
            if let tmdbMetadata {
                merged = merge(primary: merged, fallback: tmdbMetadata)
            }
            return merged
        }

        if let tmdbMetadata {
            return tmdbMetadata
        }

        if !doubanClient.isConfigured, !tmdbClient.isConfigured {
            throw MovieMetadataError.missingProvider
        }
        if let providerError {
            throw providerError
        }
        throw MovieMetadataError.notFound
    }

    private func firstMetadata(from client: DoubanMovieClient, queries: [String]) async throws -> MovieMetadata? {
        var lastError: Error?
        for query in queries {
            do {
                if let metadata = try await client.searchMovie(query: query) {
                    return metadata
                }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    private func firstTMDBMetadata(queries: [String]) async throws -> MovieMetadata? {
        var lastError: Error?
        for query in queries {
            do {
                guard let first = try await tmdbClient.searchMovies(query: query).first else { continue }
                return try await tmdbClient.metadata(for: first.id).asMovieMetadata()
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    private func merge(primary: MovieMetadata, fallback: MovieMetadata) -> MovieMetadata {
        var merged = primary
        if merged.title.isEmpty { merged.title = fallback.title }
        if merged.originalTitle.isEmpty { merged.originalTitle = fallback.originalTitle }
        if merged.year.isEmpty { merged.year = fallback.year }
        if merged.releaseDate.isEmpty { merged.releaseDate = fallback.releaseDate }
        if merged.director.isEmpty { merged.director = fallback.director }
        if merged.runtimeMinutes == nil { merged.runtimeMinutes = fallback.runtimeMinutes }
        if merged.tmdbRating == nil { merged.tmdbRating = fallback.tmdbRating }
        if merged.tmdbId == nil { merged.tmdbId = fallback.tmdbId }
        if merged.posterLocalPath == nil { merged.posterLocalPath = fallback.posterLocalPath }
        if primary.source != fallback.source {
            merged.source = "\(primary.source)+\(fallback.source)"
        }
        return merged
    }
}

struct DoubanMovieClient {
    private let baseURL: URL?
    private let apiKey: String
    private let session: URLSession

    init(
        apiBaseURL: String = Bundle.main.object(forInfoDictionaryKey: "DOUBAN_API_BASE_URL") as? String ?? "",
        apiKey: String = Bundle.main.object(forInfoDictionaryKey: "DOUBAN_API_KEY") as? String ?? ""
    ) {
        let cleanedBaseURL = Self.cleanedConfiguredURL(apiBaseURL)
        self.baseURL = URL(string: cleanedBaseURL)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 20 * 1024 * 1024,
            diskPath: "DoubanMovieMetadata"
        )
        self.session = URLSession(configuration: configuration)
    }

    var isConfigured: Bool {
        baseURL != nil
    }

    func searchMovie(query: String) async throws -> MovieMetadata? {
        guard let baseURL else { throw MovieMetadataError.missingProvider }
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return nil }

        var components = URLComponents(url: baseURL.appending(path: "movie/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: cleanQuery)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("TicketWalletApp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty, !apiKey.hasPrefix("$("), apiKey != "your_douban_api_key_here" {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw MovieMetadataError.requestFailed
        }

        let decoded = try JSONDecoder().decode(DoubanMovieSearchResponse.self, from: data)
        guard let movie = decoded.bestMatch else { return nil }
        let posterLocalPath = try await PosterCacheStore.cachePoster(from: movie.posterURL)
        return MovieMetadata(
            title: movie.title,
            originalTitle: movie.originalTitle ?? "",
            year: movie.year,
            releaseDate: movie.releaseDate,
            director: movie.directorText,
            runtimeMinutes: movie.runtimeMinutes,
            doubanRating: movie.ratingText,
            tmdbRating: nil,
            tmdbId: nil,
            posterLocalPath: posterLocalPath,
            source: "douban"
        )
    }

    private static func cleanedConfiguredURL(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.hasPrefix("$("), clean != "your_douban_proxy_url_here" else {
            return ""
        }
        return clean
    }
}

private struct DoubanMovieSearchResponse: Decodable {
    let results: [DoubanMoviePayload]
    let movie: DoubanMoviePayload?

    var bestMatch: DoubanMoviePayload? {
        movie ?? results.first
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           keyed.contains(.results) || keyed.contains(.subjects) || keyed.contains(.items) || keyed.contains(.movie) {
            self.results = (try? keyed.decode([DoubanMoviePayload].self, forKey: .results)) ??
                (try? keyed.decode([DoubanMoviePayload].self, forKey: .subjects)) ??
                (try? keyed.decode([DoubanMoviePayload].self, forKey: .items)) ??
                []
            self.movie = try? keyed.decode(DoubanMoviePayload.self, forKey: .movie)
        } else {
            let container = try decoder.singleValueContainer()
            self.movie = try container.decode(DoubanMoviePayload.self)
            self.results = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case results
        case subjects
        case items
        case movie
    }
}

private struct DoubanMoviePayload: Decodable {
    let title: String
    let originalTitle: String?
    let yearValue: String?
    let releaseDateValue: String?
    let directors: [String]?
    let director: String?
    let runtimeText: String?
    let runtimeMinutesValue: Int?
    let ratingValue: String?
    let posterValue: String?

    var year: String {
        if let yearValue, !yearValue.isEmpty { return yearValue }
        return String(releaseDate.prefix(4))
    }

    var releaseDate: String {
        releaseDateValue ?? ""
    }

    var directorText: String {
        if let directors, !directors.isEmpty {
            return directors.joined(separator: " / ")
        }
        return director ?? ""
    }

    var runtimeMinutes: Int? {
        if let runtimeMinutesValue { return runtimeMinutesValue }
        guard let runtimeText else { return nil }
        return Int(runtimeText.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression))
    }

    var ratingText: String {
        ratingValue ?? ""
    }

    var posterURL: URL? {
        guard let posterValue, !posterValue.isEmpty else { return nil }
        return URL(string: posterValue)
    }

    enum CodingKeys: String, CodingKey {
        case title
        case originalTitle = "original_title"
        case yearValue = "year"
        case releaseDateValue = "release_date"
        case directors
        case director
        case runtimeText = "runtime"
        case runtimeMinutesValue = "runtime_minutes"
        case ratingValue = "douban_rating"
        case posterValue = "poster_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        originalTitle = try? container.decode(String.self, forKey: .originalTitle)
        yearValue = try? container.decode(String.self, forKey: .yearValue)
        releaseDateValue = try? container.decode(String.self, forKey: .releaseDateValue)
        directors = try? container.decode([String].self, forKey: .directors)
        director = try? container.decode(String.self, forKey: .director)
        runtimeText = try? container.decode(String.self, forKey: .runtimeText)
        runtimeMinutesValue = try? container.decode(Int.self, forKey: .runtimeMinutesValue)
        if let rating = try? container.decode(Double.self, forKey: .ratingValue) {
            ratingValue = String(format: "%.1f", rating)
        } else {
            ratingValue = try? container.decode(String.self, forKey: .ratingValue)
        }
        posterValue = try? container.decode(String.self, forKey: .posterValue)
    }
}

extension TMDBMovieMetadata {
    func asMovieMetadata() -> MovieMetadata {
        MovieMetadata(
            title: details.title,
            originalTitle: details.originalTitle ?? "",
            year: details.year,
            releaseDate: details.releaseDate ?? "",
            director: director,
            runtimeMinutes: details.runtime,
            doubanRating: "",
            tmdbRating: details.voteAverage,
            tmdbId: details.id,
            posterLocalPath: posterLocalPath,
            source: "tmdb"
        )
    }
}

enum MovieMetadataError: LocalizedError {
    case emptyQuery
    case missingProvider
    case notFound
    case requestFailed
    case incompleteRequiredInfo

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "还没有识别到片名，无法自动补全影片信息。"
        case .missingProvider:
            "还没有配置影片资料源。请先配置豆瓣资料代理，或配置 TMDB 作为兜底。"
        case .notFound:
            "没有找到匹配的影片资料，请检查片名是否正确。"
        case .requestFailed:
            "影片资料请求失败，请稍后再试。"
        case .incompleteRequiredInfo:
            "影片信息还没有补全。需要自动获取上映日期、导演、片长和豆瓣评分后才能保存。"
        }
    }
}
