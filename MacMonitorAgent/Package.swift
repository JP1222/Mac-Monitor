// swift-tools-version: 5.10
//
// MacMonitorAgent — a tiny HTTP daemon that reports local Mac health
// (disk, CPU, OrbStack, Docker, BuildKit cache) to the MacMonitor menu
// bar app. Designed to run as a LaunchAgent on each Mac mini in the
// build farm, but works fine on the user's primary Mac too.
//
// Build:
//   cd MacMonitorAgent
//   swift build -c release
//   .build/release/macmonitor-agent
//
// Install as LaunchAgent:
//   cp .build/release/macmonitor-agent /usr/local/bin/
//   cp launchd/com.jp1222.macmonitor-agent.plist ~/Library/LaunchAgents/
//   launchctl load ~/Library/LaunchAgents/com.jp1222.macmonitor-agent.plist
//
// Default port: 8765. Override with `MM_AGENT_PORT=<port>` env var.

import PackageDescription

let package = Package(
    name: "MacMonitorAgent",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macmonitor-agent", targets: ["MacMonitorAgent"]),
    ],
    targets: [
        .executableTarget(
            name: "MacMonitorAgent",
            path: "Sources/MacMonitorAgent"
        ),
    ]
)
