---
status: accepted
---

# Learn extensions automatically with a Folder Check when a Preview is shown

Most of the text files that slip past Infiniview have one-off extensions no list will ever contain, and Quick Look never calls an extension for a file whose extension macOS doesn't know. But the number of folders a person actually looks at in Finder is small. So whenever Infiniview shows a Preview, it asks a background helper to run a **Folder Check** on that file's folder: the helper looks at up to 1,000 entries in the folder (not subfolders), reads the first 32 KB of one file per extension macOS doesn't know, and silently learns the extensions whose contents are text. The first file with a new extension may still show a Generic Icon; once anything else in its folder has been previewed, it previews like any other Text File, within about a second.

## Considered Options

- **Growing the built-in extension list** (e.g. from GitHub Linguist). Rejected: one-off extensions are the actual problem, and no list reaches them. The current list stays as a head start, and doesn't grow.
- **A watcher on chosen folders.** Rejected: a permanent watch over folders the user has to choose, mostly over files they'll never look at.
- **A Spotlight query for every file with a `dyn.*` type.** Rejected for now: it covers the whole disk instead of what the user looks at, and couldn't be shown to work from a sandboxed session.
- **A Thumbnail extension as a sensor** (Finder asks for thumbnails as soon as a folder opens; the extension would report the folder and decline to draw). Deferred: worth adding if Folder Checks triggered by previews turn out to be too late.
- **A Finder Sync extension observing every folder opened.** Deferred: the only trigger that works in a folder containing nothing but unknown extensions, but built on an extension point Apple has been moving away from.

## Consequences

- The sandboxed preview extension can't read the folder itself, so a helper outside the sandbox runs the Folder Check. The helper is a launch agent inside the app, registered with `SMAppService`; the extension reaches its Mach service through a `mach-lookup` temporary-exception entitlement, and launchd starts it on demand, so it isn't running when not needed. It accepts connections only from Infiniview's own preview extensions. Proven on macOS 15.4 with an ad-hoc signed build: no approval prompt at registration, and a Folder Check of a small folder takes about 15 ms.
- Reading a folder under Documents, Desktop or Downloads may bring up macOS's folder access prompt for Infiniview the first time.
- Learning is per extension, because that's how macOS assigns types: one text file named `foo.x` teaches `.x` everywhere. Binary `.x` files still get the Fallback Card, since every file is classified by its contents.
- macOS treats learned extensions as text, so double-clicking such a file opens it in the default text editor (TextEdit unless changed). That's wanted.
- Learned extensions are user state, kept in settings; nothing learned is ever committed to the built-in list.
