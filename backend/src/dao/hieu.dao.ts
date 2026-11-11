// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import { Injectable } from '@nestjs/common';
import { DataSource, EntityManager } from 'typeorm';

/* ================================================================== 5. KHO LINH KIỆN (UC40, UC41, UC42) */
@Injectable()
export class InventoryDao {
  constructor(private readonly ds: DataSource) {}

  /** UC40 – Tra cứu lịch sử bất biến của mọi giao dịch kho */
  async getTransactions(inventoryId: number) {
    return this.ds.query(
      `SELECT t.transaction_id::int AS id, t.inventory_id::int AS "inventoryId",
              t.transaction_type AS "transactionType", t.quantity, t.balance_after AS "balanceAfter",
              t.reference_type AS "referenceType", t.reference_id::int AS "referenceId",
              u.full_name AS "performedByName", t.created_at AS "createdAt"
       FROM inventory_transactions t
       JOIN staff s ON s.staff_id = t.performed_by
       JOIN users u ON u.user_id = s.user_id
       WHERE t.inventory_id = $1
       ORDER BY t.created_at DESC`,
      [inventoryId],
    );
  }

  async getInventory(inventoryId: number, m?: EntityManager) {
    const em = m ?? this.ds.manager;
    const [inv] = await em.query(
      `SELECT i.inventory_id::int AS id, i.warehouse_id::int AS "warehouseId", i.part_id::int AS "partId",
              p.part_code AS "partCode", p.part_name AS "partName",
              i.quantity_on_hand AS "quantityOnHand", i.quantity_reserved AS "quantityReserved",
              i.reorder_level AS "reorderLevel"
       FROM inventories i
       JOIN parts p ON p.part_id = i.part_id
       WHERE i.inventory_id = $1`,
      [inventoryId],
    );
    return inv ?? null;
  }

  async recordTransaction(
    m: EntityManager,
    inventoryId: number,
    type: 'RECEIPT' | 'RESERVE' | 'RELEASE' | 'ISSUE' | 'RETURN' | 'ADJUST',
    quantity: number,
    balanceAfter: number,
    referenceType: string,
    referenceId: number,
    performedByStaffId: number,
  ) {
    const [row] = await m.query(
      `INSERT INTO inventory_transactions 
         (inventory_id, transaction_type, quantity, balance_after, reference_type, reference_id, performed_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING transaction_id::int AS id, created_at AS "createdAt"`,
      [inventoryId, type, quantity, balanceAfter, referenceType, referenceId, performedByStaffId],
    );
    return row;
  }

  async updateQuantityOnHand(m: EntityManager, inventoryId: number, newQuantity: number) {
    await m.query(
      `UPDATE inventories 
       SET quantity_on_hand = $1, version = version + 1, updated_at = NOW()
       WHERE inventory_id = $2`,
      [newQuantity, inventoryId],
    );
  }
}

/* ================================================================== 6. BẢO HÀNH (UC43 - UC50) */
@Injectable()
export class WarrantyDao {
  constructor(private readonly ds: DataSource) {}

  /** UC43 – Cấu hình chính sách bảo hành */
  async createPolicy(policy: {
    policyCode: string;
    policyName: string;
    appliesTo: 'SERVICE' | 'PART';
    serviceId?: number;
    partId?: number;
    durationMonths: number;
    maxOdometerKm?: number;
    terms: string;
  }) {
    const [r] = await this.ds.query(
      `INSERT INTO warranty_policies 
         (policy_code, policy_name, applies_to, service_id, part_id, duration_months, max_odometer_km, terms)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING policy_id::int AS id, policy_code AS code, policy_name AS name`,
      [
        policy.policyCode,
        policy.policyName,
        policy.appliesTo,
        policy.serviceId ?? null,
        policy.partId ?? null,
        policy.durationMonths,
        policy.maxOdometerKm ?? null,
        policy.terms,
      ],
    );
    return r;
  }

