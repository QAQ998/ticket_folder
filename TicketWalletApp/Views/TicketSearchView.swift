import SwiftData
import SwiftUI

struct TicketSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MovieRecord.watchedAt, order: .reverse) private var records: [MovieRecord]
    @AppStorage("ticketSearchHistory") private var searchHistoryData = ""

    @State private var query = ""
    @State private var movieResults: [TMDBMovieSearchResult] = []
    @State private var message = ""
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedMetadata: TMDBMovieMetadata?

    private let client = TMDBClient()

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localResults: [MovieRecord] {
        guard !trimmedQuery.isEmpty else { return [] }
        return records.filter { record in
            record.movieTitle.localizedCaseInsensitiveContains(trimmedQuery) ||
            record.originalTitle.localizedCaseInsensitiveContains(trimmedQuery) ||
            record.director.localizedCaseInsensitiveContains(trimmedQuery) ||
            record.cinema.localizedCaseInsensitiveContains(trimmedQuery) ||
            record.hall.localizedCaseInsensitiveContains(trimmedQuery) ||
            record.seat.localizedCaseInsensitiveContains(trimmedQuery) ||
            record.note.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var searchHistory: [String] {
        searchHistoryData
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TicketPalette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        searchInput

                        if trimmedQuery.isEmpty {
                            historySection
                        } else {
                            resultSections
                        }
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .onChange(of: query) { _, _ in
                scheduleMovieSearch()
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .sheet(item: $selectedMetadata) { metadata in
                TicketRecordEditorView(initialMetadata: metadata)
            }
        }
    }

    private var searchInput: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TicketPalette.muted)
            TextField(
                "",
                text: $query,
                prompt: Text("搜索电影、影院、导演或座位")
                    .foregroundStyle(TicketPalette.muted.opacity(0.78))
            )
                .foregroundStyle(TicketPalette.ink)
                .tint(TicketPalette.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    addHistory(trimmedQuery)
                    scheduleMovieSearch(immediate: true)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    movieResults = []
                    message = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(TicketPalette.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(TicketPalette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(TicketPalette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var historySection: some View {
        if !searchHistory.isEmpty {
            TicketSectionCard(title: "最近搜索", systemImage: "clock.arrow.circlepath") {
                VStack(spacing: 10) {
                    ForEach(searchHistory, id: \.self) { keyword in
                        Button {
                            query = keyword
                            scheduleMovieSearch(immediate: true)
                        } label: {
                            HStack {
                                Text(keyword)
                                    .foregroundStyle(TicketPalette.ink)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(TicketPalette.muted)
                            }
                            .frame(height: 34)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            TicketSectionCard(title: "开始搜索", systemImage: "magnifyingglass") {
                Text("可以搜索已保存的票根，也可以实时查找电影资料。")
                    .font(.subheadline)
                    .foregroundStyle(TicketPalette.muted)
            }
        }
    }

    private var resultSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !localResults.isEmpty {
                TicketSectionCard(title: "已保存票根", systemImage: "ticket") {
                    VStack(spacing: 10) {
                        ForEach(localResults) { record in
                            NavigationLink {
                                TicketRecordDetailView(record: record)
                            } label: {
                                SearchRecordRow(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            TicketSectionCard(title: "电影推荐", systemImage: "film") {
                VStack(alignment: .leading, spacing: 12) {
                    MovieMetadataSourceView()

                    if isLoading {
                        ProgressView("正在搜索电影")
                            .foregroundStyle(TicketPalette.muted)
                    } else if !message.isEmpty {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(TicketPalette.muted)
                    }

                    ForEach(movieResults.prefix(8)) { movie in
                        Button {
                            addHistory(trimmedQuery)
                            Task {
                                await select(movie)
                            }
                        } label: {
                            SearchMovieRow(movie: movie, posterURL: client.posterURL(for: movie.posterPath))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func scheduleMovieSearch(immediate: Bool = false) {
        searchTask?.cancel()
        message = ""

        let currentQuery = trimmedQuery

        guard !currentQuery.isEmpty else {
            movieResults = []
            isLoading = false
            return
        }

        searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            await searchMovies(for: currentQuery)
        }
    }

    private func searchMovies(for currentQuery: String) async {
        guard client.isConfigured else {
            await updateSearchState(for: currentQuery, results: [], message: TMDBError.missingAPIKey.localizedDescription, isLoading: false)
            return
        }

        await updateSearchState(for: currentQuery, results: nil, message: "", isLoading: true)

        do {
            let results = try await client.searchMovies(query: currentQuery)
            guard !Task.isCancelled else { return }
            await updateSearchState(
                for: currentQuery,
                results: results,
                message: results.isEmpty ? "没有找到匹配的电影。" : "",
                isLoading: false
            )
        } catch {
            guard !Task.isCancelled else { return }
            await updateSearchState(for: currentQuery, results: [], message: error.localizedDescription, isLoading: false)
        }
    }

    @MainActor
    private func updateSearchState(for currentQuery: String, results: [TMDBMovieSearchResult]?, message: String, isLoading: Bool) {
        guard currentQuery == trimmedQuery else { return }
        if let results {
            movieResults = results
        }
        self.message = message
        self.isLoading = isLoading
    }

    @MainActor
    private func select(_ movie: TMDBMovieSearchResult) async {
        isLoading = true
        defer { isLoading = false }

        do {
            selectedMetadata = try await client.metadata(for: movie.id)
        } catch {
            message = error.localizedDescription
        }
    }

    private func addHistory(_ keyword: String) {
        let clean = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        var updated = searchHistory.filter { $0 != clean }
        updated.insert(clean, at: 0)
        searchHistoryData = updated.prefix(5).joined(separator: "\n")
    }
}

private struct SearchRecordRow: View {
    let record: MovieRecord

    var body: some View {
        HStack(spacing: 12) {
            TicketPhotoView(filename: record.ticketImagePaths.first)
                .frame(width: 50, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                Text(record.movieTitle.isEmpty ? "未命名电影" : record.movieTitle)
                    .font(.headline)
                    .foregroundStyle(TicketPalette.ink)
                    .lineLimit(1)
                Text([record.cinema, record.hall, record.seat].filter { !$0.isEmpty }.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(TicketPalette.muted)
                    .lineLimit(1)
                Text(record.watchedAt.ticketDateText)
                    .font(.caption)
                    .foregroundStyle(TicketPalette.muted)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TicketPalette.muted.opacity(0.55))
        }
        .padding(10)
        .background(TicketPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SearchMovieRow: View {
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
            .frame(width: 50, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 5) {
                Text(movie.title)
                    .font(.headline)
                    .foregroundStyle(TicketPalette.ink)
                    .lineLimit(2)
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
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

extension TMDBMovieMetadata: Identifiable {
    var id: Int { details.id }
}
