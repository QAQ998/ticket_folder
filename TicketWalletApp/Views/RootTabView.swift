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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppPageHeader("日历", subtitle: "按月份回看每一次走进影院的时间。")

                    VStack(spacing: 12) {
                        CalendarSummaryCard(title: "本月观影", value: "0", detail: "还没有记录")
                        CalendarSummaryCard(title: "最近一次", value: "未开始", detail: "录入票根后会显示最近观影")
                        CalendarSummaryCard(title: "即将支持", value: "月历视图", detail: "按日期展示观影记录和票根")
                    }

                    TicketSectionCard(title: "计划中的日历能力", systemImage: "calendar.badge.clock") {
                        Text("按月查看观影记录、快速跳转到某一天、标记开场前已记录但未观影的票根。")
                            .foregroundStyle(TicketPalette.muted)
                            .font(.subheadline)
                    }
                }
                .padding(24)
            }
            .background(TicketPalette.background)
        }
    }
}

private struct SettingsPlaceholderView: View {
    private let tmdbClient = TMDBClient()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppPageHeader("设置", subtitle: "管理备份、隐私和电影资料来源。")

                    TicketSectionCard(title: "数据与备份", systemImage: "icloud") {
                        SettingsRow(title: "iCloud 备份", value: "规划中")
                        SettingsRow(title: "本机存储", value: "已启用")
                    }

                    TicketSectionCard(title: "隐私", systemImage: "lock.shield") {
                        SettingsRow(title: "设备端 OCR", value: "已启用")
                        SettingsRow(title: "上传票根到服务器", value: "不会")
                    }

                    TicketSectionCard(title: "电影资料", systemImage: "film") {
                        SettingsRow(title: "资料来源", value: "TMDB")
                        SettingsRow(title: "API Key", value: tmdbClient.isConfigured ? "已配置" : "未配置")
                        TMDBAttributionView()
                    }
                }
                .padding(24)
            }
            .background(TicketPalette.background)
        }
    }
}

private struct CalendarSummaryCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(TicketPalette.muted)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(TicketPalette.ink)
            Text(detail)
                .font(.caption)
                .foregroundStyle(TicketPalette.muted)
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

private struct SettingsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(TicketPalette.ink)
            Spacer()
            Text(value)
                .foregroundStyle(TicketPalette.muted)
        }
        .font(.subheadline)
    }
}
