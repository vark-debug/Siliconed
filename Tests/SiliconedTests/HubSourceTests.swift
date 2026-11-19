import XCTest

@testable import Siliconed

// **The Hub's doors**: where a file lives on each (`Downloader.url`), ModelScope's own names for
// the recipe repositories, the automatic probe's order, and the pin that judges every door alike.
// Pure, no network — except the live download at the end, behind `SILICONED_LIVE_HUB`.

final class HubSourceTests: XCTestCase {

    /// huggingface.co and hf-mirror.com keep the repository's name and the recipe's pinned
    /// revision; modelscope.cn answers at `master` under the name the mapping gives it — and a
    /// repository with no copy there (`vanes430`'s Anima GGUF) falls back to the mirror, at the
    /// pinned revision.
    func testTheDoorsNameTheFiles() {
        XCTAssertEqual(
            Downloader.url("Tongyi-MAI/Z-Image-Turbo", revision: "f3320", path: "transformer/config.json",
                           source: .huggingface).absoluteString,
            "https://huggingface.co/Tongyi-MAI/Z-Image-Turbo/resolve/f3320/transformer/config.json")
        XCTAssertEqual(
            Downloader.url("Tongyi-MAI/Z-Image-Turbo", revision: "f3320", path: "transformer/config.json",
                           source: .mirror).absoluteString,
            "https://hf-mirror.com/Tongyi-MAI/Z-Image-Turbo/resolve/f3320/transformer/config.json")
        XCTAssertEqual(
            Downloader.url("OpenMOSS-Team/MOSS-Image-SFT", revision: "f972b", path: "transformer/config.json",
                           source: .modelscope).absoluteString,
            "https://modelscope.cn/models/OpenMOSS/MOSS-Image-SFT/resolve/master/transformer/config.json")
        XCTAssertEqual(
            Downloader.url("vanes430/Anima-Turbo-V1.1-GGUF", revision: "efdf0", path: "anima-turbo-v1.1-Q8_0.gguf",
                           source: .modelscope).absoluteString,
            "https://hf-mirror.com/vanes430/Anima-Turbo-V1.1-GGUF/resolve/efdf0/anima-turbo-v1.1-Q8_0.gguf")
    }

    /// The human's page: on the Hub and the mirror the file's own (`blob/`, at the revision); on
    /// ModelScope the repository's — its file view is not a stable URL.
    func testThePagesLeadSomewhereReadable() {
        XCTAssertEqual(
            Downloader.page("Qwen/Qwen-Image-2.1-Turbo", revision: "d65db", path: "LICENSE",
                            source: .huggingface).absoluteString,
            "https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo/blob/d65db/LICENSE")
        XCTAssertEqual(
            Downloader.page("Qwen/Qwen-Image-2.1-Turbo", revision: "d65db", path: "LICENSE",
                            source: .modelscope).absoluteString,
            "https://modelscope.cn/models/Qwen/Qwen-Image-2.1-Turbo")
    }

    /// Every recipe repository is mapped ( fifteen keep their name, the MOSS org renamed), and
    /// nothing else is — an import's own pick falls back to the mirror rather than guessing.
    func testTheMappingCoversTheRecipeRepositories() {
        let recipes = [Installer.zImage.name, Installer.animaBase.name, Installer.anima.name,
                       Installer.krea2Comfy.name, Installer.qwenImage.name, Installer.qwenImage21Turbo.name,
                       Installer.zImageGGUF.name, Installer.zImageSDNQ.name, Installer.qwenImage21Comfy.name,
                       Installer.qwenImage21Unsloth.name, Installer.qwenImage21GGUF.name, Installer.animaGGUF.name,
                       Installer.krea2GGUF.name, Installer.mossImage.name, Installer.mossTurbo.name,
                       Installer.mossComfy.name]
        XCTAssertEqual(recipes.count, 16)
        XCTAssertEqual(Set(recipes.filter { Installer.modelscopeName($0) == nil }), ["vanes430/Anima-Turbo-V1.1-GGUF"])
        XCTAssertEqual(Installer.modelscopeName("OpenMOSS-Team/MOSS-Image-SFT"), "OpenMOSS/MOSS-Image-SFT",
                       "the org publishes under its own, newer name there")
        XCTAssertEqual(recipes.filter { Installer.modelscopeName($0) == $0 }.count, 14)
        XCTAssertNil(Installer.modelscopeName("someone-else/a-checkpoint"))
    }

    /// **Automatic keeps the first door that answers** — the Hub first, so a Mac that reaches it
    /// behaves exactly as today.
    func testAutomaticKeepsTheFirstDoorThatAnswers() {
        XCTAssertEqual(Downloader.firstAnswering { $0 == .huggingface }, .huggingface)
        XCTAssertEqual(Downloader.firstAnswering { $0 != .huggingface }, .modelscope)
        XCTAssertEqual(Downloader.firstAnswering { $0 == .mirror }, .mirror)
        XCTAssertEqual(Downloader.firstAnswering { _ in false }, .huggingface,
                       "none answers: the Hub, and the download's own error will say why")
    }

