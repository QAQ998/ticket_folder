import SwiftUI

struct MovieSearchView: View {
    let initialQuery: String
    let onSelect: (MovieMetadata) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [MovieMetadata] = []
    @State private var message = ""
    @State private var isLoading = false

    private let metadataService = MovieMetadataService()

    init(initialQuery: String, onSelect: @escaping (MovieMetadata) -> Void) {
        self.initialQuery = initialQuery
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                MovieMetadataAttributionView()
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
                        MovieSearchResultRow(movie: movie)
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
        guard metadataService.isConfigured else {
            results = []
            message = MovieMetadataError.missingProvider.localizedDescription
            return
        }

        isLoading = true
        message = ""
        defer { isLoading = false }

        do {
            let metadata = try await metadataService.metadata(for: [query])
            results = [metadata]
            if results.isEmpty {
                message = "没有找到合适的电影。请检查片名后重试，影片资料需要自动补全后才能保存。"
            }
        } catch {
            results = []
            message = error.localizedDescription
        }
    }

    private func select(_ movie: MovieMetadata) async {
        isLoading = true
        defer { isLoading = false }

        onSelect(movie)
        dismiss()
    }
}

private struct MovieSearchResultRow: View {
    let movie: MovieMetadata

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                TicketPalette.charcoal
                if let posterLocalPath = movie.posterLocalPath,
                   let uiImage = UIImage(contentsOfFile: posterLocalPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 54, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title)
                    .font(.headline)
                    .foregroundStyle(TicketPalette.ink)
                Text([movie.releaseDate, movie.director].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(TicketPalette.muted)
                Text([movie.runtimeMinutes.map { "\($0) 分钟" } ?? "", movie.doubanRating.isEmpty ? "" : "豆瓣 \(movie.doubanRating)"]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(TicketPalette.muted)
            }
        }
        .padding(.vertical, 4)
    }
}
