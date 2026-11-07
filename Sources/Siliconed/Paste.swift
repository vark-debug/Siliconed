import Foundation

// ── the crop returns to its place ───────────────────────────────────────────────────────────────
//
// The engine renders a patch's crop alone (`Patch.render`); this file lays it back over the original
// image. It is `遮罩裁剪V2.py`'s `孤海_裁剪恢复` (`GH_CropRestore`), translated function by function:
//
//     计算百分比像素值   L497–503     a percentage of the mask box's average side, in pixels
//     创建羽化遮罩       L505–569     ellipse dilation, then a separable Gaussian with a smoothed tail
//     匹配裁剪颜色       L621–677     a robust per-channel gain/offset, Tukey IRLS, 6 rounds
//     恢复图像           L679–884     Lanczos back to the crop, feather, colour match, blend, dither
//
// The workflow's node 212 passes `遮罩扩展百分比 = 4`, `遮罩羽化百分比 = 5`, `颜色还原强度 = 1`;
// `裁剪遮罩` and `背景图像` are unconnected, so the mask is the crop's own (the filled mask, saved
// unscaled in the seam) and the background is the original image the crop was cut from.

extension Patch {
    /// The workflow's node 212 values (`Qwen-2.1-Remove-Inpaint-Turbo.api.json`): the mask's box grows
    /// by 4 % and feathers over 5 % of its average side; the colour match is on.
    package static let pasteExpansionPercent = 4
    package static let pasteFeatherPercent = 5
    package static let pasteColorStrength = 1.0

    // MARK: the percentages

    /// **`计算百分比像素值`** (L497–503): `int((width + height) / 2 × percent / 100)`, at least one
    /// pixel, zero for zero. The base is the mask's **white box** — the filled mask's bounds in the
    /// original image, the seam's `遮罩白色区域宽/高` — not the crop's size.
    package static func percentagePixels(_ percent: Int, width: Int, height: Int) -> Int {
        guard percent != 0 else { return 0 }
        return max(1, Int(Double(width + height) / 2 * Double(percent) / 100))
    }

    // MARK: the feather

    /// **`创建羽化遮罩`** (L505–569): the mask grows by `expansion` pixels (an ellipse below 64,
    /// a distance transform above), then is blurred by a separable Gaussian whose kernel is scaled
    /// by `feather`, whose radius is `ceil(feather)` in working pixels, and whose outer half is
    /// smoothed to zero (`1 − tail³(tail(tail·6 − 15) + 10)`, the cubic smoothstep). `float32`
    /// throughout, `BORDER_REPLICATE` — a radius above 64 shrinks the working grid by
    /// `ceil(feather / 64)` and scales back.
    package static func featherMask(_ mask: [Float], width: Int, height: Int,
                                    expansion: Int, feather: Int) -> [Float] {
        guard expansion > 0 || feather > 0 else { return mask }
        var values = mask.map { min(1, max(0, $0)) }

        if expansion > 0 {
            if expansion <= 64 {
                // `max(3, int(扩展) * 2 + 1)`, `MORPH_ELLIPSE`: a filled disk of radius `expansion`.
                let radius = max(1, expansion)
                values = dilate(values, width: width, height: height, radius: radius)
            } else {
                // `distanceTransform(1 − 前景, DIST_L2, 3)` then `<= 扩展`: every pixel within the
                // radius of a foreground pixel becomes 1. The 3×3 chamfer is a grid walk here.
                values = expandByDistance(values, width: width, height: height, radius: expansion)
            }
        }

        if feather > 0 {
            let f = Double(feather)
            // `缩小倍数 = max(1, ceil(羽化 / 64))`; `round` is Python's half-to-even.
            let shrink = max(1, Int((f / 64.0).rounded(.up)))
            let workWidth = max(1, Int((Double(width) / Double(shrink)).rounded(.toNearestOrEven)))
            let workHeight = max(1, Int((Double(height) / Double(shrink)).rounded(.toNearestOrEven)))
            var work = shrink > 1
                ? areaResize(values, width: width, height: height, channels: 1,
                             toWidth: workWidth, toHeight: workHeight)
                : values
            // `羽化 * 工作宽 / 原宽` per axis: the kernel radius in working pixels.
            let kw = featherKernel(radius: f * Double(workWidth) / Double(width))
            let kh = featherKernel(radius: f * Double(workHeight) / Double(height))
            work = convolve(work, width: workWidth, height: workHeight, kernelX: kw, kernelY: kh)
            values = shrink > 1
                ? linearResize(work, width: workWidth, height: workHeight, channels: 1,
                               toWidth: width, toHeight: height)
                : work
        }
        return values.map { min(1, max(0, $0)) }
    }

