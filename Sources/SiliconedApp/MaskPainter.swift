// **The mask painted over image 1** (`MaskEditor`, `AppState+Mask.swift`): strokes in the image's own
// pixels, rasterised once — the same `ImageMask` the PNG path reads.
//
//     brush / eraser ── strokes (image pixels) ──▶ maskImage() ──▶ ReferenceImage ──▶ attachMask
//
// - **One rasteriser**: the strokes become a white-on-black bitmap of image 1's size, never scaled
//   here — `attachMask` checks the size and `ImageMask` applies its own `> 0.1`, hole filling and
//   `Patch.minimumPixels`, exactly as it does for an imported PNG.
// - **The canvas is the preview**: strokes are kept as geometry and drawn by SwiftUI over the fitted
//   image, so the window's size never changes what was painted; the editor has no zoom and no pan
//   (the image is fitted whole, the brush follows the fit).
// - **Undo is one stroke**, `⌘Z` or the bar's « Undo »; « Clear » is every stroke. A stroke painted
//   again in the eraser is taken back as one, as drawn.

import AppKit
import Siliconed
import SwiftUI

/// **The mask being painted**: image 1's pixels, the strokes so far, and the tool they are drawn with.
/// `@unchecked Sendable`: the image is immutable and the strokes are values — the rasteriser runs
/// off the main thread.
struct MaskSession: @unchecked Sendable {
    enum Tool { case brush, eraser }

    /// One drag: its tool, its radius (image pixels), and the points it went through (image pixels,
    /// top-left origin — the same frame the image is shown in).
    struct Stroke {
        var tool: Tool
        var radius: CGFloat
        var points: [CGPoint]
    }

    /// Image 1, decoded at its own size: the canvas and the mask's frame.
    let image: CGImage
    /// What the mask will be attached to — a replaced image 1 takes the strokes with it.
    let imageID: ReferenceImage.ID
    var strokes: [Stroke] = []
    var tool: Tool = .brush
    /// The brush's radius, in the canvas's points (the stroke turns it into image pixels as it starts).
    var brush: CGFloat = 18

    /// The workflow's green, over the image: the same `#00FF00` its crop tint uses.
    static let overlay = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let overlayOpacity: Double = 0.4
    static let brushRange: ClosedRange<CGFloat> = 3...80

    var isEmpty: Bool { strokes.isEmpty }

    /// **The strokes as a mask of image 1's size**: a grayscale bitmap, the brush white and the eraser
    /// black, in the order drawn — what `ImageMask(image:)` reads as brightness, as it reads a PNG's.
    func maskImage() -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Points are kept top-left, as the canvas draws them; the bitmap's origin is bottom-left.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            let gray: CGFloat = stroke.tool == .brush ? 1 : 0
            let radius = max(0.5, stroke.radius)
            if stroke.points.count == 1, let only = stroke.points.first {
                context.setFillColor(gray: gray, alpha: 1)
                context.fillEllipse(in: CGRect(x: only.x - radius, y: only.y - radius,
                                               width: 2 * radius, height: 2 * radius))
            } else if let first = stroke.points.first {
                context.setStrokeColor(gray: gray, alpha: 1)
                context.setLineWidth(2 * radius)
                context.beginPath()
                context.move(to: first)
                for point in stroke.points.dropFirst() { context.addLine(to: point) }
                context.strokePath()
            }
        }
        return context.makeImage()
    }
}

// MARK: - The view

/// **The brush over image 1**, in the canvas's place: the image fitted, the strokes in the workflow's
/// green at 0.4, a ring where the brush will land, and under it the tool, the size, « Undo », « Clear »,
/// « Cancel » and « Use Mask ».
struct MaskEditor: View {
    @Bindable var app: AppState
    let session: MaskSession

