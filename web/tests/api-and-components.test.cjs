const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function loadModule(relativePath, env = {}, extraContext = {}, imports = {}) {
  const exports = {};
  const source = ts.transpileModule(readFileSync(join(__dirname, '..', relativePath), 'utf8'), {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      jsx: ts.JsxEmit.React,
    },
  }).outputText;
  vm.runInNewContext(source, {
    exports,
    module: { exports },
    Headers,
    Response,
    process: { env },
    require(name) {
      if (name in imports) return imports[name];
      throw new Error('Unexpected import: ' + name);
    },
    ...extraContext,
  });
  return exports;
}

test('getApiBase defaults to /api and normalizes trailing slash from NEXT_PUBLIC_API_BASE', () => {
  assert.equal(loadModule('lib/api.ts', {}).getApiBase(), '/api');
  assert.equal(loadModule('lib/api.ts', { NEXT_PUBLIC_API_BASE: '  /api/v2/ ' }).getApiBase(), '/api/v2');
  assert.equal(
    loadModule('lib/api.ts', { NEXT_PUBLIC_API_BASE: 'http://localhost:5000/api/' }).getApiBase(),
    'http://localhost:5000/api',
  );
});

test('apiUrl resolves routes against configured API base without duplicating /api', () => {
  const defaultApi = loadModule('lib/api.ts', {});
  assert.equal(defaultApi.apiUrl('/api/auth/login'), '/api/auth/login');
  assert.equal(defaultApi.apiUrl('/nodes?status=ONLINE'), '/api/nodes?status=ONLINE');

  const customApi = loadModule('lib/api.ts', { NEXT_PUBLIC_API_BASE: 'http://localhost:5000/api' });
  assert.equal(customApi.apiUrl('/api/auth/login'), 'http://localhost:5000/api/auth/login');
  assert.equal(customApi.apiUrl('/nodes'), 'http://localhost:5000/api/nodes');
});

test('apiUrl rejects protocol-relative, cross-origin and control character paths', () => {
  const api = loadModule('lib/api.ts', {});
  for (const bad of ['//evil.invalid/steal', 'https://evil.invalid/api', '/api/\n//evil']) {
    assert.throws(() => api.apiUrl(bad));
  }
});

test('apiFetch routes through apiUrl, sets no-store cache and attaches Bearer token', async () => {
  let calledUrl = '';
  let calledInit = null;
  const api = loadModule(
    'lib/api.ts',
    { NEXT_PUBLIC_API_BASE: '/api/v1' },
    {
      fetch: async (url, init) => {
        calledUrl = url;
        calledInit = init;
        return new Response('{"ok":true}');
      },
    },
  );
  await api.apiFetch('/api/handover', { method: 'POST', token: 'jwt-sample-token', body: '{}' });
  assert.equal(calledUrl, '/api/v1/handover');
  assert.equal(calledInit.cache, 'no-store');
  assert.equal(calledInit.headers.get('Authorization'), 'Bearer jwt-sample-token');
});

test('HandoverTab is extracted as a standalone component and wired into page.tsx', () => {
  const handoverMod = loadModule(
    'components/HandoverTab.tsx',
    {},
    {},
    {
      react: { useState: init => [init, () => {}], default: { createElement: () => ({}) } },
      '@/lib/api': { apiFetch: async () => new Response('[]') },
      '@/lib/i18n': { getCopy: () => ({ handover: {}, myWork: {} }) },
    },
  );
  assert.equal(typeof handoverMod.HandoverTab, 'function');

  const pageSrc = readFileSync(join(__dirname, '..', 'app/page.tsx'), 'utf8');
  assert.ok(pageSrc.includes("import { HandoverTab"), 'page.tsx must import HandoverTab');
  assert.ok(pageSrc.includes('<HandoverTab'), 'page.tsx must render <HandoverTab />');
  assert.ok(!pageSrc.includes('className="ticket-form handover-form"'), 'inline handover form must be removed from page.tsx');
});
