export const STATUS_LABEL: Record<string, string> = {
  // appointments
  PENDING: 'Chờ xác nhận', CONFIRMED: 'Đã xác nhận', REJECTED: 'Bị từ chối', CHECKED_IN: 'Đã nhận xe', IN_SERVICE: 'Đang phục vụ',
  WAITING_PAYMENT: 'Chờ thanh toán', COMPLETED: 'Hoàn thành', CANCELLED: 'Đã hủy',
  // vehicles
  ACTIVE: 'Đang sử dụng', INACTIVE: 'Ngừng sử dụng',
};

const TONE: Record<string, string> = {
  PENDING: 'warn', CONFIRMED: 'info', REJECTED: 'danger', CHECKED_IN: 'info', IN_SERVICE: 'violet', WAITING_PAYMENT: 'violet',
  COMPLETED: 'ok', CANCELLED: 'muted', ACTIVE: 'ok', INACTIVE: 'muted',
};
export const tone = (s: string) => TONE[s] ?? 'muted';

export const ROLE_LABEL: Record<string, string> = {
  RECEPTIONIST: 'Lễ tân', MECHANIC: 'Thợ máy', CASHIER: 'Thu ngân', BRANCH_MANAGER: 'Quản lý chi nhánh', SYS_ADMIN: 'Quản trị hệ thống', CUSTOMER: 'Khách hàng',
};

export const VEHICLE_TYPE: Record<string, string> = { CAR: 'Ô tô', MOTORCYCLE: 'Xe máy', ALL: 'Mọi loại xe' };

export function money(v: number | null | undefined) {
  return v == null ? '–' : new Intl.NumberFormat('vi-VN').format(v) + ' đ';
}
export function dt(v: string | null | undefined) {
  if (!v) return '–';
  return new Date(v).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}
export function dateVi(isoDate: string) {
  const [y, m, d] = isoDate.split('-');
  return `${d}/${m}/${y}`;
}
export function minutes(n: number) {
  return n >= 60 ? `${Math.floor(n / 60)} giờ${n % 60 ? ` ${n % 60} phút` : ''}` : `${n} phút`;
}
/** yyyy-mm-dd in local time, offset by n days */
export function isoDay(offset = 0) {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
