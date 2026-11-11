// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
'use client';
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { api, getSession, SessionUser } from '@/lib/api';
import { dateVi, isoDay, minutes, money, VEHICLE_TYPE } from '@/lib/format';
import { Alert, Card, Empty } from '@/components/ui';
import type { Branch, Service } from '../services/page';
import type { MyVehicle } from '../vehicles/page';

interface Slot { id: number; startTime: string; endTime: string; capacity: number; bookedCount: number; status: string; available: boolean; past: boolean }
interface Cust { id: number; fullName: string; phone: string; email: string }
interface Created { code: string; date: string; startTime: string; endTime: string; branchName: string; branchAddress: string; licensePlate: string; estimatedTotal: number }

/** UC13 – Create Service Appointment (uses UC12 time slots). Receptionists book on behalf of a customer (13.A1). */
export default function BookPage() {
  const [me, setMe] = useState<SessionUser | null>(null);
  const isDesk = me?.role === 'RECEPTIONIST';
  const steps = isDesk ? ['Khách hàng', 'Xe', 'Chi nhánh & dịch vụ', 'Ngày & giờ', 'Xác nhận'] : ['Xe', 'Chi nhánh & dịch vụ', 'Ngày & giờ', 'Xác nhận'];
  const [step, setStep] = useState(0);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const [customer, setCustomer] = useState<Cust | null>(null);
  const [q, setQ] = useState('');
  const [found, setFound] = useState<Cust[] | null>(null);
  const [vehicles, setVehicles] = useState<MyVehicle[] | null>(null);
  const [vehicleId, setVehicleId] = useState(0);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [branchId, setBranchId] = useState(0);
  const [services, setServices] = useState<Service[]>([]);
  const [chosen, setChosen] = useState<number[]>([]);
  const [date, setDate] = useState(isoDay(1));
  const [slots, setSlots] = useState<{ slots: Slot[]; message: string | null } | null>(null);
  const [slotId, setSlotId] = useState(0);
  const [note, setNote] = useState('');
  const [created, setCreated] = useState<Created | null>(null);
  const [preset, setPreset] = useState<{ service?: number; vehicle?: number }>({});

  const name = (i: number) => steps[i];
  const at = (label: string) => steps.indexOf(label);
  const vehicle = vehicles?.find((v) => v.id === vehicleId);
  const branch = branches.find((b) => b.id === branchId);
  const slot = slots?.slots.find((s) => s.id === slotId);
  const picked = useMemo(() => services.filter((s) => chosen.includes(s.id)), [services, chosen]);
  const total = picked.reduce((a, s) => a + s.price, 0);

  // ---- initial load + presets from ?branch=&service=&vehicle=
  useEffect(() => {
    const u = getSession()?.user ?? null;
    setMe(u);
    const p = new URLSearchParams(window.location.search);
    setPreset({ service: Number(p.get('service')) || undefined, vehicle: Number(p.get('vehicle')) || undefined });
    api<Branch[]>('/branches').then((b) => {
      setBranches(b);
      const wanted = u?.role === 'RECEPTIONIST' ? u.branchId : Number(p.get('branch')) || b[0]?.id;
      setBranchId(wanted ?? b[0]?.id ?? 0);
    }).catch((e) => setError(e.message));
    if (u?.role === 'CUSTOMER') loadVehicles('/vehicles/mine', Number(p.get('vehicle')) || 0);
  }, []);

  function loadVehicles(path: string, pre = 0) {
    setVehicles(null);
    api<MyVehicle[]>(path).then((v) => {
      const active = v.filter((x) => x.status === 'ACTIVE');
      setVehicles(v);
      setVehicleId(active.find((x) => x.id === pre)?.id ?? (active.length === 1 ? active[0].id : 0));
    }).catch((e) => setError(e.message));
  }

  // services of the branch applicable to the chosen vehicle type (UC10)
  useEffect(() => {
    if (!branchId || !vehicle) return;
    api<Service[]>(`/branches/${branchId}/services?vehicleType=${vehicle.vehicleType}`).then((s) => {
      setServices(s);
      setChosen((c) => {
        const keep = c.filter((id) => s.some((x) => x.id === id));
        if (!keep.length && preset.service && s.some((x) => x.id === preset.service)) return [preset.service];
        return keep;
      });
    }).catch((e) => setError(e.message));
  }, [branchId, vehicle?.vehicleType, preset.service]);

  // time slots of the branch on the date (UC12)
  const loadSlots = () => {
    if (!branchId || !date) return;
    setSlots(null);
    api<{ slots: Slot[]; message: string | null }>(`/branches/${branchId}/slots?date=${date}`).then((r) => {
      setSlots(r);
      setSlotId((id) => (r.slots.some((s) => s.id === id && s.available) ? id : 0));
    }).catch((e) => setError(e.message));
  };
  useEffect(loadSlots, [branchId, date]);

  async function search() {
    setError('');
    try { setFound(await api<Cust[]>(`/customers?q=${encodeURIComponent(q)}`)); } catch (e) { setError((e as Error).message); }
  }

  async function confirm() {
    setBusy(true); setError('');
    try {
      const r = await api<Created>('/appointments', {
        method: 'POST', body: { vehicleId, branchId, slotId, serviceIds: chosen, note: note || undefined, customerId: isDesk ? customer?.id : undefined },
      });
      setCreated(r);
    } catch (e) {
      const msg = (e as Error).message;
      setError(msg);
      if (/hết chỗ|đã đóng|đã qua/.test(msg)) { setStep(at('Ngày & giờ')); loadSlots(); }          // 13.E1 – choose another slot
    } finally { setBusy(false); }
  }

  const canNext = (() => {
    const s = name(step);
    if (s === 'Khách hàng') return !!customer;
    if (s === 'Xe') return !!vehicle && vehicle.status === 'ACTIVE';
    if (s === 'Chi nhánh & dịch vụ') return !!branchId && chosen.length > 0;
    if (s === 'Ngày & giờ') return !!slot?.available;
    return false;
  })();

  if (!me) return null;
  if (!['CUSTOMER', 'RECEPTIONIST'].includes(me.role)) return <Card><Empty>Chức năng đặt lịch dành cho khách hàng và lễ tân.</Empty></Card>;

  if (created) {
    return (
      <Card>
        <div className="success-box">
          <div style={{ fontSize: 40 }}>✅</div>
          <h1>Đặt lịch thành công</h1>
          <div className="code">{created.code}</div>
          <p className="muted">Trạng thái: <span className="badge badge-warn">Chờ xác nhận</span> – chi nhánh sẽ xác nhận lịch hẹn và gửi thông báo.</p>
          <p><b>{created.startTime}–{created.endTime} ngày {dateVi(created.date)}</b> tại {created.branchName}<br /><span className="small muted">{created.branchAddress}</span></p>
          <p>Xe {created.licensePlate} · Dự kiến {money(created.estimatedTotal)}</p>
          <div className="form-row" style={{ justifyContent: 'center' }}>
            <Link className="btn btn-primary" href="/appointments">Xem lịch hẹn</Link>
            <button className="btn-ghost" onClick={() => { setCreated(null); setStep(0); setSlotId(0); setNote(''); setChosen([]); loadSlots(); }}>Đặt lịch khác</button>
          </div>
        </div>
      </Card>
    );
  }

  return (
    <>
      <div className="page-head">
        <div>
          <h1>{isDesk ? 'Đặt lịch hộ khách hàng' : 'Đặt lịch dịch vụ'}</h1>
          <p className="muted" style={{ margin: 0 }}>Chọn xe, dịch vụ và khung giờ còn trống. Hệ thống giữ chỗ ngay khi bạn xác nhận.</p>
        </div>
      </div>
      <div className="steps">
        {steps.map((s, i) => <span key={s} className={i === step ? 'on' : i < step ? 'done' : ''}>{i < step ? '✓' : i + 1}. {s}</span>)}
      </div>
      <Alert onClose={() => setError('')}>{error}</Alert>

      <Card>
        {name(step) === 'Khách hàng' && (
          <>
            <h2 style={{ marginBottom: 10 }}>Tìm khách hàng (số điện thoại, email hoặc tên)</h2>
            <div className="form-row">
              <input style={{ flex: 1 }} value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && search()} placeholder="VD: 0912000001" />
              <button className="btn-primary" disabled={q.trim().length < 3} onClick={search}>Tìm</button>
            </div>
            {found && (found.length === 0 ? <Empty>Không tìm thấy khách hàng.</Empty> : (
              <table style={{ marginTop: 12 }}>
                <thead><tr><th>Khách hàng</th><th>Điện thoại</th><th>Email</th><th></th></tr></thead>
                <tbody>
                  {found.map((c) => (
                    <tr key={c.id} className="clickable" onClick={() => { setCustomer(c); loadVehicles(`/customers/${c.id}/vehicles`); }}>
                      <td><b>{c.fullName}</b></td><td>{c.phone}</td><td>{c.email}</td>
                      <td>{customer?.id === c.id ? <span className="badge badge-ok">Đã chọn</span> : <span className="small">Chọn</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ))}
          </>
        )}

        {name(step) === 'Xe' && (
          vehicles === null ? <Empty>Đang tải…</Empty> : vehicles.length === 0 ? (
            <Empty>{isDesk ? 'Khách hàng chưa đăng ký xe nào.' : <>Bạn chưa có xe. <Link href="/vehicles">Thêm xe</Link> trước khi đặt lịch.</>}</Empty>
          ) : (
            <div className="svc-grid">
              {vehicles.map((v) => (
                <div key={v.id} className={`svc-card ${v.status === 'ACTIVE' ? 'selectable' : ''} ${vehicleId === v.id ? 'selected' : ''}`}
                  onClick={() => v.status === 'ACTIVE' && setVehicleId(v.id)} style={v.status !== 'ACTIVE' ? { opacity: .5 } : undefined}>
                  <h3>{v.licensePlate}</h3>
                  <div className="meta"><span className="badge badge-info">{VEHICLE_TYPE[v.vehicleType]}</span>{v.status !== 'ACTIVE' && <span className="badge badge-muted">Ngừng sử dụng</span>}</div>
                  <span>{v.brand} {v.model}</span>
                  <span className="small muted">{new Intl.NumberFormat('vi-VN').format(v.currentOdometer)} km{v.openAppointment ? ` · đang có lịch ${v.openAppointment}` : ''}</span>
                </div>
              ))}
            </div>
          )
        )}

        {name(step) === 'Chi nhánh & dịch vụ' && (
          <>
            <h2 style={{ marginBottom: 10 }}>Chi nhánh</h2>
            <div className="branch-tabs" style={{ marginBottom: 18 }}>
              {branches.filter((b) => !isDesk || b.id === me.branchId).map((b) => (
                <button key={b.id} className={branchId === b.id ? 'on' : ''} onClick={() => { setBranchId(b.id); setSlotId(0); }}>
                  <b>{b.name}</b><span className="small muted">{b.address}</span>
                </button>
              ))}
            </div>
            <h2 style={{ marginBottom: 10 }}>Dịch vụ cho {VEHICLE_TYPE[vehicle?.vehicleType ?? 'CAR'].toLowerCase()} (chọn một hoặc nhiều)</h2>
            <div className="svc-grid">
              {services.map((s) => {
                const on = chosen.includes(s.id);
                return (
                  <div key={s.id} className={`svc-card selectable ${on ? 'selected' : ''}`} onClick={() => setChosen(on ? chosen.filter((x) => x !== s.id) : [...chosen, s.id])}>
                    <h3>{on ? '☑' : '☐'} {s.name}</h3>
                    <span className="small muted grow">{s.description}</span>
                    <div className="meta"><span>⏱ {minutes(s.estimatedMinutes)}</span></div>
                    <div className="price">{money(s.price)}</div>
                  </div>
                );
              })}
            </div>
          </>
        )}

        {name(step) === 'Ngày & giờ' && (
          <>
            <div className="form-row" style={{ marginBottom: 14 }}>
              <label>Ngày hẹn
                <input type="date" value={date} min={isoDay(0)} onChange={(e) => { setDate(e.target.value); setSlotId(0); }} />
              </label>
              <span className="small muted">Chi nhánh: <b>{branch?.name}</b> · mỗi khung giờ nhận số xe có hạn</span>
            </div>
            {slots === null ? <Empty>Đang tải khung giờ…</Empty> : (
              <>
                {slots.message && <Alert kind="error">{slots.message}</Alert>}
                <div className="slot-grid">
                  {slots.slots.map((s) => (
                    <button key={s.id} className={`slot ${slotId === s.id ? 'on' : ''}`} disabled={!s.available} onClick={() => setSlotId(s.id)}>
                      {s.startTime} – {s.endTime}
                      <small>{s.past ? 'Đã qua' : s.status === 'CLOSED' ? 'Đóng' : s.bookedCount >= s.capacity ? 'Hết chỗ' : `Còn ${s.capacity - s.bookedCount}/${s.capacity} chỗ`}</small>
                    </button>
                  ))}
                </div>
              </>
            )}
          </>
        )}

        {name(step) === 'Xác nhận' && (
          <div className="grid">
            <dl className="summary">
              {isDesk && <><dt>Khách hàng</dt><dd>{customer?.fullName} · {customer?.phone}</dd></>}
              <dt>Xe</dt><dd>{vehicle?.licensePlate} – {vehicle?.brand} {vehicle?.model}</dd>
              <dt>Chi nhánh</dt><dd>{branch?.name}<br /><span className="small muted">{branch?.address}</span></dd>
              <dt>Thời gian</dt><dd>{slot?.startTime}–{slot?.endTime} ngày {dateVi(date)}</dd>
            </dl>
            <div>
              <dl className="summary">
                <dt>Dịch vụ</dt>
                <dd>{picked.map((s) => <div key={s.id} style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}><span>{s.name}</span><span>{money(s.price)}</span></div>)}</dd>
                <dt>Tạm tính</dt><dd style={{ fontSize: 18, color: 'var(--brand)' }}>{money(total)}</dd>
              </dl>
              <label className="field">Mô tả triệu chứng / ghi chú (không bắt buộc)
                <textarea value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} placeholder="VD: phanh kêu khi đạp, đèn check engine sáng…" />
              </label>
            </div>
          </div>
        )}

        <div className="step-nav">
          <button className="btn-ghost" disabled={step === 0 || busy} onClick={() => setStep(step - 1)}>← Quay lại</button>
          {name(step) === 'Xác nhận'
            ? <button className="btn-success" disabled={busy} onClick={confirm}>{busy ? 'Đang giữ chỗ…' : '✓ Xác nhận đặt lịch'}</button>
            : <button className="btn-primary" disabled={!canNext} onClick={() => setStep(step + 1)}>Tiếp tục →</button>}
        </div>
      </Card>
    </>
  );
}
