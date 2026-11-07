import XCTest
@testable import Siliconed

/// **What the chain says of a request before any computation** (`Admission`): pure, no weight, no file — the chains have empty
/// paths, so a test that touched one would not get the error it expects. Also the one rule of the half-size start
/// (`Spectral.reducedEvaluations`) and its field on the request.
final class AdmissionTests: XCTestCase {

    private let zImage = try! Chain(
        text: ZImageTextModule(map: "", tokenizer: ""), denoising: ZImageDenoisingModule(map: ""),
        decoding: FluxDecodingModule(path: ""), encoding: FluxEncodingModule(path: ""))

    private let qwen = try! Chain(
        text: QwenImage21TextModule(map: "", tokenizer: ""),
        denoising: QwenImage21DenoisingModule(map: "", scheduler: .init()),
        decoding: QwenImage21DecodingModule(path: ""), encoding: QwenImage21EncodingModule(path: ""))

    private func judge(_ request: Request, usesANE: Bool = true) throws -> Admission {
        try Admission.judge(request, chain: zImage, usesANE: usesANE)
    }

    func testTheGridStepsAndPlanOfARequest() throws {
        let a = try judge(Request("a cat", width: 1024, height: 1536))
        XCTAssertEqual([a.height, a.width], [192, 128])
        XCTAssertEqual(a.steps, zImage.denoising.defaultSteps)
        XCTAssertEqual(a.start, 0)
        XCTAssertEqual(a.plan.evaluations, a.steps)
        XCTAssertEqual(a.plan.reduced, 0, "off by default: the recipe at full size")
    }

    func testRefusalsComeInTheirOrderAndBeforeAnything() {
        XCTAssertThrowsError(try judge(Request("  \n", resolution: 512))) {
            XCTAssertEqual($0 as? Request.Failure, .emptyPrompt)
        }
        var many = Request("x", resolution: 512); many.steps = Request.maximumSteps + 1
        XCTAssertThrowsError(try judge(many)) { XCTAssertEqual($0 as? Request.Failure, .steps(Request.maximumSteps + 1)) }
        var detail = Request("x", resolution: 512); detail.detail = .more
        XCTAssertNoThrow(try judge(detail), "Z-Image offers Detail")
        var solver = Request("x", resolution: 512); solver.solver = .unipc
        XCTAssertNoThrow(try judge(solver))
    }

    func testTheNeuralEngineIsAskedAndOffered() throws {
        var request = Request("x", resolution: 512)
        XCTAssertTrue(try judge(request, usesANE: true).neuralEngine)
        XCTAssertFalse(try judge(request, usesANE: false).neuralEngine, "the plan has no ANE")
        request.neuralEngine = false
        XCTAssertFalse(try judge(request, usesANE: true).neuralEngine)
    }

    func testFasterRenderingIsTheRequestsAndReachesThePlan() throws {
        try XCTSkipIf(Spectral.forced != nil, "SILICONED_SPECTRAL forces k")
        var request = Request("x", resolution: 1024)
        let off = try judge(request)
        XCTAssertFalse(off.fasterRendering); XCTAssertEqual(off.plan.reduced, 0)
        request.fasterRendering = true
        let on = try judge(request)
        XCTAssertTrue(on.fasterRendering)
        XCTAssertEqual(on.plan.reduced, ZImageDenoisingModule.halfSizeSteps)
        // The rule's own refusals still hold: a LoRA, a format that does not halve.
        var lora = request; lora.loras = [LoRAEntry("x.lora.silicon")]
        XCTAssertEqual(try judge(lora).plan.reduced, 0)
        var small = Request("x", resolution: 512); small.fasterRendering = true
        XCTAssertEqual(try judge(small).plan.reduced, 0)
    }

