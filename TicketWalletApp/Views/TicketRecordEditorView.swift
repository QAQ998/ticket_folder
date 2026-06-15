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
    @State private var releaseDate: String
    @State private var runtime: Int?
    @State private var doubanRating: String
    @State private var tmdbRating: Double?
    @State private var tmdbId: Int?
    @State private var metadataSource: String
    @State private var metadataFetchedAt: Date?
    @State private var posterLocalPath: String?
    @State private var posterCachedAt: Date?

    @State private var watchedAt: Date
    @State private var hasRecognizedWatchedAt: Bool
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
    @State private var showingNonMovieTicketNotice = false
    @State private var showingNonMovieTicketAlert = false
    @State private var showingReplacementPhotoPicker = false
    @State private var isEditingRecognitionFields = false
    @State private var showingDiscardConfirmAlert = false
    @State private var isSaving = false
    @State private var recognizedLines: [String] = []
    @State private var pendingDeletedTicketImagePaths: [String] = []
    @State private var newlyImportedTicketImagePaths: [String] = []
    @FocusState private var focusedField: EditorField?

    private let ocrService = TicketOCRService()
    private let llmRecognitionService = TicketLLMRecognitionService()
    private let parsingService = TicketParsingService()
    private let metadataService = MovieMetadataService()

    init(record: MovieRecord? = nil, initialMovieMetadata: MovieMetadata? = nil) {
        self.record = record
        let resolvedMetadata = initialMovieMetadata
        _movieTitle = State(initialValue: record?.movieTitle ?? resolvedMetadata?.title ?? "")
        _originalTitle = State(initialValue: record?.originalTitle ?? resolvedMetadata?.originalTitle ?? "")
        _year = State(initialValue: record?.year ?? resolvedMetadata?.year ?? "")
        _director = State(initialValue: record?.director ?? resolvedMetadata?.director ?? "")
        _releaseDate = State(initialValue: record?.releaseDate ?? resolvedMetadata?.releaseDate ?? "")
        _runtime = State(initialValue: record?.runtimeMinutes ?? resolvedMetadata?.runtimeMinutes)
        _doubanRating = State(initialValue: record?.doubanRating ?? resolvedMetadata?.doubanRating ?? "")
        _tmdbRating = State(initialValue: record?.tmdbRating ?? resolvedMetadata?.tmdbRating)
        _tmdbId = State(initialValue: record?.tmdbId ?? resolvedMetadata?.tmdbId)
        _metadataSource = State(initialValue: record?.metadataSource ?? resolvedMetadata?.source ?? "manual")
        _metadataFetchedAt = State(initialValue: record?.metadataFetchedAt ?? (resolvedMetadata == nil ? nil : .now))
        _posterLocalPath = State(initialValue: record?.posterLocalPath ?? resolvedMetadata?.posterLocalPath)
        _posterCachedAt = State(initialValue: record?.posterCachedAt ?? (resolvedMetadata?.posterLocalPath == nil ? nil : .now))
        _watchedAt = State(initialValue: record?.watchedAt ?? .now)
        _hasRecognizedWatchedAt = State(initialValue: record != nil)
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
                            ticketPhotoInput
                        }

                        movieInfoSection

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
                        requestClose()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(movieTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    await importPhoto(item)
                }
            }
            .photosPicker(isPresented: $showingReplacementPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .fullScreenCover(isPresented: $showingTicketPreview) {
                if let first = ticketImagePaths.first {
                    TicketImagePreviewView(
                        filename: first,
                        selectedPhotoItem: $selectedPhotoItem,
                        onDelete: deleteCurrentTicketImage
                    )
                }
            }
            .alert(
                "确认删除当前内容",
                isPresented: $showingDiscardConfirmAlert,
            ) {
                Button("是", role: .destructive) {
                    discardEditingAndDismiss()
                }
                Button("否", role: .cancel) {}
            } message: {
                Text("删除后当前录入的信息不会保存。")
            }
            .alert("这可能不是一张电影票根", isPresented: $showingNonMovieTicketAlert) {
                Button("重新选择") {
                    showingReplacementPhotoPicker = true
                }
                Button("取消录入", role: .cancel) {
                    discardEditingAndDismiss()
                }
            } message: {
                Text("我没有找到足够的票根信息。请换一张包含影片、影院、时间和座位的照片试试。")
            }
            .interactiveDismissDisabled(shouldPromptForDiscard)
            .background(
                DismissAttemptHandler(isDisabled: shouldPromptForDiscard) {
                    requestClose()
                }
            )
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

    @ViewBuilder
    private var ticketPhotoInput: some View {
        ZStack {
            if let first = ticketImagePaths.first {
                Button {
                    showingTicketPreview = true
                } label: {
                    TicketPhotoView(filename: first)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    emptyTicketPreview
                }
                .buttonStyle(.plain)
            }

            if isRecognizing {
                recognitionOverlay
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var recognitionOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text(llmRecognitionService.isConfigured ? "正在分析票面文字和位置" : "正在识别票面文字")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial)
        .background(.black.opacity(0.18))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.26), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }

    private var movieMetadataPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterView(filename: posterLocalPath)
                .frame(width: 76, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            movieMetadataSummary
                .frame(height: 112, alignment: .top)
        }
        .padding(12)
        .background(TicketPalette.paper.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            metadataRefreshButton
                .padding(10)
        }
    }

    private var movieMetadataSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            compactMetadataRow("片名", movieTitle.isEmpty ? "待识别" : movieTitle, valueWeight: .semibold, lineLimit: 2)
            compactMetadataRow("上映", displayValue(releaseDate))
            compactMetadataRow("导演", displayValue(director))
            compactMetadataRow("片长", runtime.map { "\($0) 分钟" } ?? "暂无")
            compactMetadataRow("豆瓣", displayValue(doubanRating))
        }
        .font(.caption2)
        .padding(.trailing, 52)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func compactMetadataRow(
        _ label: String,
        _ value: String,
        valueWeight: Font.Weight = .medium,
        lineLimit: Int = 1
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .foregroundStyle(TicketPalette.muted)
                .frame(width: 30, alignment: .leading)
            Text(value)
                .fontWeight(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value == "暂无" || value == "待识别" ? .regular : valueWeight)
                .foregroundStyle(value == "暂无" || value == "待识别" ? TicketPalette.muted.opacity(0.75) : TicketPalette.ink)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metadataRefreshButton: some View {
        Button {
            Task {
                await fetchMovieMetadata()
            }
        } label: {
            Group {
                if isFetchingMovieMetadata {
                    ProgressView()
                } else {
                    Image(systemName: metadataSource == "tmdb" || metadataSource.contains("douban") ? "arrow.clockwise" : "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: 34, height: 30)
        }
        .foregroundStyle(TicketPalette.ink)
        .background(.ultraThinMaterial)
        .overlay {
            Capsule()
                .stroke(TicketPalette.border, lineWidth: 1)
        }
        .clipShape(Capsule())
        .disabled(movieTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFetchingMovieMetadata)
    }

    private var movieInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("影片信息", systemImage: "film")
                    .font(.headline)
                    .foregroundStyle(TicketPalette.ink)

                Spacer()

                Button {
                    let willFinishEditing = isEditingRecognitionFields
                    withAnimation(.snappy(duration: 0.18)) {
                        isEditingRecognitionFields.toggle()
                    }
                    if willFinishEditing {
                        focusedField = nil
                        Task {
                            await fetchMovieMetadata(quiet: true)
                        }
                    }
                } label: {
                    Label(isEditingRecognitionFields ? "完成" : "编辑", systemImage: isEditingRecognitionFields ? "checkmark" : "pencil")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                }
                .foregroundStyle(TicketPalette.ink)
                .background(TicketPalette.paper)
                .overlay {
                    Capsule()
                        .stroke(TicketPalette.border, lineWidth: 1)
                }
                .clipShape(Capsule())
            }

            movieMetadataPanel

            if isEditingRecognitionFields {
                candidateField("片名", text: $movieTitle, field: .movieTitle)
                candidateDateField
                candidateField("影院", text: $cinema, field: .cinema)
                candidateField("影厅", text: $hall, field: .hall)
                candidateField("座位号", text: $seat, field: .seat)
                candidateField("票价", text: $ticketPrice, field: .ticketPrice)
            } else {
                readOnlyMovieFields
            }
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

    private var readOnlyMovieFields: some View {
        VStack(spacing: 4) {
            readOnlyField("片名", value: movieTitle)
            readOnlyField("观影时间", value: hasRecognizedWatchedAt ? watchedAt.ticketDateText : "")
            readOnlyField("影院", value: cinema)
            readOnlyField("影厅", value: hall)
            readOnlyField("场次", value: hasRecognizedWatchedAt ? watchedAt.showtimeText : "")
            readOnlyField("座位号", value: seat)
            readOnlyField("票价", value: ticketPrice)
        }
    }

    private func readOnlyField(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TicketPalette.muted)
                .frame(width: 54, alignment: .leading)

            Text(displayValue(value))
                .font(.footnote.weight(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .regular : .semibold))
                .foregroundStyle(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? TicketPalette.muted.opacity(0.72) : TicketPalette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(TicketPalette.paper.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func displayValue(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "待识别" : text
    }

    private var nonMovieTicketNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TicketPalette.accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text("这可能不是一张电影票根")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TicketPalette.ink)
                    Text("我没有找到足够的票根信息。请换一张包含影片、影院、时间和座位的照片试试。")
                        .font(.footnote)
                        .foregroundStyle(TicketPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("重新选择", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(TicketPalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Button(role: .cancel) {
                    discardEditingAndDismiss()
                } label: {
                    Label("取消录入", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .foregroundStyle(TicketPalette.ink)
                .background(TicketPalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(TicketPalette.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TicketPalette.paper.opacity(0.88))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(TicketPalette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                DatePicker(
                    "观影时间",
                    selection: Binding(
                        get: { watchedAt },
                        set: { newValue in
                            watchedAt = newValue
                            hasRecognizedWatchedAt = true
                        }
                    )
                )
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
                        hasRecognizedWatchedAt = true
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
        showingNonMovieTicketNotice = false
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
            let previousPaths = ticketImagePaths
            showingTicketPreview = false
            isRecognizing = true
            defer { isRecognizing = false }

            let ocrResult: TicketOCRResult
            do {
                ocrResult = try await ocrService.recognize(in: image)
            } catch {
                throw error
            }

            if llmRecognitionService.isConfigured {
                do {
                    let result = try await llmRecognitionService.recognizeTicket(fromSpatialOCR: ocrResult)
                    guard result.isMovieTicket else {
                        ticketImagePaths = previousPaths
                        message = ""
                        showingNonMovieTicketNotice = true
                        showingNonMovieTicketAlert = true
                        return
                    }
                    resetRecognitionStateForNewTicket()
                    applyOCRText(ocrResult.rawText)
                    recognizedLines = mergedCandidateLines(result.candidateLines, normalizedLines(from: ocrResult.rawText))
                    applyLLMRecognition(result)
                    if ocrResult.isSparse, result.isEmpty {
                        message = "OCR 文本较少，大模型也没有识别出明确字段，可以手动修正。"
                    } else {
                        message = result.shouldRequestManualReview ? "已识别出部分票根信息，但置信度偏低，请重点核对。" : (result.isEmpty ? "大模型没有从票面文字和位置中识别出明确字段，可以点字段进行修正。" : "已用大模型按票面位置校对，请快速确认。")
                    }
                } catch {
                    resetRecognitionStateForNewTicket()
                    applyOCRText(ocrResult.rawText)
                    message = "大模型空间文本校对失败，已保留设备端 OCR 结果：\(error.localizedDescription)"
                }
            } else {
                resetRecognitionStateForNewTicket()
                applyOCRText(ocrResult.rawText)
                message = "未配置大模型 API Key，已使用设备端 OCR。"
            }

            let filename = try TicketImageStore.save(image)
            ticketImagePaths = [filename]
            newlyImportedTicketImagePaths.append(filename)
            pendingDeletedTicketImagePaths.append(contentsOf: previousPaths)

            isRecognizing = false
            if !movieTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await fetchMovieMetadata(quiet: true)
            }
        } catch {
            isRecognizing = false
            message = error.localizedDescription
        }
    }

    private func resetRecognitionStateForNewTicket() {
        movieTitle = ""
        originalTitle = ""
        year = ""
        director = ""
        releaseDate = ""
        runtime = nil
        doubanRating = ""
        tmdbRating = nil
        tmdbId = nil
        metadataSource = "manual"
        metadataFetchedAt = nil
        posterLocalPath = nil
        posterCachedAt = nil
        hasRecognizedWatchedAt = false
        cinema = ""
        hall = ""
        seat = ""
        ticketPrice = ""
        recognizedLines = []
        message = ""
        showingNonMovieTicketNotice = false
        showingNonMovieTicketAlert = false
        isEditingRecognitionFields = false
    }

    private func applyLLMRecognition(_ result: TicketLLMRecognitionResult) {
        if !result.movieTitle.isEmpty { movieTitle = result.movieTitle }
        if !result.originalTitle.isEmpty { originalTitle = result.originalTitle }
        if !result.year.isEmpty { year = result.year }
        if !result.director.isEmpty { director = result.director }
        if result.watchedAt != nil {
            watchedAt = result.watchedAt!
            hasRecognizedWatchedAt = true
        }
        if !result.cinema.isEmpty { cinema = result.cinema }
        if !result.hall.isEmpty { hall = result.hall }
        if !result.seat.isEmpty { seat = result.seat }
        if !result.ticketPrice.isEmpty { ticketPrice = result.ticketPrice }
        if metadataSource != "tmdb", !result.movieTitle.isEmpty || !result.year.isEmpty || !result.director.isEmpty {
            metadataSource = "llm"
            metadataFetchedAt = .now
        }
    }

    private func applyOCRText(_ text: String) {
        recognizedLines = normalizedLines(from: text)
        let draft = parsingService.parse(text)
        if !draft.movieTitle.isEmpty { movieTitle = draft.movieTitle }
        if let parsedDate = parseCandidateDate(text) {
            watchedAt = parsedDate
            hasRecognizedWatchedAt = true
        }
        if !draft.cinema.isEmpty { cinema = draft.cinema }
        if !draft.hall.isEmpty { hall = draft.hall }
        if !draft.seat.isEmpty { seat = draft.seat }
        if !draft.ticketPrice.isEmpty { ticketPrice = draft.ticketPrice }
        message = draft.isEmpty ? "没有识别出明确字段，可以点字段进行修正。" : "已识别票面信息，请快速确认。"
    }

    private func fetchMovieMetadata(quiet: Bool = false) async {
        let queries = movieMetadataQueries()
        guard !queries.isEmpty else { return }
        guard metadataService.isConfigured else {
            if !quiet {
                message = MovieMetadataError.missingProvider.localizedDescription
            }
            return
        }

        isFetchingMovieMetadata = true
        defer { isFetchingMovieMetadata = false }

        do {
            let metadata = try await metadataService.metadata(for: queries)
            applyMovieMetadata(metadata)
            if !quiet {
                message = metadata.hasRequiredMovieInfo ? "已自动补全影片信息。" : "已获取部分影片信息，还缺少豆瓣评分等字段。"
            }
        } catch {
            if !quiet {
                message = error.localizedDescription
            }
        }
    }

    private func movieMetadataQueries() -> [String] {
        var seen = Set<String>()
        let candidates = [movieTitle] + recognizedLines
        return candidates
            .map(cleanedMovieTitle)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter(isLikelyMovieMetadataQuery)
            .filter { candidate in
                if seen.contains(candidate) { return false }
                seen.insert(candidate)
                return true
            }
            .prefix(5)
            .map { $0 }
    }

    private func isLikelyMovieMetadataQuery(_ text: String) -> Bool {
        guard text.count >= 2, text.count <= 24 else { return false }
        guard text.range(of: #"\p{Han}"#, options: .regularExpression) != nil else { return false }
        let noisePatterns = [
            #"\d{4}[-/.年]\d{1,2}"#,
            #"\d{1,2}[:：]\d{2}"#,
            #"\d+排.*座"#,
            #"\d{3,}"#
        ]
        if noisePatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            return false
        }
        let noiseWords = [
            "影院", "影城", "影厅", "Cinema", "Galaxy", "座位", "票价", "服务费",
            "手续费", "取票", "售票", "票号", "工号", "副券", "扫码", "HALL",
            "TIME", "SEAT", "PRICE", "SERVICE", "CHARGE", "KIOSK"
        ]
        return !noiseWords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func applyMovieMetadata(_ metadata: MovieMetadata) {
        movieTitle = metadata.title
        originalTitle = metadata.originalTitle
        year = metadata.year
        director = metadata.director
        releaseDate = metadata.releaseDate
        runtime = metadata.runtimeMinutes
        doubanRating = metadata.doubanRating
        tmdbRating = metadata.tmdbRating
        tmdbId = metadata.tmdbId
        metadataSource = metadata.source
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

    private func mergedCandidateLines(_ groups: [String]...) -> [String] {
        var seen = Set<String>()
        return groups
            .flatMap { $0 }
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

    private func save() async {
        guard !showingNonMovieTicketNotice else {
            showingNonMovieTicketAlert = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        await ensureRequiredMovieMetadata()
        guard hasRequiredMovieMetadata else {
            message = missingMovieMetadataMessage
            return
        }

        let target = record ?? MovieRecord()
        applyCurrentState(to: target)

        if record == nil {
            modelContext.insert(target)
        }
        try? modelContext.save()
        cleanupImagesAfterSave(keeping: Set(ticketImagePaths))
        dismiss()
    }

    private var hasRequiredMovieMetadata: Bool {
        !movieTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !releaseDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !director.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            runtime != nil &&
            !doubanRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var missingMovieMetadataMessage: String {
        let missing = [
            releaseDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "上映时间" : nil,
            director.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "导演" : nil,
            runtime == nil ? "片长" : nil,
            doubanRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "豆瓣评分" : nil
        ].compactMap { $0 }

        if !metadataService.isDoubanConfigured, missing.contains("豆瓣评分") {
            return "影片信息还缺少\(missing.joined(separator: "、"))。豆瓣评分需要配置豆瓣资料代理后自动获取，不能手动编造。"
        }
        return "影片信息还缺少\(missing.joined(separator: "、"))。我会优先从豆瓣自动补全，补全后才能保存。"
    }

    private func ensureRequiredMovieMetadata() async {
        guard !hasRequiredMovieMetadata else { return }
        await fetchMovieMetadata(quiet: true)
    }

    private var shouldPromptForDiscard: Bool {
        guard record != nil else { return hasDiscardableContent }
        return hasUnsavedChanges
    }

    private var hasDiscardableContent: Bool {
        !ticketImagePaths.isEmpty ||
            !movieTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !cinema.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !hall.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !seat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !ticketPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            rating > 0 ||
            hasRecognizedWatchedAt
    }

    private var hasUnsavedChanges: Bool {
        guard let record else { return hasDiscardableContent }
        return cleanedMovieTitle(movieTitle) != record.movieTitle ||
            originalTitle != record.originalTitle ||
            year != record.year ||
            director != record.director ||
            releaseDate != record.releaseDate ||
            runtime != record.runtimeMinutes ||
            doubanRating != record.doubanRating ||
            tmdbRating != record.tmdbRating ||
            tmdbId != record.tmdbId ||
            metadataSource != record.metadataSource ||
            posterLocalPath != record.posterLocalPath ||
            watchedAt != record.watchedAt ||
            cinema != record.cinema ||
            hall != record.hall ||
            seat != record.seat ||
            ticketPrice != record.ticketPrice ||
            ticketImagePaths != record.ticketImagePaths ||
            rating != record.rating ||
            note != record.note
    }

    private func requestClose() {
        if shouldPromptForDiscard {
            showingDiscardConfirmAlert = true
        } else {
            discardEditingAndDismiss()
        }
    }

    private func applyCurrentState(to target: MovieRecord) {
        target.movieTitle = cleanedMovieTitle(movieTitle)
        target.originalTitle = originalTitle
        target.year = year
        target.director = director
        target.releaseDate = releaseDate
        target.runtimeMinutes = runtime
        target.doubanRating = doubanRating
        target.tmdbRating = tmdbRating
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
        target.isDraft = false
        target.updatedAt = .now
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

    private func discardEditingAndDismiss() {
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

private struct DismissAttemptHandler: UIViewControllerRepresentable {
    let isDisabled: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.isDisabled = isDisabled
        context.coordinator.onAttempt = onAttempt

        DispatchQueue.main.async {
            uiViewController.parent?.presentationController?.delegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isDisabled: isDisabled, onAttempt: onAttempt)
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isDisabled: Bool
        var onAttempt: () -> Void

        init(isDisabled: Bool, onAttempt: @escaping () -> Void) {
            self.isDisabled = isDisabled
            self.onAttempt = onAttempt
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !isDisabled
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if isDisabled {
                onAttempt()
            }
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
                .padding(.horizontal, 16)
                .padding(.top, 86)
                .padding(.bottom, 112)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 0) {
                previewHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
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

    private var previewHeader: some View {
        HStack {
            LiquidGlassIconButton(
                systemImage: "xmark",
                accessibilityLabel: "关闭",
                foreground: .white
            ) {
                dismiss()
            }

            Spacer()

            Text("票根图片")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(.ultraThinMaterial)
                .background(.black.opacity(0.08))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    private var previewActions: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                LiquidGlassActionLabel(title: "更换照片", systemImage: "photo")
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                LiquidGlassActionLabel(title: "删除", systemImage: "trash", fill: Color.red.opacity(0.28))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
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
