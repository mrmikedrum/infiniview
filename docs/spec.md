# Infiniview: specification (v1)

Infiniview makes Quick Look show the contents of every human-readable file in Finder, whatever its extension or lack of one, so Finder never falls back to a Generic Icon. Terms in **bold** are defined in [GLOSSARY.md](../GLOSSARY.md). Platform facts behind these decisions are in [docs/research/quicklook-platform-2026-11.md](research/quicklook-platform-2026-11.md).

## Goals

1. Any **Text File** shows its text in the **Preview**: extensionless files, dotfiles, scripts, and files with extensions macOS has never heard of.
2. Anything else that reaches Infiniview shows a **Fallback Card**, never a blank or a Generic Icon.
3. It keeps working across macOS upgrades: documented mechanisms only, with each fragile spot named and its fallback stated.

## Non-goals (v1)

- **Thumbnails.** Finder keeps its standard icons in file lists. A Thumbnail extension may come later.
- Rendering documents (HTML as a web page, Markdown as formatted output). Infiniview shows source.
- Previews for media or other types macOS already handles well.
- Watching folders for new files, or searching the disk, to learn extensions (see [ADR-0005](adr/0005-learn-extensions-by-folder-check.md)).
- Format-specific views for binaries (archive listings, `.class` summaries) and claiming named binary types such as `.class`, `.jar`, `.gz`.
- Notarized downloadable releases.

## Platform and distribution

- macOS 15 or later, Apple Silicon (arm64) only.
- A host app plus sandboxed Quick Look Preview extension(s), built from source and ad-hoc signed. No paid Apple Developer account required.
- Bundle identifier prefix `com.mdrum.infiniview`.
- Public repository, MIT licence. Nothing specific to one machine or user goes into code, tests, fixtures or docs (see AGENTS.md).
- App groups are unavailable to ad-hoc signed builds on macOS 15+. Settings must reach the extension by another route, chosen during implementation.

## Which files reach Infiniview

| Source | Covers | Notes |
|---|---|---|
| `public.data` | Extensionless files, dotfiles (`.gitignore`), names like `Dockerfile`, `CODEOWNERS` | Includes binaries; classified by content |
| `public.unix-executable` | Executable scripts with no extension | Classified by content |
| **Learned Extensions** | Extensions that ship in the built-in list, plus ones the user adds | Mechanism in [ADR-0001](adr/0001-coverage-via-learned-type.md) |
| **Takeover** (on by default) | Types macOS previews as plain text: source code, JSON, YAML, XML, shell, Markdown, and similar | Switchable; when off, those files get macOS's own preview |

Always left to macOS, Takeover or not: HTML, SVG, `.rtf`, and media and document types macOS renders visually.

The built-in extension list starts from QLOmni's MIT-licensed list (with attribution) and is a plain data file in the repo.

## Classifying a file

Infiniview reads the start of the file and decides:

1. **RTF content** (starts with `{\rtf`), whatever the extension: rendered formatted, keeping its own fonts and sizes.
2. **Text File**: decodes cleanly as UTF-8 (with or without BOM), UTF-16 (with BOM), or Latin-1, with no NUL bytes and almost no control characters in the sample. Shown as text.
3. Anything else: **Fallback Card**.

The sample size and thresholds are tuned against a fixture corpus.

## The Preview (text)

Shown identically in the **Quick Look Panel** and the **Preview Pane**.

- Monospace text, selectable and copyable, scrollable, with line numbers. Soft wrap on.
- Colours follow the system's light/dark appearance live; nothing is fixed to one mode.
- **Syntax highlighting** uses TextMate grammars from VS Code's open-source built-in extensions (MIT), bundled with the app.
  - The language is chosen by extension or by well-known file name (`Dockerfile`, `Makefile`). Failing that, the contents decide: shebang line, `<?xml` prolog, valid JSON.
  - No language identified: plain monospace.
