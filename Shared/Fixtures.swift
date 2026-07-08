import Foundation

// 2026 世界杯：比赛 -> 球场静态表（TheSportsDB 抓取 + 官方赛程补全；运行时查表，不联网）
// key = 两队中文名排序后用 | 连接；value = 球场英文名（经 Venues 映射成中文显示）
enum Fixtures {
    static func venue(_ home: String, _ away: String, id: Int? = nil) -> String? {
        if let id, let venue = venueByMatchId[id] { return venue }
        let k = [Teams.info(home).zh, Teams.info(away).zh].sorted().joined(separator: "|")
        return venueByPair[k]
    }

    // 淘汰赛优先按比赛 ID 匹配：队伍会随晋级变化，但比赛 ID 和球场固定。
    static let venueByMatchId: [Int: String] = [
        537381: "Mercedes-Benz Stadium",          // Argentina vs Egypt
        537382: "BC Place",                       // Switzerland vs Colombia
        537383: "Gillette Stadium",               // France vs Morocco
        537384: "SoFi Stadium",                   // Spain vs Belgium
        537385: "Hard Rock Stadium",              // Norway vs England
        537386: "GEHA Field at Arrowhead Stadium",
        537387: "AT&T Stadium",
    ]

    static let venueByPair: [String: String] = [
        "乌兹别克斯坦|刚果（金）": "Estadio Akron",
        "乌兹别克斯坦|哥伦比亚": "Estadio Azteca",
        "乌兹别克斯坦|葡萄牙": "NRG Stadium",
        "乌拉圭|佛得角": "Hard Rock Stadium",
        "乌拉圭|沙特": "Hard Rock Stadium",
        "乌拉圭|西班牙": "Estadio Akron",
        "伊拉克|塞内加尔": "BMO Field",
        "伊拉克|挪威": "Gillette Stadium",
        "伊拉克|法国": "Lincoln Financial Field",
        "伊朗|比利时": "SoFi Stadium",
        "伊朗|埃及": "Lumen Field",
        "伊朗|新西兰": "SoFi Stadium",
        "佛得角|沙特": "Reliant Stadium",
        "佛得角|西班牙": "Mercedes-Benz Stadium",
        "佛得角|阿根廷": "Hard Rock Stadium",
        "克罗地亚|加纳": "Lincoln Financial Field",
        "克罗地亚|巴拿马": "BMO Field",
        "克罗地亚|英格兰": "AT&T Stadium",
        "刚果（金）|哥伦比亚": "Estadio Akron",
        "刚果（金）|葡萄牙": "NRG Stadium",
        "加拿大|卡塔尔": "BC Place",
        "加拿大|波黑": "BMO Field",
        "加拿大|瑞士": "BC Place",
        "加纳|巴拿马": "BMO Field",
        "加纳|英格兰": "Gillette Stadium",
        "南非|墨西哥": "Estadio Azteca",
        "南非|捷克": "Mercedes-Benz Stadium",
        "南非|韩国": "Estadio BBVA",
        "加拿大|摩洛哥": "NRG Stadium",
        "卡塔尔|波黑": "Lumen Field",
        "卡塔尔|瑞士": "Levi's Stadium",
        "厄瓜多尔|瑞典": "AT&T Stadium",
        "厄瓜多尔|库拉索": "GEHA Field at Arrowhead Stadium",
        "厄瓜多尔|德国": "MetLife Stadium",
        "厄瓜多尔|科特迪瓦": "Lincoln Financial Field",
        "哥伦比亚|加纳": "GEHA Field at Arrowhead Stadium",
        "哥伦比亚|葡萄牙": "Hard Rock Stadium",
        "哥伦比亚|瑞士": "BC Place",
        "土耳其|巴拉圭": "Levi's Stadium",
        "土耳其|澳大利亚": "BC Place",
        "土耳其|美国": "SoFi Stadium",
        "埃及|澳大利亚": "AT&T Stadium",
        "埃及|阿根廷": "Mercedes-Benz Stadium",
        "埃及|新西兰": "BC Place",
        "埃及|比利时": "Lumen Field",
        "墨西哥|英格兰": "Estadio Azteca",
        "塞内加尔|挪威": "MetLife Stadium",
        "塞内加尔|法国": "MetLife Stadium",
        "墨西哥|捷克": "Estadio Azteca",
        "墨西哥|韩国": "Estadio Akron",
        "巴拉圭|法国": "Lincoln Financial Field",
        "奥地利|约旦": "Levi's Stadium",
        "奥地利|阿尔及利亚": "GEHA Field at Arrowhead Stadium",
        "奥地利|阿根廷": "AT&T Stadium",
        "巴拉圭|澳大利亚": "Levi's Stadium",
        "巴拉圭|美国": "SoFi Stadium",
        "巴拿马|英格兰": "MetLife Stadium",
        "巴西|摩洛哥": "MetLife Stadium",
        "巴西|海地": "Lincoln Financial Field",
        "巴西|苏格兰": "Hard Rock Stadium",
        "巴西|挪威": "MetLife Stadium",
        "库拉索|德国": "NRG Stadium",
        "库拉索|科特迪瓦": "Lincoln Financial Field",
        "德国|科特迪瓦": "BMO Field",
        "挪威|法国": "Gillette Stadium",
        "捷克|韩国": "Estadio Akron",
        "摩洛哥|海地": "Mercedes-Benz Stadium",
        "摩洛哥|苏格兰": "Gillette Stadium",
        "新西兰|比利时": "BC Place",
        "日本|瑞典": "Estadio BBVA",
        "日本|突尼斯": "Estadio BBVA",
        "日本|荷兰": "AT&T Stadium",
        "沙特|西班牙": "Mercedes-Benz Stadium",
        "波黑|瑞士": "Levi's Stadium",
        "海地|苏格兰": "Gillette Stadium",
        "澳大利亚|美国": "Lumen Field",
        "瑞典|突尼斯": "Estadio BBVA",
        "瑞典|荷兰": "NRG Stadium",
        "突尼斯|荷兰": "GEHA Field at Arrowhead Stadium",
        "美国|比利时": "Lumen Field",
        "约旦|阿尔及利亚": "Levi's Stadium",
        "约旦|阿根廷": "AT&T Stadium",
        "葡萄牙|西班牙": "AT&T Stadium",
        "瑞士|阿尔及利亚": "BC Place",
        "阿尔及利亚|阿根廷": "GEHA Field at Arrowhead Stadium",
    ]
}
