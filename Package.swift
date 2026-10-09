// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchPet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NotchPet", path: "Sources/NotchPet"),
        .testTarget(name: "NotchPetTests", dependencies: ["NotchPet"], path: "Tests/NotchPetTests", exclude: ["Fixtures"])
    ]
)
