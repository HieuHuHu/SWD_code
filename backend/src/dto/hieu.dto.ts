// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import { Transform, Type } from 'class-transformer';
import {
  IsBoolean, IsDateString, IsIn, IsInt, IsNotEmpty, IsNumber, IsOptional, IsString, Max, MaxLength, Min, MinLength,
} from 'class-validator';

const trim = () => Transform(({ value }) => (typeof value === 'string' ? value.trim() : value));

/* ================================================================ UC41 Adjust Inventory */
export class AdjustInventoryDto {
  @Type(() => Number) @IsInt({ message: 'inventoryId phải là số nguyên' })
  inventoryId: number;

  @Type(() => Number) @IsInt({ message: 'Số lượng thực tế kiểm kê phải là số nguyên' })
  @Min(0, { message: 'Số lượng thực tế không được âm' })
  actualQuantity: number;

  @trim() @IsString() @MinLength(3, { message: 'Lý do kiểm kê điều chỉnh tối thiểu 3 ký tự' }) @MaxLength(255)
  reason: string;
}

/* ================================================================ UC42 Inter-branch Transfer */
export class CreateTransferDto {
  @Type(() => Number) @IsInt()
  fromWarehouseId: number;

  @Type(() => Number) @IsInt()
  toWarehouseId: number;

  @Type(() => Number) @IsInt()
  partId: number;

  @Type(() => Number) @IsInt() @Min(1, { message: 'Số lượng điều chuyển tối thiểu là 1' })
  quantity: number;

  @IsOptional() @trim() @IsString() @MaxLength(255)
  note?: string;
}

/* ================================================================ UC43 Warranty Policy */
export class CreateWarrantyPolicyDto {
  @trim() @IsString() @MinLength(2) @MaxLength(20)
  policyCode: string;

  @trim() @IsString() @MinLength(3) @MaxLength(150)
  policyName: string;

  @IsIn(['SERVICE', 'PART'], { message: 'appliesTo phải là SERVICE hoặc PART' })
  appliesTo: 'SERVICE' | 'PART';

  @IsOptional() @Type(() => Number) @IsInt()
  serviceId?: number;

  @IsOptional() @Type(() => Number) @IsInt()
  partId?: number;

  @Type(() => Number) @IsInt() @Min(1, { message: 'Thời hạn bảo hành tối thiểu 1 tháng' })
  durationMonths: number;

  @IsOptional() @Type(() => Number) @IsInt() @Min(100)
  maxOdometerKm?: number;

  @trim() @IsString() @MinLength(5, { message: 'Điều khoản bảo hành tối thiểu 5 ký tự' })
  terms: string;
}

/* ================================================================ UC45 Warranty Claim / Request */
export class CreateWarrantyClaimDto {
  @Type(() => Number) @IsInt({ message: 'warrantyId phải là số' })
  warrantyId: number;

  @Type(() => Number) @IsInt({ message: 'branchId phải là số' })
  branchId: number;

  @trim() @IsString() @MinLength(5, { message: 'Mô tả hiện tượng lỗi tối thiểu 5 ký tự' })
  issueDescription: string;

  @Type(() => Number) @IsInt({ message: 'Số km hiện tại (ODO) phải là số nguyên' }) @Min(0)
  currentOdometer: number;
}

/* ================================================================ UC46 Assess Warranty */
export class AssessWarrantyDto {
  @IsBoolean({ message: 'isEligible phải là true (đủ điều kiện) hoặc false (từ chối)' })
  isEligible: boolean;

  @trim() @IsString() @MinLength(3, { message: 'Ghi chú đánh giá kỹ thuật tối thiểu 3 ký tự' })
  assessmentNote: string;
}

/* ================================================================ UC47 Approve Warranty */
export class ApproveWarrantyDto {
  @IsIn(['APPROVED', 'REJECTED'], { message: 'Quyết định phải là APPROVED hoặc REJECTED' })
  decision: 'APPROVED' | 'REJECTED';

  @IsOptional() @trim() @IsString()
  reason?: string;
}

/* ================================================================ UC48 Warranty Repair Order */
export class CreateWarrantyRepairDto {
  @Type(() => Number) @IsInt()
  requestId: number;

  @Type(() => Number) @IsInt()
  repairOrderId: number;

  @Type(() => Number) @IsNumber() @Min(0)
  internalCost: number;

  @Type(() => Number) @IsNumber() @Min(0)
  customerCharge: number; // Mặc định = 0 theo BR_WAR_3
}

/* ================================================================ UC51 Configure Tax Rule */
export class CreateTaxRuleDto {
  @IsIn(['SERVICE', 'PART'])
  itemType: 'SERVICE' | 'PART';

  @Type(() => Number) @IsNumber() @Min(0) @Max(100, { message: 'Thuế suất VAT từ 0% đến 100%' })
  vatRate: number;

  @IsDateString({}, { message: 'Ngày hiệu lực định dạng YYYY-MM-DD' })
  effectiveFrom: string;

  @IsOptional() @IsDateString({}, { message: 'Ngày kết thúc định dạng YYYY-MM-DD' })
  effectiveTo?: string;
}

/* ================================================================ UC52 Finalize Charges */
export class FinalizeChargesDto {
  @Type(() => Number) @IsInt({ message: 'repairOrderId phải là số' })
  repairOrderId: number;

  @IsOptional() @Type(() => Number) @IsNumber() @Min(0)
  discountAmount?: number;

  @IsOptional() @Type(() => Number) @IsInt()
  billingId?: number;
}
