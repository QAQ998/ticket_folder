import SwiftUI

struct TicketPalette {
    static let paper = Color(red: 0.96, green: 0.92, blue: 0.82)
    static let paperDeep = Color(red: 0.89, green: 0.83, blue: 0.70)
    static let ink = Color(red: 0.15, green: 0.13, blue: 0.10)
    static let muted = Color(red: 0.49, green: 0.42, blue: 0.34)
    static let accent = Color(red: 0.60, green: 0.10, blue: 0.13)
    static let gold = Color(red: 0.78, green: 0.56, blue: 0.26)
    static let green = Color(red: 0.18, green: 0.38, blue: 0.31)
    static let dark = Color(red: 0.07, green: 0.07, blue: 0.06)
    static let charcoal = Color(red: 0.13, green: 0.12, blue: 0.10)
}

struct TicketBackground: View {
    var body: some View {
        LinearGradient(
            colors: [TicketPalette.dark, TicketPalette.charcoal, Color(red: 0.18, green: 0.14, blue: 0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
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
            .foregroundStyle(tint)
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
