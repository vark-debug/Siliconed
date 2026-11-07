// **The 「移除」/「重绘」 branch and the paste switch** (`RemoteControl+Add.swift`): the command line's
// `--mode`, the presets that imply it, and `--paste` / `--no-paste` (`--crop-only`).
//
// What these tests keep:
//
// - `--mode` left out is `.remove`: the tinted crop and the remove LoRA at the workflow's 1.0;
// - `--mode redraw` is `.redraw`: no tint, the redraw LoRA at 0.48 — geometry unchanged;
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
}