  async listPolicies() {
    return this.ds.query(
      `SELECT p.policy_id::int AS id, p.policy_code AS code, p.policy_name AS name,
              p.applies_to AS "appliesTo", p.duration_months AS "durationMonths",
              p.max_odometer_km AS "maxOdometerKm", p.terms, p.status
       FROM warranty_policies p
       WHERE p.status = 'ACTIVE'
       ORDER BY p.policy_id`,
    );
  }

  /** UC44 – Tạo hồ sơ bảo hành tự động sau nghiệm thu bàn giao */
  async createWarrantyRecord(
    m: EntityManager,
    data: {
      warrantyCode: string;
      policyId: number;
      vehicleId: number;
      repairOrderId: number;
      quotationItemId?: number;
      startDate: string;
      endDate: string;
      startOdometer: number;
      maxOdometer?: number;
    },
  ) {
    const [row] = await m.query(
      `INSERT INTO warranties 
         (warranty_code, policy_id, vehicle_id, repair_order_id, quotation_item_id, start_date, end_date, start_odometer, max_odometer, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'ACTIVE')
       RETURNING warranty_id::int AS id, warranty_code AS code`,
      [
        data.warrantyCode,
        data.policyId,
        data.vehicleId,
        data.repairOrderId,
        data.quotationItemId ?? null,
        data.startDate,
        data.endDate,
        data.startOdometer,
        data.maxOdometer ?? null,
      ],
    );
    return row;
  }

  async getWarrantyById(warrantyId: number) {
    const [w] = await this.ds.query(
      `SELECT w.warranty_id::int AS id, w.warranty_code AS code, w.vehicle_id::int AS "vehicleId",
              w.start_date AS "startDate", w.end_date AS "endDate",
              w.start_odometer AS "startOdometer", w.max_odometer AS "maxOdometer",
              w.status, v.customer_id::int AS "customerId", v.license_plate AS "licensePlate",
              p.policy_name AS "policyName", p.duration_months AS "durationMonths"
       FROM warranties w
       JOIN vehicles v ON v.vehicle_id = w.vehicle_id
       JOIN warranty_policies p ON p.policy_id = w.policy_id
       WHERE w.warranty_id = $1`,
      [warrantyId],
    );
    return w ?? null;
  }

  /** UC49 – Khách hàng xem danh sách bảo hành của mình */
  async getMyWarranties(customerId: number) {
    return this.ds.query(
      `SELECT w.warranty_id::int AS id, w.warranty_code AS code, v.license_plate AS "licensePlate",
              v.brand, v.model, p.policy_name AS "policyName", p.applies_to AS "appliesTo",
              w.start_date AS "startDate", w.end_date AS "endDate",
              w.start_odometer AS "startOdometer", w.max_odometer AS "maxOdometer",
              w.status,
              CASE WHEN CURRENT_DATE > w.end_date THEN true ELSE false END AS "isExpiredByTime"
       FROM warranties w
       JOIN vehicles v ON v.vehicle_id = w.vehicle_id
       JOIN warranty_policies p ON p.policy_id = w.policy_id
       WHERE v.customer_id = $1
       ORDER BY w.created_at DESC`,
      [customerId],
    );
  }

  /** UC45 – Tạo yêu cầu bảo hành */
  async createClaim(
    m: EntityManager,
    claim: {
      requestCode: string;
      warrantyId: number;
      customerId: number;
      branchId: number;
      issueDescription: string;
      currentOdometer: number;
    },
  ) {
    const [row] = await m.query(
      `INSERT INTO warranty_requests 
         (request_code, warranty_id, customer_id, branch_id, issue_description, current_odometer, status)
       VALUES ($1, $2, $3, $4, $5, $6, 'SUBMITTED')
       RETURNING request_id::int AS id, request_code AS code, status`,
      [
        claim.requestCode,
        claim.warrantyId,
        claim.customerId,
        claim.branchId,
        claim.issueDescription,
        claim.currentOdometer,
      ],
    );
    return row;
  }

