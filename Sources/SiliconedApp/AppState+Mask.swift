// **`AppState`: the mask attached in the Prompt Lab** — the entry to the 「移除」 path (`Patch`):
// painted over image 1 (`MaskEditor`) or imported as a PNG, attached to the next click only.
//
//     Prompt Lab ── painted strokes / « Attach Mask… », the size of image 1 ──▶ attachedMask (mask, plan)
//                                                                        │
//     render() ── image 1 + that mask ──▶ PatchInput ──▶ the job ──▶ crop, tint, noise_mask, paste
//
// - **Both entries make the same mask**: the painted strokes become a white-on-black bitmap of image
//   1's pixels, then `attachMask` reads it through `ImageMask` exactly as it reads a PNG — one size
//   check, one `> 0.1`, one hole filling, one `Patch.plan`. There is no second mask geometry.
// - **It belongs to one render**: `render` takes it before the jobs are made and clears it, so the
//   next click is an ordinary render unless the user attaches it again — the leak the 0.20 fix
//   (`a08e33f`) closed, now with the entries that need it.
// - **Its size is the image's**, never scaled here: a mask of another size is refused with both
//   sizes said. The crop, its margins and the plan are the engine's (`Patch.plan`), the defaults
//   the command line's (`Patch.Settings()`: 1.3/1.4/1.4/1.4, 2560, `noise_mask` on).
// - **The render's size is the crop's plan**, not image 1's: the memory preflight (`outputFormat`)
//   and the job read the plan's dimensions.
// - **A redo keeps its image's own mask** (`entry.mask`, `entry.settings.patch`); the lab's
//   attachment never enters a redo — the entry decides what it renders.
// - **Incognito**: the mask lives in memory, read from the file or painted there; nothing is written.

import AppKit
import Siliconed
import UniformTypeIdentifiers

/// **The mask attached in the lab**, with what the engine will make of it: the crop's plan.
struct AttachedMask {
    /// The file, its thumbnail and its size (upright, as image 1's).
    var mask: ReferenceImage
    /// The crop the render takes, and the size it renders at (`Patch.plan`): what the memory
    /// preflight and the job's format read.
    var plan: Patch.Plan
}

extension AppState {
    // MARK: What the form offers

    /// Whether the chosen model has the 「移除」 workflow: an image encoder, and a denoiser whose
    /// latent an additive start can seed (Qwen-Image-2.1). Never in a mirror: its jobs carry no patch.
    var canPatchMask: Bool {
        guard mirror == nil, imageCapacity > 0, let chain else { return false }
        return chain.encoding != nil && chain.denoising.acceptsSeededStart
    }

    /// Whether an image can take a mask: image 1 alone, the render being a patch of it.
    var canAttachMask: Bool { canPatchMask && editInputs.count == 1 }

    /// **The size the render will have with this mask**: the crop's plan — `nil` without a usable
    /// mask. The form's own format is untouched (`restoreSettings` keeps it too).
    var attachedMaskPlan: RecommendedFormat? {
        attachedMask.map { RecommendedFormat($0.plan.width, $0.plan.height) }
    }

    /// The plan's size when the mask is one the render can take (image 1 alone): what `outputFormat`,
    /// `sentImages` and the footer read.
    var attachedMaskFormat: RecommendedFormat? {
        guard attachedMask != nil, editInputs.count == 1 else { return nil }
        return attachedMaskPlan
    }

