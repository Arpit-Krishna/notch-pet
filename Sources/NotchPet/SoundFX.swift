import AppKit

/// Sound effects and pet voices, all synthesized at runtime (no audio files shipped).
enum SoundFX {
    enum Kind: String {
        case done      // pet cheers, then a rising arpeggio
        case waiting   // pet calls you, then two bell dings
        case error     // pet groans lower, then a falling buzz
        case select    // pet says hello when picked
    }

    nonisolated(unsafe) static var enabled = true
    nonisolated(unsafe) private static var cache: [String: NSSound] = [:]
    static let rate = 22050.0

    /// Optional voice clips you add yourself: `<dir>/<pet>/<kind>*.mp3|wav|m4a|aiff`.
    /// When a pet has clips for an alert, one is played instead of its synthesized voice.
    static let customDir = HookInstaller.dir.appendingPathComponent("sounds")

    private static func customClips(_ kind: Kind, pet: PetKind) -> [URL] {
        let dir = customDir.appendingPathComponent(pet.rawValue)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(kind.rawValue) && ["mp3", "wav", "m4a", "aiff"].contains($0.pathExtension.lowercased()) }
    }

    nonisolated(unsafe) private static var playing: NSSound?
    nonisolated(unsafe) private static var playingJingle: NSSound?

    static func play(_ kind: Kind, pet: PetKind) {
        guard enabled else { return }
        if let url = customClips(kind, pet: pet).randomElement(), let clip = NSSound(contentsOf: url, byReference: true) {
            playing?.stop()
            playing = clip
            clip.volume = 0.7
            clip.play()
            // Long clips (cave ambience, creeper fuse) are cut short so an alert stays an alert.
            let length = min(clip.duration, 3.5)
            if clip.duration > length {
                DispatchQueue.main.asyncAfter(deadline: .now() + length) { if playing === clip { clip.stop() } }
            }
            guard kind != .select else { return }
            let jingleSound = NSSound(data: wav(jingle(kind, pet.voice)))
            DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.05) {
                jingleSound?.volume = 0.6
                playingJingle = jingleSound   // keep it alive while it plays
                jingleSound?.play()
            }
            return
        }
        let key = "\(kind.rawValue)-\(pet.rawValue)"
        let sound = cache[key] ?? {
            let s = NSSound(data: wav(clip(kind, pet: pet)))
            cache[key] = s
            return s
        }()
        sound?.stop()
        sound?.volume = 0.6
        sound?.play()
    }

    static func data(_ kind: Kind, pet: PetKind) -> Data { wav(clip(kind, pet: pet)) }

    private static func clip(_ kind: Kind, pet: PetKind) -> [Float] {
        let gap = [Float](repeating: 0, count: Int(0.05 * rate))
        let v = pet.voice
        switch kind {
        case .done: return voice(pet, mood: 1.12) + gap + jingle(.done, v)
        case .waiting: return voice(pet, mood: 1.0) + gap + jingle(.waiting, v)
        case .error: return voice(pet, mood: 0.85) + gap + jingle(.error, v)
        case .select: return voice(pet, mood: 1.0) + (Voices.has(pet) ? [] : jingle(.select, v))
        }
    }

    private static func voice(_ pet: PetKind, mood: Double) -> [Float] {
        Voices.samples(pet, pitch: mood)
    }

    // MARK: Chiptune jingles

    private struct Note { let freq: Double; let dur: Double; var wave = Wave.square; var slideTo: Double? = nil; var decay = 6.0 }
    private enum Wave { case square, triangle, noise }

    private static func jingle(_ kind: Kind, _ v: Double) -> [Float] {
        let notes: [Note]
        switch kind {
        case .done:
            notes = [523.25, 659.25, 783.99, 1046.5].map { Note(freq: $0 * v, dur: 0.08, wave: .square, decay: 3) }
                + [Note(freq: 1318.5 * v, dur: 0.3, wave: .triangle, decay: 5)]
        case .waiting:
            notes = [Note(freq: 880 * v, dur: 0.16, wave: .triangle, decay: 9),
                     Note(freq: 880 * v, dur: 0.28, wave: .triangle, decay: 7)]
        case .error:
            notes = [Note(freq: 220 * v, dur: 0.26, wave: .square, slideTo: 110 * v, decay: 4)]
        case .select:
            notes = [Note(freq: 600 * v, dur: 0.07, wave: .square, slideTo: 1200 * v, decay: 10)]
        }
        var out: [Float] = []
        var phase = 0.0
        var seed: UInt32 = 0x1234567
        for n in notes {
            let count = Int(n.dur * rate)
            for i in 0..<count {
                let p = Double(i) / Double(count)
                let f = n.slideTo.map { n.freq + ($0 - n.freq) * p } ?? n.freq
                phase += f / rate
                let x = phase - floor(phase)
                var s: Double
                switch n.wave {
                case .square: s = x < 0.5 ? 1 : -1
                case .triangle: s = 4 * abs(x - 0.5) - 1
                case .noise:
                    seed = seed &* 1103515245 &+ 12345
                    s = Double((seed >> 16) & 0x7fff) / 16384 - 1
                }
                let attack = min(1, Double(i) / (0.004 * rate))
                out.append(Float(s * attack * exp(-n.decay * p * n.dur * 4) * 0.3))
            }
        }
        return out
    }

    static func wav(_ samples: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
        return d
    }
}

