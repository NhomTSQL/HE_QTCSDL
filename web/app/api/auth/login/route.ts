import { NextRequest, NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import { callSp } from '@/lib/db';
import { signUserToken } from '@/lib/auth';

export const runtime = 'nodejs';

type UserRow = {
  id: number;
  username: string;
  password_hash: string;
  role_code: string;
  is_active: boolean;
};

export async function POST(req: NextRequest) {
  let body: { username?: unknown; password?: unknown };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body.' }, { status: 400 });
  }

  const { username, password } = body;
  if (typeof username !== 'string' || typeof password !== 'string' || !username.trim() || !password) {
    return NextResponse.json({ error: 'username and password are required.' }, { status: 400 });
  }

  try {
    const [user] = await callSp<UserRow>('dbo.usp_authenticate_user', {
      username: username.trim(),
    });
    if (!user || !user.is_active || !user.password_hash || user.password_hash.includes('placeholder')) {
      return NextResponse.json({ error: 'Invalid credentials.' }, { status: 401 });
    }
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) return NextResponse.json({ error: 'Invalid credentials.' }, { status: 401 });

    const userInfo = { id: user.id, username: user.username, role: user.role_code };
    const token = await signUserToken(userInfo);
    return NextResponse.json({ token, user: userInfo });
  } catch {
    return NextResponse.json({ error: 'Authentication service unavailable.' }, { status: 503 });
  }
}
