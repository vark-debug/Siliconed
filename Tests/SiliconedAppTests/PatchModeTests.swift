// **The 「移除」/「重绘」 branch and the paste switch** (`RemoteControl+Add.swift`): the command line's
// `--mode`, the presets that imply it, and `--paste` / `--no-paste` (`--crop-only`).
//
// What these tests keep:
//
// - with a mask and no `--mode` / preset, the prompt reads the branch (`PatchBranch`, the GUI's
//   rule): a removal sentence is `.remove` (tinted, remove LoRA 1.0), another sentence is `.redraw`
//   (no tint, redraw LoRA 0.48); an empty prompt is remove's;
// - `--mode` is the explicit override: it wins over the prompt's reading, and over a preset;
// - a preset implies the mode, and `--mode` with the other branch's preset is refused, never
//   silently overridden;
// - `--no-paste` and `--crop-only` are one switch, and `--paste` against them is refused;
// - `--mode` and the paste switches go with `--mask`, like the rest of the patch.

import AppKit
import Siliconed
import XCTest
@testable import SiliconedApp

@MainActor
final class PatchModeTests: XCTestCase {
    private func control() -> RemoteControl {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PatchModeTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RemoteControl(app: AppState(library: Library(root: root)))
    }

    private func parse(_ arguments: [String]) throws -> RemoteControl.RenderOrder {
        try control().parse(arguments)
    }

    private func refusal(_ arguments: [String], _ code: String, line: UInt = #line) {
        XCTAssertThrowsError(try parse(arguments), line: line) { error in
            guard let refusal = error as? RemoteControl.Refusal else { return XCTFail("\(error)", line: line) }
            XCTAssertEqual(refusal.code, code, refusal.message, line: line)
        }
    }

    /// **The prompt picks the branch when neither `--mode` nor a preset does**: a removal sentence is
    /// the remove branch — tinted, the remove LoRA at 1.0 — and any other sentence is redraw, the
    /// redraw LoRA at 0.48. The mode and the LoRA are one reading, not two.
    func testAPromptPicksTheBranchWithoutAMode() throws {
        let remove = try parse(["--image", "photo.png", "--mask", "mask.png", "remove the lamp"])
        XCTAssertEqual(remove.mode, .remove)
        XCTAssertEqual(remove.loras.count, 1, "the branch's preset alone")
        XCTAssertEqual(remove.loras.first?.name, PatchLoRA.remove.fileName)
        XCTAssertEqual(try XCTUnwrap(remove.loras.first?.strength), PatchLoRA.remove.strength)

        let redraw = try parse(["--image", "photo.png", "--mask", "mask.png", "make it a red jacket"])
        XCTAssertEqual(redraw.mode, .redraw)
        XCTAssertEqual(redraw.loras.count, 1)
        XCTAssertEqual(redraw.loras.first?.name, PatchLoRA.redraw.fileName)
        XCTAssertEqual(try XCTUnwrap(redraw.loras.first?.strength), PatchLoRA.redraw.strength)
    }

    /// **A removal that continues is still a removal** — the first group's sentences.
    func testARemovalThatContinuesStaysRemove() throws {
        let d = try parse(["--image", "photo.png", "--mask", "mask.png",
                           "remove the cup, then rebuild the table around it"])
        XCTAssertEqual(d.mode, .remove)
        XCTAssertEqual(d.loras.map(\.name), [PatchLoRA.remove.fileName])
    }

    /// **`--mode` is the explicit override**: it wins over what the prompt would have read, both ways.
    func testAnExplicitModeOverridesThePromptsReading() throws {
        let forcedRemove = try parse(["--image", "photo.png", "--mask", "mask.png",
                                      "--mode", "remove", "make it a red jacket"])
        XCTAssertEqual(forcedRemove.mode, .remove)
        XCTAssertEqual(forcedRemove.loras.map(\.name), [PatchLoRA.remove.fileName])

        let forcedRedraw = try parse(["--image", "photo.png", "--mask", "mask.png",
                                      "--mode", "redraw", "remove the lamp"])
        XCTAssertEqual(forcedRedraw.mode, .redraw)
        XCTAssertEqual(forcedRedraw.loras.map(\.name), [PatchLoRA.redraw.fileName])
    }

