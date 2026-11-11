// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { AuthUser } from '../../common/security/security';
import { InventoryDao } from '../../dao/hieu.dao';
import { AdjustInventoryDto, CreateTransferDto } from '../../dto/hieu.dto';

@Injectable()
export class InventoryService {
  constructor(
    private readonly ds: DataSource,
    private readonly dao: InventoryDao,
  ) {}

  /** UC40 – Xem lịch sử biến động kho (Lịch sử bất biến, chỉ đọc) */
  async getHistory(inventoryId: number) {
    const inv = await this.dao.getInventory(inventoryId);
    if (!inv) throw new NotFoundException('Không tìm thấy mục tồn kho');
    const transactions = await this.dao.getTransactions(inventoryId);
    return {
      inventory: inv,
      transactions,
    };
  }

  /** UC41 – Adjust Inventory (Điều chỉnh kiểm kê thực tế) */
  async adjust(user: AuthUser, dto: AdjustInventoryDto) {
    if (!['BRANCH_MANAGER', 'RECEPTIONIST'].includes(user.role)) {
      throw new ForbiddenException('Chỉ Lễ tân hoặc Quản lý chi nhánh mới được thực hiện kiểm kê kho');
    }
    if (!user.staffId) {
      throw new ForbiddenException('Tài khoản người dùng chưa được liên kết nhân viên');
    }

    return this.ds.transaction(async (m) => {
      const inv = await this.dao.getInventory(dto.inventoryId, m);
      if (!inv) throw new NotFoundException('Mục tồn kho không tồn tại');

      const diff = dto.actualQuantity - inv.quantityOnHand;
      if (diff === 0) {
        throw new BadRequestException('Số lượng kiểm kê thực tế trùng khớp với tồn hệ thống, không cần điều chỉnh');
      }

      // Cập nhật tồn thực tế
      await this.dao.updateQuantityOnHand(m, dto.inventoryId, dto.actualQuantity);

      // Ghi nhận dòng lịch sử bất biến (BR_INV_1)
      const tx = await this.dao.recordTransaction(
        m,
        dto.inventoryId,
        'ADJUST',
        diff,
        dto.actualQuantity,
        'INVENTORY_AUDIT',
        dto.inventoryId,
        user.staffId!,
      );

      return {
        message: 'Điều chỉnh tồn kho thành công',
        inventoryId: dto.inventoryId,
        previousQuantity: inv.quantityOnHand,
        newQuantity: dto.actualQuantity,
        difference: diff,
        transactionId: tx.id,
      };
    });
  }

  /** UC42 – Điều chuyển linh kiện (Mở rộng) */
  async transfer(user: AuthUser, dto: CreateTransferDto) {
    if (!['BRANCH_MANAGER', 'RECEPTIONIST'].includes(user.role)) {
      throw new ForbiddenException('Không có quyền tạo yêu cầu điều chuyển kho');
    }
    if (dto.fromWarehouseId === dto.toWarehouseId) {
      throw new BadRequestException('Kho nguồn và kho đích không được trùng nhau');
    }
    // Ghi nhận yêu cầu điều chuyển
    return {
      message: 'Tạo yêu cầu điều chuyển linh kiện thành công',
      transfer: { ...dto, status: 'PENDING_APPROVAL', createdBy: user.staffId },
    };
  }
}
