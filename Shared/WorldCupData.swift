import Foundation

// MARK: - Models

struct Goal: Codable, Hashable {
    let player: String
    let minute: Int?
    let isHome: Bool
    let ownGoal: Bool
}

struct Match: Identifiable, Hashable, Codable {
    let id: String
    let home: String
    let away: String
    let homeScore: Int?
    let awayScore: Int?
    let date: Date?
    let status: String
    let progress: String?
    let group: String?
    let venue: String?
    let city: String?
    var goals: [Goal] = []     // 进球人+分钟（由数据代理补全，拿得到才有）
    var minute: Int? = nil     // 直播分钟（ESPN，进行中才有）
    var phase: String? = nil   // 直播阶段（如 STATUS_HALFTIME）
}

struct WorldCupSnapshot: Codable {
    var live: [Match]
    var results: [Match]
    var upcoming: [Match]
    var updated: Date
}

// MARK: - football-data.org v4 响应

private struct FDResponse: Decodable { let matches: [FDMatch]? }

private struct FDMatch: Decodable {
    let id: Int?
    let utcDate: String?
    let status: String?      // SCHEDULED / TIMED / IN_PLAY / PAUSED / FINISHED / …
    let stage: String?
    let group: String?       // "GROUP_A" 或 null
    let venue: String?
    let homeTeam: FDTeam?
    let awayTeam: FDTeam?
    let score: FDScore?
    let goals: [Goal]?
    let minute: Int?
    let phase: String?
}
private struct FDTeam: Decodable { let name: String?; let shortName: String?; let tla: String? }
private struct FDScore: Decodable { let fullTime: FDScoreTime? }
private struct FDScoreTime: Decodable { let home: Int?; let away: Int? }

// MARK: - Fetcher（football-data.org）

enum WorldCupAPI {
    /// 从构建配置注入，避免把个人 API Token 提交到源码仓库。
    static var apiToken: String {
        Bundle.main.object(forInfoDictionaryKey: "FootballDataAPIToken") as? String ?? ""
    }

    /// 公开安装包优先使用云端代理，避免把 football-data.org Token 写进 App。
    static var dataEndpoint: String {
        Bundle.main.object(forInfoDictionaryKey: "WorldCupDataEndpoint") as? String ?? ""
    }

    static let matchesURL = "https://api.football-data.org/v4/competitions/WC/matches"

    // 模拟休赛日（清空窗口 → 回退展示未来比赛）。仅 Debug 可开，发布版恒为 false。
    #if DEBUG
    static let debugForceRestDay = false   // 演示休赛日时临时改 true
    #else
    static let debugForceRestDay = false
    #endif

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func fetchSnapshot() async -> WorldCupSnapshot {
        let today = Date()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)
        // 今天 00:00 ~ 未来 7 天（本地/北京时间）之间开球的比赛。
        // 这样菜单栏/中大卡有足够的预告数据可填充；具体展示数量由各尺寸卡片自行裁剪。
        let windowLower = todayStart
        let windowUpper = today.addingTimeInterval(7 * 24 * 3600)

        let raw = await fetchAll()
        if raw.isEmpty {   // 网络/配置失败：回退到上次缓存，避免误显示空
            return SharedStore.read() ?? WorldCupSnapshot(live: [], results: [], upcoming: [], updated: Date())
        }

        let finishedStatuses: Set<String> = ["FINISHED", "AWARDED"]
        let liveStatuses: Set<String> = ["IN_PLAY", "PAUSED", "SUSPENDED"]
        let upcomingStatuses: Set<String> = ["SCHEDULED", "TIMED"]

        // 先构造全部比赛（不限窗口）
        let allMatches: [Match] = raw.compactMap { fm in
            guard let dt = fm.utcDate.flatMap({ iso.date(from: $0) }) else { return nil }
            return Match(
                id: fm.id.map(String.init) ?? UUID().uuidString,
                home: fm.homeTeam?.name ?? "",
                away: fm.awayTeam?.name ?? "",
                homeScore: fm.score?.fullTime?.home,
                awayScore: fm.score?.fullTime?.away,
                date: dt,
                status: (fm.status ?? "").uppercased(),
                progress: nil,
                group: groupLetter(fm.group),
                venue: fm.venue ?? Fixtures.venue(fm.homeTeam?.name ?? "", fm.awayTeam?.name ?? "", id: fm.id),
                city: nil,
                goals: fm.goals ?? [],
                minute: fm.minute,
                phase: fm.phase
            )
        }

