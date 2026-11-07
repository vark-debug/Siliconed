// **The Qwen-Image-2.1 workflow's two GH LoRAs**, as presets: the removal at 1.0, the redraw at 0.48.
// The names below are the `nom` their installed `.lora.silicon` headers carry, checked against
// `~/Library/Application Support/Siliconed/store`.
//
// The workflow's third GH LoRA (`Qwen2.1_扩图_GH_3750`, an outpainting branch) is not wired: its
// preset name is refused, never silently dropped, and « Add » does not list it.

import Foundation
import Siliconed

enum PatchLoRA: String, CaseIterable, Identifiable {
    case remove
    case redraw

    /// The model whose workflow these presets come from.
    static let workflow = "qwen-image-2.1"

    var id: String { rawValue }

    /// The LoRA's name without `.lora.silicon`, as its header's `nom` spells it.
    var fileName: String {
        switch self {
        case .remove: return "Qwen2.1_万物移除Remove_GH"
        case .redraw: return "Qwen2.1 一致性无偏移_GH_V1.0"
        }
    }

    /// The strength its node in the workflow used.
    var strength: Double {
        switch self {
        case .remove: return 1
        case .redraw: return 0.48
        }
    }

    /// **The branch this preset carries** (`Patch.Mode`): the remove LoRA goes with the tinted crop,
    /// the redraw LoRA with the untouched one.
    var mode: Patch.Mode {
        switch self {
        case .remove: return .remove
        case .redraw: return .redraw
        }
    }

    /// The preset a branch carries.
    static func preset(for mode: Patch.Mode) -> PatchLoRA {
        switch mode {
        case .remove: return .remove
        case .redraw: return .redraw
        }
    }

    /// The rack's « Add » entry: the preset, with the strength it pins.
    var title: String {
        switch self {
        case .remove: return String(localized: "Remove preset (1.0)")
        case .redraw: return String(localized: "Redraw preset (0.48)")
        }
    }

    /// A `--lora` name that designates a preset; `nil` for a LoRA's own name.
    static func preset(named name: String) -> PatchLoRA? {
        PatchLoRA(rawValue: name.lowercased())
    }

    /// The third GH LoRA's preset names: not part of this workflow, so `--lora` refuses them rather
    /// than ignoring them.
    static func isUnwired(named name: String) -> Bool {
        ["expand", "outpaint", "扩图"].contains(name.lowercased())
    }

    /// The presets this model's LoRAs offer, in order — only the workflow's model has them.
    static func presets(in loras: [LoRACard], for identifier: String) -> [PatchLoRAPreset] {
        guard identifier == workflow else { return [] }
        return allCases.compactMap { preset in
            card(for: preset, in: loras).map { PatchLoRAPreset(lora: preset, card: $0) }
        }
    }

    /// **The card a preset stands for**, if installed. By name — but the library may hold one LoRA
    /// twice under one `nom` (an import that kept both files): then the shorter path — the first
    /// file over its suffixed copy — so a preset resolves to one card rather than to a name that
    /// designates two.
    static func card(for preset: PatchLoRA, in loras: [LoRACard]) -> LoRACard? {
        let wanted = key(preset.fileName)
        let matches = loras.filter {
            key($0.rawName) == wanted || key(($0.path as NSString).lastPathComponent) == wanted
        }
        return matches.sorted { ($0.path.count, $0.path) < ($1.path.count, $1.path) }.first
    }

    /// `Qwen2.1 万物移除Remove GH`, `Qwen2.1_万物移除Remove_GH.lora.silicon`: the same key.
    private static func key(_ name: String) -> String {
        name.replacingOccurrences(of: ".lora.silicon", with: "")
            .replacingOccurrences(of: ".lora", with: "")
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
    }
}

/// A preset the model's installed LoRAs can carry: its own strength, the card to add.
struct PatchLoRAPreset: Identifiable {
    let lora: PatchLoRA
    let card: LoRACard
    var id: String { lora.id }
}

extension AppState {
    /// The workflow's presets, where the model's LoRAs are installed.
    var patchLoRAPresets: [PatchLoRAPreset] {
        PatchLoRA.presets(in: compatibleLoras, for: identifier)
    }
}
