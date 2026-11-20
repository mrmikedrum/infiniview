#!/usr/bin/env python3
"""Writes Infiniview's generic test fixtures.

    make-fixtures.py <dir>            the small corpus (committed under Tests/Fixtures/corpus)
    make-fixtures.py <dir> --large    also a large log (not committed; for manual checks)

Every file is made up for the tests. `expected.tsv` lists what the classifier should say.
"""
import os
import sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
expected = []


def write(name, data, kind, mode=None):
    path = os.path.join(out, name)
    with open(path, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))
    if mode:
        os.chmod(path, mode)
    expected.append((name, kind))


# Extensionless scripts and well-known names
write("run-tests", "#!/bin/sh\nset -e\necho \"running\"\n", "text:utf8", 0o755)
write("tool", "#!/usr/bin/env python3\nprint('hello')\n", "text:utf8", 0o755)
write("not-executable-script", "#!/usr/bin/env ruby\nputs 'hi'\n", "text:utf8")
write("Dockerfile", "FROM alpine:3\nRUN apk add --no-cache curl\nCMD [\"sh\"]\n", "text:utf8")
write("Makefile", "all: build\n\nbuild:\n\techo building\n", "text:utf8")
write("NOTES", "Plain notes with no extension.\nSecond line.\n", "text:utf8")
write("settings-json", '{\n  "name": "example",\n  "enabled": true,\n  "items": [1, 2, 3]\n}\n', "text:utf8")
write("feed", '<?xml version="1.0" encoding="UTF-8"?>\n<feed><entry id="1"/></feed>\n', "text:utf8")
# Dotfiles
write(".exampleignore", "build/\n*.log\n", "text:utf8")
write(".examplerc", "export EXAMPLE=1\nalias ll='ls -l'\n", "text:utf8")
write(".env", "API_URL=https://example.com\nDEBUG=false\n", "text:utf8")
# Unknown extensions
write("settings.zqx", "key = value\nother = 2\n", "text:utf8")
write("schema.lblx", "label: first\nlabel: second\n", "text:utf8")
# Encodings
write("utf8-bom.txt", b"\xef\xbb\xbfcaf\xc3\xa9 with a BOM\n", "text:utf8BOM")
write("utf8-multibyte.txt", "naïve café — ünïcödé ✓ 日本語\n", "text:utf8")
write("utf16le.txt", b"\xff\xfe" + "UTF-16 little endian café\n".encode("utf-16-le"), "text:utf16LE")
write("utf16be.txt", b"\xfe\xff" + "UTF-16 big endian café\n".encode("utf-16-be"), "text:utf16BE")
write("latin1.txt", "Latin-1 café naïve © 2026\n".encode("latin-1"), "text:latin1")
write("ansi-colors.log", "\x1b[32mINFO\x1b[0m started\n\x1b[31mERROR\x1b[0m failed\n", "text:utf8")
# RTF content behind a misleading extension
write("rtf-in-txt.txt", r"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\fs28 Hello {\b bold} world.\par}", "rtf")
# Markdown for Styled Source
write("styled.md", "# Title\n\nSome **bold**, *italic* and `code` with a [link](https://example.com).\n\n"
      "- item\n> quote\n\n```python\nprint('hi')\n```\n", "text:utf8")
# Empty file
write("empty", b"", "text:utf8")
# Binaries
write("blob.bin", bytes(range(256)) * 4, "binary")
write("noext-binary", b"\x7fELF\x02\x01\x01\x00" + bytes(56) + bytes(range(1, 200)), "binary")
write("controls-no-nul", bytes([1, 2, 3, 4, 5, 6, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]) * 16 + b"abc", "binary")
write("archive.gz", b"\x1f\x8b\x08\x00" + bytes(6) + bytes([7, 9, 200, 3, 0, 1]) * 20, "binary")

with open(os.path.join(out, "expected.tsv"), "w") as f:
    f.write("# file\tclassification\n")
    for name, kind in expected:
        f.write(f"{name}\t{kind}\n")

if "--large" in sys.argv:
    with open(os.path.join(out, "large.log"), "w") as f:
        for i in range(400_000):
            f.write(f"2026-01-01T00:00:{i % 60:02d}Z INFO  [worker-{i % 8}] request id={i} path=/items/{i} status=200\n")