    // MARK: the colour match

    /// **A `匹配裁剪颜色` result**: the corrected pixels (planar, 0…1), the gain and offset it applied
    /// per channel (after the strength's blend), and whether it kept them at all.
    package struct ColorMatch: Equatable, Sendable {
        package var pixels: [Float]
        package var gain: [Double]
        package var offset: [Double]
        package var applied: Bool
    }

    /// **`匹配裁剪颜色`** (L621–677), on planar 0…1 pixels.
    ///
    /// The samples are the pixels whose **local structure** is the same in the crop and in the original
    /// (`1 / (1 + ((detailSource − detailTarget) / 0.02)²)> 0.8`) and whose colour is only slightly off
    /// (at most 24 levels any channel, 18 the luma) — eroded by 3×3 so the resampled edges stay out.
    /// Six IRLS rounds fit one gain and one offset per channel with Tukey's bisquare (c = 4.685, MAD
    /// scaled by 1.4826, a 0.004 floor), gains clipped to 0.9…1.1 and offsets to ±24/255. The estimate
    /// is kept only if the samples hold and the residual stays under 0.035 on 60 % of them.
    package static func colorMatched(_ crop: [Float], width: Int, height: Int,
                                     reference: [Float],
                                     strength: Double) -> ColorMatch {
        let identity = ColorMatch(pixels: crop, gain: [1, 1, 1], offset: [0, 0, 0], applied: false)
        guard strength > 0, width > 0, height > 0 else { return identity }
        let plane = width * height

        // `比例 = min(1, 256 / max(高, 宽))`, then `cv2.resize(..., INTER_AREA)` on both images.
        let ratio = min(1, 256 / Double(max(width, height)))
        let workWidth = max(1, Int((Double(width) * ratio).rounded(.toNearestOrEven)))
        let workHeight = max(1, Int((Double(height) * ratio).rounded(.toNearestOrEven)))
        let source = resizedRGB(crop, width: width, height: height,
                                toWidth: workWidth, toHeight: workHeight)
        let target = resizedRGB(reference, width: width, height: height,
                                toWidth: workWidth, toHeight: workHeight)

        // `cv2.COLOR_RGB2GRAY`; `细节 = 灰度 − GaussianBlur(灰度, (0,0), 1.5)`.
        let workPlane = workWidth * workHeight
        var sourceGray = [Double](repeating: 0, count: workPlane)
        var targetGray = [Double](repeating: 0, count: workPlane)
        for i in 0..<workPlane {
            sourceGray[i] = 0.299 * Double(source[3 * i]) + 0.587 * Double(source[3 * i + 1])
                + 0.114 * Double(source[3 * i + 2])
            targetGray[i] = 0.299 * Double(target[3 * i]) + 0.587 * Double(target[3 * i + 1])
                + 0.114 * Double(target[3 * i + 2])
        }
        let sourceDetail = zip(sourceGray, gaussianBlur(sourceGray, width: workWidth,
                                                        height: workHeight, sigma: 1.5)).map { $0 - $1 }
        let targetDetail = zip(targetGray, gaussianBlur(targetGray, width: workWidth,
                                                        height: workHeight, sigma: 1.5)).map { $0 - $1 }
        var structureWeight = [Double](repeating: 0, count: workPlane)
        for i in 0..<workPlane {
            let d = (sourceDetail[i] - targetDetail[i]) / 0.02
            structureWeight[i] = 1 / (1 + d * d)
        }

        // The candidates: every channel within 24/255, the luma within 18/255, the structure above 0.8.
        var candidates = [Bool](repeating: false, count: workPlane)
        let rgbTolerance = 24.0 / 255.0, lumaTolerance = 18.0 / 255.0
        for i in 0..<workPlane {
            var close = true
            for c in 0..<3 where abs(Double(target[3 * i + c]) - Double(source[3 * i + c])) > rgbTolerance {
                close = false; break
            }
            candidates[i] = close && abs(targetGray[i] - sourceGray[i]) <= lumaTolerance
                && structureWeight[i] > 0.8
        }
        // `cv2.erode(candidates, ones((3,3)))`: a neighbour outside the image is the morphology's
        // default border value, which never erodes — it counts as true.
        var eroded = [Bool](repeating: false, count: workPlane)
        for y in 0..<workHeight {
            for x in 0..<workWidth {
                var all = true
                for dy in -1...1 {
                    let yy = y + dy
                    if yy < 0 || yy >= workHeight { continue }
                    for dx in -1...1 {
                        let xx = x + dx
                        if xx < 0 || xx >= workWidth { continue }
                        if !candidates[yy * workWidth + xx] { all = false; break }
                    }
                    if !all { break }
                }
                eroded[y * workWidth + x] = all
            }
        }
        let sampleCount = eroded.reduce(0) { $1 ? $0 + 1 : $0 }
        let minimumSamples = max(16, Double(workPlane) * 0.05)
        guard Double(sampleCount) >= minimumSamples else { return identity }

        var sourceSamples: [[Double]] = [[], [], []]
        var targetSamples: [[Double]] = [[], [], []]
        var weightSamples: [Double] = []
        for i in 0..<workPlane where eroded[i] {
            for c in 0..<3 {
                sourceSamples[c].append(Double(source[3 * i + c]))
                targetSamples[c].append(Double(target[3 * i + c]))
            }
            weightSamples.append(structureWeight[i])
        }
        let sampleSize = targetSamples[0].count

        // `偏移 = median(目标 − 源, axis=0)`, the gain starting at 1.
        var gain = [Double](repeating: 1, count: 3)
        var offset = (0..<3).map { median(zip(targetSamples[$0], sourceSamples[$0]).map { $0 - $1 }) }
        for _ in 0..<6 {
            let residual = (0..<sampleSize).map { i in
                (0..<3).map { c in targetSamples[c][i] - (sourceSamples[c][i] * gain[c] + offset[c]) }
            }
            let centre = (0..<3).map { c in median(residual.map { $0[c] }) }
            let scale = (0..<3).map { c in
                max(median(residual.map { abs($0[c] - centre[c]) }) * 1.4826, 0.004)
            }
            let weights = (0..<sampleSize).map { i -> Double in
                let deviation = (0..<3).map { c in
                    abs(residual[i][c] - centre[c]) / (4.685 * scale[c])
                }.max() ?? 0
                let tukey = max(1 - deviation * deviation, 0)
                return tukey * tukey * weightSamples[i]
            }
            let weightSum = weights.reduce(0, +)
            // `权重和 < max(16, len(源) × 0.1)`: too few good pixels to trust the fit.
            guard weightSum >= max(16, Double(sampleSize) * 0.1) else { return identity }
            var sourceMean = [Double](repeating: 0, count: 3)
            var targetMean = [Double](repeating: 0, count: 3)
            for i in 0..<sampleSize {
                let w = weights[i] / weightSum
                for c in 0..<3 {
                    sourceMean[c] += sourceSamples[c][i] * w
                    targetMean[c] += targetSamples[c][i] * w
                }
            }
            var variance = [Double](repeating: 0, count: 3)
            var covariance = [Double](repeating: 0, count: 3)
            for i in 0..<sampleSize {
                let w = weights[i] / weightSum
                for c in 0..<3 {
                    let ds = sourceSamples[c][i] - sourceMean[c]
                    let dt = targetSamples[c][i] - targetMean[c]
                    variance[c] += ds * ds * w
                    covariance[c] += ds * dt * w
                }
            }
            for c in 0..<3 {
                gain[c] = min(1.1, max(0.9, (covariance[c] + 1e-4) / (variance[c] + 1e-4)))
                offset[c] = min(24 / 255, max(-24 / 255, targetMean[c] - sourceMean[c] * gain[c]))
            }
        }
        // `稳定区域` (L668–670), once the six rounds have settled: enough samples must sit within
        // 0.035 of the fit, with a structure weight above 0.5 — otherwise the crop comes back as is.
        var stable = 0
        for i in 0..<sampleSize {
            let worst = (0..<3).map { c in
                abs(targetSamples[c][i] - (sourceSamples[c][i] * gain[c] + offset[c]))
            }.max() ?? 0
            if worst < 0.035, weightSamples[i] > 0.5 { stable += 1 }
        }
        guard Double(stable) >= max(minimumSamples, Double(sampleSize) * 0.6) else { return identity }

        // `混合强度 = min(强度, 1)`; the gain moves from 1, the offset from 0.
        let blend = min(strength, 1)
        gain = gain.map { 1 + ($0 - 1) * blend }
        offset = offset.map { $0 * blend }
        var corrected = [Float](repeating: 0, count: 3 * width * height)
        for c in 0..<3 {
            let g = Float(gain[c]), o = Float(offset[c])
            for i in 0..<plane {
                corrected[c * plane + i] = min(1, max(0, crop[c * plane + i] * g + o))
            }
        }
        return ColorMatch(pixels: corrected, gain: gain, offset: offset, applied: true)
    }

