import XCTest
@testable import Siliconed

/// **The 「扩图」 path** (`Expand`): the grey canvas, the coefficients, the ÷32 plan, the stretched
/// render and the paste-back — the values here are the workflow's, to the pixel.
final class ExpandTests: XCTestCase {

    private func image(_ width: Int, _ height: Int, value: Float = 0) -> ImageRGB {
        ImageRGB(pixels: [Float](repeating: value, count: 3 * width * height), height: height, width: width)
    }

    /// **The canvas `孤海外补画板可视化` makes**: each pad is `round(percent × the image's own side)`,
    /// the border grey — (0, 0, 0) in the model's −1…1 RGB, the `#808080` of 0…255 — and the image's
    /// own pixels untouched where they sit.
    func testTheCanvasPadsTheImageWithGrey() {
        let original = image(1000, 700, value: 0.25)
        let canvas = Expand.canvas(image: original, pads: Expand.Pads(left: 30, right: 30, top: 0, bottom: 0))
        XCTAssertEqual(canvas.width, 1600, "1000 + round(0.30 × 1000) a side")
        XCTAssertEqual(canvas.height, 700, "no pad above or below")
        let plane = 1600 * 700
        for c in 0..<3 {
            XCTAssertEqual(canvas.pixels[c * plane + 350 * 1600 + 800], 0.25, "the image's (500, 350), channel \(c)")
            XCTAssertEqual(canvas.pixels[c * plane + 10 * 1600 + 10], 0, "the grey border, channel \(c)")
        }
        // `round`, not truncation: 0.30 × 1001 = 300.3 grows by 300.
        XCTAssertEqual(Expand.canvas(image: image(1001, 10),
                                     pads: Expand.Pads(left: 30, right: 0, top: 0, bottom: 0)).width, 1301)
    }

    /// **The canvas's 5120 cap**: a canvas whose long side passes it is scaled back under it, pads and
    /// image together — 9000×9000 lands on 5120×5120, the image's offset scaled with it.
    func testTheCanvasIsCappedAt5120() {
        let pads = Expand.Pads(left: 100, right: 100, top: 100, bottom: 100)
        let g = Expand.geometry(width: 3000, height: 3000, pads: pads)
        XCTAssertEqual(g.canvasWidth, 5120)
        XCTAssertEqual(g.canvasHeight, 5120)
        XCTAssertEqual(g.x, 1707, "round(3000 × 5120/9000)")
        XCTAssertEqual(g.imageWidth, 1706, "5120 − 1707 − 1707: the cap's rounding shaves a pixel")
        let canvas = Expand.canvas(image: image(3000, 3000, value: 0.25), pads: pads)
        XCTAssertEqual([canvas.width, canvas.height], [5120, 5120])
        let plane = 5120 * 5120
        for c in 0..<3 {
            XCTAssertEqual(canvas.pixels[c * plane + 2560 * 5120 + 2560], 0.25, accuracy: 1e-5,
                           "the image's centre, scaled with the canvas, channel \(c)")
            XCTAssertEqual(canvas.pixels[c * plane + 5 * 5120 + 5], 0, accuracy: 1e-6,
                           "the grey border, channel \(c)")
        }
    }

    /// **Node 39's coefficients**: a direction with no grey stays at 1.0; the worked example — an
    /// image 1024×1024 with the default 30 % pads either side makes a canvas 1638×1024, whose
    /// horizontal coefficient is (2/3 × 614) / 1024 + 1.
    func testTheCoefficientsAreNodeThirtyNines() {
        let none = Expand.coefficients(canvasWidth: 1024, canvasHeight: 1024, maskWidth: 1024, maskHeight: 1024)
        XCTAssertEqual([none.top, none.bottom, none.left, none.right], [1, 1, 1, 1], "no grey at all")
        let padded = Expand.coefficients(canvasWidth: 1638, canvasHeight: 1024, maskWidth: 1024, maskHeight: 1024)
        XCTAssertEqual(padded.top, 1.0, accuracy: 1e-12, "b == d: no grey above or below")
        XCTAssertEqual(padded.bottom, 1.0, accuracy: 1e-12)
        XCTAssertEqual(padded.left, 1.0 + (2.0 / 3.0 * 614.0) / 1024.0, accuracy: 1e-12)
        XCTAssertEqual(padded.right, padded.left, accuracy: 1e-12)
    }

