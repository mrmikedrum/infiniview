#!/usr/bin/env python3
"""Writes Infiniview's generic test fixtures.

    make-fixtures.py <dir>            the small corpus (committed under Tests/Fixtures/corpus)
    make-fixtures.py <dir> --large    also a large log (not committed; for manual checks)

Every file is made up for the tests. `expected.tsv` lists what the classifier should say.
"""
import bz2
import gzip
import io
import lzma
import os
import struct
import sys
import tarfile
import zipfile
import zlib

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
# The same without an extension: macOS 27 keeps .txt (public.plain-text) for its own preview,
# so these are the ones that reach Infiniview there.
write("utf16le-noext", b"\xff\xfe" + "UTF-16 without an extension\n".encode("utf-16-le"), "text:utf16LE")
write("latin1-noext", "Latin-1 caf\u00e9 without an extension\n".encode("latin-1"), "text:latin1")
write("rtf-noext", r"{\rtf1\ansi\deff0 {\fonttbl {\f0 Times;}}\f0\fs32 Rich {\i text} without an extension.\par}", "rtf")
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


# Archives: the same small project in each format (ADR-0006).
def png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\x00" + bytes([200, 60, 60]) * 4 for _ in range(4))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


LONG_DIR = "project/" + "/".join(["a-rather-long-folder-name"] * 5)
FILES = {
    "project/README.md": "# Example project\n\nSome **notes** about it.\n",
    "project/src/main.py": "print('hello')\n" * 50,
    "project/config.qqcfg": "key = value\n",
    "project/docs/caf\u00e9.txt": "Accented name.\n",
    "project/pixel.png": png(),
    LONG_DIR + "/deep.txt": "Deep inside.\n",
}
STAMP = 1767225600  # 2026-01-01T00:00:00Z


def data(v):
    return v if isinstance(v, bytes) else v.encode("utf-8")


def zip_bytes(files, metadata=True):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr(zipfile.ZipInfo("project/empty-dir/", (2026, 1, 1, 0, 0, 0)), b"")
        for i, (name, v) in enumerate(files.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED if i % 2 else zipfile.ZIP_STORED
            info.external_attr = 0o100644 << 16
            info.create_system = 3
            z.writestr(info, data(v))
        link = zipfile.ZipInfo("project/readme-link", (2026, 1, 1, 0, 0, 0))
        link.create_system = 3
        link.external_attr = 0o120777 << 16
        z.writestr(link, b"README.md")
        if metadata:
            z.writestr(zipfile.ZipInfo("__MACOSX/project/._README.md", (2026, 1, 1, 0, 0, 0)), b"\x00\x05\x16\x07")
    return buf.getvalue()


def tar_bytes(fmt):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=fmt) as t:
        d = tarfile.TarInfo("project/empty-dir")
        d.type, d.mode, d.mtime = tarfile.DIRTYPE, 0o755, STAMP
        t.addfile(d)
        for name, v in FILES.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data(v)), 0o644, STAMP
            t.addfile(info, io.BytesIO(data(v)))
        link = tarfile.TarInfo("project/readme-link")
        link.type, link.linkname, link.mtime = tarfile.SYMTYPE, "README.md", STAMP
        t.addfile(link)
        meta = tarfile.TarInfo("project/._README.md")
        meta.size, meta.mtime = 4, STAMP
        t.addfile(meta, io.BytesIO(b"\x00\x05\x16\x07"))
    return buf.getvalue()


write("bundle.zip", zip_bytes(FILES), "binary")
write("bundle.tar", tar_bytes(tarfile.GNU_FORMAT), "binary")
pax = tar_bytes(tarfile.PAX_FORMAT)
write("bundle.tar.gz", gzip.compress(pax, mtime=0), "binary")
write("bundle.tar.bz2", bz2.compress(pax), "binary")
write("bundle.tar.xz", lzma.compress(pax), "binary")
gz = io.BytesIO()
with gzip.GzipFile(filename="notes.txt", mode="wb", fileobj=gz, mtime=0) as g:
    g.write(b"Plain notes, gzip compressed.\n")
write("notes.txt.gz", gz.getvalue(), "binary")
# Zip64 records, as archives over 4 GB have, forced on a small zip by lowering zipfile's limits.
limits = zipfile.ZIP_FILECOUNT_LIMIT, zipfile.ZIP64_LIMIT
zipfile.ZIP_FILECOUNT_LIMIT, zipfile.ZIP64_LIMIT = 1, 64
write("zip64.zip", zip_bytes(FILES, metadata=False), "binary")
zipfile.ZIP_FILECOUNT_LIMIT, zipfile.ZIP64_LIMIT = limits
# A zip whose one entry is marked encrypted.
enc = bytearray(zip_bytes({"secret.txt": "not really secret\n"}, metadata=False))
for sig in (b"PK\x03\x04", b"PK\x01\x02"):
    i = 0
    while (i := enc.find(sig, i)) >= 0:
        flag = i + (6 if sig == b"PK\x03\x04" else 8)
        enc[flag] |= 1
        i += 4
write("encrypted.zip", bytes(enc), "binary")

with open(os.path.join(out, "expected.tsv"), "w") as f:
    f.write("# file\tclassification\n")
    for name, kind in expected:
        f.write(f"{name}\t{kind}\n")

if "--large" in sys.argv:
    with open(os.path.join(out, "large.log"), "w") as f:
        for i in range(400_000):
            f.write(f"2026-01-01T00:00:{i % 60:02d}Z INFO  [worker-{i % 8}] request id={i} path=/items/{i} status=200\n")
