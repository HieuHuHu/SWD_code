import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { AuthUser } from '../../common/security/security';
import { BillingDao } from '../../dao/hieu.dao';
import { CreateTaxRuleDto, FinalizeChargesDto } from '../../dto/hieu.dto';

@Injectable()
export class BillingService {
  constructor(
    private readonly ds: DataSource,
    private readonly dao: BillingDao,
  ) {}

  /** UC51 – Cấu hình quy tắc thuế GTGT */
  async createTaxRule(user: AuthUser, dto: CreateTaxRuleDto) {
    if (user.role !== 'SYS_ADMIN') {
      throw new ForbiddenException('Chỉ Quản trị viên hệ thống mới có quyền cấu hình thuế');
    }
    return this.dao.createTaxRule({
      itemType: dto.itemType,
      vatRate: dto.vatRate,
      effectiveFrom: dto.effectiveFrom,
      effectiveTo: dto.effectiveTo,
      userId: user.userId,
    });
  }

  async getActiveTaxRules(forDate?: string) {
    return this.dao.getActiveTaxRules(forDate);
  }

  /** UC52 – Finalize Charges (Chốt chi phí & tính tiền) */
  async finalizeCharges(user: AuthUser, dto: FinalizeChargesDto) {
    if (!['CASHIER', 'BRANCH_MANAGER'].includes(user.role)) {
      throw new ForbiddenException('Chỉ Nhân viên thu ngân hoặc Quản lý chi nhánh mới có quyền chốt hóa đơn');
    }
    if (!user.staffId) {
      throw new ForbiddenException('Tài khoản chưa được gắn mã nhân viên');
    }

    return this.ds.transaction(async (m) => {
      const ro = await this.dao.getRepairOrder(dto.repairOrderId, m);
      if (!ro) throw new NotFoundException('Không tìm thấy phiếu sửa chữa');

      const items = await this.dao.getRepairOrderItems(dto.repairOrderId, m);
      if (items.length === 0) {
        throw new BadRequestException('Phiếu sửa chữa chưa có hạng mục nào được khách hàng duyệt');
      }

      // Lấy thuế suất GTGT đang có hiệu lực cho Ngày hôm nay
      const taxRules = await this.dao.getActiveTaxRules();
      const getRate = (type: string) => {
        const found = taxRules.find((r: any) => r.itemType === type);
        return found ? found.vatRate : 10.0; // Mặc định 10% nếu chưa cấu hình
      };

      let subtotal = 0;
      let totalVat = 0;
      const linesData = [];

      for (const it of items) {
        const lineSubtotal = it.quantity * it.unitPrice;
        const rate = getRate(it.itemType);
        const lineVat = (lineSubtotal * rate) / 100;
        const lineTotal = lineSubtotal + lineVat;

        subtotal += lineSubtotal;
        totalVat += lineVat;

        linesData.push({
          quotationItemId: it.quotationItemId,
          itemType: it.itemType,
          description: it.description,
          quantity: it.quantity,
          unitPrice: it.unitPrice,
          vatRate: rate,
          vatAmount: lineVat,
          lineTotal: lineTotal,
        });
      }

      const discount = dto.discountAmount ?? 0;
      const totalAmount = Math.max(0, subtotal + totalVat - discount);
      const invoiceCode = `INV-${Date.now().toString().slice(-8)}`;

      // 1. Tạo bản ghi Hóa đơn nội bộ
      const invoice = await this.dao.createInvoice(m, {
        invoiceCode,
        repairOrderId: dto.repairOrderId,
        billingId: dto.billingId,
        subtotal,
        discountAmount: discount,
        vatAmount: totalVat,
        totalAmount,
        finalizedBy: user.staffId!,
      });

      // 2. Tạo các dòng chi tiết hóa đơn
      for (const line of linesData) {
        await this.dao.createInvoiceLine(m, {
          invoiceId: invoice.id,
          ...line,
        });
      }

      // 3. Khóa trạng thái phiếu sang WAITING_PAYMENT (BR_TAX_3)
      await this.dao.setRepairOrderWaitingPayment(m, dto.repairOrderId);

      return {
        message: 'Chốt chi phí thành công',
        invoiceId: invoice.id,
        invoiceCode: invoice.code,
        subtotal,
        vatAmount: totalVat,
        discountAmount: discount,
        totalAmount,
        status: invoice.status,
      };
    });
  }
}
