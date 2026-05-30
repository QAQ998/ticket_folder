import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TicketWalletHomeView()
                .tabItem {
                    Label("首页", systemImage: "house")
                }

            CalendarPlaceholderView()
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }

            SettingsPlaceholderView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .tint(.black)
    }
}

private struct CalendarPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("日历")
                    .font(.system(size: 34, weight: .semibold))
                Text("之后会在这里按月份回看每一次观影。")
                    .font(.body)
                    .foregroundStyle(TicketPalette.muted)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TicketPalette.background)
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置")
                    .font(.system(size: 34, weight: .semibold))
                Text("之后会放置 iCloud 备份、隐私说明和资料来源配置。")
                    .font(.body)
                    .foregroundStyle(TicketPalette.muted)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TicketPalette.background)
        }
    }
}
