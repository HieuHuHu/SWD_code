import { Column, Entity, PrimaryColumn } from 'typeorm';
import { numeric } from './columns';

/* ------------------------------------------------------------------ enumerations */
export type RoleCode = 'CUSTOMER' | 'RECEPTIONIST' | 'MECHANIC' | 'CASHIER' | 'BRANCH_MANAGER' | 'SYS_ADMIN';
export type VehicleType = 'MOTORCYCLE' | 'CAR';
export type AppointmentStatus =
  | 'PENDING' | 'CONFIRMED' | 'REJECTED' | 'CHECKED_IN' | 'IN_SERVICE' | 'WAITING_PAYMENT' | 'COMPLETED' | 'CANCELLED';

const id = (name: string) =>
  PrimaryColumn({ name, type: 'bigint', generated: 'identity', generatedIdentity: 'ALWAYS', transformer: numeric });
const big = (name: string, nullable = false) => Column({ name, type: 'bigint', nullable, transformer: numeric });

/* ------------------------------------------------------------------ account (UC01, UC02) */
@Entity('users')
export class User {
  @id('user_id') userId: number;
  @Column({ name: 'role_id', type: 'smallint' }) roleId: number;
  @Column() email: string;
  @Column({ type: 'varchar', nullable: true }) phone: string | null;
  @Column({ name: 'password_hash' }) passwordHash: string;
  @Column({ name: 'full_name' }) fullName: string;
  @Column() status: 'ACTIVE' | 'LOCKED' | 'INACTIVE';
  @Column({ name: 'failed_login_count', type: 'smallint' }) failedLoginCount: number;
  @Column({ name: 'locked_until', type: 'timestamptz', nullable: true }) lockedUntil: Date | null;
  @Column({ name: 'last_login_at', type: 'timestamptz', nullable: true }) lastLoginAt: Date | null;
  @Column({ name: 'updated_at', type: 'timestamptz' }) updatedAt: Date;
}

@Entity('customers')
export class Customer {
  @id('customer_id') customerId: number;
  @big('user_id') userId: number;
  @Column({ type: 'varchar', nullable: true }) address: string | null;
}

/* ------------------------------------------------------------------ vehicle (UC05) */
@Entity('vehicles')
export class Vehicle {
  @id('vehicle_id') vehicleId: number;
  @big('customer_id') customerId: number;
  @Column({ name: 'license_plate' }) licensePlate: string;
  @Column({ name: 'vehicle_type', type: 'varchar' }) vehicleType: VehicleType;
  @Column() brand: string;
  @Column() model: string;
  @Column({ name: 'manufacture_year', type: 'smallint', nullable: true }) manufactureYear: number | null;
  @Column({ type: 'varchar', nullable: true }) vin: string | null;
  @Column({ type: 'varchar', nullable: true }) color: string | null;
  @Column({ name: 'current_odometer', type: 'int' }) currentOdometer: number;
  @Column() status: 'ACTIVE' | 'INACTIVE';
}

/* ------------------------------------------------------------------ appointment (UC10, UC12, UC13) */
@Entity('time_slots')
export class TimeSlot {
  @id('slot_id') slotId: number;
  @big('branch_id') branchId: number;
  @Column({ name: 'slot_date', type: 'date' }) slotDate: string;
  @Column({ name: 'start_time', type: 'time' }) startTime: string;
  @Column({ name: 'end_time', type: 'time' }) endTime: string;
  @Column({ type: 'smallint' }) capacity: number;
  @Column({ name: 'booked_count', type: 'smallint' }) bookedCount: number;
  @Column() status: 'OPEN' | 'CLOSED';
}

@Entity('appointments')
export class Appointment {
  @id('appointment_id') appointmentId: number;
  @Column({ name: 'appointment_code' }) appointmentCode: string;
  @big('customer_id') customerId: number;
  @big('vehicle_id') vehicleId: number;
  @big('branch_id') branchId: number;
  @big('slot_id') slotId: number;
  @Column({ type: 'varchar' }) status: AppointmentStatus;
  @Column({ name: 'customer_note', type: 'varchar', nullable: true }) customerNote: string | null;
}

@Entity('appointment_services')
export class AppointmentServiceLine {
  @PrimaryColumn({ name: 'appointment_id', type: 'bigint', transformer: numeric }) appointmentId: number;
  @PrimaryColumn({ name: 'service_id', type: 'bigint', transformer: numeric }) serviceId: number;
  @Column({ name: 'estimated_price', type: 'numeric', transformer: numeric }) estimatedPrice: number;
}

/* ------------------------------------------------------------------ cross-cutting */
@Entity('notifications')
export class Notification {
  @id('notification_id') notificationId: number;
  @big('user_id') userId: number;
  @Column() channel: string;
  @Column() title: string;
  @Column() content: string;
  @Column({ name: 'reference_type', type: 'varchar', nullable: true }) referenceType: string | null;
  @big('reference_id', true) referenceId: number | null;
  @Column() status: string;
  @Column({ name: 'sent_at', type: 'timestamptz', nullable: true }) sentAt: Date | null;
}

@Entity('audit_logs')
export class AuditLog {
  @id('audit_id') auditId: number;
  @big('user_id', true) userId: number | null;
  @Column() action: string;
  @Column({ name: 'entity_name' }) entityName: string;
  @big('entity_id') entityId: number;
  @Column({ name: 'new_value', type: 'jsonb', nullable: true }) newValue: object | null;
}

export const ENTITIES = [User, Customer, Vehicle, TimeSlot, Appointment, AppointmentServiceLine, Notification, AuditLog];
