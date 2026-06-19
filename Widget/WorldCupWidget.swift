import WidgetKit
import SwiftUI

struct WCEntry: TimelineEntry {
    let date: Date
    let snapshot: WorldCupSnapshot
    var rotation: Int = 0   // 小号轮播索引
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WCEntry {
        WCEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WCEntry) -> Void) {
        if context.isPreview {
            completion(WCEntry(date: Date(), snapshot: .sample))
            return
        }
        Task {
            let snapshot = await WorldCupAPI.fetchSnapshot()
            completion(WCEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WCEntry>) -> Void) {
        Task {
            let snapshot = await WorldCupAPI.fetchSnapshot()
            let now = Date()

            // 自适应刷新：进行中→3分钟（追比分）；否则→30分钟，
            // 但若有即将开赛的比赛更早开球，则在其开球后约30秒刷新（待赛→进行中）。
            let hasLive = !snapshot.live.isEmpty
            var span: TimeInterval = hasLive ? 3 * 60 : 30 * 60
            if !hasLive, let kickoff = snapshot.upcoming.first?.date {
                let untilKickoff = kickoff.timeIntervalSince(now)
                if untilKickoff > 60, untilKickoff + 30 < span {
                    span = untilKickoff + 30
                }
            }

            // 小号轮播：每 15 秒切一张，循环到下次刷新
            let count = max(1, snapshot.smallFeatured.count)
            let step: TimeInterval = 15
            var entries: [WCEntry] = []
            var i = 0
            while Double(i) * step < span {
                entries.append(WCEntry(date: now.addingTimeInterval(Double(i) * step),
                                       snapshot: snapshot, rotation: i % count))
                i += 1
            }
            if entries.isEmpty { entries = [WCEntry(date: now, snapshot: snapshot)] }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(span))))
        }
    }
}

struct WorldCupWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WCEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(snapshot: entry.snapshot, rotation: entry.rotation)
        case .systemLarge, .systemExtraLarge:
            LargeView(snapshot: entry.snapshot)
        default:
            MediumView(snapshot: entry.snapshot)
        }
    }
}

struct WorldCupWidget: Widget {
    let kind = "WorldCupWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WorldCupWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.11, blue: 0.16),
                                 Color(red: 0.05, green: 0.06, blue: 0.09)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("2026世界杯摸鱼看球小组件")
        .description("在 Mac 桌面悄悄查看 2026 世界杯实时比分、已完赛和即将开赛的比赛。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
