import XCTest
@testable import Siliconed

/// **The crop's return** (`Patch.composited`, the workflow's `GH_CropRestore`): the percentages, the
/// feather's shape, the colour match, and the promise that the delivered image is the original's size
/// with nothing touched outside the ring.
final class PasteTests: XCTestCase {

    private func image(_ width: Int, _ height: Int,
                       color: (Int, Int) -> (Float, Float, Float)) -> ImageRGB {
        var pixels = [Float](repeating: 0, count: 3 * width * height)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = color(x, y)
                let i = y * width + x
                pixels[i] = r * 2 - 1
                pixels[width * height + i] = g * 2 - 1
                pixels[2 * width * height + i] = b * 2 - 1
            }
        }
        return ImageRGB(pixels: pixels, height: height, width: width)
    }

    private func box(_ width: Int, _ height: Int, x: Int, y: Int, w: Int, h: Int) -> ImageMask {
        ImageMask(width: width, height: height, values: (0..<(width * height)).map { i in
            let px = i % width, py = i / width
            return px >= x && px < x + w && py >= y && py < y + h ? 1 : 0
        })
    }

    /// **`计算百分比像素值`**: `int((width + height) / 2 × percent / 100)`, at least one, zero for zero —
    /// the base is the mask's white box, and the workflow's 4 % and 5 % are two different rings.
    func testTheFeatherPixelsAreTheMasksPercentage() {
        XCTAssertEqual(Patch.percentagePixels(4, width: 458, height: 1512), 39)
        XCTAssertEqual(Patch.percentagePixels(5, width: 458, height: 1512), 49)
        XCTAssertEqual(Patch.percentagePixels(5, width: 100, height: 80), 4)
        XCTAssertEqual(Patch.percentagePixels(0, width: 100, height: 80), 0)
        XCTAssertEqual(Patch.percentagePixels(1, width: 3, height: 3), 1, "never less than a pixel")
    }

    /// **The mask's centre is replaced outright**: `mask ≥ 1` means the background term is zero —
    /// `粘贴 · 0 + 恢复 · 1`.
    func testTheMaskCentreIsFullyReplaced() throws {
        let original = image(200, 160) { _, _ in (0.25, 0.25, 0.25) }
        let mask = box(200, 160, x: 70, y: 60, w: 60, h: 40)
        let patch = Patch(image: original, mask: mask)
        let plan = try patch.plan()
        let rendered = image(plan.width, plan.height) { _, _ in (0.8, 0.8, 0.8) }
        let composited = patch.composited(rendered, plan: plan)
        XCTAssertEqual(composited.width, 200)
        XCTAssertEqual(composited.height, 160)
        let centre = (60 + 20) * 200 + (70 + 30)
        for c in 0..<3 {
            let value = (composited.pixels[c * 200 * 160 + centre] + 1) / 2
            XCTAssertEqual(value, 0.8, accuracy: 1 / 255, "the crop's own pixels, at the mask's centre")
        }
    }

    /// **The feather falls monotonically from the mask to nothing** (`创建羽化遮罩`'s kernel tail),
    /// and is exactly zero beyond `expansion + feather` pixels of the box.
    func testTheFeatherFallsMonotonicallyToNothing() {
        let width = 140, height = 100
        let values = (0..<(width * height)).map { i -> Float in
            let x = i % width, y = i / width
            return x >= 20 && x < 120 && y >= 10 && y < 90 ? 1 : 0
        }
        let feather = Patch.featherMask(values, width: width, height: height, expansion: 3, feather: 4)
        let row = stride(from: 60, through: 135, by: 1).map { feather[50 * width + $0] }
        for (a, b) in zip(row, row.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a, b - 1e-5, "the transition must not rise")
        }
        XCTAssertEqual(feather[50 * width + 40], 1, "inside the box, beyond the blur's reach")
        XCTAssertEqual(feather[50 * width + 135], 0, "outside expansion + feather, exactly zero")
        XCTAssertLessThan(feather[50 * width + 125], 0.5, "the ring is a fall, not a step")
    }

    /// **A colour match of an image with itself is the identity**: the samples all fit, so the gain
    /// stays 1 and the offset 0 — no drift from repeated pastes.
    func testTheColourMatchOfAnImageWithItselfChangesNothing() {
        let width = 40, height = 32, plane = width * height
        var pixels = [Float](repeating: 0, count: 3 * plane)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = Float(x) / 40
                pixels[plane + y * width + x] = Float(y) / 32
                pixels[2 * plane + y * width + x] = 0.5
            }
        }
        let match = Patch.colorMatched(pixels, width: width, height: height,
                                       reference: pixels, strength: 1)
        XCTAssertTrue(match.applied)
        XCTAssertEqual(match.gain, [1, 1, 1])
        XCTAssertEqual(match.offset, [0, 0, 0])
        for (a, b) in zip(match.pixels, pixels) {
            XCTAssertEqual(a, b, accuracy: 1e-6)
        }
    }

    /// **The default delivers the original's size; `--crop-only` the crop's** — the two paths differ
    /// by the paste, and outside 20 px of the mask's box the original is there bit for bit.
    func testTheDefaultPastesAndTheCropOnlyDoesNot() throws {
        let original = image(200, 160) { x, y in
            (Float(x) / 200, Float(y) / 160, 0.5)
        }
        let mask = box(200, 160, x: 70, y: 60, w: 60, h: 40)
        let patch = Patch(image: original, mask: mask)
        let plan = try patch.plan()
        let rendered = patch.render(plan)
        let composited = patch.composited(rendered, plan: plan)

        XCTAssertEqual(plan.width, 768, "the crop-only path is the plan's size")
        XCTAssertEqual([composited.width, composited.height], [200, 160], "the default is the original's")
        XCTAssertNotEqual(rendered.width, composited.width)

        let box = (x: 70, y: 60, width: 60, height: 40)
        for y in 0..<160 {
            for x in 0..<200 {
                let dx = max(box.x - x, 0, x - (box.x + box.width - 1))
                let dy = max(box.y - y, 0, y - (box.y + box.height - 1))
                let distance = max(dx, dy)
                guard distance > 20 else { continue }
                for c in 0..<3 {
                    let i = c * 200 * 160 + y * 200 + x
                    XCTAssertEqual(composited.pixels[i], original.pixels[i],
                                   "\(x), \(y): beyond the ring the input itself")
                }
            }
        }
    }

    /// **An entry keeps the paste choice**, so a redo draws the same image (default: on).
    func testTheSettingsKeepThePasteChoice() {
        XCTAssertTrue(Patch.Settings().paste)
        XCTAssertFalse(Patch.Settings(paste: false).paste)
    }
}
