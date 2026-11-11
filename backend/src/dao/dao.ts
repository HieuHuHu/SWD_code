// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import { Injectable } from '@nestjs/common';
import { DataSource, EntityManager } from 'typeorm';

/** Start time of a slot as an absolute instant in Vietnam time. */
const SLOT_START = `((s.slot_date + s.start_time) AT TIME ZONE 'Asia/Ho_Chi_Minh')`;

/* ================================================================== autocare.dao.account */
@Injectable()
export class AccountDao {
  constructor(private readonly ds: DataSource) {}

  async findLoginByEmailOrPhone(login: string) {
    const rows = await this.ds.query(
      `SELECT u.user_id::int AS "userId", u.email, u.phone, u.password_hash AS "passwordHash", u.full_name AS "fullName", u.status,
              u.failed_login_count AS "failedLoginCount", u.locked_until AS "lockedUntil", r.role_code AS role,
              s.staff_id::int AS "staffId", s.branch_id::int AS "branchId", b.branch_name AS "branchName", c.customer_id::int AS "customerId"
       FROM users u JOIN roles r ON r.role_id = u.role_id
       LEFT JOIN staff s ON s.user_id = u.user_id LEFT JOIN branches b ON b.branch_id = s.branch_id
       LEFT JOIN customers c ON c.user_id = u.user_id
       WHERE LOWER(u.email) = LOWER($1) OR u.phone = $1`, [login.trim()]);
    return rows[0] ?? null;
  }

  async emailOrPhoneTaken(m: EntityManager, email: string, phone: string) {
    const [r] = await m.query(
      `SELECT EXISTS (SELECT 1 FROM users WHERE LOWER(email) = LOWER($1)) AS email,
              EXISTS (SELECT 1 FROM users WHERE phone = $2) AS phone`, [email, phone]);
    return r as { email: boolean; phone: boolean };
  }

  async customerRoleId(m: EntityManager): Promise<number> {
    const [r] = await m.query(`SELECT role_id::int AS id FROM roles WHERE role_code = 'CUSTOMER'`);
    return r.id;
  }

  myNotifications(userId: number) {
    return this.ds.query(
      `SELECT notification_id::int AS id, title, content, reference_type AS "referenceType", reference_id::int AS "referenceId",
              status, created_at AS "createdAt"
       FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 20`, [userId]);
  }

  /** 13.A1 – receptionist looks up a walk-in / calling customer by phone or email. */
  findCustomers(keyword: string) {
    return this.ds.query(
      `SELECT c.customer_id::int AS id, u.full_name AS "fullName", u.phone, u.email
       FROM customers c JOIN users u ON u.user_id = c.user_id
       WHERE u.status = 'ACTIVE' AND (u.phone LIKE $1 OR LOWER(u.email) LIKE LOWER($1) OR LOWER(u.full_name) LIKE LOWER($1))
       ORDER BY u.full_name LIMIT 10`, [`%${keyword.trim()}%`]);
  }
}

/* ================================================================== autocare.dao.vehicle */
@Injectable()
export class VehicleDao {
  constructor(private readonly ds: DataSource) {}

  vehiclesOfCustomer(customerId: number) {
    return this.ds.query(
      `SELECT v.vehicle_id::int AS id, v.license_plate AS "licensePlate", v.vehicle_type AS "vehicleType", v.brand, v.model,
              v.manufacture_year AS "manufactureYear", v.vin, v.color, v.current_odometer AS "currentOdometer", v.status,
              v.created_at AS "createdAt",
              (SELECT COUNT(*)::int FROM appointments a WHERE a.vehicle_id = v.vehicle_id) AS "appointmentCount",
              (SELECT a.appointment_code FROM appointments a WHERE a.vehicle_id = v.vehicle_id
                 AND a.status IN ('PENDING','CONFIRMED','CHECKED_IN','IN_SERVICE','WAITING_PAYMENT') ORDER BY a.created_at DESC LIMIT 1) AS "openAppointment"
       FROM vehicles v WHERE v.customer_id = $1 ORDER BY v.status, v.created_at DESC`, [customerId]);
  }

  async plateTaken(m: EntityManager, plate: string) {
    const [r] = await m.query(`SELECT EXISTS (SELECT 1 FROM vehicles WHERE UPPER(license_plate) = UPPER($1)) AS taken`, [plate]);
    return r.taken as boolean;
  }

  async vinTaken(m: EntityManager, vin: string) {
    const [r] = await m.query(`SELECT EXISTS (SELECT 1 FROM vehicles WHERE UPPER(vin) = UPPER($1)) AS taken`, [vin]);
    return r.taken as boolean;
  }
}

/* ================================================================== autocare.dao.appointment */
@Injectable()
export class CatalogDao {
  constructor(private readonly ds: DataSource) {}

  branches() {
    return this.ds.query(
      `SELECT branch_id::int AS id, branch_code AS code, branch_name AS name, address, phone
       FROM branches WHERE status = 'ACTIVE' ORDER BY branch_id`);
  }

  async branch(id: number) {
    const [b] = await this.ds.query(`SELECT branch_id::int AS id, branch_name AS name, status FROM branches WHERE branch_id = $1`, [id]);
    return b ?? null;
  }

