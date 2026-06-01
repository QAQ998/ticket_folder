import PhotosUI
import SwiftData
import SwiftUI

private enum EditorField: Hashable {
    case movieTitle
    case cinema
    case hall
    case seat
    case ticketPrice
    case year
    case director
    case note
}

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
    @State private var showingTicketPreview = false
    @State private var showingMovieSearch = false
    @State private var isRecognizing = false
    @State private var message = ""
    @State private var recognizedLines: [String] = []
    @State private var pendingDeletedTicketImagePaths: [String] = []
    @State private var newlyImportedTicketImagePaths: [String] = []
    @FocusState private var focusedField: EditorField?

    private let ocrService = TicketOCRService()
    private let parsingService = TicketParsingService()

    init(record: MovieRecord? = nil, initialMetadata: TMDBMovieMetadata? = nil) {
        self.record = record
        _movieTitle = State(initialValue: record?.movieTitle ?? initialMetadata?.details.title ?? "")
        _originalTitle = State(initialValue: record?.originalTitle ?? initialMetadata?.details.originalTitle ?? "")
        _year = State(initialValue: record?.year ?? initialMetadata?.details.year ?? "")
        _director = State(initialValue: record?.director ?? initialMetadata?.director ?? "")
        _tmdbId = State(initialValue: record?.tmdbId ?? initialMetadata?.details.id)
        _metadataSource = State(initialValue: record?.metadataSource ?? (initialMetadata == nil ? "manual" : "tmdb"))
        _metadataFetchedAt = State(initialValue: record?.metadataFetchedAt ?? (initialMetadata == nil ? nil : .now))
        _posterLocalPath = State(initialValue: record?.posterLocalPath ?? initialMetadata?.posterLocalPath)
        _posterCachedAt = State(initialValue: record?.posterCachedAt ?? (initialMetadata?.posterLocalPath == nil ? nil : .now))
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
                TicketPalette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        editorSection("票根图片", systemImage: "ticket") {
                            if let first = ticketImagePaths.first {
                                Button {
                                    showingTicketPreview = true
                                } label: {
                                    TicketPhotoView(filename: first)
                                        .frame(height: 190)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .bottomTrailing) {
                                            Label("查看全图", systemImage: "arrow.up.left.and.arrow.down.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(.black.opacity(0.62))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .padding(10)
                                        }
                                }
                                .buttonStyle(.plain)
                            } else {
                                emptyTicketPreview

                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    Label("从相册选择", systemImage: "photo")
                                }
                                .buttonStyle(SecondaryActionButtonStyle())
                            }

                            if isRecognizing {
                                ProgressView("正在识别票面文字")
                                    .foregroundStyle(TicketPalette.muted)
                            }
                        }

                        editorSection("票面信息", systemImage: "text.viewfinder") {
                            candidateField("电影名", text: $movieTitle, field: .movieTitle)
                            candidateDateField
                            candidateField("影院", text: $cinema, field: .cinema)
                            candidateField("影厅", text: $hall, field: .hall)
                            candidateField("座位", text: $seat, field: .seat)
                            candidateField("票价", text: $ticketPrice, field: .ticketPrice)
                        }

                        if !recognizedLines.isEmpty {
                            editorSection("OCR 候选文本", systemImage: "text.magnifyingglass") {
                                Text("识别结果可能有误。你可以在每个字段右侧选择候选文本，也可以直接手动输入。")
                                    .font(.footnote)
                                    .foregroundStyle(TicketPalette.muted)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                    ForEach(recognizedLines, id: \.self) { line in
                                        Text(line)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .foregroundStyle(TicketPalette.ink)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(TicketPalette.paper)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
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
                                }
                            }

                            Button {
                                showingMovieSearch = true
                            } label: {
                                Label("匹配电影资料", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(SecondaryActionButtonStyle())

                            candidateField("年份", text: $year, field: .year)
                            candidateField("导演", text: $director, field: .director)
                        }

                        editorSection("私人记录", systemImage: "square.and.pencil") {
                            RatingPicker(rating: $rating)
                            labeledTextField("短评", placeholder: "可以留空", text: $note, field: .note, axis: .vertical)
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
                        cancelEditing()
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
            .fullScreenCover(isPresented: $showingTicketPreview) {
                if let first = ticketImagePaths.first {
                    TicketImagePreviewView(
                        filename: first,
                        selectedPhotoItem: $selectedPhotoItem,
                        onDelete: deleteCurrentTicketImage
                    )
                }
            }
            .sheet(isPresented: $showingMovieSearch) {
                MovieSearchView(initialQuery: movieTitle) { _, metadata in
                    let details = metadata.details
                    movieTitle = details.title
                    originalTitle = details.originalTitle ?? ""
                    year = details.year
                    director = metadata.director
                    tmdbId = details.id
                    metadataSource = "tmdb"
                    metadataFetchedAt = .now
                    if let cachedPoster = metadata.posterLocalPath {
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

    private func styledTextField(_ placeholder: String, text: Binding<String>, field: EditorField, axis: Axis = .horizontal) -> some View {
        let isActive = focusedField == field
        return TextField(placeholder, text: text, axis: axis)
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(isActive ? TicketPalette.surface : TicketPalette.paper)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? TicketPalette.accent : TicketPalette.border, lineWidth: isActive ? 1.5 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .focused($focusedField, equals: field)
    }

    private func labeledTextField(_ label: String, placeholder: String, text: Binding<String>, field: EditorField, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(label)
            styledTextField(placeholder, text: text, field: field, axis: axis)
        }
    }

    private func candidateField(_ label: String, text: Binding<String>, field: EditorField) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(label)
            HStack(spacing: 8) {
                styledTextField("请输入\(label)", text: text, field: field)
                candidateMenu { selected in
                    text.wrappedValue = selected
                }
            }
        }
    }

    private var candidateDateField: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("观影时间")
            HStack(spacing: 8) {
                DatePicker("观影时间", selection: $watchedAt)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TicketPalette.paper)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(TicketPalette.border, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                candidateMenu { selected in
                    if let date = parseCandidateDate(selected) {
                        watchedAt = date
                    } else {
                        message = "这条候选文本没有识别出明确日期，可以手动选择观影时间。"
                    }
                }
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TicketPalette.muted)
    }

    private func candidateMenu(onSelect: @escaping (String) -> Void) -> some View {
        Menu {
            if recognizedLines.isEmpty {
                Text("暂无 OCR 候选")
            } else {
                ForEach(recognizedLines, id: \.self) { line in
                    Button(line) {
                        onSelect(line)
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet.rectangle")
                .frame(width: 46, height: 46)
                .foregroundStyle(TicketPalette.ink)
                .background(TicketPalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(TicketPalette.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(recognizedLines.isEmpty)
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
        .background(TicketPalette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(TicketPalette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedPhotoItem = nil }
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
            let previousPaths = ticketImagePaths
            ticketImagePaths = [filename]
            newlyImportedTicketImagePaths.append(filename)
            pendingDeletedTicketImagePaths.append(contentsOf: previousPaths)
            showingTicketPreview = false
            isRecognizing = true
            defer { isRecognizing = false }

            let text = try await ocrService.recognizeText(in: image)
            recognizedLines = normalizedLines(from: text)
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

    private func deleteCurrentTicketImage() {
        pendingDeletedTicketImagePaths.append(contentsOf: ticketImagePaths)
        ticketImagePaths.removeAll()
        showingTicketPreview = false
        message = "已移除票根图片，保存后会从本机删除。"
    }

    private func normalizedLines(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                if seen.contains(line) { return false }
                seen.insert(line)
                return true
            }
    }

    private func parseCandidateDate(_ text: String) -> Date? {
        let normalized = text
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        let patterns = [
            #"20\d{2}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}"#,
            #"20\d{2}-\d{1,2}-\d{1,2}"#
        ]

        for pattern in patterns {
            guard let range = normalized.range(of: pattern, options: .regularExpression) else { continue }
            let raw = String(normalized[range])
            for format in ["yyyy-M-d H:mm", "yyyy-MM-dd H:mm", "yyyy-M-d", "yyyy-MM-dd"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = format
                if let date = formatter.date(from: raw) {
                    return date
                }
            }
        }
        return nil
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
        cleanupImagesAfterSave(keeping: Set(ticketImagePaths))
        dismiss()
    }

    private func cancelEditing() {
        for filename in Set(newlyImportedTicketImagePaths) {
            TicketImageStore.delete(filename)
        }
        dismiss()
    }

    private func cleanupImagesAfterSave(keeping keptFilenames: Set<String>) {
        let removable = Set(pendingDeletedTicketImagePaths + newlyImportedTicketImagePaths)
            .subtracting(keptFilenames)
        for filename in removable {
            TicketImageStore.delete(filename)
        }
    }
}

private struct TicketImagePreviewView: View {
    let filename: String
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                TicketPalette.dark.ignoresSafeArea()

                fullTicketImage
                    .padding(16)
            }
            .navigationTitle("票根图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("更换照片", systemImage: "photo")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            .alert("删除这张票根图片？", isPresented: $showingDeleteAlert) {
                Button("删除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后这张图片将不再保存在当前票根记录里。")
            }
        }
    }

    private var fullTicketImage: some View {
        Group {
            if let image = TicketImageStore.image(named: filename) ?? BundleImageStore.image(named: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                TicketPhotoView(filename: filename)
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}
