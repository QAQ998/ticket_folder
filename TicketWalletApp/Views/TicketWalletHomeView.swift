import SwiftData
import SwiftUI

struct TicketWalletHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MovieRecord.watchedAt, order: .reverse) private var records: [MovieRecord]
    @State private var searchText = ""
    @State private var showingEditor = false

    private var filteredRecords: [MovieRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return records
        }
        return records.filter {
            $0.movieTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.cinema.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TicketPalette.dark.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if filteredRecords.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(filteredRecords) { record in
                                    NavigationLink(value: record) {
                                        TicketCard(record: record)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationDestination(for: MovieRecord.self) { record in
                TicketRecordDetailView(record: record)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("录入票根", systemImage: "plus")
                    }
                    .tint(TicketPalette.paper)
                }
            }
            .sheet(isPresented: $showingEditor) {
                TicketRecordEditorView()
            }
            .searchable(text: $searchText, prompt: "搜索电影或影院")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("散场记")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(TicketPalette.paper)
            Text("开场前也可以记，散场后慢慢收好。")
                .font(.subheadline)
                .foregroundStyle(TicketPalette.paper.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "ticket")
                .font(.system(size: 52))
                .foregroundStyle(TicketPalette.accent)
            Text("还没有票根")
                .font(.title3.weight(.semibold))
            Text("从一张电影票开始，慢慢收起你的观影轨迹。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(TicketPalette.muted)
            Button {
                showingEditor = true
            } label: {
                Label("录入第一张", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(TicketPalette.accent)
        }
        .foregroundStyle(TicketPalette.ink)
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(TicketPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TicketCard: View {
    let record: MovieRecord

    var body: some View {
        HStack(spacing: 12) {
            PosterView(filename: record.posterLocalPath)
                .frame(width: 72, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 8) {
                Text(record.movieTitle.isEmpty ? "未命名电影" : record.movieTitle)
                    .font(.headline)
                    .foregroundStyle(TicketPalette.ink)
                    .lineLimit(2)
                Text([record.year, record.director].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(TicketPalette.muted)
                    .lineLimit(1)
                Text(record.watchedAt.ticketDateText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TicketPalette.accent)
                Text([record.cinema, record.hall, record.seat].filter { !$0.isEmpty }.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(TicketPalette.muted)
                    .lineLimit(1)
                RatingDots(rating: record.rating)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            TicketPalette.paper
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(TicketPalette.accent.opacity(0.12))
                        .frame(width: 8)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
