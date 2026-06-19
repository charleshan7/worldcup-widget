# Customization map

| Goal | Primary files |
|---|---|
| Change widget layout, typography, colors, sections | `Widget/WorldCupWidgetViews.swift` |
| Change timeline and refresh policy | `Widget/WorldCupWidget.swift` |
| Change menu-bar app | `App/WorldCupApp.swift` |
| Change API parsing, date window, match grouping | `Shared/WorldCupData.swift` |
| Change translated team names and flags | `Shared/TeamInfo.swift` |
| Change stadium names and cities | `Shared/Venues.swift`, `Shared/Fixtures.swift` |
| Change app name, identifiers, deployment target | `project.yml`, `Widget/Info.plist` |
| Change icons and tournament artwork | `App/Assets.xcassets`, `Widget/Assets.xcassets` |

Regenerate `WorldCupWidget.xcodeproj` with XcodeGen after changing `project.yml`.

Release builds use the public proxy configured in `Release.xcconfig`. Debug builds can override the endpoint or inject a personal token through the ignored `Config.local.xcconfig`. Both values are read from each target's Info.plist using `Bundle.main`.
