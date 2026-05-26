import SwiftUI

struct MovieSearchView: View {
    let initialQuery: String
    let onSelect: (TMDBMovieSearchResult, TMDBMovieDetails, String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [TMDBMovieSearchResult] = []
    @State private var message = ""
    @State private var isLoading = false

    private let client = TMDBClient()

    init(initialQuery: String, onSelect: @escaping (TMDBMovieSearchResult, TMDBMovieDetails, String, String?) -> Void) {
        self.initialQuery = initialQuery
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                if !message.isEmpty {
                    Text(message)
                        .foregroundStyle(TicketPalette.muted)
                }

                ForEach(results) { movie in
                    Button {
                        Task {
                            await select(movie)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(movie.title)
                                .foregroundStyle(TicketPalette.ink)
                            Text([movie.year, movie.originalTitle ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(TicketPalette.muted)
                            if let overview = movie.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.caption)
                                    .foregroundStyle(TicketPalette.muted)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择电影资料")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索电影名")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("搜索") {
                            Task {
                                await search()
                            }
                        }
                    }
                }
            }
            .task {
                await search()
            }
            .onSubmit(of: .search) {
                Task {
                    await search()
                }
            }
        }
    }

    private func search() async {
        isLoading = true
        message = ""
        defer { isLoading = false }

        do {
            results = try await client.searchMovies(query: query)
            if results.isEmpty {
                message = "没有找到合适的电影，可以关闭后手动填写资料。"
            }
        } catch {
            results = []
            message = error.localizedDescription
        }
    }

    private func select(_ movie: TMDBMovieSearchResult) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let metadata = try await client.metadata(for: movie.id)
            let posterPath = try await PosterCacheStore.cachePoster(from: client.posterURL(for: metadata.details.posterPath))
            onSelect(movie, metadata.details, metadata.director, posterPath)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
