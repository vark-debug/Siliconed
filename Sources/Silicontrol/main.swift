// **`silicontrol` — the app's command-line remote control**, shipped inside `Siliconed.app`
// (`Contents/Helpers/silicontrol`; the app's menu links it into the PATH).
//
// A pipe, and nothing more: it sends its arguments verbatim to the running app — one JSON line,
// `{"argv": […], "cwd": "…"}`, on the socket `<library>/silicontrol.sock` — and copies each JSON line
// it gets back to stdout. Parsing and checks: all in the app (`RemoteControl.swift`), so the
// command cannot say anything the app does not do, and it does not link the engine.
//
// Two things are handled here. `open` launches the app. The help (`help [topic]`, `<command> --help`,
// no argument) is answered without it — reading a manual must not open a window — from the module
// `SilicontrolHelp`, the same pages and the same routing the app answers on its socket. Any other
// command launches the app when it is not running, then waits for its socket (30 s at most).
//
// Exit codes: 0 the last line says `"ok": true` · 1 it says `"ok": false` · 2 usage ·
// 3 the app cannot be reached.

import Foundation
import Measurement
import SilicontrolHelp

let environment = ProcessInfo.processInfo.environment

/// The app's space: `SILICONED_ROOT`, else its own in Application Support. The socket stays there
/// when the library is moved to another disk (`Library.socket`, in `local`).
let library: String = {
    if let root = environment["SILICONED_ROOT"], !root.isEmpty { return root }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appendingPathComponent("Siliconed").path
}()
let socketPath = library + "/silicontrol.sock"

func printJSON(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    print(String(decoding: data, as: UTF8.self))
}

func fail(_ code: String, _ message: String, hint: String? = nil, exit status: Int32 = 3) -> Never {
    var o: [String: Any] = ["ok": false, "error": code, "message": message]
    if let hint { o["hint"] = hint }
    printJSON(o)
    exit(status)
}

func connect() -> Int32? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socketPath.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes); $0[bytes.count] = 0 }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    let r = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard r == 0 else { close(fd); return nil }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    return fd
}

/// Sends `argv`, streams every line received (a `"help"` field prints as raw text), returns the
/// last one. `nil`: nobody answers.
@discardableResult
func send(_ argv: [String], echo: Bool = true) -> [String: Any]? {
    exchange(argv, echo: echo)?.last
}

/// `send`, plus the pid of the app that answered (`measure` samples that process) and a hook on each line.
func exchange(_ argv: [String], echo: Bool, onLine: (([String: Any]) -> Void)? = nil) -> (last: [String: Any]?, peer: pid_t?)? {
    guard let fd = connect() else { return nil }
    defer { close(fd) }
    let peer = Probes.peerPid(of: fd)
    var request = (try? JSONSerialization.data(withJSONObject: ["argv": argv, "cwd": FileManager.default.currentDirectoryPath])) ?? Data()
    request.append(0x0A)
    guard request.withUnsafeBytes({ write(fd, $0.baseAddress!, $0.count) }) == request.count else { return nil }

    var pending = Data(), last: [String: Any]?
    var buffer = [UInt8](repeating: 0, count: 65536)
    func consume(_ line: Data) {
        guard !line.isEmpty else { return }
        let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        if echo {
            if let help = object?["help"] as? String { print(help) } else { print(String(decoding: line, as: UTF8.self)) }
        }
        last = object
        if let object { onLine?(object) }
    }
    while true {
        let n = read(fd, &buffer, buffer.count)
        if n < 0, errno == EINTR { continue }
        guard n > 0 else { break }
        pending.append(contentsOf: buffer[0..<n])
        while let end = pending.firstIndex(of: 0x0A) {
            consume(pending[pending.startIndex..<end])
            pending = Data(pending[pending.index(after: end)...])
        }
    }
    consume(pending)
    return (last, peer)
}