    /// The rule, alone: the recipe's step count, the first step, the floor, no LoRA — and a forcing replaces the family's count.
    func testTheHalfSizeRuleAlone() throws {
        try XCTSkipIf(Spectral.forced != nil, "SILICONED_SPECTRAL forces k")
        func k(faster: Bool = true, size: Int = 128, steps: Int = 8, start: Int = 0, lora: Bool = false, evaluations: Int = 8) -> Int {
            Spectral.reducedEvaluations(faster: faster, height: size, width: size, steps: steps, start: start, withLoRA: lora,
                                        defaultSteps: 8, halfSizeSteps: 3, evaluations: evaluations)
        }
        XCTAssertEqual(k(), 3)
        XCTAssertEqual(k(faster: false), 0)
        XCTAssertEqual(k(size: 64), 0, "512²")
        XCTAssertEqual(k(steps: 12), 0, "off the recipe")
        XCTAssertEqual(k(start: 1), 0)
        XCTAssertEqual(k(lora: true), 0)
        XCTAssertEqual(k(evaluations: 3), 2, "one evaluation at least stays at full size")
    }

    func testTheRequestAndTheRenderKeepTheSwitchInTheirMetadata() {
        var request = Request("x", resolution: 1024)
        XCTAssertFalse(request.fasterRendering)
        request.fasterRendering = true
        XCTAssertNotEqual(request, Request("x", resolution: 1024))
        let text = Infotext.text(prompt: "x", steps: 8, sampler: .euler, seed: 1, width: 1024, height: 1024, model: "m",
                                 strength: nil, loras: [], civitaiModelVersion: nil, version: nil, fasterRendering: true)
        XCTAssertTrue(text.contains("Faster rendering: true"))
        let plain = Infotext.text(prompt: "x", steps: 8, sampler: .euler, seed: 1, width: 1024, height: 1024, model: "m",
                                  strength: nil, loras: [], civitaiModelVersion: nil, version: nil)
        XCTAssertFalse(plain.contains("Faster rendering"))
    }

    /// **C2**: a reference resolution is judged with the request, before the memory it charges: an
    /// edit at 1536² is admitted, 1000 px (not a multiple of 32) and 3000 px (past the crop) are refused
    /// as `Request.Failure.referenceResolution`; unset stays the published 1024.
    func testTheReferenceResolutionIsJudgedBeforeAnyComputation() throws {
        let reference = ImageRGB(pixels: [Float](repeating: 0, count: 3 * 64 * 64), height: 64, width: 64)
        var edit = Request("x", resolution: 512)
        edit.references = [reference]
        XCTAssertNoThrow(try Admission.judge(edit, chain: qwen, usesANE: false))
        edit.referenceResolution = 1536
        XCTAssertNoThrow(try Admission.judge(edit, chain: qwen, usesANE: false))
        for r in [1000, 3000] {
            edit.referenceResolution = r
            XCTAssertThrowsError(try Admission.judge(edit, chain: qwen, usesANE: false), "\(r)") {
                guard let failure = $0 as? Request.Failure, case .referenceResolution = failure else {
                    return XCTFail("\($0)")
                }
            }
        }
    }

    /// **B**: a `--mask` crop that is the render's own size (`Patch.Plan.primaryMatchesTarget`, the
    /// workflow's 64 px a side) is image 1 and the reference block **at that size**: an explicit
    /// `--ref-res` is refused there — not silently ignored — and admitted once left out.
    func testAPatchWhoseCropIsTheRenderRefusesAReferenceResolution() throws {
        let values = (0..<(1000 * 700)).map { i -> Float in
            let x = i % 1000, y = i / 1000
            return x >= 400 && x < 600 && y >= 250 && y < 450 ? 1 : 0
        }
        let patch = Patch(image: ImageRGB(pixels: [Float](repeating: 0, count: 3 * 1000 * 700), height: 700,
                                          width: 1000),
                          mask: ImageMask(width: 1000, height: 700, values: values))
        var request = Request("x", resolution: 512)
        request.patch = patch
        request.referenceResolution = 1024
        XCTAssertTrue(try patch.plan().primaryMatchesTarget)
        XCTAssertThrowsError(try Admission.judge(request, chain: qwen, usesANE: false)) {
            guard let error = $0 as? EngineError, case .invalidReferenceResolution(let reason) = error else {
                return XCTFail("\($0)")
            }
            XCTAssertTrue(reason.contains("--ref-res does not apply"), reason)
        }
        request.referenceResolution = nil
        XCTAssertNoThrow(try Admission.judge(request, chain: qwen, usesANE: false))
    }

