// **The Prompt Lab's expand entry** (`AppState+Expand.swift`): four pad percents over image 1, no brush,
// one click, the 「扩图」 path.
//
// The tests read the form and the jobs a click makes — no model is installed, nothing is decoded but
// the pictures these tests draw. What they keep:
//
// - pads attached with the workflow's defaults make the job carry `expand` (pads 30/30/0/0, the
//   ceiling 2048) and the render's format become the canvas's plan, not image 1's editing size;
// - the click consumes them: the next click is ordinary, at the form's format;
// - all four pads 0 — and pads outside 0–200 — are refused before anything attaches;
// - an expand beside a mask is refused, either way attached, before the click (`formBlocker`);
// - an ON expand preset card beside a mask is refused too (`maskBlocker`, the CLI's `lora` rule);
// - `settings.expand` survives « Reuse These Settings » without writing the canvas's size into the
//   form, and a redo reads its entry's own image and pads (`redoExpand`);
// - an expand entry's curtain compares against the original image it grew from;
// - the expand preset's LoRA is wired into the job's stack at the workflow's 0.7.

import AppKit
import Siliconed
import XCTest
@testable import SiliconedApp

@MainActor
final class ExpandEntryTests: XCTestCase {
    private func form() -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ExpandEntryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppState(library: Library(root: root))
    }

    /// A gray picture, decoded from its pixels — image 1 as the form carries it.
    private func picture(_ side: Int, name: String) -> ReferenceImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let cg = context.makeImage()!
        return ReferenceImage(source: .image(cg),
                              vignette: NSImage(cgImage: cg, size: NSSize(width: side, height: side)),
                              name: name, width: side, height: side)
    }

    /// A white-on-black mask of `side`'s size, with a region to replace — the mask tests' own shape.
    private func mask(_ side: Int, name: String = "mask.png") -> ReferenceImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 100, y: 100, width: 40, height: 40))
        let cg = context.makeImage()!
        return ReferenceImage(source: .image(cg),
                              vignette: NSImage(cgImage: cg, size: NSSize(width: side, height: side)),
                              name: name, width: side, height: side)
    }

    /// A source of the 「移除」/「扩图」 paths — only its size matters here, nothing is decoded.
    private func source(_ side: Int, name: String) -> ReferenceImage {
        ReferenceImage(source: .bytes(Data()), vignette: NSImage(size: NSSize(width: side, height: side)),
                       name: name, width: side, height: side)
    }

    private func onePixel() -> CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// The workflow's preset as the library holds it: a card whose `nom` is the preset's file name.
    private func loraCard(_ preset: PatchLoRA) -> LoRACard {
        LoRACard(header: ["kind": "lora", "cible": ["modele": PatchLoRA.workflow], "nom": preset.fileName],
                 path: "/tmp/\(preset.rawValue).lora.silicon")!
    }

    /// **Attached with the workflow's defaults → the next render is an expand at the canvas's size;
    /// then it is gone.**
    func testAnAttachedExpandDrivesOneRenderThenGoes() async {
        let app = form()
        let image = picture(256, name: "image.png")

        await app.attachExpand(Expand.Pads(), to: image)
        XCTAssertNotNil(app.attachedExpand, "the workflow's own 30/30/0/0 is accepted")
        XCTAssertEqual(app.attachedExpand?.pads, Expand.Pads(), "left 30, right 30, above and below 0")
        XCTAssertNil(app.problem)
        XCTAssertEqual(app.steps, Patch.defaultSteps, "the expand walks the mask path's own nine")
        guard let plan = app.attachedExpand?.plan else { return XCTFail("no plan") }
        XCTAssertEqual(plan, try? Expand.plan(pads: Expand.Pads(), width: 256, height: 256),
                       "the plan is the engine's, computed once at attach")
        XCTAssertGreaterThanOrEqual(plan.width, Expand.minimumSampleSide, "the long side reaches the graph's floor")
        XCTAssertEqual(app.attachedExpandPlan, RecommendedFormat(plan.width, plan.height),
                       "the render's size is the canvas's plan")

        // The job this click makes: the canvas is image 1, the pads ride the settings.
        guard let input = app.attachedExpandInput(for: image) else { return XCTFail("no attachment") }
        XCTAssertEqual(input.settings, ExpandSettings(), "pads 30/30/0/0, the ceiling 2048 — no GUI control")
        let jobs = app.renderJobs(seed: 7, format: app.attachedExpandPlan!, patch: nil, expand: input,
                                  prompts: ["more waves"], edit: [])
        XCTAssertEqual(jobs.count, 1)
        XCTAssertNotNil(jobs[0].expand, "with the pads the job is the 「扩图」 path")
        XCTAssertNil(jobs[0].patch, "no mask beside the canvas")
        XCTAssertNil(jobs[0].start, "the render starts from noise, never from the image")
        XCTAssertEqual(jobs[0].expand?.name, "image.png", "the canvas grows around image 1")
        XCTAssertEqual(jobs[0].settings.expand, ExpandSettings())
        XCTAssertEqual(jobs[0].settings.format, RecommendedFormat(plan.width, plan.height),
                       "the job renders at the canvas's plan, not image 1's size")
        XCTAssertEqual(jobs[0].references.count, 0, "an expand reads image 1 alone")
        XCTAssertEqual(jobs[0].settings.prompt, "more waves", "the user's words are the supplement, kept as typed")

        // The click takes it — once, and the form is ordinary again.
        XCTAssertNotNil(app.takeAttachedExpand())
        XCTAssertNil(app.attachedExpand)
        XCTAssertNil(app.attachedExpandInput(for: image))
        let plain = app.renderJobs(seed: 8, format: RecommendedFormat(512, 512), patch: nil, expand: nil,
                                   prompts: ["a cat"], edit: [])
        XCTAssertNil(plain[0].expand, "the next click carries no canvas")
        XCTAssertNil(plain[0].settings.expand)
        XCTAssertEqual(plain[0].settings.format, RecommendedFormat(512, 512), "and it renders at the form's format")
    }

    /// **An empty prompt beside the pads is the fixed sentence's to fill** — the job keeps the empty
    /// string, the engine leading with the workflow's own (`Expand.promptPrefix`, `EngineRender`).
    func testAnEmptyPromptStaysEmptyBesideThePads() async {
        let app = form()
        let image = picture(256, name: "image.png")
        await app.attachExpand(Expand.Pads(), to: image)
        guard let input = app.attachedExpandInput(for: image) else { return XCTFail("no attachment") }

        let jobs = app.renderJobs(seed: 3, format: app.attachedExpandPlan!, patch: nil, expand: input,
                                  prompts: [""], edit: [])
        XCTAssertEqual(jobs[0].settings.prompt, "", "the fixed sentence is the engine's to prepend")
    }

    /// **The pads are the engine's to judge, said before anything attaches**: all four 0 is nothing to
    /// expand; a percent outside 0–200 is outside the workflow; good pads land in the plan.
    func testThePadsAreValidatedBeforeAttaching() async {
        let app = form()
        let image = picture(256, name: "image.png")

        await app.attachExpand(Expand.Pads(left: 0, right: 0, top: 0, bottom: 0), to: image)
        XCTAssertNil(app.attachedExpand, "all four pads 0: nothing to expand")
        XCTAssertNotNil(app.problem, "the engine's refusal, said")

        await app.attachExpand(Expand.Pads(left: 250, right: 0, top: 0, bottom: 0), to: image)
        XCTAssertNil(app.attachedExpand, "a pad beyond 200 percent is outside the workflow")
        XCTAssertNotNil(app.problem)

        let pads = Expand.Pads(left: 10, right: 20, top: 30, bottom: 40)
        await app.attachExpand(pads, to: image)
        XCTAssertNotNil(app.attachedExpand, "pads inside the range attach")
        XCTAssertEqual(app.attachedExpand?.pads, pads)
        XCTAssertEqual(app.attachedExpand?.plan, try? Expand.plan(pads: pads, width: 256, height: 256))
    }

    /// **An expand beside a mask is refused, whichever attached second**: the mask says which region
    /// changes, the expand keeps the whole image — the engine refuses them together, and the form says
    /// so before the click.
    func testAnExpandBesideAMaskIsRefusedBothWays() async {
        // The mask first, the pads second: the attachment is refused.
        let app = form()
        let image = picture(256, name: "image.png")
        await app.attachMask(mask(256), to: image)
        XCTAssertNotNil(app.attachedMask)
        await app.attachExpand(Expand.Pads(), to: image)
        XCTAssertNil(app.attachedExpand, "the mask is already attached: no canvas beside it")
        XCTAssertNotNil(app.problem)
        XCTAssertNotNil(app.attachedMask, "and the mask survives the refusal")

        // The pads first, the mask second: the attachment is refused the other way.
        let other = form()
        let padsImage = picture(256, name: "pads.png")
        await other.attachExpand(Expand.Pads(), to: padsImage)
        XCTAssertNotNil(other.attachedExpand)
        await other.attachMask(mask(256), to: image)
        XCTAssertNil(other.attachedMask, "the expand is already attached: no mask beside it")
        XCTAssertNotNil(other.problem, "and the refusal is said")

        // Both set directly (any path that leaves them on): both blockers say it, « Generate » greys.
        let both = form()
        let plan = try! Expand.plan(pads: Expand.Pads(), width: 256, height: 256)
        both.attachedExpand = AttachedExpand(pads: Expand.Pads(), plan: plan)
        both.attachedMask = AttachedMask(mask: mask(256), plan: try! Patch.plan(
            mask: ImageMask(image: try! mask(256).imageRGB()), width: 256, height: 256))
        XCTAssertNotNil(both.maskBlocker, "the mask's blocker refuses the pads beside it")
        XCTAssertTrue(both.maskBlocker?.contains("expand") == true, "got \(both.maskBlocker ?? "nil")")
        XCTAssertNotNil(both.expandBlocker, "the expand's blocker refuses the mask beside it")
        XCTAssertTrue(both.expandBlocker?.contains("mask") == true, "got \(both.expandBlocker ?? "nil")")
        XCTAssertNotNil(both.formBlocker, "« Generate » is greyed with the sentence")
    }

    /// **An ON expand preset card beside a mask is refused** (`maskBlocker`): the card belongs to the
    /// 「扩图」 workflow, whose canvas is the opposite of a mask's replace-region — the CLI's `lora`
    /// refusal, said before the click. The card off names nothing, and the refusal goes.
    func testAnExpandCardBesideAMaskIsRefused() async {
        let app = form()
        app.compatibleLoras = [loraCard(.expand)]
        app.loras = [LoRASlot(path: loraCard(.expand).path, strength: PatchLoRA.expand.strength)]
        let image = picture(256, name: "image.png")
        await app.attachMask(mask(256), to: image)

        let blocker = app.maskBlocker
        XCTAssertNotNil(blocker)
        XCTAssertTrue(blocker?.contains("expand") == true,
                      "the expand preset is no mask branch — got \(blocker ?? "nil")")

        app.loras[0].on = false
        XCTAssertNotEqual(app.maskBlocker?.contains("expand"), true,
                          "a card switched off is not stacked, so no conflict")
    }

    /// **A mask branch's preset card beside the pads is refused** (`expandBlocker`): remove and redraw
    /// are the mask workflow's branches, the canvas has none of them — the CLI's `mode` refusal.
    func testAMaskPresetCardBesideThePadsIsRefused() async {
        let app = form()
        app.compatibleLoras = [loraCard(.remove)]
        app.loras = [LoRASlot(path: loraCard(.remove).path, strength: PatchLoRA.remove.strength)]
        let image = picture(256, name: "image.png")
        await app.attachExpand(Expand.Pads(), to: image)

        XCTAssertTrue(app.expandBlocker?.contains("mask") == true, "got \(app.expandBlocker ?? "nil")")
        app.loras[0].on = false
        XCTAssertNotEqual(app.expandBlocker?.contains("mask"), true, "the card off names no branch")
    }

    /// **`settings.expand` survives « Reuse These Settings » and « Render Again » without leaking the
    /// canvas's size into the form** — the state-leak rule the mask's settings keep: a redo draws the
    /// same canvas from its entry's own image and pads, and the ordinary click after it carries none.
    func testTheExpandSettingsSurviveReuseAndARedoStaysItsOwn() {
        let app = form()
        let chosen = RecommendedFormat(512, 512)
        app.format = chosen
        app.prompt = "more waves"

        let image = source(640, name: "entry.png")
        let pads = ExpandSettings(pads: Expand.Pads(left: 20, right: 20, top: 0, bottom: 0), maximumSample: 2048)

        // t1: the 「扩图」 path, at the canvas's plan size.
        let expandJobs = app.renderJobs(seed: 1001, format: RecommendedFormat(1152, 896), patch: nil,
                                        expand: (image, pads), prompts: ["more waves"], edit: [])
        XCTAssertEqual(expandJobs.count, 1)
        XCTAssertEqual(expandJobs[0].settings.expand, pads, "the expand job keeps its pads")
        XCTAssertNotNil(expandJobs[0].expand, "the expand job keeps its image")
        XCTAssertEqual(expandJobs[0].settings.format, RecommendedFormat(1152, 896))

        // The form takes what the expand job computed, as the remote control leaves it…
        app.restoreSettings(expandJobs[0].settings)

        // …t2: an ordinary render, from the form as it stands.
        let plainJobs = app.renderJobs(seed: 1002, format: app.format, patch: nil, expand: nil,
                                       prompts: ["a cat"], edit: [])
        XCTAssertEqual(app.format, chosen, "the canvas's size must not become the form's format")
        XCTAssertNil(plainJobs[0].settings.expand, "the second job must carry no expand settings")
        XCTAssertNil(plainJobs[0].expand, "the second job must carry no canvas")
        XCTAssertEqual(plainJobs[0].settings.format, chosen, "the second job renders at the form's format")

        // The redo: the entry's own image and pads, never the lab's attachment.
        var settings = expandJobs[0].settings
        settings.offer = .none; settings.fasterRendering = false
        let entry = Entry(ordinal: 1, job: 1, png: Data(), vignette: onePixel(), width: 1152, height: 896,
                          seed: 9, timings: .init(), footprints: .init(), evaluations: 0, settings: settings,
                          metadata: [:], start: image)
        let redone = app.redoExpand(entry)
        XCTAssertEqual(redone?.image.name, "entry.png", "the image the canvas grew around")
        XCTAssertEqual(redone?.settings, pads, "the pads it was drawn at")

        var plainSettings = settings
        plainSettings.expand = nil
        let plainEntry = Entry(ordinal: 2, job: 2, png: Data(), vignette: onePixel(), width: 1024, height: 1024,
                               seed: 10, timings: .init(), footprints: .init(), evaluations: 0,
                               settings: plainSettings, metadata: [:])
        XCTAssertNil(app.redoExpand(plainEntry), "an ordinary image's redo stays ordinary")
    }

    /// **An expand entry's curtain compares against the original image**: the original sits inside the
    /// bigger picture — the comparison the workflow's own Image Comparer draws.
    func testAnExpandEntryComparesAgainstTheOriginalImage() async {
        let app = form()
        let original = picture(512, name: "original.png")
        var settings = RenderSettings(identifier: "qwen-image-2.1", modelName: "Qwen-Image-2.1", prompt: "more waves",
                                      format: RecommendedFormat(896, 896), steps: 9, loras: [], references: 0)
        settings.expand = ExpandSettings()
        let entry = Entry(ordinal: 1, job: 1, png: Data(), vignette: onePixel(), width: 896, height: 896,
                          seed: 1, timings: .init(), footprints: .init(), evaluations: 0, settings: settings,
                          metadata: [:], start: original)
        app.history = [entry]

        XCTAssertEqual(app.comparisonStart(entry)?.name, "original.png", "the original is the curtain's image")
        XCTAssertTrue(app.canCompareOriginal(entry), "the bar draws the button")
        app.comparesOriginal = true
        let decoded = await Self.waitForOriginal(app)
        XCTAssertNotNil(decoded, "the original decodes, under the grown canvas")
        XCTAssertTrue(app.showsOriginal, "and the curtain is what the canvas shows")
    }

    /// **The expand preset's LoRA is wired into the stack at the workflow's 0.7** — once, and never
    /// doubled when the card is already there.
    func testTheExpandPresetIsWiredIntoTheStack() async {
        let app = form()
        app.compatibleLoras = [loraCard(.expand)]
        let image = picture(256, name: "image.png")
        await app.attachExpand(Expand.Pads(), to: image)
        guard let input = app.attachedExpandInput(for: image) else { return XCTFail("no attachment") }

        let jobs = app.renderJobs(seed: 5, format: app.attachedExpandPlan!, patch: nil, expand: input,
                                  prompts: ["more waves"], edit: [])
        XCTAssertEqual(jobs[0].settings.loras.count, 1, "one LoRA: the preset's, wired for you")
        XCTAssertEqual(jobs[0].settings.loras.first?.strength, PatchLoRA.expand.strength, "the workflow's 0.7")

        app.loras = [LoRASlot(path: loraCard(.expand).path, strength: 0.5)]
        let restacked = app.renderJobs(seed: 6, format: app.attachedExpandPlan!, patch: nil, expand: input,
                                       prompts: ["more waves"], edit: [])
        XCTAssertEqual(restacked[0].settings.loras.count, 1, "the card already in the rack is not doubled")
        XCTAssertEqual(restacked[0].settings.loras.first?.strength, 0.5, "the strength the rack holds stays")
    }

    /// The curtain's own decode is off the main thread: wait for it, as the canvas does.
    private static func waitForOriginal(_ app: AppState) async -> CGImage? {
        for _ in 0..<50 {
            if let image = app.original?.image { return image }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }
}
