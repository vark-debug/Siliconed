import XCTest
@testable import Siliconed

/// Qwen-Image-2.1-Turbo's pipeline without a byte of weights: the schedule, the noise, the sizes, the wire.
/// The expected bits are diffusers 0.41.0's (`retrieve_timesteps(sigmas=sample_sigmas, mu=μ)` with the
/// Turbo's `scheduler_config.json`) and PyTorch 2.14's
/// (`torch.randn` on a CPU generator), printed by the venv.
final class QwenImage21PipelineTests: XCTestCase {
    private func bits(_ v: [Float]) -> [UInt32] { v.map(\.bitPattern) }

    /// The Turbo's `d65dbc9a` files, as published.
    private let config = #"""
        {"_class_name": "FlowMatchEulerDiscreteScheduler", "_diffusers_version": "0.41.0.dev0", "base_image_seq_len": 256,
         "base_shift": 0.5, "invert_sigmas": false, "max_image_seq_len": 8192, "max_shift": 0.9, "num_train_timesteps": 1000,
         "shift": 1.0, "shift_terminal": null, "stochastic_sampling": false, "time_shift_type": "exponential",
         "use_beta_sigmas": false, "use_dynamic_shifting": false, "use_exponential_sigmas": false, "use_karras_sigmas": false}
        """#
    private let modelIndex = #"""
        {"_class_name": "QwenImage21Pipeline", "scheduler": ["diffusers", "FlowMatchEulerDiscreteScheduler"],
         "sample_sigmas": [1.0, 0.978453, 0.95418, 0.926626, 0.89508, 0.845148, 0.704534, 0.414568]}
        """#

    /// **σ and timesteps to the bit, as diffusers gives them** — the same in generation and editing, at
    /// 512², 1024², 1024×1536 (μ is computed and ignored): `float32(sample_sigmas)`, then 0.
    func testTheTurboScheduleIsDiffusersToTheBit() throws {
        let s = try QwenImage21Pipeline.Scheduler(config: Data(config.utf8), modelIndex: Data(modelIndex.utf8))
        XCTAssertEqual(s, QwenImage21Pipeline.Scheduler(), "the published defaults")
        let σ = s.sigmas
        XCTAssertEqual(bits(σ), [0x3f800000, 0x3f7a7be5, 0x3f744524, 0x3f6d375d, 0x3f6523f6, 0x3f585b9f, 0x3f345c57,
                                 0x3ed44242, 0])
        XCTAssertEqual(bits(QwenImage21Pipeline.timesteps(σ)),
                       [0x447a0000, 0x44749cfe, 0x446e8b85, 0x4467a811, 0x445fc51e, 0x44534979, 0x4430222d, 0x43cf48b4])
        // `scheduler.step`'s `dt = σ_next − σ`, in float32.
        XCTAssertEqual(bits(zip(σ.dropFirst(), σ).map { $0 - $1 }),
                       [0xbcb08360, 0xbcc6d820, 0xbce1b8e0, 0xbd013670, 0xbd4c8570, 0xbe0ffd20, 0xbe94766c, 0xbed44242])
        // The round trip the pipeline makes, `(σ·1000)/1000`, gives σ back to the bit for these nodes.
        for x in σ.dropLast() { XCTAssertEqual((x * 1000 / 1000).bitPattern, x.bitPattern) }
        // The module: the published schedule at 8, the graph's ManualSigmas at 9.
        let module = QwenImage21DenoisingModule(map: "", scheduler: s)
        XCTAssertEqual(module.defaultSteps, 8)
        XCTAssertEqual(bits(module.sigmas(steps: 8)), bits(σ))
        XCTAssertEqual(QwenImage21Pipeline.acceptedSteps, [8, 9])
        XCTAssertNoThrow(try QwenImage21Pipeline.check(steps: 8))
        for n in [5, 6, 7, 10] { XCTAssertThrowsError(try QwenImage21Pipeline.check(steps: n), "\(n)") }
    }

    /// **The 9-step ManualSigmas of a ComfyUI graph** (`#271` of the « 移除、局部重绘 » workflow):
    /// the published eight, then 0.150000, then 0 — to the bit; the first eight are the published
    /// ones, unchanged. And the shape a σ table must have for the sampler to walk it
    /// (`Request.admit(sigmas:)`, through `QwenImage21Pipeline.check(sigmas:)`).
    func testTheManualSigmasScheduleAndTheSigmaChecks() throws {
        let module = QwenImage21DenoisingModule(map: "", scheduler: QwenImage21Pipeline.Scheduler())
        let σ = module.sigmas(steps: 9)
        XCTAssertEqual(bits(σ), [0x3f800000, 0x3f7a7be5, 0x3f744524, 0x3f6d375d, 0x3f6523f6, 0x3f585b9f,
                                 0x3f345c57, 0x3ed44242, 0x3e19999a, 0])
        // The refinement only: the first eight do not move from the published schedule.
        XCTAssertEqual(Array(σ.prefix(8)), Array(module.sigmas(steps: 8).prefix(8)))
        XCTAssertNoThrow(try QwenImage21Pipeline.check(sigmas: σ))
        XCTAssertNoThrow(try module.check(sigmas: σ, startImage: false))
        XCTAssertThrowsError(try module.check(sigmas: σ, startImage: true))
        // What the sampler divides by: a table that does not decrease strictly to 0, that starts at
        // 0, that carries a non-finite σ, or that is one σ long, is refused before any computation.
        let bad: [[Float]] = [[0.5, 1, 0], [1, 0.5, 0.5, 0], [1, 0.5, 0.6, 0], [1, 0.5, 0.2], [0, 0], [1], [1, .nan, 0]]
        for σ in bad {
            XCTAssertThrowsError(try QwenImage21Pipeline.check(sigmas: σ), "\(σ)")
        }
        // The two-step table the published schedule is, by the same door: the engine's σ path is
        // general, the workflow's nine one table among the shapes it takes.
        XCTAssertNoThrow(try QwenImage21Pipeline.check(sigmas: [1, 0.5, 0]))
    }

    /// **C2: the reference's area is a request's (`Request.referenceResolution`)** — 1024 unless asked,
    /// then the same `calculate_dimensions(R², w/h)` at that `R`; the output size's rule does not move.
    func testTheReferenceResolutionMovesTheReferenceAlone() throws {
        // 729×486: at 1024² the oracle's condition size is 1248×832 (the test photo's own),
        // at 1536² it is 1888×1248 (sides at 32, the ratio kept).
        let image = ImageRGB(pixels: (0..<(3 * 729 * 486)).map { Float($0 % 29) / 29 }, height: 486, width: 729)
        let published = QwenImage21Pipeline.preparedReference(image)
        let explicit = QwenImage21Pipeline.preparedReference(image, resolution: 1024)
        XCTAssertEqual(published.width, 1248)
        XCTAssertEqual(published.height, 832)
        XCTAssertEqual(published.width, explicit.width)
        XCTAssertEqual(published.height, explicit.height)
        XCTAssertEqual(published.pixels, explicit.pixels, "unset is 1024, to the bit")
        let raised = QwenImage21Pipeline.preparedReference(image, resolution: 1536)
        XCTAssertEqual(raised.width, 1888)
        XCTAssertEqual(raised.height, 1248)
        XCTAssertEqual(QwenImage21Pipeline.outputSize(referenceWidth: 729, referenceHeight: 486).width, 1248,
                       "the output size still follows 1024², whatever the reference's area")
        XCTAssertEqual(QwenImage21Pipeline.outputSize(referenceWidth: 729, referenceHeight: 486).height, 832)
        // The module reads the request's `R`; without one, its own (1024 here).
        let module = QwenImage21DenoisingModule(map: "", scheduler: QwenImage21Pipeline.Scheduler())
        XCTAssertEqual(try module.preparedReferences([image], referenceResolution: 1536).first?.width, 1888)
        XCTAssertEqual(try module.preparedReferences([image], referenceResolution: nil).first?.width, 1248)
        XCTAssertEqual(try module.preparedReferences([image]).first?.width, 1248)
    }

    /// The bounds of `Request.referenceResolution`: the workflow's 768–2560 long side, a multiple of 32;
    /// `nil` (the published 1024) is always admitted.
    func testTheReferenceResolutionIsAdmittedWithinTheWorkflowsCrop() {
        let admitted: [Int?] = [nil, 768, 1024, 1536, 2560]
        for r in admitted { XCTAssertNoThrow(try Request.admit(referenceResolution: r), "\(String(describing: r))") }
        let refused = [512, 767, 2576, 1000, 1025, 0, -32]
        for r in refused {
            XCTAssertThrowsError(try Request.admit(referenceResolution: r), "\(r)") {
                guard let failure = $0 as? Request.Failure, case .referenceResolution = failure else {
                    return XCTFail("\($0)")
                }
            }
        }
    }

    /// The configs that would move the published σ are refused: the base model's dynamic shift and
    /// terminal stretch, a non-unit shift, Karras σ; and a `model_index.json` without `sample_sigmas`.
    func testTheSchedulerRefusesWhatWouldMoveTheSchedule() {
        func scheduler(_ c: String, _ m: String? = nil) throws -> QwenImage21Pipeline.Scheduler {
            try QwenImage21Pipeline.Scheduler(config: Data(c.utf8), modelIndex: Data((m ?? modelIndex).utf8))
        }
        let base = #"{"use_dynamic_shifting": true, "time_shift_type": "exponential", "shift_terminal": 0.02}"#
        XCTAssertThrowsError(try scheduler(base))
        XCTAssertThrowsError(try scheduler(#"{"use_dynamic_shifting": false, "shift": 3.0}"#))
        XCTAssertThrowsError(try scheduler(#"{"use_dynamic_shifting": false, "shift_terminal": 0.02}"#))
        XCTAssertThrowsError(try scheduler(#"{"use_dynamic_shifting": false, "use_karras_sigmas": true}"#))
        XCTAssertThrowsError(try scheduler(#"{"use_dynamic_shifting": false}"#, #"{"_class_name": "QwenImage21Pipeline"}"#))
        XCTAssertThrowsError(try scheduler(#"{"use_dynamic_shifting": false}"#, #"{"sample_sigmas": [1.0, 0.5]}"#))
        XCTAssertNoThrow(try scheduler(#"{"use_dynamic_shifting": false, "shift": 1.0, "shift_terminal": null}"#))
    }

    func testTheNoiseIsTorchRandn() {
        // `torch.randn((1, 1, 64, 2, 3), generator=manual_seed(0))`: 384 values, a multiple of 16.
        var a = [Float](repeating: 0, count: 384)
        var g = TorchNoise(seed: 0)
        a.withUnsafeMutableBufferPointer { g.fill($0.baseAddress!, count: 384) }
        XCTAssertEqual(bits(Array(a.prefix(4))), [0xbf901b85, 0xbf93808a, 0xbe804bd6, 0xbede255e])
        XCTAssertEqual(bits(Array(a.suffix(3))), [0x3f0dda9a, 0xbe3a03d5, 0xbe7019cb])
        // All 384, by their FNV-1a 64 over the little-endian bits: value 42 is one whose cos and sin differ by an ulp
        // between the fused `__sincosf_stret` torch calls and two separate calls, which the seven above do not catch.
        XCTAssertEqual(a[42].bitPattern, 0xbe944f4f)
        let fnv = bits(a).reduce(UInt64(0xcbf2_9ce4_8422_2325)) { h, w in
            (0..<4).reduce(h) { ($0 ^ UInt64((w >> (8 * $1)) & 0xff)) &* 0x100_0000_01b3 }
        }
        XCTAssertEqual(fnv, 0x5bfe_ebab_057d_1cb2)
        // A count that is not a multiple of 16 (never a latent) redraws its last 16 values: `torch.randn(20, seed 42)`,
        // to the bit. Value 14 once missed by an ulp: cos and sin called apart, where torch's compiled path fuses them.
        var b = [Float](repeating: 0, count: 20)
        var h = TorchNoise(seed: 42)
        b.withUnsafeMutableBufferPointer { h.fill($0.baseAddress!, count: 20) }
        let torch: [UInt32] = [0x3ff6a527, 0x3fbe5f54, 0x3f669567, 0xc006c0dd, 0xbf4214e2, 0x3f8a0650, 0x3f4d0143,
                               0x3fd71e93, 0x3eb63341, 0xbf2fc686, 0xbefc9934, 0x3e774894, 0xbe6d2eed, 0x3d2b0c00,
                               0xbe80ce79, 0x3f5c1fb0, 0xbe9e9487, 0xbeca9a91, 0x3f4dac3c, 0xbf1f20e0]
        XCTAssertEqual(bits(b), torch)
        // The product's latent draws it, Qwen-Image-2.1 only.
        XCTAssertEqual(bits(Array(Latent.noise(.qwenImage21, height: 2, width: 3, seed: 0).values)), bits(a))
    }

    func testTheOutputSizeFollowsTheFirstReference() {
        // 1216×832 (the test photo) at ~1024²: 1248×832, the oracle's own condition size at 1024.
        XCTAssertTrue(QwenImage21Pipeline.outputSize(referenceWidth: 1216, referenceHeight: 832) == (1248, 832))
        XCTAssertTrue(QwenImage21Pipeline.outputSize(referenceWidth: 1024, referenceHeight: 1024) == (1024, 1024))
        // An extreme panorama: the short side raised to 512, the area kept under the edit's 1024×1536.
        let wide = QwenImage21Pipeline.outputSize(referenceWidth: 8000, referenceHeight: 1000)
        XCTAssertGreaterThanOrEqual(wide.height, Format.minimumSide)
        XCTAssertLessThanOrEqual(wide.width * wide.height, Format.editSurface)
        XCTAssertEqual(wide.width % 32, 0); XCTAssertEqual(wide.height % 32, 0)
        for (w, h) in [(300, 4000), (4000, 3000), (640, 480), (1, 1000)] {
            let s = QwenImage21Pipeline.outputSize(referenceWidth: w, referenceHeight: h)
            XCTAssertNoThrow(try Format.check(width: s.width, height: s.height), "\(w)×\(h) → \(s)")
        }
    }

    func testRGB8RoundTripsThroughImageRGB() {
        let bytes = (0..<(3 * 7 * 5)).map { (i: Int) -> UInt8 in UInt8((i * 37) % 256) }
        let rgb = Qwen3VLImages.RGB8(bytes: bytes, width: 7, height: 5)
        XCTAssertEqual(QwenImage21Pipeline.rgb8(QwenImage21Pipeline.image(rgb)), rgb)
    }

    func testAFormatThatReadsImagesNeedsAnImageTextModule() {
        XCTAssertTrue(TextFormat.qwenImage21.readsImages)
        XCTAssertFalse(TextFormat.zImage.readsImages)
    }
}