/// Creature voices built from a buzzy source (sawtooth + noise) run through vowel
/// formant filters, with a pitch contour per call. Nothing is sampled from any game.
enum Voices {
    struct Call {
        var dur: Double
        var pitch: [Double]                 // contour, Hz, spread over the call
        var formants: [[Double]]            // vowel(s), interpolated over the call
        var noise = 0.1                     // breath / rasp
        var vibrato = (rate: 5.0, depth: 0.0)
        var tremolo = (rate: 0.0, depth: 0.0)
        var gain = 1.0
    }

    static func has(_ pet: PetKind) -> Bool { !calls(pet, pitch: 1).isEmpty }

    static func calls(_ pet: PetKind, pitch k: Double) -> [Call] {
        // Vowels as formant frequency pairs.
        let ee = [300.0, 2300], ah = [750.0, 1200], oo = [350.0, 800], uh = [600.0, 1000], mm = [250.0, 1800], eh = [550.0, 1800]
        switch pet {
        case .villager:
            return [Call(dur: 0.22, pitch: [190 * k, 150 * k], formants: [mm], noise: 0.05, vibrato: (7, 0.03)),
                    Call(dur: 0.26, pitch: [210 * k, 230 * k, 160 * k], formants: [mm, ah, uh], noise: 0.05, vibrato: (7, 0.04))]
        case .warden:
            return [Call(dur: 0.12, pitch: [48 * k, 40 * k], formants: [oo], noise: 0.2, gain: 1.4),          // heartbeat
                    Call(dur: 0.12, pitch: [48 * k, 40 * k], formants: [oo], noise: 0.2, gain: 1.2),
                    Call(dur: 0.9, pitch: [62 * k, 70 * k, 48 * k], formants: [uh, oo], noise: 0.55, vibrato: (4, 0.05), tremolo: (22, 0.6), gain: 1.3)]
        case .zombie:
            return [Call(dur: 0.85, pitch: [115 * k, 95 * k, 80 * k], formants: [uh, oo], noise: 0.25, vibrato: (5, 0.07), tremolo: (9, 0.25))]
        case .wolf:
            return k > 1.05
                ? [Call(dur: 0.9, pitch: [420 * k, 720 * k, 640 * k, 480 * k], formants: [oo, uh, oo], noise: 0.05, vibrato: (6, 0.02))] // howl
                : [Call(dur: 0.11, pitch: [560 * k, 330 * k], formants: [ah], noise: 0.3, gain: 1.2),
                   Call(dur: 0.11, pitch: [600 * k, 340 * k], formants: [ah], noise: 0.3, gain: 1.2)]                              // arf arf
        case .cat:
            return [Call(dur: 0.6, pitch: [520 * k, 820 * k, 700 * k, 440 * k], formants: [ee, ah, oo], noise: 0.06, vibrato: (6, 0.02))]
        case .pig:
            return [Call(dur: 0.16, pitch: [210 * k, 160 * k], formants: [[400, 1900]], noise: 0.3),
                    Call(dur: 0.14, pitch: [230 * k, 170 * k], formants: [[400, 1900]], noise: 0.3)]
        case .cow:
            return [Call(dur: 0.95, pitch: [125 * k, 120 * k, 105 * k], formants: [mm, oo, uh], noise: 0.12, vibrato: (4, 0.02))]
        case .sheep:
            return [Call(dur: 0.6, pitch: [330 * k, 300 * k], formants: [eh, ah], noise: 0.08, vibrato: (11, 0.08))]
        case .chicken:
            return (0..<3).map { i in Call(dur: 0.07, pitch: [760 * k + Double(i) * 40, 520 * k], formants: [[900, 2100]], noise: 0.35) }
        case .creeper:
            return [Call(dur: 0.7, pitch: [1], formants: [[4200, 7000]], noise: 1.0, gain: 0.7)]                                    // fuse hiss
        case .herobrine:
            return [Call(dur: 1.0, pitch: [72 * k, 66 * k], formants: [oo], noise: 0.08, vibrato: (0.7, 0.04), gain: 1.1)]
        case .steve, .notch:
            return [Call(dur: 0.16, pitch: [150 * k, 115 * k], formants: [uh, oo], noise: 0.15)]
        case .alex:
            return [Call(dur: 0.16, pitch: [240 * k, 185 * k], formants: [eh, uh], noise: 0.12)]
        case .fox:
            return [Call(dur: 0.14, pitch: [900 * k, 1250 * k, 1000 * k], formants: [ee], noise: 0.25)]
        case .bee:
            return [Call(dur: 0.5, pitch: [230 * k, 245 * k, 225 * k], formants: [[500, 1500]], noise: 0.1, tremolo: (30, 0.4), gain: 0.8)]
        case .axolotl:
            return [Call(dur: 0.08, pitch: [1200 * k, 1500 * k], formants: [ee], noise: 0.05),
                    Call(dur: 0.1, pitch: [1250 * k, 1600 * k], formants: [ee], noise: 0.05)]
        case .grassBlock, .classic:
            return []
        }
    }

