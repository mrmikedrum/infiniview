# Manual checklist

Run on each macOS version (record the version and date). The fixtures are in `Tests/Fixtures/corpus`. `python3 Tests/Fixtures/make-fixtures.py <dir> --large` also writes a 34 MB `large.log`. Before starting, turn off other Quick Look apps that claim text (PreviewText, QLOmni, Syntax Highlight).

`scripts/check.sh` already confirms which fixtures reach Infiniview. This list covers what only a person can see.

## Setup

- [ ] `scripts/build.sh --install` finishes without errors.
- [ ] System Settings → General → Login Items & Extensions → Quick Look lists "Infiniview" and "Infiniview Takeover", both on.
- [ ] The same place, under Finder (or Actions), lists "Always Preview as Text". Turn it on.

## Preview, in both the Quick Look Panel (space) and the Preview Pane (column or gallery view)

- [ ] `Dockerfile`, `Makefile`, `run-tests`, `tool`, `.env`, `.examplerc`: text, line numbers, highlighting.
- [ ] `NOTES`, `settings-json`, `feed`: text. `settings-json` is highlighted as JSON and `feed` as XML.
- [ ] `styled.md`: larger headings, bold and italic, tinted inline code, underlined link, with every `#`, `*`, `` ` ``, `[`, `](` kept but dimmed; the fenced Python block is highlighted.
- [ ] `utf16le-noext`, `latin1-noext`: correct characters (é).
- [ ] `rtf-noext`: formatted, in its own fonts.
- [ ] `empty`: says "Empty file.", never blank.
- [ ] `noext-binary`, `controls-no-nul`: Fallback Card with kind, size, dates and hex dump.
- [ ] `large.log`: appears without noticeable delay, with the "Showing the first … of …" note; scrolling stays smooth.
- [ ] Text can be selected and copied; ⌘F finds text.
- [ ] Switch the system between Light and Dark with a Preview open: colours follow straight away.

## Learning an extension

- [ ] Press space on `settings.zqx` (or another unknown extension). Note what macOS shows.
- [ ] Right-click it → Quick Actions → Always Preview as Text. The message names the extension.
- [ ] Press space again: the text shows, with no rebuild or relaunch. (If Finder still shows the old preview, note it: Finder may cache previews per file.)
- [ ] Settings window: the extension is in the list; remove it, and the file goes back to macOS's preview.
- [ ] After a restart, learned extensions still preview as text.

## Folder Checks

- [ ] After installing, macOS reports a background item for Infiniview, and the settings window shows no warning about Folder Checks.
- [ ] Make a folder with `notes` (no extension), `a.<new ext>` with text in it, and `b.<another new ext>` with binary bytes. Press space on `a.…`: macOS's own preview.
- [ ] Press space on `notes`, then on `a.…` again: the text shows. `b.…` still gets macOS's preview.
- [ ] In a folder under Documents, Desktop or Downloads, the first Folder Check may bring up a macOS prompt for Infiniview to access that folder. Note what it says.
- [ ] Remove the learned extension in the settings window, then preview `notes` again: the extension isn't learned back.

## Archives

- [ ] `bundle.zip`, `bundle.tar`, `bundle.tar.gz`, `bundle.tar.bz2`, `bundle.tar.xz` in the Quick Look Panel: a header line, the tree with `project` open, and `README.md` selected and shown as Styled Source beside it. No `__MACOSX` or `._README.md`.
- [ ] Click `src` → `main.py`: highlighted Python. Click `pixel.png`: a small red square. Click `readme-link`: "Link to README.md". Click `empty-dir`: a folder note.
- [ ] Drag the divider: both sides resize.
- [ ] The same files in the Preview Pane: only the tree, in small text, and folders open and close.
- [ ] `notes.txt.gz`: one entry, `notes.txt`, whose text shows when selected.
- [ ] `encrypted.zip`: `secret.txt` is listed, and selecting it says it's encrypted.
- [ ] `archive.gz` (damaged): Fallback Card.
- [ ] A large `.tar.gz` (hundreds of MB): the Preview appears within a few seconds, with a note if the listing stopped early.

## Takeover

- [ ] With Takeover on, a `.json`, `.py` and `.md` file get Infiniview's Preview (line numbers).
- [ ] Turn Takeover off in Settings: the same files get macOS's own preview, not a Generic Icon or a blank.
- [ ] Turn it back on: Infiniview's Preview returns.

## Theme

- [ ] With a VS Code-family editor installed, choose its themes in Settings: previews use its light and dark themes.
- [ ] Switch back to the bundled pair.
