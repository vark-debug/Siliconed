// **C6: the workflow's two GH LoRAs as presets.** The removal goes in at 1.0, the redraw at 0.48;
// the third GH LoRA (an outpainting branch) is not a preset — `--lora` refuses its name rather
// than ignoring it, and « Add » does not list it.

import Siliconed
import XCTest
@testable import SiliconedApp

final class PatchLoRATests: XCTestCase {
    private func card(_ nom: String, name: String) -> LoRACard {
        let path = "/tmp/\(name).lora.silicon"
        return LoRACard(header: ["kind": "lora", "cible": ["modele": "qwen-image-2.1"], "nom": nom],
                        path: path)!
    }

    /// The strengths the workflow's nodes used: removal 1, redraw 0.48.
    func testTheTwoPresetsPinTheWorkflowStrengths() {
        XCTAssertEqual(PatchLoRA.allCases, [.remove, .redraw])
        XCTAssertEqual(PatchLoRA.remove.strength, 1)
        XCTAssertEqual(PatchLoRA.redraw.strength, 0.48)
    }

    /// The names `--lora` takes, and the files they stand for, as the installed headers spell them.
    func testPresetNamesStandForTheInstalledLoRAs() {
        XCTAssertEqual(PatchLoRA.preset(named: "remove"), .remove)
        XCTAssertEqual(PatchLoRA.preset(named: "redraw"), .redraw)
        XCTAssertEqual(PatchLoRA.remove.fileName, "Qwen2.1_万物移除Remove_GH")
        XCTAssertEqual(PatchLoRA.redraw.fileName, "Qwen2.1 一致性无偏移_GH_V1.0")
    }

    /// **The third LoRA is refused, not silently ignored**: `expand` names no preset, and the CLI's
    /// branch turns that into a refusal.
    func testTheThirdLoRAsNameIsUnwired() {
        XCTAssertNil(PatchLoRA.preset(named: "expand"))
        XCTAssertTrue(PatchLoRA.isUnwired(named: "expand"))
        XCTAssertTrue(PatchLoRA.isUnwired(named: "扩图"))
        XCTAssertFalse(PatchLoRA.isUnwired(named: "remove"))
        XCTAssertFalse(PatchLoRA.isUnwired(named: "redraw"))
    }

    /// « Add » offers the presets only where their LoRAs are installed, and never the third.
    func testTheRackOffersTheInstalledPresetsAndNotTheThird() {
        let loras = [
            card("Qwen2.1_万物移除Remove_GH", name: "qwen2-1-remove-gh"),
            card("Qwen2.1 一致性无偏移_GH_V1.0", name: "qwen2-1-gh-v1-0"),
            card("Qwen2.1_扩图_GH_3750", name: "qwen2-1-outpaint")
        ]
        let presets = PatchLoRA.presets(in: loras, for: PatchLoRA.workflow)

        XCTAssertEqual(presets.map(\.lora), [.remove, .redraw], "the third is not offered")
        XCTAssertEqual(presets.map(\.lora.strength), [1, 0.48])
        XCTAssertEqual(presets.map(\.card.path),
                       ["/tmp/qwen2-1-remove-gh.lora.silicon", "/tmp/qwen2-1-gh-v1-0.lora.silicon"])
    }

    /// Another model's rack keeps its LoRA list as it was: these presets are the workflow's.
    func testAnotherModelGetsNoPresets() {
        let loras = [card("Qwen2.1_万物移除Remove_GH", name: "qwen2-1-remove-gh")]
        XCTAssertTrue(PatchLoRA.presets(in: loras, for: "z-image").isEmpty)
    }
}
