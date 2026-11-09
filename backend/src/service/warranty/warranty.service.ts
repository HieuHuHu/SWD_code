import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { AuthUser } from '../../common/security/security';
import { WarrantyDao } from '../../dao/hieu.dao';
import {
  ApproveWarrantyDto,
  AssessWarrantyDto,
  CreateWarrantyClaimDto,
  CreateWarrantyPolicyDto,
  CreateWarrantyRepairDto,
} from '../../dto/hieu.dto';

@Injectable()
export class WarrantyService {
  constructor(
    private readonly ds: DataSource,
    private readonly dao: WarrantyDao,
  ) {}

  /** UC43 – Cấu hình chính sách bảo hành */
  async createPolicy(user: AuthUser, dto: CreateWarrantyPolicyDto) {
    if (user.role !== 'SYS_ADMIN') {
      throw new ForbiddenException('Chỉ Quản trị viên hệ thống (SYS_ADMIN) mới có quyền tạo chính sách bảo hành');
    }
    if (dto.appliesTo === 'SERVICE' && !dto.serviceId) {
      throw new BadRequestException('Chính sách cho dịch vụ cần chỉ định serviceId');
    }
    if (dto.appliesTo === 'PART' && !dto.partId) {
      throw new BadRequestException('Chính sách cho linh kiện cần chỉ định partId');
    }
    return this.dao.createPolicy(dto);
  }

  async listPolicies() {
    return this.dao.listPolicies();
  }

  /** UC44 – Tự động tạo hồ sơ bảo hành sau khi bàn giao */
  async autoGenerateWarranty(
    policyId: number,
    vehicleId: number,
    repairOrderId: number,
    startOdometer: number,
    quotationItemId?: number,
  ) {
    const policies = await this.dao.listPolicies();
    const policy = policies.find((p: any) => p.id === policyId);
    if (!policy) throw new NotFoundException('Không tìm thấy chính sách bảo hành');

    const startDate = new Date();
    const endDate = new Date();
    endDate.setMonth(endDate.getMonth() + policy.durationMonths);

    const maxOdometer = policy.maxOdometerKm ? startOdometer + policy.maxOdometerKm : undefined;
    const warrantyCode = `WAR-${Date.now().toString().slice(-8)}`;

    return this.ds.transaction(async (m) => {
      return this.dao.createWarrantyRecord(m, {
        warrantyCode,
        policyId,
        vehicleId,
        repairOrderId,
        quotationItemId,
        startDate: startDate.toISOString().slice(0, 10),
        endDate: endDate.toISOString().slice(0, 10),
        startOdometer,
        maxOdometer,
      });
    });
  }

  /** UC45 – Khách hàng hoặc Lễ tân gửi yêu cầu bảo hành */
  async createClaim(user: AuthUser, dto: CreateWarrantyClaimDto) {
    let customerId: number;
    if (user.role === 'CUSTOMER') {
      if (!user.customerId) throw new ForbiddenException('Không xác định được khách hàng');
      customerId = user.customerId;
    } else if (['RECEPTIONIST', 'BRANCH_MANAGER'].includes(user.role)) {
      // Đặt hộ khách hàng
      const w = await this.dao.getWarrantyById(dto.warrantyId);
      if (!w) throw new NotFoundException('Hồ sơ bảo hành không tồn tại');
      customerId = w.customerId;
    } else {
      throw new ForbiddenException('Không có quyền tạo yêu cầu bảo hành');
    }

    const warranty = await this.dao.getWarrantyById(dto.warrantyId);
    if (!warranty) throw new NotFoundException('Hồ sơ bảo hành không tồn tại');
    if (user.role === 'CUSTOMER' && warranty.customerId !== customerId) {
      throw new ForbiddenException('Xe và hồ sơ bảo hành không thuộc tài khoản của bạn');
    }
    if (warranty.status !== 'ACTIVE') {
      throw new ConflictException(`Hồ sơ bảo hành hiện không còn hiệu lực (trạng thái: ${warranty.status})`);
    }

    // BR_WAR_2: Kiểm tra hạn bảo hành theo thời gian và số km ODO
    const today = new Date().toISOString().slice(0, 10);
    if (today > warranty.endDate) {
      throw new BadRequestException(`Đã hết hạn bảo hành theo thời gian (hết hạn ngày: ${warranty.endDate})`);
    }
    if (warranty.maxOdometer && dto.currentOdometer > warranty.maxOdometer) {
      throw new BadRequestException(
        `Số km hiện tại (${dto.currentOdometer} km) đã vượt quá giới hạn bảo hành tối đa (${warranty.maxOdometer} km)`,
      );
    }

    const requestCode = `WREQ-${Date.now().toString().slice(-8)}`;
    return this.ds.transaction(async (m) => {
      return this.dao.createClaim(m, {
        requestCode,
        warrantyId: dto.warrantyId,
        customerId,
        branchId: dto.branchId,
        issueDescription: dto.issueDescription,
        currentOdometer: dto.currentOdometer,
      });
    });
  }

