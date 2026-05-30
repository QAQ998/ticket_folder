import SwiftData
import SwiftUI

struct TicketWalletHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MovieRecord.watchedAt, order: .reverse) private var records: [MovieRecord]
    @State private var searchText = ""
    @State private var showingEditor = false
    @FocusState private var isSearchFocused: Bool

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
                    VStack(alignment: .leading, spacing: 24) {
                        searchBar
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
                    .padding(.bottom, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isSearchFocused = false
                    }
                )
            }
            .navigationDestination(for: MovieRecord.self) { record in
                TicketRecordDetailView(record: record)
            }
            .sheet(isPresented: $showingEditor) {
                TicketRecordEditorView()
            }
            .onAppear {
                isSearchFocused = false
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TicketPalette.muted)
            TextField("搜索电影或影院", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("散场记")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(TicketPalette.ink)
                Text("开场前也可以记，散场后慢慢收好。")
                    .font(.subheadline)
                    .foregroundStyle(TicketPalette.muted)
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
            .foregroundStyle(.white)
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
                .foregroundStyle(.black)
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
            TicketPalette.surface
                .overlay(alignment: .top) {
                    TicketDashedDivider()
                        .padding(.top, 14)
                }
                .overlay(alignment: .bottom) {
                    TicketDashedDivider()
                        .padding(.bottom, 14)
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TicketCard: View {
    let record: MovieRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                thumbnail
                    .frame(width: 64, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 8) {
                    Text(record.movieTitle.isEmpty ? "未命名电影" : record.movieTitle)
                        .font(.title3.weight(.semibold))
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
            TicketPalette.surface
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 8)
    }

    private var thumbnail: some View {
        Group {
            if record.posterLocalPath != nil {
                PosterView(filename: record.posterLocalPath)
            } else {
                TicketPhotoView(filename: record.ticketImagePaths.first)
            }
        }
    }
}
