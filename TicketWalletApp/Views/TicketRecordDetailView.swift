import SwiftData
import SwiftUI

struct TicketRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let record: MovieRecord
    @State private var showingEditor = false
    @State private var showingDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                section("票根") {
                    if let first = record.ticketImagePaths.first {
                        TicketPhotoView(filename: first)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("没有保存票根图片")
                            .foregroundStyle(TicketPalette.muted)
                    }
                }
                section("观影信息") {
                    infoRow("时间", record.watchedAt.ticketDateText)
                    infoRow("影院", record.cinema)
                    infoRow("影厅", record.hall)
                    infoRow("座位", record.seat)
                    infoRow("票价", record.ticketPrice)
                }
                section("私人记录") {
                    RatingDots(rating: record.rating)
                    if !record.note.isEmpty {
                        Text(record.note)
                            .foregroundStyle(TicketPalette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
        }
        .background(TicketPalette.paper.opacity(0.45))
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
        HStack(alignment: .bottom, spacing: 16) {
            PosterView(filename: record.posterLocalPath)
                .frame(width: 116, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 8) {
                Text(record.movieTitle.isEmpty ? "未命名电影" : record.movieTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TicketPalette.ink)
                Text([record.year, record.director].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(TicketPalette.muted)
                Text(record.metadataSource == "tmdb" ? "资料来自 TMDB" : "手动录入资料")
                    .font(.caption)
                    .foregroundStyle(TicketPalette.accent)
            }
            Spacer()
        }
        .padding(16)
        .background(TicketPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(TicketPalette.ink)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
