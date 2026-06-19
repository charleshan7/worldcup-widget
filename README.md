# 2026世界杯摸鱼看球小组件

把 2026 世界杯赛程和比分放到 Mac 桌面上，工作时不用反复打开网页，也能悄悄掌握正在进行、已经结束和即将开赛的比赛。

这是一个原生 SwiftUI + WidgetKit 项目，可同时运行在 macOS 桌面小组件和菜单栏。
![Uploading fa3b51352f131a94087fcc495cb4e71f.png…]()

## 它能做什么

- 小、中、大三种桌面组件
- 菜单栏实时比分与比赛列表
- 中文球队名、国旗、球场和分组信息
- 根据比赛状态自动调整刷新频率
- 使用 [football-data.org](https://www.football-data.org/) 获取比赛数据
- 安装包通过 Cloudflare Worker 安全获取数据，不会在 App 中暴露 API Token
- 内置 AI Skill，可帮助快速换主题、改布局或生成同款

## 怎么使用

### 1. 我只想直接用

适合不想改代码，只想把小组件放到桌面上的用户。

1. 打开 [Releases](https://github.com/charleshan7/worldcup-widget/releases/latest)，下载最新版 `.dmg` 安装包。
2. 将 App 拖入“应用程序”并打开一次。
3. 在 macOS 桌面右键选择“编辑小组件”。
4. 搜索“2026世界杯摸鱼看球小组件”，选择尺寸并添加到桌面。

> 当前为未经过 Apple Developer 公证的测试版。首次打开请按住 Control 键点按 App，选择“打开”；如果仍被拦截，请前往“系统设置 → 隐私与安全性”选择“仍要打开”。

### 2. 我想拿走源码，自己克隆

适合会使用 Xcode、希望自己维护或修改代码的用户。

环境要求：

- macOS 14 或更高版本
- Xcode
- 可选：一个免费的 [football-data.org](https://www.football-data.org/) API Token，用于改成自己的数据配置
- 可选：[XcodeGen](https://github.com/yonaskolb/XcodeGen)，仅在修改 `project.yml` 后需要

操作步骤：

1. 克隆仓库：

   ```bash
   git clone https://github.com/charleshan7/worldcup-widget.git
   cd worldcup-widget
   ```

2. 创建仅保存在本机的配置文件：

   ```bash
   cp Config.local.xcconfig.example Config.local.xcconfig
   ```

3. 默认会使用项目提供的公开数据接口。如果希望改用自己的 football-data.org Token，请填写 `Config.local.xcconfig`，并按文件注释清空公开接口配置。这个文件已被 Git 忽略，不会被提交。
4. 打开 `WorldCupWidget.xcodeproj`。
5. 选择 `WorldCupWidget` scheme 并运行。
6. 在桌面组件库中搜索“2026世界杯摸鱼看球小组件”并添加。

如果修改了 `project.yml`，先运行：

```bash
xcodegen generate
```

### 3. 我想用 Skill，让 AI 给我做一个

适合不会 Swift，或者想快速换主题、球队、语言、数据源和布局的用户。

仓库内置 `.agents/skills/world-cup-widget-builder`。在支持项目 Skill 的 AI 编程工具中打开本仓库，然后对 AI 说：

> 使用 world-cup-widget-builder，帮我制作一个自己的世界杯小组件。保留实时比分，改成蓝白配色，大号组件显示六场比赛。

Skill 会引导 AI 找到正确文件、保护 API Token、重新生成项目并进行构建验证。

你也可以继续提出更具体的要求，例如：

- “把它改成公司品牌色”
- “只显示中国队和我关注的球队”
- “改成英文界面”
- “做一个更适合上班摸鱼的小号组件”
- “帮我编译并告诉我怎么添加到桌面”

## 数据与商标

比赛数据由 football-data.org 提供，实际覆盖范围、刷新频率和额度取决于其服务计划。世界杯、FIFA 名称及相关标志属于各自权利人；公开分发前请确认图像和商标授权。

## License

代码采用 MIT License。第三方数据、字体、图片和商标不包含在该授权内。
