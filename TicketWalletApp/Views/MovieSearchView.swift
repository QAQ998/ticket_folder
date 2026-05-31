import SwiftUI

struct MovieSearchView: View {
    let initialQuery: String
    let onSelect: (TMDBMovieSearchResult, TMDBMovieMetadata) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [TMDBMovieSearchResult] = []
    @State private var message = ""
    @State private var isLoading = false

    private let client = TMDBClient()

    init(initialQuery: String, onSelect: @escaping (TMDBMovieSearchResult, TMDBMovieMetadata) -> Void) {
        self.initialQuery = initialQuery
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                TMDBAttributionView()
                    .listRowBackground(TicketPalette.background)

                if !message.isEmpty {
                    Text(message)
                        .foregroundStyle(TicketPalette.muted)
                        .listRowBackground(TicketPalette.background)
                }

                ForEach(results) { movie in
                    Button {
                        Task {
                            await select(movie)
                        }
                    } label: {
                        MovieSearchResultRow(movie: movie, posterURL: client.posterURL(for: movie.posterPath))
                    }
                    .listRowBackground(TicketPalette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(TicketPalette.background)
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
        guard client.isConfigured else {
            results = []
            message = TMDBError.missingAPIKey.localizedDescription
            return
        }

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
            onSelect(movie, metadata)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct MovieSearchResultRow: View {
    let movie: TMDBMovieSearchResult
    let posterURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    ZStack {
                        TicketPalette.charcoal
                        Image(systemName: "film")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(width: 54, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title)
                    .font(.headline)
                    .foregroundStyle(TicketPalette.ink)
                Text([movie.year, movie.originalTitle ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(TicketPalette.muted)
                if let overview = movie.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(TicketPalette.muted)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
