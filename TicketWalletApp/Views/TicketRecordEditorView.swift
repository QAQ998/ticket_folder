import PhotosUI
import SwiftData
import SwiftUI

struct TicketRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let record: MovieRecord?

    @State private var movieTitle: String
    @State private var originalTitle: String
    @State private var year: String
    @State private var director: String
    @State private var tmdbId: Int?
    @State private var metadataSource: String
    @State private var metadataFetchedAt: Date?
    @State private var posterLocalPath: String?
    @State private var posterCachedAt: Date?

    @State private var watchedAt: Date
    @State private var cinema: String
    @State private var hall: String
    @State private var seat: String
    @State private var ticketPrice: String
    @State private var ticketImagePaths: [String]
    @State private var rating: Int
    @State private var note: String

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingMovieSearch = false
    @State private var isRecognizing = false
    @State private var message = ""

    private let ocrService = TicketOCRService()
    private let parsingService = TicketParsingService()

    init(record: MovieRecord? = nil) {
        self.record = record
        _movieTitle = State(initialValue: record?.movieTitle ?? "")
        _originalTitle = State(initialValue: record?.originalTitle ?? "")
        _year = State(initialValue: record?.year ?? "")
        _director = State(initialValue: record?.director ?? "")
        _tmdbId = State(initialValue: record?.tmdbId)
        _metadataSource = State(initialValue: record?.metadataSource ?? "manual")
        _metadataFetchedAt = State(initialValue: record?.metadataFetchedAt)
        _posterLocalPath = State(initialValue: record?.posterLocalPath)
        _posterCachedAt = State(initialValue: record?.posterCachedAt)
        _watchedAt = State(initialValue: record?.watchedAt ?? .now)
        _cinema = State(initialValue: record?.cinema ?? "")
        _hall = State(initialValue: record?.hall ?? "")
        _seat = State(initialValue: record?.seat ?? "")
        _ticketPrice = State(initialValue: record?.ticketPrice ?? "")
        _ticketImagePaths = State(initialValue: record?.ticketImagePaths ?? [])
        _rating = State(initialValue: record?.rating ?? 0)
        _note = State(initialValue: record?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.95, green: 0.92, blue: 0.86)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        editorSection("票根图片", systemImage: "ticket") {
                            if let first = ticketImagePaths.first {
                                TicketPhotoView(filename: first)
                                    .frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                emptyTicketPreview
                            }

                            HStack(spacing: 10) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    Label("相册", systemImage: "photo")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(TicketPalette.green)

                                Button {
                                    showingCamera = true
                                } label: {
                                    Label("拍摄", systemImage: "camera")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(TicketPalette.accent)
                            }

                            if isRecognizing {
                                ProgressView("正在识别票面文字")
                                    .foregroundStyle(TicketPalette.muted)
                            }
                        }

                        editorSection("票面信息", systemImage: "text.viewfinder") {
                            TextField("电影名", text: $movieTitle)
                                .textFieldStyle(.roundedBorder)
                            DatePicker("观影时间", selection: $watchedAt)
                            TextField("影院", text: $cinema)
                                .textFieldStyle(.roundedBorder)
                            TextField("影厅", text: $hall)
                                .textFieldStyle(.roundedBorder)
                            TextField("座位", text: $seat)
                                .textFieldStyle(.roundedBorder)
                            TextField("票价", text: $ticketPrice)
                                .textFieldStyle(.roundedBorder)
                        }

                        editorSection("电影资料", systemImage: "film") {
                            HStack(spacing: 12) {
                                PosterView(filename: posterLocalPath)
                                    .frame(width: 64, height: 94)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(movieTitle.isEmpty ? "先填写或识别电影名" : movieTitle)
                                        .font(.headline)
                                        .foregroundStyle(TicketPalette.ink)
                                    Text([year, director].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(TicketPalette.muted)
                                    if metadataSource == "tmdb" {
                                        TicketPill(text: "海报已缓存")
                                    }
                                }
                            }

                            Button {
                                showingMovieSearch = true
                            } label: {
                                Label("从 TMDB 补全资料", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(TicketPalette.accent)

                            TextField("年份", text: $year)
                                .textFieldStyle(.roundedBorder)
                            TextField("导演", text: $director)
                                .textFieldStyle(.roundedBorder)
                        }

                        editorSection("私人记录", systemImage: "square.and.pencil") {
                            RatingPicker(rating: $rating)
                            TextField("短评，可留空", text: $note, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...8)
                        }

                        if !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(TicketPalette.muted)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(TicketPalette.paper.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(record == nil ? "录入票根" : "编辑票根")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(movieTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    await importPhoto(item)
                }
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(sourceType: .camera) { image in
                    Task {
                        await saveAndRecognize(image)
                    }
                }
            }
            .sheet(isPresented: $showingMovieSearch) {
                MovieSearchView(initialQuery: movieTitle) { _, details, foundDirector, cachedPoster in
                    movieTitle = details.title
                    originalTitle = details.originalTitle ?? ""
                    year = details.year
                    director = foundDirector
                    tmdbId = details.id
                    metadataSource = "tmdb"
                    metadataFetchedAt = .now
                    if let cachedPoster {
                        PosterCacheStore.delete(posterLocalPath)
                        posterLocalPath = cachedPoster
                        posterCachedAt = .now
                    }
                }
            }
        }
    }

    private var emptyTicketPreview: some View {
        VStack(spacing: 10) {
            Image(systemName: "ticket")
                .font(.system(size: 42))
                .foregroundStyle(TicketPalette.accent)
            Text("添加一张纸质票根或电子票截图")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TicketPalette.ink)
            Text("识别后可以手动校对信息")
                .font(.caption)
                .foregroundStyle(TicketPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(TicketPalette.paperDeep.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func editorSection<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(TicketPalette.ink)
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                message = "无法读取这张图片，请换一张再试。"
                return
            }
            await saveAndRecognize(image)
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveAndRecognize(_ image: UIImage) async {
        do {
            let filename = try TicketImageStore.save(image)
            ticketImagePaths = [filename]
            isRecognizing = true
            defer { isRecognizing = false }

            let text = try await ocrService.recognizeText(in: image)
            let draft = parsingService.parse(text)
            if !draft.movieTitle.isEmpty { movieTitle = draft.movieTitle }
            watchedAt = draft.watchedAt
            if !draft.cinema.isEmpty { cinema = draft.cinema }
            if !draft.hall.isEmpty { hall = draft.hall }
            if !draft.seat.isEmpty { seat = draft.seat }
            if !draft.ticketPrice.isEmpty { ticketPrice = draft.ticketPrice }
            message = draft.isEmpty ? "没有识别出明确字段，可以手动填写。" : "已识别票面文字，请确认并修正。"
        } catch {
            isRecognizing = false
            message = error.localizedDescription
        }
    }

    private func save() {
        let target = record ?? MovieRecord()
        target.movieTitle = movieTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        target.originalTitle = originalTitle
        target.year = year
        target.director = director
        target.tmdbId = tmdbId
        target.metadataSource = metadataSource
        target.metadataFetchedAt = metadataFetchedAt
        target.posterLocalPath = posterLocalPath
        target.posterCachedAt = posterCachedAt
        target.watchedAt = watchedAt
        target.cinema = cinema
        target.hall = hall
        target.seat = seat
        target.ticketPrice = ticketPrice
        target.ticketImagePaths = ticketImagePaths
        target.rating = rating
        target.note = note
        target.updatedAt = .now

        if record == nil {
            modelContext.insert(target)
        }
        try? modelContext.save()
        dismiss()
    }
}
