// Turns a checkout of VS Code's built-in extensions into Infiniview's bundled highlighting assets:
//   grammars/<scopeName>.json   every TextMate grammar (plist grammars converted to JSON)
//   languages.json              language ids, file extensions, file names, first-line patterns,
//                               grammar scope, embedded languages, injections
//   themes/light.json, dark.json the default VS Code light/dark pair, includes resolved
// usage: node prepare-assets.mjs <vscode checkout> <out dir> <light theme file> <dark theme file>
import fs from 'node:fs';
import path from 'node:path';
import tm from 'vscode-textmate';

const [root, out, lightTheme, darkTheme] = process.argv.slice(2);
const ext = path.join(root, 'extensions');
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(path.join(out, 'grammars'), { recursive: true });
fs.mkdirSync(path.join(out, 'themes'), { recursive: true });

// VS Code's JSON files may hold comments and trailing commas.
function readJSONC(file) {
  const src = fs.readFileSync(file, 'utf8');
  let s = '', i = 0, inStr = false;
  while (i < src.length) {
    const c = src[i];
    if (inStr) { s += c; if (c === '\\') { s += src[i + 1]; i += 2; continue; } if (c === '"') inStr = false; i++; continue; }
    if (c === '"') { inStr = true; s += c; i++; continue; }
    if (c === '/' && src[i + 1] === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && src[i + 1] === '*') { i = src.indexOf('*/', i + 2) + 2; continue; }
    s += c; i++;
  }
  return JSON.parse(s.replace(/,(\s*[}\]])/g, '$1'));
}

const languages = new Map(); // id -> entry
const grammars = []; // {scopeName, language, embeddedLanguages, injectTo}
for (const dir of fs.readdirSync(ext).sort()) {
  if (dir.startsWith('vscode-')) continue; // test fixtures
  const pkgFile = path.join(ext, dir, 'package.json');
  if (!fs.existsSync(pkgFile)) continue;
  const contributes = readJSONC(pkgFile).contributes ?? {};
  for (const l of contributes.languages ?? []) {
    const e = languages.get(l.id) ?? { id: l.id, extensions: [], filenames: [] };
    e.extensions.push(...(l.extensions ?? []).map((x) => x.replace(/^\./, '').toLowerCase()));
    e.filenames.push(...(l.filenames ?? []));
    if (l.firstLine) e.firstLine = l.firstLine;
    if (l.aliases?.[0] && !e.name) e.name = l.aliases[0];
    languages.set(l.id, e);
  }
  for (const g of contributes.grammars ?? []) {
    const file = path.join(ext, dir, g.path);
    if (!fs.existsSync(file)) continue;
    const raw = tm.parseRawGrammar(fs.readFileSync(file, 'utf8'), file);
    fs.writeFileSync(path.join(out, 'grammars', `${g.scopeName}.json`), JSON.stringify(raw));
    grammars.push({ scopeName: g.scopeName, language: g.language, embeddedLanguages: g.embeddedLanguages, injectTo: g.injectTo });
  }
}

const langList = [...languages.values()].map((l) => {
  const g = grammars.find((x) => x.language === l.id);
  return { ...l, extensions: [...new Set(l.extensions)], filenames: [...new Set(l.filenames)], scopeName: g?.scopeName ?? null };
}).filter((l) => l.scopeName);
const injections = {};
for (const g of grammars) for (const target of g.injectTo ?? []) (injections[target] ??= []).push(g.scopeName);
fs.writeFileSync(path.join(out, 'languages.json'), JSON.stringify({ languages: langList, injections }, null, 1));

// A theme with its "include" chain flattened into one tokenColors list (included first),
// in the shape vscode-textmate's Registry.setTheme expects, plus the editor colours we use.
function resolveTheme(file) {
  const t = readJSONC(file);
  const base = t.include ? resolveTheme(path.join(path.dirname(file), t.include)) : { colors: {}, settings: [] };
  return {
    name: t.name ?? base.name,
    type: t.type ?? base.type,
    colors: { ...base.colors, ...(t.colors ?? {}) },
    settings: [...base.settings, ...(t.tokenColors ?? [])],
  };
}
for (const [name, file] of [['light', lightTheme], ['dark', darkTheme]]) {
  const t = resolveTheme(path.join(ext, 'theme-defaults', 'themes', file));
  const keep = ['editor.background', 'editor.foreground', 'editorLineNumber.foreground', 'editor.selectionBackground'];
  const colors = Object.fromEntries(keep.filter((k) => t.colors[k]).map((k) => [k, t.colors[k]]));
  // The first, scope-less rule sets the default colours.
  const settings = [{ settings: { foreground: colors['editor.foreground'], background: colors['editor.background'] } }, ...t.settings];
  fs.writeFileSync(path.join(out, 'themes', `${name}.json`), JSON.stringify({ name: t.name, type: t.type, colors, settings }));
}
console.log(`${grammars.length} grammars, ${langList.length} languages → ${out}`);