  async getClaimById(requestId: number) {
    const [c] = await this.ds.query(
      `SELECT r.request_id::int AS id, r.request_code AS code, r.warranty_id::int AS "warrantyId",
              r.customer_id::int AS "customerId", r.branch_id::int AS "branchId",
              r.issue_description AS "issueDescription", r.current_odometer AS "currentOdometer",
              r.status, r.is_eligible AS "isEligible", r.assessment_note AS "assessmentNote",
              r.assessed_by::int AS "assessedBy", r.approved_by::int AS "approvedBy"
       FROM warranty_requests r
       WHERE r.request_id = $1`,
      [requestId],
    );
    return c ?? null;
  }

  /** UC46 – Thợ sửa xe đánh giá lỗi */
  async assessClaim(requestId: number, isEligible: boolean, note: string, staffId: number) {
    const [row] = await this.ds.query(
      `UPDATE warranty_requests 
       SET is_eligible = $1, assessment_note = $2, assessed_by = $3, status = 'ASSESSED'
       WHERE request_id = $4
       RETURNING request_id::int AS id, status, is_eligible AS "isEligible"`,
      [isEligible, note, staffId, requestId],
    );
    return row;
  }

  /** UC47 – Quản lý chi nhánh duyệt yêu cầu bảo hành */
  async approveClaim(requestId: number, decision: 'APPROVED' | 'REJECTED', managerStaffId: number) {
    const [row] = await this.ds.query(
      `UPDATE warranty_requests 
       SET status = $1, approved_by = $2, decided_at = NOW()
       WHERE request_id = $3
       RETURNING request_id::int AS id, status, decided_at AS "decidedAt"`,
      [decision, managerStaffId, requestId],
    );
    return row;
  }

  /** UC48 – Lập phiếu sửa chữa bảo hành (customer_charge = 0) */
  async createWarrantyRepair(
    m: EntityManager,
    requestId: number,
    repairOrderId: number,
    internalCost: number,
    customerCharge: number = 0,
  ) {
    const [row] = await m.query(
      `INSERT INTO warranty_repairs 
         (request_id, repair_order_id, internal_cost, customer_charge, repair_date)
       VALUES ($1, $2, $3, $4, CURRENT_DATE)
       RETURNING warranty_repair_id::int AS id, internal_cost AS "internalCost", customer_charge AS "customerCharge"`,
      [requestId, repairOrderId, internalCost, customerCharge],
    );
    await m.query(`UPDATE warranty_requests SET status = 'IN_REPAIR' WHERE request_id = $1`, [requestId]);
    return row;
  }

  /** UC50 – Báo cáo chi phí bảo hành */
  async getWarrantyCostReport(branchId?: number) {
    return this.ds.query(
      `SELECT b.branch_id::int AS "branchId", b.branch_name AS "branchName",
              COUNT(wr.warranty_repair_id)::int AS "totalWarrantyRepairs",
              COALESCE(SUM(wr.internal_cost), 0)::float8 AS "totalInternalCost",
              COALESCE(SUM(wr.customer_charge), 0)::float8 AS "totalCustomerCharge"
       FROM branches b
       LEFT JOIN warranty_requests req ON req.branch_id = b.branch_id
       LEFT JOIN warranty_repairs wr ON wr.request_id = req.request_id
       WHERE ($1::int IS NULL OR b.branch_id = $1)
       GROUP BY b.branch_id, b.branch_name
       ORDER BY b.branch_id`,
      [branchId ?? null],
    );
  }
}

/* ================================================================== 7. THUẾ & CHỐT PHÍ (UC51, UC52) */
@Injectable()
export class BillingDao {
  constructor(private readonly ds: DataSource) {}

  /** UC51 – Cấu hình quy tắc thuế GTGT */
  async createTaxRule(rule: {
    itemType: 'SERVICE' | 'PART';
    vatRate: number;
    effectiveFrom: string;
    effectiveTo?: string;
    userId: number;
  }) {
    const [row] = await this.ds.query(
      `INSERT INTO tax_rules (item_type, vat_rate, effective_from, effective_to, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING tax_rule_id::int AS id, item_type AS "itemType", vat_rate AS "vatRate"`,
      [rule.itemType, rule.vatRate, rule.effectiveFrom, rule.effectiveTo ?? null, rule.userId],
    );
    return row;
  }