        let past = Date.distantPast
        let future = Date.distantFuture

        var results: [Match] = []
        var live: [Match] = []
        var upcoming: [Match] = []
        for m in allMatches {
            guard let dt = m.date, dt >= windowLower, dt <= windowUpper else { continue }
            if finishedStatuses.contains(m.status) { results.append(m) }
            else if liveStatuses.contains(m.status) { live.append(m) }
            else if upcomingStatuses.contains(m.status), !m.home.isEmpty, !m.away.isEmpty { upcoming.append(m) }
        }

        if debugForceRestDay { live = []; results = []; upcoming = [] }   // 模拟休赛日

        live.sort { ($0.date ?? past) < ($1.date ?? past) }
        let finalResults = results.sorted { ($0.date ?? past) < ($1.date ?? past) }
        var finalUpcoming = upcoming.sorted { ($0.date ?? future) < ($1.date ?? future) }

        // 窗口内没有任何比赛 → 直接提示未来最近的 6 场（跳过队伍未定的淘汰赛）
        if live.isEmpty && finalResults.isEmpty && finalUpcoming.isEmpty {
            let now = Date()
            finalUpcoming = allMatches
                .filter { upcomingStatuses.contains($0.status)
                    && !$0.home.isEmpty && !$0.away.isEmpty
                    && ($0.date ?? past) >= now }
                .sorted { ($0.date ?? future) < ($1.date ?? future) }
            finalUpcoming = Array(finalUpcoming.prefix(6))
        }

        let snapshot = WorldCupSnapshot(
            live: Array(live.prefix(6)),
            results: finalResults,
            upcoming: finalUpcoming,
            updated: Date()
        )
        SharedStore.write(snapshot)   // 写入进程内缓存：减少重复请求 + 离线兜底
        return snapshot
    }

    private static func groupLetter(_ g: String?) -> String? {
        guard let g, !g.isEmpty else { return nil }
        if let r = g.range(of: "GROUP_") { return String(g[r.upperBound...]) }
        return g
    }

    private static func fetchAll() async -> [FDMatch] {
        let endpoint = dataEndpoint.isEmpty ? matchesURL : dataEndpoint
        guard let url = URL(string: endpoint) else { return [] }

        if dataEndpoint.isEmpty && apiToken.isEmpty {
            print("WorldCupWidget: configure WORLD_CUP_DATA_ENDPOINT or FOOTBALL_DATA_API_TOKEN.")
            return []
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if dataEndpoint.isEmpty {
            req.setValue(apiToken, forHTTPHeaderField: "X-Auth-Token")
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return (try? JSONDecoder().decode(FDResponse.self, from: data).matches) ?? []
        } catch {
            return []
        }
    }

}

// MARK: - Sample data (用于预览 / 占位)

extension WorldCupSnapshot {
    static var sample: WorldCupSnapshot {
        func date(_ s: String) -> Date {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f.date(from: s) ?? Date()
        }
        let results = [
            Match(id: "r1", home: "England", away: "Croatia", homeScore: 4, awayScore: 2,
                  date: date("2026-06-17T20:00:00"), status: "FINISHED", progress: nil, group: "L",
                  venue: "AT&T Stadium", city: "Arlington, TX"),
            Match(id: "r2", home: "Portugal", away: "Ghana", homeScore: 3, awayScore: 1,
                  date: date("2026-06-18T01:00:00"), status: "FINISHED", progress: nil, group: "F",
                  venue: "MetLife Stadium", city: "New York, NJ"),
        ]
        let upcoming = [
            Match(id: "u1", home: "Mexico", away: "South Korea", homeScore: nil, awayScore: nil,
                  date: date("2026-06-19T01:00:00"), status: "TIMED", progress: nil, group: "A",
                  venue: "Estadio Akron", city: "Zapopan, JA"),
            Match(id: "u2", home: "Brazil", away: "Haiti", homeScore: nil, awayScore: nil,
                  date: date("2026-06-20T00:30:00"), status: "TIMED", progress: nil, group: "C",
                  venue: "Lincoln Financial Field", city: "Philadelphia, PA"),
        ]
        return WorldCupSnapshot(live: [], results: results, upcoming: upcoming, updated: Date())
    }
}

// MARK: - 热度（两队人气之和，用于挑选最受关注的比赛）

enum Popularity {
    static func heat(_ m: Match) -> Int { score(m.home) + score(m.away) }
    static func score(_ team: String) -> Int { map[team] ?? 50 }

