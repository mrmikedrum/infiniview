import Foundation

/// Size limits for the Preview, set from the milestone 2 measurements
/// (docs/research/milestone-2-highlighting-2026-11.md).
public enum PreviewLimits {
    /// Lines highlighted before the Preview first appears.
    public static let syncHighlightLines = 300
    /// Text highlighted in total; the rest stays plain.
    public static let maxHighlightedUTF16 = 2 * 1024 * 1024
    /// Time budget for background highlighting.
    public static let highlightBudgetMillis = 5_000
    /// Longer lines are left plain (VS Code's default).
    public static let maxHighlightedLineLength = 20_000
    /// Bytes of a file shown; beyond this a banner says how much is shown.
    public static let maxShownBytes = 32 * 1024 * 1024
    /// Lines per chunk when applying background highlighting on the main thread.
    public static let applyChunkLines = 2_000
}
