// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
'use client';

export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4001/api';
const KEY = 'autocare.session';

export type Role = 'CUSTOMER' | 'RECEPTIONIST' | 'MECHANIC' | 'CASHIER' | 'BRANCH_MANAGER' | 'SYS_ADMIN';
export interface SessionUser {
  userId: number; fullName: string; role: Role; staffId: number | null; branchId: number | null; customerId: number | null;
  email: string; phone: string | null; branchName: string | null;
}
export interface Session { accessToken: string; user: SessionUser }

export function getSession(): Session | null {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}
export function saveSession(s: Session) {
  try { localStorage.setItem(KEY, JSON.stringify(s)); } catch { /* storage unavailable */ }
}
export function clearSession() {
  try { localStorage.removeItem(KEY); } catch { /* storage unavailable */ }
}

/** Fetch wrapper: adds the JWT, unwraps Nest error messages, redirects to /login when the session expires. */
export async function api<T = any>(path: string, opts: { method?: string; body?: unknown } = {}): Promise<T> {
  const s = getSession();
  const res = await fetch(API_URL + path, {
    method: opts.method ?? 'GET',
    headers: { 'Content-Type': 'application/json', ...(s ? { Authorization: `Bearer ${s.accessToken}` } : {}) },
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && s && !path.startsWith('/auth/')) {
    clearSession();
    window.location.href = '/login';
  }
  if (!res.ok) {
    const msg = Array.isArray(data.message) ? data.message.join('; ') : data.message;
    throw new Error(msg ?? `Lỗi ${res.status}`);
  }
  return data as T;
}

export function homeFor(role: Role): string {
  if (role === 'CUSTOMER') return '/vehicles';
  if (role === 'RECEPTIONIST' || role === 'BRANCH_MANAGER') return '/appointments';
  return '/services';
}
