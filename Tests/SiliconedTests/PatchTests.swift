import XCTest
@testable import Siliconed

/// **The 「移除」 path's crop** (`Patch`): the workflow's hole filling, box, margins, 32-multiple size,
/// and the green crop the text encoder and z₀ share — the values here are the workflow's, to the pixel.
final class PatchTests: XCTestCase {

    private func image(_ width: Int, _ height: Int, value: Float = 0) -> ImageRGB {
        ImageRGB(pixels: [Float](repeating: value, count: 3 * width * height), height: height, width: width)
    }

    private func box(_ width: Int, _ height: Int, x: Int, y: Int, w: Int, h: Int) -> ImageMask {
        ImageMask(width: width, height: height, values: (0..<(width * height)).map { i in
            let px = i % width, py = i / width
            return px >= x && px < x + w && py >= y && py < y + h ? 1 : 0
        })
    }

    /// **A ring fills its centre** — `binary_fill_holes(mask > 0.1)`, as the workflow's 遮罩填充 does:
    /// the background 4-connected to the border stays out, the enclosed one becomes part of the mask.
    func testARingFillsItsCentre() {
        let size = 64, centre = 32
        let values = (0..<(size * size)).map { i -> Float in
            let x = i % size, y = i / size
            let d = ((x - centre) * (x - centre) + (y - centre) * (y - centre))
            return (d >= 100 && d <= 196) ? 1 : 0 // radius 10…14: a ring, a hole inside
        }
        let mask = ImageMask(width: size, height: size, values: values)
        let hole = centre * size + centre
        XCTAssertEqual(mask.values[hole], 0, "the centre is a hole before the fill")
        XCTAssertEqual(mask.filled().values[hole], 1, "and white after it")
        XCTAssertEqual(mask.filled().values[0], 0, "the outside stays black")
        XCTAssertEqual(mask.filled().values[0 * size + 10], 0)
    }

    /// **The crop `遮罩裁剪V2` then `图像缩放（范围）` make**: 200 px of mask in a 1000×700 image grow
    /// by 0.3 × 200 above and 0.4 × 200 on the other sides — `int(200 × 0.399…)` = **79**, not 80: the
    /// workflow's `1.4 − 1` in binary floating point, kept as it is — then the long side is scaled to 768
    /// and both sides rounded down to 32.
    func testTheCropAndSizeAreTheWorkflows() throws {
        let mask = box(1000, 700, x: 400, y: 250, w: 200, h: 200)
        let patch = Patch(image: image(1000, 700), mask: mask)
        let plan = try patch.plan()
        XCTAssertEqual(plan.crop.x, 321, "400 − int(200 × 0.399…)")
        XCTAssertEqual(plan.crop.y, 190, "250 − int(200 × 0.300…)")
        XCTAssertEqual(plan.crop.width, 358)
        XCTAssertEqual(plan.crop.height, 339)
        XCTAssertEqual([plan.width, plan.height], [768, 704], "768 × (339 × 768 / 358 → 727) floored to 32")
        XCTAssertEqual(plan.width % 32, 0)
        XCTAssertEqual(plan.height % 32, 0)
    }

    /// **No mask, no patch**: an empty mask and one with five white pixels are refused, not painted
    /// over the whole image (the workflow's `纯白像素 < 10` would).
    func testAnEmptyMaskIsRefusedInsteadOfTheWholeImage() {
        let empty = Patch(image: image(64, 64), mask: ImageMask(width: 64, height: 64,
                                                              values: [Float](repeating: 0, count: 64 * 64)))
        XCTAssertThrowsError(try empty.plan()) {
            guard case .invalidPatch = $0 as? EngineError else { return XCTFail("\($0)") }
        }
        var five = [Float](repeating: 0, count: 64 * 64)
        for i in 0..<5 { five[i + 10] = 1 }
        let sparse = Patch(image: image(64, 64), mask: ImageMask(width: 64, height: 64, values: five))
        XCTAssertThrowsError(try sparse.plan()) {
            guard case .invalidPatch = $0 as? EngineError else { return XCTFail("\($0)") }
        }
        // Ten is enough: the workflow's threshold, said.
        var ten = five
        for i in 5..<10 { ten[i + 10] = 1 }
        XCTAssertNoThrow(try Patch(image: image(64, 64), mask: ImageMask(width: 64, height: 64, values: ten)).plan())
    }

