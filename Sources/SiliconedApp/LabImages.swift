// **The Prompt Lab's images**, in a row under the text: the rack's (`AppState.inputs`), each with its role, then the subjects.
//
//     ┌──┐ 1 · Image to Edit ▾   ┌──┐ 2 · Reference ▾   ┌──┐ 3 · @alice      ┌┄┄┐ No Role ▾        ┌┄┄┐
//     │▣ │ Describe  Beta        │▣ │ Describe          │▣ │ Person · cited  ┊▣ ┊ 3 / 3: full     ┊+ ┊
//     └──┘                       └──┘                   └──┘                 └┄┄┘ Describe         └┄┄┘
//
// - **The edge says the role**: the image wire's rose, full for the image the model edits or starts from, lighter for
//   a reference or a cited subject; dashed for an image that does not go — neutral, or with a role the model lacks, which
//   the tile says (« “Reference”: no effect with Anima »). A change of model never gives nor converts a role (`LabInputs`).
// - **Under Qwen-Image-2.1** an image takes the next place as it comes in; its menu changes it (Image to Edit, Reference,
//   No Role) or names it. Full (three images with the cited subjects), a newcomer comes in without a role and says so.
// - **Under Z-Image, Anima, Krea 2, MOSS** an image comes in without a role: « Start From This Image » makes it the start
//   (its tile then carries the rack's strength), Describe writes what it shows into the text.
// - **Right-click**: Crop…, Paint Mask… (on image 1), Replace…, Name…, Reuse These Settings (a PNG Siliconed wrote), Remove.
// - A **subject** (`SubjectSheet.swift`) goes only when the text cites it by `@name`, after the images the roles send.

import AppKit
import Siliconed
import SwiftUI

struct LabImages: View {
    @Bindable var model: LabModel
    /// The row's own height: a horizontal scroll view takes all the height it is offered, so it is held to its tiles'.
    @State private var rowHeight = LabTile.picture.height + 4

    /// Where the render will place each image, by the carried list's order (from 1).
    private var numbers: (plain: [InputImage.ID: Int], subjects: [String: [Int]]) {
        guard case .success(let carry) = model.rack.carried else { return ([:], [:]) }
        var plain: [InputImage.ID: Int] = [:]
        var subjects: [String: [Int]] = [:]
        for (i, image) in carry.images.enumerated() {
            switch image {
            case .plain(let id, _): plain[id] = i + 1
            case .subject(let p): subjects[p.subject.id, default: []].append(i + 1)
            }
        }
        return (plain, subjects)
    }

    var body: some View {
        let numbers = numbers
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(model.pictures) { picture in
                        PictureTile(model: model, picture: picture, number: numbers.plain[picture.id])
                    }
                    if model.showsMaskTile { MaskTile(model: model) }
                    if model.showsExpandTile { ExpandTile(model: model) }
                    ForEach(model.subjects.all) { subject in
                        SubjectTile(model: model, subject: subject, numbers: numbers.subjects[subject.id] ?? [])
                    }
                    addTile
                }
                .padding(.vertical, 2)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
            }
            .frame(height: rowHeight)
            .scrollIndicators(.automatic)
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hint: LocalizedStringKey {
        if model.startIsImg2Img {
            switch model.pictures.count {
            case 0: return "Drop an image here to describe it, or to start the render from it."
            case 1: return "The render can start from one image: it keeps its composition, the strength says how far it moves away."
            default: return "The render can start from one image: it keeps its composition, the strength says how far it moves away. The others stay here, to be described."
            }
        }
        if model.capacity == 0 {
            return "This model does not read images: they stay here, to be described."
        }
        if model.pictures.isEmpty && model.subjects.all.isEmpty {
            return "Drop images here. The first one is the image to edit; a name makes a picture citable as @name in the text."
        }
        if model.rack.attachedMask != nil, model.rack.patchDecision(prompt: "").mode == .remove,
           model.rack.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No prompt: this render removes the marked area."
        }
        return "Image 1 is the one edited and gives the format. The rack takes 3 images at most."
    }

    private var addTile: some View {
        Menu {
            Button("Open Images…") { model.chooseImages() }
            Button("Name an Image…") { model.chooseImageToName() }
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                .foregroundStyle(WireKind.image.color.opacity(0.7))
                .overlay(Image(systemName: "plus").foregroundStyle(WireKind.image.color))
                .frame(width: LabTile.picture.width, height: LabTile.picture.height)
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .help("Open images — or drop them here, or send one from the history (Send to the Prompt Lab)")
        .accessibilityLabel(Text("Add an Image"))
    }
}

