import Foundation
import Siliconed

// **« Upscale » with SeedVR2 (MLX)**: the quality path next to macOS's « Enlarge » — a diffusion
// model that refines an image 1:1, any scale, no 1920 side. It lives in **its own process**, never
// linked here: the engine behind it (mlx-swift) dies with a `Fatal error` when a memory ceiling is
// crossed — an abort, not a throw — and a helper's death is an error the app reports, not a crash.
// The helper is `Contents/Helpers/seedvr2-upscale`, driven here by a `Process` that reads its
// NDJSON events (`--json`): one `plan` before the first tile, one `tile` per tile, then `done`
// or `error`. The contract — arguments, exit codes, events — is seedvr2-siliconed-upscale-plan.md §3.
//
// The failures that only a parent can heal — the helper aborted (the model grabbed too much), or the
// machine began to swap — shrink the tiles (`tileMP × 0.8`) and try again, twice at most.

/// The SeedVR2 upscaler, driven as a helper process: availability, the weights, the run, the cancel.
@MainActor
enum SeedVR2Upscale {
    /// The weights' directory, until they install into the library (`silicontrol install seedvr2`).
    static let weightsVariable = "SILICONED_SEEDVR2_WEIGHTS"
    /// The helper's path, when developing outside the .app bundle.
    static let helperVariable = "SILICONED_SEEDVR2_HELPER"
    /// The scales the menu offers — the model refines 1:1, so the target is the source × scale.
    static let scales = [2, 4]

    /// `Siliconed.app/Contents/Helpers/seedvr2-upscale`, or the development override.
    static var helperURL: URL {
        if let raw = ProcessInfo.processInfo.environment[helperVariable], !raw.isEmpty {
            return URL(fileURLWithPath: raw)
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/seedvr2-upscale")
    }

    /// The weights: the environment's path while it is set, else the library's
    /// (`<library>/models/seedvr2-3b-int8`).
    static func weightsDirectory(_ library: Library) -> URL? {
        let manager = FileManager.default
        if let raw = ProcessInfo.processInfo.environment[weightsVariable], !raw.isEmpty {
            var directory: ObjCBool = false
            if manager.fileExists(atPath: raw, isDirectory: &directory), directory.boolValue {
                return URL(fileURLWithPath: raw)
            }
        }
        let url = library.root.appendingPathComponent("models/seedvr2-3b-int8")
        var directory: ObjCBool = false
        return manager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue ? url : nil
    }

    /// The helper is in place and the weights are on disk.
    static func available(_ library: Library) -> Bool {
        FileManager.default.isExecutableFile(atPath: helperURL.path) && weightsDirectory(library) != nil
    }

    /// Where the weights go when they install: `<library>/models/seedvr2-3b-int8`, the folder
    /// `weightsDirectory` looks for once the environment says nothing.
    static func installDirectory(_ library: Library) -> URL {
        library.root.appendingPathComponent("models/seedvr2-3b-int8")
    }

    /// **The weights, from Hugging Face**: the helper's `download` verb fills the directory — the
    /// same process boundary, the same HFHub the run reads its weights from, and the same cancel.
    /// A `download` event carries the file and its fraction as they go; a half-downloaded file
    /// never takes its final name, so a failed install leaves nothing to mistake for weights.
    static func download(to directory: URL,
                         onFile: @escaping @MainActor (String) -> Void = { _ in },
                         onFraction: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else { throw Failure.helperMissing }
        let process = Process()
        process.executableURL = helperURL
        // `--ndjson`, not the root's `--json`: the download verb's own flag (the root's would shadow it).
        process.arguments = ["download", directory.path, "--ndjson"]
        // The helper inherits the environment; its stderr is only the framework's usage text.
        let errors = Pipe()
        process.standardError = errors

        let (stream, events) = AsyncStream<Data>.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let stdout = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; events.finish() } else { events.yield(data) }
        }
        process.standardOutput = stdout

        do { try process.run() } catch { throw Failure.failed(error.localizedDescription) }
        current = process
        defer { if current === process { current = nil } }

        var buffer = Data()
        var failure: Failure?
        for await chunk in stream {
            drain(chunk, into: &buffer) { line in
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let type = object["type"] as? String else { return }
                switch type {
                case "download":
                    if let file = object["file"] as? String {
                        onFile(file)
                        onFraction(object["fraction"] as? Double ?? 0)
                    }
                case "error":
                    if let code = object["code"] as? String {
                        failure = Self.failure(code: code, message: object["message"] as? String ?? "")
                    }
                default: break
                }
            }
        }

