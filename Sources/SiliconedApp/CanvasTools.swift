// **The canvas's tools** — PS-like: the image on the canvas is the editor. The hand pans and zooms,
// the brush paints the mask on image 1 at once (an old session continues), the expand grows the
// canvas with draggable handles. Leaving a tool commits what it made — the painted mask attaches by
// itself, the expand's pads live in their editor (`ExpandEditor.swift`) until « Expand » is pressed.
// The rail sits at the canvas's top left, the fold button of the rack on its own above the tools.

import Siliconed
import SwiftUI

/// **The tool the canvas holds.** `pan` is the canvas as it was — zoom, pan, double-click back; the
/// two editors (`MaskEditor`, `ExpandEditor`) take the canvas in the place of the image while their
/// tool holds.
enum CanvasTool: String, CaseIterable, Identifiable {
    case pan, brush, expand
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pan: "hand.raised"
        case .brush: "paintbrush.pointed"
        case .expand: "arrow.up.and.down.and.arrow.left.and.right"
        }
    }

    var help: String {
        switch self {
        case .pan:
            return String(localized: "Pan and zoom (drag, pinch, double-click to fit)",
                          comment: "The pan tool's help: the canvas as it is")
        case .brush:
            return String(localized: "Paint the mask: paint on the image, leave the tool to use it",
                          comment: "The brush tool's help: the strokes become the mask")
        case .expand:
            return String(localized: "Expand: drag the handles to grow the canvas, then expand",
                          comment: "The expand tool's help: the handles grow the canvas")
        }
    }
}

extension AppState {
    /// **Taking a tool**: the brush's strokes commit on the way out (dropped when nothing was
    /// painted), the expand's draft lives only in its editor. Then the tool begins — with the
    /// refusal's sentence flashed, and the canvas kept whole, when it cannot.
    func choose(_ tool: CanvasTool) {
        guard tool != canvasTool else { return }
        if canvasTool == .brush, let session = paintingMask {
            // Empty strokes say nothing: they go without a toast.
            if session.strokes.isEmpty { cancelMaskPainting() } else { commitMaskPainting() }
        }
        // The expand editor's zoom is its own: leaving the tool — or coming back — fits again.
        if canvasTool == .expand || tool == .expand {
            expandZoom = 1
            expandOffset = .zero
            canvasHover = false
        }
        canvasTool = tool
        switch tool {
        case .pan: break
        case .brush: beginBrushPainting()
        case .expand: beginExpandingOnCanvas()
        }
    }

    /// **The brush tool's beginning**: the mask begins on the image the moment the tool is chosen —
    /// an old session on the same image continues, a changed image begins a fresh one. The refusals
    /// are the mask's own, flashed, and the hand comes back.
    func beginBrushPainting() {
        guard let image = editInputs.first?.shown else {
            flash(String(localized: "Attach an image first: the mask must have the image’s size.",
                         comment: "A mask without image 1: there is nothing to patch"))
            canvasTool = .pan
            return
        }
        guard canPatchMask else {
            flash(String(localized: "\(modelName(identifier)) has no mask workflow: a mask needs a model that edits by reference (Qwen-Image-2.1).",
                         comment: "The model refuses a patch: no additive start, or no image encoder"))
            canvasTool = .pan
            return
        }
        if let session = paintingMask {
            if session.imageID == image.id { return }
            paintingMask = nil
        }
        beginMaskPainting()
    }

    /// **The expand tool's beginning**: the editor takes the canvas. The pads themselves live in the
    /// editor until « Expand »; beginning says the same refusals the pads form says.
    func beginExpandingOnCanvas() {
        guard editInputs.first?.shown != nil else {
            flash(String(localized: "Attach an image first: the canvas grows around it.",
                         comment: "An expand without image 1: there is nothing to grow"))
            canvasTool = .pan
            return
        }
        guard canAttachExpand else {
            flash(String(localized: "An expand needs a model that edits by reference (Qwen-Image-2.1), image 1 alone",
                         comment: "The expand tile shows it: where the workflow is and one image sits in the lab"))
            canvasTool = .pan
            return
        }
        showsExploration = false
        followsRender = false
        comparesOriginal = false
    }
}

/// **The rail at the canvas's top left**: the rack's fold button above, then the three tools. The
/// editors' own bars say what each can do; the rail is how one moves between them — brush in, hand
/// out, the mask committed on the way.
private struct ToolRail: View {
    @Bindable var app: AppState

    /// While the render runs the tools have no image to take, and the crop has its own editor: the
    /// rail steps aside. The fold stays — the rack answers whenever it is asked.
    var visible: Bool { app.cropping == nil && app.currentJob == nil }