  async getActiveTaxRules(forDate: string = 'CURRENT_DATE') {
    return this.ds.query(
      `SELECT tax_rule_id::int AS id, item_type AS "itemType", vat_rate::float8 AS "vatRate",
              effective_from AS "effectiveFrom", effective_to AS "effectiveTo"
       FROM tax_rules
       WHERE effective_from <= $1::date AND (effective_to IS NULL OR effective_to >= $1::date)
       ORDER BY tax_rule_id DESC`,
      [forDate === 'CURRENT_DATE' ? new Date().toISOString().slice(0, 10) : forDate],
    );
  }

  /** UC52 – Lấy các hạng mục sửa chữa đã hoàn tất để chốt phí */
  async getRepairOrderItems(repairOrderId: number, m?: EntityManager) {
    const em = m ?? this.ds.manager;
    return em.query(
      `SELECT qi.item_id::int AS "quotationItemId", qi.item_type AS "itemType",
              qi.description, qi.quantity::float8 AS quantity, qi.unit_price::float8 AS "unitPrice",
              qi.is_approved AS "isApproved"
       FROM repair_orders ro
       JOIN quotations q ON q.quotation_id = ro.quotation_id
       JOIN quotation_items qi ON qi.quotation_id = q.quotation_id
       WHERE ro.repair_order_id = $1 AND qi.is_approved = true`,
      [repairOrderId],
    );
  }

  async getRepairOrder(repairOrderId: number, m?: EntityManager) {
    const em = m ?? this.ds.manager;
    const [ro] = await em.query(
      `SELECT ro.repair_order_id::int AS id, ro.order_code AS code, ro.status,
              ro.appointment_id::int AS "appointmentId", a.customer_id::int AS "customerId"
       FROM repair_orders ro
       JOIN appointments a ON a.appointment_id = ro.appointment_id
       WHERE ro.repair_order_id = $1`,
      [repairOrderId],
    );
    return ro ?? null;
  }

  async createInvoice(
    m: EntityManager,
    inv: {
      invoiceCode: string;
      repairOrderId: number;
      billingId?: number;
      subtotal: number;
      discountAmount: number;
      vatAmount: number;
      totalAmount: number;
      finalizedBy: number;
    },
  ) {
    const [row] = await m.query(
      `INSERT INTO invoices 
         (invoice_code, repair_order_id, billing_id, subtotal, discount_amount, vat_amount, total_amount, payment_status, status, finalized_by, finalized_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'UNPAID', 'FINALIZED', $8, NOW())
       RETURNING invoice_id::int AS id, invoice_code AS code, total_amount AS "totalAmount", status`,
      [
        inv.invoiceCode,
        inv.repairOrderId,
        inv.billingId ?? null,
        inv.subtotal,
        inv.discountAmount,
        inv.vatAmount,
        inv.totalAmount,
        inv.finalizedBy,
      ],
    );
    return row;
  }

  async createInvoiceLine(
    m: EntityManager,
    line: {
      invoiceId: number;
      quotationItemId?: number;
      itemType: string;
      description: string;
      quantity: number;
      unitPrice: number;
      vatRate: number;
      vatAmount: number;
      lineTotal: number;
      isWarrantyCovered?: boolean;
    },
  ) {
    await m.query(
      `INSERT INTO invoice_lines 
         (invoice_id, quotation_item_id, item_type, description, quantity, unit_price, vat_rate, vat_amount, line_total, is_warranty_covered)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [
        line.invoiceId,
        line.quotationItemId ?? null,
        line.itemType,
        line.description,
        line.quantity,
        line.unitPrice,
        line.vatRate,
        line.vatAmount,
        line.lineTotal,
        line.isWarrantyCovered ?? false,
      ],
    );
  }

  async setRepairOrderWaitingPayment(m: EntityManager, repairOrderId: number) {
    await m.query(`UPDATE repair_orders SET status = 'WAITING_PAYMENT' WHERE repair_order_id = $1`, [repairOrderId]);
    await m.query(
      `UPDATE appointments 
       SET status = 'WAITING_PAYMENT' 
       WHERE appointment_id = (SELECT appointment_id FROM repair_orders WHERE repair_order_id = $1)`,
      [repairOrderId],
    );
  }
}
