---
status: accepted
---

# Coverage via a Learned Type re-registered at runtime

Quick Look picks a preview extension by a file's concrete UTI. Files with no extension get `public.data`, but every unknown extension gets its own opaque `dyn.*` UTI, which a `public.data` claim does not catch. So Infiniview covers files three ways: its preview extension claims `public.data` and `public.unix-executable` and classifies by content; it claims one type of its own, the **Learned Type**, whose list of file extensions is declared in a small helper bundle that the app rewrites and re-registers with Launch Services whenever an extension is learned; and an optional second extension claims the system's text types for Takeover. Learning an extension takes effect immediately, with no rebuild, and uses only documented mechanisms (type declarations, Launch Services registration).

## Considered Options

- **Register `dyn.*` identifiers directly** (what Syntax Highlight does). Rejected: the encoding is undocumented, Apple calls the IDs opaque, and an entry silently stops matching once any app declares that extension.
- **Fixed extension list compiled into the app** (what QLOmni does). Rejected: every new extension needs a rebuild, and unusual extensions are the main problem.
- **Claim `public.data` only.** Rejected: misses every file with an unknown extension.

## Consequences

- Files with an extension nobody has learned yet still get the system's preview (often a Generic Icon) until the user learns it.
- Because the extension claims `public.data`, it receives binaries too, and must always render something (the Fallback Card); a Quick Look extension can't hand a file back to the system.
- The helper-bundle approach must be proven on a real system before anything else is built (spec, milestone 1).
