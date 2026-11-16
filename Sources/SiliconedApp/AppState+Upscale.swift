import AppKit
import Siliconed

// **« Upscale » with SeedVR2**: a history image refined 1:1 at ×2 or ×4 — the quality path next to
// macOS's « Enlarge » (`Enlarge.swift`), slower by orders of magnitude and bound by nothing the
// system scaler is bound by: no ×4 only, no 1920 side. The helper's gigabytes are its own process's
// (the engine's plan B counts none of them), so the same gates as an enlargement's — one image at a
// time, the queue finished first — keep the GPU jobs apart, and a failure of the helper, however
// violent, is a sentence the app shows, never a crash.
//
// The result goes to the head of the history like an enlargement's: `enlarged` carries the scale
// (the caption's « enlarged ×4 », the curtain's comparison), `enlargedFrom` the PNG it was made from.

/// Why an upscaling did not happen — the remote control's refusal codes.
enum UpscaleFailure: Error {
    /// `upscaleRefusal`'s sentence, or the helper's own (too large, too slow).
    case refused(String)
    case weightsMissing
    case failed(String)
}

extension AppState {
    /// Why « Upscale » cannot take this image now, in a sentence — `nil` when it can.
    func upscaleRefusal(_ entry: Entry, scale: Int = 4) -> String? {
        if mirror != nil { return String(localized: "Upscaling runs on this Mac alone — not in a mirror session") }
        if !SeedVR2Upscale.available(library) { return String(localized: "SeedVR2 is not installed") }
        if entry.grid != nil { return String(localized: "A grid is not upscaled") }
        if entry.enlarged != nil { return String(localized: "This image is already enlarged") }
        if upscaling != nil { return String(localized: "An image is being upscaled") }
        if enlarging != nil { return String(localized: "An image is being enlarged") }
        if busy { return String(localized: "Upscaling waits for the queue to finish") }
        // The output's canvas is what the helper refuses (`canvasLimit`: a twelfth of the RAM, at
        // 16 bytes a pixel): said here, in numbers, rather than discovered at the click.
        let megapixels = Double(entry.width * entry.height) * Double(scale * scale) / 1_000_000
        let limit = 0.12 * Double(ProcessInfo.processInfo.physicalMemory) / 16 / 1_000_000
        if megapixels > limit {
            return String(localized: "Upscaling ×\(String(scale)) makes \(String(Int(megapixels.rounded()))) MP, beyond this Mac’s \(String(Int(limit.rounded()))) MP — try a smaller scale")
        }
        return nil
    }

    /// The button's sentence: what comes out, and how long it takes once learned this session.
    func upscaleHelp(_ entry: Entry) -> String {
        if let refusal = upscaleRefusal(entry) { return refusal }
        let size = "\(entry.width)×\(entry.height) → \(entry.width * 4)×\(entry.height * 4)"
        let megapixels = Double(entry.width * entry.height) / 1_000_000
        if let speed = upscaleSpeed {
            // The learned pace is seconds per output megapixel; ×4 makes sixteen times the pixels.
            return String(localized: "Upscale ×4 with SeedVR2: \(size), about \(Figures.seconds(speed * megapixels * 16)). The original stays.")
        }
        return String(localized: "Upscale ×4 with SeedVR2: \(size). The original stays.")
    }

    /// **« Upscale »** from the app: the helper refines the image at once — the weights are already
    /// on this Mac, nothing is downloaded, nothing is asked. In a mirror session the click is forwarded:
    /// the other Mac refines its own pixels (`MirrorServer`), and the result comes back as any image
    /// of the history — as an enlargement's click does (`Enlarge.swift`).
    func upscale(_ entry: Entry, scale: Int = 4) {
        if let mirror { mirror.send(.upscale(entry.ordinal, scale: scale)); return }
        guard upscaleRefusal(entry, scale: scale) == nil else { return }
        Task {
            do { try await upscaled(entry, scale: scale) }
            catch UpscaleFailure.refused(let sentence) { flash(sentence) }
            catch UpscaleFailure.weightsMissing { flash(String(localized: "The SeedVR2 weights are missing")) }
            catch is CancellationError { }
            catch { flash(String(localized: "This image could not be upscaled")) }
        }
    }