/// The `Siliconed.app` this command lives in (`Siliconed.app/Contents/Helpers/silicontrol`, possibly
/// through a symlink in the PATH) — so it never opens some other, older copy.
func ownBundle() -> String? {
    var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    if !CommandLine.arguments[0].contains("/"), let path = Bundle.main.executablePath {
        url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }
    while url.path != "/" {
        if url.pathExtension == "app" { return url.path }
        url.deleteLastPathComponent()
    }
    return nil
}

/// Launches the app in the background if it does not answer, and waits for its socket.
/// Returns whether it was already running.
@discardableResult
func ensureRunning() -> Bool {
    if let fd = connect() { close(fd); return true }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    var arguments = ["-g"]   // without stealing the foreground
    if let root = environment["SILICONED_ROOT"], !root.isEmpty { arguments += ["--env", "SILICONED_ROOT=\(root)"] }
    arguments += ownBundle().map { [$0] } ?? ["-b", "dev.gwenn-ha.siliconed"]
    open.arguments = arguments
    do { try open.run() } catch { fail("app_not_found", "cannot run /usr/bin/open: \(error)") }
    open.waitUntilExit()
    guard open.terminationStatus == 0 else {
        fail("app_not_found", "could not launch Siliconed.app (open exited with \(open.terminationStatus))")
    }
    for _ in 0..<60 {
        if let fd = connect() { close(fd); return false }
        usleep(500_000)
    }
    // Two causes look alike from here, and neither can be told apart from this side: the open
    // app could not open its socket (its Siliconed menu says why), or the app launched predates the
    // remote control. The message names both rather than guessing.
    fail("app_not_running", "the app does not answer on \(socketPath) after 30 s",
         hint: "if Siliconed is open, its Siliconed menu says why its remote control is off; "
             + "otherwise the Siliconed.app installed may predate the remote control")
}

let argv = Array(CommandLine.arguments.dropFirst())
if let answer = RemoteControlHelp.answer(argv) {
    // Printed as `send` prints the app's answer: a page raw, a refusal as its JSON line.
    if let help = answer["help"] as? String { print(help); exit(0) }
    printJSON(answer)
    exit(2)
}
if argv.first == "open" {
    let already = ensureRunning()
    printJSON(["ok": true, "message": already ? "Siliconed was already open" : "Siliconed open", "socket": socketPath])
    exit(0)
}
if argv.first == "upscale" {
    // `upscale i7 …` goes to the app below; a file path does not need the app at all — the client
    // execs the helper itself (`Contents/Helpers/seedvr2-upscale`), exactly as the window would,
    // and the helper's exit code is the answer (0 ok · 1 failed · 3 weights · 4 too large · 5 refused).
    let second = argv.dropFirst().first ?? ""
    let isImage = second.first == "i" && Int(second.dropFirst()) != nil
    if !isImage { upscaleFile(Array(argv.dropFirst())) }
}