    /// **A mask of another size is refused by name**, before any crop: the mask is the image's grid.
    func testAMaskOfAnotherSizeIsRefused() {
        let patch = Patch(image: image(64, 64), mask: box(32, 32, x: 0, y: 0, w: 32, h: 32))
        XCTAssertThrowsError(try patch.plan()) {
            guard let error = $0 as? EngineError, case .invalidPatch(let reason) = error else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("the mask is 32×32"), reason)
        }
    }

    /// **The green crop**: inside the filled mask `原图 × 0.6 + #00FF00 × 0.4` (`图像合并（遮罩）`),
    /// outside it untouched — to the bit, when the crop is not scaled.
    func testTheCropIsTintedGreenOnTheMaskOnly() throws {
        let patch = Patch(image: image(64, 64, value: 0.25), mask: box(64, 64, x: 0, y: 0, w: 64, h: 64))
        let plan = try patch.plan()
        XCTAssertEqual([plan.width, plan.height], [768, 768])
        let crop = patch.render(plan)
        XCTAssertEqual(crop.width, 768)
        XCTAssertEqual(crop.height, 768)
        let plane = 768 * 768
        for (index, expected) in [(0 * plane, Float(0.25 * 0.6)), (1 * plane, Float(0.25 * 0.6 + 0.4)),
                                  (2 * plane, Float(0.25 * 0.6 - 0.4))] {
            XCTAssertEqual(crop.pixels[index], expected, accuracy: 1e-6, "masked, channel \(index / plane)")
        }
        // A pixel the mask leaves alone, in the unscaled crop: the left half alone is masked.
        let patchHalf = Patch(image: image(64, 64, value: 0.25), mask: box(64, 64, x: 0, y: 0, w: 32, h: 64))
        let unscaled = patchHalf.render(Patch.Plan(crop: Patch.Crop(x: 0, y: 0, width: 64, height: 64),
                                                   width: 64, height: 64))
        let kept = 32 * 64 + 40 // x = 40: outside the mask
        for c in 0..<3 { XCTAssertEqual(unscaled.pixels[c * 4096 + kept], 0.25, "channel \(c): untouched") }
        XCTAssertEqual(unscaled.pixels[10 * 64 + 10], 0.15, "x = 10: masked, the red channel × 0.6")
    }

    /// **The same pixels are z₀ and image 1** (the user's C4 check): the rendered crop, fitted to the
    /// plan's size — what the seeded start encodes — is the rendered crop bit for bit, and the text
    /// encoder's copy follows `referenceResolution`, not the output's size.
    func testTheSeededCropAndTheReferenceAreOneImageAtTheirOwnSizes() throws {
        let patch = Patch(image: image(1000, 700, value: 0.1), mask: box(1000, 700, x: 400, y: 250, w: 200, h: 200))
        let plan = try patch.plan()
        let crop = patch.render(plan)
        // `EngineRender` hands `crop` to `preparedReference` and fits `crop` to the format for z₀:
        // the fit is the identity, so the two uses start from the same pixels.
        XCTAssertEqual(crop.fitted(width: plan.width, height: plan.height), crop, "z₀'s image, bit for bit")
        XCTAssertEqual(patch.render(plan), crop, "the render is deterministic")

        let at1024 = QwenImage21Pipeline.preparedReference(crop, resolution: 1024)
        let at1536 = QwenImage21Pipeline.preparedReference(crop, resolution: 1536)
        XCTAssertNotEqual(at1024.width, plan.width, "the reference is re-prepared, not the output")
        XCTAssertLessThan(abs(at1024.width * at1024.height - 1024 * 1024), 1024 * 1024 / 8)
        XCTAssertLessThan(abs(at1536.width * at1536.height - 1536 * 1536), 1536 * 1536 / 8)
        XCTAssertGreaterThan(at1536.width, at1024.width, "the resolution alone sets its size")
    }
}