  /** UC46 – Thợ sửa xe đánh giá lỗi kỹ thuật */
  async assessClaim(user: AuthUser, requestId: number, dto: AssessWarrantyDto) {
    if (!['MECHANIC', 'BRANCH_MANAGER'].includes(user.role)) {
      throw new ForbiddenException('Chỉ thợ sửa xe hoặc quản lý mới có quyền đánh giá lỗi bảo hành');
    }
    const claim = await this.dao.getClaimById(requestId);
    if (!claim) throw new NotFoundException('Yêu cầu bảo hành không tồn tại');
    if (claim.status !== 'SUBMITTED') {
      throw new BadRequestException(`Chỉ yêu cầu ở trạng thái SUBMITTED mới được đánh giá (hiện tại: ${claim.status})`);
    }

    return this.dao.assessClaim(requestId, dto.isEligible, dto.assessmentNote, user.staffId!);
  }

  /** UC47 – Quản lý chi nhánh phê duyệt yêu cầu bảo hành */
  async approveClaim(user: AuthUser, requestId: number, dto: ApproveWarrantyDto) {
    if (user.role !== 'BRANCH_MANAGER') {
      throw new ForbiddenException('Chỉ Quản lý chi nhánh (BRANCH_MANAGER) mới có thẩm quyền duyệt bảo hành');
    }
    const claim = await this.dao.getClaimById(requestId);
    if (!claim) throw new NotFoundException('Yêu cầu bảo hành không tồn tại');
    if (claim.status !== 'ASSESSED') {
      throw new BadRequestException('Yêu cầu bảo hành cần được thợ đánh giá kỹ thuật trước khi duyệt');
    }

    return this.dao.approveClaim(requestId, dto.decision, user.staffId!);
  }

  /** UC48 – Lập phiếu sửa chữa bảo hành (customer_charge = 0 theo BR_WAR_3) */
  async createWarrantyRepair(user: AuthUser, dto: CreateWarrantyRepairDto) {
    if (!['RECEPTIONIST', 'BRANCH_MANAGER'].includes(user.role)) {
      throw new ForbiddenException('Không có quyền tạo phiếu sửa chữa bảo hành');
    }
    const claim = await this.dao.getClaimById(dto.requestId);
    if (!claim) throw new NotFoundException('Yêu cầu bảo hành không tồn tại');
    if (claim.status !== 'APPROVED') {
      throw new BadRequestException('Chỉ yêu cầu bảo hành đã được phê duyệt (APPROVED) mới được tạo phiếu sửa chữa');
    }

    return this.ds.transaction(async (m) => {
      // Đảm bảo đơn giá khách hàng trả là 0đ đối với phần bảo hành
      return this.dao.createWarrantyRepair(m, dto.requestId, dto.repairOrderId, dto.internalCost, 0);
    });
  }

  /** UC49 – Khách hàng xem danh sách bảo hành của mình */
  async getMyWarranties(user: AuthUser) {
    if (!user.customerId) throw new ForbiddenException('Không tìm thấy thông tin khách hàng');
    return this.dao.getMyWarranties(user.customerId);
  }

  /** UC50 – Báo cáo chi phí bảo hành (Hạch toán chi phí riêng) */
  async getCostReport(user: AuthUser, branchId?: number) {
    if (!['BRANCH_MANAGER', 'SYS_ADMIN'].includes(user.role)) {
      throw new ForbiddenException('Không có quyền xem báo cáo chi phí bảo hành');
    }
    const targetBranch = user.role === 'BRANCH_MANAGER' ? user.branchId : branchId;
    return this.dao.getWarrantyCostReport(targetBranch);
  }
}
