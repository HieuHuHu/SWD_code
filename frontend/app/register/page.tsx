// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
'use client';
import { FormEvent, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { api } from '@/lib/api';
import { Alert } from '@/components/ui';

type Form = { fullName: string; phone: string; email: string; password: string; confirmPassword: string };
const EMPTY: Form = { fullName: '', phone: '', email: '', password: '', confirmPassword: '' };

/** Client-side checks mirror the server rules (01.E1); the server re-validates everything. */
function validate(f: Form): Partial<Record<keyof Form, string>> {
  const e: Partial<Record<keyof Form, string>> = {};
  if (f.fullName.trim().length < 2) e.fullName = 'Họ tên tối thiểu 2 ký tự';
  if (!/^0\d{9}$/.test(f.phone.trim())) e.phone = 'Số điện thoại gồm 10 chữ số, bắt đầu bằng 0';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.email.trim())) e.email = 'Email không đúng định dạng';
  if (f.password.length < 8 || !/[A-Za-z]/.test(f.password) || !/\d/.test(f.password)) e.password = 'Tối thiểu 8 ký tự, gồm cả chữ và số';
  if (f.confirmPassword !== f.password) e.confirmPassword = 'Mật khẩu nhập lại không khớp';
  return e;
}

/** UC01 – Register Account */
export default function RegisterPage() {
  const router = useRouter();
  const [form, setForm] = useState<Form>(EMPTY);
  const [touched, setTouched] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const errors = touched ? validate(form) : {};
  const set = (k: keyof Form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm({ ...form, [k]: e.target.value });

  async function submit(e: FormEvent) {
    e.preventDefault();
    setTouched(true);
    if (Object.keys(validate(form)).length) return;
    setBusy(true); setError('');
    try {
      const r = await api<{ email: string }>('/auth/register', { method: 'POST', body: form });
      router.replace(`/login?registered=${encodeURIComponent(r.email)}`);           // POST-2: redirect to login
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const field = (k: keyof Form, label: string, type = 'text', placeholder = '', auto = '') => (
    <div className="field">
      <label htmlFor={k}>{label}</label>
      <input id={k} type={type} value={form[k]} onChange={set(k)} placeholder={placeholder} autoComplete={auto} className={errors[k] ? 'invalid' : ''} />
      {errors[k] && <span className="field-error">{errors[k]}</span>}
    </div>
  );

  return (
    <main className="login-wrap">
      <div className="login-card">
        <aside className="login-side">
          <div className="brand"><span className="brand-dot">A</span>AutoCare</div>
          <h1 style={{ marginTop: 28 }}>Tạo tài khoản khách hàng</h1>
          <p className="muted">Một tài khoản để quản lý nhiều xe, đặt lịch tại mọi chi nhánh và theo dõi lịch sử dịch vụ.</p>
          <ul className="muted small" style={{ paddingLeft: 18, lineHeight: 1.9 }}>
            <li>Email và số điện thoại chỉ được đăng ký một lần</li>
            <li>Mật khẩu được mã hóa một chiều, AutoCare không lưu mật khẩu gốc</li>
            <li>Sau khi đăng ký, bạn đăng nhập để thêm xe và đặt lịch</li>
          </ul>
        </aside>
        <form className="login-form" onSubmit={submit} noValidate>
          <h2 style={{ fontSize: 20 }}>Đăng ký</h2>
          <Alert onClose={() => setError('')}>{error}</Alert>
          {field('fullName', 'Họ và tên', 'text', 'Nguyễn Văn A', 'name')}
          {field('phone', 'Số điện thoại', 'tel', '09xxxxxxxx', 'tel')}
          {field('email', 'Email', 'email', 'ten@gmail.com', 'email')}
          {field('password', 'Mật khẩu', 'password', '', 'new-password')}
          {field('confirmPassword', 'Nhập lại mật khẩu', 'password', '', 'new-password')}
          <button className="btn-primary" disabled={busy} type="submit" style={{ marginTop: 6 }}>{busy ? 'Đang tạo tài khoản…' : 'Đăng ký'}</button>
          <p className="small" style={{ margin: 0 }}>Đã có tài khoản? <Link href="/login">Đăng nhập</Link></p>
        </form>
      </div>
    </main>
  );
}
