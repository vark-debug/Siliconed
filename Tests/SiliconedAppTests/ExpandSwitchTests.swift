// **The 「扩图」 branch's switches** (`RemoteControl+Add.swift`): `--mode expand` without a mask,
// `--pad` and `--max-sample`, and the preset `--lora expand` implying the branch as the mask presets
// imply theirs.
//
// What these tests keep:
//
// - expand alone (no mask) builds the branch: the workflow's pads and ceiling left at their
//   defaults, the expand preset wired at 0.7, the prompt optional (the fixed sentence leads);
// - `--pad` reads four percents, floats included, 0–200; `--max-sample` walks the slider's steps;
// - the branch's contradictions refuse where the flags were typed: a mask beside it (`patch`), no
//   image (`usage`), a remove/redraw preset beside it (`mode`), the crop's and img2img's own
//   switches (`usage`);
// - `--pad` and `--max-sample` go with the branch alone: beside a mask `patch`, without one `usage`;
// - remove and redraw still need a mask, and an unknown mode is still refused.

import Siliconed
import XCTest
@testable import SiliconedApp

@MainActor
final class ExpandSwitchTests: XCTestCase {
    private func control() -> RemoteControl {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExpandSwitchTests-\(UUID().uuidString)")
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

    /// **Expand alone**: no mask, the branch on, the workflow's pads and sampling ceiling left at
    /// their defaults (`add` resolves them), the expand preset wired once at 0.7 — and no mask
    /// branch picked.
    func testExpandAloneBuildsTheBranchWithoutAMask() throws {
        let d = try parse(["--image", "photo.jpg", "--mode", "expand"])
        XCTAssertTrue(d.expandBranch)
        XCTAssertNil(d.pads, "the workflow's 30/30/0/0, resolved by add")
        XCTAssertNil(d.maximumSample, "the workflow's 2048, resolved by add")
        XCTAssertNil(d.mode, "no mask branch: expand is no Patch.Mode")
        XCTAssertEqual(d.prompt, "", "the fixed sentence carries an empty one")
        XCTAssertEqual(d.loras.map(\.name), [PatchLoRA.expand.fileName])
        XCTAssertEqual(try XCTUnwrap(d.loras.first?.strength), PatchLoRA.expand.strength)
    }

    /// The case reads as typed: `EXPAND` is the branch too, and a supplement is kept as typed — the
    /// engine leads with the fixed sentence (`Expand.prompt`).
    func testExpandTakesTheCaseAndKeepsThePrompt() throws {
        let d = try parse(["--image", "photo.jpg", "--mode", "EXPAND", "the beach continues, more waves"])
        XCTAssertTrue(d.expandBranch)
        XCTAssertEqual(d.prompt, "the beach continues, more waves")
    }

    /// **`--pad` reads four percents**, left,right,top,bottom, floats included.
    func testPadReadsFourPercents() throws {
        let d = try parse(["--image", "photo.jpg", "--mode", "expand", "--pad", "12.5,20,0,40"])
        let pads = try XCTUnwrap(d.pads)
        XCTAssertEqual(pads.left, 12.5)
        XCTAssertEqual(pads.right, 20)
        XCTAssertEqual(pads.top, 0)
        XCTAssertEqual(pads.bottom, 40)
    }

    /// **`--pad` out of range, or not four percents, is refused**, said — the range is the workflow's
    /// 0–200 (`Expand.Pads.range`).
    func testPadOutOfRangeOrUnreadableIsRefused() {
        refusal(["--image", "photo.jpg", "--mode", "expand", "--pad", "201,0,0,0"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--pad", "-1,0,0,0"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--pad", "30,30,0"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--pad", "30,30,0,0,0"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--pad", "a,b,c,d"], "usage")
    }

    /// **`--max-sample` takes the slider's steps**: 1024–3840, a multiple of 128.
    func testMaxSampleTakesTheSlidersSteps() throws {
        XCTAssertEqual(try parse(["--image", "photo.jpg", "--mode", "expand",
                                  "--max-sample", "1536"]).maximumSample, 1536)
        XCTAssertEqual(try parse(["--image", "photo.jpg", "--mode", "expand",
                                  "--max-sample", "3840"]).maximumSample, 3840)
        refusal(["--image", "photo.jpg", "--mode", "expand", "--max-sample", "1023"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--max-sample", "3968"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--max-sample", "2049"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--max-sample", "1100"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--max-sample", "wide"], "usage")
    }

    /// **A mask beside expand is refused** (`patch`): the mask's region is replaced, the expand's
    /// canvas keeps the image — either way the branch is named.
    func testExpandRefusesAMask() {
        refusal(["--image", "photo.jpg", "--mode", "expand", "--mask", "mask.png", "x"], "patch")
        refusal(["--image", "photo.jpg", "--lora", "expand", "--mask", "mask.png", "x"], "patch")
    }

    /// **Expand without an image**: nothing to grow — refused for what it is, as `--mode expand` and
    /// as `--lora expand` implying it.
    func testExpandWithoutAnImageIsRefused() {
        refusal(["--mode", "expand", "cat"], "usage")
        refusal(["--lora", "expand", "cat"], "usage")
    }

    /// **The expand preset goes alone**: remove and redraw are the mask's branches — by preset name
    /// or by installed file name, refused as a contradiction of branches (`mode`).
    func testExpandRefusesTheMaskPresets() {
        refusal(["--image", "photo.jpg", "--mode", "expand", "--lora", "remove", "x"], "mode")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--lora", "redraw", "x"], "mode")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--lora", PatchLoRA.redraw.fileName, "x"], "mode")
        refusal(["--image", "photo.jpg", "--lora", "expand", "--lora", "remove", "x"], "mode")
    }

    /// **A preset's strength is fixed** (`--lora expand:0.5` is refused, as remove and redraw's are):
    /// the generic preset rule, the expand branch inheriting it.
    func testTheExpandPresetRefusesAStrengthSuffix() {
        refusal(["--image", "photo.jpg", "--lora", "expand:0.5", "x"], "lora")
        refusal(["--image", "photo.jpg", "--lora", "\(PatchLoRA.expand.fileName):0.5", "x"], "lora")
    }

    /// **`--lora expand` implies the branch**, as `--lora remove` implies remove: the preset wired
    /// once, at 0.7 — the same order `--mode expand` builds. Its installed file name reads the same.
    func testLoraExpandImpliesTheBranch() throws {
        let d = try parse(["--image", "photo.jpg", "--lora", "expand"])
        XCTAssertTrue(d.expandBranch)
        XCTAssertEqual(d.loras.map(\.name), [PatchLoRA.expand.fileName])
        XCTAssertEqual(try XCTUnwrap(d.loras.first?.strength), PatchLoRA.expand.strength)

        let byFile = try parse(["--image", "photo.jpg", "--lora", PatchLoRA.expand.fileName])
        XCTAssertTrue(byFile.expandBranch)
        XCTAssertEqual(byFile.loras.map(\.name), [PatchLoRA.expand.fileName])
        XCTAssertEqual(try XCTUnwrap(byFile.loras.first?.strength), PatchLoRA.expand.strength)
    }

    /// **One start, one geometry**: the crop's margins, the img2img's strength, the edit's
    /// references and a typed format say another path — the canvas decides the format, the expand
    /// starts from noise. The patch's own opt-ins refuse without a mask already (`usage`).
    func testExpandRefusesTheOtherPathsSwitches() {
        refusal(["--image", "photo.jpg", "--mode", "expand", "--expand", "1.3,1.4,1.4,1.4", "x"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--max-side", "2560", "x"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--strength", "0.65", "x"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--ref", "dog.png", "x"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "x", "1024"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "x", "3:4@1K"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--seeded-start", "x"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--noise-mask", "x"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--crop-only", "x"], "usage")
        refusal(["--image", "photo.jpg", "--mode", "expand", "--no-paste", "x"], "usage")
    }

    /// **`--pad` and `--max-sample` go with the expand branch alone**: beside a mask the crop
    /// decides its own (`patch`), without the branch they would be no-ops (`usage`).
    func testPadAndMaxSampleGoWithTheExpandBranch() {
        refusal(["--image", "photo.jpg", "--mask", "mask.png", "--pad", "30,30,0,0", "x"], "patch")
        refusal(["--image", "photo.jpg", "--mask", "mask.png", "--max-sample", "2048", "x"], "patch")
        refusal(["cat", "--pad", "30,30,0,0"], "usage")
        refusal(["cat", "--max-sample", "2048"], "usage")
        refusal(["--image", "photo.jpg", "--pad", "30,30,0,0", "x"], "usage")
    }

    /// **The empty prompt is expand's and the mask's alone**: with the branch it is the fixed
    /// sentence's supplement (kept empty here — `add` fills nothing, the engine leads); without
    /// either branch it is still refused.
    func testTheEmptyPromptIsExpandAndMaskAlone() throws {
        XCTAssertEqual(try parse(["--image", "photo.jpg", "--mode", "expand", ""]).prompt, "")
        XCTAssertEqual(try parse(["--image", "photo.jpg", "--lora", "expand"]).prompt, "")
        XCTAssertThrowsError(try parse(["--image", "photo.jpg", ""])) { error in
            guard let refusal = error as? RemoteControl.Refusal else { return XCTFail("\(error)") }
            XCTAssertEqual(refusal.code, "usage")
        }
    }

    /// **A mask render that names the expand preset by its installed file name is refused** (`patch`),
    /// as `--lora expand` beside a mask is: the installed names are presets under a mask too, and
    /// the branch above refuses the mask beside the expand either way.
    func testAMaskRenderNamingTheExpandFileIsRefused() {
        refusal(["--image", "photo.png", "--mask", "mask.png", "--lora", PatchLoRA.expand.fileName, "x"], "patch")
    }

    /// The mask branches' old rules stand beside the new one: remove and redraw still need a mask,
    /// and an unknown mode is still refused, said.
    func testTheMaskBranchesAreUnchanged() {
        refusal(["cat", "--mode", "redraw"], "usage")
        refusal(["--image", "photo.jpg", "--mask", "mask.png", "--mode", "inpaint", "x"], "usage")
    }
}
