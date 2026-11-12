import { SignJWT, jwtVerify } from 'jose';

function getSecret(): Uint8Array {
  const raw = process.env.JWT_SECRET;
  if (!raw || raw.length < 32) throw new Error('JWT_SECRET must contain at least 32 characters.');
  return new TextEncoder().encode(raw);
}

export interface TokenPayload { sub: string; username: string; role: string }
export async function signUserToken(user: { id: number; username: string; role: string }): Promise<string> {
  return new SignJWT({ username: user.username, role: user.role }).setProtectedHeader({ alg: 'HS256' }).setSubject(String(user.id)).setIssuedAt().setExpirationTime('8h').sign(getSecret());
}
export async function verifyUserToken(token: string): Promise<TokenPayload | null> {
  try {
    const { payload } = await jwtVerify(token, getSecret());
    if (typeof payload.sub !== 'string' || typeof payload.username !== 'string' || typeof payload.role !== 'string') return null;
    return { sub: payload.sub, username: payload.username, role: payload.role };
  } catch { return null; }
}
export function extractBearerToken(header: string | null): string | null {
  const match = header?.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}
