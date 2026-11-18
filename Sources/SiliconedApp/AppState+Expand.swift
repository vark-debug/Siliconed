// **`AppState`: the expand attached in the Prompt Lab** — the entry to the 「扩图」 path (`Expand`):
// four pad percents over image 1, no brush and no mask.
//
//     Prompt Lab ── « Expand… », the pads form (`ExpandPadsSheet`) ──▶ attachedExpand (pads, plan)
//                                                                │
//     render() ── image 1 + those pads ──▶ ExpandInput ──▶ the job ──▶ grey canvas, 9 steps, paste-back
//
// - **One attachment of its own kind**: like the mask, it is taken as `render` queues its jobs and
//   cleared there — the next click is an ordinary render unless the pads are committed again. A redo
//   reads its entry's own pads (`entry.settings.expand`), never the lab's.
// - **The mask and the expand are two edits of one image**: the mask says which region changes, the
//   expand keeps the whole image and grows the canvas. Both attachments refuse each other at attach
//   time, and `expandBlocker` / `maskBlocker` refuse them again before the click; so does an ON
//   expand preset card beside a mask — the rack's card is the CLI's `lora` refusal, the attachment's
//   the engine's own (`Request.expand` refuses `patch`).
// - **The pads are percents of the image's own sides**, 0–200 each, all four 0 refused: nothing to
//   expand. The plan is computed at attach time (`Expand.plan`), so the form shows the size the
//   render will have and the memory preflight reads it — as the mask's crop does.
// - **Incognito**: the attachment lives in memory; nothing is written.

import AppKit
import Siliconed

/// **The expand attached in the lab**, with what the engine will make of it: the canvas's plan.
struct AttachedExpand {
    /// The percents each side grows by (`Expand.Pads`).
    var pads: Expand.Pads
    /// The canvas and the size the render will have (`Expand.plan`): what the memory preflight and
    /// the job's format read.
    var plan: Expand.Plan
}

extension AppState {
    // MARK: What the form offers

    /// Whether the chosen model has the 「扩图」 workflow: the same engine as the mask's — an image
    /// encoder, and a denoiser whose latent an additive start can seed (Qwen-Image-2.1). Never in a
    /// mirror: its jobs carry no expand.
    var canExpand: Bool { canPatchMask }

    /// Whether an image can take an expand: image 1 alone, no mask beside it.
    var canAttachExpand: Bool { canExpand && editInputs.count == 1 && attachedMask == nil }

    /// **The size the render will have with these pads**: the canvas's plan — `nil` without a usable
    /// attachment. The form's own format is untouched (`restoreSettings` keeps it too).
    var attachedExpandPlan: RecommendedFormat? {
        attachedExpand.map { RecommendedFormat($0.plan.width, $0.plan.height) }
    }

    /// The plan's size when the expand is one the render can take (image 1 alone): what
    /// `outputFormat`, `sentImages` and the footer read.
    var attachedExpandFormat: RecommendedFormat? {
        guard attachedExpand != nil, editInputs.count == 1 else { return nil }
        return attachedExpandPlan
    }

    /// **Why the form refuses the expand as it stands**, or `nil`. Read by `formBlocker`, so
    /// « Generate » greys out with the sentence instead of letting the engine refuse the request.
    var expandBlocker: String? {
        guard let attached = attachedExpand else { return nil }
        if mirror != nil {
            return String(localized: "An expand stays on this Mac: stop following another Mac first.",
                          comment: "An expand cannot cross a mirror: its canvas is this Mac's")
        }
        // **The mask and the expand are two edits of one image**: the mask says which region changes,
        // the expand keeps the whole image and grows the canvas — the engine refuses them together.
        if attachedMask != nil {
            return String(localized: "A mask replaces a region and an expand grows the canvas: remove one of them.",
                          comment: "A mask and an expand cannot edit one image two ways")
        }
        // **The remove and redraw presets are the mask workflow's branches**: switched on beside an
        // expand, neither is the canvas's — the CLI's `mode` refusal, said before the click. The
        // expand preset itself is the canvas's: it is wired into the stack by the render.
        if rackPresetMode != nil {
            return String(localized: "The remove and redraw presets belong to the mask: turn them off to expand.",
                          comment: "A mask branch's preset and an expand are two branches of one workflow")
        }
        guard canExpand else {
            return String(localized: "%@ has no expand workflow: an expand needs a model that edits by reference (Qwen-Image-2.1).",
                          comment: "The model refuses an expand: no additive start, or no image encoder")
        }
        guard editInputs.first?.shown != nil else {
            return String(localized: "Attach an image first: the canvas grows around it.",
                          comment: "An expand without image 1: there is nothing to grow")
        }
        // Image 1 replaced under the pads: the plan the form showed was the old image's — refused,
        // said, until the pads are committed again (`attachExpand`).
        if let image = editInputs.first?.shown,
           let fresh = try? Expand.plan(pads: attached.pads, width: image.width, height: image.height),
           fresh != attached.plan {
            return String(localized: "Image 1 changed: remove the expand and commit the pads again.",
                          comment: "The image the canvas was grown from was replaced under the attachment")
        }
        if editInputs.count > 1 {
            return String(localized: "An expand edits image 1 alone: remove the other images.",
                          comment: "The expand's canvas is the edit's only image")
        }
        if case .success(let carry) = carried,
           carry.images.contains(where: { if case .subject = $0 { true } else { false } }) {
            return String(localized: "An expand edits image 1 alone: the text cites a named subject — remove the @name or the expand.",
                          comment: "An expand is the edit's only image, subjects' pictures included")
        }
        return nil
    }