    /// A named choice names its door without any probe, and a reset re-asks.
    func testTheChoiceNamesItsDoorWithoutProbing() {
        defer { Downloader.setChoice(nil) }
        Downloader.setChoice(.modelscope)
        XCTAssertEqual(Downloader.choice, .modelscope)
        XCTAssertEqual(Downloader.source, .modelscope, "named: the door, no probe")
        XCTAssertEqual(Downloader.resolvedDoor, .modelscope)
        Downloader.setChoice(nil)
        XCTAssertEqual(Downloader.choice, .automatic)
        XCTAssertNil(Downloader.resolvedDoor, "a reset re-asks the doors at the next download")
    }

    /// The listing's parse: one entry per blob, the LFS object's sha256 lowercased (the same value
    /// the recipe pins), trees and non-LFS files name no object.
    func testTheModelScopeListingIsParsedByPath() throws {
        let fixture = """
        {"Code":200,"Data":{"Files":[
            {"Type":"tree","Path":"tokenizer","Size":0,"Sha256":""},
            {"Type":"blob","Path":"vae/diffusion_pytorch_model.safetensors","Size":167666902,
             "Sha256":"F5B59A26851551B67AE1FE58D32E76486E1E812DEF4696A4BEA97F16604D40A3"}]}}
        """
        let listing = try Downloader.modelscopeListing(from: Data(fixture.utf8))
        XCTAssertEqual(listing["vae/diffusion_pytorch_model.safetensors"]?.size, 167666902)
        XCTAssertEqual(listing["vae/diffusion_pytorch_model.safetensors"]?.sha256,
                       "f5b59a26851551b67ae1fe58d32e76486e1e812def4696a4bea97f16604d40a3")
        XCTAssertNil(listing["tokenizer"]?.sha256)
    }

    /// **A door is never trusted**: a pin disagrees with what it announces — refused before the
    /// first byte, whichever door announced it.
    func testAPinRefusesAnotherAnnouncement() {
        XCTAssertThrowsError(try Downloader.expectedSHA(path: "x.safetensors", pinned: "aa", announced: "bb",
                                                        status: 200, file: "x"))
        XCTAssertEqual(try Downloader.expectedSHA(path: "x.safetensors", pinned: "aa", announced: nil,
                                                  status: 200, file: "x"), "aa",
                       "a door that announces nothing is checked against the pin alone")
    }

    /// **Live, one small file through each door** (`SILICONED_LIVE_HUB=1`): the MOSS tokenizer
    /// (20 MB, pinned), downloaded from the Hub, the mirror and ModelScope — each door to a
    /// destination of its own, so no door inherits another's file as a "resumed" one. A door this
    /// machine cannot reach (huggingface.co from the mainland — the very case the doors are for)
    /// is a skip, printed; the doors of this side of the wall — mirror and ModelScope — **must**
    /// serve the pinned bytes.
    func testTheDoorsServeTheSameObject() throws {
        guard ProcessInfo.processInfo.environment["SILICONED_LIVE_HUB"] != nil else {
            throw XCTSkip("live: set SILICONED_LIVE_HUB=1")
        }
        let pin = "06b9509352d2af50381ab2247e083b80d32d5c0aba91c272ca9ff729b6a0e523"
        let journal: @Sendable (String) -> Void = { print($0) }
        var verified: Set<HubSource> = []
        for door: HubSource in [.huggingface, .mirror, .modelscope] {
            let path = NSTemporaryDirectory() + "hub-live-\(door.rawValue)-tokenizer.json"
            defer { try? FileManager.default.removeItem(atPath: path) }
            try? FileManager.default.removeItem(atPath: path)
            try Downloader.setChoice(HubChoice(rawValue: door.rawValue))
            do {
                try Downloader.download("OpenMOSS-Team/MOSS-Image-SFT", revision: Installer.mossImage.revision,
                                        path: "tokenizer/tokenizer.json", to: path, journal: journal)
                XCTAssertEqual(try Downloader.sha256(path), pin, "\(door.rawValue) serves the pinned bytes")
                verified.insert(door)
            } catch {
                print("live: \(door.rawValue) could not serve: \(error)")
                XCTAssertFalse(door == .mirror || door == .modelscope,
                               "the doors of this side of the wall must serve: \(door.rawValue)")
            }
        }
        Downloader.setChoice(nil)
        XCTAssertTrue(verified.contains(.modelscope) || verified.contains(.mirror),
                      "at least one door on this side of the wall served the pinned bytes: \(verified)")
    }
}
