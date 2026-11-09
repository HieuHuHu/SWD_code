import { ConflictException, ForbiddenException, Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { AuthUser } from '../../common/security/security';
import { VehicleDao } from '../../dao/dao';
import { CreateVehicleDto } from '../../dto/dto';
import { Vehicle } from '../../model/entities';
import { NotificationService } from '../common/notification.service';

@Injectable()
export class VehicleService {
  constructor(private readonly ds: DataSource, private readonly dao: VehicleDao, private readonly notifier: NotificationService) {}

  /** BR6 – a customer only sees the vehicles of their own account */
  myVehicles(user: AuthUser) {
    return this.dao.vehiclesOfCustomer(this.customerOf(user));
  }

  vehiclesOfCustomer(customerId: number) {
    return this.dao.vehiclesOfCustomer(customerId);
  }

  /* ================================================================ UC05 Add Vehicle */
  async add(user: AuthUser, dto: CreateVehicleDto) {
    const customerId = this.customerOf(user);
    const vehicleId = await this.ds.transaction(async (m) => {
      if (await this.dao.plateTaken(m, dto.licensePlate)) {                                                 // 05.E1
        throw new ConflictException(`Biển số ${dto.licensePlate} đã được đăng ký trong hệ thống`);
      }
      if (dto.vin && (await this.dao.vinTaken(m, dto.vin))) throw new ConflictException(`Số VIN ${dto.vin} đã tồn tại`);
      const v = await m.getRepository(Vehicle).save(m.getRepository(Vehicle).create({
        customerId, licensePlate: dto.licensePlate, vehicleType: dto.vehicleType, brand: dto.brand, model: dto.model,
        manufactureYear: dto.manufactureYear ?? null, vin: dto.vin ?? null, color: dto.color || null, currentOdometer: dto.currentOdometer, status: 'ACTIVE',
      }));
      await this.notifier.audit(m, user.userId, 'VEHICLE_ADDED', 'vehicles', v.vehicleId, { licensePlate: v.licensePlate });
      return v.vehicleId;
    });
    const list = await this.dao.vehiclesOfCustomer(customerId);
    return { vehicle: list.find((v: { id: number }) => v.id === vehicleId), vehicles: list };
  }

  private customerOf(user: AuthUser): number {
    if (!user.customerId) throw new ForbiddenException('Chức năng chỉ dành cho tài khoản khách hàng');
    return user.customerId;
  }
}