    /// **The default is the workflow's own**: no `--mode`, no preset — the crop tinted, the remove
    /// LoRA at 1.0, nothing else.
    func testRemoveIsTheDefaultMode() throws {
        let d = try parse(["--image", "photo.png", "--mask", "mask.png", "remove the lamp"])
        XCTAssertEqual(d.mode, .remove)
        XCTAssertEqual(d.paste, true, "the crop is pasted back by default")
        XCTAssertEqual(d.loras.count, 1, "the branch's preset alone")
        XCTAssertEqual(d.loras.first?.name, PatchLoRA.remove.fileName)
        XCTAssertEqual(try XCTUnwrap(d.loras.first?.strength), PatchLoRA.remove.strength)
    }

    /// **`--mode redraw`**: the same geometry, the other branch — the redraw LoRA at 0.48 and no
    /// remove LoRA; the crop's tint is the engine's (`Patch.tint`), from the same `mode`.
    func testRedrawModeWiresItsLoanAndNoRemove() throws {
        let d = try parse(["--image", "photo.png", "--mask", "mask.png", "--mode", "redraw", "make it a jacket"])
        XCTAssertEqual(d.mode, .redraw)
        XCTAssertEqual(d.loras.count, 1)
        XCTAssertEqual(d.loras.first?.name, PatchLoRA.redraw.fileName)
        XCTAssertEqual(try XCTUnwrap(d.loras.first?.strength), PatchLoRA.redraw.strength)
    }

    /// A preset names its branch: `--lora redraw` alone is redraw, with the preset wired once — the
    /// implied preset is not added beside it.
    func testAPresetImpliesTheModeWithoutStackingTwice() throws {
        let d = try parse(["--image", "photo.png", "--mask", "mask.png", "--lora", "redraw", "make it a jacket"])
        XCTAssertEqual(d.mode, .redraw)
        XCTAssertEqual(d.loras.map(\.name), [PatchLoRA.redraw.fileName])
    }

    /// **A preset's own installed file name is the preset under `--mask`**: `--lora
    /// "Qwen2.1 一致性无偏移_GH_V1.0"` selects the redraw branch at 0.48 — never the default remove
    /// branch with the redraw LoRA stacked beside its remove preset. A path to the file reads the same.
    func testAPresetsFileNameIsThePresetUnderAMask() throws {
        let redraw = try parse(["--image", "photo.png", "--mask", "mask.png",
                                "--lora", PatchLoRA.redraw.fileName, "make it a jacket"])
        XCTAssertEqual(redraw.mode, .redraw)
        XCTAssertEqual(redraw.loras.map(\.name), [PatchLoRA.redraw.fileName], "one LoRA, the preset's")
        XCTAssertEqual(redraw.loras.first?.strength, PatchLoRA.redraw.strength, "the workflow's 0.48")

        let remove = try parse(["--image", "photo.png", "--mask", "mask.png",
                                "--lora", PatchLoRA.remove.fileName])
        XCTAssertEqual(remove.mode, .remove)
        XCTAssertEqual(remove.loras.map(\.name), [PatchLoRA.remove.fileName])
        XCTAssertEqual(remove.loras.first?.strength, PatchLoRA.remove.strength)

        let byPath = try parse(["--image", "photo.png", "--mask", "mask.png",
                                "--lora", "/tmp/\(PatchLoRA.redraw.fileName).lora.silicon", "x"])
        XCTAssertEqual(byPath.mode, .redraw)
        XCTAssertEqual(byPath.loras.first?.strength, PatchLoRA.redraw.strength)

        // The two files are the two branches: refused, as `--lora remove --lora redraw` is.
        refusal(["--image", "photo.png", "--mask", "mask.png",
                 "--lora", PatchLoRA.remove.fileName, "--lora", PatchLoRA.redraw.fileName, "x"], "mode")
        // A strength typed beside a preset's file would be dropped by the preset: refused, like
        // `--lora redraw:0.3`.
        refusal(["--image", "photo.png", "--mask", "mask.png",
                 "--lora", "\(PatchLoRA.redraw.fileName):0.3", "x"], "lora")
    }

