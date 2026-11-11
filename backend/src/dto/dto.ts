// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import { Transform, Type } from 'class-transformer';
import {
  ArrayMinSize, ArrayUnique, IsArray, IsEmail, IsIn, IsInt, IsNotEmpty, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength,
} from 'class-validator';

const trim = () => Transform(({ value }) => (typeof value === 'string' ? value.trim() : value));

/* ------------------------------------------------------------------ UC01 Register Account */
export class RegisterDto {
  @trim() @IsString() @MinLength(2, { message: 'Họ tên tối thiểu 2 ký tự' }) @MaxLength(150) fullName: string;
  @trim() @Matches(/^0\d{9}$/, { message: 'Số điện thoại phải gồm 10 chữ số và bắt đầu bằng 0' }) phone: string;
  @trim() @IsEmail({}, { message: 'Email không đúng định dạng' }) @MaxLength(150) email: string;
  @IsString() @MinLength(8, { message: 'Mật khẩu tối thiểu 8 ký tự' }) @MaxLength(72)
  @Matches(/^(?=.*[A-Za-z])(?=.*\d).+$/, { message: 'Mật khẩu phải có cả chữ và số' }) password: string;
  @IsString() confirmPassword: string;
}

/* ------------------------------------------------------------------ UC02 Login */
export class LoginDto {
  @trim() @IsNotEmpty({ message: 'Nhập email hoặc số điện thoại' }) login: string;
  @IsString() @IsNotEmpty({ message: 'Nhập mật khẩu' }) password: string;
}

/* ------------------------------------------------------------------ UC05 Add Vehicle */
export class CreateVehicleDto {
  @Transform(({ value }) => (typeof value === 'string' ? value.trim().toUpperCase().replace(/\s+/g, '') : value))
  @Matches(/^\d{2}[A-Z]{1,2}\d?-(\d{4}|\d{5}|\d{3}\.\d{2})$/, { message: 'Biển số không hợp lệ (ví dụ: 30A-123.45 hoặc 29B1-234.56)' })
  licensePlate: string;
  @IsIn(['CAR', 'MOTORCYCLE'], { message: 'Loại xe phải là CAR hoặc MOTORCYCLE' }) vehicleType: 'CAR' | 'MOTORCYCLE';
  @trim() @IsString() @MinLength(1, { message: 'Nhập hãng xe' }) @MaxLength(50) brand: string;
  @trim() @IsString() @MinLength(1, { message: 'Nhập dòng xe' }) @MaxLength(50) model: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1950, { message: 'Năm sản xuất từ 1950' }) @Max(new Date().getFullYear() + 1, { message: 'Năm sản xuất không hợp lệ' })
  manufactureYear?: number;
  @IsOptional() @Transform(({ value }) => (typeof value === 'string' && value.trim() ? value.trim().toUpperCase() : undefined))
  @Matches(/^[A-HJ-NPR-Z0-9]{17}$/, { message: 'Số VIN gồm 17 ký tự chữ/số (không có I, O, Q)' }) vin?: string;
  @IsOptional() @trim() @IsString() @MaxLength(30) color?: string;
  @Type(() => Number) @IsInt({ message: 'Số km phải là số nguyên' }) @Min(0) @Max(2_000_000) currentOdometer: number;
}

/* ------------------------------------------------------------------ UC13 Create Service Appointment */
export class CreateAppointmentDto {
  @Type(() => Number) @IsInt() vehicleId: number;
  @Type(() => Number) @IsInt() branchId: number;
  @Type(() => Number) @IsInt() slotId: number;
  @IsArray() @ArrayMinSize(1, { message: 'Chọn ít nhất một dịch vụ' }) @ArrayUnique() @Type(() => Number) @IsInt({ each: true }) serviceIds: number[];
  @IsOptional() @trim() @IsString() @MaxLength(500) note?: string;
  /** 13.A1 – only when a receptionist books on behalf of a customer */
  @IsOptional() @Type(() => Number) @IsInt() customerId?: number;
}
