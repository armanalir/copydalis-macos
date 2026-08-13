// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopydalisCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Copydalis", targets: ["Copydalis"])
    ],
    targets: [
        .target(
            name: "Copydalis",
            path: "Copydalis",
            exclude: [
                "App",
                "Resources",
                "Settings",
                "UI",
                "Clipboard/ClipboardMonitor.swift",
                "Interaction/CarbonHotKeyRegistrar.swift"
            ],
            sources: [
                "Clipboard/ClipboardFilter.swift",
                "Clipboard/PasteboardWriter.swift",
                "Diagnostics/PrivacySafeLogger.swift",
                "History/ClipboardEntry.swift",
                "History/HistoryRepository.swift",
                "Interaction/HotKeyConfiguration.swift",
                "Interaction/PasteCoordinator.swift",
                "Interaction/PasteTargetPolicy.swift",
                "Interaction/PopupInputInterpreter.swift",
                "Interaction/SelectionSession.swift",
                "Security/EntryCryptor.swift",
                "Security/KeyMaterialStore.swift"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CopydalisTests",
            dependencies: ["Copydalis"],
            path: "CopydalisTests"
        )
    ]
)
