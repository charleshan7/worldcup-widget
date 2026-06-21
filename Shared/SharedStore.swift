import Foundation

// 本地缓存：保存上次成功取到的赛况快照。
// 用途：① 网络/配置失败时回退展示上次数据（避免误显示空）；
//       ② 小组件手动刷新后短暂复用，避免紧接着重复请求。
// 说明：进程内缓存（App 与小组件各存各的）。要做「菜单栏 App ↔ 小组件」跨进程共享，
//       需 App Group 权限——而它需要 Apple ID 开发者团队/描述文件，当前 ad-hoc 签名用不了。
enum SharedStore {
    private static let key = "lastSnapshot"
    private static let defaults = UserDefaults.standard

    static func write(_ snapshot: WorldCupSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> WorldCupSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WorldCupSnapshot.self, from: data)
    }

    /// 读取且未过期（默认 5 秒内）才返回。
    static func readFresh(maxAge: TimeInterval = 5) -> WorldCupSnapshot? {
        guard let s = read() else { return nil }
        return Date().timeIntervalSince(s.updated) <= maxAge ? s : nil
    }
}
