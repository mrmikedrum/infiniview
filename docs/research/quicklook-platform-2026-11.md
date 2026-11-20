# Quick Look platform research (November 2026)

Facts gathered on macOS 15.4.1 plus web research, to ground the design. Things marked _unverified_ were not confirmed independently.

## Legacy `.qlgenerator` plugins are dead

- macOS 15 release notes: generator plugin support removed; migrate to Preview and Thumbnail app extensions. <https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes>, <https://eclecticlight.co/2024/10/31/how-sequoia-has-changed-quicklook-and-its-thumbnails/>
- macOS 27 notes: Intel-only software (including Quick Look plugins) stops working in macOS 28. Ship arm64.

## What UTI Quick Look sees (measured via `URLResourceValues.contentType`)

| File | UTI |
|---|---|
| no extension, dotfiles (`.gitignore`), `CODEOWNERS`, `Dockerfile`, non-executable scripts | `public.data` |
| executable script without extension | `public.unix-executable` |
| unknown extension (`.lblx`, `.lst`, `.version`, `.cfg`, `.feature`, `.baseline`, `.off`, `.env`, `.properties`) | `dyn.*` (conforms only to `public.data`/`public.item`) |
| `.JSON` | `public.json` (extension matching is case-insensitive) |
| `.class` / `.jar` | `com.sun.java-class` / `com.sun.java-archive` |
| `.yaml` | `public.yaml` (does not conform to `public.plain-text`) |

- Quick Look dispatches on the concrete UTI, not the conformance tree: claiming `public.data` catches extensionless files and dotfiles but **not** `dyn.*` files (per QLOmni, <https://github.com/j-256/qlomni>).
- A `dyn.*` UTI is `dyn.a` + a custom base-32 encoding of `?0=6:1=<lowercased ext>`. Apple documents these as opaque. Registering `dyn.*` IDs directly is undocumented (sbarex ships 128 of them; efficacy _unverified_), and a dyn entry silently stops matching once any app declares the extension.
- Declaring a type (`UTImportedTypeDeclarations`) with the extension in its tag spec turns that extension into a real UTI that an extension can claim. Installing or uninstalling other apps can change which UTI an extension resolves to (e.g. `.toml` → `com.bps.toml` because PreviewText exports it).

## Precedence

- Third-party extensions can override the system preview for many types (plain text, JSON, source code), but some types are reserved, and the reserved list has shifted across releases (`.ts`, `.html`, `.xml` before macOS 12, `.plist` on 10.15, `.json` on 13/Apple Silicon).
- No documented rule picks between two third-party extensions claiming the same UTI; users resolve it by disabling one.
- **Forward-compat risk:** on iOS 27, Quick Look stopped calling third-party extensions for system-provided UTIs (FB24481377); macOS 26/27 still allow it. <https://developer.apple.com/forums/thread/843292>. macOS 27.3 beta renders Markdown natively.

## Extension mechanics

- Extensions must be sandboxed (pkd rejects unsandboxed appexes).
- Ad-hoc signed local builds in `/Applications` work; no paid account or notarization needed.
- App groups don't work with ad-hoc signing on macOS 15+ (inferred), so settings must be shared between app and extension some other way.
- Once an extension is chosen it can't hand the file back to the system; failure behaviour is _unverified_. It must render something for every file it receives.
- Data-based (`QLPreviewProvider`: HTML/RTF/plain text/PDF/image replies) vs view-based (`QLPreviewingController`: own NSTextView/WKWebView, lazy loading). Neither is deprecated as of the macOS 27 notes.
- `qlmanage -t` often doesn't invoke third-party thumbnailers; on macOS 26 extensions sometimes need toggling off/on in System Settings before they load.

## Prior art

| Project | Status / licence | Approach | Lessons |
|---|---|---|---|
| QLStephen | MIT, last release 2020 | `.qlgenerator` claiming `public.data` | Dead on 15+ |
| PreviewText (Tony Smith) | MIT, archived, 1.0.9 (Apr 2025) | View-based preview + thumbnail appexes; claims `public.data`, `public.plain-text`, exports its own UTIs | Uses an app group for settings |
| QLOmni | MIT, active (1.15.0, Oct 2026) | Declares concrete plain-text UTIs for many extensions so the system text viewer renders them; `EXTRA_EXTS` at build time | Undeclared extensions stay `dyn.*` and get no preview; no highlighting; 1 MiB cap |
| Syntax Highlight (sbarex) | GPL-3, active, notarized | Data-based; unsandboxed XPC helper runs `highlight` and `file`; claims system source types and 128 `dyn.*` IDs | README documents reserved types per OS version |
| Glance | MIT, archived 2020 | WKWebView rendering | — |
