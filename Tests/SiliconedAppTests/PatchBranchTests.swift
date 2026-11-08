import Siliconed
import XCTest
@testable import SiliconedApp

/// **The prompt's own reading** (`PatchBranch.mode`): a literal removal table, not a similarity
/// score. Empty is remove (the mask's sentence); a non-negated removal verb anywhere is remove; any
/// other sentence — `change X into Y`, `make it Y`, `replace X with Y`, or no verb at all — is the
/// redraw default.
final class PatchBranchTests: XCTestCase {
    func testAnEmptyPromptIsTheRemoveBranch() {
        XCTAssertEqual(PatchBranch.mode(for: ""), .remove)
        XCTAssertEqual(PatchBranch.mode(for: "  \n\t "), .remove, "whitespace is empty")
    }

    func testTheRemovalVerbsReadRemove() {
        for prompt in ["remove the lamp", "erase the logo", "delete the watermark", "take out the pole",
                       "clean up the background", "get rid of the wires", "wipe out the text",
                       "eliminate the glare", "移除左侧的路人", "把电线擦掉", "删除水印", "去除背景里的人群"] {
            XCTAssertEqual(PatchBranch.mode(for: prompt), .remove, prompt)
        }
    }

    func testADrawingSentenceReadsRedraw() {
        for prompt in ["change the sky into a sunset", "make it a red leather jacket",
                       "replace the sofa with a wooden bench", "turn the wall into glass",
                       "把天空换成晚霞", "把这个区域画成木地板", "a red jacket"] {
            XCTAssertEqual(PatchBranch.mode(for: prompt), .redraw, prompt)
        }
    }

    /// **A removal that continues or rebuilds is still a removal**: the first group's own sentences.
    func testARemovalThatContinuesStaysRemove() {
        for prompt in ["remove the cup and continue the room's style",
                       "remove the pole, then rebuild the wall behind it",
                       "移除桌上的杯子然后继续生成房间"] {
            XCTAssertEqual(PatchBranch.mode(for: prompt), .remove, prompt)
        }
    }

    /// A removal said *not* is not one: `do not`, `don't`, `without`, `不要`.
    func testANegatedRemovalReadsRedraw() {
        for prompt in ["do not remove the lamp, make it blue", "don't erase the logo",
                       "without removing the tree, add flowers", "不要删除那个人，把他换成剪影"] {
            XCTAssertEqual(PatchBranch.mode(for: prompt), .redraw, prompt)
        }
    }

    /// A removal verb inside a longer word is not the verb (`remover`).
    func testAWordInsideAnotherWordIsNotASignal() {
        XCTAssertEqual(PatchBranch.mode(for: "the remover tool stays"), .redraw)
    }
}