    /// **The rack folded away entirely** by the divider dragged past the edge: a fold the split view
    /// keeps to itself — `rackVisibility` is never told of it. `AppState.rackHidden` reads the
    /// canvas's leading edge instead. The button's first work is to bring the column back **as it
    /// was** — `sidebarCompact` is the drag's to leave alone; only then does it fold the rack to
    /// its model picker.
    private var rackHidden: Bool { app.rackHidden }

    /// Either fold reads as folded — the compact strip or the column gone — and wears the button's
    /// indigo; the full chain alone is the unfolded rack.
    private var folded: Bool { app.sidebarCompact || rackHidden }

    var body: some View {
        VStack(spacing: 3) {
            Button {
                if rackHidden { app.rackVisibility = .all } else { app.sidebarCompact.toggle() }
            } label: {
                // One symbol for both states — `sidebar.left.fill` is missing on this macOS and
                // renders nothing, leaving a blank the size of the button. The state is the color:
                // indigo on its capsule while the rack is folded (either fold), gray when it is out.
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background {
                        if folded {
                            Capsule().fill(Palette.control.opacity(0.18))
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(folded ? Text("Unfold the rack: the chain, its boxes and « Generate »")
                   : Text("Fold the rack: the model picker alone"))
            .accessibilityLabel(Text(folded ? "Unfold the Rack" : "Fold the Rack"))
            .foregroundStyle(folded ? AnyShapeStyle(Palette.control) : AnyShapeStyle(.secondary))
            .overlay(alignment: .topTrailing) {
                // The rack's footer speaks while the strip is away: a dot on the fold says so.
                if app.sidebarCompact, app.footerSpeaks {
                    Circle().fill(Color(nsColor: .systemOrange)).frame(width: 7, height: 7).offset(x: 9, y: -3)
                }
            }
            // The divider's width is its own: a bare `Divider` would take the overlay's whole width
            // and stretch the rail (and its glass) across the canvas.
            Divider().frame(width: 14, height: 14)
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    app.choose(tool)
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .background {
                            if app.canvasTool == tool {
                                Capsule().fill(Palette.control.opacity(0.18))
                            }
                        }
                        .foregroundStyle(app.canvasTool == tool ? AnyShapeStyle(Palette.control) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(tool.help)
                .accessibilityLabel(Text(verbatim: String(localized: String.LocalizationValue(tool.rawValue), comment: "A canvas tool's name")))
            }
            // The canvas's zoom, the hand tool's own: a wheel zooms too, but a button is always
            // there. The brush paints the mask fitted — its editor wants no zoom — and the expand's
            // editor zooms its own (`expandZoom`).
            if app.canvasTool != .brush {
                Divider().frame(width: 14, height: 14)
                Button {
                    stepZoom(1 / 1.5)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(zoom <= zoomFloor)
                .help(Text("Zoom Out (⌘−)"))
                .accessibilityLabel(Text("Zoom Out"))
                Button {
                    resetZoom()
                } label: {
                    Text(verbatim: "\(Int((zoom * 100).rounded()))%")
                        .font(.caption2).monospacedDigit()
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(zoom != 1 ? AnyShapeStyle(Palette.control) : AnyShapeStyle(.secondary))
                .disabled(zoom <= 1)
                .help(Text("Zoom to Fit (⌘0)"))
                .accessibilityLabel(Text("Zoom to Fit"))
                Button {
                    stepZoom(1.5)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(zoom >= 8)
                .help(Text("Zoom In (⌘+)"))
                .accessibilityLabel(Text("Zoom In"))
            }
        }
        .padding(4)
        .glass(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .transition(.opacity)
    }

    /// The zoom the rail's buttons work on: the canvas's own, the expand editor's while its tool
    /// holds (`expandZoom`).
    private var zoom: CGFloat { app.canvasTool == .expand ? app.expandZoom : app.zoom }

    /// The zoom's lowest step: the canvas's own never under its fit (1); the expand editor's to the
    /// pads' cap (`AppState.minExpandZoom`) — the whole canvas seen, however large the pads grew it.
    private var zoomFloor: CGFloat { app.canvasTool == .expand ? AppState.minExpandZoom : 1 }

    private func stepZoom(_ factor: CGFloat) {
        let z = min(max(zoom * factor, zoomFloor), 8)
        if app.canvasTool == .expand { app.expandZoom = z } else { app.zoom = z }
    }

    private func resetZoom() {
        if app.canvasTool == .expand { app.expandZoom = 1 } else { app.zoom = 1 }
    }
}

extension View {
    /// **The rail over the canvas**: the fold and the tools at its top left. Hidden while a crop is
    /// made or the render runs — the crop has its own editor, the tools have nothing to take yet.
    @ViewBuilder func toolRail(_ app: AppState) -> some View {
        if app.cropping == nil && app.currentJob == nil {
            ToolRail(app: app)
        } else {
            EmptyView()
        }
    }
}
