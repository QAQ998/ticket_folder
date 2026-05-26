import SwiftData
import SwiftUI

@main
struct TicketWalletApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: MovieRecord.self)
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TicketWalletHomeView()
        }
        .modelContainer(modelContainer)
    }
}