    // MARK: the return

    /// **`恢复图像`** (L679–884): the decoded crop, scaled back to the crop's pixels with Pillow's
    /// Lanczos (8-bit, as `Image.LANCZOS`), feathered where the mask is, colour-matched against the
    /// original's same pixels, blended over a copy of the original and dithered in the transition —
    /// returned at the **original image's size**.
    package func composited(_ rendered: ImageRGB, plan: Plan) -> ImageRGB {
        let crop = plan.crop
        let width = image.width, height = image.height

        // `强制匹配尺寸` (L729–742): the decoded crop is brought to the plan's size if it is not.
        var bytes = renderedBytes(rendered)
        if rendered.width != plan.width || rendered.height != plan.height {
            bytes = PillowResample.lanczos(bytes, channels: 3, width: rendered.width,
                                           height: rendered.height,
                                           toWidth: plan.width, toHeight: plan.height)
        }
        // L744–766: then to the crop's own pixels (`原像素` path; no padding to remove).
        if plan.width != crop.width || plan.height != crop.height {
            bytes = PillowResample.lanczos(bytes, channels: 3, width: plan.width, height: plan.height,
                                           toWidth: crop.width, toHeight: crop.height)
        }
        let cropPlane = crop.width * crop.height
        var restored = [Float](repeating: 0, count: 3 * cropPlane)
        for i in 0..<cropPlane {
            for c in 0..<3 { restored[c * cropPlane + i] = Float(bytes[3 * i + c]) / 255 }
        }

        // `未缩放裁剪遮罩`, quantized as the seam stores it (`uint8` / 255): the filled mask over the
        // crop's rectangle (`获取边缘像素填充图像`, L355–360, with an in-bounds crop: a copy).
        let filled = mask.filled()
        var cropMask = [Float](repeating: 0, count: cropPlane)
        for y in 0..<crop.height {
            for x in 0..<crop.width {
                cropMask[y * crop.width + x] =
                    filled.values[(crop.y + y) * mask.width + crop.x + x] > ImageMask.threshold ? 1 : 0
            }
        }

        // `遮罩扩展` / `遮罩羽化` from the white box's average side, not the crop's (L710–711).
        let box = filled.bounds() ?? (x: 0, y: 0, width: 0, height: 0)
        let expansion = Self.percentagePixels(Self.pasteExpansionPercent, width: box.width, height: box.height)
        let feather = Self.percentagePixels(Self.pasteFeatherPercent, width: box.width, height: box.height)

        // L797–824: feather inside the canvas only; the crop's artificial edges (not shared with the
        // original's) fall to zero over the feather's width with the same smoothstep.
        let effectiveLeft = max(0, -crop.x), effectiveTop = max(0, -crop.y)
        let effectiveRight = min(crop.width, width - crop.x)
        let effectiveBottom = min(crop.height, height - crop.y)
        var featherMask = [Float](repeating: 0, count: cropPlane)
        if effectiveRight > effectiveLeft, effectiveBottom > effectiveTop {
            let ew = effectiveRight - effectiveLeft, eh = effectiveBottom - effectiveTop
            var effective = [Float](repeating: 0, count: ew * eh)
            for y in 0..<eh {
                for x in 0..<ew {
                    effective[y * ew + x] = cropMask[(effectiveTop + y) * crop.width + effectiveLeft + x]
                }
            }
            effective = Self.featherMask(effective, width: ew, height: eh,
                                         expansion: expansion, feather: feather)
            if feather > 0 {
                for (axis, lowEdge, highEdge) in [
                    (0, crop.y > 0, crop.y + crop.height < height),
                    (1, crop.x > 0, crop.x + crop.width < width),
                ] {
                    let length = axis == 0 ? eh : ew
                    var weights = [Float](repeating: 1, count: length)
                    for i in 0..<length {
                        var w = Float(1)
                        if lowEdge { w = min(w, Self.smoothstepRamp(step: i, length: feather)) }
                        if highEdge { w = min(w, Self.smoothstepRamp(step: length - 1 - i, length: feather)) }
                        weights[i] = w
                    }
                    if axis == 0 {
                        for y in 0..<eh { for x in 0..<ew { effective[y * ew + x] *= weights[y] } }
                    } else {
                        for y in 0..<eh { for x in 0..<ew { effective[y * ew + x] *= weights[x] } }
                    }
                }
            }
            for y in 0..<eh {
                for x in 0..<ew {
                    featherMask[(effectiveTop + y) * crop.width + effectiveLeft + x] = effective[y * ew + x]
                }
            }
        }

        // L835–845: the paste position, and the part of the crop that lands on the canvas.
        let pasteX = max(0, crop.x), pasteY = max(0, crop.y)
        let sourceX = max(0, -crop.x), sourceY = max(0, -crop.y)
        let sourceWidth = min(crop.width - sourceX, width - pasteX)
        let sourceHeight = min(crop.height - sourceY, height - pasteY)

        var result = image.pixels
        guard sourceWidth > 0, sourceHeight > 0 else {
            return ImageRGB(pixels: result, height: height, width: width)
        }
        let imagePlane = width * height

        // The restored region and the original's same pixels — the reference is ALWAYS the original,
        // never the background argument (L852–855).
        var region = [Float](repeating: 0, count: 3 * sourceWidth * sourceHeight)
        var reference = [Float](repeating: 0, count: 3 * sourceWidth * sourceHeight)
        for c in 0..<3 {
            for y in 0..<sourceHeight {
                for x in 0..<sourceWidth {
                    region[c * sourceWidth * sourceHeight + y * sourceWidth + x] =
                        restored[c * cropPlane + (sourceY + y) * crop.width + sourceX + x]
                    reference[c * sourceWidth * sourceHeight + y * sourceWidth + x] =
                        (image.pixels[c * imagePlane + (pasteY + y) * width + pasteX + x] + 1) / 2
                }
            }
        }
        let matched = Self.colorMatched(region, width: sourceWidth, height: sourceHeight,
                                        reference: reference, strength: Self.pasteColorStrength)
        let corrected = matched.pixels

        // L861–879: `粘贴区域 · (1 − 遮罩) + 恢复区域 · 遮罩`, then in the transition a deterministic
        // dither of less than one level, capped by the brighter of the two sources.
        for y in 0..<sourceHeight {
            for x in 0..<sourceWidth {
                let maskValue = featherMask[(sourceY + y) * crop.width + sourceX + x]
                if maskValue <= 0 { continue } // the background itself: bit for bit
                let index = y * sourceWidth + x
                if maskValue >= 1 {
                    for c in 0..<3 {
                        let correctedValue = Double(corrected[c * sourceWidth * sourceHeight + index])
                        result[c * imagePlane + (pasteY + y) * width + pasteX + x] =
                            Float(correctedValue * 2 - 1)
                    }
                    continue
                }
                let dither = Self.dither(x: pasteX + x, y: pasteY + y) / 255
                for c in 0..<3 {
                    let backgroundValue = Double(reference[c * sourceWidth * sourceHeight + index])
                    let restoredValue = Double(corrected[c * sourceWidth * sourceHeight + index])
                    let blended = backgroundValue * (1 - Double(maskValue)) + restoredValue * Double(maskValue)
                    let capped = min(blended + dither, max(backgroundValue, restoredValue))
                    result[c * imagePlane + (pasteY + y) * width + pasteX + x] = Float(capped * 2 - 1)
                }
            }
        }
        return ImageRGB(pixels: result, height: height, width: width)
    }

