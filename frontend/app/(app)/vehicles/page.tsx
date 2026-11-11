// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
'use client';
import { FormEvent, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { VEHICLE_TYPE } from '@/lib/format';
import { Alert, Badge, Card, Empty } from '@/components/ui';

export interface MyVehicle {
  id: number; licensePlate: string; vehicleType: string; brand: string; model: string; manufactureYear: number | null; vin: string | null;
  color: string | null; currentOdometer: number; status: string; appointmentCount: number; openAppointment: string | null;
}
const EMPTY = { licensePlate: '', vehicleType: 'CAR', brand: '', model: '', manufactureYear: '', vin: '', color: '', currentOdometer: '0' };
const PLATE = /^\d{2}[A-Z]{1,2}\d?-(\d{4}|\d{5}|\d{3}\.\d{2})$/;

/** UC05 – Add Vehicle (+ the customer's vehicle list) */
export default function VehiclesPage() {
  const [list, setList] = useState<MyVehicle[] | null>(null);
  const [form, setForm] = useState(EMPTY);
  const [showForm, setShowForm] = useState(false);
  const [touched, setTouched] = useState(false);
  const [error, setError] = useState('');
  const [ok, setOk] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => { api<MyVehicle[]>('/vehicles/mine').then((v) => { setList(v); setShowForm(v.length === 0); }).catch((e) => setError(e.message)); }, []);

  const plate = form.licensePlate.trim().toUpperCase().replace(/\s+/g, '');
  const errs: Record<string, string> = {};
  if (touched) {
    if (!PLATE.test(plate)) errs.licensePlate = 'Ví dụ: 30A-123.45 (ô tô) hoặc 29B1-234.56 (xe máy)';
    if (!form.brand.trim()) errs.brand = 'Nhập hãng xe';
    if (!form.model.trim()) errs.model = 'Nhập dòng xe';
    if (form.vin && !/^[A-HJ-NPR-Z0-9]{17}$/i.test(form.vin.trim())) errs.vin = 'VIN gồm 17 ký tự (không có I, O, Q)';
    if (!/^\d+$/.test(form.currentOdometer)) errs.currentOdometer = 'Số km là số nguyên ≥ 0';
  }
  const set = (k: keyof typeof EMPTY) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setForm({ ...form, [k]: e.target.value });

  async function submit(e: FormEvent) {
    e.preventDefault();
    setTouched(true);
    if (!PLATE.test(plate) || !form.brand.trim() || !form.model.trim() || (form.vin && !/^[A-HJ-NPR-Z0-9]{17}$/i.test(form.vin.trim())) || !/^\d+$/.test(form.currentOdometer)) return;
    setBusy(true); setError(''); setOk('');
    try {
      const r = await api<{ vehicle: MyVehicle; vehicles: MyVehicle[] }>('/vehicles', {
        method: 'POST',
        body: {
          licensePlate: plate, vehicleType: form.vehicleType, brand: form.brand, model: form.model, color: form.color || undefined,
          vin: form.vin || undefined, manufactureYear: form.manufactureYear ? Number(form.manufactureYear) : undefined, currentOdometer: Number(form.currentOdometer),
        },
      });
      setList(r.vehicles);
      setOk(`Đã thêm xe ${r.vehicle.licensePlate} vào danh sách.`);
      setForm(EMPTY); setTouched(false); setShowForm(false);
    } catch (err) { setError((err as Error).message); } finally { setBusy(false); }
  }

  const input = (k: keyof typeof EMPTY, label: string, props: React.InputHTMLAttributes<HTMLInputElement> = {}) => (
    <label>{label}
      <input value={form[k]} onChange={set(k)} className={errs[k] ? 'invalid' : ''} {...props} />
      {errs[k] && <span className="field-error">{errs[k]}</span>}
    </label>
  );

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Xe của tôi</h1>
          <p className="muted" style={{ margin: 0 }}>Đăng ký xe để đặt lịch bảo dưỡng, sửa chữa. Một tài khoản có thể quản lý nhiều xe.</p>
        </div>
        {!showForm && <button className="btn-primary" onClick={() => { setShowForm(true); setOk(''); }}>+ Thêm xe</button>}
      </div>
      <Alert onClose={() => setError('')}>{error}</Alert>
      <Alert kind="success" onClose={() => setOk('')}>{ok}</Alert>

      {showForm && (
        <Card title="UC05 · Thêm xe mới">
          <form onSubmit={submit} noValidate>
            <div className="form-grid">
              {input('licensePlate', 'Biển số *', { placeholder: '30A-123.45' })}
              <label>Loại xe *
                <select value={form.vehicleType} onChange={set('vehicleType')}>
                  <option value="CAR">Ô tô</option><option value="MOTORCYCLE">Xe máy</option>
                </select>
              </label>
              {input('brand', 'Hãng xe *', { placeholder: 'Toyota' })}
              {input('model', 'Dòng xe *', { placeholder: 'Vios 1.5G' })}
              {input('manufactureYear', 'Năm sản xuất', { type: 'number', min: 1950, max: new Date().getFullYear() + 1, placeholder: '2021' })}
              {input('currentOdometer', 'Số km hiện tại *', { type: 'number', min: 0 })}
              {input('vin', 'Số khung (VIN)', { placeholder: '17 ký tự – không bắt buộc' })}
              {input('color', 'Màu xe', { placeholder: 'Trắng' })}
            </div>
            <div className="form-row" style={{ marginTop: 14 }}>
              <button className="btn-primary" disabled={busy} type="submit">{busy ? 'Đang lưu…' : 'Lưu xe'}</button>
              {list && list.length > 0 && <button type="button" className="btn-ghost" onClick={() => { setShowForm(false); setForm(EMPTY); setTouched(false); }}>Hủy</button>}
            </div>
          </form>
        </Card>
      )}

      <Card title={`Danh sách xe${list ? ` (${list.length})` : ''}`}>
        {list === null ? <Empty>Đang tải…</Empty> : list.length === 0 ? <Empty>Bạn chưa có xe nào. Hãy thêm xe để đặt lịch.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>Biển số</th><th>Xe</th><th>Loại</th><th className="num">Số km</th><th>VIN</th><th>Lịch hẹn</th><th>Trạng thái</th><th></th></tr></thead>
              <tbody>
                {list.map((v) => (
                  <tr key={v.id}>
                    <td><b>{v.licensePlate}</b></td>
                    <td>{v.brand} {v.model}<br /><span className="small muted">{[v.manufactureYear, v.color].filter(Boolean).join(' · ') || '–'}</span></td>
                    <td>{VEHICLE_TYPE[v.vehicleType]}</td>
                    <td className="num">{new Intl.NumberFormat('vi-VN').format(v.currentOdometer)}</td>
                    <td className="small">{v.vin ?? '–'}</td>
                    <td className="small">{v.openAppointment ? <>Đang có lịch <b>{v.openAppointment}</b></> : `${v.appointmentCount} lần`}</td>
                    <td><Badge status={v.status} /></td>
                    <td>{v.status === 'ACTIVE' && <Link href={`/book?vehicle=${v.id}`}>Đặt lịch →</Link>}</td>
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
