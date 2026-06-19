---
name: world-cup-widget-builder
description: Create, customize, configure, build, and troubleshoot a native macOS SwiftUI and WidgetKit World Cup live-score widget based on this repository. Use when a user asks AI to make a World Cup desktop widget, change its teams, language, colors, layout, refresh behavior, football-data.org integration, bundle identifiers, or prepare the project for local installation.
---

# World Cup Widget Builder

Build on the native project at the repository root. Preserve its SwiftUI, WidgetKit, menu-bar app, and shared-data structure unless the user requests a different architecture.

## Workflow

1. Locate the repository root by walking upward until `project.yml` and `WorldCupWidget.xcodeproj` are present.
2. Read `README.md`, `project.yml`, and the relevant files under `App/`, `Widget/`, and `Shared/`.
3. Never place API tokens, signing certificates, or developer-team identifiers in tracked files.
4. Use the public proxy by default. If the user explicitly wants a private football-data.org token, copy `Config.local.xcconfig.example` to `Config.local.xcconfig` and follow its comments. Do not request that they send the token in chat.
5. Apply requested visual or data changes. Use [references/customization.md](references/customization.md) to find the correct files.
6. Run `scripts/prepare-project.sh` from this skill to regenerate the Xcode project when `project.yml` changes.
7. Validate with an unsigned Debug build:

   ```bash
   xcodebuild -project WorldCupWidget.xcodeproj \
     -scheme WorldCupWidget \
     -configuration Debug \
     -derivedDataPath build/DerivedData \
     CODE_SIGNING_ALLOWED=NO build
   ```

8. Scan tracked candidates for secrets before handing off:

   ```bash
   git grep -n -Ei '(api[_-]?key|api[_-]?token|secret|password).*[=:].*[A-Za-z0-9]{16,}'
   ```

9. Explain that local unsigned builds may trigger macOS security warnings. Require Developer ID signing and Apple notarization for frictionless public distribution.

## Guardrails

- Keep `Config.local.xcconfig` ignored by Git. Never add a personal token to `Release.xcconfig`.
- Do not claim that football-data.org provides every live event or minute-by-minute update; respect its plan and rate limits.
- Do not commit generated build products or personal Xcode user data.
- Treat FIFA marks, tournament logos, and third-party image assets as potentially restricted. Prefer original or properly licensed artwork for public releases.
- Preserve macOS 14 or later support unless the user explicitly changes the deployment target.
