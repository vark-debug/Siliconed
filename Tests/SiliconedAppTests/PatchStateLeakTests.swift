// **The 「移除」 path leaves nothing behind between jobs.**
//
// A real user, after one mask edit, saw the next plain text-to-image come out with the tinted crop's
// green and at the crop's size instead of the form's. The mask, the margins and the plan's size
// belonged to one job: they were staged in the form (`AppState.patchInput`, removed) and written
// back into `format` (`restoreSettings`). These tests keep them where they belong — in the job.

import AppKit
import Siliconed
import XCTest
@testable import SiliconedApp

@MainActor
final class PatchStateLeakTests: XCTestCase {
    /// A form with nothing on disk: the tests read the form and the jobs a click makes, never the
    /// library's models, so no map or weight is touched.
    private func form() -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SiliconedAppTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppState(library: Library(root: root))
    }

    /// A source of the 「移除」 path — only its size matters here, nothing is decoded.
    private func source(_ side: Int) -> ReferenceImage {
        ReferenceImage(source: .bytes(Data()), vignette: NSImage(size: NSSize(width: side, height: side)),
                       name: "source.png", width: side, height: side)
    }

    /// **A patch job's plan size is not written back into the form**: the settings a mask job keeps
    /// carry the crop's dimensions, and the form keeps the user's — otherwise the next ordinary
    /// render is the crop's size, the second symptom the user reported.
    func testAPatchJobsPlanSizeStaysOutOfTheForm() {
        let app = form()
        let chosen = RecommendedFormat(512, 512)
        app.format = chosen
        app.orientation = chosen.orientation

        var settings = RenderSettings(identifier: "qwen-image-2.1", modelName: "Qwen-Image-2.1", prompt: "a cat",
                                      format: RecommendedFormat(864, 512), steps: 9, loras: [], references: 0)
        settings.patch = Patch.Settings()

        app.restoreSettings(settings)   // what `silicontrol add --mask` and a redo put on the form

        XCTAssertEqual(app.format, chosen, "a mask's plan size must not become the form's format")
        XCTAssertEqual(app.orientation, chosen.orientation)
    }

    /// **Patch → text-to-image, two jobs**: the patch's sources and margins live in its job only; the
    /// job after it carries no patch field at all and renders at the form's format.
    func testThePlainJobAfterAPatchCarriesNoPatch() {
        let app = form()
        let chosen = RecommendedFormat(512, 512)
        app.format = chosen
        app.prompt = "a cat"

        let image = source(640)
        let mask = source(640)
        let margins = Patch.Settings(seededStart: false, paste: true)

        // t1: the 「移除」 path, at the crop's plan size.
        let patchJobs = app.renderJobs(seed: 1001, format: RecommendedFormat(864, 512),
                                       patch: (image, mask, margins),
                                       prompts: ["a cat"], edit: [])
        XCTAssertEqual(patchJobs.count, 1)
        XCTAssertEqual(patchJobs[0].settings.patch, margins, "the patch job keeps its margins")
        XCTAssertNotNil(patchJobs[0].patch, "the patch job keeps its two sources")
        XCTAssertEqual(patchJobs[0].settings.format, RecommendedFormat(864, 512))

        // The form takes what the patch job computed, as the remote control leaves it…
        app.restoreSettings(patchJobs[0].settings)

        // …t2: an ordinary render, from the form as it stands.
        let plainJobs = app.renderJobs(seed: 1002, format: app.format, patch: nil, prompts: ["a cat"], edit: [])
        XCTAssertEqual(plainJobs.count, 1)
        XCTAssertNil(plainJobs[0].settings.patch, "the second job must carry no patch settings")
        XCTAssertNil(plainJobs[0].patch, "the second job must carry no mask, hence no green tint")
        XCTAssertEqual(plainJobs[0].settings.format, chosen, "the second job renders at the form's format")
        XCTAssertEqual(plainJobs[0].references.count, 0)
    }
}
