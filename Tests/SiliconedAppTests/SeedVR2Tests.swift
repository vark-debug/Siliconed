// **The helper driver** (`SeedVR2.swift`): the events read as they come, the retries after a crash
// or a swap, the exit codes mapped to failures. No GPU and no weights here: a fake helper — a bash
// script — replays the contract's NDJSON, and `FAKE_MODE` decides how its first call fails.
//
// What they keep:
//
// - a run that replays `plan` / `tile` / `done` delivers the output file's bytes, and the plan and
//   the tiles reach the callbacks;
// - a helper that dies on a signal (the model crossed a ceiling) is retried once with `--tile-mp`
//   and succeeds — two calls, one image;
// - a swap stop (`error: swap`) is retried the same way;
// - a weights refusal (exit 3) is not retried: one call, and the failure is `weightsMissing`.

import Foundation
import Siliconed
import XCTest
@testable import SiliconedApp

@MainActor
final class SeedVR2Tests: XCTestCase {
    private var home: URL!
    private var calls: URL!
    private var weights: URL!

    /// A fake home, the weights folder, and the helper installed: a bash script that appends to
    /// `$FAKE_CALLS` at each call, replays a `plan`, then — `FAKE_MODE` — crashes on a signal, stops
    /// on a swap, or refuses the weights, unless `--tile-mp` was given (the retry's shape).
    private func prepare(_ mode: String) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("SeedVR2Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        weights = home.appendingPathComponent("weights")
        try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
        calls = home.appendingPathComponent("calls")
        let directory: URL = home
        addTeardownBlock {
            unsetenv(SeedVR2Upscale.helperVariable)
            unsetenv("FAKE_CALLS")
            unsetenv("FAKE_MODE")
            try? FileManager.default.removeItem(at: directory)
        }
        let helper = home.appendingPathComponent("fake-upscale")
        let script = """
        #!/bin/bash
        echo x >> "$FAKE_CALLS"
        # `download <dir> --json`: the weights' install — two events, or a network refusal.
        if [ "$1" = "download" ]; then
          case "$FAKE_MODE" in
            download-fail)
              echo '{"type":"error","code":"download_failed","message":"the network is down"}'
              exit 1 ;;
          esac
          echo '{"type":"download","file":"config.json","bytes":100,"total":100,"fraction":1.0}'
          echo '{"type":"download","file":"transformer.safetensors","bytes":50,"total":100,"fraction":0.5}'
          exit 0
        fi
        img=""; out=""; tilemp=""
        prev=""
        for a in "$@"; do
          case "$prev" in
            --image) img="$a";;
            --output) out="$a";;
          esac
          [ "$a" = "--tile-mp" ] && tilemp=1
          prev="$a"
        done
        echo '{"type":"plan","ram_gb":16,"budget_gb":8.59,"out":[32,16],"tile":[16,16],"tiles":1,"blend":64,"peak_gb":8.59,"estimate_s":1.0}'
        case "$FAKE_MODE" in
          crash)
            if [ -z "$tilemp" ]; then kill -SEGV $$; fi ;;
          swap)
            if [ -z "$tilemp" ]; then
              echo '{"type":"error","code":"swap","message":"swap grew 1.2 GB"}'
              exit 1
            fi ;;
          weights)
            echo '{"type":"error","code":"weights_missing","message":"no weights here"}'
            exit 3 ;;
        esac
        echo '{"type":"tile","index":1,"count":1,"x":0,"y":0,"w":16,"h":16,"seconds":0.1,"fraction":1.0}'
        cp "$img" "$out"
        echo '{"type":"done","ok":true,"out":"ignored","width":32,"height":16,"seconds":1.5,"peak_gb":8.0,"swap_gb":0.0}'
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        setenv(SeedVR2Upscale.helperVariable, helper.path, 1)
        setenv("FAKE_CALLS", calls.path, 1)
        setenv("FAKE_MODE", mode, 1)
    }

    private func callCount() -> Int {
        (try? String(contentsOf: calls, encoding: .utf8))?.filter(\.isNewline).count ?? 0
    }

    func testRunReplaysTheContract() async throws {
        try prepare("none")
        let source = Data("the image".utf8)
        var plans = 0, tiles = 0
        let result = try await SeedVR2Upscale.run(source, weights: weights, scale: 2, seed: 1,
                                                  onPlan: { _ in plans += 1 }, onTile: { _, _, _ in tiles += 1 })
        XCTAssertEqual(plans, 1)
        XCTAssertEqual(tiles, 1)
        XCTAssertEqual(result.png, source)  // the fake copies its input to its output
        XCTAssertEqual(result.width, 32)
        XCTAssertEqual(result.height, 16)
        XCTAssertEqual(result.seconds, 1.5, accuracy: 0.001)
    }

    func testCrashIsRetriedWithSmallerTiles() async throws {
        try prepare("crash")
        let result = try await SeedVR2Upscale.run(Data("the image".utf8), weights: weights, scale: 2, seed: 1)
        XCTAssertEqual(callCount(), 2)  // the first call died on a signal, the retry took `--tile-mp`
        XCTAssertEqual(result.width, 32)
    }

    func testSwapIsRetriedWithSmallerTiles() async throws {
        try prepare("swap")
        let result = try await SeedVR2Upscale.run(Data("the image".utf8), weights: weights, scale: 2, seed: 1)
        XCTAssertEqual(callCount(), 2)
        XCTAssertEqual(result.width, 32)
    }

    func testWeightsRefusalIsNotRetried() async throws {
        try prepare("weights")
        do {
            _ = try await SeedVR2Upscale.run(Data("the image".utf8), weights: weights, scale: 2, seed: 1)
            XCTFail("the weights are missing")
        } catch SeedVR2Upscale.Failure.weightsMissing { }
        catch { XCTFail("\(error)") }
        XCTAssertEqual(callCount(), 1)
    }

    func testDownloadReplaysTheEvents() async throws {
        try prepare("none")
        var files: [String] = []
        var fraction = 0.0
        let destination = home.appendingPathComponent("install-here")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await SeedVR2Upscale.download(to: destination,
                                          onFile: { files.append($0) },
                                          onFraction: { fraction = $0 })
        XCTAssertEqual(files, ["config.json", "transformer.safetensors"])
        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }

    func testDownloadFailureIsReported() async throws {
        try prepare("download-fail")
        do {
            _ = try await SeedVR2Upscale.download(to: home.appendingPathComponent("nowhere"))
            XCTFail("the network is down")
        } catch SeedVR2Upscale.Failure.failed(let text) {
            XCTAssertTrue(text.contains("network"), text)
        } catch { XCTFail("\(error)") }
    }

    func testWeightsDirectory() throws {
        try prepare("none")
        let library = Library(root: home)
        // The environment's path wins while it is set.
        let direct = home.appendingPathComponent("direct-weights")
        try FileManager.default.createDirectory(at: direct, withIntermediateDirectories: true)
        setenv(SeedVR2Upscale.weightsVariable, direct.path, 1)
        XCTAssertEqual(SeedVR2Upscale.weightsDirectory(library)?.path, direct.path)
        unsetenv(SeedVR2Upscale.weightsVariable)
        // Without it, the library's own folder is the answer.
        let models = home.appendingPathComponent("models/seedvr2-3b-int8")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        XCTAssertEqual(SeedVR2Upscale.weightsDirectory(library)?.path, models.path)
        // Nothing anywhere: `nil`, and the menu knows why it is greyed.
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("SeedVR2Tests-none-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: elsewhere) }
        XCTAssertNil(SeedVR2Upscale.weightsDirectory(Library(root: elsewhere)))
        XCTAssertFalse(SeedVR2Upscale.available(Library(root: elsewhere)))
    }
}
