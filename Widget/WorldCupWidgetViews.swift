import SwiftUI
import WidgetKit

extension Color {
    static let wcText = Color(red: 0.91, green: 0.92, blue: 0.95)
    static let wcMuted = Color(red: 0.58, green: 0.60, blue: 0.66)
    static let wcDim = Color(red: 0.44, green: 0.46, blue: 0.52)
    static let wcGreen = Color(red: 0.24, green: 0.86, blue: 0.59)
    static let wcAmber = Color(red: 1.0, green: 0.82, blue: 0.40)
    static let wcRed = Color(red: 1.0, green: 0.33, blue: 0.44)
    static let wcGold = Color(red: 0.93, green: 0.76, blue: 0.38)
}

// MARK: - 区块标题

struct SectionTitle: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: 12)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.wcMuted)
        }
    }
}

// MARK: - 一队（国旗 + 名字）

struct TeamLabel: View {
    let name: String
    let trailing: Bool   // true = 靠右贴近比分（主队）
    let nameSize: CGFloat

    var body: some View {
        let info = Teams.info(name)
        HStack(spacing: 5) {
            if trailing { Spacer(minLength: 0) }
            if !trailing { Text(info.flag).font(.system(size: nameSize + 2)) }
            Text(info.zh)
                .font(.system(size: nameSize))
                .foregroundStyle(Color.wcText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if trailing { Text(info.flag).font(.system(size: nameSize + 2)) }
            if !trailing { Spacer(minLength: 0) }
        }
    }
}

private func scoreText(_ m: Match) -> String { "\(m.homeScore ?? 0) : \(m.awayScore ?? 0)" }

// MARK: - 排布 B：居中对阵式（小/中号用）

struct CenteredMatchRow: View {
    let m: Match
    let upcoming: Bool
    var nameSize: CGFloat = 12.5

    var body: some View {
        VStack(spacing: 2) {
            Text(WCFormat.metaTime(m, withCity: true))   // 时间 · 组别 · 球场（城市）
                .font(.system(size: 11))
                .foregroundStyle(Color.wcMuted)
                .lineLimit(1).minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                TeamLabel(name: m.home, trailing: true, nameSize: nameSize)
                Text(upcoming ? "VS" : scoreText(m))
                    .font(.system(size: upcoming ? 12 : 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(upcoming ? Color.wcAmber : Color.wcText)
                    .frame(width: 50)
                TeamLabel(name: m.away, trailing: false, nameSize: nameSize)
            }
        }
    }
}

// MARK: - 排布 C：左对齐紧凑式（大号用）

struct LeftMatchRow: View {
    let m: Match
    let upcoming: Bool
    var nameSize: CGFloat = 12.5

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(WCFormat.metaTime(m))
                .font(.system(size: 11))
                .foregroundStyle(Color.wcMuted)
                .lineLimit(1).minimumScaleFactor(0.7)

