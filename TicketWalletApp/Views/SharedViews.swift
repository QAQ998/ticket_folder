import SwiftUI

struct TicketPalette {
    static let background = Color(red: 0.965, green: 0.965, blue: 0.97)
    static let surface = Color.white
    static let paper = Color.white
    static let paperDeep = Color(red: 0.93, green: 0.93, blue: 0.94)
    static let ink = Color.black
    static let muted = Color(red: 0.43, green: 0.43, blue: 0.46)
    static let accent = Color.black
    static let gold = Color.black
    static let green = Color.black
    static let dark = Color.black
    static let charcoal = Color(red: 0.08, green: 0.08, blue: 0.09)
}

struct TicketBackground: View {
    var body: some View {
        TicketPalette.background.ignoresSafeArea()
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
            .background(Color.black.opacity(0.06))
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
        .background(TicketPalette.paper.opacity(0.94))
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
