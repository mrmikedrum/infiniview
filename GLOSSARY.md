# Infiniview

A macOS app that lets Quick Look show the contents of every human-readable file, whatever its extension, so Finder never falls back to a generic app icon.

## Language

**Preview**:
The scrollable, selectable view of a file's contents, shown both in the Quick Look Panel and in the Preview Pane.
_Avoid_: Quick view, peek

**Quick Look Panel**:
The window that opens when you press space on a file in Finder.
_Avoid_: Popup, QL window

**Preview Pane**:
The area beside or above the file list in Finder's column and gallery views that shows the selected file's Preview.
_Avoid_: Thumbnail, sidebar, inspector

**Thumbnail**:
The still image Finder draws in place of a file's icon in file lists; it cannot scroll.
_Avoid_: Icon, preview image

**Text File**:
A file whose contents are human-readable text, judged by its bytes rather than its extension or file type.
_Avoid_: Plain text file, source file

**Fallback Card**:
What a Preview or Thumbnail shows for a file that is not a Text File: what kind of file it is and its size, plus a hex dump in the Preview only.
_Avoid_: Binary view, info panel

**Styled Source**:
Markdown shown with its common elements (headings, bold, italic) visually styled while every markup character stays visible.
_Avoid_: Rendered Markdown, preview mode

**Archive Browser**:
The Preview of a zip, tar or compressed file: a tree of what's inside and, in the Quick Look Panel only, a Preview of the selected entry beside it.
_Avoid_: Archive viewer, file list

**Learned Extension**:
A file extension the user has told Infiniview to treat as text, or that ships in its built-in list.
_Avoid_: Custom extension, registered extension

**Takeover**:
Infiniview showing the Preview for file types that macOS already previews as plain text, instead of macOS doing it; can be switched off.
_Avoid_: Override, system override

**Folder Check**:
A look through the folder of a file being previewed for files whose extension macOS doesn't know, learning each extension whose files turn out to be text.
_Avoid_: Scan, crawl, watcher

**Generic Icon**:
The app-handler or blank-document icon Finder shows when no Preview or Thumbnail is available; the outcome this project exists to eliminate.
_Avoid_: Default icon, fallback icon