    /// **Why the form refuses the mask as it stands**, or `nil`. Read by `formBlocker`, so « Generate »
    /// greys out with the sentence instead of letting the engine refuse the request.
    var maskBlocker: String? {
        guard let attached = attachedMask else { return nil }
        if mirror != nil {
            return String(localized: "A mask stays on this Mac: stop following another Mac first.",
                           comment: "A patch cannot cross a mirror: its crop and mask are this Mac's")
        }
        // **The two presets are two branches of one workflow**: switched on together, neither is the
        // mask's — refused before the click. A card switched off is not in the stack (`patchMode`
        // reads the same `activeLoRAs`). The stack is read before the model's own refusal: it is the
        // rack's, whatever shape the mask workflow has here.
        if let remove = PatchLoRA.card(for: .remove, in: compatibleLoras)?.path,
           let redraw = PatchLoRA.card(for: .redraw, in: compatibleLoras)?.path,
           activeLoRAs.contains(where: { $0.path == remove }),
           activeLoRAs.contains(where: { $0.path == redraw }) {
            return String(localized: "The remove and redraw presets are exclusive: keep one in the rack.",
                           comment: "A patch takes one branch of the workflow, not both")
        }
        guard canPatchMask else {
            return String(localized: "\(modelName(identifier)) has no mask workflow: a mask needs a model that edits by reference (Qwen-Image-2.1).",
                           comment: "The model refuses a patch: no additive start, or no image encoder")
        }
        guard let image = editInputs.first?.shown else {
            return String(localized: "Attach an image first: the mask must have the image’s size.",
                           comment: "A mask without image 1: there is nothing to patch")
        }
        // Image 1 replaced under the mask: the engine would refuse it, said before the click.
        if image.width != attached.mask.width || image.height != attached.mask.height {
            return String(localized: "The mask is \(String(attached.mask.width)) × \(String(attached.mask.height)), the image \(String(image.width)) × \(String(image.height)): a mask must be the image’s size — it is never scaled.",
                           comment: "The mask and image 1 must have the same pixel size")
        }
        if editInputs.count > 1 {
            return String(localized: "A mask edits image 1 alone: remove the other images.",
                           comment: "The patch's crop is the edit's only image")
        }
        if case .success(let carry) = carried,
           carry.images.contains(where: { if case .subject = $0 { true } else { false } }) {
            return String(localized: "A mask edits image 1 alone: the text cites a named subject — remove the @name or the mask.",
                           comment: "A patch is the edit's only image, subjects' pictures included")
        }
        return nil
    }

    // MARK: Attaching

