---
status: accepted
---

# Settings reach the extensions through the app's defaults domain

App groups don't work with ad-hoc signing on macOS 15 and later, so the sandboxed preview extensions read the app's own defaults domain (`com.mdrum.infiniview`) through the `com.apple.security.temporary-exception.shared-preference.read-only` entitlement. The app writes it as its standard defaults. A change reaches the extension on the next preview, with no relaunch (milestone 1 research).

Only what the extensions need goes there: the theme choice and the resolved editor themes as JSON. The app resolves editor themes when the option is chosen and again each time it opens. Learned Extensions are also stored there, but the extensions never read them; they act through the Learned Type.

## Considered Options

- **A file in Application Support plus a home-relative read-only exception.** It didn't work as written in the spike.
- **Copying files into the extension's container.** Writing into another app's container triggers macOS's App Data protection prompts.
