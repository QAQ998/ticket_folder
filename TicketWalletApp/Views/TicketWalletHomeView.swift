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
                TicketBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
                        Image(systemName: "plus")
                            .font(.headline)
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                TicketPill(text: "\(records.count) 张票根", tint: TicketPalette.gold)
                Text("散场记")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .foregroundStyle(TicketPalette.paper)
                Text("开场前也可以记，散场后慢慢收好。")
                    .font(.subheadline)
                    .foregroundStyle(TicketPalette.paper.opacity(0.72))
            }

            Button {
                showingEditor = true
            } label: {
                Label("录入一张票根", systemImage: "ticket")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TicketPalette.paper)
            .background(TicketPalette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 50))
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
        .background(
            TicketPalette.paper
                .overlay(alignment: .top) {
                    TicketDashedDivider()
                        .padding(.top, 14)
                }
                .overlay(alignment: .bottom) {
                    TicketDashedDivider()
                        .padding(.bottom, 14)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TicketCard: View {
    let record: MovieRecord

    var body: some View {
        VStack(spacing: 12) {
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
                    TicketPill(text: record.watchedAt.ticketDateText)
                    Text([record.cinema, record.hall, record.seat].filter { !$0.isEmpty }.joined(separator: " / "))
                        .font(.caption)
                        .foregroundStyle(TicketPalette.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            TicketDashedDivider()

            HStack {
                RatingDots(rating: record.rating)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TicketPalette.muted.opacity(0.55))
            }
        }
        .padding(14)
        .background(
            TicketPalette.paper
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(TicketPalette.accent)
                        .frame(width: 5)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 6)
    }
}
