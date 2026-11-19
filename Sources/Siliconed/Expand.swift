import Foundation

// ── the 「扩图」 path ───────────────────────────────────────────────────────────────────────────
//
// ComfyUI's 「扩图」 workflow grows a picture outward: the image sits inside a grey canvas, the model
// redraws the whole thing from noise, and the original is laid back inside the bigger picture. `Expand`
// is that geometry, translated from `孤海外补画板可视化` (the canvas), `数学运算_孤海` (the
// coefficients) and `GH_CropRestore` (the paste-back, `Paste.swift`'s own translation); the grey, the
// pads and the sampling target come from the workflow's own nodes.

/// **The 「扩图」 edit**: the image, the percents its canvas grows by, and the sampling ceiling.
///
/// The constants are the workflow's (`Qwen Image 2.1 扩图.json`): the canvas pads each side by a
/// percent of the image's own side — left 30, right 30, above and below 0 — in grey `#808080`, capped
/// at a long side of 5120; the sampling long side lands between 1024 and `maximumSample` (2048, the
/// graph's slider), both sides a multiple of 32; its short side stays at least
/// `Patch.minimumRenderSide` (448), the patch path's own floor, adopted here. There is **no
/// noise-mask**: the canvas is the text encoder's image 1 and the render starts from pure noise — the
/// whole picture is rebuilt, grey border included.
package struct Expand: Sendable, Equatable {
    /// The canvas node's `最大输出长边`: a canvas whose long side passes it is scaled back under it,
    /// pads and image together.
    package static let maximumCanvasSide = 5120
    /// `数学运算_孤海` #28's floor on the sampling long side: `min(max(1024, 长边), a)` — a canvas
    /// under it is scaled **up** to it.
    package static let minimumSampleSide = 1024
    /// `GoohaiUniversalSlider` #27: the sampling long side's ceiling, 2048 by default.
    package static let defaultMaximumSample = 2048
    /// `整除数`: both sides of the canvas are multiples of 32, as `Patch.multiple`.
    package static let multiple = 32

    /// **Node 5's `就近整除`**: the size to the nearest multiple of `multiple`, never under one
    /// (`max(d, floor(size / d + 0.5) × d)`). Rounding to the nearest — not down — is what keeps the
    /// render's shape near the canvas's, so the paste-back's resample never stretches the picture.
    package static func nearestMultiple(_ size: Int) -> Int {
        guard multiple > 1 else { return size }
        return max(multiple, Int((Double(size) / Double(multiple) + 0.5).rounded(.down)) * multiple)
    }
    /// The workflow's `外补颜色 #808080`. In the model's −1…1 RGB that is (0, 0, 0), not 128 levels
    /// of grey.
    package static let padColor: (Float, Float, Float) = (0, 0, 0)
    /// `easy string` #33's fixed sentence, which leads the prompt whatever the user adds (`CR Text
    /// Concatenate` #32 joins the two with an empty separator; `DF_Text_Box` #2 is empty by default).
    package static let promptPrefix = "移除图像中的灰色区域，无缝自然延展为完整图像。"
    /// `GH_CropRestore` #25: the keep-mask grows by 3 % and feathers over 3 % of the image's average
    /// side, the colour restore fully on — the mask path's own paste takes 4 / 5 / 1
    /// (`Patch.pasteExpansionPercent`).
    package static let pasteExpansionPercent = 3
    package static let pasteFeatherPercent = 3
    package static let pasteColorStrength = 1.0

    /// **The percents each side of the canvas grows by** (the widget's 单位 `百分比`, of the image's
    /// own side): left 30, right 30, above and below 0 — the workflow's defaults. 0 to 200 each; a pad
    /// of 0 on every side is refused (`EngineError.invalidPatch`): nothing to expand, the render would
    /// redraw everything and change nothing the user asked for.
    package struct Pads: Sendable, Equatable {
        package static let range = 0.0...200.0
        package var left: Double
        package var right: Double
        package var top: Double
        package var bottom: Double

        package init(left: Double = 30, right: Double = 30, top: Double = 0, bottom: Double = 0) {
            self.left = left; self.right = right; self.top = top; self.bottom = bottom
        }
    }

    /// **The expansion coefficients node 39 returns** (`数学运算_孤海`): the grey border folded into
    /// the margin `GH_MaskCropV2` would take, one value per direction — the mask marks the image
    /// itself, so the mask's sides are the image's own, and a direction's two sides carry the same
    /// value. A direction with no grey keeps its coefficient at 1.0: no margin at all.
    package struct Coefficients: Sendable, Equatable {
        package var top: Double
        package var bottom: Double
        package var left: Double
        package var right: Double

        package init(top: Double, bottom: Double, left: Double, right: Double) {
            self.top = top; self.bottom = bottom; self.left = left; self.right = right
        }
    }

    /// **What the render will be**: the canvas — the crop, the whole canvas, whose x and y are the
    /// image's offset inside it —, the size the ÷32 rounding leaves, the pads and coefficients as the
    /// graph holds them, and the image's own rectangle inside the canvas.
    package struct Plan: Sendable, Equatable {
        package let crop: Patch.Crop
        package let width: Int
        package let height: Int
        package let pads: Pads
        package let coefficients: Coefficients
        /// The image's size **inside the canvas**: the canvas cap's rounding may shave a pixel off the
        /// scaled one (`geometry`).
        package let imageWidth: Int
        package let imageHeight: Int

        /// The image's offset inside the canvas — the crop's own x and y.
        package var imageOffset: (x: Int, y: Int) { (crop.x, crop.y) }

        package init(crop: Patch.Crop, width: Int, height: Int, pads: Pads,
                     coefficients: Coefficients, imageWidth: Int, imageHeight: Int) {
            self.crop = crop; self.width = width; self.height = height; self.pads = pads
            self.coefficients = coefficients; self.imageWidth = imageWidth; self.imageHeight = imageHeight
        }
    }

    /// **Node 39's formula**, on the canvas (a × b) and the image inside it (c × d):
    ///
    ///     vertical    1.0 if b == d else (2/3 × (b − d)) / min(c, d) + 1.0
    ///     horizontal  1.0 if a == c else (2/3 × (a − c)) / min(c, d) + 1.0
    ///
    /// `GH_MaskCropV2` grows its crop by (系数 − 1) × the mask's shortest side per side — with the
    /// default 30 % pads the margin comes out at (4/3) × the grey, past the canvas's edge, and the
    /// crop lands on the canvas's bounds: **the crop the workflow feeds forward is the whole padded
    /// canvas**. The app takes the canvas directly and records these values, the same ones node 39
    /// returns, so the plan reads like the graph (§2 of `docs/EXPAND-WORKFLOW.md`).
    package static func coefficients(canvasWidth: Int, canvasHeight: Int,
                                     maskWidth: Int, maskHeight: Int) -> Coefficients {
        let a = Double(canvasWidth), b = Double(canvasHeight)
        let c = Double(maskWidth), d = Double(maskHeight)
        let vertical = b == d ? 1.0 : (2.0 / 3.0 * (b - d)) / min(c, d) + 1.0
        let horizontal = a == c ? 1.0 : (2.0 / 3.0 * (a - c)) / min(c, d) + 1.0
        return Coefficients(top: vertical, bottom: vertical, left: horizontal, right: horizontal)
    }

    /// **The canvas the pads make**: each pad is `round(percent / 100 × the image's own side)`, and a
    /// canvas whose long side passes `maximumCanvasSide` is scaled back under it — pads and image
    /// together, the proportions kept. Returns the canvas's size, the image's offset in it, and the
    /// image's size inside it (the cap's rounding may shave a pixel off the scaled image).
    package static func geometry(width: Int, height: Int, pads: Pads)
            -> (canvasWidth: Int, canvasHeight: Int, x: Int, y: Int, imageWidth: Int, imageHeight: Int) {
        func pad(_ percent: Double, _ side: Int) -> Int {
            Int((percent / 100 * Double(side)).rounded(.toNearestOrEven))
        }
        var left = pad(pads.left, width), right = pad(pads.right, width)
        var top = pad(pads.top, height), bottom = pad(pads.bottom, height)
        var canvasWidth = width + left + right, canvasHeight = height + top + bottom
        let long = max(canvasWidth, canvasHeight)
        if long > maximumCanvasSide {
            let scale = Double(maximumCanvasSide) / Double(long)
            left = Int((Double(left) * scale).rounded(.toNearestOrEven))
            right = Int((Double(right) * scale).rounded(.toNearestOrEven))
            top = Int((Double(top) * scale).rounded(.toNearestOrEven))
            bottom = Int((Double(bottom) * scale).rounded(.toNearestOrEven))
            canvasWidth = min(maximumCanvasSide, Int((Double(canvasWidth) * scale).rounded(.toNearestOrEven)))
            canvasHeight = min(maximumCanvasSide, Int((Double(canvasHeight) * scale).rounded(.toNearestOrEven)))
        }
        return (canvasWidth, canvasHeight, left, top, canvasWidth - left - right, canvasHeight - top - bottom)
    }

    /// **The canvas and the size the render will have**, as `孤海外补画板可视化` then `数学运算_孤海`
    /// and `图像缩放V2_孤海` make them.
    ///
    /// Throws `.invalidPatch` for pads out of `Pads.range`, all four 0 (nothing to expand), a sampling
    /// ceiling under `minimumSampleSide` (the canvas could not reach the long side the graph floors
    /// its sampling at), or a size whose short side falls under `Patch.minimumRenderSide` — a grey
    /// strip that thin renders nothing legible.
    package static func plan(pads: Pads, width: Int, height: Int,
                             maximumSample: Int = Expand.defaultMaximumSample) throws(EngineError) -> Plan {
        for (side, percent) in [("left", pads.left), ("right", pads.right),
                                ("top", pads.top), ("bottom", pads.bottom)]
        where !percent.isFinite || !Pads.range.contains(percent) {
            throw EngineError.invalidPatch(reason: "the \(side) pad is \(percent), outside the workflow's 0–200 percent")
        }
        guard pads.left > 0 || pads.right > 0 || pads.top > 0 || pads.bottom > 0 else {
            throw EngineError.invalidPatch(reason:
                "all four pads are 0 percent: nothing to expand — the render would redraw the image and change nothing")
        }
        guard width > 0, height > 0 else {
            throw EngineError.invalidPatch(reason: "the image is \(width)×\(height), empty")
        }
        guard maximumSample >= minimumSampleSide else {
            throw EngineError.invalidPatch(reason:
                "the sampling ceiling is \(maximumSample), under the workflow's \(minimumSampleSide): "
                + "the canvas cannot reach the long side the graph floors its sampling at")
        }
        let g = geometry(width: width, height: height, pads: pads)
        // #28: the long side between 1024 and the ceiling — then node 5's own arithmetic (`图像缩放V2_孤海`,
        // `计算等比例目标`): the fixed side rounds to the **nearest** multiple (`就近整除`, `floor(x/d + 0.5) × d`),
        // the other side follows the ratio (`round`) and rounds to the nearest multiple too — the
        // workflow's 拉伸 mode (`按模式整除`). Rounding to the *nearest* is what keeps the render's shape
        // the canvas's: a floor here (the patch path's own rule) drops up to 31 px off the long side and
        // the paste-back's resample stretches the picture back — a distortion ComfyUI never shows.
        let long = max(g.canvasWidth, g.canvasHeight)
        let target = min(max(minimumSampleSide, long), maximumSample)
        let fixed = Self.nearestMultiple(target)
        let (w, h): (Int, Int)
        if g.canvasWidth >= g.canvasHeight {
            w = fixed
            h = Self.nearestMultiple(Int((Double(g.canvasHeight) * Double(fixed) / Double(g.canvasWidth)).rounded()))
        } else {
            h = fixed
            w = Self.nearestMultiple(Int((Double(g.canvasWidth) * Double(fixed) / Double(g.canvasHeight)).rounded()))
        }
        guard w >= Self.multiple, h >= Self.multiple else {
            throw EngineError.invalidPatch(reason:
                "the canvas \(g.canvasWidth)×\(g.canvasHeight) has no whole \(Self.multiple) size — its proportions are too narrow")
        }
        // **The patch path's own floor** (`Patch.minimumRenderSide`, 448), adopted: a canvas taller than
        // it is wide by more than 4.5:1 renders a grey strip nothing legible comes out of.
        guard min(w, h) >= Patch.minimumRenderSide else {
            throw EngineError.invalidPatch(reason:
                "the canvas \(g.canvasWidth)×\(g.canvasHeight) renders at \(w)×\(h), its short side under the "
                + "\(Patch.minimumRenderSide) px floor the patch path keeps: widen the pads or use a less elongated image")
        }
        // **The mask marks the expansion, not the image** (`孤海外补画板可视化`, read from its source:
        // with no user mask the output mask is 1 over the grey border and 0 over the image). So
        // `GH_MaskCropV2`'s bounding box is the canvas on a padded axis and the image's own size on
        // an axis without one — and node 39's formula answers 1.0 on every axis (a padded axis makes
        // 画布 == 遮罩, an unpadded one makes 画布高 == 遮罩高), the crop grows by nothing and lands
        // on the mask's bounds: the whole canvas, exactly what the app feeds forward.
        let maskWidth = pads.left > 0 || pads.right > 0 ? g.canvasWidth : g.imageWidth
        let maskHeight = pads.top > 0 || pads.bottom > 0 ? g.canvasHeight : g.imageHeight
        let coefficients = Self.coefficients(canvasWidth: g.canvasWidth, canvasHeight: g.canvasHeight,
                                             maskWidth: maskWidth, maskHeight: maskHeight)
        return Plan(crop: Patch.Crop(x: g.x, y: g.y, width: g.canvasWidth, height: g.canvasHeight),
                    width: w, height: h, pads: pads, coefficients: coefficients,
                    imageWidth: g.imageWidth, imageHeight: g.imageHeight)
    }

    package var image: ImageRGB
    package var pads: Pads
    package var maximumSample: Int

    package init(image: ImageRGB, pads: Pads = Pads(), maximumSample: Int = Expand.defaultMaximumSample) {
        self.image = image; self.pads = pads; self.maximumSample = maximumSample
    }

    /// **The canvas and its size for this image's dimensions** — the same rules as the static
    /// `plan(pads:width:height:maximumSample:)`.
    package func plan() throws(EngineError) -> Plan {
        try Self.plan(pads: pads, width: image.width, height: image.height, maximumSample: maximumSample)
    }

    /// **The canvas the model sees** (node 48's output, scaled by node 5): the image laid in at its
    /// offset over the grey border, then stretched exactly to the plan's size — the workflow's `拉伸`:
    /// no cover, no crop, the ÷32 rounding leaves at most 32 px of difference.
    package func render(_ plan: Plan) -> ImageRGB {
        Self.laid(image: image, canvasWidth: plan.crop.width, canvasHeight: plan.crop.height,
                  x: plan.crop.x, y: plan.crop.y, imageWidth: plan.imageWidth, imageHeight: plan.imageHeight)
            .stretched(width: plan.width, height: plan.height)
    }

    /// **The padded canvas** (node 48): the image at its offset over the grey border. When the canvas
    /// was capped, the image inside is the cap's scaled one (`geometry`).
    package static func canvas(image: ImageRGB, pads: Pads) -> ImageRGB {
        let g = geometry(width: image.width, height: image.height, pads: pads)
        return laid(image: image, canvasWidth: g.canvasWidth, canvasHeight: g.canvasHeight,
                    x: g.x, y: g.y, imageWidth: g.imageWidth, imageHeight: g.imageHeight)
    }

    /// The canvas itself: the grey planes, the image — stretched when the cap scaled it — pasted at
    /// its offset.
    private static func laid(image: ImageRGB, canvasWidth: Int, canvasHeight: Int,
                             x: Int, y: Int, imageWidth: Int, imageHeight: Int) -> ImageRGB {
        let plane = canvasWidth * canvasHeight
        var pixels = [Float](repeating: 0, count: 3 * plane)
        let inside = imageWidth == image.width && imageHeight == image.height
        let laid = inside ? image : image.stretched(width: imageWidth, height: imageHeight)
        let laidPlane = imageWidth * imageHeight
        pixels.withUnsafeMutableBufferPointer { out in
            laid.pixels.withUnsafeBufferPointer { source in
                for c in 0..<3 {
                    let from = c * laidPlane, to = c * plane
                    for row in 0..<imageHeight {
                        let s = from + row * imageWidth
                        let d = to + (y + row) * canvasWidth + x
                        for column in 0..<imageWidth { out[d + column] = source[s + column] }
                    }
                }
            }
        }
        return ImageRGB(pixels: pixels, height: canvasHeight, width: canvasWidth)
    }

    /// **The canvas comes back whole** (`GH_CropRestore` #25 read from `遮罩裁剪V2.py`): the decoded
    /// render is scaled back to the canvas's pixels; the mask the graph pastes with is the
    /// **expansion ring** — 1 over the grey border, 0 over the image — grown `expansion` px *inward*
    /// (`遮罩扩展`: outward is the canvas edge, clamped) and feathered over `feather`. So the blend
    /// band lies **inside the image's edge**, over the original's own pixels, and past the edge the
    /// render stands alone — the grey the canvas was built with never shows, and no pixel is ever
    /// read outside the image's bounds (`获取边缘像素填充图像` fills the mask path's paste beyond its
    /// crop; here that fill would smear the bordermost pixel across the whole band — the artefact).
    /// The layer is matched to the render over the band alone, colour at full strength, blended with
    /// the workflow's dither. The image delivered is the **canvas's size**, bigger than the original,
    /// where the mask path's paste comes back at the original's own.
    package func composited(_ rendered: ImageRGB, plan: Plan) -> ImageRGB {
        let cw = plan.crop.width, ch = plan.crop.height
        let plane = cw * ch
        // `强制匹配尺寸` (L729–742) then the crop's own pixels (L744–766): the render, 8-bit, through
        // Pillow's Lanczos back to the canvas — the same two resamples `Patch.composited` takes.
        var bytes = Self.renderedBytes(rendered)
        if rendered.width != plan.width || rendered.height != plan.height {
            bytes = PillowResample.lanczos(bytes, channels: 3, width: rendered.width,
                                           height: rendered.height,
                                           toWidth: plan.width, toHeight: plan.height)
        }
        if plan.width != cw || plan.height != ch {
            bytes = PillowResample.lanczos(bytes, channels: 3, width: plan.width, height: plan.height,
                                           toWidth: cw, toHeight: ch)
        }
        var background = [Float](repeating: 0, count: 3 * plane)
        for i in 0..<plane {
            for c in 0..<3 { background[c * plane + i] = Float(bytes[3 * i + c]) / 255 }
        }
        // The original laid in — inside its rectangle the original's own pixels, outside it the grey
        // the canvas was built with (0.5 in 0…1): real pixels everywhere, none read past the bounds.
        let laid = plan.imageWidth == image.width && plan.imageHeight == image.height
            ? image : image.stretched(width: plan.imageWidth, height: plan.imageHeight)
        let ox = plan.crop.x, oy = plan.crop.y, iw = plan.imageWidth, ih = plan.imageHeight
        let laidPlane = iw * ih
        var layer = [Float](repeating: 0.5, count: 3 * plane)
        for c in 0..<3 {
            let from = c * laidPlane, to = c * plane
            for y in 0..<ih {
                let s = from + y * iw, d = to + (oy + y) * cw + ox
                for x in 0..<iw { layer[d + x] = (laid.pixels[s + x] + 1) / 2 }
            }
        }
        // The keep-mask: the image's rectangle **shrunk** `expansion` px — the ring grown inward —
        // feathered over `feather` (`创建羽化遮罩`), at the image's own side as the base (`L710–711`).
        let expansion = Patch.percentagePixels(Self.pasteExpansionPercent, width: iw, height: ih)
        let feather = Patch.percentagePixels(Self.pasteFeatherPercent, width: iw, height: ih)
        let grow = min(expansion, min(max(iw / 2 - 1, 0), max(ih / 2 - 1, 0)))
        let ix0 = ox + grow, iy0 = oy + grow, ix1 = ox + iw - grow, iy1 = oy + ih - grow
        guard ix1 > ix0, iy1 > iy0 else {
            return ImageRGB(pixels: background.map { $0 * 2 - 1 }, height: ch, width: cw)
        }
        var box = [Float](repeating: 0, count: plane)
        for y in iy0..<iy1 {
            for x in ix0..<ix1 { box[y * cw + x] = 1 }
        }
        let keep = Patch.featherMask(box, width: cw, height: ch, expansion: 0, feather: feather)
        // `匹配裁剪颜色` (L621–677), the other way round from the mask path: the pasted layer is the
        // original and the surroundings the render, so the layer is matched to the render's same
        // pixels — over the band alone (`feather` past the shrunk box; the mask never stands past
        // the image's edge when feather ≤ expansion, the workflow's own 3 / 3).
        let reach = feather
        let rx = max(0, ix0 - reach), ry = max(0, iy0 - reach)
        let rw = min(cw, ix1 + reach) - rx, rh = min(ch, iy1 + reach) - ry
        guard rw > 0, rh > 0 else {
            return ImageRGB(pixels: background.map { $0 * 2 - 1 }, height: ch, width: cw)
        }
        let regionPlane = rw * rh
        var region = [Float](repeating: 0, count: 3 * regionPlane)
        var reference = [Float](repeating: 0, count: 3 * regionPlane)
        for c in 0..<3 {
            for y in 0..<rh {
                for x in 0..<rw {
                    let i = y * rw + x, g = (ry + y) * cw + rx + x
                    region[c * regionPlane + i] = layer[c * plane + g]
                    reference[c * regionPlane + i] = background[c * plane + g]
                }
            }
        }
        let corrected = Patch.colorMatched(region, width: rw, height: rh, reference: reference,
                                           strength: Self.pasteColorStrength).pixels
        // L861–879: the layer where the mask stands, the render alone elsewhere, and in the transition
        // the deterministic dither of less than one level, capped by the brighter of the two sources.
        var result = background
        for y in 0..<rh {
            for x in 0..<rw {
                let maskValue = keep[(ry + y) * cw + rx + x]
                if maskValue <= 0 { continue } // the render itself: bit for bit
                let index = y * rw + x
                if maskValue >= 1 {
                    for c in 0..<3 { result[c * plane + (ry + y) * cw + rx + x] = corrected[c * regionPlane + index] }
                    continue
                }
                let dither = Patch.dither(x: rx + x, y: ry + y) / 255
                for c in 0..<3 {
                    let g = (ry + y) * cw + rx + x
                    let backgroundValue = Double(result[c * plane + g])
                    let layerValue = Double(corrected[c * regionPlane + index])
                    let blended = backgroundValue * (1 - Double(maskValue)) + layerValue * Double(maskValue)
                    let capped = min(blended + dither, max(backgroundValue, layerValue))
                    result[c * plane + g] = Float(capped)
                }
            }
        }
        return ImageRGB(pixels: result.map { $0 * 2 - 1 }, height: ch, width: cw)
    }

    /// **The prompt the graph hands the model** (nodes 33 + 32): the fixed sentence, then the user's —
    /// an empty supplement is the sentence alone, and a prompt that already leads with it comes back
    /// unchanged, so a caller may compose before the engine does.
    package static func prompt(_ supplement: String) -> String {
        let sentence = supplement.trimmingCharacters(in: .whitespacesAndNewlines)
        if sentence.hasPrefix(promptPrefix) { return sentence }
        return sentence.isEmpty ? promptPrefix : promptPrefix + sentence
    }

    /// The decoded render as 8-bit RGB, `np.clip(255 · x) → uint8` (truncation), as `tensor2pil` does
    /// — the conversion `Patch.composited` takes its own Lanczos resamples through.
    private static func renderedBytes(_ rendered: ImageRGB) -> [UInt8] {
        let plane = rendered.width * rendered.height
        var bytes = [UInt8](repeating: 0, count: 3 * plane)
        for c in 0..<3 {
            for i in 0..<plane {
                let value = (rendered.pixels[c * plane + i] + 1) / 2 * 255
                bytes[3 * i + c] = UInt8(min(255, max(0, value)))
            }
        }
        return bytes
    }
}