    /// **Qwen-Image-2.1-Turbo's 9-step workflow table** (C1): `--steps 9` is admitted and plans nine
    /// evaluations (the module walks the graph's `ManualSigmas` — to the bit in
    /// `QwenImage21PipelineTests`); a σ table the request supplies sets the steps from its length, and a
    /// `steps` that disagrees with it is refused before any computation. Every other family refuses a
    /// table: its schedule is the artifact's.
    func testQwenNineStepsAndASigmaTableAreAdmitted() throws {
        var nine = Request("x", resolution: 512); nine.steps = 9
        let a = try Admission.judge(nine, chain: qwen, usesANE: false)
        XCTAssertEqual(a.steps, 9)
        XCTAssertEqual(a.plan.evaluations, 9)

        var table = Request("x", resolution: 512)
        table.sigmas = QwenImage21Pipeline.manualSigmas
        let b = try Admission.judge(table, chain: qwen, usesANE: false)
        XCTAssertEqual(b.steps, 9)
        XCTAssertEqual(b.plan.evaluations, 9)

        var mismatch = table; mismatch.steps = 8
        XCTAssertThrowsError(try Admission.judge(mismatch, chain: qwen, usesANE: false)) {
            guard let failure = $0 as? Request.Failure, case .schedule = failure else { return XCTFail("\($0)") }
        }
        var bad = Request("x", resolution: 512); bad.sigmas = [1, 0.5, 0.6, 0]
        XCTAssertThrowsError(try Admission.judge(bad, chain: qwen, usesANE: false)) {
            guard let failure = $0 as? Request.Failure, case .schedule = failure else { return XCTFail("\($0)") }
        }
        var onZImage = Request("x", resolution: 512); onZImage.sigmas = [1, 0.5, 0]
        XCTAssertThrowsError(try judge(onZImage)) {
            XCTAssertEqual($0 as? Request.Failure, .noCustomSchedule(model: zImage.denoising.model))
        }
    }

    /// **C3**: the additive start (the workflow's crop) is judged with the request, before any
    /// computation. Qwen-Image-2.1 admits it — with its published 8 σ, the workflow's 9, or a custom
    /// table — and never halves its first evaluation; its σ₀ is the first node of the schedule the
    /// render walks, so a table that starts below 1 starts at that value. Z-Image, whose img2img is
    /// `Latent.start` (`acceptsStartImage`), refuses it, and so does a request that carries both starts.
    /// Without a seeded start the img2img path is what it was: `seededSigma` nil, the strength's start.
    func testTheSeededStartIsJudgedBeforeAnyComputation() throws {
        let crop = ImageRGB(pixels: [Float](repeating: 0.5, count: 3 * 64 * 64), height: 64, width: 64)
        var seeded = Request("x", resolution: 512)
        seeded.seededStart = crop
        let a = try Admission.judge(seeded, chain: qwen, usesANE: false)
        XCTAssertEqual(a.start, 0, "not img2img: the strength plays no part")
        XCTAssertEqual(a.seededSigma, 1)
        seeded.steps = 9
        XCTAssertEqual(try Admission.judge(seeded, chain: qwen, usesANE: false).seededSigma, 1)
        seeded.sigmas = QwenImage21Pipeline.manualSigmas
        seeded.steps = nil
        XCTAssertEqual(try Admission.judge(seeded, chain: qwen, usesANE: false).seededSigma, 1)
        seeded.sigmas = [0.9, 0.6, 0.3, 0]
        let custom = try Admission.judge(seeded, chain: qwen, usesANE: false)
        XCTAssertEqual(custom.steps, 3)
        XCTAssertEqual(custom.seededSigma, 0.9, "σ₀ is the table's first node, never assumed to be 1")
        // A half-size first evaluation would project the crop onto another grid: off, as for an edit.
        var big = Request("x", resolution: 2048); big.fasterRendering = true
        XCTAssertGreaterThan(try Admission.judge(big, chain: qwen, usesANE: false).plan.reduced, 0)
        big.seededStart = crop
        XCTAssertEqual(try Admission.judge(big, chain: qwen, usesANE: false).plan.reduced, 0)
        // A model whose img2img is `Latent.start`: refused — and so is a request with both starts.
        var onZImage = Request("x", resolution: 512); onZImage.seededStart = crop
        XCTAssertThrowsError(try judge(onZImage)) {
            guard let failure = $0 as? Request.Failure, case let .seededStart(why) = failure else {
                return XCTFail("\($0)")
            }
            XCTAssertTrue(why.contains(zImage.denoising.model), why)
        }
        var both = Request("x", resolution: 512); both.image = crop; both.seededStart = crop
        XCTAssertThrowsError(try Admission.judge(both, chain: qwen, usesANE: false)) {
            guard let failure = $0 as? Request.Failure, case let .seededStart(why) = failure else {
                return XCTFail("\($0)")
            }
            XCTAssertTrue(why.contains("one image at most"), why)
        }
        // The img2img path, unchanged: no seeded sigma, the strength's own start.
        var img2img = Request("x", resolution: 512); img2img.image = crop
        let plain = try judge(img2img)
        XCTAssertNil(plain.seededSigma)
        XCTAssertEqual(plain.start, Strength.startStep(steps: plain.steps, strength: img2img.strength))
    }

