// **The painted mask** (`MaskPainter.swift`): the brush and the eraser as a mask of image 1's size.
//
// The strokes are geometry, rasterised once; these tests read that bitmap — where the paint landed, that
// the eraser takes it back, that the mask is image 1's size, and that a blank one is blank.

import AppKit
import Siliconed
import XCTest
@testable import SiliconedApp

final class MaskPainterTests: XCTestCase {
    private func image(_ side: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()!
    }

    private func mask(_ session: MaskSession) throws -> CGImage {
        try XCTUnwrap(session.maskImage())
    }

    /// The bitmap's bytes, a row a pixel: `row` 0 is the image's top row (the rasteriser flips the context).
    private func bytes(_ image: CGImage) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        return [UInt8](data)
    }

    private func covered(_ image: CGImage) -> Int {
        bytes(image).reduce(0) { $0 + ($1 >= 26 ? 1 : 0) }   // ImageMask's "> 0.1" of 8 bits
    }

    /// The mask is image 1's size, whatever the window shows.
    func testTheMaskIsImageOnesSize() throws {
        for side in [64, 256, 512] {
            let session = MaskSession(image: image(side), imageID: UUID())
            XCTAssertEqual(try mask(session).width, side)
            XCTAssertEqual(try mask(session).height, side)
        }
    }

    /// Where the brush went, in the image's own frame (top-left, as the canvas draws it).
    func testTheBrushPaintsWhereTheCanvasShows() throws {
        let side = 256
        var session = MaskSession(image: image(side), imageID: UUID())
        session.strokes = [MaskSession.Stroke(tool: .brush, radius: 12,
                                              points: [CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 40)])]
        let maskImage = try mask(session)
        XCTAssertGreaterThan(covered(maskImage), 300, "a 24 px wide band, 40 px long")
        XCTAssertLessThan(covered(maskImage), 1200, "and not the whole mask")

        // Rows are the image's: the stroke's row band is 40, not its mirror 216.
        let rows = bytes(maskImage)
        let near = (28...52).reduce(0) { $0 + Int(rows[$1 * side + 50]) }
        let far = (204...228).reduce(0) { $0 + Int(rows[$1 * side + 50]) }
        XCTAssertGreaterThan(near, 0, "the stroke landed at y 40")
        XCTAssertEqual(far, 0, "and nothing landed at y 216")
    }

    /// **The eraser takes it back** — the same path, painted black again.
    func testTheEraserTakesTheStrokeBack() throws {
        let side = 256
        var session = MaskSession(image: image(side), imageID: UUID())
        let path = [CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 100)]
        session.strokes = [MaskSession.Stroke(tool: .brush, radius: 20, points: path)]
        XCTAssertGreaterThan(covered(try mask(session)), 2000)
        session.strokes.append(MaskSession.Stroke(tool: .eraser, radius: 24, points: path))
        XCTAssertEqual(covered(try mask(session)), 0, "the eraser's wider band leaves nothing")
    }

    /// A tap is a dot: one point is a stroke too.
    func testATapIsADot() throws {
        var session = MaskSession(image: image(256), imageID: UUID())
        session.strokes = [MaskSession.Stroke(tool: .brush, radius: 10, points: [CGPoint(x: 128, y: 128)])]
        XCTAssertGreaterThan(covered(try mask(session)), 200)
        XCTAssertLessThan(covered(try mask(session)), 500, "π · 10² ≈ 314")
    }

    /// No strokes, no mask — and an empty one is a (blank) mask all the same.
    func testNoStrokesIsABlankMask() throws {
        let session = MaskSession(image: image(256), imageID: UUID())
        XCTAssertEqual(covered(try mask(session)), 0)
    }

    /// **The painted mask is the PNG's `ImageMask`**: image 1's size, the same conversion and the same
    /// `Patch.plan` — the painter has no second geometry.
    @MainActor
    func testAPaintedMaskDoesNotMakeASecondImageMask() async throws {
        let app = AppState(library: Library(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("MaskPainterTests-\(UUID().uuidString)")))
        let pixels = image(256)
        let shown = ReferenceImage(source: .image(pixels),
                                   vignette: NSImage(cgImage: pixels, size: NSSize(width: 256, height: 256)),
                                   name: "image.png", width: 256, height: 256)
        var session = MaskSession(image: pixels, imageID: shown.id)
        session.strokes = [MaskSession.Stroke(tool: .brush, radius: 20,
                                              points: [CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 100)])]
        let painted = try mask(session)
        let attached = ReferenceImage(source: .image(painted),
                                      vignette: NSImage(cgImage: painted, size: NSSize(width: 256, height: 256)),
                                      name: "Painted mask", width: 256, height: 256)
        await app.attachMask(attached, to: shown)
        XCTAssertNotNil(app.attachedMask)
        XCTAssertNil(app.problem)
        XCTAssertEqual(app.steps, Patch.defaultSteps, "the same 9 the PNG path takes")
        XCTAssertEqual(app.attachedMask?.mask.width, shown.width)
        let planned = try Patch.plan(mask: ImageMask(image: ImageRGB(cgImage: painted)), width: 256, height: 256)
        XCTAssertEqual(app.attachedMask?.plan, planned, "one crop, one plan, painted or imported")
    }
}
