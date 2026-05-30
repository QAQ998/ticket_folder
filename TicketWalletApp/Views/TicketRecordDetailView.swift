import SwiftData
import SwiftUI

struct TicketRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let record: MovieRecord
    @State private var showingEditor = false
    @State private var showingDeleteAlert = false

    var body: some View {
        ZStack {
            TicketBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    TicketSectionCard(title: "票根", systemImage: "ticket") {
                        if let first = record.ticketImagePaths.first {
                            TicketPhotoView(filename: first)
                                .frame(height: 270)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Text("没有保存票根图片")
                                .foregroundStyle(TicketPalette.muted)
                        }
                    }
                    TicketSectionCard(title: "观影信息", systemImage: "calendar") {
                        infoRow("时间", record.watchedAt.ticketDateText)
                        infoRow("影院", record.cinema)
                        infoRow("影厅", record.hall)
                        infoRow("座位", record.seat)
                        infoRow("票价", record.ticketPrice)
                    }
                    TicketSectionCard(title: "私人记录", systemImage: "pencil.and.outline") {
                        RatingDots(rating: record.rating)
                        if !record.note.isEmpty {
                            Text(record.note)
                                .foregroundStyle(TicketPalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("还没有写下短评。")
                                .foregroundStyle(TicketPalette.muted)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle(record.movieTitle.isEmpty ? "票根详情" : record.movieTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("编辑") {
                    showingEditor = true
                }
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            TicketRecordEditorView(record: record)
        }
        .alert("删除这张票根？", isPresented: $showingDeleteAlert) {
            Button("删除", role: .destructive) {
                deleteRecord()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("票根图片、本地记录和缓存海报都会从这台设备删除。")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                PosterView(filename: record.posterLocalPath)
                    .frame(width: 116, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 10) {
                    TicketPill(text: record.metadataSource == "tmdb" ? "TMDB 资料" : "手动资料")
                    Text(record.movieTitle.isEmpty ? "未命名电影" : record.movieTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(TicketPalette.ink)
                    Text([record.year, record.director].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(TicketPalette.muted)
                }
                Spacer()
            }

            TicketDashedDivider()

            HStack {
                Label(record.watchedAt.ticketDateText, systemImage: "clock")
                Spacer()
                if !record.seat.isEmpty {
                    Label(record.seat, systemImage: "chair")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(TicketPalette.muted)
        }
        .padding(16)
        .background(TicketPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 8)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(TicketPalette.muted)
            Spacer()
            Text(value.isEmpty ? "未填写" : value)
                .foregroundStyle(TicketPalette.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func deleteRecord() {
        for filename in record.ticketImagePaths {
            TicketImageStore.delete(filename)
        }
        PosterCacheStore.delete(record.posterLocalPath)
        modelContext.delete(record)
        try? modelContext.save()
        dismiss()
    }
}
