// **The expand tool's editor** — PS-like: the image fitted on the canvas, around it the grey the
// render will paint, the rim dashed, handles on the edges and corners. A handle dragged outward
// grows its side's percent (0–200, never negative); the drawn canvas is the plan's (`Expand.plan`),
// snapped to 32 as the render will read it. The ratio chips recenter the canvas to a proportion;
// « Expand » goes through the same attachment the pads form takes. Leaving the tool without it
// drops the draft — nothing is attached until « Expand ».

import Siliconed
import SwiftUI

struct ExpandEditor: View {
    @Bindable var app: AppState
    let image: CGImage

    /// The draft: the pads as the handles leave them, the workflow's own 30/30/0/0 to start. Gone
    /// when the tool leaves — nothing is attached until « Expand ».
    @State private var pads = Expand.Pads()
    /// The grip in a drag, with the pads where it began (the translation is from the drag's start).
    @State private var held: (Grip, Expand.Pads)?
    /// The ratio chip pressed (an index into `Self.ratios`); a handle drag leaves it (the pads are
    /// then the handles' own — « free »).
    @State private var chip = 0

    /// Where the pointer holds: an edge grows one side, a corner grows two.
    enum Grip: Hashable {
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// The proportions the chips offer — the ratios image-makers pick, plus « free ».
    private static let ratios: [(Int, Int)?] = [nil, (1, 1), (3, 2), (2, 3), (4, 3), (3, 4), (16, 9), (9, 16)]

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { space in
                let fitted = fitted(in: space.size)
                ZStack(alignment: .topLeading) {
                    if let plan {
                        greyCanvas(plan, around: fitted)
                    }
                    Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                        .resizable()
                        .interpolation(.high)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                    if let plan {
                        handles(plan, around: fitted)
                    }
                }
                .onExitCommand { app.choose(.pan) }
                .clipped()
                .onContinuousHover { phase in
                    switch phase {
                    case .active: app.canvasHover = true
                    case .ended: app.canvasHover = false
                    }
                }
                .onDisappear { app.canvasHover = false }
            }
            bar
        }
        .padding(28)
    }

    // ── The geometry ──

    /// The image fitted in the canvas's frame, never enlarged at 100 % — then the editor's own
    /// zoom (`app.expandZoom`, the wheel and the rail's buttons) about the frame's center, moved by
    /// `app.expandOffset`. The zoom folds into the layout, not a `scaleEffect`: the handles' drag
    /// reads the same scale back, so a drag is the same percent at every zoom.
    private func fitted(in size: CGSize) -> CGRect {
        let base = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height), 1)
        let scale = base * app.expandZoom
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        return CGRect(x: (size.width - width) / 2 + app.expandOffset.width,
                      y: (size.height - height) / 2 + app.expandOffset.height,
                      width: width, height: height)
    }

    /// **The plan, from the pads** — never a private rounding: the canvas drawn here is the one the
    /// render reads (`crop`), at the size the render will have (`width`, `height`).
    private var plan: Expand.Plan? { try? Expand.plan(pads: pads, width: image.width, height: image.height) }

    // ── The grey canvas and its handles ──

    /// The canvas the pads grow: grey where the render will paint, dashed at the rim, the image
    /// sitting at the plan's own offset (`crop.x`, `crop.y`) — the canvas can be capped, so the
    /// image's place inside it is the plan's, not an assumption.
    private func greyCanvas(_ plan: Expand.Plan, around fitted: CGRect) -> some View {
        let scale = fitted.width / CGFloat(plan.imageWidth)
        let rect = CGRect(x: fitted.minX - CGFloat(plan.crop.x) * scale,
                          y: fitted.minY - CGFloat(plan.crop.y) * scale,
                          width: CGFloat(plan.crop.width) * scale,
                          height: CGFloat(plan.crop.height) * scale)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.5).opacity(0.32))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.control.opacity(0.55),
                              style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .allowsHitTesting(false)
    }

    /// The handles: capsules on the edges, circles on the corners — each a grip that drags its own
    /// side (corners, both of theirs), outward only, never under the image.
    private func handles(_ plan: Expand.Plan, around fitted: CGRect) -> some View {
        let scale = fitted.width / CGFloat(plan.imageWidth)
        let rect = CGRect(x: fitted.minX - CGFloat(plan.crop.x) * scale,
                          y: fitted.minY - CGFloat(plan.crop.y) * scale,
                          width: CGFloat(plan.crop.width) * scale,
                          height: CGFloat(plan.crop.height) * scale)
        return ForEach(Grip.all, id: \.self) { grip in
            handleShape(grip)
                .position(x: point(grip, in: rect).x, y: point(grip, in: rect).y)
                .gesture(gripGesture(grip, scale: scale))
        }
    }

    /// A capsule on an edge, a circle on a corner; the one held is tinted.
    private func handleShape(_ grip: Grip) -> some View {
        let heldThis = held?.0 == grip
        let shape: some Shape = grip.isCorner
            ? AnyShape(Circle())
            : AnyShape(Capsule())
        return shape
            .fill(heldThis ? AnyShapeStyle(Palette.control) : AnyShapeStyle(.white))
            .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 0.7).padding(0.15))
            .frame(width: grip.isCorner ? 14 : 22, height: grip.isCorner ? 14 : 10)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    /// Where a grip sits, on the canvas's rect.
    private func point(_ grip: Grip, in rect: CGRect) -> CGPoint {
        switch grip {
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// The drag: translation in points, into percent of the image's side — outward grows, inward
    /// shrinks to nothing at most. The chip's highlight goes with it (the pads are the handles' own).
    private func gripGesture(_ grip: Grip, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let start: Expand.Pads
                if let (heldGrip, heldPads) = held, heldGrip == grip {
                    start = heldPads
                } else {
                    held = (grip, pads)
                    chip = 0
                    start = pads
                }
                let dx = Double(value.translation.width) / (scale * Double(image.width)) * 100
                let dy = Double(value.translation.height) / (scale * Double(image.height)) * 100
                var next = start
                switch grip {
                case .left: next.left = grown(start.left, -dx)
                case .right: next.right = grown(start.right, dx)
                case .top: next.top = grown(start.top, -dy)
                case .bottom: next.bottom = grown(start.bottom, dy)
                case .topLeft:
                    next.left = grown(start.left, -dx); next.top = grown(start.top, -dy)
                case .topRight:
                    next.right = grown(start.right, dx); next.top = grown(start.top, -dy)
                case .bottomLeft:
                    next.left = grown(start.left, -dx); next.bottom = grown(start.bottom, dy)
                case .bottomRight:
                    next.right = grown(start.right, dx); next.bottom = grown(start.bottom, dy)
                }
                pads = next
            }
            .onEnded { _ in held = nil }
    }

    /// One side's pad, grown by the drag's delta, clamped to the pads' range.
    private func grown(_ value: Double, _ delta: Double) -> Double {
        min(max(value + delta, 0), 200)
    }

    // ── The ratio chips ──

    /// **A chip**: the canvas snapped to the proportion **from the image alone** — never grown from
    /// the pads a previous chip left, so chips can be switched forever without creeping to the
    /// 5120 cap. The image's shape against the proportion decides where the border goes: a narrower
    /// image grows the sides, a wider one the top and bottom, an equal one spreads a plain 30 %
    /// over all four. A side the proportion does not need falls back to 0 — the handles' drag is
    /// the only thing that keeps a pad (the « free » chip).
    private func snap(_ ratio: (Int, Int)) {
        let w = Double(image.width), h = Double(image.height)
        let want = Double(ratio.0) / Double(ratio.1)
        let have = w / h
        if abs(have - want) < 0.0001 {
            pads = Expand.Pads(left: 30, right: 30, top: 30, bottom: 30)
        } else if have < want {
            // The canvas's width must be the height × the proportion: the sides share the border.
            let pad = grown(0, (h * want - w) / 2 / w * 100)
            pads = Expand.Pads(left: pad, right: pad, top: 0, bottom: 0)
        } else {
            let pad = grown(0, (w / want - h) / 2 / h * 100)
            pads = Expand.Pads(left: 0, right: 0, top: pad, bottom: pad)
        }
    }

    // ── The bar ──

    private var bar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(Array(Self.ratios.enumerated()), id: \.offset) { index, ratio in
                    Button {
                        if let ratio { snap(ratio) }
                        chip = index
                    } label: {
                        Text(verbatim: chipLabel(ratio))
                            .font(.callout)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background {
                                if chipMatches(index) {
                                    Capsule().fill(Palette.control.opacity(0.18))
                                }
                            }
                            .foregroundStyle(chipMatches(index) ? AnyShapeStyle(Palette.control) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .help(chipHelp(ratio))
                }
            }
            Divider().frame(height: 22)
            readout
                .frame(minWidth: 170, alignment: .leading)
            Spacer(minLength: 12)
            Button("Cancel") { app.choose(.pan) }
                .help("Leave without the pads (Esc)")
            Button("Expand") { commit() }
                .buttonStyle(.prominent)
                .disabled(plan == nil)
                .help(plan == nil ? Text("The canvas cannot be this shape: give a side a percent to grow by")
                      : Text("The pads go to the workflow: « Generate » says « Expand »"))
        }
        .imageScale(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glass(Capsule())
    }

    private func chipLabel(_ ratio: (Int, Int)?) -> String {
        if let ratio { return "\(ratio.0):\(ratio.1)" }
        return String(localized: "Free", comment: "The expand's free proportion: the handles' own")
    }

    private func chipHelp(_ ratio: (Int, Int)?) -> String {
        guard let ratio else {
            return String(localized: "Keep the handles' proportions", comment: "The « free » chip's help")
        }
        return String(localized: "Center the canvas to \(ratio.0):\(ratio.1)",
                      comment: "A ratio chip's help: the canvas snapped to the proportion")
    }

    private func chipMatches(_ index: Int) -> Bool {
        chip == index
    }

    /// The plan said out: the canvas as the render reads it, then the size it will render at.
    @ViewBuilder private var readout: some View {
        if let plan {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(String(plan.crop.width)) × \(String(plan.crop.height))")
                        .font(.callout).monospacedDigit()
                    Text("The canvas")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.right").font(.callout).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(String(plan.width)) × \(String(plan.height))")
                        .font(.callout).monospacedDigit().foregroundStyle(Palette.control)
                    HStack(spacing: 4) {
                        Text("The render")
                            .font(.caption).foregroundStyle(.secondary)
                        if let need = need {
                            Text(verbatim: Figures.memory(need))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            Text("The canvas cannot be this shape: give a side a percent to grow by")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the canvas needs of memory, as the rack's own estimate reads it — the render's size and
    /// the model the workflow will take.
    private var need: Int? {
        guard let plan, app.card != nil else { return nil }
        return app.need(RecommendedFormat(plan.width, plan.height), images: 1)
    }

    /// **« Expand »**: the pads to the workflow, the same attachment the pads form takes. A refusal
    /// leaves the editor up (the reason is said); success brings the hand back.
    private func commit() {
        Task {
            await app.attachExpand(pads: pads)
            if app.attachedExpand != nil { app.choose(.pan) }
        }
    }
}

extension ExpandEditor.Grip {
    var isCorner: Bool {
        switch self {
        case .left, .right, .top, .bottom: return false
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        }
    }

    static let all: [ExpandEditor.Grip] = [.left, .right, .top, .bottom,
                                           .topLeft, .topRight, .bottomLeft, .bottomRight]
}