enum LabTile {
    static let picture = CGSize(width: 48, height: 64)
    static let meta: CGFloat = 150

    /// The edge of a tile's picture: the image wire's colour, full for the image the render edits or starts from, lighter
    /// for a reference or a subject; dashed for what does not go.
    @ViewBuilder static func edge(goes: Bool, main: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if goes {
            shape.strokeBorder(WireKind.image.color.opacity(main ? 1 : 0.6), lineWidth: 2)
        } else {
            shape.strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }
}

/// **The mask attached to image 1** — the entry to the 「移除」 path (`AppState+Mask.swift`). A tile beside
/// the images: « Attach Mask… » opens a PNG picker, « Paint Mask… » opens the brush over image 1 (`MaskEditor`);
/// once attached it shows the mask's thumbnail, its name, the crop's plan size, and « Remove Mask ». With a
/// mask attached, « Generate » edits image 1 through the workflow; the mask goes with that one click and the
/// next is an ordinary render. A brush-made mask and a PNG become the same `ImageMask`.
private struct MaskTile: View {
    let model: LabModel
    private var rack: AppState { model.rack }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let attached = rack.attachedMask {
                    Image(nsImage: attached.mask.vignette).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay(Image(systemName: "rectangle.dashed").foregroundStyle(.secondary))
                }
            }
            .frame(width: LabTile.picture.width, height: LabTile.picture.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { LabTile.edge(goes: rack.attachedMask != nil, main: false) }
            VStack(alignment: .leading, spacing: 3) {
                Text("Mask").font(.caption.weight(.semibold))
                    .foregroundStyle(rack.attachedMask == nil ? Color.secondary : WireKind.image.color)
                if let attached = rack.attachedMask {
                    Text(attached.mask.name).font(.caption2).lineLimit(2)
                        .help(attached.mask.name)
                    Text(verbatim: "\(attached.mask.width) × \(attached.mask.height) → \(attached.plan.width) × \(attached.plan.height)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Button("Paint Mask…") { rack.beginMaskPainting() }
                        .controlSize(.small)
                        .disabled(!rack.canAttachMask)
                        .help("Paint over image 1 again: the stroke you commit replaces this mask")
                    Button("Remove Mask") { rack.removeMask() }
                        .controlSize(.small)
                        .help("The next render is an ordinary one again, at the format the form shows")
                } else {
                    Button("Attach Mask…") { rack.chooseMask() }
                        .controlSize(.small)
                        .disabled(!rack.canAttachMask)
                    Button("Paint Mask…") { rack.beginMaskPainting() }
                        .controlSize(.small)
                        .disabled(!rack.canAttachMask)
                        .help("Paint the mask over image 1 with a brush and an eraser")
                    Text("PNG or brush: image 1’s size. White changes, black stays.")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(rack.canAttachMask
                              ? Text("A mask the size of image 1: white is what changes, black what stays — painted or imported")
                              : Text("A mask edits image 1 alone: one image in the lab, its size"))
                }
            }
            .frame(width: LabTile.meta, alignment: .leading)
        }
        .contextMenu {
            Button("Paint Mask…") { rack.beginMaskPainting() }.disabled(!rack.canAttachMask)
            if rack.attachedMask == nil {
                Button("Attach Mask…") { rack.chooseMask() }.disabled(!rack.canAttachMask)
            } else {
                Button("Remove Mask", role: .destructive) { rack.removeMask() }
            }
        }
    }
}

