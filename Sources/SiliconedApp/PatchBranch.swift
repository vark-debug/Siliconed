// **The branch a masked prompt reads as** (`PatchBranch.mode`): the workflow has two — removing
// something from the marked area, or drawing something else there. The rule is a table of removal
// verbs, not a similarity score: a prompt that asks to remove something is the remove branch
// (`remove the lamp and continue the room` included); a sentence that never says it is redraw — the
// generative branch — because only removal has an explicit vocabulary. An empty prompt is the remove
// branch's, whose sentence the mask fills in (`MaskPrompt.standard`).

import Foundation
import Siliconed

/// **One branch and the LoRA it wires**: decided once (`AppState.patchDecision`), so the tint
/// (`Patch.Settings.mode`) and the stack can never disagree.
struct PatchDecision: Equatable {
    var mode: Patch.Mode
    var preset: PatchLoRA
}

enum PatchBranch {
    /// The remove branch's verbs and phrases, in the languages the workflow's prompts are written in.
    /// A match is a whole word (Latin scripts) or a substring (Chinese and Japanese); the list is
    /// literal — add a verb, not a heuristic.
    static let removals: [String] = [
        // English
        "remove", "removes", "removed", "removing",
        "erase", "erases", "erased", "erasing",
        "delete", "deletes", "deleted", "deleting",
        "take out", "takes out", "took out", "taking out",
        "clean up", "cleans up", "cleaned up", "cleaning up",
        "get rid of", "gets rid of", "got rid of", "getting rid of",
        "wipe out", "wipes out", "wiped out", "wiping out",
        "eliminate", "eliminates", "eliminated", "eliminating",
        // 中文
        "移除", "删除", "去掉", "擦掉", "消除", "去除", "抹掉", "删掉", "清理", "清除",
        // The other five interface languages' common removal verbs.
        "retire", "retirer", "enlève", "enlever", "efface", "effacer", "supprime", "supprimer",
        "entferne", "entfernen", "lösche", "löschen", "beseitige", "beseitigen",
        "elimina", "eliminar", "quita", "quitar", "borra", "borrar",
        "rimuovi", "rimuovere", "cancella", "cancellare",
        "削除", "消去", "取り除く", "除去",
    ]

    /// **The branch a masked prompt reads as**: empty → remove (the mask's own sentence); a
    /// non-negated removal verb anywhere → remove — `remove X and continue Y` and `remove X, then
    /// rebuild Y` still remove; anything else → redraw. Redraw is the uncertain default: a sentence
    /// that does not say *remove* is describing what the area becomes, and only removal has an
    /// explicit vocabulary (`change X into Y`, `make it Y`, `replace X with Y`).
    static func mode(for prompt: String) -> Patch.Mode {
        let text = prompt.lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .remove }
        return asksToRemove(text) ? .remove : .redraw
    }

    private static func asksToRemove(_ text: String) -> Bool {
        for signal in removals {
            var from = text.startIndex
            while let range = text.range(of: signal, range: from..<text.endIndex) {
                if bounded(text, range, signal), !negated(text, before: range.lowerBound) { return true }
                from = text.index(after: range.lowerBound)
            }
        }
        return false
    }

    /// A signal inside a longer word is not it: `remove` in `remover` is not a removal verb.
    private static func bounded(_ text: String, _ range: Range<String.Index>, _ signal: String) -> Bool {
        func asciiLetter(_ character: Character) -> Bool { character.isASCII && character.isLetter }
        if let first = signal.first, asciiLetter(first), range.lowerBound != text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if asciiLetter(before) { return false }
        }
        if let last = signal.last, asciiLetter(last), range.upperBound != text.endIndex {
            let after = text[range.upperBound]
            if asciiLetter(after) { return false }
        }
        return true
    }

    /// **A removal said *not*** is not one: `do not remove the lamp`, `don't erase it`, `without
    /// removing the logo`, `不要删除` read redraw. Only the word right before the verb is read.
    private static func negated(_ text: String, before index: String.Index) -> Bool {
        let prefix = String(text[..<index].suffix(18))
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for marker in ["不要", "不用", "无需", "别", "勿"] where trimmed.hasSuffix(marker) { return true }
        let word = String(trimmed.reversed().prefix { $0.isLetter || $0 == "'" }.reversed()).lowercased()
        return ["not", "no", "never", "without"].contains(word) || word.hasSuffix("n't")
    }
}
