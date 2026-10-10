// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Skillbox",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Skillbox", targets: ["Skillbox"]),
        .library(name: "SkillboxCore", targets: ["SkillboxCore"]),
    ],
    targets: [
        .target(name: "SkillboxCore"),
        .executableTarget(name: "SkillboxChecks", dependencies: ["SkillboxCore"], path: "Checks"),
        .executableTarget(
            name: "Skillbox",
            dependencies: ["SkillboxCore"],
            resources: [.copy("Resources/preview.css")]
        ),
        .testTarget(name: "SkillboxCoreTests", dependencies: ["SkillboxCore"],
            swiftSettings: [.unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])],
            linkerSettings: [.unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks", "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks", "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"])]) ,
    ]
)
