import AppKit
import Siliconed
import SwiftUI
import UniformTypeIdentifiers

// **The Upscale window**: SeedVR2 in its own room. Drop a picture, or take the last render, then
// pick ×2 / ×4 or a long side — and read the **plan** before anything runs: the tiles and the
// estimate are this Mac's own (`--plan`), which is what a 16 GB Mac needs to see before it commits
// to an 8K. Past ten minutes, the button asks. While it runs, the tiles and their fraction, and a
// cancel stops the helper at once. A result with a parent goes to the head of the history; a
// dropped file is nobody's child — the window asks where to save it.

/// The window's state: a source, a target, the plan, the run.
@MainActor @Observable
final class UpscaleModel {
    /// The history entry the window was opened for, if any — its seed, job, and settings the result inherits.
    private(set) var parent: Entry?
    private(set) var source: CGImage?
    private(set) var sourcePNG: Data?
    private(set) var sourceName = ""
    /// ×2 / ×4 — ignored when a long side is given.
    var scale = 4
    /// A long side in pixels, as text; empty when the target is the scale instead.
    var longSide = ""
    private(set) var plan: SeedVR2Upscale.Plan?
    private(set) var planError: String?
    private(set) var planning = false
    private(set) var running = false
    private(set) var tileIndex = 0
    private(set) var tileCount = 0
    private(set) var fraction = 0.0
    private(set) var message: String?
    /// The weights coming from Hugging Face: the file in flight and its fraction.
    private(set) var installing = false
    private(set) var installFile = ""
    private(set) var installFraction = 0.0

    private weak var app: AppState?
    private var planTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?

    /// Why the plan looks the way it does: the source and the target change it.
    var planKey: String { "\(sourcePNG?.hashValue ?? 0) \(scale) \(longSide)" }
    var targetLongSide: Int { Int(longSide) ?? 0 }
    var targetScale: Int { targetLongSide > 0 ? 0 : scale }
    /// The weights are on disk — or the environment points at them.
    var installed: Bool {
        guard let app else { return false }
        return SeedVR2Upscale.weightsDirectory(app.library) != nil
    }

    func attach(_ app: AppState) { self.app = app }

    /// A picture in: dropped, chosen, or from the history. While a run holds the window, no.
    func load(_ png: Data, named name: String, parent: Entry?) {
        guard !running else { return }
        self.parent = parent
        sourcePNG = png
        sourceName = name
        source = nil
        plan = nil
        message = nil
        Task {
            let decoded = await Entry.decoded(png)
            source = decoded.image
        }
    }

    func load(entry: Entry) {
        load(entry.png, named: String(localized: "image i\(String(entry.ordinal))"), parent: entry)
    }

    /// The plan, honestly: the helper derives from this Mac's RAM and quits before the model loads.
    func replan() {
        planTask?.cancel()
        guard let app, let png = sourcePNG, !running,
              let weights = SeedVR2Upscale.weightsDirectory(app.library) else { return }
        planning = true
        planError = nil
        planTask = Task {
            defer { planning = false }
            do {
                plan = try await SeedVR2Upscale.preview(png, weights: weights, scale: targetScale, longSide: targetLongSide)
            } catch is CancellationError {
            } catch {
                plan = nil
                planError = UpscaleModel.sentence(for: error)
            }
        }
    }

    /// **The run**: the helper refines tile by tile; the fraction and the tiles arrive as they go.
    func start() {
        guard !running, let app, let png = sourcePNG,
              let weights = SeedVR2Upscale.weightsDirectory(app.library) else { return }
        running = true
        message = nil
        fraction = 0
        tileIndex = 0
        tileCount = plan?.tiles ?? 0
        let scale = targetScale
        let longSide = targetLongSide
        let seed = parent?.seed ?? 42
        let parent = parent
        let start = Date()
        runTask = Task {
            defer { running = false }
            do {
                var lastPlan: SeedVR2Upscale.Plan?
                let outcome = try await SeedVR2Upscale.run(png, weights: weights, scale: scale, longSide: longSide, seed: seed,
                                                           onPlan: { lastPlan = $0; self.tileCount = $0.tiles },
                                                           onTile: { index, count, step in
                                                               self.tileIndex = index; self.tileCount = count; self.fraction = step
                                                           })
                let seconds = Date().timeIntervalSince(start)
                app.upscaleSpeed = seconds / max(Double(outcome.width * outcome.height) / 1_000_000, 0.01)
                // The caption's ×N is the one the result really got (a long side rarely lands on ×2 or ×4).
                let enlarged = source.map { max(1, outcome.width / max($0.width, 1)) } ?? max(1, scale)
                let made = try await app.finishedUpscale(outcome, scale: enlarged, seed: seed, seconds: seconds,
                                                         parent: parent, plan: lastPlan)
                guard let made else { throw UpscaleFailure.failed(String(localized: "The upscaled image could not be encoded")) }
                if made.entry != nil {
                    message = String(localized: "The upscaled image is at the head of the history")
                } else {
                    save(made.png, named: sourceName)
                }
            } catch is CancellationError {
            } catch {
                message = UpscaleModel.sentence(for: error)
            }
        }
    }

