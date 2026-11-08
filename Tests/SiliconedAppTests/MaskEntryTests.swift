// **The Prompt Lab's mask entry** (`AppState+Mask.swift`): one PNG beside image 1, one click, the 「移除」 path.
//
// The tests read the form and the jobs a click makes — no model is installed, nothing is decoded but the
// masks these tests draw. What they keep:
//
// - a mask attached makes the job carry `patch` (with noise_mask on, the command line's defaults) and the
//   render's format become the crop's plan, not image 1's editing size;
// - the click consumes it: the next click is ordinary, at the form's format;
// - a mask of another size is refused with both sizes said, never scaled;
// - a blank mask is refused as `invalid_patch` with a readable sentence (not the code);
// - a redo keeps its own entry's mask and image, and never takes the lab's.

import AppKit
import Siliconed
import XCTest
@testable import SiliconedApp

@MainActor
final class MaskEntryTests: XCTestCase {
    private func form() -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MaskEntryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppState(library: Library(root: root))
    }

    /// A gray/alpha picture: transparent but for `white` (in pixels), the size given. White is what a
    /// mask replaces; nothing white leaves nothing to replace.
    private func picture(_ side: Int, white: CGRect?, name: String) -> ReferenceImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 0))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        if let white {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(white)
        }
        let cg = context.makeImage()!
        return ReferenceImage(source: .image(cg),
                              vignette: NSImage(cgImage: cg, size: NSSize(width: side, height: side)),
                              name: name, width: side, height: side)
    }

    private func source(_ side: Int, name: String = "source.png") -> ReferenceImage {
        ReferenceImage(source: .bytes(Data()), vignette: NSImage(size: NSSize(width: side, height: side)),
                       name: name, width: side, height: side)
    }

    private func onePixel() -> CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// **Attached → the next render is a patch at the plan's size; then it is gone.**
    func testTheAttachedMaskDrivesOneRenderThenGoes() async {
        let app = form()
        let image = picture(256, white: nil, name: "image.png")
        let mask = picture(256, white: CGRect(x: 100, y: 100, width: 40, height: 40), name: "mask.png")

        await app.attachMask(mask, to: image)
        XCTAssertNotNil(app.attachedMask)
        XCTAssertNil(app.problem, "a mask of image 1's size, with pixels to replace, is accepted")
        XCTAssertEqual(app.steps, Patch.defaultSteps, "the patch's own default: the workflow's 9")
        guard let plan = app.attachedMask?.plan else { return XCTFail("no plan") }
        XCTAssertEqual(app.attachedMaskPlan, RecommendedFormat(plan.width, plan.height),
                       "the render's size is the crop's plan")

        // The job this click makes.
        let input = app.attachedMaskInput(for: image)
        XCTAssertNotNil(input, "the attachment is image 1's mask")
        let jobs = app.renderJobs(seed: 7, format: app.attachedMaskPlan!, patch: input,
                                  prompts: ["a cat"], edit: [])
        XCTAssertEqual(jobs.count, 1)
        XCTAssertNotNil(jobs[0].patch, "with a mask the job is the 「移除」 path")
        XCTAssertEqual(jobs[0].settings.steps, Patch.defaultSteps,
                       "the job walks the nine the form shows — display and plan, one number")
        XCTAssertEqual(jobs[0].settings.patch, Patch.Settings(),
                       "expand 1.3/1.4/1.4/1.4, max side 2560, noise_mask on: the command line's defaults")
        XCTAssertEqual(jobs[0].settings.format, RecommendedFormat(plan.width, plan.height),
                       "the job renders at the plan's size, not image 1's")
        XCTAssertEqual(jobs[0].references.count, 0, "a patch reads image 1 alone")

        // The click takes it — once (`render`), and the form is ordinary again.
        XCTAssertNotNil(app.takeAttachedMask())
        XCTAssertNil(app.attachedMask)
        XCTAssertNil(app.attachedMaskInput(for: image))
        XCTAssertNil(app.attachedMaskPlan)

        let chosen = RecommendedFormat(512, 512)
        app.format = chosen
        let plain = app.renderJobs(seed: 8, format: chosen, patch: app.attachedMaskInput(for: image),
                                   prompts: ["a cat"], edit: [])
        XCTAssertNil(plain[0].patch, "the next click carries no mask, hence no green tint")
        XCTAssertNil(plain[0].settings.patch)
        XCTAssertEqual(plain[0].settings.format, chosen, "and it is the form's format")
    }

    /// **The mask's nine are the mask's**: attaching defaults the form to the workflow's 9
    /// (`Patch.defaultSteps`), removing it returns the model's 8, a count chosen while attached
    /// stays the user's, and an ordinary render always keeps the form's count — the job's settings
    /// are the form's, so the displayed steps and the planned evaluations cannot diverge.
    func testTheMaskStepsBelongToTheMask() async {
        let app = form()
        let image = picture(256, white: nil, name: "image.png")
        let mask = picture(256, white: CGRect(x: 100, y: 100, width: 50, height: 50), name: "mask.png")
        app.steps = 7
        await app.attachMask(mask, to: image)
        XCTAssertEqual(app.steps, 9, "attaching shows the patch's 9, whatever the form held")
        app.removeMask()
        XCTAssertEqual(app.steps, 8, "removing returns the model's default")
        await app.attachMask(mask, to: image)
        app.steps = 8
        app.removeMask()
        XCTAssertEqual(app.steps, 8, "a count chosen while attached is the user's, kept")
        app.steps = 12
        let plain = app.renderJobs(seed: 3, format: RecommendedFormat(512, 512), patch: nil,
                                   prompts: ["x"], edit: [])
        XCTAssertEqual(plain[0].settings.steps, 12, "no mask: the form's own count, unchanged")
    }

    /// **A mask of another size is refused, both sizes said** — never scaled.
    func testAMaskOfAnotherSizeIsRefusedWithBothSizes() async {
        let app = form()
        let image = picture(256, white: nil, name: "image.png")
        let mask = picture(128, white: CGRect(x: 10, y: 10, width: 20, height: 20), name: "mask.png")

        await app.attachMask(mask, to: image)
        XCTAssertNil(app.attachedMask, "a 128 px mask is not image 1's 256 px")
        guard let problem = app.problem else { return XCTFail("no problem shown") }
        XCTAssertTrue(problem.title.contains("128"))
        XCTAssertTrue(problem.title.contains("256"))
        XCTAssertNil(problem.code, "the app's own refusal, not an engine code alone")
    }

    /// **A blank mask is `invalid_patch` with a readable sentence**: the engine's `minimumPixels`, said.
    func testABlankMaskIsRefusedReadably() async {
        let app = form()
        let image = picture(256, white: nil, name: "image.png")

        await app.attachMask(picture(256, white: nil, name: "blank.png"), to: image)
        XCTAssertNil(app.attachedMask)
        guard let problem = app.problem else { return XCTFail("no problem shown") }
        XCTAssertTrue(problem.title.contains(String(Patch.minimumPixels)))
        XCTAssertNotNil(problem.suggestion)
        XCTAssertFalse(problem.title.contains("invalid_patch"), "a sentence, not the code, reaches the interface")
    }

    /// **An empty prompt with a mask is the remove sentence** (`MaskPrompt.standard`): painted or imported,
    /// the marked area says what changes — the workflow's own « 移除图像中的绿色区域 ». A prompt the user
    /// did write stays theirs, and without a mask the field is still required.
    func testAnEmptyPromptWithAMaskIsTheRemoveSentence() async {
        let app = form()
        let image = picture(256, white: nil, name: "image.png")
        await app.attachMask(picture(256, white: CGRect(x: 100, y: 100, width: 40, height: 40), name: "mask.png"),
                             to: image)
        app.prompt = ""
        XCTAssertNil(MaskPrompt.blocker(prompt: "", masked: true, mode: .remove),
                     "with a mask the prompt may be left empty")

        guard let plan = app.attachedMaskPlan, let input = app.attachedMaskInput(for: image) else {
            return XCTFail("no attachment")
        }
        let jobs = app.renderJobs(seed: 1, format: plan, patch: input, prompts: [""], edit: [])
        XCTAssertEqual(jobs[0].settings.prompt, MaskPrompt.standard,
                       "the remove branch fills in the workflow's sentence")
        XCTAssertEqual(jobs[0].settings.patch?.mode, .remove)

        let typed = app.renderJobs(seed: 2, format: plan, patch: input, prompts: ["a cat"], edit: [])
        XCTAssertEqual(typed[0].settings.prompt, "a cat", "a prompt the user wrote is not replaced")

        app.removeMask()
        app.prompt = ""
        XCTAssertEqual(MaskPrompt.blocker(prompt: "", masked: false, mode: .remove), "Write a prompt.",
                       "without a mask an empty prompt still has nothing to render")
    }

    /// **The redraw branch never takes the remove sentence**: it would be inventing what the marked area
    /// becomes, so an empty prompt is refused with a sentence — and the job's prompt stays empty, never
    /// silently filled. (The form's branch is the LoRA stack's, so the message is tested where it lives,
    /// `MaskPrompt.blocker`; the job's prompt below carries the redraw settings directly.)
    func testARedrawAsksForItsOwnPrompt() async {
        let app = form()
        let image = picture(256, white: nil, name: "image.png")
        await app.attachMask(picture(256, white: CGRect(x: 100, y: 100, width: 40, height: 40), name: "mask.png"),
                             to: image)
        XCTAssertNil(MaskPrompt.blocker(prompt: "", masked: true, mode: .remove),
                     "remove fills the sentence in")
        XCTAssertEqual(MaskPrompt.blocker(prompt: "", masked: true, mode: .redraw),
                       "Redraw needs a prompt: say what the marked area becomes.")
        XCTAssertEqual(MaskPrompt.blocker(prompt: "", masked: false, mode: .remove), "Write a prompt.")
        XCTAssertNil(MaskPrompt.blocker(prompt: "a cat", masked: false, mode: .remove),
                     "a prompt the user wrote needs no sentence")

        guard let plan = app.attachedMaskPlan, let mask = app.attachedMask?.mask else {
            return XCTFail("no attachment")
        }
        let redraw: PatchInput = (image, mask, Patch.Settings(mode: .redraw))
        let jobs = app.renderJobs(seed: 1, format: plan, patch: redraw, prompts: [""], edit: [])
        XCTAssertEqual(jobs[0].settings.prompt, "", "the redraw branch never fills one in")
        XCTAssertEqual(jobs[0].settings.patch?.mode, .redraw)
    }

    /// **A redo keeps its entry's own mask, and an ordinary redo never takes the lab's.**
    func testARedoKeepsItsOwnMaskAndIgnoresTheLabs() async {
        let app = form()
        let image = picture(256, white: nil, name: "image.png")
        await app.attachMask(picture(256, white: CGRect(x: 100, y: 100, width: 40, height: 40), name: "lab.png"),
                             to: image)
        XCTAssertNotNil(app.attachedMask)

        let entryImage = source(640, name: "entry.png")
        let entryMask = source(640, name: "entry-mask.png")
        var geometry = Patch.Settings()
        geometry.noiseMask = false
        var settings = RenderSettings(identifier: "qwen-image-2.1", modelName: "Qwen-Image-2.1", prompt: "a cat",
                                      format: RecommendedFormat(864, 512), steps: 9, loras: [], references: 0)
        settings.patch = geometry
        let patchEntry = Entry(ordinal: 1, job: 1, png: Data(), vignette: onePixel(), width: 864, height: 512,
                               seed: 9, timings: .init(), footprints: .init(), evaluations: 0, settings: settings,
                               metadata: [:], start: entryImage, mask: entryMask)
        var plainSettings = settings
        plainSettings.patch = nil
        let plainEntry = Entry(ordinal: 2, job: 2, png: Data(), vignette: onePixel(), width: 1024, height: 1024,
                               seed: 10, timings: .init(), footprints: .init(), evaluations: 0,
                               settings: plainSettings, metadata: [:])

        let redone = app.redoPatch(patchEntry)
        XCTAssertEqual(redone?.image.name, "entry.png", "the image it was rendered from")
        XCTAssertEqual(redone?.mask.name, "entry-mask.png", "the mask it was rendered with")
        XCTAssertEqual(redone?.settings.noiseMask, false, "and its own margins")
        XCTAssertNil(app.redoPatch(plainEntry), "an ordinary image's redo stays ordinary")
        XCTAssertNotNil(app.attachedMask, "a redo neither takes nor clears the lab's attachment")
    }

    /// A gray square: image 1 as the painter decodes it.
    private func square(_ side: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()!
    }

    /// The workflow's preset as the library holds it: a card whose `nom` is the preset's file name.
    private func loraCard(_ preset: PatchLoRA) -> LoRACard {
        LoRACard(header: ["kind": "lora", "cible": ["modele": PatchLoRA.workflow], "nom": preset.fileName],
                 path: "/tmp/\(preset.rawValue).lora.silicon")!
    }

    /// Image 1 with its mask attached — the size and the pixels a click takes (`attachMask`).
    @discardableResult
    private func attachAMask(to app: AppState, side: Int = 256) async -> ReferenceImage {
        let image = picture(side, white: nil, name: "image.png")
        await app.attachMask(picture(side, white: CGRect(x: 100, y: 100, width: 40, height: 40), name: "mask.png"),
                             to: image)
        return image
    }

    /// **The redraw preset's branch reaches the job** (`AppState+Render.swift`): its card switched on in
    /// the rack gives `Patch.Settings.mode == .redraw` — the engine's `tint: mode != .redraw` false, so
    /// the crop is not painted green — and the stack holds one LoRA at the workflow's 0.48.
    func testARedrawPresetRendersTheRedrawBranch() async {
        let app = form()
        let redraw = loraCard(.redraw)
        app.compatibleLoras = [redraw]
        app.loras = [LoRASlot(path: redraw.path, strength: PatchLoRA.redraw.strength)]
        let image = await attachAMask(to: app)
        XCTAssertEqual(app.patchMode, .redraw, "the rack's card picks the branch")

        guard let plan = app.attachedMaskPlan, let input = app.attachedMaskInput(for: image) else {
            return XCTFail("no attachment")
        }
        XCTAssertEqual(input.settings.mode, .redraw, "the click takes the rack's branch, not the default")
        let jobs = app.renderJobs(seed: 7, format: plan, patch: input, prompts: ["a red jacket"], edit: [])
        XCTAssertEqual(jobs[0].settings.patch?.mode, .redraw)
        XCTAssertEqual(jobs[0].settings.loras.count, 1, "one LoRA: the preset's, never a remove one beside it")
        XCTAssertEqual(jobs[0].settings.loras.first?.strength, PatchLoRA.redraw.strength)
    }

    /// **The remove preset's branch**: its card gives `mode == .remove` — the tinted crop — and its
    /// one LoRA at the workflow's 1.0.
    func testARemovePresetRendersTheRemoveBranch() async {
        let app = form()
        let remove = loraCard(.remove)
        app.compatibleLoras = [remove]
        app.loras = [LoRASlot(path: remove.path, strength: PatchLoRA.remove.strength)]
        let image = await attachAMask(to: app)
        XCTAssertEqual(app.patchMode, .remove)

        guard let plan = app.attachedMaskPlan, let input = app.attachedMaskInput(for: image) else {
            return XCTFail("no attachment")
        }
        XCTAssertEqual(input.settings.mode, .remove)
        let jobs = app.renderJobs(seed: 8, format: plan, patch: input, prompts: ["remove the lamp"], edit: [])
        XCTAssertEqual(jobs[0].settings.patch?.mode, .remove)
        XCTAssertEqual(jobs[0].settings.loras.count, 1)
        XCTAssertEqual(jobs[0].settings.loras.first?.strength, PatchLoRA.remove.strength)
    }

    /// **Both presets switched on are refused before a job is made** (`maskBlocker`): neither branch is
    /// the mask's. Switching one off leaves the other's, so the refusal goes.
    func testTwoPresetsOnAreRefusedBeforeGenerate() async {
        let app = form()
        let remove = loraCard(.remove), redraw = loraCard(.redraw)
        app.compatibleLoras = [remove, redraw]
        app.loras = [LoRASlot(path: remove.path, strength: PatchLoRA.remove.strength),
                     LoRASlot(path: redraw.path, strength: PatchLoRA.redraw.strength)]
        await attachAMask(to: app)

        let blocker = app.maskBlocker
        XCTAssertNotNil(blocker)
        XCTAssertTrue(blocker?.contains("exclusive") == true,
                      "the two presets' branches are exclusive — got \(blocker ?? "nil")")

        app.loras[1].on = false
        XCTAssertNotEqual(app.maskBlocker?.contains("exclusive"), true,
                          "a card switched off is not stacked, so no conflict")
    }

    /// **A preset card switched off does not pick the branch** (`patchMode` reads `activeLoRAs`): redraw
    /// off is remove, on is redraw; the remove card beside it keeps remove.
    func testATurnedOffPresetDoesNotPickTheBranch() {
        let app = form()
        let remove = loraCard(.remove), redraw = loraCard(.redraw)
        app.compatibleLoras = [remove, redraw]
        var slot = LoRASlot(path: redraw.path, strength: PatchLoRA.redraw.strength)
        slot.on = false
        app.loras = [slot]
        XCTAssertEqual(app.patchMode, .remove, "switched off: not in the stack")
        app.loras[0].on = true
        XCTAssertEqual(app.patchMode, .redraw)
        app.loras[0].on = false
        app.loras.append(LoRASlot(path: remove.path, strength: PatchLoRA.remove.strength))
        XCTAssertEqual(app.patchMode, .remove, "the remove card alone")
    }

    /// **A painted mask with the redraw preset leaves the crop untinted**: the brush's bitmap goes
    /// through the same attachment as a PNG, and the click's branch is the rack's — `.redraw`, where
    /// `execute` builds `Patch(tint: settings.patch?.mode != .redraw)`, hence tint false.
    func testAPaintedMaskWithTheRedrawPresetIsNotTinted() async throws {
        let app = form()
        let redraw = loraCard(.redraw)
        app.compatibleLoras = [redraw]
        app.loras = [LoRASlot(path: redraw.path, strength: PatchLoRA.redraw.strength)]

        let side = 256
        let pixels = square(side)
        let image = ReferenceImage(source: .image(pixels),
                                   vignette: NSImage(cgImage: pixels, size: NSSize(width: side, height: side)),
                                   name: "image.png", width: side, height: side)
        var session = MaskSession(image: pixels, imageID: image.id)
        session.strokes = [MaskSession.Stroke(tool: .brush, radius: 20,
                                              points: [CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 100)])]
        let painted = try XCTUnwrap(session.maskImage())
        let mask = ReferenceImage(source: .image(painted),
                                  vignette: NSImage(cgImage: painted, size: NSSize(width: side, height: side)),
                                  name: "Painted mask", width: side, height: side)
        await app.attachMask(mask, to: image)
        XCTAssertNotNil(app.attachedMask, "the painted mask is attached")

        guard let plan = app.attachedMaskPlan, let input = app.attachedMaskInput(for: image) else {
            return XCTFail("no attachment")
        }
        XCTAssertEqual(input.settings.mode, .redraw, "the painted entry takes the rack's branch")
        let jobs = app.renderJobs(seed: 9, format: plan, patch: input, prompts: ["a red jacket"], edit: [])
        XCTAssertEqual(jobs[0].settings.patch?.mode, .redraw,
                       "redraw: the engine leaves the painted crop as it is (no green)")
    }
}
