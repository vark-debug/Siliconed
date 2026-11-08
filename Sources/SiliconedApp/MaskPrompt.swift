// **The prompt a masked remove uses when the field is empty** — the workflow's `DF_Text_Box` sentence
// (« 移除图像中的绿色区域 »), in the app's language. The form (`formBlocker`) and `--mask` read this
// one string, so an empty prompt with a mask draws the same sentence in both; the redraw branch never
// takes it: it cannot invent what the marked area becomes.

import Siliconed

/// The remove branch's sentence, and what a blank prompt means for each branch.
enum MaskPrompt {
    static var standard: String {
        String(localized: "Remove the green area from the image.",
               comment: "The prompt a masked remove fills in when the field is empty; the workflow's own sentence")
    }

    /// **What a blank prompt means for the branch**: `nil` when a mask fills it in (the remove branch's
    /// sentence), otherwise the sentence the form shows — no mask to say it, or a redraw, which cannot
    /// invent what the marked area becomes. The form (`formBlocker`) reads this; `add` refuses the same.
    static func blocker(prompt: String, masked: Bool, mode: Patch.Mode) -> String? {
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard masked else { return String(localized: "Write a prompt.") }
        guard mode == .redraw else { return nil }
        return String(localized: "Redraw needs a prompt: say what the marked area becomes.",
                      comment: "The redraw branch cannot fill one in: only the remove branch has a default")
    }
}
