import Foundation

// ── the 「移除」 path ───────────────────────────────────────────────────────────────────────────
//
// ComfyUI's 「移除」 workflow edits one region of an image: the mask is cropped with a margin, tinted
// green, and that crop is both the image the text encoder reads (image 1) and the additive start the
// latent begins from. `Patch` is that geometry, translated from `遮罩裁剪V2.py` and
// `图像缩放（范围）.py`; the tint and the fill come from `Goohaitools`' nodes.

/// **The region an edit replaces**: one value per pixel, 0 (kept) to 1 (replaced).
///
/// `白=改，黑=留`: a white-on-black mask, or the alpha channel of a bitmap mask (a pixel map keeps
/// its shape in the alpha). The workflow reads the mask at `> 0.1` once, for the holes and the box.
package struct ImageMask: Sendable, Equatable {
    package static let threshold: Float = 0.1

    package let width: Int
    package let height: Int
    package let values: [Float]

    package init(width: Int, height: Int, values: [Float]) {
        precondition(width > 0 && height > 0, "ImageMask: \(width)×\(height), an empty mask")
        precondition(values.count == width * height, "ImageMask: \(values.count) values for \(width)×\(height)")
        self.width = width; self.height = height; self.values = values
    }

    /// The mask of an image: its alpha when it has one (a bitmap's shape), else its brightness,
    /// `max(r, g, b)` — white substitutes.
    package init(image: ImageRGB) {
        let count = image.width * image.height
        if let rgba = image.rgba {
            self.init(width: image.width, height: image.height,
                      values: (0..<count).map { Float(rgba[4 * $0 + 3]) / 255 })
            return
        }
        let plane = count
        self.init(width: image.width, height: image.height, values: (0..<count).map { i in
            (max(max(image.pixels[i], image.pixels[plane + i]), image.pixels[2 * plane + i]) + 1) / 2
        })
    }

    /// The pixels the workflow calls the mask's own: `> 0.1`, before any filling.
    package var effectivePixels: Int {
        values.reduce(0) { $1 > Self.threshold ? $0 + 1 : $0 }
    }

    /// **`binary_fill_holes(mask > 0.1)`**: the workflow fills a mask's holes before it crops, so a
    /// ring redraws its centre too. Pure Swift: the background 4-connected to the border stays out,
    /// every other background pixel is a hole and becomes part of the mask. Only the binary layer is
    /// filled: the values themselves are replaced by 0 and 1.
    package func filled() -> ImageMask {
        let cell = values.map { $0 > Self.threshold }
        let count = cell.count
        var outside = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        stack.reserveCapacity(count / 4)
        func seed(_ x: Int, _ y: Int) {
            let i = y * width + x
            if !cell[i] && !outside[i] { outside[i] = true; stack.append(i) }
        }
        for x in 0..<width { seed(x, 0); seed(x, height - 1) }
        for y in 0..<height { seed(0, y); seed(width - 1, y) }
        while let i = stack.popLast() {
            let x = i % width, y = i / width
            if x > 0, !cell[i - 1], !outside[i - 1] { outside[i - 1] = true; stack.append(i - 1) }
            if x + 1 < width, !cell[i + 1], !outside[i + 1] { outside[i + 1] = true; stack.append(i + 1) }
            if y > 0, !cell[i - width], !outside[i - width] { outside[i - width] = true; stack.append(i - width) }
            if y + 1 < height, !cell[i + width], !outside[i + width] { outside[i + width] = true; stack.append(i + width) }
        }
        return ImageMask(width: width, height: height,
                         values: (0..<count).map { cell[$0] || !outside[$0] ? 1 : 0 })
    }

    /// The box of the pixels `> 0.1`, in pixels; `nil` for an empty mask.
    package func bounds() -> (x: Int, y: Int, width: Int, height: Int)? {
        var left = width, right = -1, top = height, bottom = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where values[row + x] > Self.threshold {
                if x < left { left = x }
                if x > right { right = x }
                if y < top { top = y }
                if y > bottom { bottom = y }
            }
        }
        guard right >= left, bottom >= top else { return nil }
        return (left, top, right - left + 1, bottom - top + 1)
    }
}