            HStack(spacing: 5) {
                Text(Teams.info(m.home).flag).font(.system(size: nameSize + 2))
                Text(Teams.info(m.home).zh)
                    .font(.system(size: nameSize)).foregroundStyle(Color.wcText)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(upcoming ? "VS" : scoreText(m))
                    .font(.system(size: upcoming ? 12 : 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(upcoming ? Color.wcAmber : Color.wcText)
                    .padding(.horizontal, 3)
                Text(Teams.info(m.away).zh)
                    .font(.system(size: nameSize)).foregroundStyle(Color.wcText)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(Teams.info(m.away).flag).font(.system(size: nameSize + 2))
                Spacer(minLength: 0)
            }

            Text(WCFormat.metaPlace(m))
                .font(.system(size: 10))
                .foregroundStyle(Color.wcDim)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

// MARK: - 顶部标题（大力神杯图标）

struct WidgetHeader: View {
    let updated: Date
    var compact: Bool = false
    var body: some View {
        HStack(spacing: 6) {
            Image("WC26Mark")
                .resizable()
                .scaledToFit()
                .frame(height: compact ? 17 : 20)
            Text("2026 美加墨世界杯")
                .font(.system(size: compact ? 13 : 14.5, weight: .semibold))
                .foregroundStyle(Color.wcText)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise").font(.system(size: 9))
                Text(WCFormat.clock(updated)).font(.system(size: 10))
            }
            .foregroundStyle(Color.wcMuted)
        }
    }
}

// MARK: - Large（排布 C）

struct LargeView: View {
    let snapshot: WorldCupSnapshot

    private func rows(_ arr: [Match], upcoming: Bool) -> some View {
        ForEach(arr) { CenteredMatchRow(m: $0, upcoming: upcoming, nameSize: 11.5) }
    }

    @ViewBuilder private var resultsBlock: some View {
        SectionTitle(text: "已完赛", color: .wcGreen)
        if snapshot.results.isEmpty {
            Text("暂无已结束的比赛").font(.system(size: 11)).foregroundStyle(Color.wcMuted)
        } else {
            rows(snapshot.results, upcoming: false)
        }
    }

    @ViewBuilder private var upcomingBlock: some View {
        SectionTitle(text: "即将开赛", color: .wcAmber)
        if snapshot.upcoming.isEmpty {
            Text("暂无即将开始的比赛").font(.system(size: 11)).foregroundStyle(Color.wcMuted)
        } else {
            rows(snapshot.upcoming, upcoming: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(updated: snapshot.updated)

            if !snapshot.live.isEmpty {
                SectionTitle(text: "正在进行", color: .wcRed)
                rows(snapshot.live, upcoming: false)
            }

            // 有已结束比赛 → 战报在上；没有 → 战报放最底
            if snapshot.results.isEmpty {
                upcomingBlock
                resultsBlock
            } else {
                resultsBlock
                upcomingBlock
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Medium（排布 B）

struct MediumView: View {
    let snapshot: WorldCupSnapshot

    // 中号规则：共 3 场，优先级 进行中 > 已完赛 > 即将开赛。
    // 已完赛取「最近刚完成的两场」（按时间，最多2）；不足3场用即将开赛补足。
    var body: some View {
        let live = Array(snapshot.live.prefix(3))
        let afterLive = max(0, 3 - live.count)
        let finished = Array(snapshot.results.suffix(min(2, afterLive)))   // 最近的若干场（升序）
        let afterFin = max(0, afterLive - finished.count)
        let upcoming = Array(snapshot.upcoming.prefix(afterFin))

        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(updated: snapshot.updated, compact: true)

            if !live.isEmpty {
                SectionTitle(text: "正在进行", color: .wcRed)
                ForEach(live) { CenteredMatchRow(m: $0, upcoming: false, nameSize: 11) }
            }
            if !finished.isEmpty {
                SectionTitle(text: "已完赛", color: .wcGreen)
                ForEach(finished) { CenteredMatchRow(m: $0, upcoming: false, nameSize: 11) }
            }
            if !upcoming.isEmpty {
                SectionTitle(text: "即将开赛", color: .wcAmber)
                ForEach(upcoming) { CenteredMatchRow(m: $0, upcoming: true, nameSize: 11) }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Small（排布 B，队伍竖排居中以适应窄宽度）

struct SmallView: View {
    let snapshot: WorldCupSnapshot
    var rotation: Int = 0   // 轮播：已完赛热度前3 + 即将开赛1（+进行中）

    var body: some View {
        let items = snapshot.smallFeatured
        if items.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Text("暂无比赛").font(.system(size: 12)).foregroundStyle(Color.wcMuted)
                Spacer()
            }
        } else {
            let active = rotation % items.count
            let m = items[active]
            let upcoming = (m.homeScore == nil && m.awayScore == nil)
            VStack(alignment: .leading, spacing: 4) {
                header(m, count: items.count, active: active)
                Spacer(minLength: 0)
                teamLine(m.home, m.homeScore, showScore: !upcoming)
                if upcoming {
                    Text(WCFormat.clock(m.date))
                        .font(.system(size: 17, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color.wcAmber)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                teamLine(m.away, m.awayScore, showScore: !upcoming)
                Spacer(minLength: 0)
                Text(WCFormat.metaTime(m))
                    .font(.system(size: 9.5)).foregroundStyle(Color.wcDim)
                    .lineLimit(1).minimumScaleFactor(0.55)
            }
        }
    }

    @ViewBuilder
    private func header(_ m: Match?, count: Int = 0, active: Int = 0) -> some View {
        HStack(spacing: 4) {
            Image("WC26Mark").resizable().scaledToFit().frame(height: 15)
            Text(label(m)).font(.system(size: 10, weight: .semibold)).foregroundStyle(labelColor(m))
            Spacer(minLength: 0)
            if count > 1 {
                HStack(spacing: 3) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(i == active ? Color.wcText : Color.wcDim.opacity(0.45))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
    }

    private func teamLine(_ name: String, _ score: Int?, showScore: Bool) -> some View {
        let info = Teams.info(name)
        return HStack(spacing: 5) {
            Text(info.flag).font(.system(size: 15))
            Text(info.zh).font(.system(size: 13)).foregroundStyle(Color.wcText)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            if showScore {
                Text("\(score ?? 0)").font(.system(size: 16, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Color.wcText)
            }
        }
    }

    private func isLive(_ m: Match) -> Bool {
        ["IN_PLAY", "PAUSED", "SUSPENDED"].contains(m.status)
    }
    private func label(_ m: Match?) -> String {
        guard let m else { return "美加墨世界杯" }
        if isLive(m) { return "进行中" }
        return (m.homeScore == nil) ? "即将开赛" : "已完赛"
    }
    private func labelColor(_ m: Match?) -> Color {
        guard let m else { return .wcMuted }
        if isLive(m) { return .wcRed }
        return (m.homeScore == nil) ? .wcAmber : .wcGreen
    }
}
