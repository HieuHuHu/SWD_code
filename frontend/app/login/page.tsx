'use client';
import { FormEvent, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { api, homeFor, saveSession, Session } from '@/lib/api';
import { Alert } from '@/components/ui';

const DEMO = [
  { login: 'customer1@gmail.com', label: 'Khách hàng', who: 'Nguyễn Văn An', note: 'Có 2 xe – UC05 thêm xe · UC13 đặt lịch' },
  { login: 'customer5@gmail.com', label: 'Khách hàng', who: 'Hoàng Minh Đức', note: 'Có 1 xe đang sửa ở chi nhánh Cầu Giấy' },
  { login: 'reception1.cg@autocare.vn', label: 'Lễ tân', who: 'Lê Thu Hà – Cầu Giấy', note: '13.A1 đặt lịch hộ khách · xem lịch chi nhánh' },
];

/** UC02 – Login */
export default function LoginPage() {
  const router = useRouter();
  const [login, setLogin] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const registered = new URLSearchParams(window.location.search).get('registered');
    if (registered) {
      setLogin(registered);
      setInfo('Đăng ký thành công! Vui lòng đăng nhập bằng tài khoản vừa tạo.');
    }
  }, []);

  async function submit(e?: FormEvent, preset?: string) {
    e?.preventDefault();
    setBusy(true); setError(''); setInfo('');
    try {
      const s = await api<Session>('/auth/login', { method: 'POST', body: { login: preset ?? login, password: preset ? 'Password@123' : password } });
      saveSession(s);
      router.replace(homeFor(s.user.role));
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login-wrap">
      <div className="login-card">
        <aside className="login-side">
          <div className="brand"><span className="brand-dot">A</span>AutoCare</div>
          <h1 style={{ marginTop: 28 }}>Đặt lịch bảo dưỡng &amp; sửa chữa</h1>
          <p className="muted">Quản lý xe của bạn, xem bảng giá dịch vụ từng chi nhánh và đặt lịch theo khung giờ còn trống.</p>
          <div className="demo">
            <span className="small" style={{ color: '#94a3b8' }}>Đăng nhập nhanh bằng tài khoản demo (mật khẩu Password@123):</span>
            {DEMO.map((d) => (
              <button key={d.login} disabled={busy} onClick={() => submit(undefined, d.login)}>
                <b>{d.label}</b> · {d.who}<br /><span className="small" style={{ color: '#94a3b8' }}>{d.note}</span>
              </button>
            ))}
          </div>
        </aside>
        <form className="login-form" onSubmit={submit}>
          <h2 style={{ fontSize: 20 }}>Đăng nhập</h2>
          <p className="muted small" style={{ margin: 0 }}>Khách hàng và nhân viên AutoCare</p>
          <Alert kind="success" onClose={() => setInfo('')}>{info}</Alert>
          <Alert onClose={() => setError('')}>{error}</Alert>
          <label className="field-label" htmlFor="login">Email hoặc số điện thoại</label>
          <input id="login" required value={login} onChange={(e) => setLogin(e.target.value)} placeholder="ten@gmail.com hoặc 09xxxxxxxx" autoComplete="username" />
          <label className="field-label" htmlFor="password">Mật khẩu</label>
          <input id="password" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" />
          <button className="btn-primary" disabled={busy} type="submit" style={{ marginTop: 8 }}>{busy ? 'Đang đăng nhập…' : 'Đăng nhập'}</button>
          <p className="small" style={{ margin: 0 }}>Chưa có tài khoản? <Link href="/register">Đăng ký ngay</Link> · <Link href="/services">Xem bảng giá dịch vụ</Link></p>
          <p className="small muted">Phiên làm việc hết hạn sau 30 phút. Tài khoản bị khóa 15 phút nếu nhập sai mật khẩu 5 lần liên tiếp.</p>
        </form>
      </div>
    </main>
  );
}
