# Milestone 1 spikes (November 2026)

Throwaway spikes proving the risky mechanisms in the [spec](../spec.md). The code is in `spikes/m1/` (`build.sh` builds and installs everything). Results are from macOS 27.0.1 (26A434) on Apple Silicon, built with the Command Line Tools only (no Xcode), ad-hoc signed, installed to `~/Applications`.

**All three mechanisms work.** Not yet covered: macOS 15 (no machine available), and the same checks in Finder itself (see "Still to check by hand").

## How previews were observed

- `qlmanage -p` is unusable on macOS 27.0.1: it crashes (`-[__NSDictionaryM setObject:forKey:]: key cannot be nil` in `EXConcreteExtension makeExtensionContextAndXPCConnectionForRequest:`) whenever it has to host a preview *extension*, including Apple's own (`com.apple.ips`). The host seems to need a bundle identifier.
- Instead, `QLProbe.app` (in the spike) shows each file in a `QLPreviewView`, the same QuickLookUI machinery Finder uses, in a long-running process. It reads paths from stdin, like a Finder that stays open.
- The spike extensions append one line per request to `spike.log` in their sandbox container: which extension answered, and the file's content type. `log show` needs an admin account, so the unified log wasn't an option.
- `QLPreviewView` ignores re-assigning the same item; the probe clears the item and calls `refreshPreviewItem()` so each request really reaches an extension.

## 1. Learning an extension with no rebuild: works

Setup: a helper bundle in `~/Library/Application Support/<app>/…Types.app` holding only `Contents/Info.plist`: no executable, no signature. It exports one type (`UTExportedTypeDeclarations`, conforming to `public.plain-text`) whose `public.filename-extension` list is the Learned Extensions. The preview extension's `QLSupportedContentTypes` lists that type's identifier, although a different bundle declares it. To learn or forget an extension, a tool rewrites the plist, bumps `CFBundleVersion` and calls `LSRegisterURL(url, true)`.

| Step (one long-running host process) | Result |
|---|---|
| `seen.qqv` before learning (type `dyn.*`) | not sent to Infiniview |
| learn `qqv`, preview `seen.qqv` again | Infiniview, type = Learned Type |
| file created before learning, never previewed | Infiniview |
| file created after learning | Infiniview |
| forget `qqv`, preview again | not sent to Infiniview; the type is `dyn.*` again |

Learning takes effect for the next preview, in an already-running host, with nothing rebuilt or re-signed.

Limits found:

- **The Learned Type can't take an extension that already has a declared type.** Learning `yaml` or `log` leaves them as `public.yaml` and `com.apple.log`. The same will happen for extensions another installed app declares. So the Quick Action should be offered only when a file's type is `dyn.*`; system text types belong to Takeover.
- `UTType(filenameExtension:)` in the process that registered keeps returning the old answer; other processes see the change at once.
- Untested: whether the registration survives a reboot or a Launch Services database rebuild, since the helper isn't in an application folder. Fallback: the host app re-registers the helper every time it launches.

## 2. Switching Takeover: works

A second preview extension in the same app claims the system text types. `pluginkit -e ignore -i <takeover id>` switches it off and `pluginkit -e use -i <id>` switches it back on. These are the same per-user setting System Settings → Extensions shows. Off: `.json`, `.py`, `.md` no longer reach Infiniview, and the main extension is unaffected (`Dockerfile` still reaches it). On: they come back. Repeated off/on cycles behaved the same.

Findings that shape the Takeover extension:

- **Dispatch is by concrete type only.** Claiming `public.source-code` didn't catch `.c` (`public.c-source`); claiming `public.script` didn't catch `.rb` (`public.ruby-script`). The Takeover extension must list every concrete system text type it wants.
- **`public.plain-text` is reserved on macOS 27.0.1.** `.txt`, `.text`, and (on macOS 27) files named `README` and `LICENSE`, which now resolve to `public.plain-text`, never reached a third-party extension, Takeover or not. They get macOS's own text preview: not a Generic Icon, but no line numbers or highlighting.
- With Takeover off, macOS's own preview couldn't be confirmed automatically (qlmanage crashes on those too); it's on the manual checklist.

## 3. `public.data` catches extensionless files and dotfiles: works

| File | Type | Reached Infiniview |
|---|---|---|
| `Dockerfile`, `CODEOWNERS` | `public.data` | yes |
| `.gitignore`, `.envrc`, `.editorconfig` | `public.data` | yes |
| `#!/bin/sh` script without the execute bit | `public.data` | yes |
| executable scripts (`#!/bin/sh`, `#!/usr/bin/env python3`) | `public.unix-executable` | yes |
| extensionless binary | `public.data` | yes |
| `Makefile` | `public.make-source` | no: a system type, so Takeover's |
| `README`, `LICENSE` | `public.plain-text` | no: reserved (above) |

## Bonus: getting settings to the sandboxed extension

App groups aren't available to ad-hoc signed builds. What works: the host writes its own defaults domain, and the extension has `com.apple.security.temporary-exception.shared-preference.read-only` for that domain and reads it with `UserDefaults(suiteName:)`. A change made with `defaults write` reached the extension on the next preview, with no relaunch. A `home-relative-path.read-only` exception for a folder in Application Support did *not* work as written; not pursued.

## Building without Xcode

This Mac has only the Command Line Tools. They're enough. `swiftc -parse-as-library -application-extension … -Xlinker -e -Xlinker _NSExtensionMain` builds the appex, and `codesign -s -` with the sandbox entitlement signs it. The extension crashes at launch unless its Info.plist carries the keys Xcode normally adds: `CFBundleInfoDictionaryVersion`, `CFBundleSupportedPlatforms`, `DTPlatformName`, `DTPlatformVersion`, `DTSDKName`, `DTSDKBuild`. After replacing an installed copy, `pluginkit` sometimes drops the extensions for a few seconds; `pluginkit -a` brings them back.

## Still to check by hand

- macOS 15: all three spikes.
- In Finder (Quick Look Panel and Preview Pane): learn an extension, then press space on a file of that type that was previewed before learning (Finder may cache it); switch Takeover off and see macOS's own preview for `.json`; and see that nothing goes blank.
- After a reboot: learned extensions still work.
