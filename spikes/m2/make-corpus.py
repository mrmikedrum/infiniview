#!/usr/bin/env python3
"""Writes a synthetic benchmark corpus: the same generic snippet per language, repeated to size."""
import json, os, sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
S = {
 "py": 'class Widget{i}:\n    """Holds item {i}."""\n    def __init__(self, name="w{i}", size={i}):\n        self.name = name  # label\n        self.size = size * 2\n\n    def render(self) -> str:\n        return f"<{{self.name}}:{{self.size}}>" if self.size > 3 else ""\n\n',
 "js": 'export function widget{i}(name = "w{i}", size = {i}) {{\n  // label\n  const doubled = size * 2;\n  return doubled > 3 ? `<${{name}}:${{doubled}}>` : null;\n}}\n\n',
 "ts": 'interface Item{i} {{ name: string; size: number }}\nexport class Widget{i} implements Item{i} {{\n  constructor(public name = "w{i}", public size = {i}) {{}}\n  render(): string {{ return this.size > 3 ? `<${{this.name}}>` : ""; }}\n}}\n\n',
 "c": '/* widget {i} */\nstatic int widget_{i}(const char *name, int size) {{\n    if (size > 3) {{ printf("%s:%d\\n", name, size * 2); }}\n    return size + {i};\n}}\n\n',
 "swift": 'struct Widget{i}: Codable {{\n    var name = "w{i}"\n    let size: Int = {i}\n    func render() -> String {{ size > 3 ? "<\\(name)>" : "" }}  // label\n}}\n\n',
 "go": 'func widget{i}(name string, size int) (string, error) {{\n\tif size > 3 {{\n\t\treturn fmt.Sprintf("%s:%d", name, size*2), nil\n\t}}\n\treturn "", errors.New("small")\n}}\n\n',
 "sh": 'widget_{i}() {{\n  local name="${{1:-w{i}}}"  # label\n  if [ "$2" -gt 3 ]; then echo "$name:$(( $2 * 2 ))"; fi\n}}\n\n',
 "md": '## Section {i}\n\nSome **bold** text, some *italic* text and `inline code` with a [link](https://example.com/{i}).\n\n- item one\n- item two\n\n```python\nprint("block {i}")\n```\n\n',
 "yaml": 'widget_{i}:\n  name: "w{i}"  # label\n  size: {i}\n  tags: [alpha, beta]\n  enabled: true\n',
 "xml": '<widget id="{i}" name="w{i}">\n  <!-- label -->\n  <size unit="px">{i}</size>\n  <tags><tag>alpha</tag><tag>beta</tag></tags>\n</widget>\n',
 "css": '.widget-{i} > .name {{\n  color: #3a7bd5; /* label */\n  margin: {i}px 0 calc(1em + 2px);\n}}\n\n',
 "log": '2026-01-01T00:00:{s:02d}.000Z INFO  [worker-{i}] request id={i} path=/items/{i} status=200 took={i}ms\n2026-01-01T00:00:{s:02d}.500Z WARN  [worker-{i}] slow response for item {i}\n',
}
SIZES = {"10k": 10_000, "100k": 100_000, "1m": 1_000_000, "5m": 5_000_000}
for ext, snip in S.items():
    for label, size in SIZES.items():
        parts, n, i = [], 0, 0
        while n < size:
            p = snip.format(i=i, s=i % 60)
            parts.append(p); n += len(p); i += 1
        path = os.path.join(out, f"{ext}-{label}.{ext}")
        with open(path, "w") as f:
            f.write("".join(parts))
# JSON: pretty and minified (one long line).
for label, size in SIZES.items():
    items = [{"id": i, "name": f"w{i}", "size": i, "tags": ["alpha", "beta"], "enabled": i % 2 == 0} for i in range(size // 70)]
    with open(os.path.join(out, f"json-{label}.json"), "w") as f: json.dump(items, f, indent=2)
    with open(os.path.join(out, f"jsonmin-{label}.json"), "w") as f: json.dump(items, f, separators=(",", ":"))
