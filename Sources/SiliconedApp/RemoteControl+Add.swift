// `add` and its argument parsing, single images and XY grids: the command that
// builds a `RenderOrder` from the command line. Split from `RemoteControl.swift`.

import AppKit
import Foundation
import Observation
import Siliconed
import SilicontrolHelp

extension RemoteControl {
    func parse(_ arguments: [String]) throws -> RenderOrder {
        var d = RenderOrder()
        var positional: [String] = []
        var i = 0
        func value(_ flag: String) throws -> String {
            guard i + 1 < arguments.count else { throw Refusal("usage", String(localized: "\(flag) expects a value")) }
            i += 1
            return arguments[i]
        }
        /// `--paste` and its two negative spellings write one value: disagreeing ones are refused
        /// rather than the last one winning.
        func setPaste(_ paste: Bool, _ flag: String) throws {
            if let given = d.pasteGiven, given != paste {
                throw Refusal("usage", String(localized: "\(flag) contradicts the paste switch already given: keep one"),
                              help: "silicontrol help add")
            }
            d.pasteGiven = paste; d.paste = paste
        }
        while i < arguments.count {
            let a = arguments[i]
            switch a {
            case "--model": d.model = try value(a)
            case "--steps":
                let v = try value(a)
                guard let n = Int(v), (1...Request.maximumSteps).contains(n) else {
                    throw Refusal("usage", String(localized: "--steps expects an integer from 1 to \(Request.maximumSteps), not \"\(v)\""))
                }
                d.steps = n
            case "--ref-res":
                let v = try value(a)
                let bounds = QwenImage21Pipeline.minimumReferenceResolution...QwenImage21Pipeline.maximumReferenceResolution
                guard let n = Int(v), bounds ~= n, n % QwenImage21Pipeline.referenceResolutionMultiple == 0 else {
                    throw Refusal("usage", String(localized: "\(a) expects \(bounds.lowerBound) to \(bounds.upperBound), a multiple of \(QwenImage21Pipeline.referenceResolutionMultiple), not \"\(v)\""),
                                  help: String(localized: "--ref-res 1024 (the default) or 1536 — silicontrol help add"))
                }
                d.referenceResolution = n
            case "--detail":
                let v = try value(a)
                guard let level = Detail(rawValue: v.lowercased()) else {
                    throw Refusal("usage", String(localized: "--detail expects normal, more or most, not \"\(v)\""))
                }
                d.detail = level
            case "--solver":
                let v = try value(a)
                guard let rule = Solver(rawValue: v.lowercased()) else {
                    throw Refusal("usage", String(localized: "--solver expects euler, euler-ancestral, dpmpp-2m or unipc, not \"\(v)\""))
                }
                d.solver = rule
            case "--batch":
                let v = try value(a)
                guard let n = Int(v), (1...8).contains(n) else { throw Refusal("usage", String(localized: "--batch expects an integer from 1 to 8, not \"\(v)\"")) }
                d.batch = n
                d.batchGiven = true
            case "--x": d.x = try value(a)
            case "--y": d.y = try value(a)
            case "--lora":
                let v = try value(a)
                var name = v, strength: Double?
                // `name:strength` — the last colon separates the strength (a path has none).
                if let colonIndex = v.lastIndex(of: ":"), let f = Double(v[v.index(after: colonIndex)...].replacingOccurrences(of: ",", with: ".")) {
                    // `Double` reads « nan » and « inf »: a strength that would make every weight NaN.
                    guard f.isFinite else { throw Refusal("usage", String(localized: "--lora expects a finite strength, not \"\(v)\"")) }
                    name = String(v[..<colonIndex]); strength = f
                }
                if let preset = PatchLoRA.preset(named: name) {
                    // The preset's node had its strength: a strength typed here would silently lose it.
                    guard strength == nil else {
                        throw Refusal("lora", String(localized: "a preset's strength is fixed: name it without a strength"),
                                      help: "silicontrol add --lora remove")
                    }
                    d.loras.append((preset.fileName, preset.strength))
                    d.presets.append(preset)
                } else {
                    // A preset's own installed name: kept as the LoRA it is without a mask; `--mask`
                    // reads `presetFiles` and makes it the preset (its branch and pinned strength).
                    if let preset = PatchLoRA.preset(fileNamed: name) {
                        d.presetFiles.append((preset, strength))
                    }
                    d.loras.append((name, strength ?? 1))
                }
            case "--ref": d.references.append(try value(a))
            case "--out": d.folder = try value(a)
            case "--accelerators", "--ane": d.accelerators = true
            case "--no-accelerators", "--no-ane": d.accelerators = false
            case "--preview": d.previews = true
            case "--no-preview": d.previews = false
            case "--wait": d.wait = true
            case "--no-sheet": d.sheet = false
            case "--image": d.image = try value(a)
            case "--mask": d.mask = try value(a)
            case "--expand":
                let v = try value(a)
                let parts = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let factors = parts.compactMap { Double($0) }
                guard parts.count == 4, factors.count == 4, factors.allSatisfy({ $0.isFinite && $0 >= 1 }) else {
                    throw Refusal("usage", String(localized: "--expand expects four multipliers above 1, top,bottom,left,right, not \"\(v)\""),
                                  help: "--expand 1.3,1.4,1.4,1.4 (the workflow’s) — silicontrol help add")
                }
                d.expansion = Patch.Expansion(top: factors[0], bottom: factors[1], left: factors[2], right: factors[3])
            case "--max-side":
                let v = try value(a)
                let bounds = Patch.minimumSide...Patch.maximumSide
                guard let n = Int(v), bounds ~= n else {
                    throw Refusal("usage", String(localized: "\(a) expects \(bounds.lowerBound) to \(bounds.upperBound), not \"\(v)\""),
                                  help: "--max-side 2560 (the workflow’s) — silicontrol help add")
                }
                d.maximumSide = n
            case "--mode":
                let v = try value(a)
                // **`expand` is the 「扩图」 branch**, no `Patch.Mode`: the canvas grows, no mask —
                // refused beside one further down (`patch`), where the contradiction is said.
                if v.lowercased() == PatchLoRA.expand.rawValue {
                    d.expandMode = true
                } else {
                    guard let m = Patch.Mode(rawValue: v.lowercased()) else {
                        throw Refusal("usage", String(localized: "--mode expects remove, redraw or expand, not \"\(v)\""),
                                      help: String(localized: "--mode remove (the default), redraw — or expand, the canvas that grows — silicontrol help add"))
                    }
                    d.mode = m
                }
            case "--pad":
                let v = try value(a)
                // `单位 百分比`: four percents of the image's own sides, left,right,top,bottom —
                // floats included, 0–200 each (`Expand.Pads.range`). All four 0 is not refused here:
                // the honest check is the canvas's plan, where the mask's own emptiness is judged.
                let parts = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let percents = parts.compactMap { Double($0) }
                guard parts.count == 4, percents.count == 4,
                      percents.allSatisfy({ $0.isFinite && Expand.Pads.range.contains($0) }) else {
                    throw Refusal("usage", String(localized: "--pad expects four percents from 0 to 200, left,right,top,bottom, not \"\(v)\""),
                                  help: "--pad 30,30,0,0 (the workflow's) — silicontrol help add")
                }
                d.pads = Expand.Pads(left: percents[0], right: percents[1], top: percents[2], bottom: percents[3])
            case "--max-sample":
                let v = try value(a)
                // `GoohaiUniversalSlider` #27: the sampling long side's ceiling, walked in the
                // slider's steps of 128, from the graph's own floor to its slider's end.
                let bounds = Expand.minimumSampleSide...3840
                guard let n = Int(v), bounds ~= n, n % 128 == 0 else {
                    throw Refusal("usage", String(localized: "\(a) expects \(bounds.lowerBound) to \(bounds.upperBound), a multiple of 128, not \"\(v)\""),
                                  help: "--max-sample 2048 (the workflow's slider) — silicontrol help add")
                }
                d.maximumSample = n
            case "--seeded-start": d.seededStart = true
            case "--paste": try setPaste(true, "--paste")
            case "--no-paste": try setPaste(false, "--no-paste")
            case "--crop-only": try setPaste(false, "--crop-only")
            case "--noise-mask": d.noiseMask = true
            case "--no-noise-mask": d.noiseMask = false
            case "--strength":
                let v = try value(a)
                guard let s = StartImage.strength(v) else {
                    throw Refusal("usage", String(localized: "--strength expects a number above 0 and at most 1 (0.65 or 65%), not \"\(v)\""))
                }
                d.strength = s
            default:
                if a.hasPrefix("--") { throw Refusal("usage", String(localized: "unknown flag: \(a)")) }
                positional.append(a)
            }
            i += 1
        }
        // **The prompt may be left out with a mask or the expand branch**: `add` fills in the remove
        // sentence the form uses (`MaskPrompt.standard`) for a mask; the expand's fixed sentence
        // (`Expand.prompt`) the engine prepends, so an empty supplement is the sentence alone.
        // Without either the prompt is the render.
        if let first = positional.first {
            d.prompt = first
        } else if d.mask != nil || d.expandBranch {
            d.prompt = ""
        } else {
            throw Refusal("usage", String(localized: "the prompt is missing"), help: "silicontrol add [--model id] \"<prompt>\" [512|1024|WxH|P:Q@1K|2K] [seed] — silicontrol help add")
        }
        for p in positional.dropFirst() {
            if d.format == nil, SizeScales.looksLikeScale(p) {
                // `3:4@2K`: the pixels of the rack's two-scale Size (`SizeScales`), whether or not that Beta option is on.
                // The model's own limits are judged below, with `WxH`'s.
                do { let c = try SizeScales.parse(p); d.format = (c.width, c.height) } catch {
                    switch error {
                    case .unknownRatio(let r):
                        throw Refusal("format", String(localized: "no such proportion: \"\(r)\""),
                                      help: String(localized: "proportions: \(SizeScales.ratioList) — silicontrol help add"))
                    case .unknownResolution(let r):
                        throw Refusal("format", String(localized: "no such resolution: \"\(r)\""), help: String(localized: "1K or 2K, e.g. 3:4@2K"))
                    case .unreadable:
                        throw Refusal("format", String(localized: "unreadable size: \"\(p)\""), help: String(localized: "proportion@resolution, e.g. 3:4@2K"))
                    }
                }
            } else if d.format == nil, p.lowercased().contains("x") || p.contains("×") {
                guard let f = Format.parse(p) else { throw Refusal("format", String(localized: "unreadable format: \"\(p)\""), help: String(localized: "width x height, e.g. 832x1216")) }
                d.format = (f.width, f.height)
            } else if d.format == nil, p == "512" || p == "1024" {
                d.format = (Int(p)!, Int(p)!)
            } else if d.seed == nil, let g = UInt64(p) {
                d.seed = g
            } else {
                throw Refusal("usage", String(localized: "extra argument: \"\(p)\""),
                            help: String(localized: "the prompt is ONE argument: put it in quotes — silicontrol help add"))
            }
        }
        // `--seeded-start` seeds a patch's crop: without a mask there is no crop to start from, and
        // the render would start from noise anyway — refused for what it is, not ignored (`Admission`
        // says the same of a request built by the API).
        if d.seededStart, d.mask == nil {
            throw Refusal("usage", String(localized: "--seeded-start goes with --mask: the patch’s crop is the start"))
        }
        // `noise_mask` keeps a patch's mask: without one there is neither mask nor crop, and both
        // switches would be no-ops (`Admission` says the same of a request built by the API).
        if d.noiseMask != nil, d.mask == nil {
            throw Refusal("usage", String(localized: "--noise-mask and --no-noise-mask go with --mask: there is no mask to keep"))
        }
        // `--paste`, `--no-paste` and `--crop-only` lay back or keep a patch's crop: without a mask
        // there is no crop at all, and the switch would be a no-op (`Admission` says the same of a
        // request built by the API).
        if d.pasteGiven != nil, d.mask == nil {
            throw Refusal("usage", String(localized: "--paste, --no-paste and --crop-only go with --mask: there is no crop to paste"))
        }
        // `--mode` picks a patch branch: without a mask there is neither branch to pick.
        if d.mode != nil, d.mask == nil {
            throw Refusal("usage", String(localized: "--mode goes with --mask: the crop is the branch"))
        }
        // **The 「扩图」 branch** (`--mode expand`, or `--lora expand` implying it, as presets imply
        // modes): no mask — the image itself is the region kept, the pads the growth. Refused where
        // the flags were typed, as the mask's own contradictions are.
        if d.expandBranch {
            // The masks of remove/redraw mean replace: the opposite of expand's keep-region —
            // refused, never translated (`Request.expand` refuses a patch the same way).
            if d.mask != nil {
                throw Refusal("patch", String(localized: "--mode expand and --mask don’t go together: the mask’s region is replaced, the expand’s canvas keeps the image"),
                              help: String(localized: "drop --mask: --image is the image the canvas grows from"))
            }
            // **A preset's own installed name is the preset here too**, as under a mask: the branch
            // is the preset's, at the strength the workflow pinned — a strength typed beside it is
            // refused, and left a bare LoRA it would stack twice.
            for named in d.presetFiles {
                guard named.strength == nil else {
                    throw Refusal("lora", String(localized: "a preset's strength is fixed: name it without a strength"),
                                  help: "silicontrol add --lora \(named.preset.rawValue)")
                }
                if !d.presets.contains(named.preset) { d.presets.append(named.preset) }
            }
            if !d.presetFiles.isEmpty {
                d.loras = d.loras.map { entry in
                    guard let preset = PatchLoRA.preset(fileNamed: entry.name) else { return entry }
                    return (preset.fileName, preset.strength)
                }
            }
            // **One branch, once**: the expand preset goes alone — remove and redraw are the mask's.
            if let other = d.presets.first, other != .expand {
                throw Refusal("mode", String(localized: "--mode expand contradicts --lora \(other.rawValue)"),
                              help: String(localized: "leave --lora out: --mode expand wires its preset"))
            }
            guard d.presets.count <= 1 else {
                throw Refusal("mode", String(localized: "--lora expand goes alone: remove and redraw are the mask’s branches"),
                              help: String(localized: "leave --lora out: --mode expand wires its preset"))
            }
            // **One start, one geometry**: the crop's margins, the img2img's strength, the edit's
            // references and a typed format say another path — the canvas decides the format
            // (`Expand.plan`), the expand starts from noise, and its canvas is the edit's only image.
            if d.expansion != nil || d.maximumSide != nil {
                throw Refusal("usage", String(localized: "--expand and --max-side go with --mask: the expand’s pads are --pad"),
                              help: "--pad 30,30,0,0 — silicontrol help add")
            }
            if d.strength != nil {
                throw Refusal("usage", String(localized: "--strength and --mode expand don’t go together: the expand starts from noise"),
                              help: String(localized: "leave out --strength"))
            }
            guard d.references.isEmpty else {
                throw Refusal("usage", String(localized: "--ref and --mode expand don’t go together: the canvas is the edit’s only image"),
                              help: String(localized: "leave out --ref"))
            }
            if d.format != nil {
                throw Refusal("usage", String(localized: "the expand’s canvas decides the format: leave 1024 / WxH out"),
                              help: "--pad 30,30,0,0 — silicontrol help add")
            }
            // The canvas grows from an image: without one there is nothing to expand.
            guard d.image != nil else {
                throw Refusal("usage", String(localized: "--mode expand goes with --image <the image the canvas grows from>"),
                              help: "silicontrol add --image photo.jpg --mode expand — silicontrol help add")
            }
            // **The branch's preset, wired when `--lora` named none** — as `--mode` wires its preset
            // under a mask.
            if d.presets.isEmpty {
                let preset = PatchLoRA.expand
                d.presets.append(preset)
                d.loras.append((preset.fileName, preset.strength))
            }
        }
        // `--pad` and `--max-sample` are the expand's geometry: without the branch they would be
        // no-ops — with a mask, the crop decides its own, said as the patch refusal it is.
        if (d.pads != nil || d.maximumSample != nil), !d.expandBranch {
            if d.mask != nil {
                throw Refusal("patch", String(localized: "--pad and --max-sample go with --mode expand: the mask decides its own crop"),
                              help: String(localized: "drop --mask, or leave --pad out"))
            }
            throw Refusal("usage", String(localized: "--pad and --max-sample go with --mode expand: the canvas’s pads and sampling ceiling"),
                          help: "--pad 30,30,0,0 — silicontrol help add")
        }
        // **The branch, once**: with a mask, `--mode` and the presets named must agree, the two
        // presets exclude each other, and the branch's preset is wired at the workflow's strength
        // when the user named none — no silent overwrite either way. With neither named, the prompt
        // reads its own branch (`PatchBranch`, the GUI's rule); an empty prompt is remove's. The
        // expand preset never reaches here: the branch above refused it beside a mask either way
        // (`patch`), the keep-region being the opposite of a mask's replace-region.
        if d.mask != nil {
            // **A `--lora` naming a preset's own installed LoRA is that preset** — its file name as
            // the header spells it, or a path to it. Left a bare LoRA it would keep the default
            // `remove` branch and stack its remove preset beside the redraw LoRA: the branch is the
            // preset's, at the strength the workflow pinned.
            for named in d.presetFiles {
                guard named.strength == nil else {
                    throw Refusal("lora", String(localized: "a preset's strength is fixed: name it without a strength"),
                                  help: "silicontrol add --lora \(named.preset.rawValue)")
                }
                if !d.presets.contains(named.preset) { d.presets.append(named.preset) }
            }
            if !d.presetFiles.isEmpty {
                d.loras = d.loras.map { entry in
                    guard let preset = PatchLoRA.preset(fileNamed: entry.name) else { return entry }
                    return (preset.fileName, preset.strength)
                }
            }
            if d.presets.count > 1 {
                throw Refusal("mode", String(localized: "--lora remove and --lora redraw are exclusive: name one"),
                              help: String(localized: "leave --lora out: --mode wires its preset"))
            }
            if let explicit = d.mode, let named = d.presets.first, named.mode != explicit {
                throw Refusal("mode", String(localized: "--mode \(explicit.rawValue) contradicts --lora \(named.rawValue)"),
                              help: String(localized: "leave --lora out: --mode wires its preset"))
            }
            let mode = d.mode ?? d.presets.first?.mode ?? PatchBranch.mode(for: d.prompt ?? "")
            d.mode = mode
            if d.presets.first?.mode != mode {
                let preset = PatchLoRA.preset(for: mode)
                d.loras.append((preset.fileName, preset.strength))
            }
        }
        // **The prompt, once the branch is known**: with a mask, remove may leave it out (the `add`
        // below fills `MaskPrompt.standard`); redraw may not — an empty one there would be a sentence
        // about what the marked area becomes, which the program cannot invent. With the expand
        // branch it may too: the engine leads with its fixed sentence. Without either the prompt is
        // the render.
        if d.prompt.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) == true {
            guard d.mask != nil || d.expandBranch else {
                throw Refusal("usage", String(localized: "empty prompt"))
            }
            guard (d.mode ?? .remove) == .remove else {
                throw Refusal("prompt", String(localized: "redraw needs a prompt: say what the marked area becomes"),
                              help: String(localized: "write the sentence the area becomes — or --mode remove, whose prompt the mask fills"))
            }
        }
        return d
    }

    func absolute(_ path: String, _ cwd: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
            .standardizedFileURL.path
    }

    /// `add`, and `grid` (`grid: true`): the same request, checked the same way; a grid queues one
    /// job per cell (`AppState.enqueueGrid`) instead of one per alternative.
    func add(_ arguments: [String], cwd: String, _ c: Connection, grid: Bool = false) throws {
        var d = try parse(arguments)
        // One big job at a time on 16 GB: no render while an installation or an import runs.
        if let reason = app.libraryBlocker { throw Refusal("library_absent", reason, help: String(localized: "connect the disk, then retry")) }
        if let reason = app.installBlocker { throw Refusal("busy", reason, help: String(localized: "retry once the installation is done (silicontrol models)")) }
        if !grid, d.x != nil || d.y != nil || !d.sheet {
            throw Refusal("usage", String(localized: "--x, --y and --no-sheet belong to “silicontrol grid”"), help: "silicontrol help grid")
        }
        if grid, d.x == nil {
            throw Refusal("usage", String(localized: "a grid needs --x (and optionally --y)"), help: "silicontrol help grid")
        }
        if grid, d.batchGiven {
            throw Refusal("usage", String(localized: "a grid’s cell is one image: --batch does not apply"),
                          help: String(localized: "--x seeds=N gives N seeds — silicontrol help grid"))
        }
        if grid, d.referenceResolution != nil {
            throw Refusal("usage", String(localized: "a grid does not take --ref-res yet"),
                          help: String(localized: "leave it out, or render with add — silicontrol help add"))
        }
        let b = app.library
        let model: Model
        do { model = try Model.named(d.model, in: b) } catch {
            let detail = Problem(error).title, readySet = app.visibleReady.map(\.id).joined(separator: ", ")
            throw Refusal("model", String(localized: "model \"\(d.model)\" unavailable: \(detail)"),
                        help: String(localized: "ready: \(readySet) — silicontrol models"))
        }
        let card = b.cards().first { $0.id == model.identifier }
        // A solver other than Euler: the rack's, so More Solvers, and the models in front only.
        if d.solver != .euler {
            guard app.developerMode else {
                throw Refusal("solver", String(localized: "--solver \(d.solver.rawValue) is offered only when More Solvers is on"),
                              help: String(localized: "turn on More Solvers in Settings (⌘,)"))
            }
            guard card.map({ AppState.solverFamilies.contains($0.family) }) == true else {
                throw Refusal("solver", String(localized: "\(card?.name ?? model.name) doesn’t offer the \(d.solver.rawValue) solver"),
                              help: String(localized: "Euler only, or --model z-image"))
            }
        }
        // Detail: not on a model that offers none (Anima, Krea 2) — the rack hides it there.
        if d.detail != .normal, !model.chain.denoising.acceptsDetail {
            throw Refusal("detail", String(localized: "\(card?.name ?? model.name) doesn’t offer Detail"),
                          help: String(localized: "leave out --detail"))
        }
        // The accelerators: only where this Mac's map chooses one (the DiT box greys its switch elsewhere).
        if d.accelerators == true, !app.acceleratorsOffered {
            throw Refusal("accelerators", String(localized: "this Mac’s measure offers no accelerator"),
                          help: String(localized: "leave out --accelerators"))
        }
        // **A mask may leave the prompt out** (`MaskPrompt.standard`, « 移除图像中的绿色区域 »): the marked
        // area is the sentence, and the form fills in the same string. `parse` has refused redraw's
        // empty prompt already — here the remove branch's one is filled, never invented elsewhere.
        // **The expand branch keeps its emptiness**: the engine leads with its own fixed sentence
        // (`Expand.prompt`) and the user's words follow — a remove sentence would say nothing here.
        var prompt = d.prompt ?? ""
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, d.expandBranch != true {
            prompt = MaskPrompt.standard
        }
        // `{a|b}`: one job per expanded prompt, parsed like the app's field — before anything else
        // is read, so that a typo costs nothing.
        let alternatives: PromptAlternatives
        do { alternatives = try PromptAlternatives(prompt) } catch {
            let p = Problem(error)
            throw Refusal("prompt", p.title, help: p.suggestion)
        }

        // **The 「移除」 path** (`--mask`): `--image` is the image to edit, not a start. The mask's crop
        // decides the format, so a typed format, `--strength`, `--ref` and a grid are refused — said,
        // not ignored. The crop's plan is the honest check: a mask of another size or one too empty
        // is refused here, before a job is queued.
        var patchOrigins: (image: ReferenceImage, mask: ReferenceImage)?
        var patchSettings: Patch.Settings?
        if let maskWord = d.mask {
            guard !grid else {
                throw Refusal("patch", String(localized: "grid does not take --mask"),
                              help: String(localized: "render one patch with add — silicontrol help add"))
            }
            guard let imageWord = d.image else {
                throw Refusal("patch", String(localized: "--mask goes with --image <the image to edit>"),
                              help: String(localized: "--image photo.jpg --mask photo-mask.png — silicontrol help add"))
            }
            guard d.strength == nil else {
                throw Refusal("patch", String(localized: "--strength and --mask don’t go together: the patch starts from its crop"),
                              help: String(localized: "leave out --strength"))
            }
            guard d.references.isEmpty else {
                throw Refusal("patch", String(localized: "--ref and --mask don’t go together: the patch’s crop is the edit’s only image"),
                              help: String(localized: "leave out --ref"))
            }
            guard d.format == nil else {
                throw Refusal("format", String(localized: "a mask decides the format: leave 1024 / WxH out"),
                              help: String(localized: "the crop’s size follows the mask — silicontrol help add"))
            }
            guard model.chain.denoising.acceptsSeededStart, model.chain.encoding != nil else {
                let name = card?.name ?? model.name
                throw Refusal("patch", String(localized: "\(name) has no additive start for a mask (--mask)"),
                              help: String(localized: "models that do have \"seeded_start\": true in \"silicontrol models\""))
            }
            let original = try startImage(imageWord, cwd: cwd)
            let mask = try startImage(maskWord, cwd: cwd)
            let expansion = d.expansion ?? Patch.Expansion()
            let maximumSide = d.maximumSide ?? Patch.maximumSide
            let patch = Patch(image: try original.imageRGB(), mask: ImageMask(image: try mask.imageRGB()),
                              expansion: expansion, maximumSide: maximumSide)
            let planned: Patch.Plan
            do { planned = try patch.plan() } catch {
                let p = Problem(error)
                throw Refusal("patch", p.title, help: p.suggestion ?? "silicontrol help add")
            }
            d.format = (planned.width, planned.height)
            patchOrigins = (original, mask)
            patchSettings = Patch.Settings(expansion: expansion, maximumSide: maximumSide,
                                           mode: d.mode ?? .remove, seededStart: d.seededStart,
                                           paste: d.paste, noiseMask: d.noiseMask ?? true)
        }

        // **The 「扩图」 path** (`--mode expand`): `--image` is the image the canvas grows from. The
        // canvas's plan decides the format, as a mask's crop does — and a canvas that cannot render
        // is refused here, before a job is queued, as a mask too empty is: all four pads at 0
        // (`invalid_patch`), a plan whose short side falls under the patch path's floor. The pads
        // and the ceiling the job carries are the resolved ones, defaults applied.
        var expandOrigins: ReferenceImage?
        var expandSettings: ExpandSettings?
        if d.expandBranch {
            guard !grid else {
                throw Refusal("usage", String(localized: "grid does not take --mode expand"),
                              help: String(localized: "render one expand with add — silicontrol help add"))
            }
            guard model.chain.denoising.acceptsSeededStart, model.chain.encoding != nil else {
                let name = card?.name ?? model.name
                throw Refusal("patch", String(localized: "\(name) takes no reference block of the kind the expand’s canvas needs (--mode expand)"),
                              help: String(localized: "models that do have \"seeded_start\": true in \"silicontrol models\""))
            }
            guard let imageWord = d.image else {
                throw Refusal("usage", String(localized: "--mode expand goes with --image <the image the canvas grows from>"),
                              help: "silicontrol add --image photo.jpg --mode expand — silicontrol help add")
            }
            let original = try startImage(imageWord, cwd: cwd)
            let pads = d.pads ?? Expand.Pads()
            let maximumSample = d.maximumSample ?? Expand.defaultMaximumSample
            let expand = Expand(image: try original.imageRGB(), pads: pads, maximumSample: maximumSample)
            let planned: Expand.Plan
            do { planned = try expand.plan() } catch {
                let p = Problem(error)
                throw Refusal("patch", p.title, help: p.suggestion ?? "silicontrol help add")
            }
            d.format = (planned.width, planned.height)
            expandOrigins = original
            expandSettings = ExpandSettings(pads: pads, maximumSample: maximumSample)
        }

        // The starting image (img2img): a model whose chain starts from one, never with references — one or the other.
        var start: ReferenceImage?
        if d.strength != nil, d.image == nil {
            throw Refusal("usage", String(localized: "--strength goes with --image"), help: "silicontrol help add")
        }
        if let word = d.image, d.mask == nil, expandOrigins == nil {
            guard model.chain.entries.contains(where: { $0.kind == .image }) else {
                let name = card?.name ?? model.name
                throw Refusal("img2img", String(localized: "\(name) doesn’t start from an image (--image)"),
                              help: model.chain.denoising.maxReferences > 0
                                  ? String(localized: "--ref <image> to edit it (help edit)")
                                  : String(localized: "models that do have \"start_image\": true in \"silicontrol models\""))
            }
            guard d.references.isEmpty else {
                throw Refusal("usage", String(localized: "--image and --ref don’t go together"), help: "silicontrol help add")
            }
            start = try startImage(word, cwd: cwd)
            if d.format == nil, let start {
                let fitting = (card?.formats ?? ModelCard.recommendedFormats).filter {
                    app.card?.id != model.identifier || app.macNeeded($0, images: 1) == nil
                }
                if let f = StartImage.recommendedFormat(width: start.width, height: start.height, among: fitting, current: app.format) {
                    d.format = (f.width, f.height)
                }
            }
        }

        // The references, in order: files, or images of the history (`i7`). The first is image 1,
        // the one edited: with no format typed, the output takes the denoiser's (`editFormat`) —
        // the app's rule and the CLI's, so that a command and a click give the same image.
        var references: [ReferenceImage] = []
        if !d.references.isEmpty {
            let max = model.chain.denoising.maxReferences
            guard max > 0 else {
                let name = model.name
                throw Refusal("edit", String(localized: "\(name) does no editing by reference (--ref)"),
                            help: String(localized: "models that do have \"edit\": true in \"silicontrol models\""))
            }
            guard d.references.count <= max else {
                let n = d.references.count, name = model.name
                throw Refusal("edit", String(localized: "\(n) references: \(name) reads \(max) at most"),
                            help: String(localized: "\"max_references\" in \"silicontrol models\""))
            }
            references = try d.references.map { r -> ReferenceImage in
                if let entry = image(r), let reference = app.fromHistory(entry) { return reference }
                let url = URL(fileURLWithPath: absolute(r, cwd))
                guard let vignette = NSImage(contentsOf: url), vignette.isValid,
                      let size = ReferenceImage.size(of: url) else {
                    let path = url.path
                    throw Refusal("ref", String(localized: "image unreadable or missing: \(path)"))
                }
                return ReferenceImage(source: .file(url), vignette: vignette, name: url.lastPathComponent,
                                      width: size.width, height: size.height)
            }
            if d.format == nil, let first = references.first {
                let f = model.chain.denoising.editFormat(referenceWidth: first.width, referenceHeight: first.height)
                let capped = AppState.cappedForEditing(RecommendedFormat(f.width, f.height))
                d.format = (capped.width, capped.height)
            }
            // The app edits up to 1024² of area (`AppState.editingSurface`); beyond is the CLI's.
            if let (w, h) = d.format, w * h > AppState.editingSurface {
                throw Refusal("format", String(localized: "the app edits up to 1024² of area, not \(String(w))x\(String(h))"),
                            help: String(localized: "leave the format out (the output follows image 1)"))
            }
        }
        // `--ref-res`: the area the references are encoded at — an edit's parameter, Qwen-Image-2.1's
        // alone (a model with "max_references" > 0). Its value was checked by `parse`.
        if d.referenceResolution != nil, references.isEmpty, d.mask == nil {
            throw Refusal("usage", String(localized: "--ref-res goes with --ref or --mask"), help: "silicontrol add --ref IMAGE --ref-res 1536 …")
        }

        let (width, height) = d.format ?? (1024, 1024)
        // A mask's format is its crop's plan, an expand's its canvas's: those renders alone clear
        // 512 at `Patch.minimumRenderSide`.
        do { try Format.check(width: width, height: height, family: model.card.family,
                              minimumSide: d.mask == nil && expandOrigins == nil ? Format.minimumSide : Patch.minimumRenderSide) } catch {
            let p = Problem(error)
            throw Refusal("format", p.title, help: p.suggestion)
        }
        guard d.loras.count <= AppState.maxLoRA else {
            let n = d.loras.count, max = AppState.maxLoRA
            throw Refusal("lora", String(localized: "\(n) LoRAs: the app stacks \(max) at most"))
        }
        guard app.negativeLoRAStrengths || !d.loras.contains(where: { $0.strength < 0 }) else {
            throw Refusal("lora", String(localized: "negative LoRA strengths are off"),
                          help: String(localized: "turn on Beta → Negative LoRA Strengths in Settings (⌘,)"))
        }
        let stack = try d.loras.map { entry -> LoRASlot in
            // A preset resolves to the workflow's own card: the library may hold its LoRA twice
            // under one `nom`, and a name alone then designates neither.
            let preset = PatchLoRA.allCases.first { $0.fileName == entry.name }
            let name = preset.flatMap { PatchLoRA.card(for: $0, in: b.loras(for: model.identifier)) }?.path
                ?? entry.name
            guard let f = b.lora(name, for: model.identifier) ?? b.lora(absolute(name, cwd), for: model.identifier) else {
                let compatible = b.loras(for: model.identifier).map { Self.shortName($0.path) }
                let name = entry.name, id = model.identifier, list = compatible.joined(separator: ", ")
                throw Refusal("lora", String(localized: "LoRA \"\(name)\" not found for \(id)"),
                            help: compatible.isEmpty ? String(localized: "no LoRA installed for this model")
                                                      : String(localized: "compatible: \(list)"))
            }
            return LoRASlot(path: f.path, strength: entry.strength)
        }
        // The same LoRA twice — a preset and a manual name that resolve to one file, say — would
        // stack two strengths of it: refused, not silently resolved either way.
        let paths = stack.map(\.path)
        if Set(paths).count != paths.count {
            throw Refusal("lora", String(localized: "the same LoRA twice: name it once"),
                          help: String(localized: "leave --lora out: --mode wires its preset"))
        }
        guard grid || app.file.count + alternatives.count <= AppState.maxQueueLength else {
            let max = AppState.maxQueueLength
            if alternatives.count > 1 {
                let n = alternatives.count, room = max - app.file.count
                throw Refusal("queue_full", String(localized: "\(n) jobs for the alternatives: the queue has room for \(room) (\(max) jobs)"),
                            help: "silicontrol wait, then retry")
            }
            throw Refusal("queue_full", String(localized: "the queue is full (\(max) jobs)"),
                        help: "silicontrol wait, then retry")
        }
        var folder: String?
        if let raw = d.folder {
            folder = absolute(raw, cwd)
            try createFolder(folder!)
        }

        let defaultSteps = card?.defaultSteps ?? model.chain.denoising.defaultSteps
        // **A mask or an expand walks the workflow's `ManualSigmas`**: 9 by default, not the Turbo's
        // published 8. An explicit `--steps` is the user's, and the check below still refuses a
        // count without a schedule — never mapped onto another table.
        let requestDefault = d.mask == nil && expandOrigins == nil ? defaultSteps : Patch.defaultSteps
        let steps = d.steps ?? requestDefault
        // A step count the denoiser has no schedule for (Qwen-Image-2.1-Turbo: 8 alone) would
        // fail in the queue: refused here, like everything else an accepted request cannot fail on.
        if (try? model.chain.denoising.check(steps: steps, startImage: false)) == nil {
            let accepted = (1...50).filter { (try? model.chain.denoising.check(steps: $0, startImage: false)) != nil }
                .map(String.init).formatted(.list(type: .or))
            throw Refusal("steps", String(localized: "This model has no schedule for \(String(steps)) steps: \(accepted)."),
                        help: d.mask == nil && expandOrigins == nil ? "--steps \(defaultSteps) (the model's \"default_steps\")"
                                                                    : "--steps \(Patch.defaultSteps) (the workflow's ManualSigmas)")
        }
        let f = model.chain.denoising.space.factor
        let strength = start == nil ? nil : StartImage.snapped(d.strength ?? StartImage.defaultStrength(for: card?.family))
        let first = strength.map { min(steps, Strength.startStep(steps: steps, strength: $0)) } ?? 0
        if strength != nil, first >= steps {
            throw Refusal("img2img", String(localized: "At this strength the image would come back unchanged: raise it."),
                          help: "--strength 0.65")
        }
        let plan = model.chain.denoising.plan(height: height / f, width: width / f, steps: steps, start: first,
                                                 withLoRA: !stack.isEmpty || d.detail != .normal, faster: app.fasterRendering(for: model.identifier))
        // One seed for the whole series, drawn once: the alternatives are compared at the same seeds.
        let firstNumber = d.seed ?? UInt64.random(in: 0...UInt64(UInt32.max))
        if grid {
            if alternatives.variants.contains(where: { app.rewrite($0.prompt, model: model) != nil }) {
                throw Refusal("subject", String(localized: "a grid does not cite named subjects yet"),
                              help: "silicontrol add")
            }
            let format = RecommendedFormat(width, height)
            try addGrid(d, prompt: prompt, model: model, card: card, format: format, steps: steps, stack: stack,
                        references: references, start: start, strength: strength,
                        seed: firstNumber, defaultSteps: defaultSteps, folder: folder, cwd: cwd, c)
            return
        }
        let variants = alternatives.variants
        // A patch reads one image — its crop — so a prompt that cites a subject (whose picture would
        // become a reference) is refused, not silently thinned. The expand's canvas likewise: the
        // edit's only image, so a subject's picture has nowhere to go.
        if patchOrigins != nil {
            for v in variants where app.rewrite(v.prompt, model: model, editImages: 0) != nil {
                throw Refusal("subject", String(localized: "a mask’s prompt does not cite named subjects yet"),
                              help: "silicontrol add")
            }
        }
        if expandOrigins != nil {
            for v in variants where app.rewrite(v.prompt, model: model, editImages: 0) != nil {
                throw Refusal("subject", String(localized: "the expand’s prompt does not cite named subjects yet"),
                              help: "silicontrol add")
            }
        }
        // Named subjects (`Subjects.swift`): each expanded prompt rewritten, its
        // subjects' pictures after the --ref images — refused whole if one expansion is.
        for v in variants {
            if case .failure(let f)? = app.rewrite(v.prompt, model: model, editImages: references.count) {
                let p = Problem(f)
                throw Refusal("subject", p.title, help: p.suggestion ?? "silicontrol subjects")
            }
        }
        let jobs = variants.map { v in
            var settings = RenderSettings(identifier: model.identifier, modelName: card?.name ?? model.name,
                                          prompt: v.prompt, format: RecommendedFormat(width, height), steps: steps,
                                          loras: stack, references: references.count, detail: d.detail,
                                          solver: d.solver)
            settings.strength = strength
            settings.referenceResolution = d.referenceResolution
            settings.patch = patchSettings
            settings.expand = expandSettings
            let used = app.namedJob(v.prompt, settings: &settings, references: references, model: model)
            var job = Job(ordinal: app.nextJobNumber(), settings: settings,
                          seeds: (0..<d.batch).map { firstNumber &+ UInt64($0) },
                          references: used, previews: d.previews ?? app.previews,
                          // Subjects' pictures, a mask's crop or an expand's canvas make the plan
                          // unreduced (as `AppState.expectedPlan`); without them, the plan as it was.
                          defaultSteps: defaultSteps,
                          plan: used.count > references.count || patchOrigins != nil || expandOrigins != nil
                              ? plan.unreduced : plan)
            job.accelerators = d.accelerators
            job.start = start
            job.patch = patchOrigins
            job.expand = expandOrigins
            return job
        }
        app.enqueue(jobs)
        if let on = d.accelerators { app.setAccelerators(on, for: model.identifier) }
        // The form takes what the job computes, as after a click: settings, edit images, seed — and
        // the prompt as typed, so that « Generate » would queue the same series.
        app.restoreSettings(jobs[0].settings)
        app.prompt = prompt
        app.setEditImages(references)
        // The starting image too, or none: « Generate » would queue the same request. A mask's two
        // sources stay with the job queued here: they are no part of the form, and the next click is
        // an ordinary render (`render(…, patch:)`).
        app.setStart(start)
        if let strength { app.startStrength = strength }
        // A seed drawn here is a Random render, as after a click: the rack must not keep showing an old Fixed one.
        if let seed = d.seed { app.fixedSeed = true; app.seed = seed } else { app.fixedSeed = false }

        let added = zip(jobs, variants).map { job, v -> [String: Any] in
            var o = json(job)
            o["position"] = app.currentJob?.ordinal == job.ordinal
                ? 0 : (app.file.firstIndex { $0.ordinal == job.ordinal }.map { $0 + 1 } ?? 0)
            o["estimate_s"] = app.estimation(job).map { Response.number($0, 1) } ?? NSNull()
            if alternatives.hasAlternatives { o["choices"] = v.choices }
            return o
        }
        if d.wait {
            for var o in added { o["type"] = "added"; emit(c, o) }
            followToEnd(jobs.map(\.ordinal), folder: folder, c)
        } else if jobs.count == 1 {
            // One job: the answer of a prompt without alternatives, unchanged.
            var o = added[0]
            o["ok"] = true
            finish(c, o)
        } else {
            let estimates = jobs.map { app.estimation($0) }
            let total: Any = estimates.contains { $0 == nil } ? NSNull()
                : Response.number(estimates.compactMap { $0 }.reduce(0, +), 1)
            finish(c, ["ok": true, "jobs": added, "estimate_s": total])
        }
    }

    // ── subjects ──

    /// **`grid`**: the request `add` checked, its axes read and the grid checked by the library
    /// (`RenderGrid`), every step count of it checked by the denoiser, the queue's room — then one job
    /// per cell, and the sheet when the last one ends.
    private func addGrid(_ d: RenderOrder, prompt: String, model: Model, card: ModelCard?, format: RecommendedFormat,
                         steps: Int, stack: [LoRASlot], references: [ReferenceImage], start: ReferenceImage?, strength: Double?,
                         seed: UInt64,
                         defaultSteps: Int, folder: String?, cwd: String, _ c: Connection) throws {
        let g: RenderGrid
        do {
            let names = d.loras.map(\.name)
            // A LoRA axis names its LoRAs as `--lora` does (a name, else a path from the client's
            // folder): their paths for the cells.
            func resolved(_ a: RenderGrid.Axis) throws(EngineError) -> RenderGrid.Axis {
                guard case let .addedLoRAs(l, f) = a else { return a }
                var paths: [String] = []
                for name in l {
                    if name.isEmpty { paths.append(""); continue }
                    guard let card = app.library.lora(name, for: model.identifier)
                            ?? app.library.lora(absolute(name, cwd), for: model.identifier) else {
                        throw .gridRefused(reason: .noSuchLoRA)
                    }
                    paths.append(card.path)
                }
                return .addedLoRAs(paths, strength: f)
            }
            let x = try resolved(RenderGrid.axis(d.x ?? "", loras: names))
            let y = try d.y.map { try resolved(RenderGrid.axis($0, loras: names)) }
            g = try RenderGrid(.init(prompt: prompt, seed: seed, steps: steps, loraStrengths: stack.map(\.strength),
                                     images: references.count, start: start != nil), x: x, y: y)
            guard !app.refusesNegativeStrength(g) else { throw EngineError.gridRefused(reason: .invalidValue) }
        } catch {
            let p = Problem(error)
            throw Refusal("grid", p.title, help: p.suggestion ?? "silicontrol help grid")
        }
        // A solver axis is the rack's Solver swept, so as `--solver`: More Solvers, and the models in
        // front (a model axis: a cell of a model walking Euler alone renders Euler, as in the app).
        if g.cells.contains(where: { ($0.solver ?? .euler) != .euler }) {
            guard app.developerMode else {
                throw Refusal("solver", String(localized: "a solver axis is offered only when More Solvers is on"),
                              help: String(localized: "turn on More Solvers in Settings (⌘,)"))
            }
            guard g.cells.contains(where: { $0.model != nil }) || card.map({ AppState.solverFamilies.contains($0.family) }) == true else {
                throw Refusal("solver", String(localized: "\(card?.name ?? model.name) walks Euler only"),
                              help: String(localized: "Euler only, or --model z-image"))
            }
        }
        // Each cell's step count against its own model's schedules (a model axis: each model's).
        for cell in g.cells {
            guard let n = cell.steps else { continue }
            let denoising = cell.model.flatMap { try? Model.named($0, in: app.library).chain.denoising } ?? model.chain.denoising
            guard (try? denoising.check(steps: n, startImage: false)) == nil else { continue }
            let accepted = (1...50).filter { (try? denoising.check(steps: $0, startImage: false)) != nil }
                .map(String.init).formatted(.list(type: .or))
            throw Refusal("steps", String(localized: "This model has no schedule for \(String(n)) steps: \(accepted)."))
        }
        guard app.file.count + g.count <= AppState.maxQueueLength else {
            let n = g.count, max = AppState.maxQueueLength, room = max - app.file.count
            throw Refusal("queue_full", String(localized: "\(n) jobs for the grid: the queue has room for \(room) (\(max) jobs)"),
                          help: "silicontrol wait, then retry")
        }
        var settings = RenderSettings(identifier: model.identifier, modelName: card?.name ?? model.name, prompt: prompt,
                                      format: format, steps: steps, loras: stack, references: references.count, detail: d.detail,
                                      solver: d.solver)
        settings.strength = strength
        let (run, jobs) = app.enqueueGrid(g, settings: settings, references: references, previews: d.previews ?? app.previews,
                                          sheet: d.sheet, accelerators: d.accelerators, start: start)
        // The rack's tag of each model the cells render, as after a click.
        if let on = d.accelerators { for id in Set(jobs.map(\.settings.identifier)) { app.setAccelerators(on, for: id) } }
        // The form takes the grid, as after a click: settings, prompt as typed, edit images, and the axes the window brackets
        // (a models, steps, listed seeds or images axis stays silicontrol's).
        app.restoreSettings(settings)
        app.prompt = prompt
        app.setEditImages(references)
        app.setStart(start)
        if let strength { app.startStrength = strength }
        if let s = d.seed { app.fixedSeed = true; app.seed = s } else { app.fixedSeed = false }
        _ = app.setSeries(from: g)
        // …and the canvas shows the grid filling in, as « Generate » shows a series (`renderSeries`).
        app.followsRender = false
        app.showsExploration = true

        let added = jobs.map { job -> [String: Any] in
            var o = json(job)
            o["position"] = app.currentJob?.ordinal == job.ordinal
                ? 0 : (app.file.firstIndex { $0.ordinal == job.ordinal }.map { $0 + 1 } ?? 0)
            o["estimate_s"] = app.estimation(job).map { Response.number($0, 1) } ?? NSNull()
            return o
        }
        if d.wait {
            for var o in added { o["type"] = "added"; emit(c, o) }
            followGrid(run.ordinal, folder: folder, c)
        } else {
            let estimates = jobs.map { app.estimation($0) }
            let total: Any = estimates.contains { $0 == nil } ? NSNull()
                : Response.number(estimates.compactMap { $0 }.reduce(0, +), 1)
            finish(c, ["ok": true, "grid": run.name, "columns": g.columns, "rows": g.rows, "jobs": added,
                       "estimate_s": total])
        }
    }
}

