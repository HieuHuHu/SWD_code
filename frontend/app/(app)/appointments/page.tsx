'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { api, getSession, SessionUser } from '@/lib/api';
import { dateVi, dt, money } from '@/lib/format';
import { Alert, Badge, Card, Empty } from '@/components/ui';

interface Appt {
  id: number; code: string; status: string; note: string | null; createdAt: string; date: string; startTime: string; endTime: string;
  branchName: string; licensePlate: string; vehicle: string; customerName: string; customerPhone: string;
  services: { name: string; price: number }[]; estimatedTotal: number;
}

export default function AppointmentsPage() {
  const [me, setMe] = useState<SessionUser | null>(null);
  const [rows, setRows] = useState<Appt[] | null>(null);
  const [date, setDate] = useState('');
  const [error, setError] = useState('');

  useEffect(() => { setMe(getSession()?.user ?? null); }, []);
  useEffect(() => {
    if (!me) return;
    setRows(null);
    const path = me.role === 'CUSTOMER' ? '/appointments/mine' : `/appointments${date ? `?date=${date}` : ''}`;
    api<Appt[]>(path).then(setRows).catch((e) => setError(e.message));
  }, [me, date]);

  if (!me) return null;
  const isCustomer = me.role === 'CUSTOMER';

  return (
    <>
      <div className="page-head">
        <div>
          <h1>{isCustomer ? 'Lịch hẹn của tôi' : `Lịch hẹn – ${me.branchName ?? 'toàn hệ thống'}`}</h1>
          <p className="muted" style={{ margin: 0 }}>{isCustomer ? 'Theo dõi các lịch hẹn đã đặt và trạng thái xử lý.' : 'Lịch hẹn của chi nhánh, mới nhất ở trên.'}</p>
        </div>
        <div className="form-row">
          {!isCustomer && <label>Lọc theo ngày<input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></label>}
          {!isCustomer && date && <button className="btn-ghost" onClick={() => setDate('')}>Bỏ lọc</button>}
          {(isCustomer || me.role === 'RECEPTIONIST') && <Link className="btn btn-primary" href="/book">+ Đặt lịch</Link>}
        </div>
      </div>
      <Alert onClose={() => setError('')}>{error}</Alert>
      <Card>
        {rows === null ? <Empty>Đang tải…</Empty> : rows.length === 0 ? <Empty>Chưa có lịch hẹn nào.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Mã lịch hẹn</th><th>Thời gian</th>{!isCustomer && <th>Khách hàng</th>}<th>Xe</th><th>Dịch vụ</th><th className="num">Tạm tính</th><th>Trạng thái</th><th>Đặt lúc</th></tr>
              </thead>
              <tbody>
                {rows.map((a) => (
                  <tr key={a.id}>
                    <td style={{ whiteSpace: 'nowrap' }}><b>{a.code}</b>{isCustomer && <><br /><span className="small muted">{a.branchName}</span></>}</td>
                    <td style={{ whiteSpace: 'nowrap' }}><b>{a.startTime}–{a.endTime}</b><br /><span className="small muted">{dateVi(a.date)}</span></td>
                    {!isCustomer && <td>{a.customerName}<br /><span className="small muted">{a.customerPhone}</span></td>}
                    <td>{a.licensePlate}<br /><span className="small muted">{a.vehicle}</span></td>
                    <td className="small">{(a.services ?? []).map((s) => s.name).join(', ')}{a.note && <><br /><i className="muted">“{a.note}”</i></>}</td>
                    <td className="num">{money(a.estimatedTotal)}</td>
                    <td><Badge status={a.status} /></td>
                    <td className="small">{dt(a.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