/// `silicontrol upscale FILE [DEST] [--scale N | --long-side N] [--seed N]` — the client's own run,
/// no app, no socket. The helper prints its plan and its tiles as they go; the exit code passes through.
func upscaleFile(_ rest: [String]) -> Never {
    guard let file = rest.first else {
        fail("usage", "upscale <file> [DEST] [--scale N | --long-side N] [--seed N]", hint: "silicontrol help upscale", exit: 2)
    }
    var rest = Array(rest.dropFirst())
    var dest: String?
    if let first = rest.first, !first.hasPrefix("--") { dest = first; rest.removeFirst() }
    var scale = 4, longSide = 0
    var seed: UInt64 = 42
    while let flag = rest.first {
        rest.removeFirst()
        switch flag {
        case "--scale", "--long-side", "--seed":
            guard let value = rest.first, let n = Int(value), n > 0 else {
                fail("usage", "\"\(flag)\" expects a positive integer, not \"\(rest.first ?? "")\"", hint: "silicontrol help upscale", exit: 2)
            }
            rest.removeFirst()
            switch flag {
            case "--scale": scale = n
            case "--long-side": longSide = n
            default: seed = UInt64(n)
            }
        default:
            fail("usage", "unknown option \"\(flag)\"", hint: "silicontrol help upscale", exit: 2)
        }
    }
    guard FileManager.default.fileExists(atPath: file) else {
        fail("no_file", "no file at \(file)", exit: 2)
    }
    // The helper next to this command (possibly through a symlink), or the development override.
    // An environment variable set to the empty string counts as unset.
    let helper = environment["SILICONED_SEEDVR2_HELPER"].flatMap { $0.isEmpty ? nil : $0 }
        ?? ownBundle().map { $0 + "/Contents/Helpers/seedvr2-upscale" }
    guard let helper, FileManager.default.isExecutableFile(atPath: helper) else {
        fail("helper_missing", "the SeedVR2 helper is not in the app bundle", hint: "reinstall Siliconed.app", exit: 3)
    }
    let weights = environment["SILICONED_SEEDVR2_WEIGHTS"].flatMap { $0.isEmpty ? nil : $0 } ?? library + "/models/seedvr2-3b-int8"
    guard FileManager.default.fileExists(atPath: weights) else {
        fail("weights_missing", "the SeedVR2 weights are not at \(weights)", hint: "silicontrol install seedvr2", exit: 3)
    }
    // Never over an existing file: the destination is said, or named after the source.
    let sourceURL = URL(fileURLWithPath: file)
    let output = dest ?? sourceURL.deletingPathExtension().path + ".upscaled.png"
    guard !FileManager.default.fileExists(atPath: output) else {
        fail("exists", "\(output) is already there", hint: "name another DEST", exit: 2)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helper)
    var arguments = ["--weights", weights, "--image", sourceURL.path, "--output", output]
    if longSide > 0 { arguments += ["--long-side", String(longSide)] } else { arguments += ["--scale", String(scale)] }
    arguments += ["--seed", String(seed)]
    process.arguments = arguments
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    do { try process.run() } catch { fail("helper", "cannot run the helper: \(error)", exit: 1) }
    process.waitUntilExit()
    exit(process.terminationStatus)
}

ensureRunning()
if argv.first == "measure" {
    // Client-side, like `open`: the series needs this process's clock and the app's pid, which the app
    // cannot give itself. Its lines (one JSON per render, the verdict last) follow the contract.
    let options: MeasureOptions
    do { options = try MeasureOptions.parse(Array(argv.dropFirst())) }
    catch let failure as MeasureOptions.Failure { fail("usage", failure.message, hint: "silicontrol help measure", exit: 2) }
    catch { fail("usage", "\(error)", exit: 2) }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let path = options.tsv ?? "siliconed-measure-\(formatter.string(from: Date()))-\(options.model)-\(options.size).tsv"
    FileManager.default.createFile(atPath: path, contents: nil)
    guard let file = FileHandle(forWritingAtPath: path) else { fail("write", "cannot write \(path)", exit: 1) }
    // Nothing sleeps while the series runs: a Mac that dozes off between two renders measures the doze.
    let awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "silicontrol measure")
    defer { ProcessInfo.processInfo.endActivity(awake) }
    do {
        var verdict = try Runner.run(options, send: { argv, onLine in
            // The hook is called before `exchange` returns and never kept.
            withoutActuallyEscaping(onLine) { hook in exchange(argv, echo: false, onLine: hook) } ?? (nil, nil)
        }, log: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
        emit: { printJSON($0) }, append: { file.write(Data(($0 + "\n").utf8)) })
        verdict["tsv"] = URL(fileURLWithPath: path).standardizedFileURL.path
        printJSON(verdict)
        exit(0)
    } catch let failure as Failure {
        fail(failure.code, failure.message, hint: "the rows measured so far are in \(path)", exit: 1)
    } catch { fail("render", "\(error)", exit: 1) }
}
guard let last = send(argv) else {
    fail("app_not_running", "the app closed the connection without an answer (\(socketPath))")
}
if last["ok"] as? Bool != true { exit(last["error"] as? String == "usage" ? 2 : 1) }
