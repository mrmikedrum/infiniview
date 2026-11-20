# Milestone 2: highlighting speed (November 2026)

Measured on macOS 27.0.1, Apple Silicon, in a sandboxed, ad-hoc signed Quick Look preview extension. The spike is in `spikes/m2/`. The corpus is synthetic: the same generic snippet per language, repeated to 10 KB, 100 KB, 1 MB and 5 MB (`spikes/m2/make-corpus.py`).

## Engine

Grammars run through **vscode-textmate 9.3.2** and **vscode-oniguruma 2.0.1** (both MIT, as published), bundled with esbuild into one 81 KB script and run in JavaScriptCore (`JSContext`). The Oniguruma WASM (473 KB) is instantiated synchronously. Grammars, language definitions and themes come from VS Code 1.147.0's built-in extensions (MIT): 89 grammars and 72 languages, 5.4 MB. The default pair is VS Code's current default themes, "2026 Light" and "2026 Dark", with their `include` chains resolved. `prepare-assets.mjs` does the conversion; nothing is fetched at run time.

## JavaScriptCore needs `com.apple.security.cs.allow-jit`

On macOS 27, `JSContext` runs with JIT off unless the process has the `com.apple.security.cs.allow-jit` entitlement. That holds even for a plain command-line tool with only the linker's ad-hoc signature. Without it, highlighting is 20–30× slower (100 KB of Python: 1.9 s instead of 62 ms). With it, the sandboxed extension runs as fast as Node. The entitlement works with ad-hoc signing and the sandbox, so **the preview extension must carry `allow-jit`**.

## Results (sandboxed extension, JIT on)

Tokenizing the whole file, warm, in milliseconds:

| Language | 10 KB | 100 KB | 1 MB | 5 MB | ≈ throughput |
|---|---|---|---|---|---|
| Python | 6 | 62 | 596 | 2,930 | 1.7 MB/s |
| C | 12 | 111 | 998 | 4,897 | 1.0 MB/s |
| JavaScript | 19 | 110 | 1,070 | 5,279 | 0.95 MB/s |
| TypeScript | 17 | 99 | 989 | 4,688 | 1.0 MB/s |
| Swift | 12 | 97 | 977 | 4,762 | 1.0 MB/s |
| Go | 17 | 102 | 947 | 4,842 | 1.0 MB/s |
| Shell | 16 | 114 | 995 | 4,985 | 1.0 MB/s |
| YAML | 21 | 138 | 1,224 | 5,958 | 0.8 MB/s |
| CSS | 24 | 219 | 2,135 | > 10,000 (cap) | 0.5 MB/s |
| Markdown | 10 | 80 | 734 | 3,446 | 1.4 MB/s |
| JSON (pretty; ~1.9× the label size) | 9 | 59 | 378 | 1,879 | 5 MB/s |
| XML | 6 | 29 | 200 | 895 | 5 MB/s |
| Log | 3 | 39 | 326 | 1,589 | 3 MB/s |

- Setting up the engine (JSContext, script, WASM, theme): **10–11 ms**, once per extension process.
- Loading a grammar: under 6 ms, except Markdown at 44 ms (it embeds many languages).
- Turning tokens into an `NSAttributedString`: about 40 ms per MB.
- Minified JSON (one line of 100 KB or more) skips tokenizing, because lines over 20,000 characters are left plain.

### First paint in a view-based preview

This is the MVP's shape: a TextKit 2 `NSTextView` with the first 300 lines highlighted before the view goes to Quick Look, and the rest highlighted in the background. Times are from the request to the text view's first draw:

| File | First draw | Whole file highlighted (from request, includes a 1 s pause) |
|---|---|---|
| Python 10 KB / 100 KB / 1 MB / 5 MB | 50 / 14 / 17 / 26 ms | 1.1 / 1.1 / 1.7 / 4.4 s |
| Python 10 MB | 27 ms | stopped at the 5 s budget, 8.9 MB in |
| CSS 1 MB | 29 ms | 3.3 s |
| Markdown 1 MB | 94 ms (grammar load) | 1.9 s |
| JSON 9.7 MB | 22 ms | 3.2 s |
| Plain text 1 / 10 / 50 MB | 10 / 15 / 40 ms | — |

The first screen appears within 100 ms in every case, including 50 MB of plain text. Swapping in the fully highlighted text on the main thread took 0.4–0.8 s for 5–10 MB, and would stall scrolling. The extension's memory was about 85 MB showing 10 MB of plain text, 125 MB for 50 MB, and 280 MB while highlighting 5 MB of Python.

## Limits for the MVP

| Limit | Value | Why |
|---|---|---|
| Highlighted before first paint | first **300 lines** | first draw ≤ 100 ms in every measured case |
| Background highlighting | up to **2 MB** of text and a **5 s** budget; the rest stays plain | 2 MB of the slowest grammar (CSS) is about 4 s |
| Applying background highlighting | in chunks of about 2,000 lines on the main thread | the measured 0.4–0.8 s single swap would stall scrolling |
| Longest highlighted line | **20,000 characters** (VS Code's default) | minified files stay fast |
| Text shown | up to **32 MB**; beyond that, the first 32 MB with a "showing X of Y" banner | 50 MB drew in 40 ms at 125 MB of memory; 32 MB leaves headroom |

Above 2 MB the banner also says that highlighting covers only the start of the file.

## Other findings

- `.ts` resolves to `public.mpeg-2-transport-stream` (video) on macOS 27, so TypeScript files with that extension never reach a text preview. That's a system media type, and the spec leaves media to macOS.
