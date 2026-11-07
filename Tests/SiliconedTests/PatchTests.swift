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
        for (index, expected) in [(0 * plane, Float(0.25 * 0.6 - 0.4)), (1 * plane, Float(0.25 * 0.6 + 0.4)),
                                  (2 * plane, Float(0.25 * 0.6 - 0.4))] {
            XCTAssertEqual(crop.pixels[index], expected, accuracy: 1e-6, "masked, channel \(index / plane)")
        }
        // A pixel the mask leaves alone, in the unscaled crop: the left half alone is masked.
        let patchHalf = Patch(image: image(64, 64, value: 0.25), mask: box(64, 64, x: 0, y: 0, w: 32, h: 64))
        let unscaled = patchHalf.render(Patch.Plan(crop: Patch.Crop(x: 0, y: 0, width: 64, height: 64),
                                                   width: 64, height: 64))
        let kept = 32 * 64 + 40 // x = 40: outside the mask
        for c in 0..<3 { XCTAssertEqual(unscaled.pixels[c * 4096 + kept], 0.25, "channel \(c): untouched") }
        XCTAssertEqual(unscaled.pixels[10 * 64 + 10], -0.25, "x = 10: masked, the red channel × 0.6 − 0.4")
    }

    /// The workflow's tint is `#00FF00` (「图像合并（遮罩）」), which in the model's −1…1 RGB is
    /// `(−1, 1, −1)`, not the yellow-green `(0, 1, −1)` the port used to mix.
    func testTheGreenTintIsTheWorkflowsPureGreen() {
        XCTAssertEqual(Patch.tintColor.0, -1)
        XCTAssertEqual(Patch.tintColor.1, 1)
        XCTAssertEqual(Patch.tintColor.2, -1)
        XCTAssertEqual(Patch.tintOpacity, 0.4, accuracy: 1e-6)
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

    // ── C4's joint sequence: the crop is image 1 and the denoiser's reference block ──────────────

    /// The image the user ran, and the black-and-white mask beside it — or, when they are not
    /// installed, **the same geometry**: 1248×1807, white from `x158 y123`, 458×1512.
    private func usersPatch() throws -> Patch {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let imageURL = root.appendingPathComponent("测试使用/图层 1.png")
        let maskURL = root.appendingPathComponent("测试使用/download.png")
        if FileManager.default.fileExists(atPath: imageURL.path), FileManager.default.fileExists(atPath: maskURL.path) {
            return Patch(image: try ImageRGB(contentsOf: imageURL), mask: ImageMask(image: try ImageRGB(contentsOf: maskURL)))
        }
        return Patch(image: image(1248, 1807), mask: box(1248, 1807, x: 158, y: 123, w: 458, h: 1512))
    }

    /// **The request that failed, and its geometry** (`2373 slots for 5376 image tokens`): the mask's
    /// box grows by `int(458 × 0.4)` = 183, clamps at the image's border, so the crop is 799×1807; the
    /// long side is under 2560, and the 32-multiple nearest in area is **768×1792** (latent 48×112).
    /// The crop is the render's own size (`_cover_crop_is_small`: 12 px a side, within 64), so its
    /// prepared copy is the crop itself — image 1 **and** the reference block (`primaryMatchesTarget`).
    func testTheUsersCropIsTheWorkflowsGeometry() throws {
        let patch = try usersPatch()
        let plan = try patch.plan()
        XCTAssertEqual([plan.crop.x, plan.crop.y, plan.crop.width, plan.crop.height], [0, 0, 799, 1807])
        XCTAssertEqual([plan.width, plan.height], [768, 1792])
        XCTAssertEqual([plan.width / 16, plan.height / 16], [48, 112], "the latent grid")
        XCTAssertTrue(plan.primaryMatchesTarget, "its cover fit cuts 12 px a side, within the workflow's 64")
        XCTAssertEqual([patch.render(plan).width, patch.render(plan).height], [768, 1792], "z₀'s pixels")
    }

    /// **The joint sequence this patch makes** — the failing check, as numbers. A patch's crop is
    /// image 1 for the text encoder and one reference block for the denoiser: **4 × slots == h·w**.
    /// Fallback (`--ref-res 1024`, a crop of another proportion): 672×1568 → 1 029 slots / 4 116 rows,
    /// target 5 376, so **9 492** image rows and 2 373 slots — the error's numbers. B (`primaryMatches
    /// Target`): the copy is 768×1792 → 1 344 slots / 5 376 rows, so **10 752** rows and 2 688 slots —
    /// the workflow's two copies of one image.
    func testThePatchSequenceIsTheWorkflows() throws {
        let patch = try usersPatch()
        let plan = try patch.plan()

        var fallback = MemoryFixtures.qwenRequest(plan.width, plan.height,
                                                  references: [(width: plan.width, height: plan.height)], tokens: 33)
        fallback.referenceResolution = 1024
        let need = QwenImage21Need(fallback, maps: fallback.qwenMaps!)
        XCTAssertEqual([need.references[0].prepared.width, need.references[0].prepared.height], [672, 1568])
        XCTAssertEqual(need.references[0].slots, 1029)
        let seq = need.sequence
        XCTAssertEqual(seq.textRows.count, 19, "33 − 14 (the system turn)")
        XCTAssertEqual(seq.target, 5376)
        XCTAssertEqual(seq.count - seq.textRows.count, 9492, "the joint sequence's image rows")
        XCTAssertEqual(seq.count - seq.textRows.count, 4 * (1029 + 1344), "4 × slots, unchanged")
        XCTAssertEqual(seq.blockStarts, [8, 4135], "image 1 opens the encoder's rows: text, then the block")
        XCTAssertEqual(seq.segments.count, 3, "text, the reference, the target")

        var matched = fallback
        matched.referenceMatchesTarget = true
        let withB = QwenImage21Need(matched, maps: matched.qwenMaps!)
        XCTAssertEqual([withB.references[0].prepared.width, withB.references[0].prepared.height], [768, 1792])
        XCTAssertEqual(withB.references[0].slots, 1344)
        XCTAssertEqual(withB.sequence.count - withB.sequence.textRows.count, 10752, "2 × 5376: the workflow")
        XCTAssertEqual(withB.sequence.count - withB.sequence.textRows.count, 4 * (1344 + 1344))
    }

    /// **The edit path is untouched** (`--ref`, no `--mask`): its reference is still prepared at
    /// `--ref-res` (799×1807 → 672×1536), and its layout is the one written out before B: 19 text
    /// rows (8 before image 1, 11 after it), the reference's 4 032 rows, the target's 5 376;
    /// 9 427 rows, prefix 4 051.
    func testTheEditSequenceIsUnchanged() throws {
        var edit = MemoryFixtures.qwenRequest(768, 1792, references: [(width: 799, height: 1807)], tokens: 33)
        edit.referenceResolution = 1024
        XCTAssertFalse(edit.referenceMatchesTarget)
        let need = QwenImage21Need(edit, maps: edit.qwenMaps!)
        XCTAssertEqual([need.references[0].prepared.width, need.references[0].prepared.height], [672, 1536])
        XCTAssertEqual(need.references[0].slots, 1008, "42 × 96 ÷ 4")
        let seq = need.sequence
        XCTAssertEqual([seq.count, seq.prefix, seq.target], [9427, 4051, 5376])
        XCTAssertEqual(seq.count - seq.textRows.count, 9408)
        XCTAssertEqual(seq.blockStarts, [8, 4051])
        XCTAssertEqual(seq.textRows.count, 19)
        XCTAssertEqual(seq.textRows.prefix(8).map { $0.joint }, Array(0..<8))
        XCTAssertEqual(seq.textRows.suffix(11).map { $0.joint }, Array(4040..<4051))
    }
}
