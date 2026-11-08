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
}