    static let map: [String: Int] = [
        "Brazil": 100, "Argentina": 100,
        "France": 96, "England": 96, "Spain": 95, "Germany": 95, "Portugal": 94,
        "Netherlands": 88, "Italy": 88,
        "Belgium": 85, "Croatia": 85, "Uruguay": 84,
        "USA": 82, "United States": 82, "Mexico": 82,            // 东道主加成
        "Morocco": 80, "Japan": 78, "South Korea": 78, "Korea Republic": 78,
        "Colombia": 76, "Nigeria": 74, "Denmark": 74, "Switzerland": 74,
        "Senegal": 74, "Poland": 74, "Serbia": 72, "Canada": 72, // 东道主
        "Cameroon": 70, "Ghana": 70, "Egypt": 70, "Norway": 70,
        "Sweden": 68, "Turkey": 68, "Türkiye": 68, "Ivory Coast": 68,
        "Chile": 66, "Ukraine": 66, "Wales": 66, "Australia": 66,
        "Ecuador": 64, "Peru": 64, "Austria": 64, "Scotland": 64,
    ]
}

extension Popularity {
    /// 先按热度取前 n 场，再按时间正序排列
    static func pick(_ matches: [Match], top n: Int) -> [Match] {
        Array(matches.sorted { heat($0) > heat($1) }.prefix(n))
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
}

extension WorldCupSnapshot {
    /// 小号轮播用：进行中(≤1) + 已完赛热度前3 + 即将开赛(≤1)
    var smallFeatured: [Match] {
        Array(live.prefix(1)) + Popularity.pick(results, top: 3) + Array(upcoming.prefix(1))
    }
}

// MARK: - 格式化

enum WCFormat {
    static func clock(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func dayLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        case -1: return "昨天"
        case -2: return "前天"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日"
            return f.string(from: date)
        }
    }

    /// 例如「今天 06:00」（北京时间）
    static func dayTime(_ date: Date?) -> String {
        let d = dayLabel(date)
        let t = clock(date)
        return d.isEmpty ? t : "\(d) \(t)"
    }

    /// 进行中比赛的进程：中场休息 / 67' …（拿不到分钟时按开球至今估算）
    static func progressLabel(_ m: Match) -> String? {
        guard ["IN_PLAY", "PAUSED", "SUSPENDED"].contains(m.status) else { return nil }
        if m.status == "PAUSED" || (m.phase ?? "").contains("HALFTIME") { return "中场休息" }
        if let mn = m.minute { return "\(mn)'" }
        if let d = m.date {
            let mins = Int(Date().timeIntervalSince(d) / 60)
            if mins >= 0, mins <= 130 { return "\(mins)'" }
        }
        return "进行中"
    }

    /// 第一行：进程/日期时间 · X组 · 球场（进行中显示比赛进程，否则显示开球时间）
    static func metaTime(_ m: Match, withCity: Bool = false) -> String {
        var parts: [String] = [progressLabel(m) ?? dayTime(m.date)]
        if let g = m.group, !g.isEmpty { parts.append("\(g)组") }
        let v = Venues.info(venue: m.venue, rawCity: m.city)
        if !v.stadium.isEmpty {
            if withCity, !v.city.isEmpty {
                parts.append("\(v.stadium)（\(v.city)）")   // 球场（城市）——大/中卡片用
            } else {
                parts.append(v.stadium)
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 预告行说明：日期 · 组别 · 球场（城市）。带「今天/明天」以区分今天与次日的比赛；
    /// 不重复展示开球时间（开球时间在中间大字列单独显示）。
    static func metaVenue(_ m: Match) -> String {
        var parts: [String] = []
        let day = dayLabel(m.date)
        if !day.isEmpty { parts.append(day) }
        if let g = m.group, !g.isEmpty { parts.append("\(g)组") }
        let v = Venues.info(venue: m.venue, rawCity: m.city)
        if !v.stadium.isEmpty {
            parts.append(v.city.isEmpty ? v.stadium : "\(v.stadium)（\(v.city)）")
        }
        return parts.joined(separator: " · ")
    }

    /// 第二行：球场（城市，国家）
    static func metaPlace(_ m: Match) -> String {
        let v = Venues.info(venue: m.venue, rawCity: m.city)
        let inner = [v.city, v.country].filter { !$0.isEmpty }.joined(separator: "，")
        if inner.isEmpty { return v.stadium }
        if v.stadium.isEmpty { return "（\(inner)）" }
        return "\(v.stadium)（\(inner)）"
    }
}
