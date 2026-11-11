// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { api, getSession } from '@/lib/api';
import { minutes, money, VEHICLE_TYPE } from '@/lib/format';
import { Alert, Card, Empty } from '@/components/ui';

export interface Branch { id: number; code: string; name: string; address: string; phone: string }
export interface Service { id: number; code: string; name: string; description: string | null; vehicleType: string; price: number; estimatedMinutes: number }

/** UC10 – View Service List (public) */
export default function ServicesPage() {
  const router = useRouter();
  const [branches, setBranches] = useState<Branch[]>([]);
  const [branchId, setBranchId] = useState<number>(0);
  const [type, setType] = useState('');
  const [services, setServices] = useState<Service[] | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    api<Branch[]>('/branches').then((b) => { setBranches(b); setBranchId(b[0]?.id ?? 0); }).catch((e) => setError(e.message));
  }, []);
  useEffect(() => {
    if (!branchId) return;
    setServices(null);
    api<Service[]>(`/branches/${branchId}/services${type ? `?vehicleType=${type}` : ''}`).then(setServices).catch((e) => setError(e.message));
  }, [branchId, type]);

  const book = (serviceId: number) => {
    const s = getSession();
    if (!s) { router.push('/login'); return; }
    router.push(`/book?branch=${branchId}&service=${serviceId}`);
  };
  const canBook = (() => { const r = getSession()?.user.role; return !r || r === 'CUSTOMER' || r === 'RECEPTIONIST'; })();

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Bảng giá dịch vụ</h1>
          <p className="muted" style={{ margin: 0 }}>Chọn chi nhánh để xem các dịch vụ đang cung cấp, giá tham khảo và thời gian thực hiện.</p>
        </div>
        <div className="tabs">
          {[['', 'Tất cả loại xe'], ['CAR', 'Ô tô'], ['MOTORCYCLE', 'Xe máy']].map(([v, l]) => (
            <button key={v} className={type === v ? 'on' : ''} onClick={() => setType(v)}>{l}</button>
          ))}
        </div>
      </div>
      <Alert onClose={() => setError('')}>{error}</Alert>
      <div className="branch-tabs" style={{ marginBottom: 18 }}>
        {branches.map((b) => (
          <button key={b.id} className={branchId === b.id ? 'on' : ''} onClick={() => setBranchId(b.id)}>
            <b>{b.name}</b><span className="small muted">{b.address}</span>
          </button>
        ))}
      </div>
      <Card>
        {services === null ? <Empty>Đang tải…</Empty> : services.length === 0 ? <Empty>Chi nhánh chưa có dịch vụ phù hợp.</Empty> : (
          <div className="svc-grid">
            {services.map((s) => (
              <div key={s.id} className="svc-card">
                <h3>{s.name}</h3>
                <div className="meta"><span className="badge badge-info">{VEHICLE_TYPE[s.vehicleType]}</span><span>⏱ {minutes(s.estimatedMinutes)}</span></div>
                <p className="small muted grow" style={{ margin: 0 }}>{s.description}</p>
                <div className="price">{money(s.price)}</div>
                {canBook && <button className="btn-primary" onClick={() => book(s.id)}>Đặt lịch dịch vụ này</button>}
              </div>
            ))}
          </div>
        )}
        <p className="small muted" style={{ marginBottom: 0 }}>Giá là giá tham khảo, có thể thay đổi sau khi kiểm tra xe nếu phát sinh hạng mục được khách đồng ý.</p>
      </Card>
    </>
  );
}
