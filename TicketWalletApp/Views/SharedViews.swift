import SwiftUI

struct TicketPalette {
    static let background = Color(red: 0.97, green: 0.965, blue: 0.945)
    static let surface = Color.white
    static let paper = Color(red: 1.0, green: 0.995, blue: 0.975)
    static let paperDeep = Color(red: 0.93, green: 0.915, blue: 0.875)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let muted = Color(red: 0.45, green: 0.43, blue: 0.40)
    static let accent = Color(red: 0.12, green: 0.18, blue: 0.24)
    static let secondaryAccent = Color(red: 0.52, green: 0.43, blue: 0.34)
    static let gold = Color(red: 0.70, green: 0.52, blue: 0.28)
    static let green = Color(red: 0.22, green: 0.34, blue: 0.29)
    static let dark = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let charcoal = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let border = Color.black.opacity(0.08)
}

struct TicketBackground: View {
    var body: some View {
        TicketPalette.background.ignoresSafeArea()
    }
}

struct AppPageHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(TicketPalette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(TicketPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TicketDashedDivider: View {
    var color: Color = TicketPalette.muted.opacity(0.35)

    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .foregroundStyle(color)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct TicketPill: View {
    let text: String
    var tint: Color = TicketPalette.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TicketPalette.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }
}

struct TicketSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(TicketPalette.ink)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TicketPalette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(TicketPalette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MovieMetadataSourceView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "film")
                .foregroundStyle(TicketPalette.muted)
            Text("电影资料用于辅助匹配，请以票根信息为准")
                .foregroundStyle(TicketPalette.muted)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

typealias TMDBAttributionView = MovieMetadataSourceView

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(configuration.isPressed ? TicketPalette.accent.opacity(0.82) : TicketPalette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(TicketPalette.ink)
            .background(configuration.isPressed ? TicketPalette.paperDeep : TicketPalette.paper)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TicketPalette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PosterView: View {
    let filename: String?

    var body: some View {
        Group {
            if let url = PosterCacheStore.localURL(for: filename),
               let image = UIImage(contentsOfFile: url.path()) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    TicketPalette.charcoal
                    Image(systemName: "film.stack")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .clipped()
    }
}

struct TicketPhotoView: View {
    let filename: String?

    var body: some View {
        Group {
            if let image = TicketImageStore.image(named: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let image = BundleImageStore.image(named: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    TicketPalette.paper
                    Image(systemName: "ticket")
                        .font(.title2)
                        .foregroundStyle(TicketPalette.muted)
                }
            }
        }
        .clipped()
    }
}

enum BundleImageStore {
    static func image(named filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else { return nil }
        return UIImage(contentsOfFile: url.path())
    }
}

struct RatingDots: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(index <= rating ? TicketPalette.accent : TicketPalette.muted.opacity(0.35))
            }
        }
        .accessibilityLabel("评分 \(rating) 星")
    }
}

struct RatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { index in
                Button {
                    rating = rating == index ? 0 : index
                } label: {
                    Image(systemName: index <= rating ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(index <= rating ? TicketPalette.gold : TicketPalette.muted.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(index) 星")
            }
            if rating > 0 {
                Button("清除") {
                    rating = 0
                }
                .font(.caption)
                .foregroundStyle(TicketPalette.muted)
            }
        }
    }
}

extension Date {
    var ticketDateText: String {
        formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
    }
}
