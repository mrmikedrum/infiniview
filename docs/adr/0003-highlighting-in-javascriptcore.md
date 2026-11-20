---
status: accepted
---

# TextMate highlighting with vscode-textmate in JavaScriptCore

The spec calls for VS Code's TextMate grammars. Infiniview runs the reference engine, vscode-textmate with vscode-oniguruma's WASM build of Oniguruma (both MIT, unmodified), inside JavaScriptCore in the preview extension. Grammars, themes and the bundled JavaScript are generated into `Vendor/highlighting` by `scripts/update-highlighting.sh` from a pinned VS Code tag, so the build needs neither the network nor Node.

On macOS 27, JavaScriptCore only enables its JIT for processes with `com.apple.security.cs.allow-jit`. Without it highlighting is 20–30× slower (milestone 2 research), so the preview extensions carry that entitlement.

## Considered Options

- **A TextMate engine written in Swift with NSRegularExpression.** ICU's regex dialect differs from Oniguruma's, which grammars rely on (`\G`, possessive quantifiers, and others). Getting it right is a project of its own.
- **Tree-sitter.** A different grammar system from the one the spec names, and it needs a compiled parser per language.

## Consequences

- If a future macOS stops granting `allow-jit` to ad-hoc signed extensions, highlighting gets 20–30× slower. The limits in `PreviewLimits` still keep the first screen fast, but less of each file gets highlighted.
- Grammars update with `scripts/update-highlighting.sh <tag>`.
