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
    @Published var theme: WidgetTheme = ThemePref.get()
    @Published var barShowsResult = true   // 菜单栏轮播:true=已完赛,false=下一场
    private var started = false
    private var activity: NSObjectProtocol?
    private let themeServer = ThemeServer()   // 供桌面组件读取外观的本地服务

    func startIfNeeded() {
        guard !started else { return }
        started = true
        applyPanelAppearance() // 启动即按偏好设好面板外观
        themeServer.start()    // 起本地服务，组件取数据时来读外观+比分
        publishLocal()
        // 防 App Nap：闲置时也不被系统挂起，保证轮询不中断（仍允许系统正常息屏睡眠）
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "世界杯实时比分刷新")
        // 每次启动校正登录项（自愈）：ad-hoc 签名把代码哈希钉进登录项记录，
        // 重装/重建后哈希变化会让旧记录失效，这里据用户意愿用当前哈希重新登记。
        reconcileLoginItem()
        // 菜单栏标签轮播：无进行中时,每 12 秒在「已完赛」与「下一场预告」间切换
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                barShowsResult.toggle()
            }
        }
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
        publishLocal()   // 把最新赛况供给本地服务，组件本地取数既快又新
        // 指定刷新世界杯组件。组件优先从本地服务取「外观+比分」。
        WidgetCenter.shared.reloadTimelines(ofKind: "WorldCupWidget")
    }

    // 把当前外观 + 最新赛况编码后供给本地服务（桌面组件来读）。
    private func publishLocal() {
        let payload = LocalPayload(theme: theme.rawValue, snapshot: snapshot)
        if let data = try? JSONEncoder().encode(payload) {
            themeServer.setPayload(data)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "wantsLoginItem")
        do {
            if on {
                try? SMAppService.mainApp.unregister()   // 先清旧记录，再用当前哈希登记
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch { }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // 据用户意愿 + 可执行文件指纹，校正登录项；重装(哈希变)时自动重新登记。
    private func reconcileLoginItem() {
        let wants = UserDefaults.standard.object(forKey: "wantsLoginItem") as? Bool ?? true  // 首次默认开
        // 指纹同时含「bundle 路径 + 可执行文件修改时间」：路径变化（如从 DMG 暂存目录搬到
        // /Applications）也必须重新登记，否则登录项会指向已被删除的旧路径，开机拉不起来。
        var stamp = Bundle.main.bundlePath
        if let url = Bundle.main.executableURL,
           let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
           let date = vals.contentModificationDate {
            stamp += "@" + String(format: "%.0f", date.timeIntervalSince1970)
        }
        let changed = UserDefaults.standard.string(forKey: "loginItemStamp") != stamp
        do {
            if wants {
                if changed || SMAppService.mainApp.status != .enabled {
                    try? SMAppService.mainApp.unregister()
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch { }
        UserDefaults.standard.set(stamp, forKey: "loginItemStamp")
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func setTheme(_ t: WidgetTheme) {
        theme = t
        ThemePref.set(t)
        applyPanelAppearance()
        publishLocal()                             // 立刻把新外观供给本地服务
        WidgetCenter.shared.reloadAllTimelines()   // 组件立即重新取外观
    }

    // 强制整个 App（含菜单栏下拉面板）的外观；.system 时交还系统。
    // 比 SwiftUI 的 .preferredColorScheme 更可靠——后者管不动 MenuBarExtra 窗口的材质背景。
    func applyPanelAppearance() {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension WidgetTheme {
    // 面板/窗口可用 .preferredColorScheme 强制外观（与小组件不同，App 窗口支持覆写）。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@main
struct WorldCupApp: App {
    @StateObject private var store = ScoreStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
                .preferredColorScheme(store.theme.colorScheme)   // 面板也跟随「外观」开关
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
        let result = store.snapshot.results.last
        let next = store.snapshot.upcoming.first
        Group {
            if let m = store.snapshot.live.first {
                Text("\(WCFormat.progressLabel(m) ?? WCFormat.clock(m.date)) \(flag(m.home))\(m.homeScore ?? 0)-\(m.awayScore ?? 0)\(flag(m.away))")
            } else if let m = result, store.barShowsResult || next == nil {
                Text("已完赛 \(flag(m.home))\(m.homeScore ?? 0)-\(m.awayScore ?? 0)\(flag(m.away))")
            } else if let m = next {
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

            // 不滚动:面板贴合全部内容自然撑高,一屏展示完。
            matchList(s)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack(spacing: 8) {
                Text("外观").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { store.theme },
                    set: { store.setTheme($0) })) {
                    Text("跟随系统").tag(WidgetTheme.system)
                    Text("白").tag(WidgetTheme.light)
                    Text("黑").tag(WidgetTheme.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
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
        VStack(alignment: .leading, spacing: 6) {
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

        return VStack(spacing: 2) {
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
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
