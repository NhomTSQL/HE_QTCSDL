const DEFAULT_API_BASE = '/api';

/** Resolve client-side API base path from NEXT_PUBLIC_API_BASE (defaults to Next.js BFF '/api'). */
export function getApiBase(): string {
  const raw = (process.env.NEXT_PUBLIC_API_BASE ?? '').trim();
  if (!raw) return DEFAULT_API_BASE;
  return raw.endsWith('/') && raw.length > 1 ? raw.slice(0, -1) : raw;
}

/** Build a full API endpoint URL against the configured API base while blocking unsafe targets. */
export function apiUrl(path: string): string {
  if (!path.startsWith('/') || path.startsWith('//') || path.includes('\\') || /[\x00-\x1f]/.test(path)) {
    throw new Error(`Invalid API path: ${path}`);
  }
  const base = getApiBase();
  if (base === '/api') {
    return path.startsWith('/api/') || path === '/api' ? path : `/api${path}`;
  }
  const normalizedPath = path.startsWith('/api/') ? path.slice(4) : path === '/api' ? '' : path;
  return `${base}${normalizedPath}`;
}

export type ApiFetchOptions = RequestInit & {
  token?: string | null;
};

/** Wrapper around fetch that routes through apiUrl() with no-store caching and optional Bearer auth. */
export function apiFetch(path: string, options: ApiFetchOptions = {}): Promise<Response> {
  const { token, headers: initHeaders, ...rest } = options;
  const headers = new Headers(initHeaders ?? {});
  if (token && !headers.has('Authorization')) {
    headers.set('Authorization', `Bearer ${token}`);
  }
  return fetch(apiUrl(path), {
    ...rest,
    headers,
    cache: rest.cache ?? 'no-store',
  });
}
