import SwiftUI
import AppKit
import WidgetKit

// 菜单栏常驻：前台运行，自己用定时循环刷新（进行中 30s / 否则 180s），不受 WidgetKit 预算限制。
@MainActor
final class ScoreStore: ObservableObject {
    @Published var snapshot = WorldCupSnapshot(live: [], results: [], upcoming: [], updated: Date())
    @Published var lastUpdated = Date()
    @Published var loading = true
    private var started = false

    func startIfNeeded() {
        guard !started else { return }
        started = true
        Task { @MainActor in
            while !Task.isCancelled {
                await refresh()
                let secs: UInt64 = snapshot.live.isEmpty ? 180 : 30
                try? await Task.sleep(nanoseconds: secs * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        loading = true
        snapshot = await WorldCupAPI.fetchSnapshot()
        lastUpdated = Date()
        loading = false
        WidgetCenter.shared.reloadAllTimelines()   // 同步刷新桌面小组件
    }
}

@main
struct WorldCupApp: App {
    @StateObject private var store = ScoreStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

// 菜单栏上的紧凑标签：进行中→红点+比分；否则→下一场开球时间；都没有→奖杯
struct MenuBarLabel: View {
    @ObservedObject var store: ScoreStore
    var body: some View {
        Group {
            if let m = store.snapshot.live.first {
                Text("进行中 \(flag(m.home))\(m.homeScore ?? 0)-\(m.awayScore ?? 0)\(flag(m.away))")
            } else if let m = store.snapshot.results.last {
                Text("已完赛 \(flag(m.home))\(m.homeScore ?? 0)-\(m.awayScore ?? 0)\(flag(m.away))")
            } else if let m = store.snapshot.upcoming.first {
                Text("下一场 \(flag(m.home)) \(WCFormat.dayTime(m.date)) \(flag(m.away))")
            } else {
                Text("🏆 休赛日")
            }
        }
        .onAppear { store.startIfNeeded() }
    }
    private func flag(_ n: String) -> String { Teams.info(n).flag }
}

// 下拉面板：完整赛况列表
struct MenuContentView: View {
    @ObservedObject var store: ScoreStore

    var body: some View {
        let s = store.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🏆 2026世界杯摸鱼看球").font(.headline)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("立即刷新")
            }
            Text("更新于 \(WCFormat.clock(store.lastUpdated))")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("正在进行", s.live, color: .red, upcoming: false)
                    section("已完赛", s.results, color: .green, upcoming: false)
                    section("即将开赛", s.upcoming, color: .orange, upcoming: true)
                    if s.live.isEmpty && s.results.isEmpty && s.upcoming.isEmpty {
                        Text("暂无比赛").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 380)

            Divider()
            HStack {
                Text("进行中每30秒刷新 · 其它3分钟").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    @ViewBuilder
    private func section(_ title: String, _ matches: [Match], color: Color, upcoming: Bool) -> some View {
        if !matches.isEmpty {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.subheadline).bold().foregroundStyle(.secondary)
            }
            ForEach(matches) { m in row(m, upcoming: upcoming) }
        }
    }

    private func row(_ m: Match, upcoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(Teams.info(m.home).flag)
                Text(Teams.info(m.home).zh).lineLimit(1)
                Spacer(minLength: 6)
                Text(upcoming ? WCFormat.clock(m.date) : "\(m.homeScore ?? 0) : \(m.awayScore ?? 0)")
                    .bold().monospacedDigit()
                    .foregroundStyle(upcoming ? Color.orange : Color.primary)
                Spacer(minLength: 6)
                Text(Teams.info(m.away).zh).lineLimit(1)
                Text(Teams.info(m.away).flag)
            }
            .font(.callout)
            Text(WCFormat.metaTime(m)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}