    /// **« Attach Mask… »**: a PNG, the size of image 1.
    func chooseMask() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "A PNG mask the size of image 1: white is what changes, black what stays.",
                                comment: "The mask is white-on-black, never scaled: it must be image 1's size")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await attachMask(from: url) }
    }

    /// The file as a mask — read as the render reads a file (`AppState.read`).
    func attachMask(from url: URL) async {
        guard editInputs.count == 1, let image = editInputs.first else {
            problem = Problem(String(localized: "A mask edits image 1 alone: remove the other images.",
                                     comment: "The patch's crop is the edit's only image"))
            return
        }
        guard let mask = read(url) else { return }
        await attachMask(mask, to: image.shown)
    }

    /// **The mask is attached to `image`** — its size checked (never scaled), its pixels read off the
    /// main thread, the crop's plan computed there and then.
    func attachMask(_ mask: ReferenceImage, to image: ReferenceImage) async {
        guard mask.width == image.width, mask.height == image.height else {
            problem = Problem(String(localized: "The mask is \(String(mask.width)) × \(String(mask.height)), the image \(String(image.width)) × \(String(image.height)): a mask must be the image’s size — it is never scaled.",
                                       comment: "The mask and image 1 must have the same pixel size"),
                              suggestion: String(localized: "Make the mask the size of image 1, then attach it again."))
            return
        }
        // The pixels, the filled mask and the crop: off the main thread, as the render decodes them.
        let measured: (plan: Patch.Plan?, pixels: Int, error: EngineError?)
        do {
            measured = try await Task.detached(priority: .userInitiated) { () throws -> (Patch.Plan?, Int, EngineError?) in
                let m = ImageMask(image: try mask.imageRGB())
                guard m.effectivePixels >= Patch.minimumPixels else { return (nil, m.effectivePixels, nil) }
                do { return (try Patch.plan(mask: m, width: mask.width, height: mask.height), m.effectivePixels, nil) }
                catch { return (nil, m.effectivePixels, EngineError(error)) }
            }.value
        } catch {
            problem = Problem(EngineError(error))
            return
        }
        guard measured.pixels >= Patch.minimumPixels else {
            problem = Problem(String(localized: "The mask has fewer than \(String(Patch.minimumPixels)) pixels to replace: white is what changes, black what stays.",
                                       comment: "A patch with nothing to replace: the workflow's 10 px guard"),
                              suggestion: String(localized: "Paint the region to change in white on black, then attach it again."))
            return
        }
        guard let plan = measured.plan else {
            problem = Problem(measured.error ?? EngineError.invalidPatch(reason: "the mask leaves no crop to render"))
            return
        }
        attachedMask = AttachedMask(mask: mask, plan: plan)
        // **The patch's own default steps, 9** (`Patch.defaultSteps`): the form says so, and the job's
        // settings, its plan and every label read the same number — no second arithmetic.
        steps = Patch.defaultSteps
        problem = nil
    }

    /// **« Remove Mask »**: the next click is an ordinary render again, at the form's format.
    func removeMask() {
        attachedMask = nil
        // Nine was the mask's: back to the model's default when the form still holds it — a count the
        // user chose while attached stays theirs.
        if steps == Patch.defaultSteps { steps = card?.defaultSteps ?? 8 }
    }

    // MARK: Painting

    /// **« Paint Mask… »** (`MaskEditor`): image 1 decoded at its own size, under a brush and an
    /// eraser. The strokes stay in the image's frame, so the mask is image 1's size — the PNG's.
    func beginMaskPainting() {
        guard paintingMask == nil, canAttachMask, let image = editInputs.first?.shown else { return }
        let id = image.id, width = image.width, height = image.height
        MainWindow.shared.releaseTextFocus()
        Task {
            let decoded = await Task.detached(priority: .userInitiated) {
                Decoded(image.displayed(width: width, height: height))
            }.value
            guard let cg = decoded.image, paintingMask == nil, editInputs.first?.shown.id == id else { return }
            MainWindow.shared.releaseTextFocus()
            showsExploration = false
            followsRender = false
            comparesOriginal = false
            zoom = 1
            paintingMask = MaskSession(image: cg, imageID: id)
        }
    }

    /// **Esc**: leave without a mask — the strokes are not kept.
    func cancelMaskPainting() { paintingMask = nil }

    func setMaskTool(_ tool: MaskSession.Tool) { paintingMask?.tool = tool }

    func setMaskBrush(_ brush: CGFloat) {
        paintingMask?.brush = min(max(brush, MaskSession.brushRange.lowerBound), MaskSession.brushRange.upperBound)
    }

    func addMaskStroke(_ stroke: MaskSession.Stroke) { paintingMask?.strokes.append(stroke) }

    func undoMaskStroke() {
        guard paintingMask?.strokes.isEmpty == false else { return }
        paintingMask?.strokes.removeLast()
    }

    func clearMaskStrokes() { paintingMask?.strokes.removeAll() }

    /// **« Use Mask » / Return**: the strokes become a white-on-black bitmap of image 1's size, then
    /// the attachment every mask goes through — the size check, `ImageMask`, hole filling, the plan.
    func commitMaskPainting() {
        guard let session = paintingMask else { return }
        guard !session.isEmpty else {
            flash(String(localized: "Paint the area to change first",
                         comment: "An empty painted mask: there is nothing to replace"))
            return
        }
        guard let image = editInputs.first?.shown, image.id == session.imageID else {
            paintingMask = nil
            flash(String(localized: "Image 1 changed: the painted mask has no image to fit",
                         comment: "Image 1 was replaced while its mask was being painted"))
            return
        }
        paintingMask = nil
        Task {
            let painted = await Task.detached(priority: .userInitiated) { session.maskImage() }.value
            guard let cg = painted else {
                flash(String(localized: "This mask could not be painted"))
                return
            }
            let vignette = FinishedImage.reduce(cg, side: 240) ?? cg
            let mask = ReferenceImage(source: .image(cg),
                                      vignette: NSImage(cgImage: vignette, size: .zero),
                                      name: String(localized: "Painted mask",
                                                   comment: "The name a mask painted in the Prompt Lab is attached under"),
                                      width: cg.width, height: cg.height)
            await attachMask(mask, to: image)
        }
    }

    // MARK: One render's

    /// **The mask the click takes with `image`** — `nil` without an attachment. The attachment stays
    /// until `takeAttachedMask` is called: what `render` does as it queues its jobs.
    func attachedMaskInput(for image: ReferenceImage) -> PatchInput? {
        guard let attachedMask else { return nil }
        return (image, attachedMask.mask, Patch.Settings(mode: patchMode))
    }

    /// **The branch the rack's LoRA stack picks** (`Patch.Settings.mode`): the redraw preset's card
    /// switched **on** → redraw; anything else — the remove card included, and a card switched off —
    /// remove, the default. The Add menu's two presets and the command line's `--mode` / `--lora`
    /// write this one notion, never two paths.
    var patchMode: Patch.Mode {
        guard let redraw = PatchLoRA.card(for: .redraw, in: compatibleLoras)?.path,
              activeLoRAs.contains(where: { $0.path == redraw }) else {
            return .remove
        }
        return .redraw
    }

    /// **Takes the attachment for one render, and clears it**: the mask belongs to the job it is queued
    /// with (`PatchInput`), never to the form — the next click is ordinary unless attached again.
    func takeAttachedMask() -> AttachedMask? {
        defer { attachedMask = nil }
        return attachedMask
    }
}
