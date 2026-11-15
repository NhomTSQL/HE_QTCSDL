import { NextRequest, NextResponse } from 'next/server';

type BackendCall = {
  method?: string;
  search?: string;
  headers?: Record<string, string>;
  body?: string;
};

/** Resolve the Flask base URL from server-only configuration. */
export function backendBaseUrl(): URL {
  const base = process.env.BACKEND_URL;
  if (!base) throw new Error('BACKEND_URL is required.');
  return new URL(base.endsWith('/') ? base : `${base}/`);
}

/** Call Flask from the Next.js server tier; the browser never sees the backend URL. */
export async function callBackend(path: string, options: BackendCall = {}): Promise<NextResponse> {
  try {
    const url = new URL(path, backendBaseUrl());
    if (options.search) url.search = options.search;
    const headers = new Headers(options.headers ?? {});
    if (options.body) headers.set('content-type', 'application/json');
    const response = await fetch(url, {
      method: options.method ?? 'GET',
      headers,
      body: options.body,
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    });
    const contentType = response.headers.get('content-type') ?? 'application/json';
    return new NextResponse(response.body, { status: response.status, headers: { 'content-type': contentType } });
  } catch {
    return NextResponse.json({ error: 'Backend service unavailable.' }, { status: 503 });
  }
}

/** Forward a BFF request to Flask, forwarding only the headers listed in options.forward. */
export async function proxyToBackend(
  req: NextRequest,
  path: string,
  options: { method?: string; forward?: string[]; body?: boolean } = {},
): Promise<NextResponse> {
  const headers: Record<string, string> = {};
  for (const name of options.forward ?? ['authorization']) {
    const value = req.headers.get(name);
    if (value) headers[name] = value;
  }
  return callBackend(path, {
    method: options.method ?? req.method,
    search: new URL(req.url).search,
    headers,
    body: options.body ? await req.text() : undefined,
  });
}