    /// **The plan**: the canvas 1638×1024 keeps its long side whole (between the graph's 1024 floor
    /// and its 2048 slider), then node 5's `就近整除` rounds the fixed side to the **nearest** multiple
    /// (1638 → 1632) and the other follows the ratio before its own nearest rounding (1019 → 1024):
    /// 1632×1024, the shape the canvas's. The crop is the whole canvas; the coefficients are 1.0 on
    /// every axis — the mask marks the **expansion** (`孤海外补画板可视化`), so `GH_MaskCropV2`'s
    /// bounds are the canvas's own and the crop grows by nothing.
    func testThePlanSizesTheCanvas() throws {
        let plan = try Expand.plan(pads: Expand.Pads(), width: 1024, height: 1024)
        XCTAssertEqual(plan.crop, Patch.Crop(x: 307, y: 0, width: 1638, height: 1024))
        XCTAssertEqual([plan.width, plan.height], [1632, 1024], "nearest multiple of 1638, ratio kept")
        XCTAssertEqual(plan.width % 32, 0)
        XCTAssertEqual(plan.height % 32, 0)
        XCTAssertEqual(plan.coefficients.left, 1.0, accuracy: 1e-12, "the padded axis: mask bounds = canvas")
        XCTAssertEqual(plan.coefficients.right, 1.0, accuracy: 1e-12)
        XCTAssertEqual(plan.coefficients.top, 1.0, accuracy: 1e-12, "the unpadded axis: b == d")
        XCTAssertEqual(plan.coefficients.bottom, 1.0, accuracy: 1e-12)
        XCTAssertEqual(plan.pads, Expand.Pads())
        XCTAssertEqual(plan.imageOffset.x, 307)
        XCTAssertEqual(plan.imageOffset.y, 0)
        XCTAssertEqual(plan.imageWidth, 1024)
        XCTAssertEqual(plan.imageHeight, 1024)
        // The instance plan is the static one over the image's own dimensions.
        let expand = Expand(image: image(1024, 1024))
        XCTAssertEqual(try expand.plan(), plan)
    }

    /// **The 1024 floor cuts upward too**: a canvas 614×512 is scaled **up** to a long side of 1024
    /// before node 5's `就近整除` (`min(max(1024, 长边), a)`): the fixed side 1024, the other
    /// round(512 × 1024/614) = 854 then its nearest multiple — 864.
    func testASmallCanvasIsScaledUpTo1024() throws {
        let plan = try Expand.plan(pads: Expand.Pads(left: 10, right: 10, top: 0, bottom: 0), width: 512, height: 512)
        XCTAssertEqual(plan.crop.width, 614, "512 + round(0.10 × 512) a side")
        XCTAssertEqual([plan.width, plan.height], [1024, 864])
    }

    /// **The nearest rounding, against a floor's distortion**: a canvas 1180×1024 under the patch
    /// path's scheme lands on 1152×1024 and the paste-back stretches 1180/1152 — 2.4 %, the artefact
    /// the user saw. Node 5's `就近整除` keeps the fixed side at 1184 (its nearest multiple) and the
    /// other side at 1024: the render's shape the canvas's, the paste-back honest.
    func testTheNearestRoundingKeepsTheCanvasShape() throws {
        let plan = try Expand.plan(pads: Expand.Pads(left: 7.615, right: 7.615, top: 0, bottom: 0),
                                   width: 1024, height: 1024)
        XCTAssertEqual(plan.crop.width, 1180, "1024 + round(0.07615 × 1024) a side")
        XCTAssertEqual([plan.width, plan.height], [1184, 1024])
    }

