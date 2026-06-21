import WidgetKit
import SwiftUI
import AppIntents

// 手动刷新按钮的 AppIntent：拉取最新数据并写入缓存，系统随后重载小组件。
struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新比分"
    func perform() async throws -> some IntentResult {
        _ = await WorldCupAPI.fetchSnapshot()   // 拉最新并写入缓存
        WidgetCenter.shared.reloadAllTimelines() // 强制重绘小组件
        return .result()
    }
}

struct WCEntry: TimelineEntry {
    let date: Date
    let snapshot: WorldCupSnapshot
    var rotation: Int = 0   // 小卡无进行中时的轮播索引
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
            // 菜单栏刷新后会要求 WidgetKit 重载时间线。这里只复用 5 秒内的缓存
            // （供小组件自身的刷新按钮衔接），其余情况重新联网，避免卡片停留在旧比分。
            let snapshot: WorldCupSnapshot
            if let cached = SharedStore.readFresh(maxAge: 5) {
                snapshot = cached
            } else {
                snapshot = await WorldCupAPI.fetchSnapshot()
            }
            let now = Date()

            // 自适应刷新：进行中→1分钟（菜单栏也会在取到新数据后主动触发重载）；
            // 否则→30分钟，
            // 但若有即将开赛的比赛更早开球，则在其开球后约30秒刷新（待赛→进行中）。
            let hasLive = !snapshot.live.isEmpty
            var span: TimeInterval = hasLive ? 60 : 30 * 60
            if !hasLive, let kickoff = snapshot.upcoming.first?.date {
                let untilKickoff = kickoff.timeIntervalSince(now)
                if untilKickoff > 60, untilKickoff + 30 < span {
                    span = untilKickoff + 30
                }
            }

            // 有进行中：单帧（小卡只显示进行中，不轮播）；否则：小卡轮播（每 15 秒一张）
            if snapshot.live.isEmpty {
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
            } else {
                completion(Timeline(entries: [WCEntry(date: now, snapshot: snapshot)],
                                    policy: .after(now.addingTimeInterval(span))))
            }
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