    /// **The weights, from Hugging Face** (about 4.4 GB): the helper downloads into the library, the
    /// file and its fraction arrive as they go, and the plan comes back when the last byte lands.
    func install() {
        guard let app, !installing, !running, !app.seedvr2Downloading else { return }
        installing = true
        installFraction = 0
        installFile = ""
        message = nil
        app.seedvr2Downloading = true
        let destination = SeedVR2Upscale.installDirectory(app.library)
        installTask = Task {
            defer { installing = false; app.seedvr2Downloading = false }
            do {
                try await SeedVR2Upscale.download(to: destination,
                                                  onFile: { self.installFile = $0 },
                                                  onFraction: { self.installFraction = $0 })
                message = String(localized: "The SeedVR2 weights are installed")
                replan()
            } catch is CancellationError {
            } catch {
                message = UpscaleModel.sentence(for: error)
            }
        }
    }

    /// **Stop**: the helper gets its `SIGTERM`, the run or the download ends as a cancellation.
    func stop() {
        runTask?.cancel()
        installTask?.cancel()
        SeedVR2Upscale.cancel()
    }

    /// A file's result has no history to go home to: a save panel is its home.
    private func save(_ png: Data, named name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name.isEmpty ? "upscaled.png" : name
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try png.write(to: url, options: .atomic) }
            catch { Task { @MainActor in self.message = String(localized: "The upscaled image could not be saved") } }
        }
    }

    /// The failure, in a sentence the window can show.
    static func sentence(for error: Error) -> String {
        switch error as? SeedVR2Upscale.Failure {
        case .helperMissing: String(localized: "The SeedVR2 helper is missing from the app")
        case .weightsMissing: String(localized: "The SeedVR2 weights are not installed")
        case .modelTooLarge: String(localized: "This image is too large for this Mac's memory")
        case .outputTooLarge: String(localized: "The target size is beyond what this Mac can hold — try a smaller scale")
        case .refusedByEstimate: String(localized: "This run would take too long")
        case .swap: String(localized: "The Mac began to swap — the run was stopped")
        case .crashed: String(localized: "The upscaler ran out of memory — the tiles were made smaller, twice, and it still failed")
        case .failed(let text): text.isEmpty ? String(localized: "This image could not be upscaled") : text
        default: String(localized: "This image could not be upscaled")
        }
    }
}

