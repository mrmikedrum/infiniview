# Infiniview

Quick Look for every human-readable file. Press space on a `Dockerfile`, a `.gitignore`, an extensionless script or a file with an extension macOS has never heard of, and Infiniview shows its text, with line numbers and syntax highlighting, instead of a generic icon. Files that aren't text get a Fallback Card: what kind of file it is, its size and dates, and a hex dump.

The [spec](docs/spec.md) and the [glossary](GLOSSARY.md) describe what it does and the words it uses. Decisions are in [docs/adr](docs/adr), and platform research in [docs/research](docs/research).

## Requirements

- macOS 15 or later, on Apple Silicon
- The Command Line Tools (`xcode-select --install`). Xcode works too, but isn't needed.
- No Apple Developer account: the app is built from source and ad-hoc signed.

## Install

```sh
scripts/build.sh --install
```

This builds `Infiniview.app` and installs it in `/Applications`, or `~/Applications` if you can't write to `/Applications` (set `INSTALL_DIR` to choose). It then registers the extensions and the built-in Learned Extensions. If previews don't change straight away, make sure both Infiniview extensions are on under System Settings → General → Login Items & Extensions → Quick Look, and turn on "Always Preview as Text" under Finder.

Other Quick Look apps that claim the same files (PreviewText, QLOmni, Syntax Highlight) compete with Infiniview, and macOS doesn't define which one wins. Turn them off while using Infiniview. Old `.qlgenerator` plugins do nothing on macOS 15 and later.

## Use

- **Quick Look** (space) and Finder's **Preview Pane** show the Preview.
- **Learning extensions** happens by itself. Whenever Infiniview shows a Preview, a background helper checks the rest of that folder (up to 1,000 files, not subfolders) and learns the extensions of text files macOS doesn't recognise, so their Preview works the next time. The very first file with a new extension can still get macOS's own preview until something else in its folder has been previewed. A learned extension also makes those files open in your default text editor.
- **Learning by hand**: right-click a file → Quick Actions → **Always Preview as Text**. From then on every file with that extension previews as text, straight away. This works for extensions macOS doesn't know. Ones it already knows keep their own preview, and Takeover covers macOS's own text types.
- **Settings** (open the Infiniview app):
  - **Takeover** (on by default): Infiniview also previews the types macOS shows as plain text, such as source code, JSON, YAML, XML and Markdown. Off: macOS shows its own preview for them.
  - **Learned Extensions**: add or remove extensions.
  - **Theme**: the bundled light/dark pair, or the themes of a VS Code-family editor found in Applications.

Limits, from [measurements](docs/research/milestone-2-highlighting-2026-11.md): the first 300 lines are highlighted before the Preview appears, and highlighting covers up to 2 MB of text. Files over 32 MB show their first 32 MB with a note saying so.

### Known limits on macOS 27

- `.txt` files and files named `README` or `LICENSE` keep macOS's own text preview: third-party extensions can't take `public.plain-text`.
- `.ts` files are a video type (MPEG-2 transport stream) to macOS, so they never reach a text preview.

## Uninstall

```sh
scripts/uninstall.sh            # keeps settings
scripts/uninstall.sh --settings # removes them too
```

## Develop

```sh
scripts/test.sh                  # unit tests
scripts/check.sh                 # preview the fixture corpus through the installed extensions
swift run PreviewRender <file> out.png [light|dark]   # render a Preview to PNG
scripts/update-highlighting.sh [vscode tag]           # regenerate Vendor/highlighting (needs Node)
```

`scripts/check.sh` uses a small Quick Look host (`tools/qlprobe`), because `qlmanage -p` crashes on macOS 27 whenever it hosts a preview extension. To see what the extensions do in normal use, run `defaults write com.mdrum.infiniview debugLog -bool true`. Each preview then writes a line to `Library/Logs/Infiniview.log` in the extension's container (`~/Library/Containers/com.mdrum.infiniview.preview` or `….takeover`), and each Folder Check writes a line to `~/Library/Logs/Infiniview-helper.log`.

Before each release, and on each macOS version, run through the [manual checklist](docs/manual-checklist.md).

## Licence

MIT. Third-party material (VS Code grammars and themes, vscode-textmate, vscode-oniguruma, QLOmni's extension list) is listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
