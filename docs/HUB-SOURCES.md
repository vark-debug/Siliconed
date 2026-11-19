# Hub Download Sources Spec

## Why

Every download goes through one door — `Downloader.url`, `https://huggingface.co/<repo>/resolve/<sha>/<path>`
— and huggingface.co is unreachable from mainland China without a VPN. The app's own downloads
(16 recipe repositories across the five families) fail there, whatever the network does for the
rest of the machine; `URLSession.shared` follows the system proxy, but the installer's many
ephemeral sessions (`announcedFootprint`'s, every chunk attempt of a 4 GB file's eight
connections) do not, so even a running VPN at the system level does not always carry them.

Two alternative doors exist, and both were **verified live on 2026-11-19**:

- **hf-mirror.com** — the community mirror of the Hub: the same paths, the same pinned revisions,
  the same `X-Linked-Etag` / `X-Linked-Size` headers. A host swap, nothing else.
- **ModelScope (魔搭, modelscope.cn)** — 15 of the 16 recipe repositories exist there under the
  **same org/name**; resolve URLs answer 200 with the same file paths. Two exceptions found by
  probing: `OpenMOSS-Team` publishes as **`OpenMOSS`** there, and `vanes430/Anima-Turbo-V1.1-GGUF`
  has **no copy** (Anima's Compact and Light DiT — it falls back).

The recipes' integrity does not depend on the door: every weight file is checked against the
sha256 **pinned in the recipe** (`Downloader.expectedSHA`) before a single byte reaches the store.
A source that serves different bytes is refused (`downloadCorrupt`), wherever it lives. That is
what makes a source swap safe: the pin travels with the code, the door is a URL.

**中文**: 所有下载都走 `Downloader.url` 一扇门（huggingface.co），国内无法直连；应用内大量
ephemeral session 不跟随系统代理，挂 VPN 也未必可用。两个替代门都已实测可用：hf-mirror.com
（同路径、同 revision、同响应头，只换 host）和魔搭（16 个 recipe 仓库 15 个同名存在，仅
`OpenMOSS-Team → OpenMOSS` 改名、`vanes430/Anima-Turbo-V1.1-GGUF` 缺失）。所有权重文件都由
recipe 里 pin 的 sha256 校验，与门无关——这是换源安全的根基。

## What Changes

- A **source resolver** in the engine: `automatic` (default — probe, first door that answers),
  `huggingface`, `mirror` (hf-mirror.com), `modelscope` (魔搭). The GUI stores the choice
  (`UserDefaults`); the CLI and a remote mirror's engine take it from the environment
  (`SILICONED_HUB_SOURCE=hf|mirror|modelscope|auto`). One process-wide answer, read by every
  session the installer opens.
- **URL building per source** in `Downloader` (resolve and blob pages), inherited by everything
  that calls it: the installer's files, the writer head's ranges, `RemoteCatalog`'s headers,
  `checkSpace`'s footprints, `HubLink`'s import URLs.
- **A mapping table for ModelScope** in `Installation.swift`: the org rename, the missing
  repository's fallback (modelscope → mirror → HF, tried in that order and remembered), master as
  the revision ModelScope answers to — with the recipe's pinned sha256 untouched.
- **`announcedFootprint` per source**: HF and the mirror answer the `X-Linked-*` headers; ModelScope
  does not. There the footprint comes from the repository's file listing
  (`GET /api/v1/models/<id>/repo/files?Revision=master&Recursive=true` — size and LFS sha256 per
  file), read once per repository per process and kept in a small cache. Without this, the
  chunked downloads (the 64 MB × 8 resumable path) never trigger and the space checks weaken.
- **A picker in the Models sheet** — Automatic / Hugging Face / hf-mirror.com / ModelScope (魔搭)
  — with the door actually in use shown beside it, and the failure guidance in `Problems` extended
  to point at it (six languages).
- License *page* links stay on huggingface.co (the legal text lives there; a mirror's copy is
  offered in the same sheet). The GitHub update check is untouched.

**中文**: 引擎里加一个源解析（自动探测 / HF / hf-mirror / 魔搭），GUI 存 UserDefaults，CLI 与
远程引擎走 `SILICONED_HUB_SOURCE`；`Downloader` 按源拼 URL，安装器、writer head、远程头目录、
空间检查、导入全部自动继承。魔搭需要映射表（org 改名、缺失仓库回退、revision 用 master，
sha256 pin 不变）和按源的 footprint（魔搭走仓库文件列表 API，保住分块续传）。Models sheet 加
下载源选择，报错指引同步更新（六语言）。许可证页面链接保留 HF，GitHub 更新检查不动。

## Impact

- Affected specs: none yet — this page is the spec.
- Affected code:
  - `Sources/Siliconed/Forge/Downloader.swift` — the resolver, the URL builders, the footprint
    per source, the probe.
  - `Sources/Siliconed/Forge/Installation.swift` — the mapping table and the fallback.
  - `Sources/Siliconed/Forge/HubLink.swift` — inherits the resolver (no logic change expected).
  - `Sources/SiliconedApp/ModelsSheet.swift`, `Sources/SiliconedApp/Problems.swift`,
    `Localizable.xcstrings` — the picker and the guidance.
  - Tests in `Tests/SiliconedTests/` — the resolver, the mapping, the ModelScope listing parser,
    the pin checks against a mirror's answers.

## ADDED Requirements

### Requirement: One resolver, every door

The engine SHALL resolve every Hub URL through one source resolver. The resolver SHALL answer one
of `huggingface`, `mirror`, `modelscope` for a given (repository, revision, path), reading the
process-wide setting (`SILICONED_HUB_SOURCE`, else the GUI's stored choice, else `automatic`).
`automatic` SHALL probe the doors in the order **huggingface → modelscope → mirror** — the first
that answers a small request wins, and the answer is remembered for the process (a re-probe MAY
happen once after a network-level interruption).

#### Scenario: A Chinese Mac with no VPN installs Z-Image
- **WHEN** the installer opens its first URL and huggingface.co does not answer but modelscope.cn does
- **THEN** the resolution lands on modelscope, every file of the installation downloads from there,
  and the journal names the door once

#### Scenario: A Mac that reaches the Hub installs as today
- **WHEN** the probe answers huggingface.co first
- **THEN** every URL is built exactly as today — byte for byte the same requests, no behaviour change

#### Scenario: A pinned sha256 disagrees with what a door serves
- **WHEN** a mirror or ModelScope serves bytes whose hash differs from the recipe's pin
- **THEN** the file is refused (`downloadCorrupt`) exactly as on the Hub — the door is never trusted

### Requirement: ModelScope mapping and fallback

The engine SHALL map each recipe repository to its ModelScope identifier through a static table
(`OpenMOSS-Team/MOSS-Image-SFT → OpenMOSS/MOSS-Image-SFT`; every other recipe repository → its own
name). A repository with no ModelScope copy (`vanes430/Anima-Turbo-V1.1-GGUF`) SHALL fall back to
the mirror, then the Hub, in that order. ModelScope revisions SHALL be requested as `master`; the
integrity pin remains the recipe's sha256.

#### Scenario: Anima's Compact installs with the missing GGUF repository
- **WHEN** the source is modelscope and the DiT's repository has no copy there
- **THEN** that file downloads from the mirror at the same pinned revision and sha256, and the
  installation completes

### Requirement: The footprint per source

`announcedFootprint` SHALL keep reading the Hub's headers on HF and the mirror. On ModelScope it
SHALL read the repository's file listing (size and LFS sha256 per path), cached per repository for
the process, so that chunked downloads, resumptions and space checks work as they do on the Hub.

#### Scenario: A 17.5 GB encoder downloads from ModelScope
- **WHEN** the size is known from the listing before the first byte
- **THEN** the file downloads in 64 MB chunks, eight at a time, with its ledger, and a cut resumes
  from its first missing chunk

### Requirement: The source is visible and chosen in the app

The Models sheet SHALL offer the four choices, show which door the process currently uses, and
store the choice in `UserDefaults` (the GUI process sets the resolver at launch and on change).
The CLI and remote engines SHALL take `SILICONED_HUB_SOURCE`; `Problems`' huggingface.co guidance
SHAL name the Models sheet's picker as the first remedy.

#### Scenario: A user switches to ModelScope after a failed install
- **WHEN** the picker changes to 魔搭 and the installation is started again
- **THEN** the already-downloaded, verified files are kept (they are checked by the same pins) and
  only what is missing downloads, from the new door

## Task Breakdown

1. **The resolver** (`Downloader`): `HubSource` enum, the process-wide answer (env → stored →
   automatic), the probe (small request, short timeout, remembered), URL builders per source.
   Pure-function core, so the tests carry no network.
2. **The mapping table and the fallback** (`Installation.swift`): the table, the ModelScope
   identifier per recipe repository, the fallback chain, the revision rule.
3. **The footprint per source**: the ModelScope listing reader and its cache; `expectedSHA` fed
   from it; `checkSpace` and `RemoteCatalog` untouched (they already call the resolver).
4. **The GUI and the guidance**: the Models sheet's picker, the status line, `Problems`' message
   and its six translations; `SILICONED_HUB_SOURCE` read at first use in a fresh process.
5. **Validation**: `swift test` for the pure core (URL building, mapping, fallback, listing
   parser, pin refusal); one live download of a pinned 20 MB file (`OpenMOSS-Team/MOSS-Image-SFT`'s
   tokenizer) **through each of the three doors** (`SILICONED_LIVE_HUB=1 swift test --filter
   HubSourceTests`) — on the Mac it ran on, the Hub could not answer (the feature's own case: a
   clean skip), and the mirror and ModelScope both served bytes the pin accepted; one install with
   the resolver unset to confirm no behaviour change.

## Out of Scope

- A manual proxy setting (host:port on the download sessions) — step 3 of the earlier plan,
  deliberately left out; a system-level VPN with `automatic` covers most of it.
- Mirroring the Hub's import search (`HubLink.fetch`) beyond the URL swap — an import's
  repository is the user's own pick, and any of the three doors answers it.
- The GitHub update check, the license page links, the app's own website.
