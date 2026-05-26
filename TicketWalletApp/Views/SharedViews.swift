import SwiftUI

struct TicketPalette {
    static let paper = Color(red: 0.96, green: 0.93, blue: 0.86)
    static let ink = Color(red: 0.13, green: 0.12, blue: 0.10)
    static let muted = Color(red: 0.45, green: 0.40, blue: 0.34)
    static let accent = Color(red: 0.62, green: 0.12, blue: 0.16)
    static let dark = Color(red: 0.08, green: 0.08, blue: 0.07)
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
                    TicketPalette.dark
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

extension Date {
    var ticketDateText: String {
        formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
    }
}