/// **The expand attached to image 1** — the entry to the 「扩图」 path (`AppState+Expand.swift`), a tile
/// beside the mask's: « Expand… » opens the pads form (`ExpandPadsSheet`), four percents and no brush;
/// once attached it shows the pads, the canvas's plan size, and « Remove Expand ». With the pads
/// attached, « Generate » grows image 1's canvas through the workflow; they go with that one click
/// and the next is an ordinary render.
private struct ExpandTile: View {
    let model: LabModel
    private var rack: AppState { model.rack }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .overlay(Image(systemName: "plus.forwardslash.minus")
                    .foregroundStyle(rack.attachedExpand == nil ? Color.secondary : WireKind.image.color))
                .frame(width: LabTile.picture.width, height: LabTile.picture.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay { LabTile.edge(goes: rack.attachedExpand != nil, main: false) }
            VStack(alignment: .leading, spacing: 3) {
                Text("Expand").font(.caption.weight(.semibold))
                    .foregroundStyle(rack.attachedExpand == nil ? Color.secondary : WireKind.image.color)
                if let attached = rack.attachedExpand {
                    Text(verbatim: Self.pads(attached.pads)).font(.caption2).lineLimit(1)
                        .help("The percents each side grows by: of the image's own sides, 0–200")
                    Text(verbatim: "→ \(attached.plan.crop.width) × \(attached.plan.crop.height) → \(attached.plan.width) × \(attached.plan.height)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        .help("The canvas, then the size the render will have")
                    Button("Pads…") { rack.beginExpand() }
                        .controlSize(.small)
                        .help("Open the pads again: what you commit replaces them")
                    Button("Remove Expand") { rack.removeExpand() }
                        .controlSize(.small)
                        .help("The next render is an ordinary one again, at the format the form shows")
                } else {
                    Button("Expand…") { rack.beginExpand() }
                        .controlSize(.small)
                        .disabled(!rack.canAttachExpand)
                        .help("Grow the canvas outward: four percents, no mask")
                    Text("No mask: four percents — the canvas grows outward, the original laid back inside.")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(rack.canExpand
                              ? Text("The canvas grows by percents of the image's own sides; the model draws the new border")
                              : Text("An expand needs a model that edits by reference (Qwen-Image-2.1), image 1 alone"))
                }
            }
            .frame(width: LabTile.meta, alignment: .leading)
        }
        .contextMenu {
            Button("Expand…") { rack.beginExpand() }.disabled(!rack.canAttachExpand)
            if rack.attachedExpand != nil {
                Button("Remove Expand", role: .destructive) { rack.removeExpand() }
            }
        }
    }

    /// `L 30 · R 30 · T 0 · B 0` — the four pads, in the canvas node's own order.
    static func pads(_ pads: Expand.Pads) -> String {
        "L \(Int(pads.left)) · R \(Int(pads.right)) · T \(Int(pads.top)) · B \(Int(pads.bottom))"
    }
}

/// **The expand's pads form** (« Expand… »): four percents of the image's own sides, the workflow's own
/// 30/30/0/0 in the fields — no brush, no mask. The plan is computed live (`Expand.plan`): the canvas
/// and the size the render will have, said before the click; a size the engine refuses (all four pads
/// 0, the patch path's short-side floor) says why and keeps the sheet open.
struct ExpandPadsSheet: View {
    let app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pads = Expand.Pads()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Expand").font(.headline)
            Text("Grow the canvas outward: the model draws the new border, and the original is laid back inside.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                field("Left", left)
                field("Right", right)
            }
            HStack(spacing: 12) {
                field("Top", top)
                field("Bottom", bottom)
            }
            preview
            HStack {
                Spacer(minLength: 8)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Expand") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(blocker != nil)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { if let attached = app.attachedExpand { pads = attached.pads } }
    }

    // MARK: The fields

    private var left: Binding<Double> { pad(\.left) }
    private var right: Binding<Double> { pad(\.right) }
    private var top: Binding<Double> { pad(\.top) }
    private var bottom: Binding<Double> { pad(\.bottom) }

