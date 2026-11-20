const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

class NextResponse extends Response {
  static json(body, init) { return new NextResponse(JSON.stringify(body), init); }
}

function load(relativePath, context = {}, imports = {}) {
  const exports = {};
  const source = ts.transpileModule(readFileSync(join(__dirname, '..', relativePath), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  vm.runInNewContext(source, {
    exports, module: { exports }, URL, Headers, Response, AbortSignal,
    process: { env: { BACKEND_URL: 'http://127.0.0.1:5000' } },
    require(name) {
      if (name === 'next/server') return { NextResponse };
      if (name in imports) return imports[name];
      throw new Error('Unexpected import: ' + name);
    },
    ...context,
  });
  return exports;
}

test('proxy rejects absolute, protocol-relative and backslash destinations', () => {
  const backend = load('lib/backend.ts');
  for (const path of ['https://example.invalid', '//169.254.169.254/latest', '/\\example.invalid', '/api/\n//evil']) {
    assert.throws(() => backend.resolveBackendUrl(path));
  }
  assert.equal(backend.resolveBackendUrl('/api/nodes').origin, 'http://127.0.0.1:5000');
});

test('proxy rejects unsupported protocol and credentials in configured URL', () => {
  for (const url of ['file:///etc/passwd', 'http://user:password@localhost:5000']) {
    const backend = load('lib/backend.ts', { process: { env: { BACKEND_URL: url } } });
    assert.throws(() => backend.backendBaseUrl());
  }
});

test('proxy forbids redirects and marks responses no-store', async () => {
  let options;
  const backend = load('lib/backend.ts', {
    fetch: async (_, value) => { options = value; return new Response('{"ok":true}'); },
  });
  const response = await backend.callBackend('/auth/login', { method: 'POST', body: '{}' });
  assert.equal(options.redirect, 'error');
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
});

test('invalid target makes no network call', async () => {
  let calls = 0;
  const backend = load('lib/backend.ts', { fetch: async () => { calls++; } });
  const response = await backend.callBackend('//example.invalid/secret');
  assert.equal(response.status, 503);
  assert.equal(calls, 0);
});

test('catch-all rejects encoded separators and traversal before proxying', async () => {
  let calls = 0;
  const route = load('app/api/[...path]/route.ts', {}, {
    '@/lib/backend': { proxyToBackend: () => { calls++; } },
  });
  for (const segment of ['..', '.', 'a/b', 'a\\b', '%2e%2e', '%2fsecret', '\0']) {
    const response = await route.GET({ method: 'GET' }, { params: Promise.resolve({ path: [segment] }) });
    assert.equal(response.status, 400);
  }
  assert.equal(calls, 0);
});

test('CSV export neutralizes formula strings and preserves numeric values', async () => {
  let captured;
  const csv = load('lib/csv.ts', {
    Blob,
    URL: { createObjectURL(blob) { captured = blob; return 'blob:test'; }, revokeObjectURL() {} },
    document: { createElement: () => ({ click() {} }), body: { appendChild() {}, removeChild() {} } },
  });
  csv.downloadCsv('test.csv', ['Input'], [['=1+1'], [' +SUM(1,2)'], ['@cmd'], [-12], ['normal']]);
  const text = await captured.text();
  assert.ok(text.includes("'=1+1"));
  assert.ok(text.includes("' +SUM(1,2)"));
  assert.ok(text.includes("'@cmd"));
  assert.ok(text.includes('\r\n-12\r\nnormal'));
});