    // MARK: Attaching

    /// **« Expand… »**: the pads form (`ExpandPadsSheet`), the workflow's own 30/30/0/0 in its fields.
    func beginExpand() {
        guard canExpand, !expandingPads else { return }
        expandingPads = true
    }

    /// **The pads committed by the form**: computed against image 1 — the plan off the main thread, as
    /// the render's geometry. All four pads 0, pads out of range and an unusable size are refused with
    /// the engine's own sentence.
    func attachExpand(pads: Expand.Pads) async {
        guard let image = editInputs.first?.shown else {
            problem = Problem(String(localized: "Attach an image first: the canvas grows around it.",
                                     comment: "An expand without image 1: there is nothing to grow"))
            return
        }
        await attachExpand(pads, to: image)
    }

    /// **The pads are attached to `image`** — the canvas's plan computed off the main thread, a mask
    /// beside it refused: the two entries edit one image two ways.
    func attachExpand(_ pads: Expand.Pads, to image: ReferenceImage) async {
        if attachedMask != nil {
            problem = Problem(String(localized: "A mask replaces a region and an expand grows the canvas: remove one of them.",
                                     comment: "A mask and an expand cannot edit one image two ways"))
            return
        }
        // The canvas and the size the render will have, off the main thread, as the render plans them.
        let measured: Result<Expand.Plan, EngineError> = await Task.detached(priority: .userInitiated) {
            () -> Result<Expand.Plan, EngineError> in
            do { return .success(try Expand.plan(pads: pads, width: image.width, height: image.height)) }
            catch { return .failure(EngineError(error)) }
        }.value
        switch measured {
        case .success(let plan):
            attachedExpand = AttachedExpand(pads: pads, plan: plan)
        case .failure(let e):
            problem = Problem(e)
            return
        }
        // **The expand's nine steps, the mask's own table** (`Patch.defaultSteps`, the graph's
        // `ManualSigmas`): the form says so, and the job's settings, its plan and every label read
        // the same number — no second arithmetic.
        steps = Patch.defaultSteps
        problem = nil
    }

    /// **« Remove Expand »**: the next click is an ordinary render again, at the form's format.
    func removeExpand() {
        attachedExpand = nil
        // Nine was the expand's: back to the model's default when the form still holds it — a count
        // the user chose while attached stays theirs.
        if steps == Patch.defaultSteps { steps = card?.defaultSteps ?? 8 }
    }

    // MARK: One render's

    /// **The attachment the click takes with `image`** — `nil` without one. The attachment stays until
    /// `takeAttachedExpand` is called: what `render` does as it queues its jobs.
    func attachedExpandInput(for image: ReferenceImage) -> ExpandInput? {
        guard let attachedExpand else { return nil }
        return (image, ExpandSettings(pads: attachedExpand.pads, maximumSample: Expand.defaultMaximumSample))
    }

    /// **The stack an expand job carries**: the rack's slots, with the expand preset wired when it is
    /// not there — the workflow's own LoRA at its 0.7, as `--mode expand` wires it. An ON remove or
    /// redraw card is refused first (`expandBlocker`): the branches never stack.
    func expandLoras() -> [LoRASlot] {
        guard let preset = PatchLoRA.card(for: .expand, in: compatibleLoras),
              !activeLoRAs.contains(where: { $0.path == preset.path }) else { return activeLoRAs }
        return activeLoRAs + [LoRASlot(path: preset.path, strength: PatchLoRA.expand.strength)]
    }

    /// **Takes the attachment for one render, and clears it**: the pads belong to the job they are
    /// queued with, never to the form — the next click is ordinary unless committed again.
    func takeAttachedExpand() -> AttachedExpand? {
        defer { attachedExpand = nil }
        return attachedExpand
    }

    /// **What « Redo » hands the render**: the entry's own canvas — the image it grew from, with the
    /// pads and ceiling it was drawn at — or `nil` for an ordinary image, whatever the lab holds.
    func redoExpand(_ entry: Entry) -> ExpandInput? {
        guard let expand = entry.settings.expand, let image = entry.start else { return nil }
        return (image, expand)
    }
}