    /// **C4: the mask's crop is the render's format** (`Request.patch`), and the patch owns the start
    /// rules — beside an img2img image, a seeded start or references it is refused by `invalid_patch`,
    /// as is a chain without an additive start; the prompt stays mandatory and an empty mask is refused.
    func testThePatchDecidesTheFormatAndOwnsTheStart() throws {
        let pixels = [Float](repeating: 0.2, count: 3 * 64 * 64)
        let image = ImageRGB(pixels: pixels, height: 64, width: 64)
        let mask = ImageMask(width: 64, height: 64, values: [Float](repeating: 1, count: 64 * 64))
        var request = Request("replace the sky", resolution: 512)
        request.patch = Patch(image: image, mask: mask)
        let admitted = try Admission.judge(request, chain: qwen, usesANE: false)
        XCTAssertEqual([admitted.width, admitted.height], [48, 48], "768² from the plan, not the request's 512²")
        XCTAssertEqual([admitted.patch?.width, admitted.patch?.height], [768, 768])
        XCTAssertEqual(admitted.seededSigma, 1)
        XCTAssertEqual(admitted.start, 0)
        XCTAssertEqual(admitted.plan.reduced, 0, "the crop is never projected onto a half-size grid")

        func refuses(_ request: Request, chain: Chain, _ file: StaticString = #filePath, _ line: UInt = #line) {
            XCTAssertThrowsError(try Admission.judge(request, chain: chain, usesANE: false), file: file, line: line) {
                guard let error = $0 as? EngineError, case .invalidPatch = error else {
                    return XCTFail("\($0)", file: file, line: line)
                }
            }
        }
        var started = request; started.image = image
        refuses(started, chain: qwen)
        var seeded = request; seeded.seededStart = image
        refuses(seeded, chain: qwen)
        var referenced = request; referenced.references = [image]
        refuses(referenced, chain: qwen)
        refuses(request, chain: zImage) // no additive start
        var empty = request
        empty.patch = Patch(image: image, mask: ImageMask(width: 64, height: 64,
                                                         values: [Float](repeating: 0, count: 64 * 64)))
        refuses(empty, chain: qwen)
        var blank = request; blank.prompt = "  \n"
        XCTAssertThrowsError(try Admission.judge(blank, chain: qwen, usesANE: false)) {
            XCTAssertEqual($0 as? Request.Failure, .emptyPrompt)
        }
    }
}