    /// **What the plan refuses**: pads out of range, all four 0 (nothing to expand), a sampling
    /// ceiling that cannot reach the graph's 1024 floor, and a size whose short side falls under the
    /// patch path's 448 — said with its numbers.
    func testThePlanRefusesWhatItCannotRender() {
        XCTAssertThrowsError(try Expand.plan(pads: Expand.Pads(left: 0, right: 0, top: 0, bottom: 0),
                                             width: 1024, height: 1024)) {
            guard case .invalidPatch = $0 as? EngineError else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try Expand.plan(pads: Expand.Pads(left: 201), width: 1024, height: 1024)) {
            guard case .invalidPatch = $0 as? EngineError else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try Expand.plan(pads: Expand.Pads(), width: 1024, height: 1024, maximumSample: 960)) {
            guard let error = $0 as? EngineError, case .invalidPatch(let reason) = error else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("cannot reach"), reason)
        }
        // An image 1024×50 with 200 % above and below: a canvas 1024×250 that renders 1024×256.
        XCTAssertThrowsError(try Expand.plan(pads: Expand.Pads(left: 0, right: 0, top: 200, bottom: 200),
                                             width: 1024, height: 50)) {
            guard let error = $0 as? EngineError, case .invalidPatch(let reason) = error else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("1024×256"), reason)
        }
    }

    /// **What the model sees**: the canvas stretched exactly to the plan's size — the workflow's
    /// `拉伸`, no cover and no crop (`fitted` would cut the pads' edges away).
    func testTheRenderIsTheCanvasStretchedToThePlan() throws {
        let expand = Expand(image: image(1024, 1024, value: 0.25))
        let plan = try expand.plan()
        let rendered = expand.render(plan)
        XCTAssertEqual([rendered.width, rendered.height], [plan.width, plan.height])
        let plane = rendered.width * rendered.height
        for c in 0..<3 {
            XCTAssertEqual(rendered.pixels[c * plane + 500 * rendered.width + 10], 0, accuracy: 1e-6,
                           "the grey border, channel \(c)")
            XCTAssertEqual(rendered.pixels[c * plane + 500 * rendered.width + 400], 0.25, accuracy: 1e-6,
                           "the image's interior, channel \(c)")
        }
    }

    /// **The paste-back** (`GH_CropRestore` at the expand workflow's 3 / 3 / 1): the canvas comes back
    /// at its own size — bigger than the original —, the original's interior untouched inside it, and
    /// the border showing the render, not the grey the canvas was built with.
    func testTheCompositedImageIsTheCanvasWithTheOriginalInside() throws {
        let original = image(1024, 1024, value: 0.25)
        let expand = Expand(image: original)
        let plan = try expand.plan()
        // A synthetic render: the canvas itself — whose border here is grey — with another constant
        // painted over the border's outer band: the model's outpainting, imagined.
        let stretched = Expand.canvas(image: original, pads: plan.pads)
            .stretched(width: plan.width, height: plan.height)
        var pixels = stretched.pixels
        let plane = plan.width * plan.height
        for c in 0..<3 {
            for y in 0..<plan.height {
                for x in 0..<plan.width where x < 200 || x >= plan.width - 200 {
                    pixels[c * plane + y * plan.width + x] = 0.5
                }
            }
        }
        let out = expand.composited(ImageRGB(pixels: pixels, height: plan.height, width: plan.width), plan: plan)
        XCTAssertEqual([out.width, out.height], [plan.crop.width, plan.crop.height], "the canvas's size")
        let outPlane = out.width * out.height
        // The original's centre, preserved — a few pixels well inside the image region. The 8-bit
        // round trip of the paste (`tensor2pil`'s uint8, as the mask path's takes) keeps them to a
        // hundredth of a level.
        for (x, y) in [(819, 512), (500, 300), (1100, 700)] {
            for c in 0..<3 {
                XCTAssertEqual(out.pixels[c * outPlane + y * out.width + x], 0.25, accuracy: 0.01,
                               "the original at (\(x), \(y)), channel \(c)")
            }
        }
        // The border, the render's own — 0.5, not the grey (0) the canvas carried there.
        for (x, y) in [(50, 512), (1500, 512)] {
            for c in 0..<3 {
                XCTAssertEqual(out.pixels[c * outPlane + y * out.width + x], 0.5, accuracy: 0.01,
                               "the outpainted border at (\(x), \(y)), channel \(c)")
            }
        }
        // **No smear past the image's edge**: just outside the original's rectangle the render
        // stands alone — the keep-mask is the ring grown *inward*, so the band never reaches past
        // the edge and no pixel is read outside the image's bounds (the old paste clamped its read
        // there and stretched the bordermost pixel across the whole feather band).
        for (x, y) in [(300, 512), (1340, 512)] {
            for c in 0..<3 {
                XCTAssertEqual(out.pixels[c * outPlane + y * out.width + x], 0, accuracy: 0.01,
                               "the render's own grey just past the edge at (\(x), \(y)), channel \(c)")
            }
        }
    }

    /// **The prompt the graph hands the model** (nodes 33 + 32): the fixed sentence leads, the user's
    /// words appended with an empty separator, an empty supplement left with the sentence alone — and
    /// a prompt that already leads with it comes back unchanged.
    func testThePromptLeadsWithTheFixedSentence() {
        XCTAssertEqual(Expand.prompt(""), Expand.promptPrefix)
        XCTAssertEqual(Expand.prompt("  more waves  "), Expand.promptPrefix + "more waves")
        XCTAssertEqual(Expand.prompt(Expand.promptPrefix + " and a boat"), Expand.promptPrefix + " and a boat")
    }

    /// **The stretch, exactly** (`ImageRGB.stretched`): no fill, no crop — a constant stays the
    /// constant at the new size, where `fitted`'s cover would keep only its centre.
    func testTheStretchedImageKeepsItsPixels() {
        let stretched = image(10, 10, value: 0.5).stretched(width: 20, height: 40)
        XCTAssertEqual([stretched.width, stretched.height], [20, 40])
        let plane = 20 * 40
        for c in 0..<3 {
            XCTAssertEqual(stretched.pixels[c * plane + 20 * 20 + 10], 0.5, accuracy: 1e-6)
        }
        // An image already at the format comes back as is, bit for bit.
        let same = image(10, 10, value: -0.25)
        XCTAssertEqual(same.stretched(width: 10, height: 10), same)
    }
}
