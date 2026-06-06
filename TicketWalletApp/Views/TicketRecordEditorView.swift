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
    @State private var isRecognizing = false
    @State private var isFetchingMovieMetadata = false
    @State private var message = ""
    @State private var recognizedLines: [String] = []
    @State private var movieTitleCandidates: [String] = []
    @State private var pendingDeletedTicketImagePaths: [String] = []
    @State private var newlyImportedTicketImagePaths: [String] = []
    @FocusState private var focusedField: EditorField?

    private let ocrService = TicketOCRService()
    private let parsingService = TicketParsingService()
    private let tmdbClient = TMDBClient()

    init(record: MovieRecord? = nil, initialMetadata: TMDBMovieMetadata? = nil) {
        self.record = record
        _movieTitle = State(initialValue: record?.movieTitle ?? initialMetadata?.details.title ?? "")
        _originalTitle = State(initialValue: record?.originalTitle ?? initialMetadata?.details.originalTitle ?? "")
        _year = State(initialValue: record?.year ?? initialMetadata?.details.year ?? "")
        _director = State(initialValue: record?.director ?? initialMetadata?.director ?? "")
        _tmdbId = State(initialValue: record?.tmdbId ?? initialMetadata?.details.id)
        _metadataSource = State(initialValue: record?.metadataSource ?? (initialMetadata == nil ? "manual" : "movieMetadata"))
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
                                            Label("点按预览", systemImage: "arrow.up.left.and.arrow.down.right")
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
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    emptyTicketPreview
                                }
                                .buttonStyle(.plain)
                            }

                            if isRecognizing {
                                ProgressView("正在识别票面文字")
                                    .foregroundStyle(TicketPalette.muted)
                            }
                        }

                        editorSection("影片信息", systemImage: "film") {
                            movieMetadataPanel
                            candidateField("电影名", text: $movieTitle, field: .movieTitle)
                            candidateDateField
                            candidateField("影院", text: $cinema, field: .cinema)
                            candidateField("影厅", text: $hall, field: .hall)
                            candidateField("座位", text: $seat, field: .seat)
                            candidateField("票价", text: $ticketPrice, field: .ticketPrice)
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
        }
    }

    private var emptyTicketPreview: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(TicketPalette.accent)
            Text("添加您的纸质票根或电子票根")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TicketPalette.ink)
            Text("清晰且完整的票根能更好的智能识别影片信息")
                .font(.caption)
                .foregroundStyle(TicketPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .background(TicketPalette.paperDeep.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(TicketPalette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var movieMetadataPanel: some View {
        HStack(spacing: 12) {
            PosterView(filename: posterLocalPath)
                .frame(width: 64, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 6) {
                Text(movieTitle.isEmpty ? "识别电影名后获取资料" : movieTitle)
                    .font(.headline)
                    .foregroundStyle(TicketPalette.ink)
                    .lineLimit(2)
                Text(metadataSummary)
                    .font(.caption)
                    .foregroundStyle(TicketPalette.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    await fetchMovieMetadata()
                }
            } label: {
                if isFetchingMovieMetadata {
                    ProgressView()
                        .frame(width: 46, height: 34)
                } else {
                    Text(metadataSource == "manual" ? "获取" : "更新")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 46, height: 34)
                }
            }
            .foregroundStyle(TicketPalette.ink)
            .background(TicketPalette.paper)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TicketPalette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(movieTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFetchingMovieMetadata)
        }
        .padding(12)
        .background(TicketPalette.paper.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var metadataSummary: String {
        let parts = [year, director].filter { !$0.isEmpty }
        return parts.isEmpty ? "海报、年份、导演可从电影资料源获取" : parts.joined(separator: " · ")
    }

    private func styledTextField(_ placeholder: String, text: Binding<String>, field: EditorField, axis: Axis = .horizontal) -> some View {
        let isActive = focusedField == field
        return TextField(placeholder, text: text, axis: axis)
            .foregroundStyle(TicketPalette.ink)
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
                    text.wrappedValue = field == .movieTitle ? cleanedMovieTitle(selected) : selected
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
                    .tint(TicketPalette.ink)
                    .foregroundStyle(TicketPalette.ink)
                    .environment(\.colorScheme, .light)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TicketPalette.surface)
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
            Image(systemName: "chevron.down")
                .font(.subheadline.weight(.semibold))
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
            movieTitleCandidates = parsingService.titleCandidates(from: recognizedLines)
            let draft = parsingService.parse(text)
            if !draft.movieTitle.isEmpty { movieTitle = draft.movieTitle }
            watchedAt = draft.watchedAt
            if !draft.cinema.isEmpty { cinema = draft.cinema }
            if !draft.hall.isEmpty { hall = draft.hall }
            if !draft.seat.isEmpty { seat = draft.seat }
            if !draft.ticketPrice.isEmpty { ticketPrice = draft.ticketPrice }
            message = draft.isEmpty ? "没有识别出明确字段，可以点字段进行修正。" : "已识别票面信息，请快速确认。"
            isRecognizing = false
            if !metadataTitleQueries().isEmpty,
               metadataSource == "manual" {
                await fetchMovieMetadata(quiet: true)
            }
        } catch {
            isRecognizing = false
            message = error.localizedDescription
        }
    }

    private func fetchMovieMetadata(quiet: Bool = false) async {
        let queries = metadataTitleQueries()
        guard !queries.isEmpty else { return }
        guard tmdbClient.isConfigured else {
            if !quiet {
                message = TMDBError.missingAPIKey.localizedDescription
            }
            return
        }

        isFetchingMovieMetadata = true
        defer { isFetchingMovieMetadata = false }

        var lastError: Error?
        var triedQueries: [String] = []

        for query in queries {
            triedQueries.append(query)
            do {
                guard let first = try await tmdbClient.searchMovies(query: query).first else {
                    continue
                }
                let usedFallbackTitle = query != cleanedMovieTitle(movieTitle)
                let shouldUseMatchedTitle = query != cleanedMovieTitle(movieTitle)
                    || parsingService.titleCandidates(from: [movieTitle]).isEmpty
                let metadata = try await tmdbClient.metadata(for: first.id)
                applyMovieMetadata(metadata, matchedTitle: query, shouldUseMatchedTitle: shouldUseMatchedTitle)
                if !quiet {
                    message = usedFallbackTitle ? "已根据候选片名「\(query)」获取电影资料。" : "已获取电影资料。"
                }
                return
            } catch {
                lastError = error
                if case TMDBError.networkUnavailable = error {
                    break
                }
            }
        }

        if let lastError {
            if !quiet {
                message = lastError.localizedDescription
            }
        } else if !quiet {
            message = triedQueries.count > 1 ? "这些候选片名都没有找到匹配资料，可以手动修正片名后再试。" : "没有找到匹配的电影资料，可以手动修正片名后再试。"
        } else if triedQueries.count > 1 {
            message = "未能自动匹配电影资料，请检查片名。"
        }
    }

    private func metadataTitleQueries() -> [String] {
        var seen = Set<String>()
        let currentCandidates = parsingService.titleCandidates(from: [movieTitle])
        let candidates = currentCandidates + movieTitleCandidates

        return candidates
            .map(cleanedMovieTitle)
            .filter { !$0.isEmpty }
            .filter { candidate in
                if seen.contains(candidate) { return false }
                seen.insert(candidate)
                return true
            }
    }

    private func applyMovieMetadata(
        _ metadata: TMDBMovieMetadata,
        matchedTitle: String,
        shouldUseMatchedTitle: Bool
    ) {
        let details = metadata.details
        if shouldUseMatchedTitle {
            movieTitle = matchedTitle
        }
        originalTitle = details.originalTitle ?? details.title
        year = details.year
        director = metadata.director
        tmdbId = details.id
        metadataSource = "movieMetadata"
        metadataFetchedAt = .now
        if let cachedPoster = metadata.posterLocalPath {
            PosterCacheStore.delete(posterLocalPath)
            posterLocalPath = cachedPoster
            posterCachedAt = .now
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
        target.movieTitle = cleanedMovieTitle(movieTitle)
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

    private func cleanedMovieTitle(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"\s*[（(][^）)]*(英文|英语|中文|国语|原版|中字|字幕|2D|3D|4D|IMAX|CINITY|中国巨幕|杜比|激光)[^）)]*[）)]\s*$"#,
            #"\s*(中文|国语|原版|英语|英文)?\s*[234]D\s*$"#,
            #"\s*(IMAX|CINITY|中国巨幕|杜比全景声|杜比|激光|原版|国语|中字|中文字幕)\s*$"#
        ]

        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        ZStack {
            TicketPalette.dark.ignoresSafeArea()

            fullTicketImage
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            VStack {
                previewTopActions
                Spacer()
                previewActions
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

    private var previewTopActions: some View {
        HStack {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .foregroundStyle(.white)
                    .background(Color.red.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("关闭")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .foregroundStyle(TicketPalette.ink)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    private var previewActions: some View {
        HStack {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("更换照片", systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
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
