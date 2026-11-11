// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthUser, CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../common/security/security';
import {
  AdjustInventoryDto,
  ApproveWarrantyDto,
  AssessWarrantyDto,
  CreateTaxRuleDto,
  CreateTransferDto,
  CreateWarrantyClaimDto,
  CreateWarrantyPolicyDto,
  CreateWarrantyRepairDto,
  FinalizeChargesDto,
} from '../dto/hieu.dto';
import { BillingService } from '../service/billing/billing.service';
import { InventoryService } from '../service/inventory/inventory.service';
import { WarrantyService } from '../service/warranty/warranty.service';

/* ================================================================== 5. KHO LINH KIỆN (UC40 - UC42) */
@Controller('inventory')
@UseGuards(JwtAuthGuard, RolesGuard)
export class InventoryController {
  constructor(private readonly inventory: InventoryService) {}

  /** UC40 – Xem lịch sử biến động kho (Lịch sử bất biến) */
  @Get('transactions')
  @Roles('RECEPTIONIST', 'BRANCH_MANAGER', 'SYS_ADMIN')
  transactions(@Query('inventoryId', ParseIntPipe) inventoryId: number) {
    return this.inventory.getHistory(inventoryId);
  }

  /** UC41 – Điều chỉnh kiểm kê tồn kho */
  @Post('adjustments')
  @HttpCode(200)
  @Roles('RECEPTIONIST', 'BRANCH_MANAGER')
  adjust(@CurrentUser() u: AuthUser, @Body() dto: AdjustInventoryDto) {
    return this.inventory.adjust(u, dto);
  }

  /** UC42 – Điều chuyển linh kiện liên chi nhánh */
  @Post('transfers')
  @Roles('RECEPTIONIST', 'BRANCH_MANAGER')
  transfer(@CurrentUser() u: AuthUser, @Body() dto: CreateTransferDto) {
    return this.inventory.transfer(u, dto);
  }
}

/* ================================================================== 6. BẢO HÀNH (UC43 - UC50) */
@Controller('warranties')
export class WarrantyController {
  constructor(private readonly warranty: WarrantyService) {}

  /** UC43 – Cấu hình chính sách bảo hành */
  @Post('policies')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('SYS_ADMIN')
  createPolicy(@CurrentUser() u: AuthUser, @Body() dto: CreateWarrantyPolicyDto) {
    return this.warranty.createPolicy(u, dto);
  }

  @Get('policies')
  listPolicies() {
    return this.warranty.listPolicies();
  }

  /** UC45 – Yêu cầu bảo hành */
  @Post('claims')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('CUSTOMER', 'RECEPTIONIST')
  createClaim(@CurrentUser() u: AuthUser, @Body() dto: CreateWarrantyClaimDto) {
    return this.warranty.createClaim(u, dto);
  }

  /** UC46 – Thợ kỹ thuật đánh giá lỗi */
  @Patch('claims/:id/assess')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('MECHANIC', 'BRANCH_MANAGER')
  assessClaim(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: AssessWarrantyDto,
  ) {
    return this.warranty.assessClaim(u, id, dto);
  }

  /** UC47 – Quản lý chi nhánh phê duyệt bảo hành */
  @Patch('claims/:id/approve')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('BRANCH_MANAGER')
  approveClaim(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ApproveWarrantyDto,
  ) {
    return this.warranty.approveClaim(u, id, dto);
  }

  /** UC48 – Phiếu sửa chữa bảo hành (0 đồng) */
  @Post('repairs')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('RECEPTIONIST', 'BRANCH_MANAGER')
  createWarrantyRepair(@CurrentUser() u: AuthUser, @Body() dto: CreateWarrantyRepairDto) {
    return this.warranty.createWarrantyRepair(u, dto);
  }

  /** UC49 – Khách hàng xem danh sách bảo hành của mình */
  @Get('mine')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('CUSTOMER')
  myWarranties(@CurrentUser() u: AuthUser) {
    return this.warranty.getMyWarranties(u);
  }

  /** UC50 – Báo cáo chi phí bảo hành */
  @Get('reports/costs')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('BRANCH_MANAGER', 'SYS_ADMIN')
  costReport(@CurrentUser() u: AuthUser, @Query('branchId') branchId?: string) {
    return this.warranty.getCostReport(u, branchId ? parseInt(branchId, 10) : undefined);
  }
}

/* ================================================================== 7. THUẾ & CHỐT PHÍ (UC51, UC52) */
@Controller('billing')
@UseGuards(JwtAuthGuard, RolesGuard)
export class BillingController {
  constructor(private readonly billing: BillingService) {}

  /** UC51 – Cấu hình quy tắc thuế GTGT */
  @Post('tax-rules')
  @Roles('SYS_ADMIN')
  createTaxRule(@CurrentUser() u: AuthUser, @Body() dto: CreateTaxRuleDto) {
    return this.billing.createTaxRule(u, dto);
  }

  @Get('tax-rules/active')
  activeTaxRules(@Query('date') date?: string) {
    return this.billing.getActiveTaxRules(date);
  }

  /** UC52 – Finalize Charges (Chốt phí & tính tiền) */
  @Post('invoices/finalize')
  @HttpCode(200)
  @Roles('CASHIER', 'BRANCH_MANAGER')
  finalize(@CurrentUser() u: AuthUser, @Body() dto: FinalizeChargesDto) {
    return this.billing.finalizeCharges(u, dto);
  }
}