    /// The stroke under the pointer: its points in image pixels, and the radius the stroke began with.
    @State private var current: [CGPoint] = []
    @State private var radius: CGFloat = 0
    @State private var cursor: CGPoint?

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let frame = fitted(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Image(decorative: session.image, scale: 1)
                        .resizable().interpolation(.high)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                    Canvas { context, _ in draw(&context, in: frame) }
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag($0, in: frame) }
                    .onEnded { _ in end() })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): cursor = frame.contains(point) ? point : nil
                    case .ended: cursor = nil
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Mask brush"))
                .accessibilityValue(Text(verbatim: "\(session.image.width) × \(session.image.height)"))
            }
            bar
        }
        .padding(28)
        .transition(.opacity)
    }

    // ── geometry ──

    /// The image's rect: fitted whole, never enlarged past its own pixels' size.
    private func fitted(in size: CGSize) -> CGRect {
        let s = min(size.width / CGFloat(session.image.width), size.height / CGFloat(session.image.height), 1)
        let w = CGFloat(session.image.width) * s, h = CGFloat(session.image.height) * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// Image pixels per point in `frame`.
    private func scale(_ frame: CGRect) -> CGFloat { CGFloat(session.image.width) / max(frame.width, 1) }

    /// A point of the canvas, in image pixels, clamped to the image.
    private func imagePoint(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        let k = scale(frame)
        return CGPoint(x: min(max(point.x - frame.minX, 0), frame.width) * k,
                       y: min(max(point.y - frame.minY, 0), frame.height) * k)
    }

    // ── the gesture ──

    private func drag(_ value: DragGesture.Value, in frame: CGRect) {
        guard frame.width > 0, let session = app.paintingMask else { return }
        MainWindow.shared.releaseTextFocus()
        let point = imagePoint(value.location, in: frame)
        if current.isEmpty {
            radius = max(0.5, session.brush * scale(frame))
            current = [point]
        } else if let last = current.last, hypot(point.x - last.x, point.y - last.y) >= max(1, radius * 0.3) {
            current.append(point)
        }
    }

    private func end() {
        guard !current.isEmpty else { return }
        app.addMaskStroke(MaskSession.Stroke(tool: session.tool, radius: max(0.5, radius), points: current))
        current = []
    }

    // ── the drawing ──

    private func draw(_ context: inout GraphicsContext, in frame: CGRect) {
        for stroke in session.strokes { paint(stroke, &context, in: frame) }
        if !current.isEmpty {
            paint(MaskSession.Stroke(tool: session.tool, radius: max(0.5, radius), points: current), &context, in: frame)
        }
        // The ring: the brush's radius in points, where the next stroke lands.
        if let cursor {
            let r = session.brush
            context.stroke(Path(ellipseIn: CGRect(x: cursor.x - r, y: cursor.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.9)), lineWidth: 1)
            context.stroke(Path(ellipseIn: CGRect(x: cursor.x - r, y: cursor.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.black.opacity(0.4)), lineWidth: 1)
        }
    }

    private func paint(_ stroke: MaskSession.Stroke, _ context: inout GraphicsContext, in frame: CGRect) {
        let k = scale(frame)
        let width = max(1, 2 * stroke.radius / k)
        if stroke.tool == .eraser {
            // The canvas is transparent and the image is a sibling: taking out only the strokes drawn here.
            context.blendMode = .destinationOut
            fill(stroke, width: width, with: .color(.white), &context, in: frame)
            context.blendMode = .normal
        } else {
            fill(stroke, width: width,
                 with: .color(Color(cgColor: MaskSession.overlay).opacity(MaskSession.overlayOpacity)),
                 &context, in: frame)
        }
    }

    private func fill(_ stroke: MaskSession.Stroke, width: CGFloat, with shade: GraphicsContext.Shading,
                      _ context: inout GraphicsContext, in frame: CGRect) {
        let k = scale(frame)
        if stroke.points.count == 1, let only = stroke.points.first {
            let rect = CGRect(x: frame.minX + only.x / k - width / 2, y: frame.minY + only.y / k - width / 2,
                              width: width, height: width)
            context.fill(Path(ellipseIn: rect), with: shade)
            return
        }
        var path = Path()
        for (i, point) in stroke.points.enumerated() {
            let p = CGPoint(x: frame.minX + point.x / k, y: frame.minY + point.y / k)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        context.stroke(path, with: shade, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    // ── the bar ──

    private var bar: some View {
        HStack(spacing: 12) {
            Picker(String(localized: "Tool"), selection: Binding(get: { session.tool },
                                                               set: { app.setMaskTool($0) })) {
                Image(systemName: "paintbrush.pointed.fill").tag(MaskSession.Tool.brush)
                Image(systemName: "eraser.fill").tag(MaskSession.Tool.eraser)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 92)
            .help("Brush paints the area, eraser takes it back (B / E)")
            Divider().frame(height: 22)
            Text("Brush").foregroundStyle(.secondary)
            Slider(value: Binding(get: { session.brush }, set: { app.setMaskBrush($0) }),
                   in: MaskSession.brushRange)
            .frame(width: 110).controlSize(.small)
            .help("The brush's size")
            Text(verbatim: "\(Int(session.brush.rounded()))").monospacedDigit().frame(minWidth: 22)
            Divider().frame(height: 22)
            Text(verbatim: "\(session.image.width) × \(session.image.height)")
                .font(.callout).monospacedDigit()
                .help("The mask will be this size — image 1's")
            Divider().frame(height: 22)
            Button("Undo") { app.undoMaskStroke() }
                .disabled(session.isEmpty)
                .help("Take back the last stroke (⌘Z)")
            Button("Clear") { app.clearMaskStrokes() }
                .disabled(session.isEmpty)
                .help("Take back every stroke")
            Divider().frame(height: 22)
            Button("Cancel") { app.cancelMaskPainting() }
                .help("Leave without a mask (Esc)")
            Button("Use Mask") { app.commitMaskPainting() }
                .buttonStyle(.prominent)
                .disabled(session.isEmpty)
                .help(session.isEmpty ? Text("Paint the area to change first") : Text("This mask edits image 1 once (↩)"))
        }
        .imageScale(.large)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .glass(Capsule())
        .zIndex(2)
    }
}