// MARK: - The starting image

extension RemoteControl {
    /// **An image the remote control names as a starting image**: `i7` of the history (its PNG's bytes), or a file — read as
    /// `siliconed-dev render --image` reads it.
    func startImage(_ word: String, cwd: String) throws -> ReferenceImage {
        if let entry = image(word) { return app.startImage(from: entry) }
        let url = URL(fileURLWithPath: absolute(word, cwd))
        guard let vignette = NSImage(contentsOf: url), vignette.isValid, let size = ReferenceImage.size(of: url) else {
            let path = url.path
            throw Refusal("ref", String(localized: "image unreadable or missing: \(path)"))
        }
        return ReferenceImage(source: .file(url), vignette: vignette, name: url.lastPathComponent,
                              width: size.width, height: size.height)
    }

    /// **`start-image`**: the rack's starting image, as the Prompt Lab carries it and the rack's Images box retouches it —
    /// `start-image` alone says what it holds; `start-image IMAGE|i7 [--strength S]` carries one (the size set to the nearest
    /// recommended format, as « Carry to the Rack » does); `--strength S` alone retouches its strength; `--remove` takes it out.
    func startImage(_ action: GestureOrder.StartImageAction, cwd: String) throws -> [String: Any] {
        func refuseWithoutImg2Img() throws {
            guard app.startsFromImage else {
                let name = app.card?.name ?? app.identifier
                throw Refusal("img2img", String(localized: "\(name) doesn’t start from an image"),
                              help: app.editingPossible ? String(localized: "--ref <image> to edit it (help edit)")
                                                        : String(localized: "models that do have \"start_image\": true in \"silicontrol models\""))
            }
        }
        switch action {
        case .status:
            break
        case .carry(let word, let strength):
            try refuseWithoutImg2Img()
            app.carryStart(try startImage(word, cwd: cwd), strength: strength)
        case .strength(let s):
            guard app.startImage != nil else {
                throw Refusal("no_start_image", String(localized: "the rack holds no starting image"),
                              help: "silicontrol start-image <image|i7>")
            }
            app.setStartStrength(s)
        case .remove:
            app.removeStart()
        }
        return ["ok": true, "rack": rackSettings()]
    }

    /// The starting image the rack holds, as the answers say it — `nil` when none.
    func startJSON() -> [String: Any]? {
        guard let s = app.startImage else { return nil }
        var o: [String: Any] = ["name": s.name, "width": s.width, "height": s.height,
                                "strength": Response.number(app.startStrength), "used": app.usedStart != nil]
        if let r = app.startRedraws { o["redrawn_steps"] = r.redrawn; o["of_steps"] = r.of }
        if app.usedStart != nil { o["image_ignored"] = app.startIgnored }
        return o
    }
}
