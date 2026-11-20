---
status: accepted
---

# Preview archives with Infiniview's own readers and macOS's compression libraries

Archives are the most common files that would otherwise get a Fallback Card or a Generic Icon, and macOS has no Quick Look preview for any of them. So Infiniview's main preview extension also claims zip (and jar and war), tar, and gzip, bzip2 and xz files, tarred or not, and shows them in an **Archive Browser**. Every file is still judged by its bytes: a `.zip` that isn't one gets the Fallback Card.

The readers are Infiniview's own: zip from its central directory at the end of the file (nothing is unpacked to list it), tar read front to back (ustar, pax, GNU and V7 headers). Compression comes from what ships with macOS: zlib for gzip and zip's deflate, libbz2 for bzip2, and the Compression framework's LZMA decoder for xz. There's no third-party code and no change to the build.

## Considered Options

- **libarchive** (BSD licence). It would add 7z, RAR, zstd, cpio, ISO and more, but macOS's SDK has no headers for it, so it would mean bundling and building a C library. Deferred until there's a need for those formats.
- **ZIPFoundation** (MIT, Swift). It covers zip only, which the reader here already does in about 150 lines.
- **Embedding Apple's own Quick Look view (`QLPreviewView`) for the selected entry.** It would preview any type macOS can, but whether it works inside a Quick Look extension is untested. Infiniview draws text, images and PDFs itself instead; anything else gets the Fallback Card.

## Consequences

- The Quick Look Panel gets the tree beside a Preview of the selected entry; the Preview Pane is too narrow, so it gets the tree only. The same width breakpoint switches the text size.
- The Quick Look Panel keeps the keyboard (arrows, space, Escape) for itself, so the browser is used with the mouse. Measured on macOS 15: no key presses reach the preview, and each click arrives about 0.55–0.6 s late, because the panel waits out the double-click interval (0.5 s by default) before passing a click on. Infiniview handles a click in under 10 ms once it arrives; the wait can only be shortened by the system double-click speed setting.
- A compressed tar has to be unpacked from the start both to list it and to reach an entry. Listing stops after 2 seconds or 20,000 entries and says so, even partway through stepping over one huge entry; on an Apple Silicon Mac a 170 MB `.tar.gz` with 19,000 entries lists in under 2 seconds. Reaching an entry deep in a huge one can take minutes: the browser says so, and stops unpacking as soon as another entry is selected or the Preview closes. A zip lists from its central directory without unpacking anything, so its size barely matters: 20,000 entries of a 570 MB zip take about 150 ms.
- Entries are unpacked into the extension's own temporary folder and deleted when the Preview closes. Only the start of a large entry is unpacked: as much text as a Preview shows (32 MiB, noted beside the entry's name when there's more), or up to 64 MiB of an image or PDF. So a single compressed file of any size, such as a 200 GB `.log.gz`, shows its start straight away.
- Zip64 (archives over 4 GB, or with over 65,535 entries) is read wherever its records are present.
- Encrypted zip entries are listed but not shown, since a Preview can't ask for a password. Zip methods other than stored, deflate and bzip2 are listed but not unpacked.
- macOS metadata that archivers add (`__MACOSX/`, `._name`) is hidden, as Archive Utility does.
- Formats macOS doesn't recognise (`.7z` has a type but no reader here; `.rar`, `.zst`, `.whl` get made-up types) still get the Fallback Card or a Generic Icon.
