// Bundled into one file for JavaScriptCore. The Swift host provides:
//   globalThis.__readGrammar(scopeName) -> JSON string or null  (lazy grammar loading)
// and calls the functions on globalThis.IV. Everything here runs synchronously from the host's
// point of view: promises resolve in the microtask queue JSC drains after each call.
import * as onig from 'vscode-oniguruma';
import * as tm from 'vscode-textmate';

let registry = null;
const grammars = new Map();

function init(wasmBytes, injections) {
  const wasm = onig.loadWASM({
    instantiator: (imports) => Promise.resolve({ instance: new WebAssembly.Instance(new WebAssembly.Module(wasmBytes), imports) }),
  });
  registry = new tm.Registry({
    onigLib: wasm.then(() => ({
      createOnigScanner: (patterns) => new onig.OnigScanner(patterns),
      createOnigString: (s) => new onig.OnigString(s),
    })),
    getInjections: (scopeName) => injections?.[scopeName],
    loadGrammar: async (scopeName) => {
      const json = globalThis.__readGrammar(scopeName);
      return json ? tm.parseRawGrammar(json, scopeName + '.json') : null;
    },
  });
}

// theme: { settings: [...] } (VS Code tokenColors, already resolved). Returns the colour map.
function setTheme(theme) {
  registry.setTheme(theme);
  return registry.getColorMap();
}

function loadGrammar(scopeName) {
  let state = { grammar: null, error: null };
  registry.loadGrammar(scopeName).then((g) => { state.grammar = g; grammars.set(scopeName, g); }, (e) => { state.error = String(e); });
  return state; // filled in once the host's evaluate returns (microtasks drained)
}

// Tokenizes the whole text. Returns a Uint32Array of [utf16Offset, metadata] pairs.
// Lines longer than maxLineLength are left plain; tokenizing stops after maxMillis overall
// (the result says where), so a pathological file can't stall the preview.
function tokenize(scopeName, text, maxLineLength, maxMillis) {
  const grammar = grammars.get(scopeName);
  const start = Date.now();
  let out = new Uint32Array(Math.max(1024, text.length >> 2));
  let n = 0;
  const push = (a, b) => {
    if (n + 2 > out.length) { const bigger = new Uint32Array(out.length * 2); bigger.set(out); out = bigger; }
    out[n++] = a; out[n++] = b;
  };
  let stack = tm.INITIAL;
  let offset = 0;
  let stoppedAt = -1;
  while (offset <= text.length) {
    let end = text.indexOf('\n', offset);
    if (end < 0) end = text.length;
    const line = text.substring(offset, end);
    if (line.length > maxLineLength) {
      push(offset, 0); // plain
    } else {
      const r = grammar.tokenizeLine2(line, stack, 0);
      const t = r.tokens;
      for (let i = 0; i < t.length; i += 2) push(offset + t[i], t[i + 1]);
      stack = r.ruleStack;
    }
    offset = end + 1;
    if (Date.now() - start > maxMillis) { stoppedAt = offset; break; }
  }
  return { tokens: out.slice(0, n), stoppedAt }; // slice: a fresh buffer the host can read from offset 0
}

globalThis.IV = { init, setTheme, loadGrammar, tokenize };
