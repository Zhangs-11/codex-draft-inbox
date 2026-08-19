// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexDraftInbox",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexDraftInbox", targets: ["CodexDraftInbox"]),
        .executable(name: "CodexDraftInboxSelfTest", targets: ["CodexDraftInboxSelfTest"]),
    ],
    targets: [
        .target(
            name: "DraftInboxCore",
            path: "Sources",
            exclude: [
                "CodexDraftInboxApp.swift",
                "DraftSyncService.swift",
                "GitHubUpdateChecker.swift",
                "InboxPanel.swift",
                "InboxViewModel.swift",
            ],
            sources: ["AppRelease.swift", "InboxModels.swift", "InboxRepository.swift", "RefreshCoordinator.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CodexDraftInbox",
            dependencies: ["DraftInboxCore"],
            path: "Sources",
            exclude: ["AppRelease.swift", "InboxModels.swift", "InboxRepository.swift", "RefreshCoordinator.swift"],
            sources: [
                "CodexDraftInboxApp.swift",
                "DraftSyncService.swift",
                "GitHubUpdateChecker.swift",
                "InboxPanel.swift",
                "InboxViewModel.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CodexDraftInboxSelfTest",
            dependencies: ["DraftInboxCore"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
