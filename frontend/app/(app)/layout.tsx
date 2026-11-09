'use client';
import { ReactNode, useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { api, clearSession, getSession, SessionUser } from '@/lib/api';
import { dt, ROLE_LABEL } from '@/lib/format';

interface Note { id: number; title: string; content: string; createdAt: string }
const PUBLIC = ['/services'];

export default function AppShell({ children }: { children: ReactNode }) {
  const router = useRouter();
  const path = usePathname();
  const [user, setUser] = useState<SessionUser | null>(null);
  const [ready, setReady] = useState(false);
  const [notes, setNotes] = useState<Note[]>([]);
  const [open, setOpen] = useState(false);
  const isPublic = PUBLIC.some((p) => path.startsWith(p));

  useEffect(() => {
    const s = getSession();
    if (!s && !isPublic) { router.replace('/login'); return; }
    setUser(s?.user ?? null);
    setReady(true);
  }, [router, isPublic]);

  useEffect(() => {
    if (!user) return;
    const load = () => api<Note[]>('/auth/notifications').then(setNotes).catch(() => {});
    load();
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, [user, path]);

  if (!ready) return null;
  const nav = !user ? [{ href: '/services', label: 'Bảng giá dịch vụ' }]
    : user.role === 'CUSTOMER'
      ? [{ href: '/services', label: 'Dịch vụ' }, { href: '/vehicles', label: 'Xe của tôi' }, { href: '/book', label: 'Đặt lịch' }, { href: '/appointments', label: 'Lịch hẹn của tôi' }]
      : user.role === 'RECEPTIONIST'
        ? [{ href: '/services', label: 'Dịch vụ' }, { href: '/book', label: 'Đặt lịch hộ khách' }, { href: '/appointments', label: 'Lịch hẹn chi nhánh' }]
        : user.role === 'BRANCH_MANAGER'
          ? [{ href: '/services', label: 'Dịch vụ' }, { href: '/appointments', label: 'Lịch hẹn chi nhánh' }]
          : [{ href: '/services', label: 'Dịch vụ' }];

  return (
    <>
      <header className="topbar">
        <div className="brand"><span className="brand-dot">A</span>AutoCare</div>
        <nav className="nav">
          {nav.map((n) => <Link key={n.href} href={n.href} className={path.startsWith(n.href) ? 'active' : ''}>{n.label}</Link>)}
        </nav>
        {user ? (
          <>
            <button className="bell" onClick={() => setOpen(!open)} aria-label="Thông báo">
              🔔 {notes.length > 0 && <span className="count">{notes.length}</span>}
            </button>
            <div className="who">
              <b>{user.fullName}</b>
              <span>{ROLE_LABEL[user.role]}{user.branchName ? ` · ${user.branchName}` : ''}</span>
            </div>
            <button className="btn-ghost" onClick={() => { clearSession(); router.replace('/login'); }}>Đăng xuất</button>
          </>
        ) : (
          <div className="auth-links"><Link className="ghost" href="/login">Đăng nhập</Link><Link className="primary" href="/register">Đăng ký</Link></div>
        )}
        {open && (
          <div className="notif-panel" onClick={() => setOpen(false)}>
            {notes.length === 0 && <div className="muted">Chưa có thông báo</div>}
            {notes.map((n) => (
              <div key={n.id}><b>{n.title}</b><span className="small">{n.content}</span><br /><span className="small muted">{dt(n.createdAt)}</span></div>
            ))}
          </div>
        )}
      </header>
      <main className="page">{children}</main>
    </>
  );
}
