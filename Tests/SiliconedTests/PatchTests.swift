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

    /// **A carried alpha falls back to brightness**: an opaque white-on-black mask whose PNG
    /// carries antialiased alpha edges (here an edge line at 220 — nothing transparent, as the
    /// editor-exported file that made the whole image the mask) reads as what it shows: the white
    /// shape is the mask, not the alpha.
    func testACarriedAlphaFallsBackToBrightness() throws {
        let width = 64, height = 64, count = width * height
        var pixels = [Float](repeating: -1, count: 3 * count) // black
        for y in 16..<48 { for x in 16..<48 { for c in 0..<3 { pixels[c * count + y * width + x] = 1 } } }
        var rgba = [UInt8](repeating: 255, count: 4 * count) // carried: alpha 255 everywhere…
        for y in 16..<48 { rgba[4 * (y * width + 16) + 3] = 220 } // …with an antialiased edge, none transparent
        let mask = ImageMask(image: ImageRGB(pixels: pixels, height: height, width: width, rgba: rgba))
        let bounds = try XCTUnwrap(mask.bounds())
        XCTAssertEqual(bounds.x, 16); XCTAssertEqual(bounds.y, 16)
        XCTAssertEqual(bounds.width, 32); XCTAssertEqual(bounds.height, 32,
                       "the white shape, not the whole image")
        XCTAssertEqual(mask.effectivePixels, 32 * 32)
    }

    /// **A shape genuinely in the alpha is the mask**: a white shape on a transparent background —
    /// some pixel below half opacity — reads the alpha, opaque being the area to change.
    func testAShapeInTheAlphaIsTheMask() throws {
        let width = 64, height = 64, count = width * height
        var rgba = [UInt8](repeating: 0, count: 4 * count) // transparent background
        for y in 16..<48 {
            for x in 16..<48 {
                let i = 4 * (y * width + x)
                rgba[i] = 255; rgba[i + 1] = 255; rgba[i + 2] = 255; rgba[i + 3] = 255
            }
        }
        let image = ImageRGB(pixels: [Float](repeating: 0.5, count: 3 * count), height: height, width: width, rgba: rgba)
        let mask = ImageMask(image: image)
        let bounds = try XCTUnwrap(mask.bounds())
        XCTAssertEqual(bounds.x, 16); XCTAssertEqual(bounds.y, 16)
        XCTAssertEqual(bounds.width, 32); XCTAssertEqual(bounds.height, 32)
        XCTAssertEqual(mask.effectivePixels, 32 * 32)
        XCTAssertEqual(mask.values[16 * width + 16], 1, "opaque: the area to change")
        XCTAssertEqual(mask.values[0], 0, "transparent: kept")
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
        // Ten clears the workflow's pixel count — but not the patch's 448 floor: a 10×1 box renders
        // 768×64, which no render path may do, said with its numbers.
        var ten = five
        for i in 5..<10 { ten[i + 10] = 1 }
        XCTAssertThrowsError(try Patch(image: image(64, 64), mask: ImageMask(width: 64, height: 64, values: ten)).plan()) {
            guard let error = $0 as? EngineError, case .invalidPatch(let reason) = error else { return XCTFail("\($0)") }
            XCTAssertFalse(reason.contains("fewer than 10 pixels"), "the count is not the refusal: \(reason)")
            XCTAssertTrue(reason.contains("768×64"), "the floor is: \(reason)")
        }
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

    /// **The 「重绘」 branch** (`Patch.tint == false`, `--mode redraw`): the same crop, but the image's
    /// own pixels — no green hole. The geometry is one implementation: the tint alone differs.
    func testTheRedrawCropIsTheImageItself() {
        let source = image(64, 64, value: 0.25)
        let mask = box(64, 64, x: 0, y: 0, w: 32, h: 64)
        let plan = Patch.Plan(crop: Patch.Crop(x: 0, y: 0, width: 64, height: 64), width: 64, height: 64)
        let plain = Patch(image: source, mask: mask, tint: false).render(plan)
        let tinted = Patch(image: source, mask: mask).render(plan)
        XCTAssertEqual([plain.width, plain.height], [64, 64], "the same crop either way")
        for (index, name) in [(20 * 64 + 40, "outside the mask"), (10 * 64 + 10, "inside the mask")] {
            for c in 0..<3 {
                XCTAssertEqual(plain.pixels[c * 4096 + index], 0.25, "\(name), channel \(c): the image's own")
            }
        }
        XCTAssertEqual(tinted.pixels[10 * 64 + 10], -0.25, "remove tints the same pixel (red channel × 0.6 − 0.4)")
    }

    /// The workflow's tint is `#00FF00` (「图像合并（遮罩）」), which in the model's −1…1 RGB is
    /// `(−1, 1, −1)`, not the yellow-green `(0, 1, −1)` the port used to mix.
    func testTheGreenTintIsTheWorkflowsPureGreen() {
        XCTAssertEqual(Patch.tintColor.0, -1)
        XCTAssertEqual(Patch.tintColor.1, 1)
        XCTAssertEqual(Patch.tintColor.2, -1)
        XCTAssertEqual(Patch.tintOpacity, 0.4, accuracy: 1e-6)
    }

    /// **The workflow's `noise_mask`** (`Text Encode Qwen Image 2.1 GH`, `prepare_mask`): the filled
    /// mask at the plan's pixels, **grown 30 px** (a 61×61 ellipse), blurred by a **21-tap** Gaussian
    /// (σ 10), then **bilinear** to the latent grid (`reshape_mask`, not area nor nearest). 0 keeps the
    /// crop's latent, 1 lets the model draw; the feather is the workflow's, around the grown region.
    func testTheNoiseMaskIsTheWorkflowsOnTheLatentGrid() {
        let patch = Patch(image: image(256, 256), mask: box(256, 256, x: 96, y: 96, w: 64, h: 64))
        let plan = Patch.Plan(crop: Patch.Crop(x: 0, y: 0, width: 256, height: 256), width: 256, height: 256)
        let values = patch.noiseMask(plan, height: 16, width: 16)
        XCTAssertEqual(values.count, 16 * 16, "one weight per latent cell")
        // The region's core: grown 30 px (66…190), blurred — latent cell (8, 8) covers the centre.
        XCTAssertEqual(values[8 * 16 + 8], 1, accuracy: 1e-5, "inside: the model draws")
        XCTAssertLessThan(values[0], 0.02, "far outside: the crop's own latent, untouched")
        // The grown edge at 66 px: a feathered band, not a step — cell x = 4 covers 64…80.
        let feather = values[8 * 16 + 4]
        XCTAssertGreaterThan(feather, 0.3)
        XCTAssertLessThan(feather, 0.95)
        XCTAssertLessThan(values[8 * 16 + 3], 0.4, "a cell further out keeps most of the crop")
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

    // ── the short side: the patch path's own floor, 448 ─────────────────────────────────────────

    /// **A crop at 1.665:1 renders at 768×448** — the case the 512 floor used to refuse. The mask is
    /// 203×100 at (100, 100) in 512×512: the margins are 30 above and 39 elsewhere, so the crop is
    /// 281×169 (1.663:1); the workflow's long side is under 768, so `target` takes it to 768×462,
    /// and the 32-multiple nearest in area is **768×448** (the other scheme, 736×448, is 24 320 px
    /// off against 10 752). That is the patch's floor exactly, and `Format.check` accepts it there —
    /// while the regular floor still refuses it.
    func testAnElongatedCropRendersAtThePatchFloor() throws {
        let patch = Patch(image: image(512, 512), mask: box(512, 512, x: 100, y: 100, w: 203, h: 100))
        let plan = try patch.plan()
        XCTAssertEqual([plan.crop.x, plan.crop.y, plan.crop.width, plan.crop.height], [61, 70, 281, 169])
        XCTAssertEqual([plan.width, plan.height], [768, 448], "the workflow's smallest long side, 12:7")
        XCTAssertEqual(Patch.minimumRenderSide, 448)
        XCTAssertNoThrow(try Format.check(width: plan.width, height: plan.height,
                                         family: .qwenImage21, minimumSide: Patch.minimumRenderSide))
        XCTAssertThrowsError(try Format.check(width: plan.width, height: plan.height,
                                              family: .qwenImage21)) {
            XCTAssertEqual($0 as? EngineError, .imageTooSmall(side: 448, minimum: Format.minimumSide),
                           "a regular render at 448 is still refused")
        }
    }

    /// **The floor's edges, one by one**: 512 passes the regular floor and 511 does not; 448 passes
    /// the patch floor and 447 does not. The floor comes first in `Format.check`, so 511 under the
    /// regular rule is `imageTooSmall`, not `notMultiple` — 511 is no 32-multiple either way, but
    /// the useful error is the one reported.
    func testTheFloorsEdgesAre512And448() throws {
        XCTAssertNoThrow(try Format.check(width: 768, height: 512, family: .qwenImage21))
        XCTAssertThrowsError(try Format.check(width: 768, height: 511, family: .qwenImage21)) {
            XCTAssertEqual($0 as? EngineError, .imageTooSmall(side: 511, minimum: 512))
        }
        XCTAssertNoThrow(try Format.check(width: 768, height: 448,
                                          family: .qwenImage21, minimumSide: Patch.minimumRenderSide))
        XCTAssertThrowsError(try Format.check(width: 768, height: 447,
                                              family: .qwenImage21, minimumSide: Patch.minimumRenderSide)) {
            XCTAssertEqual($0 as? EngineError, .imageTooSmall(side: 447, minimum: 448))
        }
    }

    /// **A crop under the floor is refused, with its numbers** — a 301×169 (1.78:1) crop renders at
    /// 768×416, under 448: the patch's floor, not a ratio rule. The refusal names both sides and
    /// the floor, and says ordinary renders keep 512.
    func testACropUnderTheFloorIsRefusedWithItsNumbers() {
        let patch = Patch(image: image(512, 512), mask: box(512, 512, x: 100, y: 100, w: 223, h: 100))
        XCTAssertThrowsError(try patch.plan()) { error in
            guard case let EngineError.invalidPatch(reason) = error else {
                return XCTFail("expected invalidPatch, got \(error)")
            }
            XCTAssertTrue(reason.contains("768×416"), "the plan's size: \(reason)")
            XCTAssertTrue(reason.contains("under the patch path's 448 px floor"), "the floor: \(reason)")
            XCTAssertTrue(reason.contains("regular renders keep 512"), "the contrast: \(reason)")
        }
    }
}