    /// **The upscaling itself**, for the app and `silicontrol upscale`: the helper refines, and the
    /// result goes to the head of the history, shown. The target is `scale` times the source — or
    /// the `longSide` given, which the caption's ×N then reports as it really landed.
    @discardableResult
    func upscaled(_ entry: Entry, scale: Int = 4, longSide: Int = 0, seed: UInt64? = nil) async throws -> Entry {
        let reported = longSide > 0 ? max(1, longSide / max(entry.width, entry.height, 1)) : scale
        if let refusal = upscaleRefusal(entry, scale: reported) { throw UpscaleFailure.refused(refusal) }
        guard let weights = SeedVR2Upscale.weightsDirectory(library) else { throw UpscaleFailure.weightsMissing }
        upscaling = entry.id
        // A render asked meanwhile waited in the queue (`next`): it starts now.
        defer { upscaling = nil; next() }
        let baseSeed = seed ?? entry.seed
        let start = Date()
        var plan: SeedVR2Upscale.Plan?
        let outcome: SeedVR2Upscale.Result
        do {
            outcome = try await SeedVR2Upscale.run(entry.png, weights: weights, scale: scale, longSide: longSide,
                                                   seed: baseSeed, onPlan: { plan = $0 })
        } catch SeedVR2Upscale.Failure.cancelled {
            throw CancellationError()
        } catch let failure as SeedVR2Upscale.Failure {
            switch failure {
            case .helperMissing:
                throw UpscaleFailure.failed(String(localized: "The SeedVR2 helper is missing from the app"))
            case .weightsMissing: throw UpscaleFailure.weightsMissing
            case .modelTooLarge(let message), .outputTooLarge(let message), .refusedByEstimate(let message):
                throw UpscaleFailure.refused(message)
            case .swap(let message), .crashed(let message), .failed(let message):
                throw UpscaleFailure.failed(message)
            case .cancelled:
                throw CancellationError()
            }
        }
        let seconds = Date().timeIntervalSince(start)
        // The learned pace is seconds per output megapixel — the output's own, however it was targeted.
        upscaleSpeed = seconds / max(Double(outcome.width * outcome.height) / 1_000_000, 0.01)
        let finished = try await finishedUpscale(outcome, scale: max(1, outcome.width / max(entry.width, 1)),
                                                 seed: baseSeed, seconds: seconds, parent: entry, plan: plan)
        guard let finished, let made = finished.entry else {
            throw UpscaleFailure.failed(String(localized: "The upscaled image could not be encoded"))
        }
        return made
    }

    /// **The upscale's last mile**, shared by the click and the window: the helper's PNG decoded,
    /// captioned, and — when it comes from a history entry — made into the next entry, shown. A
    /// file with no parent is not a render's child: `nil`, and the window saves it itself.
    func finishedUpscale(_ outcome: SeedVR2Upscale.Result, scale: Int, seed: UInt64, seconds: Double,
                         parent: Entry?, plan: SeedVR2Upscale.Plan?) async throws -> (png: Data, image: CGImage, entry: Entry?)? {
        guard let image = await Entry.decoded(outcome.png).image else {
            throw UpscaleFailure.failed(String(localized: "The upscaled image could not be read"))
        }
        var metadata = parent?.metadata ?? [:]
        metadata["upscaled"] = "\(scale)x seedvr2-3b, from \(outcome.width / scale)x\(outcome.height / scale), seed \(seed)"
        if let plan { metadata["tile"] = "\(plan.tileWidth)x\(plan.tileHeight)/\(plan.blend)" }
        guard let finished = try? await Task.detached(priority: .userInitiated, operation: { [metadata] in
            let png = try PNG.data(image, metadata: metadata)
            return (png, Decoded(FinishedImage.reduce(image, side: 240) ?? image))
        }).value else { return nil }
        guard let parent else { return (finished.0, image, nil) }
        var timings = Engine.Timings()
        timings.total = seconds
        lastImage += 1
        let made = Entry(ordinal: lastImage, job: parent.job, png: finished.0, vignette: finished.1.image ?? image,
                         width: image.width, height: image.height, seed: seed, timings: timings,
                         footprints: Engine.Footprints(), evaluations: 0, settings: parent.settings,
                         metadata: metadata, enlarged: scale, enlargedFrom: parent.png, owner: parent.owner)
        history.insert(made, at: 0)
        saveIfAsked(made)
        selectedImage = (made.id, image)
        selection = made.id
        marked = []; anchor = made.id
        sessionSeconds += seconds
        return (finished.0, image, made)
    }
}