    /// A pad typed in, kept inside the workflow's 0–200 (`Expand.Pads.range`).
    private func pad(_ side: WritableKeyPath<Expand.Pads, Double>) -> Binding<Double> {
        Binding(get: { pads[keyPath: side] },
                set: { pads[keyPath: side] = $0.isFinite ? min(max($0, Expand.Pads.range.lowerBound), Expand.Pads.range.upperBound) : 0 })
    }

    private func field(_ title: LocalizedStringKey, _ value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            TextField(value: value, format: .number.precision(.fractionLength(0))) { Text(title) }
                .labelsHidden().textFieldStyle(.roundedBorder).controlSize(.small)
                .multilineTextAlignment(.trailing).frame(width: 52).monospacedDigit()
            Text(verbatim: "%").foregroundStyle(.secondary)
        }
    }

    // MARK: The plan, before the click

    /// Why « Use Expand » stays out: a mask beside the pads, no image 1, or the pads the engine
    /// refuses — said here, as the footer says it at « Generate ».
    private var blocker: String? {
        if app.attachedMask != nil {
            return String(localized: "A mask replaces a region and an expand grows the canvas: remove one of them.",
                          comment: "A mask and an expand cannot edit one image two ways")
        }
        guard let image = app.editInputs.first?.shown else {
            return String(localized: "Attach an image first: the canvas grows around it.",
                          comment: "An expand without image 1: there is nothing to grow")
        }
        if pads.left == 0, pads.right == 0, pads.top == 0, pads.bottom == 0 {
            return String(localized: "All four pads are 0: give at least one side a percent to grow by.",
                          comment: "An expand with nothing to grow: the render would redraw the image and change nothing")
        }
        do { _ = try Expand.plan(pads: pads, width: image.width, height: image.height) }
        catch { return Problem(EngineError(error)).text }
        return nil
    }

    @ViewBuilder private var preview: some View {
        if let image = app.editInputs.first?.shown, blocker == nil,
           let plan = try? Expand.plan(pads: pads, width: image.width, height: image.height) {
            Text(verbatim: "\(image.width) × \(image.height) → \(plan.crop.width) × \(plan.crop.height) → \(plan.width) × \(plan.height)")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .help("The image, the canvas it sits in, then the size the render will have")
        }
        if let blocker {
            Text(blocker).font(.caption).foregroundStyle(Color(nsColor: .systemOrange))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **« Use Expand »**: the pads go through the same attachment every expand takes — the plan
    /// computed, the form's steps set to the workflow's nine — and the sheet closes. A refusal leaves
    /// it open, its sentence shown.
    private func commit() {
        Task {
            await app.attachExpand(pads: pads)
            if app.attachedExpand != nil { dismiss() }
        }
    }
}

private extension LabModel {
    /// **When the mask's tile is drawn**: where the model edits by reference and an image is there to edit — or
    /// while a mask is still attached and must be removable (the model changed under it, an image was removed).
    var showsMaskTile: Bool {
        // A mask still attached must stay removable, even when the image it was sized to is gone.
        if rack.attachedMask != nil { return true }
        return !pictures.isEmpty && rack.canPatchMask
    }

    /// **When the expand's tile is drawn**: where the 「扩图」 workflow is and an image is there to grow —
    /// or while the pads are still attached and must be removable.
    var showsExpandTile: Bool {
        // The pads still attached must stay removable, whatever the images do meanwhile.
        if rack.attachedExpand != nil { return true }
        return !pictures.isEmpty && rack.canExpand
    }
}

/// « Describe »: what the image shows, written into the text.
private struct DescribeButton: View {
    let model: LabModel
    let action: () -> Void

    var body: some View {
        Button("Describe", action: action)
            .disabled(!model.canDescribe)
            .help(model.writerPause.map { Text(verbatim: $0.sentence) } ?? Text("Writes what the image shows into the text, at the caret."))
            .controlSize(.small)
    }
}

// MARK: - A plain image

private struct PictureTile: View {
    let model: LabModel
    let picture: InputImage
    let number: Int?
    @State private var hover = false

    private var rack: AppState { model.rack }
    private var goes: Bool { rack.isEffective(picture) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: picture.shown.vignette).resizable().scaledToFill()
                .frame(width: LabTile.picture.width, height: LabTile.picture.height).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay { LabTile.edge(goes: goes, main: picture.role == .edited || picture.role == .start) }
                .overlay(alignment: .topTrailing) {
                    if hover {
                        Button { model.remove(picture) } label: {
                            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain).padding(2)
                        .help("Remove")
                        .accessibilityLabel(Text("Remove"))
                    }
                }
                .overlay { if model.describing == picture.id { ProgressView().controlSize(.small) } }
                .accessibilityLabel(Text("An image of the lab"))
            VStack(alignment: .leading, spacing: 3) {
                if model.capacity > 0 { roleMenu } else if goes { roleLabel }
                if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                if model.startIsImg2Img {
                    if picture.role == .start { StartStrength(model: model) }
                    else {
                        Button("Start From This Image") { model.startFrom(picture) }
                            .controlSize(.small)
                            .help("The render starts from this image and keeps its composition")
                    }
                }
                DescribeButton(model: model) { model.describe(picture) }
            }
            .frame(width: LabTile.meta, alignment: .leading)
        }
        .onHover { hover = $0 }
        .contextMenu { menu }
    }

    /// Why it does not go, when it has a role: the model lacks it. Or, without a role under Qwen, that the render is full.
    private var caption: String? {
        if picture.role != .neutral, !goes, let name = rack.card?.name {
            return String(localized: "“\(picture.role.label)”: no effect with \(name)")
        }
        let limit = min(model.capacity, NamedSubjects.maxImages)
        if picture.role == .neutral, limit > 0, rack.references.count >= limit {
            return String(localized: "\(String(rack.references.count)) / \(String(limit)): full")
        }
        return nil
    }

    private var roleLabel: some View {
        Text(verbatim: (number.map { "\($0) · " } ?? "") + picture.role.label)
            .font(.caption.weight(.semibold)).foregroundStyle(goes ? WireKind.image.color : .secondary).lineLimit(1)
            .help(picture.role.explanation(img2img: model.startIsImg2Img))
    }

    private var roleMenu: some View {
        Menu {
            ForEach(model.offeredRoles, id: \.self) { role in
                Button { model.setRole(role, of: picture) } label: {
                    if role == picture.role { Label(role.label, systemImage: "checkmark") } else { Text(role.label) }
                }
            }
            Divider()
            Button("Name…") { model.name(picture) }
        } label: {
            roleLabel
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
        .help(picture.role.explanation(img2img: model.startIsImg2Img))
    }

    @ViewBuilder private var menu: some View {
        Button("Crop…") { rack.beginCrop(picture.shown) }
            .disabled(rack.cropRefusal(width: picture.shown.width, height: picture.shown.height) != nil)
        Button("Replace…") { rack.replaceReference(picture.shown.id) }
        Button("Name…") { model.name(picture) }
        if picture.role == .start, model.startIsImg2Img {
            Button("Reset to \(StartWords.percent(rack.defaultStartStrength))") { rack.setStartStrength(rack.defaultStartStrength) }
        }
        if let bytes = picture.bytes, AppState.isRecipe(bytes) {
            Button("Reuse These Settings") { _ = rack.restoreSettings(fromPNG: bytes, file: picture.shown.name) }
        }
        // Image 1's mask, beside the image it edits (`AppState+Mask.swift`), and its expand beside both:
        // two entries of one image, never together (`AppState+Expand.swift`).
        if rack.canPatchMask, rack.editInputs.first?.id == picture.id {
            Button("Paint Mask…") { rack.beginMaskPainting() }.disabled(!rack.canAttachMask)
            if rack.attachedMask == nil {
                Button("Attach Mask…") { rack.chooseMask() }.disabled(!rack.canAttachMask)
            } else {
                Button("Remove Mask") { rack.removeMask() }
            }
            Divider()
            Button("Expand…") { rack.beginExpand() }
                .disabled(!rack.canAttachExpand)
                .help(rack.attachedMask == nil
                      ? "Grow the canvas outward: four percents, no mask"
                      : "A mask and an expand edit two ways: remove the mask first")
            if rack.attachedExpand != nil {
                Button("Remove Expand", role: .destructive) { rack.removeExpand() }
            }
        }
        Divider()
        Button("Remove", role: .destructive) { model.remove(picture) }
    }
}

