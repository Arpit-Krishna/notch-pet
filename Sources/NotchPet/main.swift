import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    let ui = NotchUI()
    var controller: NotchController?
    var bag: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController(store: store, ui: ui)
        ui.$pet.sink { [weak self] in self?.store.pet = $0 }.store(in: &bag)
        store.start()
    }
}

if CommandLine.arguments.contains("--version") {
    print("Notch Pet \(AppInfo.versionText)")
    exit(0)
}

// `NotchPet --export-sounds <dir>` writes every pet's alert sounds as WAV files, for previewing.
if let i = CommandLine.arguments.firstIndex(of: "--export-sounds"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for pet in PetKind.allCases {
        for kind in [SoundFX.Kind.done, .waiting, .error, .select] {
            try? SoundFX.data(kind, pet: pet).write(to: dir.appendingPathComponent("\(pet.rawValue)-\(kind.rawValue).wav"))
        }
    }
    exit(0)
}

MainActor.assumeIsolated {
    // `NotchPet --export-pets <file.png>` renders the pet roster, for previewing.
    if let i = CommandLine.arguments.firstIndex(of: "--export-pets"), i + 1 < CommandLine.arguments.count {
        let grid = VStack(alignment: .leading, spacing: 10) {
            ForEach([Mood.awake, .busy, .alert, .happy, .sleeping], id: \.self) { mood in
                HStack(spacing: 8) {
                    ForEach(PetKind.allCases) { AnyPetView(kind: $0, mood: mood, look: .zero, size: 48) }
                }
            }
        }
        .padding(16)
        .background(Color.black)
        let r = ImageRenderer(content: grid)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        exit(0)
    }
    // `NotchPet --export-icon <file.png>` renders the 1024 px app icon (see make-icon.sh).
    if let i = CommandLine.arguments.firstIndex(of: "--export-icon"), i + 1 < CommandLine.arguments.count {
        // The awake pet hops one pixel for a quarter of every 2.7 s; render while it stands still.
        while Int(Date().timeIntervalSinceReferenceDate * 1.5) % 4 == 0 { usleep(50_000) }
        let r = ImageRenderer(content: AppIconView())
        r.scale = 4
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        exit(0)
    }
    // `NotchPet --export-biomes <file.png>` renders every pet's home biome.
    if let i = CommandLine.arguments.firstIndex(of: "--export-biomes"), i + 1 < CommandLine.arguments.count {
        let kinds: [PetKind] = [.villager, .warden, .herobrine, .zombie, .wolf, .bee, .axolotl, .grassBlock]
        let grid = LazyVGrid(columns: [GridItem(.fixed(300)), GridItem(.fixed(300))], spacing: 8) {
            ForEach(kinds) { k in
                ZStack(alignment: .topLeading) {
                    BiomeView(biome: k.biome).frame(width: 300, height: 110)
                    HStack(spacing: 6) {
                        AnyPetView(kind: k, mood: .awake, look: .zero, size: 36)
                        Text("\(k.name) · \(k.biome.name)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
                    }
                    .padding(8)
                }
                .frame(width: 300, height: 110)
                .clipped()
            }
        }
        .padding(12)
        .background(Color.black)
        let r = ImageRenderer(content: grid)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
