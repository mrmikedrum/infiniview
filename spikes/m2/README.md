# Milestone 2 spike (throwaway)

Measures TextMate highlighting speed in a sandboxed Quick Look extension. Results: [docs/research/milestone-2-highlighting-2026-11.md](../../docs/research/milestone-2-highlighting-2026-11.md).

- `./build.sh <vscode checkout> [jit|nojit|view]` builds the JS bundle and assets, the command-line `build/bench`, and `InfiniviewBench.app` (one extension claiming `public.data`), then installs it to `~/Applications`. The VS Code checkout only needs `extensions/` (a sparse clone of tag 1.147.0).
- `python3 make-corpus.py <dir>` writes the synthetic corpus. The extension variant takes extensionless copies, named like `py-100k`.
- `./run-appex.sh <QLProbe binary> file...` previews each file through the extension (with the milestone 1 probe) and prints the extension's result rows.
