import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtAuthGuard, RolesGuard } from './common/security/security';
import { config } from './config/app.config';
import {
  AppointmentController,
  AuthController,
  CatalogController,
  CustomerLookupController,
  VehicleController,
} from './controller/controllers';
import { BillingController, InventoryController, WarrantyController } from './controller/hieu.controller';
import { AccountDao, AppointmentDao, CatalogDao, VehicleDao } from './dao/dao';
import { BillingDao, InventoryDao, WarrantyDao } from './dao/hieu.dao';
import { ENTITIES } from './model/entities';
import { AuthService } from './service/account/auth.service';
import { AppointmentService } from './service/appointment/appointment.service';
import { BillingService } from './service/billing/billing.service';
import { NotificationService } from './service/common/notification.service';
import { InventoryService } from './service/inventory/inventory.service';
import { VehicleService } from './service/vehicle/vehicle.service';
import { WarrantyService } from './service/warranty/warranty.service';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: config.db.host,
      port: config.db.port,
      username: config.db.user,
      password: config.db.password,
      database: config.db.name,
      entities: ENTITIES,
      synchronize: false, // schema is owned by database/export/autocare_full.sql
      extra: { max: 20 },
    }),
    JwtModule.register({
      global: true,
      secret: config.jwt.secret,
      signOptions: { expiresIn: config.jwt.expiresIn as any },
    }),
  ],
  controllers: [
    AuthController,
    VehicleController,
    CatalogController,
    AppointmentController,
    CustomerLookupController,
    // Phân hệ UC40 - UC52 (Hiếu)
    InventoryController,
    WarrantyController,
    BillingController,
  ],
  providers: [
    JwtAuthGuard,
    RolesGuard,
    // DAOs
    AccountDao,
    VehicleDao,
    CatalogDao,
    AppointmentDao,
    InventoryDao,
    WarrantyDao,
    BillingDao,
    // Services
    NotificationService,
    AuthService,
    VehicleService,
    AppointmentService,
    InventoryService,
    WarrantyService,
    BillingService,
  ],
})
export class AppModule {}
