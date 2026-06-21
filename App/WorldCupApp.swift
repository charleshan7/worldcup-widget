import SwiftUI
import AppKit
import WidgetKit
import ServiceManagement

// 菜单栏常驻：前台运行，自己用定时循环刷新（进行中 30s / 否则 180s），不受 WidgetKit 预算限制。
@MainActor
final class ScoreStore: ObservableObject {
    @Published var snapshot = WorldCupSnapshot(live: [], results: [], upcoming: [], updated: Date())
    @Published var lastUpdated = Date()
    @Published var loading = true
    @Published var launchAtLogin = false
    private var started = false
    private var activity: NSObjectProtocol?

    func startIfNeeded() {
        guard !started else { return }
        started = true
        // 防 App Nap：闲置时也不被系统挂起，保证轮询不中断（仍允许系统正常息屏睡眠）
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "世界杯实时比分刷新")
        // 首次启动开启「开机自启」；之后尊重用户在面板里的开关
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        Task { @MainActor in
            while !Task.isCancelled {
                await refresh()
                // 按需轮询：进行中 30s；临近开球(2h 内) 120s；其余 600s
                let secs: UInt64
                if !snapshot.live.isEmpty {
                    secs = 30
                } else if let next = snapshot.upcoming.first?.date, next.timeIntervalSinceNow < 2 * 3600 {
                    secs = 120
                } else {
                    secs = 600
                }
                try? await Task.sleep(nanoseconds: secs * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        loading = true
        snapshot = await WorldCupAPI.fetchSnapshot()
        lastUpdated = Date()
        loading = false
        // 指定刷新世界杯组件。组件 Provider 会重新联网取数，不再复用分钟级旧缓存。
        WidgetCenter.shared.reloadTimelines(ofKind: "WorldCupWidget")
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
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
                Text("\(WCFormat.progressLabel(m) ?? WCFormat.clock(m.date)) \(flag(m.home))\(m.homeScore ?? 0)-\(m.awayScore ?? 0)\(flag(m.away))")
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
        let matchCount = s.live.count + s.results.count + s.upcoming.count
        let sectionCount = [s.live, s.results, s.upcoming].filter { !$0.isEmpty }.count
        let listHeight = max(220, matchCount * 63 + sectionCount * 30)

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

            if matchCount <= 8 {
                matchList(s)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    matchList(s)
                }
                .frame(height: CGFloat(min(660, listHeight)))
            }

            Divider()
            Toggle("开机自启动", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).controlSize(.mini).font(.caption)
            HStack {
                Text("进行中每30秒刷新").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 390)
    }

    private func matchList(_ snapshot: WorldCupSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            section("正在进行", snapshot.live, color: .red, upcoming: false)
            section("已完赛", snapshot.results, color: .green, upcoming: false)
            section("即将开赛", snapshot.upcoming, color: .orange, upcoming: true)
            if snapshot.live.isEmpty && snapshot.results.isEmpty && snapshot.upcoming.isEmpty {
                Text("暂无比赛").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let home = Teams.info(m.home)
        let away = Teams.info(m.away)

        return VStack(spacing: 4) {
            Text(WCFormat.metaTime(m, withCity: true))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    Text(home.zh).lineLimit(1).minimumScaleFactor(0.75)
                    Text(home.flag)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                Text(upcoming ? WCFormat.clock(m.date) : "\(m.homeScore ?? 0) : \(m.awayScore ?? 0)")
                    .bold().monospacedDigit()
                    .foregroundStyle(upcoming ? Color.orange : Color.primary)
                    .frame(width: 58, alignment: .center)

                HStack(spacing: 5) {
                    Text(away.flag)
                    Text(away.zh).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