- **Themes**: a bundled light/dark pair by default. An option uses the light/dark themes of a VS Code-family editor installed on the user's machine, discovered when needed and never stored in the repo.
- **Styled Source** for Markdown:
  - Headings larger and bold, with `#` kept but dimmed.
  - `**bold**` in bold and `*italic*` in italic, markers kept but dimmed.
  - Inline code in monospace with a tint; fenced code blocks highlighted in their language.
  - Links: text styled, URL dimmed. List and quote markers dimmed.
  - Tables left as aligned monospace.
- **Large files**: performance comes first. The Preview loads lazily or truncates with a banner ("showing X of Y"), and highlighting switches off above a size limit. The limits are set by measurement against a target of the Preview appearing without noticeable delay.

## Fallback Card

For files that aren't text: what kind of file it is (in the style of `file(1)`), size, dates, and a hex dump of the first few KB.

## Learning an extension

Extensions are learned automatically; the user shouldn't have to think about them. See [ADR-0005](adr/0005-learn-extensions-by-folder-check.md).

- **Folder Check**: whenever Infiniview shows a Preview, a background helper (started by macOS on demand) checks that file's folder (not subfolders), up to 1,000 entries. For each extension macOS doesn't know, it reads the first 32 KB of one file, and if that's a Text File it learns the extension silently. A new extension takes effect within about a second, so the next Preview in that folder works.
- **Right-click → Quick Actions → "Always Preview as Text"** stays as a manual backstop. It takes effect immediately, without a rebuild or reinstall.
- Learned extensions are user state, listed in the settings window so a bad one can be removed. The built-in list is a fixed head start of common extensions (from QLOmni), and nothing learned is ever added to it.
- macOS treats learned extensions as text, so double-clicking such a file opens the default text editor.

## Takeover

On by default. Turning it off returns those types to macOS's own preview; it doesn't swap in Infiniview's plain view. The intended mechanism is a separate preview extension that claims only the system text types, enabled or disabled as a unit. This is to be proven in milestone 1.

Forward-compatibility risk: iOS 27 stopped calling third-party extensions for system types; macOS 26/27 still allow it. If macOS follows, those files fall back to macOS's own preview, which is degraded but never a Generic Icon.

## Host app

One small settings window, no menu bar item:

- Takeover switch
- Learned Extensions list (add, remove)
- Theme option (bundled pair, or the editor's)

Day-to-day use happens in Finder.

## Milestones

1. **Prove the risky mechanisms** (throwaway spikes):
   - A rewritten, re-registered type declaration makes a new extension reach the extension without a rebuild, on macOS 15 and on the latest macOS available.
   - Takeover can be switched on and off.
   - A preview extension claiming `public.data` receives extensionless files and dotfiles.
2. **Prove highlighting speed**: TextMate grammar highlighting in a sandboxed extension, measured on large files to set the limits.
3. **MVP**: classification, text Preview with highlighting and Styled Source, RTF, Fallback Card, the Quick Action, the settings window, and the built-in extension list.
4. **Folder Check**: a launch agent helper, started on demand when a preview extension asks for a check.
5. **Later**: Thumbnail (possibly doubling as a Folder Check trigger when a folder opens), a Finder Sync trigger, named binary types, archive listings.

## Testing

- **Unit tests**: classification (text, RTF, binary, encodings), language detection, Styled Source spans, built-in list parsing.
- **Fixtures**: a generic corpus made for the tests (extensionless scripts, dotfiles, unknown extensions, UTF-16, Latin-1, RTF in a `.txt`, binaries, a large log). Never copies of real projects.
- **Manual checklist** per macOS version: the Quick Look Panel and the Preview Pane for each fixture, learning an extension, and switching Takeover off and on.

## Setup notes

- Legacy QLStephen `.qlgenerator` plugins do nothing on macOS 15+ and can be deleted.
- Other preview apps that claim `public.data` or text types (PreviewText, QLOmni, Syntax Highlight) compete with Infiniview. Disable or remove them when testing.