/// **The starting image's strength, on its tile** — its one place: the rack reads it in its port, it does not set it.
/// Orange, and said, when it is so high that the image is ignored.
private struct StartStrength: View {
    let model: LabModel

    var body: some View {
        let rack = model.rack
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("Strength").foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(verbatim: StartWords.percent(rack.startStrength)).monospacedDigit()
                    .onTapGesture(count: 2) { rack.setStartStrength(rack.defaultStartStrength) }
            }
            .font(.caption)
            Slider(value: Binding(get: { rack.startStrength }, set: { rack.setStartStrength($0) }), in: 0...1)
                .controlSize(.mini).tint(Palette.control)
                .accessibilityLabel(Text("Strength"))
                .accessibilityValue(Text(verbatim: StartWords.percent(rack.startStrength)))
            if rack.startIgnored {
                Text("Image ignored: lower the strength").font(.caption2).foregroundStyle(Color(nsColor: .systemOrange))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .help(rack.startCaption.text)
            }
        }
        .help(StartWords.explanation(rack.startRedraws))
        .bracketable(rack, .startStrength, gutter: 18)
    }
}

extension LabInputs.Role {
    var label: String {
        switch self {
        case .edited: String(localized: "Image to Edit", comment: "The role of the image the model edits")
        case .reference: String(localized: "Reference", comment: "The role of an image the model sees as context")
        case .start: String(localized: "Starting image", comment: "The role of the image an img2img starts from")
        case .neutral: String(localized: "No Role", comment: "An image of the lab that does not go to the render")
        }
    }