  /** UC10 – active services enabled at the branch, optionally only those applicable to a vehicle type. */
  servicesOfBranch(branchId: number, vehicleType?: string | null, m?: EntityManager) {
    return (m ?? this.ds.manager).query(
      `SELECT s.service_id::int AS id, s.service_code AS code, s.service_name AS name, s.description,
              s.vehicle_type AS "vehicleType", COALESCE(bs.branch_price, s.base_price)::float8 AS price,
              s.estimated_minutes AS "estimatedMinutes"
       FROM services s JOIN branch_services bs ON bs.service_id = s.service_id
       WHERE bs.branch_id = $1 AND bs.is_enabled AND s.status = 'ACTIVE'
         AND ($2::varchar IS NULL OR s.vehicle_type IN ('ALL', $2))
       ORDER BY s.service_name`, [branchId, vehicleType ?? null]);
  }

  /** UC12 – slots of a branch on a date with capacity status. */
  slots(branchId: number, date: string) {
    return this.ds.query(
      `SELECT s.slot_id::int AS id, to_char(s.start_time, 'HH24:MI') AS "startTime", to_char(s.end_time, 'HH24:MI') AS "endTime",
              s.capacity, s.booked_count AS "bookedCount", s.status,
              (s.status = 'OPEN' AND s.booked_count < s.capacity AND ${SLOT_START} > NOW()) AS available,
              (${SLOT_START} <= NOW()) AS past
       FROM time_slots s WHERE s.branch_id = $1 AND s.slot_date = $2::date ORDER BY s.start_time`, [branchId, date]);
  }

  async slotIsFuture(m: EntityManager, slotId: number): Promise<boolean> {
    const [r] = await m.query(`SELECT ${SLOT_START} > NOW() AS ok FROM time_slots s WHERE s.slot_id = $1`, [slotId]);
    return !!r?.ok;
  }
}

@Injectable()
export class AppointmentDao {
  constructor(private readonly ds: DataSource) {}

  list(f: { customerId?: number | null; branchId?: number | null; date?: string | null; id?: number | null }) {
    return this.ds.query(
      `SELECT a.appointment_id::int AS id, a.appointment_code AS code, a.status, a.customer_note AS note, a.created_at AS "createdAt",
              to_char(s.slot_date, 'YYYY-MM-DD') AS date, to_char(s.start_time, 'HH24:MI') AS "startTime", to_char(s.end_time, 'HH24:MI') AS "endTime",
              b.branch_id::int AS "branchId", b.branch_name AS "branchName", b.address AS "branchAddress",
              v.license_plate AS "licensePlate", v.brand || ' ' || v.model AS vehicle, u.full_name AS "customerName", u.phone AS "customerPhone",
              (SELECT json_agg(json_build_object('name', sv.service_name, 'price', aps.estimated_price::float8) ORDER BY sv.service_name)
                 FROM appointment_services aps JOIN services sv ON sv.service_id = aps.service_id WHERE aps.appointment_id = a.appointment_id) AS services,
              (SELECT COALESCE(SUM(aps.estimated_price), 0)::float8 FROM appointment_services aps WHERE aps.appointment_id = a.appointment_id) AS "estimatedTotal"
       FROM appointments a JOIN time_slots s ON s.slot_id = a.slot_id JOIN branches b ON b.branch_id = a.branch_id
       JOIN vehicles v ON v.vehicle_id = a.vehicle_id JOIN customers c ON c.customer_id = a.customer_id JOIN users u ON u.user_id = c.user_id
       WHERE ($1::bigint IS NULL OR a.customer_id = $1) AND ($2::bigint IS NULL OR a.branch_id = $2)
         AND ($3::date IS NULL OR s.slot_date = $3) AND ($4::bigint IS NULL OR a.appointment_id = $4)
       ORDER BY s.slot_date DESC, s.start_time DESC`,
      [f.customerId ?? null, f.branchId ?? null, f.date ?? null, f.id ?? null]);
  }

  /** a vehicle may have only one open appointment per day */
  async vehicleBookedThatDay(m: EntityManager, vehicleId: number, slotDate: string) {
    const [r] = await m.query(
      `SELECT a.appointment_code AS code FROM appointments a JOIN time_slots s ON s.slot_id = a.slot_id
       WHERE a.vehicle_id = $1 AND s.slot_date = $2::date AND a.status NOT IN ('CANCELLED','REJECTED','COMPLETED') LIMIT 1`, [vehicleId, slotDate]);
    return (r?.code as string | undefined) ?? null;
  }

  async staffUserIds(m: EntityManager, branchId: number, positions: string[]): Promise<number[]> {
    const rows = await m.query(`SELECT user_id::int AS id FROM staff WHERE branch_id = $1 AND position = ANY($2) AND status = 'ACTIVE'`, [branchId, positions]);
    return rows.map((r: { id: number }) => r.id);
  }

  async userIdOfCustomer(m: EntityManager, customerId: number): Promise<number> {
    const [r] = await m.query(`SELECT user_id::int AS id FROM customers WHERE customer_id = $1`, [customerId]);
    return r?.id;
  }
}