/// **The 「移除」 edit**: the image, the region to replace, and the margins the crop takes around it.
///
/// The constants are the workflow's (`Goohaitools-comfyui`, 「移除、局部重绘 Turbo」): the crop
/// grows by `(factor − 1) × the box's shortest side` on each side — 0.3 above, 0.4 right, below and
/// left — and the long side lands between 768 and `maximumSide`, a multiple of 32.
package struct Patch: Sendable, Equatable {
    /// `图像缩放（范围）`'s bounds, as the workflow's slider sets them: long side 768–2560.
    package static let minimumSide = 768
    package static let maximumSide = 2560
    /// `整除数`: both sides of the crop are multiples of 32.
    package static let multiple = 32
    /// The workflow tints the crop with `#00FF00` at 0.4, over the mask only.
    package static let tintOpacity: Float = 0.4
    /// `遮罩裁剪V2`'s `纯白像素 < 10` guard, whose action this path does not reproduce: below this
    /// many pixels the patch is refused rather than the whole image replaced (see `EngineError.invalidPatch`).
    package static let minimumPixels = 10
    /// `Text Encode Qwen Image 2.1 GH`'s `_cover_crop_is_small(..., tolerance: 64)`: the crop counts as
    /// the target itself when a cover fit cuts at most this many pixels from each side. True, the
    /// workflow keeps the primary at the latent's size — the same image for the text encoder and for
    /// the denoiser's reference block (`Patch.Plan.primaryMatchesTarget`).
    package static let coverTolerance = 64

    /// The multipliers of the mask's shortest side, one per side.
    package struct Expansion: Sendable, Equatable {
        package var top: Double
        package var bottom: Double
        package var left: Double
        package var right: Double

        package init(top: Double = 1.3, bottom: Double = 1.4, left: Double = 1.4, right: Double = 1.4) {
            self.top = top; self.bottom = bottom; self.left = left; self.right = right
        }
    }

    /// The settings an entry keeps, so a redo draws the same crop (`RenderSettings.patch`).
    package struct Settings: Sendable, Equatable {
        package var expansion: Expansion
        package var maximumSide: Int
        /// **The crop as z₀, opt-in** (`Request.patchSeededStart`, `--seeded-start`): false — the
        /// default — renders the crop as image 1 alone and starts from noise.
        package var seededStart: Bool
        /// **The crop laid back over the original** (`Request.patchCropOnly`, `--crop-only`): true — the
        /// workflow's `GH_CropRestore`, the render at the **original's size**; false keeps the crop alone,
        /// at the plan's size, for comparison. A redo keeps this (`RenderSettings.patch`).
        package var paste: Bool

        package init(expansion: Expansion = Expansion(), maximumSide: Int = Patch.maximumSide,
                     seededStart: Bool = false, paste: Bool = true) {
            self.expansion = expansion; self.maximumSide = maximumSide
            self.seededStart = seededStart; self.paste = paste
        }
    }

    package struct Crop: Sendable, Equatable {
        package let x: Int
        package let y: Int
        package let width: Int
        package let height: Int
    }

    /// **What the crop is before the image is made**: the box in the original's pixels, and the size
    /// the workflow's scaling leaves — the latent's grid.
    package struct Plan: Sendable, Equatable {
        package let crop: Crop
        package let width: Int
        package let height: Int

        /// **Whether the crop is, within `Patch.coverTolerance`, the target itself** — the workflow's
        /// `_cover_crop_is_small`: fitted onto `width×height` by cover, the crop gives up at most 64 px
        /// on a side. True, the crop is handed to the text encoder and to the denoiser **as it is**
        /// (the workflow's primary latent, which is also the text encoder's image 1, so its slots and
        /// the reference block's rows agree); false, it is prepared at `--ref-res` like any reference.
        package var primaryMatchesTarget: Bool {
            let scale = max(Double(width) / Double(crop.width), Double(height) / Double(crop.height))
            let cut = max((Double(crop.width) * scale - Double(width)) / 2,
                          (Double(crop.height) * scale - Double(height)) / 2)
            return cut <= Double(Patch.coverTolerance)
        }
    }

    package var image: ImageRGB
    package var mask: ImageMask
    package var expansion: Expansion
    package var maximumSide: Int

    package init(image: ImageRGB, mask: ImageMask, expansion: Expansion = Expansion(),
                 maximumSide: Int = Patch.maximumSide) {
        self.image = image; self.mask = mask; self.expansion = expansion; self.maximumSide = maximumSide
    }

    /// **The crop and the size the render will have**, as `遮罩裁剪V2` then `图像缩放（范围）` make it.
    ///
    /// Throws `.invalidPatch` for a mask of another size, an empty one (fewer than `minimumPixels`
    /// pixels — the workflow would paint the whole image instead), or a size that leaves no pixel.
    package func plan() throws(EngineError) -> Plan {
        guard mask.width == image.width, mask.height == image.height else {
            throw EngineError.invalidPatch(reason:
                "the mask is \(mask.width)×\(mask.height), the image \(image.width)×\(image.height) — a mask must be the image's size")
        }
        guard mask.effectivePixels >= Self.minimumPixels else {
            throw EngineError.invalidPatch(reason:
                "the mask is empty or has fewer than \(Self.minimumPixels) pixels to replace — nothing to edit")
        }
        for (side, factor) in [("top", expansion.top), ("bottom", expansion.bottom),
                               ("left", expansion.left), ("right", expansion.right)]
        where !factor.isFinite || factor < 1 {
            throw EngineError.invalidPatch(reason: "the \(side) margin is \(factor), under 1: the crop would shrink the mask")
        }
        guard maximumSide >= Self.minimumSide else {
            throw EngineError.invalidPatch(reason:
                "the maximum side is \(maximumSide), under \(Self.minimumSide) — the workflow's smallest long side")
        }

        let filled = mask.filled()
        guard let box = filled.bounds() else {
            throw EngineError.invalidPatch(reason: "the mask has no pixels to replace")
        }
        // `int(最短边 × (系数 − 1))`, the box's shortest side, one margin per side, kept in the image.
        let short = Double(min(box.width, box.height))
        func margin(_ factor: Double) -> Int { Int(short * (factor - 1)) }
        let top = min(margin(expansion.top), box.y)
        let bottom = min(margin(expansion.bottom), image.height - box.y - box.height)
        let left = min(margin(expansion.left), box.x)
        let right = min(margin(expansion.right), image.width - box.x - box.width)

        let crop = Crop(x: box.x - left, y: box.y - top,
                        width: box.width + left + right, height: box.height + top + bottom)
        let scaled = target(crop.width, crop.height)

        // `应用除数`: two whole-multiple schemes, the one whose area is nearer the scaled target
        // wins; `resize_with_aspect_ratio` then `center_crop_to_divisor` leave exactly that size.
        let ratio = Double(crop.width) / Double(crop.height)
        let w1 = (scaled.w / Self.multiple) * Self.multiple
        let h1 = ((Int(Double(w1) / ratio)) / Self.multiple) * Self.multiple
        let h2 = (scaled.h / Self.multiple) * Self.multiple
        let w2 = ((Int(Double(h2) * ratio)) / Self.multiple) * Self.multiple
        let target = scaled.w * scaled.h
        let (w, h) = abs(w1 * h1 - target) <= abs(w2 * h2 - target) ? (w1, h1) : (w2, h2)
        guard w >= Self.multiple, h >= Self.multiple else {
            throw EngineError.invalidPatch(reason:
                "the crop \(crop.width)×\(crop.height) has no whole \(Self.multiple) size — its proportions are too narrow")
        }
        return Plan(crop: crop, width: w, height: h)
    }

    /// The long side's bounds: `calculate_target_size`, with Python's half-to-even rounding.
    private func target(_ width: Int, _ height: Int) -> (w: Int, h: Int) {
        let long = max(width, height)
        let ratio: Double
        if long < Self.minimumSide {
            ratio = Double(Self.minimumSide) / Double(long)
        } else if long > maximumSide {
            ratio = Double(maximumSide) / Double(long)
        } else {
            return (width, height)
        }
        return (Int((Double(width) * ratio).rounded(.toNearestOrEven)),
                Int((Double(height) * ratio).rounded(.toNearestOrEven)))
    }

    /// **The crop the model sees**: the original at the crop's pixels, tinted green where the filled
    /// mask is, then scaled to the plan's size. The workflow tints before it scales (`#204` then `#207`).
    ///
    /// A pixel the mask leaves alone is returned untouched; inside it, `0.4` of `#00FF00` substitutes,
    /// as `图像合并（遮罩）` does (its mask is quantized to 102/255, which is exactly 0.4).
    package func render(_ plan: Plan) -> ImageRGB {
        let crop = plan.crop
        let filled = mask.filled()
        let plane = crop.width * crop.height
        var pixels = [Float](repeating: 0, count: 3 * plane)
        image.pixels.withUnsafeBufferPointer { source in
            pixels.withUnsafeMutableBufferPointer { out in
                for c in 0..<3 {
                    let from = c * image.width * image.height
                    let to = c * plane
                    for y in 0..<crop.height {
                        let s = from + (crop.y + y) * image.width + crop.x
                        let d = to + y * crop.width
                        for x in 0..<crop.width {
                            out[d + x] = source[s + x]
                        }
                    }
                }
            }
        }
        let alpha = Self.tintOpacity
        let green: (Float, Float, Float) = (0, 1, -1)
        for y in 0..<crop.height {
            let sourceRow = (crop.y + y) * mask.width + crop.x
            for x in 0..<crop.width where filled.values[sourceRow + x] > ImageMask.threshold {
                let i = y * crop.width + x
                pixels[i] = pixels[i] * (1 - alpha) + green.0 * alpha
                pixels[plane + i] = pixels[plane + i] * (1 - alpha) + green.1 * alpha
                pixels[2 * plane + i] = pixels[2 * plane + i] * (1 - alpha) + green.2 * alpha
            }
        }
        return ImageRGB(pixels: pixels, height: crop.height, width: crop.width)
            .fitted(width: plan.width, height: plan.height)
    }
}