    /// Without a mask the same name stays the LoRA the user named, strength and all — the CLI's
    /// behaviour is unchanged there (`--mask` alone reads it as the preset).
    func testAPresetsFileNameStaysABareLoRAWithoutAMask() throws {
        let d = try parse(["--lora", PatchLoRA.redraw.fileName, "cat"])
        XCTAssertEqual(d.loras.map(\.name), [PatchLoRA.redraw.fileName])
        XCTAssertEqual(d.loras.first?.strength, 1, "the typed default, not the preset's 0.48")
        XCTAssertNil(d.mode, "no branch without a mask")
    }

    /// **No silent override**: the branch named by `--mode` and the preset named by `--lora` must
    /// agree; two presets exclude each other.
    func testContradictoryBranchesAreRefused() {
        refusal(["--image", "photo.png", "--mask", "mask.png", "--mode", "redraw", "--lora", "remove", "x"], "mode")
        refusal(["--image", "photo.png", "--mask", "mask.png", "--lora", "remove", "--lora", "redraw", "x"], "mode")
    }

    /// **`--no-paste` is `--crop-only`**: the same switch, two spellings — `paste` false; `--paste`
    /// is the default, said.
    func testNoPasteAndCropOnlyAreOneSwitch() throws {
        let noPaste = try parse(["--image", "photo.png", "--mask", "mask.png", "--no-paste", "x"])
        let cropOnly = try parse(["--image", "photo.png", "--mask", "mask.png", "--crop-only", "x"])
        let pasted = try parse(["--image", "photo.png", "--mask", "mask.png", "--paste", "x"])
        XCTAssertEqual(noPaste.paste, false)
        XCTAssertEqual(cropOnly.paste, false)
        XCTAssertEqual(noPaste.paste, cropOnly.paste, "one switch, two spellings")
        XCTAssertEqual(pasted.paste, true, "--paste says the default")
    }

    /// Two spellings that disagree are refused, not resolved by the last one winning.
    func testContradictoryPasteSwitchesAreRefused() {
        refusal(["--image", "photo.png", "--mask", "mask.png", "--paste", "--no-paste", "x"], "usage")
        refusal(["--image", "photo.png", "--mask", "mask.png", "--crop-only", "--paste", "x"], "usage")
    }

    /// The branch and the paste switch are the patch's: without `--mask` they would be no-ops.
    func testModeAndPasteGoWithMask() {
        refusal(["cat", "--mode", "redraw"], "usage")
        refusal(["cat", "--no-paste"], "usage")
        refusal(["cat", "--crop-only"], "usage")
    }

    /// An unknown branch is said, not guessed.
    func testAnUnknownModeIsRefused() {
        refusal(["--image", "photo.png", "--mask", "mask.png", "--mode", "inpaint", "x"], "usage")
    }

    /// **A mask may leave the prompt out; the branch decides.** `remove` keeps it empty here and
    /// `add` fills the workflow's sentence (`MaskPrompt.standard`); `redraw` refuses an empty one,
    /// a sentence the program cannot write; without a mask the prompt is still the render.
    func testAMaskMayLeaveThePromptOutButRedrawMayNot() throws {
        let remove = try parse(["--image", "photo.png", "--mask", "mask.png"])
        XCTAssertEqual(remove.prompt, "", "the remove branch fills it in, not the parser")
        XCTAssertEqual(remove.mode, .remove)

        let said = try parse(["--image", "photo.png", "--mask", "mask.png", ""])
        XCTAssertEqual(said.prompt, "", "an explicit empty positional reads the same")

        refusal(["--image", "photo.png", "--mask", "mask.png", "--mode", "redraw"], "prompt")
        refusal(["--image", "photo.png", "--mask", "mask.png", "--lora", "redraw"], "prompt")

        XCTAssertThrowsError(try parse(["--image", "photo.png"])) { error in
            guard let refusal = error as? RemoteControl.Refusal else { return XCTFail("\(error)") }
            XCTAssertEqual(refusal.code, "usage", "without a mask an empty prompt is still refused")
        }
    }
}