    /// `np.mod(52.9829189 · np.mod(x · 0.06711056 + y · 0.00583715, 1.0), 1.0)` (L874), the workflow's
    /// dither; its coordinates are the **original image's**, not the crop's.
    static func dither(x: Int, y: Int) -> Double {
        let raw = Double(x) * 0.06711056 + Double(y) * 0.00583715
        let folded = raw - raw.rounded(.down)
        let scaled = 52.9829189 * folded
        return scaled - scaled.rounded(.down)
    }

    /// The cubic smoothstep `w³(w(w·6 − 15) + 10)`, clamped to 0…1.
    static func smoothstepRamp(step: Int, length: Int) -> Float {
        guard length > 0 else { return 1 }
        let w = min(1, max(0, Float(step) / Float(length)))
        return w * w * w * (w * (w * 6 - 15) + 10)
    }

    // MARK: primitives

    /// The rendered crop as 8-bit RGB, `np.clip(255 · x) → uint8` (truncation), as `tensor2pil` does.
    private func renderedBytes(_ rendered: ImageRGB) -> [UInt8] {
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

    /// `cv2.dilate` with `MORPH_ELLIPSE` of radius `radius`: a maximum over the disk
    /// `dx² + dy² ≤ radius²`. Horizontal sliding maxima keep it linear in the radius.
    static func dilate(_ mask: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var output = [Float](repeating: 0, count: width * height)
        var row = [Float](repeating: 0, count: width)
        var deque = [Int](repeating: 0, count: width)
        for dy in -radius...radius {
            let horizontal = Int((Double(radius * radius - dy * dy)).squareRoot())
            for y in 0..<height {
                let base = y * width
                var head = 0, tail = 0, next = 0
                for x in 0..<width {
                    let high = min(width - 1, x + horizontal)
                    while next <= high {
                        while tail > head, mask[base + deque[tail - 1]] <= mask[base + next] { tail -= 1 }
                        deque[tail] = next; tail += 1; next += 1
                    }
                    let low = x - horizontal
                    while head < tail, deque[head] < low { head += 1 }
                    row[x] = head < tail ? mask[base + deque[head]] : 0
                }
                let destination = y - dy
                if destination >= 0, destination < height {
                    for x in 0..<width {
                        let index = destination * width + x
                        if row[x] > output[index] { output[index] = row[x] }
                    }
                }
            }
        }
        return output
    }

    /// `cv2.distanceTransform(1 − 前景, DIST_L2, 3) ≤ 扩展`, with a two-pass 3×3 chamfer (1 and √2).
    /// The workflow passes 4 % — a radius this large is out of reach — but the branch exists in the
    /// source, so it exists here.
    static func expandByDistance(_ mask: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let far = Double(radius + 1)
        var distance = mask.map { $0 > 1e-6 ? 0 : far }
        let diagonal = Double(2).squareRoot()
        func relax(_ index: Int, _ other: Int, _ weight: Double) {
            let candidate = distance[other] + weight
            if candidate < distance[index] { distance[index] = candidate }
        }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if x > 0 { relax(i, i - 1, 1) }
                if y > 0 {
                    relax(i, i - width, 1)
                    if x > 0 { relax(i, i - width - 1, diagonal) }
                    if x + 1 < width { relax(i, i - width + 1, diagonal) }
                }
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                if x + 1 < width { relax(i, i + 1, 1) }
                if y + 1 < height {
                    relax(i, i + width, 1)
                    if x + 1 < width { relax(i, i + width + 1, diagonal) }
                    if x > 0 { relax(i, i + width - 1, diagonal) }
                }
            }
        }
        return mask.indices.map { distance[$0] <= Double(radius) ? 1 : mask[$0] }
    }

    /// The kernel of `创建羽化遮罩` per axis: radius `r`, `ceil(r)` taps a side, the Gaussian
    /// `exp(−½(i/r)²)` times the tail window `1 − tail³(tail(tail·6 − 15) + 10)` where
    /// `tail = clip((|i|/(r + 0.5) − 0.5) · 2, 0, 1)`, normalized.
    static func featherKernel(radius r: Double) -> [Double] {
        let taps = max(1, Int(r.rounded(.up)))
        var kernel = [Double](repeating: 0, count: 2 * taps + 1)
        for i in -taps...taps {
            let ratio = Double(abs(i)) / (r + 0.5)
            let tail = min(1, max(0, (ratio - 0.5) * 2))
            let window = 1 - tail * tail * tail * (tail * (tail * 6 - 15) + 10)
            kernel[i + taps] = exp(-0.5 * pow(Double(i) / r, 2)) * window
        }
        let total = kernel.reduce(0, +)
        return total != 0 ? kernel.map { $0 / total } : kernel
    }

    /// `cv2.sepFilter2D` with `BORDER_REPLICATE`: horizontal then vertical, both borders repeated.
    static func convolve(_ values: [Float], width: Int, height: Int,
                         kernelX: [Double], kernelY: [Double]) -> [Float] {
        let rx = kernelX.count / 2, ry = kernelY.count / 2
        var horizontal = [Float](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for k in -rx...rx {
                    let sx = min(width - 1, max(0, x + k))
                    sum += Double(values[y * width + sx]) * kernelX[k + rx]
                }
                horizontal[y * width + x] = Float(sum)
            }
        }
        var output = [Float](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for k in -ry...ry {
                    let sy = min(height - 1, max(0, y + k))
                    sum += Double(horizontal[sy * width + x]) * kernelY[k + ry]
                }
                output[y * width + x] = Float(sum)
            }
        }
        return output
    }

    // MARK: the resamples

    /// `cv2.resize(..., INTER_AREA)` on the working image the colour match reads.
    private static func resizedRGB(_ values: [Float], width: Int, height: Int,
                                   toWidth: Int, toHeight: Int) -> [Float] {
        if width == toWidth, height == toHeight {
            return values
        }
        return areaResize(values, width: width, height: height, channels: 3,
                          toWidth: toWidth, toHeight: toHeight)
    }

    /// `INTER_AREA`: each destination pixel is the weighted mean of the source pixels its cell covers
    /// (both axes, exact overlaps), in float.
    static func areaResize(_ values: [Float], width w0: Int, height h0: Int,
                           channels: Int, toWidth w1: Int, toHeight h1: Int) -> [Float] {
        var output = [Float](repeating: 0, count: channels * w1 * h1)
        let scaleX = Double(w0) / Double(w1), scaleY = Double(h0) / Double(h1)
        for y1 in 0..<h1 {
            let startY = Double(y1) * scaleY, endY = Double(y1 + 1) * scaleY
            let firstY = Int(startY.rounded(.down)), lastY = min(h0 - 1, Int(endY.rounded(.up))) 
            for x1 in 0..<w1 {
                let startX = Double(x1) * scaleX, endX = Double(x1 + 1) * scaleX
                let firstX = Int(startX.rounded(.down)), lastX = min(w0 - 1, Int(endX.rounded(.up)))
                var sums = [Double](repeating: 0, count: channels)
                var total = 0.0
                for sy in firstY...lastY {
                    let overlapY = min(endY, Double(sy + 1)) - max(startY, Double(sy))
                    if overlapY <= 0 { continue }
                    for sx in firstX...lastX {
                        let overlapX = min(endX, Double(sx + 1)) - max(startX, Double(sx))
                        if overlapX <= 0 { continue }
                        let area = overlapX * overlapY
                        total += area
                        for c in 0..<channels {
                            sums[c] += Double(values[(sy * w0 + sx) * channels + c]) * area
                        }
                    }
                }
                for c in 0..<channels {
                    output[(y1 * w1 + x1) * channels + c] = Float(sums[c] / total)
                }
            }
        }
        return output
    }

    /// `cv2.resize(..., INTER_LINEAR)`, with clamped borders (the source reflects; the working grid
    /// is used only above a 64-pixel feather, which `--mask` never asks for).
    static func linearResize(_ values: [Float], width w0: Int, height h0: Int,
                             channels: Int, toWidth w1: Int, toHeight h1: Int) -> [Float] {
        var output = [Float](repeating: 0, count: channels * w1 * h1)
        let scaleX = Double(w0) / Double(w1), scaleY = Double(h0) / Double(h1)
        for y1 in 0..<h1 {
            let fy = min(Double(h0 - 1), max(0, (Double(y1) + 0.5) * scaleY - 0.5))
            let y0 = Int(fy.rounded(.down)), y0p = min(h0 - 1, y0 + 1), ty = fy - Double(y0)
            for x1 in 0..<w1 {
                let fx = min(Double(w0 - 1), max(0, (Double(x1) + 0.5) * scaleX - 0.5))
                let x0 = Int(fx.rounded(.down)), x0p = min(w0 - 1, x0 + 1), tx = fx - Double(x0)
                for c in 0..<channels {
                    let a = Double(values[(y0 * w0 + x0) * channels + c])
                    let b = Double(values[(y0 * w0 + x0p) * channels + c])
                    let d = Double(values[(y0p * w0 + x0) * channels + c])
                    let e = Double(values[(y0p * w0 + x0p) * channels + c])
                    let top = a * (1 - tx) + b * tx
                    let bottom = d * (1 - tx) + e * tx
                    output[(y1 * w1 + x1) * channels + c] = Float(top * (1 - ty) + bottom * ty)
                }
            }
        }
        return output
    }

    /// `cv2.GaussianBlur(..., (0, 0), sigma)`: `ksize = cvRound(sigma·8 + 1) | 1`, coefficients
    /// `exp(−i²/2σ²)` normalized, `BORDER_REFLECT_101`.
    static func gaussianBlur(_ values: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        let size = Int((sigma * 8 + 1).rounded()) | 1
        let radius = size / 2
        var kernel = (0...2 * radius).map { i in exp(-pow(Double(i - radius), 2) / (2 * sigma * sigma)) }
        let total = kernel.reduce(0, +)
        kernel = kernel.map { $0 / total }
        func reflect(_ i: Int) -> Int {
            guard height > 1 else { return 0 }
            var i = i
            while i < 0 || i >= height { i = i < 0 ? -i : 2 * (height - 1) - i }
            return i
        }
        func reflectX(_ i: Int) -> Int {
            guard width > 1 else { return 0 }
            var i = i
            while i < 0 || i >= width { i = i < 0 ? -i : 2 * (width - 1) - i }
            return i
        }
        var horizontal = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for k in 0...2 * radius {
                    sum += values[y * width + reflectX(x + k - radius)] * kernel[k]
                }
                horizontal[y * width + x] = sum
            }
        }
        var output = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for k in 0...2 * radius {
                    sum += horizontal[reflect(y + k - radius) * width + x] * kernel[k]
                }
                output[y * width + x] = sum
            }
        }
        return output
    }

    /// `np.median`: the middle value, the mean of the two middle ones for an even count.
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
}
