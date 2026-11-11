// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import { Body, Controller, Get, HttpCode, Param, ParseIntPipe, Post, Query, UseGuards } from '@nestjs/common';
import { AuthUser, CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../common/security/security';
import { CreateAppointmentDto, CreateVehicleDto, LoginDto, RegisterDto } from '../dto/dto';
import { AuthService } from '../service/account/auth.service';
import { AppointmentService } from '../service/appointment/appointment.service';
import { VehicleService } from '../service/vehicle/vehicle.service';

/* ------------------------------------------------------------------ autocare.controller.account */
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  /** UC01 – Register Account */
  @Post('register')
  register(@Body() dto: RegisterDto) { return this.auth.register(dto); }

  /** UC02 – Login */
  @Post('login') @HttpCode(200)
  login(@Body() dto: LoginDto) { return this.auth.login(dto); }

  @Get('me') @UseGuards(JwtAuthGuard)
  me(@CurrentUser() user: AuthUser) { return user; }

  @Get('notifications') @UseGuards(JwtAuthGuard)
  notifications(@CurrentUser() user: AuthUser) { return this.auth.notifications(user); }
}

/* ------------------------------------------------------------------ autocare.controller.vehicle */
@Controller('vehicles')
@UseGuards(JwtAuthGuard, RolesGuard)
export class VehicleController {
  constructor(private readonly vehicles: VehicleService) {}

  @Get('mine') @Roles('CUSTOMER')
  mine(@CurrentUser() u: AuthUser) { return this.vehicles.myVehicles(u); }

  /** UC05 – Add Vehicle */
  @Post() @Roles('CUSTOMER')
  add(@CurrentUser() u: AuthUser, @Body() dto: CreateVehicleDto) { return this.vehicles.add(u, dto); }
}

/* ------------------------------------------------------------------ autocare.controller.appointment (public catalog) */
@Controller('branches')
export class CatalogController {
  constructor(private readonly appointments: AppointmentService) {}

  @Get()
  branches() { return this.appointments.branches(); }

  /** UC10 – View Service List (public: no login needed to browse) */
  @Get(':id/services')
  services(@Param('id', ParseIntPipe) id: number, @Query('vehicleType') vehicleType?: string) {
    return this.appointments.services(id, vehicleType || undefined);
  }

  /** UC12 – available time slots, used by the booking flow of UC13 */
  @Get(':id/slots')
  slots(@Param('id', ParseIntPipe) id: number, @Query('date') date: string) { return this.appointments.slots(id, date); }
}

@Controller('appointments')
@UseGuards(JwtAuthGuard, RolesGuard)
export class AppointmentController {
  constructor(private readonly appointments: AppointmentService) {}

  /** UC13 – Create Service Appointment (customer, or receptionist on behalf of a customer – 13.A1) */
  @Post() @Roles('CUSTOMER', 'RECEPTIONIST')
  create(@CurrentUser() u: AuthUser, @Body() dto: CreateAppointmentDto) { return this.appointments.create(u, dto); }

  @Get('mine') @Roles('CUSTOMER')
  mine(@CurrentUser() u: AuthUser) { return this.appointments.myAppointments(u); }

  @Get() @Roles('RECEPTIONIST', 'BRANCH_MANAGER')
  branch(@CurrentUser() u: AuthUser, @Query('date') date?: string) { return this.appointments.branchAppointments(u, date); }
}

@Controller('customers')
@UseGuards(JwtAuthGuard, RolesGuard)
export class CustomerLookupController {
  constructor(private readonly appointments: AppointmentService, private readonly vehicles: VehicleService) {}

  @Get() @Roles('RECEPTIONIST')
  find(@Query('q') q: string) { return this.appointments.findCustomers(q); }

  @Get(':id/vehicles') @Roles('RECEPTIONIST')
  vehiclesOf(@Param('id', ParseIntPipe) id: number) { return this.vehicles.vehiclesOfCustomer(id); }
}
