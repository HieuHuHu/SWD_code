import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { AuthUser, assertSameBranch } from '../../common/security/security';
import { AccountDao, AppointmentDao, CatalogDao } from '../../dao/dao';
import { CreateAppointmentDto } from '../../dto/dto';
import { Appointment, AppointmentServiceLine, TimeSlot, Vehicle } from '../../model/entities';
import { NotificationService } from '../common/notification.service';

const DATE = /^\d{4}-\d{2}-\d{2}$/;

@Injectable()
export class AppointmentService {
  constructor(
    private readonly ds: DataSource,
    private readonly catalog: CatalogDao,
    private readonly dao: AppointmentDao,
    private readonly accounts: AccountDao,
    private readonly notifier: NotificationService,
  ) {}

  /* ================================================================ UC10 View Service List */
  branches() {
    return this.catalog.branches();
  }

  async services(branchId: number, vehicleType?: string) {
    const b = await this.catalog.branch(branchId);
    if (!b || b.status !== 'ACTIVE') throw new NotFoundException('Chi nhánh không tồn tại hoặc đã ngừng hoạt động');
    if (vehicleType && !['CAR', 'MOTORCYCLE'].includes(vehicleType)) throw new BadRequestException('Loại xe không hợp lệ');
    return this.catalog.servicesOfBranch(branchId, vehicleType ?? null);
  }

  /* ================================================================ UC12 View Available Time Slots (used by UC13) */
  async slots(branchId: number, date: string) {
    if (!DATE.test(date ?? '')) throw new BadRequestException('Ngày phải có dạng YYYY-MM-DD');
    const slots = await this.catalog.slots(branchId, date);
    const anyAvailable = slots.some((s: { available: boolean }) => s.available);
    return {
      date, slots,
      message: slots.length === 0 ? 'Chi nhánh chưa mở lịch cho ngày này, vui lòng chọn ngày khác'
        : anyAvailable ? null : 'Tất cả khung giờ trong ngày đã kín, vui lòng chọn ngày khác',     // 12.E1
    };
  }

