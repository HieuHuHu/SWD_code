'use client';
import { ReactNode } from 'react';
import { STATUS_LABEL, tone } from '@/lib/format';

export function Badge({ status }: { status: string }) {
  return <span className={`badge badge-${tone(status)}`}>{STATUS_LABEL[status] ?? status}</span>;
}

export function Progress({ value }: { value: number }) {
  return (
    <div className="progress" title={`${value}%`}>
      <div className="progress-bar" style={{ width: `${Math.max(0, Math.min(100, value))}%` }} />
      <span>{value}%</span>
    </div>
  );
}

export function Card({ title, actions, children }: { title?: ReactNode; actions?: ReactNode; children: ReactNode }) {
  return (
    <section className="card">
      {(title || actions) && (
        <header className="card-head">
          <h2>{title}</h2>
          <div className="card-actions">{actions}</div>
        </header>
      )}
      {children}
    </section>
  );
}

export function Alert({ kind = 'error', children, onClose }: { kind?: 'error' | 'success'; children: ReactNode; onClose?: () => void }) {
  if (!children) return null;
  return (
    <div className={`alert alert-${kind}`} role={kind === 'error' ? 'alert' : 'status'}>
      <span>{children}</span>
      {onClose && <button className="link" onClick={onClose} aria-label="Đóng">✕</button>}
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="empty">{children}</p>;
}