/// The window's body: the source, the target, the plan, the run.
struct UpscalePanel: View {
    let app: AppState
    @Bindable var model: UpscaleModel
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                preview
                VStack(alignment: .leading, spacing: 8) {
                    if model.sourcePNG != nil {
                        Text(verbatim: source)
                            .font(.headline)
                        HStack(spacing: 10) {
                            Picker(String(localized: "Scale"), selection: $model.scale) {
                                Text(verbatim: "×2").tag(2)
                                Text(verbatim: "×4").tag(4)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 92)
                            .disabled(model.running)
                            HStack(spacing: 4) {
                                Text(String(localized: "Long side"))
                                TextField(String(localized: "none"), text: $model.longSide)
                                    .frame(width: 52)
                                    .disabled(model.running)
                                Text(String(localized: "px"))
                            }
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(String(localized: "Drop a picture here, or choose one"))
                            .foregroundStyle(.secondary)
                    }
                    planView
                }
            }
            if !model.installed {
                installView
            }
            if model.running {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: model.fraction)
                    HStack {
                        Text(String(localized: "Tile \(String(model.tileIndex)) of \(String(model.tileCount))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Cancel")) { model.stop() }
                    }
                }
            } else if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(String(localized: "Choose Image…")) { choose() }
                    .disabled(model.running)
                if let last = app.history.first {
                    Button(String(localized: "Last Image")) { model.load(entry: last) }
                        .disabled(model.running)
                }
                Spacer()
                Button(String(localized: "Upscale")) {
                    // Past the soft limit, the button asks — the plan said this would take a while.
                    if let estimate = model.plan?.estimate, estimate > 600 {
                        confirming = true
                    } else {
                        model.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.sourcePNG == nil || model.running || model.planError != nil || !model.installed)
            }
        }
        .padding(18)
        .frame(width: 540, alignment: .leading)
        .onDrop(of: [UTType.image], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            let name = provider.suggestedName ?? ""
            _ = provider.loadDataRepresentation(for: UTType.image) { data, _ in
                guard let data else { return }
                Task { @MainActor in model.load(data, named: name, parent: nil) }
            }
            return true
        }
        .confirmationDialog(String(localized: "This run will take a while"), isPresented: $confirming, titleVisibility: .visible) {
            Button(String(localized: "Continue, about \(Figures.seconds(model.plan?.estimate ?? 0))")) { model.start() }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "SeedVR2 will refine every tile of this image — close the window to stop it."))
        }
        .task(id: model.planKey) { model.replan() }
    }

    private var source: String {
        let image = model.source
        var line = "\(image?.width ?? 0)×\(image?.height ?? 0)"
        if !model.sourceName.isEmpty { line += " · " + model.sourceName }
        return line
    }

    @ViewBuilder
    private var preview: some View {
        if let image = model.source {
            Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 140, maxHeight: 140)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.4))
                .frame(width: 140, height: 105)
        }
    }

    @ViewBuilder
    private var planView: some View {
        if model.planning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Deriving the tiling plan…")).font(.caption).foregroundStyle(.secondary)
            }
        } else if let error = model.planError {
            Text(error).font(.caption).foregroundStyle(.secondary)
        } else if let plan = model.plan {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: String(localized: "\(String(plan.outWidth))×\(String(plan.outHeight)), \(String(plan.tiles)) tiles of \(String(plan.tileWidth))×\(String(plan.tileHeight)), about \(Figures.seconds(plan.estimate))"))
                    .font(.caption)
                Text(verbatim: String(localized: "Budget \(String(format: "%.1f", plan.budgetGB)) GB · peak about \(String(format: "%.1f", plan.peakGB)) GB of \(String(format: "%.0f", plan.ramGB)) GB of RAM"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The weights are not here yet: the download, or the button that starts it — nothing runs
    /// into the library while the helper is not in place (`SeedVR2Upscale.available` says which).
    @ViewBuilder
    private var installView: some View {
        if model.installing {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: model.installFraction)
                HStack {
                    Text(String(localized: "Downloading SeedVR2 (about 4.4 GB)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.installFile.isEmpty {
                        Text(verbatim: model.installFile)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(String(localized: "Cancel")) { model.stop() }
                }
            }
        } else {
            HStack {
                Text(String(localized: "The SeedVR2 weights are not installed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Install SeedVR2 (about 4.4 GB)")) { model.install() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            model.load(data, named: url.lastPathComponent, parent: nil)
        }
    }
}

/// **The window itself** — one, shared, remembered where it stood; closing it stops a running upscaling.
@MainActor
final class UpscaleWindow: NSObject, NSWindowDelegate {
    static let shared = UpscaleWindow()
    private var window: NSWindow?
    private let model = UpscaleModel()

    /// Opens the window, loaded with the entry when one was offered (the menu's, the context's).
    func show(_ app: AppState, entry: Entry?) {
        model.attach(app)
        if let entry { model.load(entry: entry) }
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 340),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Upscale")
        window.contentView = NSHostingView(rootView: UpscalePanel(app: app, model: model))
        // The window is kept and shown again (`shared.window`): AppKit must not release it on close —
        // the default would free it behind the reference, and the second show would hit a dead window.
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setFrameAutosaveName("Upscale")
        window.center()
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
    }
}