        process.waitUntilExit()
        let report = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if Task.isCancelled { throw Failure.cancelled }
        if let failure { throw failure }
        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal { throw Failure.crashed(report) }
            throw Failure.failed(report.isEmpty ? String(localized: "The helper exited \(String(process.terminationStatus))") : report)
        }
    }

    // ── What the events carry ──

    /// What the helper derived before its first tile: this Mac's budget, the tiles, the estimate.
    /// The plan is the window's preview — tiles and time are this machine's, not constants.
    struct Plan: Sendable {
        let ramGB: Double
        let budgetGB: Double
        let outWidth: Int, outHeight: Int
        let tileWidth: Int, tileHeight: Int
        let tiles: Int
        let blend: Int
        let peakGB: Double
        let estimate: Double
    }

    /// The finished run: the PNG read back from the helper, its size, and what the tiles took.
    struct Result: Sendable {
        let png: Data
        let width: Int, height: Int
        let seconds: Double
    }

    /// Why the helper did not deliver — the contract's exit codes and error events.
    enum Failure: Error {
        case helperMissing
        case weightsMissing
        case modelTooLarge(String)
        case outputTooLarge(String)
        /// The estimate passed the soft limit and no `--yes` was given (the app decides, the helper only reports).
        case refusedByEstimate(String)
        /// The swap watchdog stopped the run: the machine began to page.
        case swap(String)
        /// The helper died on a signal — the model's allocation crossed a ceiling.
        case crashed(String)
        case failed(String)
        case cancelled

        /// The watchdog's stop and a crash shrink the tiles and try again (`tileMP × 0.8`).
        var isRetryable: Bool {
            switch self {
            case .swap, .crashed: true
            default: false
            }
        }
    }

    // ── The run ──

    /// The helper running now — what `cancel` stops. One upscale at a time (the `busy` gates),
    /// so one slot is enough; `unsafe`: a `Process` held past an await, read by the cancel button.
    private nonisolated(unsafe) static var current: Process?

    /// **Cancel**: `SIGTERM` to the running helper — the GPU queue is reclaimed at once, the
    /// run ends as a cancellation, and the output's `.part` never becomes a file.
    nonisolated static func cancel() {
        guard let process = current, process.isRunning else { return }
        process.interrupt()
        let pid = process.processIdentifier
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            kill(pid, SIGKILL)  // gone already: `kill` says so and does nothing
        }
    }

    /// **One enlargement**: the PNG in, the tiles refined, the PNG out — three attempts at most,
    /// the second and third with the tiles shrunk to `tileMP × 0.8` of the plan's. The target is
    /// `scale` times the source, or the `longSide` given.
    static func run(_ png: Data, weights: URL, scale: Int, longSide: Int = 0, seed: UInt64,
                    onPlan: @escaping @MainActor (Plan) -> Void = { _ in },
                    onTile: @escaping @MainActor (_ index: Int, _ count: Int, _ fraction: Double) -> Void = { _, _, _ in }) async throws -> Result {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else { throw Failure.helperMissing }
        let manager = FileManager.default
        // The helper reads a path and writes a path: two files in the temporary directory, gone
        // when the run ends, whatever its outcome — nothing for Spotlight or recent items.
        let input = manager.temporaryDirectory.appendingPathComponent("upscale-\(UUID().uuidString).png")
        let output = manager.temporaryDirectory.appendingPathComponent("upscale-\(UUID().uuidString).png")
        try png.write(to: input, options: .atomic)
        defer { try? manager.removeItem(at: input); try? manager.removeItem(at: output) }

        var tileMP = 0.0  // 0: the helper derives from the RAM, as the plan says
        var lastPlan: Plan?
        for attempt in 0...2 {
            do {
                return try await once(input: input, output: output, weights: weights, scale: scale, longSide: longSide,
                                      seed: seed, tileMP: tileMP,
                                      onPlan: { lastPlan = $0; onPlan($0) }, onTile: onTile)
            } catch let failure as Failure {
                guard failure.isRetryable, attempt < 2 else { throw failure }
                // The tiles of the plan that failed, four fifths of them — never below the helper's floor.
                let failed = lastPlan.map { Double($0.tileWidth * $0.tileHeight) / 1_000_000 } ?? 2.40
                tileMP = max(0.60, failed * 0.8)
            }
        }
        throw Failure.failed(String(localized: "The upscaling kept failing with smaller tiles"))
    }

    /// **The plan, without the run**: the helper derives, says, and quits before loading the model —
    /// the window's preview, honest numbers from this Mac (`--plan`).
    static func preview(_ png: Data, weights: URL, scale: Int, longSide: Int = 0) async throws -> Plan {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else { throw Failure.helperMissing }
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("upscale-plan-\(UUID().uuidString).png")
        try png.write(to: input, options: .atomic)
        defer { try? FileManager.default.removeItem(at: input) }
        let process = Process()
        process.executableURL = helperURL
        var arguments = ["--weights", weights.path, "--image", input.path, "--plan", "--json"]
        if scale > 0 { arguments += ["--scale", String(scale)] }
        if longSide > 0 { arguments += ["--long-side", String(longSide)] }
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors

        let (stream, events) = AsyncStream<Data>.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let stdout = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; events.finish() } else { events.yield(data) }
        }
        process.standardOutput = stdout
        do { try process.run() } catch { throw Failure.failed(error.localizedDescription) }

        var plan: Plan?
        var failure: Failure?
        var buffer = Data()
        for await chunk in stream {
            drain(chunk, into: &buffer) { line in
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let type = object["type"] as? String else { return }
                if type == "plan" { plan = Self.plan(object) }
                if type == "error", let code = object["code"] as? String {
                    failure = Self.failure(code: code, message: object["message"] as? String ?? "")
                }
            }
        }
        process.waitUntilExit()
        let report = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if let failure { throw failure }
        guard process.terminationStatus == 0 else {
            throw Failure.failed(report.isEmpty ? String(localized: "The helper exited \(String(process.terminationStatus))") : report)
        }
        guard let plan else { throw Failure.failed(String(localized: "The plan never arrived")) }
        return plan
    }

    /// One attempt: launch, read the events as they come, judge the exit.
    private static func once(input: URL, output: URL, weights: URL, scale: Int, longSide: Int, seed: UInt64, tileMP: Double,
                             onPlan: @escaping @MainActor (Plan) -> Void,
                             onTile: @escaping @MainActor (Int, Int, Double) -> Void) async throws -> Result {
        let process = Process()
        process.executableURL = helperURL
        var arguments = ["--weights", weights.path, "--image", input.path, "--output", output.path]
        if longSide > 0 { arguments += ["--long-side", String(longSide)] }
        else { arguments += ["--scale", String(scale)] }
        arguments += ["--seed", String(seed), "--json", "--yes"]
        if tileMP > 0 { arguments += ["--tile-mp", String(format: "%.3f", tileMP)] }
        process.arguments = arguments
        // The helper inherits the environment: `SILICONED_SIMULATED_RAM` reaches it, as it reaches
        // the memory budget. Its stderr is only the framework's usage text; kept for the report.
        let errors = Pipe()
        process.standardError = errors

        let (stream, events) = AsyncStream<Data>.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let stdout = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; events.finish() } else { events.yield(data) }
        }
        process.standardOutput = stdout

        do { try process.run() } catch { throw Failure.failed(error.localizedDescription) }
        current = process
        defer { if current === process { current = nil } }

        // The events, as they come — the plan before the first tile, a tile each time one ends.
        var buffer = Data()
        var failure: Failure?
        var doneWidth = 0, doneHeight = 0
        var doneSeconds = 0.0
        for await chunk in stream {
            drain(chunk, into: &buffer) { line in
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let type = object["type"] as? String else { return }
                switch type {
                case "plan":
                    if let plan = Self.plan(object) { onPlan(plan) }
                case "tile":
                    if let index = object["index"] as? Int, let count = object["count"] as? Int,
                       let fraction = object["fraction"] as? Double { onTile(index, count, fraction) }
                case "done":
                    doneWidth = object["width"] as? Int ?? 0
                    doneHeight = object["height"] as? Int ?? 0
                    doneSeconds = object["seconds"] as? Double ?? 0
                case "error":
                    if let code = object["code"] as? String {
                        failure = Self.failure(code: code, message: object["message"] as? String ?? "")
                    }
                default: break
                }
            }
        }

        process.waitUntilExit()  // the pipe is closed: the helper is gone, this returns at once
        let report = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if Task.isCancelled { throw Failure.cancelled }
        if let failure { throw failure }
        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal { throw Failure.crashed(report) }
            throw Failure.failed(report.isEmpty ? String(localized: "The helper exited \(String(process.terminationStatus))") : report)
        }
        guard doneWidth > 0, let png = try? Data(contentsOf: output) else {
            throw Failure.failed(String(localized: "The upscaled image never arrived"))
        }
        return Result(png: png, width: doneWidth, height: doneHeight, seconds: doneSeconds)
    }

    // ── The events, read ──

    /// Splits a growing buffer into its complete lines, one JSON event each.
    private static func drain(_ chunk: Data, into buffer: inout Data, _ body: (Data) -> Void) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            body(Data(buffer[buffer.startIndex ..< newline]))
            buffer.removeSubrange(buffer.startIndex ... newline)
        }
    }

    private static func plan(_ object: [String: Any]) -> Plan? {
        guard let out = object["out"] as? [Int], out.count == 2,
              let tile = object["tile"] as? [Int], tile.count == 2,
              let tiles = object["tiles"] as? Int else { return nil }
        return Plan(ramGB: object["ram_gb"] as? Double ?? 0,
                    budgetGB: object["budget_gb"] as? Double ?? 0,
                    outWidth: out[0], outHeight: out[1],
                    tileWidth: tile[0], tileHeight: tile[1],
                    tiles: tiles, blend: object["blend"] as? Int ?? 0,
                    peakGB: object["peak_gb"] as? Double ?? 0,
                    estimate: object["estimate_s"] as? Double ?? 0)
    }

    private static func failure(code: String, message: String) -> Failure {
        switch code {
        case "weights_missing": .weightsMissing
        case "model_too_large": .modelTooLarge(message)
        case "output_too_large": .outputTooLarge(message)
        case "estimate": .refusedByEstimate(message)
        case "swap": .swap(message)
        default: .failed(message)
        }
    }
}
