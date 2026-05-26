import Foundation
import SwiftData

@Model
final class MovieRecord {
    var id: UUID
    var movieTitle: String
    var originalTitle: String
    var year: String
    var director: String
    var tmdbId: Int?
    var metadataSource: String
    var metadataFetchedAt: Date?
    var posterLocalPath: String?
    var posterCachedAt: Date?

    var watchedAt: Date
    var cinema: String
    var hall: String
    var seat: String
    var ticketPrice: String
    var ticketImagePaths: [String]

    var rating: Int
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        movieTitle: String = "",
        originalTitle: String = "",
        year: String = "",
        director: String = "",
        tmdbId: Int? = nil,
        metadataSource: String = "manual",
        metadataFetchedAt: Date? = nil,
        posterLocalPath: String? = nil,
        posterCachedAt: Date? = nil,
        watchedAt: Date = .now,
        cinema: String = "",
        hall: String = "",
        seat: String = "",
        ticketPrice: String = "",
        ticketImagePaths: [String] = [],
        rating: Int = 0,
        note: String = ""
    ) {
        self.id = UUID()
        self.movieTitle = movieTitle
        self.originalTitle = originalTitle
        self.year = year
        self.director = director
        self.tmdbId = tmdbId
        self.metadataSource = metadataSource
        self.metadataFetchedAt = metadataFetchedAt
        self.posterLocalPath = posterLocalPath
        self.posterCachedAt = posterCachedAt
        self.watchedAt = watchedAt
        self.cinema = cinema
        self.hall = hall
        self.seat = seat
        self.ticketPrice = ticketPrice
        self.ticketImagePaths = ticketImagePaths
        self.rating = rating
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }
}

struct TicketDraft {
    var movieTitle = ""
    var watchedAt = Date()
    var cinema = ""
    var hall = ""
    var seat = ""
    var ticketPrice = ""

    var isEmpty: Bool {
        movieTitle.isEmpty && cinema.isEmpty && hall.isEmpty && seat.isEmpty && ticketPrice.isEmpty
    }
}
