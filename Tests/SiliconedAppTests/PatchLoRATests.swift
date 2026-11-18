// **C6: the workflow's GH LoRAs as presets.** The removal goes in at 1.0, the redraw at 0.48, the
// expand at 0.7 — the third GH LoRA, the 「扩图」 workflow's own, carries no mask branch and is
// refused beside `--mask` rather than silently stacked. Names outside the list (`outpaint`, `扩图`)
// stand for no preset: `--lora` reads them as a LoRA's own name and refuses them as unfound.

import Siliconed
import XCTest
@testable import SiliconedApp

final class PatchLoRATests: XCTestCase {
    private func card(_ nom: String, name: String) -> LoRACard {
        let path = "/tmp/\(name).lora.silicon"
        return LoRACard(header: ["kind": "lora", "cible": ["modele": "qwen-image-2.1"], "nom": nom],
                        path: path)!
    }

    /// The strengths the workflow's nodes used: removal 1, redraw 0.48, expand 0.7.
    func testTheThreePresetsPinTheWorkflowStrengths() {
        XCTAssertEqual(PatchLoRA.allCases, [.remove, .redraw, .expand])
        XCTAssertEqual(PatchLoRA.remove.strength, 1)
        XCTAssertEqual(PatchLoRA.redraw.strength, 0.48)
        XCTAssertEqual(PatchLoRA.expand.strength, 0.7)
    }

    /// The names `--lora` takes, and the files they stand for, as the installed headers spell them.
    func testPresetNamesStandForTheInstalledLoRAs() {
        XCTAssertEqual(PatchLoRA.preset(named: "remove"), .remove)
        XCTAssertEqual(PatchLoRA.preset(named: "redraw"), .redraw)
        XCTAssertEqual(PatchLoRA.preset(named: "expand"), .expand)
        XCTAssertEqual(PatchLoRA.remove.fileName, "Qwen2.1_万物移除Remove_GH")
        XCTAssertEqual(PatchLoRA.redraw.fileName, "Qwen2.1 一致性无偏移_GH_V1.0")
        XCTAssertEqual(PatchLoRA.expand.fileName, "Qwen2.1_扩图_GH_3750")
    }

    /// **A preset takes no strength** (`--lora expand:0.5` is refused, as remove and redraw's are):
    /// each is a `PatchLoRA`, and the parse refuses a strength beside any of them.
    func testEveryPresetRefusesAStrengthSuffix() {
        for preset in PatchLoRA.allCases {
            XCTAssertNotNil(PatchLoRA.preset(named: preset.rawValue), preset.rawValue)
        }
    }

    /// **The expand preset is no mask branch**: the two mask presets carry their `Patch.Mode`, the
    /// expand one carries none — its workflow has no mask, its canvas is the model's image 1 whole.
    func testTheExpandPresetCarriesNoMaskBranch() {
        XCTAssertEqual(PatchLoRA.remove.mode, .remove)
        XCTAssertEqual(PatchLoRA.redraw.mode, .redraw)
        XCTAssertNil(PatchLoRA.expand.mode)
        XCTAssertEqual(PatchLoRA.preset(for: .remove), .remove)
        XCTAssertEqual(PatchLoRA.preset(for: .redraw), .redraw)
    }

    /// **The names that stand for no preset**: `outpaint` and `扩图` are aliases of nothing — read as
    /// a LoRA's own name, they come back unfound, never silently wired.
    func testTheUnwiredNamesStandForNoPreset() {
        XCTAssertNil(PatchLoRA.preset(named: "outpaint"))
        XCTAssertNil(PatchLoRA.preset(named: "扩图"))
        XCTAssertFalse(PatchLoRA.allCases.contains { $0.fileName.lowercased().contains("outpaint") })
    }

    /// « Add » offers the presets where their LoRAs are installed — the expand one among them, at its
    /// own card.
    func testTheRackOffersTheInstalledPresets() {
        let loras = [
            card("Qwen2.1_万物移除Remove_GH", name: "qwen2-1-remove-gh"),
            card("Qwen2.1 一致性无偏移_GH_V1.0", name: "qwen2-1-gh-v1-0"),
            card("Qwen2.1_扩图_GH_3750", name: "qwen2-1-outpaint")
        ]
        let presets = PatchLoRA.presets(in: loras, for: PatchLoRA.workflow)

        XCTAssertEqual(presets.map(\.lora), [.remove, .redraw, .expand])
        XCTAssertEqual(presets.map(\.lora.strength), [1, 0.48, 0.7])
        XCTAssertEqual(presets.map(\.card.path),
                       ["/tmp/qwen2-1-remove-gh.lora.silicon", "/tmp/qwen2-1-gh-v1-0.lora.silicon",
                        "/tmp/qwen2-1-outpaint.lora.silicon"])
    }

    /// A rack without the expand LoRA offers the two mask presets alone, never a preset without its
    /// card to resolve to.
    func testAMissingLoRAOffersNoPreset() {
        let loras = [
            card("Qwen2.1_万物移除Remove_GH", name: "qwen2-1-remove-gh"),
            card("Qwen2.1 一致性无偏移_GH_V1.0", name: "qwen2-1-gh-v1-0")
        ]
        XCTAssertEqual(PatchLoRA.presets(in: loras, for: PatchLoRA.workflow).map(\.lora), [.remove, .redraw])
    }

    /// The library can hold one LoRA twice under one `nom` (an import that kept both files): the
    /// preset still resolves to one card — the smaller path — where a bare name would designate two
    /// and `Library.lora` would answer none.
    func testAPresetResolvesPastADuplicatedName() {
        let loras = [
            card("Qwen2.1 一致性无偏移_GH_V1.0", name: "qwen2-1-gh-v1-0"),
            card("Qwen2.1 一致性无偏移_GH_V1.0", name: "qwen2-1-gh-v1-0-2")
        ]
        XCTAssertEqual(PatchLoRA.card(for: .redraw, in: loras)?.path,
                       "/tmp/qwen2-1-gh-v1-0.lora.silicon")
        XCTAssertEqual(PatchLoRA.presets(in: loras, for: PatchLoRA.workflow).map(\.card.path),
                       ["/tmp/qwen2-1-gh-v1-0.lora.silicon"])
    }

    /// Another model's rack keeps its LoRA list as it was: these presets are the workflow's.
    func testAnotherModelGetsNoPresets() {
        let loras = [card("Qwen2.1_万物移除Remove_GH", name: "qwen2-1-remove-gh")]
        XCTAssertTrue(PatchLoRA.presets(in: loras, for: "z-image").isEmpty)
    }
}
