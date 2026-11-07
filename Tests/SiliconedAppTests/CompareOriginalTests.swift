// **The bar's curtain button** (`SceneView.swift`, `AppState.canCompareOriginal`): an image against
// the one it was made from. These tests read the condition the button is drawn by, and the curtain it
// opens — no model, no render.
//
// What they keep:
//
// - an edit (image 1 among its references) still offers its original, as before;
// - a 「移除」 patch that pastes its crop back offers the image it edited (`Entry.start`), which the
//   render reads through the crop and not as a reference — the button that went missing;
// - a plain img2img offers the image it started from;
// - a crop-only patch offers nothing: its entry is the crop, not the original's composition;
// - a text-to-image offers nothing: no button without an original to lay under it.

import AppKit
import Siliconed
import XCTest
@testable import SiliconedApp

@MainActor
final class CompareOriginalTests: XCTestCase {
    private func form() -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CompareOriginalTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppState(library: Library(root: root))
    }

    private func picture(_ width: Int, _ height: Int, name: String) -> ReferenceImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = context.makeImage()!
        return ReferenceImage(source: .image(cg),
                              vignette: NSImage(cgImage: cg, size: NSSize(width: width, height: height)),
                              name: name, width: width, height: height)
    }

    private func onePixel() -> CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func settings(patch: Patch.Settings? = nil, references: Int = 0) -> RenderSettings {
        var s = RenderSettings(identifier: "qwen-image-2.1", modelName: "Qwen-Image-2.1", prompt: "a cat",
                               format: RecommendedFormat(512, 512), steps: 9, loras: [], references: references)
        s.patch = patch
        return s
    }

    private func entry(_ settings: RenderSettings, references: [ReferenceImage] = [],
                       start: ReferenceImage? = nil, width: Int = 512, height: Int = 512) -> Entry {
        Entry(ordinal: 1, job: 1, png: Data(), vignette: onePixel(), width: width, height: height, seed: 1,
              timings: .init(), footprints: .init(), evaluations: 0, settings: settings, metadata: [:],
              references: references, start: start)
    }

    /// The curtain's own decode is off the main thread: wait for it, as the canvas does.
    private func waitForOriginal(_ app: AppState) async -> CGImage? {
        for _ in 0..<50 {
            if let image = app.original?.image { return image }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    /// **An ordinary edit keeps its curtain**: image 1, laid under the edited image.
    func testAnEditShowsItsImageOne() async {
        let app = form()
        let image1 = picture(512, 512, name: "image 1")
        let e = entry(settings(references: 1), references: [image1])
        app.history = [e]

        XCTAssertTrue(app.canCompareOriginal(e), "the bar draws the button: image 1 is the original")
        app.comparesOriginal = true
        let decoded = await waitForOriginal(app)
        XCTAssertNotNil(decoded, "the original decodes")
        XCTAssertTrue(app.showsOriginal, "and the curtain is what the canvas shows")
    }

    /// **A logo removal (a patch pasted back) has its original too**: `Entry.start` is the image it
    /// edited — the render read it through the crop, not as a reference, so `references` is empty.
    func testAPastedPatchShowsTheImageItEdited() async {
        let app = form()
        let source = picture(512, 512, name: "source.png")
        let e = entry(settings(patch: Patch.Settings()), start: source, width: 512, height: 512)
        app.history = [e]

        XCTAssertEqual(e.references.count, 0, "a patch reads image 1 through the crop")
        XCTAssertNotNil(app.comparisonStart(e))
        XCTAssertTrue(app.canCompareOriginal(e), "the button the mask path had lost")
        app.comparesOriginal = true
        let decoded = await waitForOriginal(app)
        XCTAssertNotNil(decoded, "the image it edited decodes, under the pasted result")
    }

    /// **Normal generation keeps the bar it had**: a start image without a patch is not newly made
    /// comparable — the curtain is the patch path's original, not a button invented here.
    func testAPlainImg2imgKeepsItsBarAsItWas() async {
        let app = form()
        var s = settings()
        s.strength = 0.6
        let e = entry(s, start: picture(512, 512, name: "start.png"))
        app.history = [e]

        XCTAssertNil(app.comparisonStart(e), "only a pasted patch reads its start")
        XCTAssertFalse(app.canCompareOriginal(e))
    }

    /// **`--crop-only` keeps the crop alone**: it is not the original's composition, so no curtain.
    func testACropOnlyPatchShowsNoOriginal() async {
        let app = form()
        var patch = Patch.Settings()
        patch.paste = false
        let e = entry(settings(patch: patch), start: picture(512, 512, name: "source.png"))
        app.history = [e]

        XCTAssertNil(app.comparisonStart(e), "the entry is the crop")
        XCTAssertFalse(app.canCompareOriginal(e), "no like-for-like original: no button")
        app.comparesOriginal = true
        let decoded = await waitForOriginal(app)
        XCTAssertNil(decoded)
        XCTAssertFalse(app.showsOriginal)
    }

    /// **A text-to-image keeps no button**: nothing to lay under it.
    func testATextToImageShowsNoButton() async {
        let app = form()
        let e = entry(settings())
        app.history = [e]

        XCTAssertFalse(app.canCompareOriginal(e))
        app.comparesOriginal = true
        let decoded = await waitForOriginal(app)
        XCTAssertNil(decoded)
        XCTAssertFalse(app.showsOriginal)
    }
}