  /* ================================================================ UC13 Create Service Appointment */
  async create(user: AuthUser, dto: CreateAppointmentDto) {
    let customerId: number;
    if (user.role === 'CUSTOMER') {
      if (!user.customerId) throw new ForbiddenException('Không xác định được khách hàng');
      if (dto.customerId && dto.customerId !== user.customerId) throw new ForbiddenException('Không thể đặt lịch cho khách hàng khác');
      customerId = user.customerId;
    } else {                                                                                                  // 13.A1 receptionist
      if (!dto.customerId) throw new BadRequestException('Chọn khách hàng cần đặt lịch hộ');
      assertSameBranch(user, dto.branchId);
      customerId = dto.customerId;
    }

    const appointmentId = await this.ds.transaction(async (m) => {
      const vehicle = await m.getRepository(Vehicle).findOneBy({ vehicleId: dto.vehicleId });
      if (!vehicle || vehicle.customerId !== customerId) throw new ForbiddenException('Xe không thuộc tài khoản khách hàng');   // BR6
      if (vehicle.status !== 'ACTIVE') throw new ConflictException('Xe đã ngừng hoạt động, không thể đặt lịch');               // BR8

      const offered = await this.catalog.servicesOfBranch(dto.branchId, vehicle.vehicleType, m);
      const chosen = dto.serviceIds.map((id) => offered.find((s: { id: number }) => s.id === id));
      if (chosen.some((s) => !s)) throw new BadRequestException('Có dịch vụ không được chi nhánh cung cấp hoặc không áp dụng cho loại xe này');

      // ---- final locked capacity check (BR9, BR10, NFR-4) – the slot row is locked until commit
      const slotRepo = m.getRepository(TimeSlot);
      const slot = await slotRepo.findOne({ where: { slotId: dto.slotId }, lock: { mode: 'pessimistic_write' } });
      if (!slot || slot.branchId !== dto.branchId) throw new BadRequestException('Khung giờ không thuộc chi nhánh đã chọn');
      if (slot.status !== 'OPEN' || !(await this.catalog.slotIsFuture(m, slot.slotId))) throw new ConflictException('Khung giờ đã đóng hoặc đã qua');
      if (slot.bookedCount >= slot.capacity) {
        throw new ConflictException('Khung giờ vừa hết chỗ, vui lòng chọn khung giờ khác');                                   // 13.E1
      }
      const existing = await this.dao.vehicleBookedThatDay(m, vehicle.vehicleId, slot.slotDate);
      if (existing) throw new ConflictException(`Xe ${vehicle.licensePlate} đã có lịch hẹn ${existing} trong ngày này`);

      slot.bookedCount += 1;
      await slotRepo.save(slot);
      const code = await nextCodeForDate(m, slot.slotDate);
      const ap = await m.getRepository(Appointment).save(m.getRepository(Appointment).create({
        appointmentCode: code, customerId, vehicleId: vehicle.vehicleId, branchId: dto.branchId, slotId: slot.slotId,
        status: 'PENDING', customerNote: dto.note || null,                                                                       // BR11
      }));
      await m.getRepository(AppointmentServiceLine).insert(
        chosen.map((s) => ({ appointmentId: ap.appointmentId, serviceId: s.id, estimatedPrice: s.price })));

      const when = `${slot.startTime.slice(0, 5)} ngày ${slot.slotDate.split('-').reverse().join('/')}`;
      const receptionists = await this.dao.staffUserIds(m, dto.branchId, ['RECEPTIONIST']);
      await this.notifier.notify(m, receptionists, 'Lịch hẹn mới chờ xác nhận', `${code} – xe ${vehicle.licensePlate}, ${when}`, 'APPOINTMENT', ap.appointmentId);
      await this.notifier.notify(m, [await this.dao.userIdOfCustomer(m, customerId)], 'Đặt lịch thành công',
        `Lịch hẹn ${code} lúc ${when} đang chờ chi nhánh xác nhận.`, 'APPOINTMENT', ap.appointmentId);
      await this.notifier.audit(m, user.userId, 'APPOINTMENT_CREATED', 'appointments', ap.appointmentId,
        { slotId: slot.slotId, serviceIds: dto.serviceIds, byReceptionist: user.role !== 'CUSTOMER' });
      return ap.appointmentId;
    });
    const [created] = await this.dao.list({ id: appointmentId });
    return created;
  }

  myAppointments(user: AuthUser) {
    if (!user.customerId) throw new ForbiddenException('Chức năng chỉ dành cho khách hàng');
    return this.dao.list({ customerId: user.customerId });
  }

  branchAppointments(user: AuthUser, date?: string) {
    if (date && !DATE.test(date)) throw new BadRequestException('Ngày phải có dạng YYYY-MM-DD');
    return this.dao.list({ branchId: user.role === 'SYS_ADMIN' ? null : user.branchId, date: date || null });
  }

  findCustomers(keyword: string) {
    if (!keyword || keyword.trim().length < 3) throw new BadRequestException('Nhập ít nhất 3 ký tự để tìm khách hàng');
    return this.accounts.findCustomers(keyword);
  }
}

/** APT-yymmdd-nnnn where yymmdd is the appointment (slot) date, consistent with the seed data. */
async function nextCodeForDate(m: import('typeorm').EntityManager, slotDate: string) {
  const ymd = slotDate.replace(/-/g, '').slice(2);
  const [{ max }] = await m.query(
    `SELECT COALESCE(MAX(CAST(SPLIT_PART(appointment_code, '-', 3) AS INT)), 0) AS max FROM appointments WHERE appointment_code LIKE $1`, [`APT-${ymd}-%`]);
  return `APT-${ymd}-${String(Number(max) + 1).padStart(4, '0')}`;
}