    static func samples(_ pet: PetKind, pitch k: Double) -> [Float] {
        let rate = SoundFX.rate
        var out: [Float] = []
        var seed: UInt32 = 0xBEEF
        for call in calls(pet, pitch: k) {
            let n = Int(call.dur * rate)
            var phase = 0.0
            // Two parallel resonators per vowel, state per filter.
            var y1 = [0.0, 0.0], y2 = [0.0, 0.0]
            for i in 0..<n {
                let p = Double(i) / Double(max(n - 1, 1))
                let f0 = interp(call.pitch, p) * (1 + call.vibrato.depth * sin(2 * .pi * call.vibrato.rate * Double(i) / rate))
                phase += f0 / rate
                let saw = 2 * (phase - floor(phase)) - 1
                seed = seed &* 1103515245 &+ 12345
                let noise = Double((seed >> 16) & 0x7fff) / 16384 - 1
                let src = saw * (1 - call.noise) + noise * call.noise
                let vowel = interpVowel(call.formants, p)
                var s = 0.0
                for j in 0..<2 {
                    let bw = j == 0 ? 90.0 : 140.0
                    let r = exp(-.pi * bw / rate)
                    let b1 = 2 * r * cos(2 * .pi * vowel[j] / rate), b2 = -r * r
                    let y = (1 - r) * src + b1 * y1[j] + b2 * y2[j]
                    y2[j] = y1[j]; y1[j] = y
                    s += y * (j == 0 ? 1.0 : 0.6)
                }
                let env = min(1, p / 0.08) * min(1, (1 - p) / 0.2)
                let trem = 1 - call.tremolo.depth * 0.5 * (1 + sin(2 * .pi * call.tremolo.rate * Double(i) / rate))
                out.append(Float(s * env * trem * call.gain * 2.2))
            }
            out += [Float](repeating: 0, count: Int(0.06 * rate))
        }
        // Normalize so every voice sits at a similar loudness.
        let peak = out.map { abs($0) }.max() ?? 0
        if peak > 0 { out = out.map { $0 / peak * 0.8 } }
        return out
    }

    private static func interp(_ pts: [Double], _ p: Double) -> Double {
        guard pts.count > 1 else { return pts.first ?? 0 }
        let x = p * Double(pts.count - 1)
        let i = min(Int(x), pts.count - 2)
        return pts[i] + (pts[i + 1] - pts[i]) * (x - Double(i))
    }

    private static func interpVowel(_ vs: [[Double]], _ p: Double) -> [Double] {
        [interp(vs.map { $0[0] }, p), interp(vs.map { $0[1] }, p)]
    }
}