    /// What the role does, for a model that starts from an image (img2img) or not.
    func explanation(img2img: Bool) -> String {
        if img2img, self == .start { return String(localized: "The image the render starts from: it keeps its composition; the size follows it.") }
        return explanation
    }

    var explanation: String {
        switch self {
        case .edited: String(localized: "The image the model edits: image 1, which gives the format.")
        case .reference: String(localized: "The model sees it as context, after the image to edit.")
        case .start: String(localized: "The image the render starts from: it keeps its composition; the size follows it.")
        case .neutral: String(localized: "Stays in the lab: it is not sent to the render.")
        }
    }
}

// MARK: - A subject

private struct SubjectTile: View {
    let model: LabModel
    let subject: NamedSubjects.Subject
    let numbers: [Int]

    /// Cited by the text, under a model that reads no image: it does not go.
    private var inert: Bool { model.capacity == 0 && NamedSubjects.mentions(in: model.text).contains { NamedSubjects.key($0.name) == subject.id } }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                if let thumbnail = model.subjects.thumbnail(subject) {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    subject.kind.color.opacity(0.15).overlay(Image(systemName: subject.kind.symbol).foregroundStyle(subject.kind.color))
                }
            }
            .frame(width: LabTile.picture.width, height: LabTile.picture.height).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { LabTile.edge(goes: !numbers.isEmpty, main: false) }
            .opacity(inert ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Button { model.cite(subject) } label: {
                    Text(verbatim: (numbers.isEmpty ? "" : numbers.map(String.init).joined(separator: "+") + " · ") + "@" + subject.name)
                        .font(.caption.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(numbers.isEmpty ? Color.secondary : WireKind.image.color)
                        .strikethrough(inert)
                }
                .buttonStyle(.plain)
                .help("Cite in the Text")
                .draggable("@\(subject.name) ")
                Text(inert ? String(localized: "\(model.rack.card?.name ?? "") does not read subjects") : subject.kind.label)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                DescribeButton(model: model) { model.describe(subject) }
            }
            .frame(width: LabTile.meta, alignment: .leading)
        }
        .contextMenu {
            Button("Cite in the Text") { model.cite(subject) }
            Button("Edit…") { model.edit(subject) }
            Divider()
            Button("Delete…", role: .destructive) { model.confirmDeletion(subject) }
        }
    }
}
