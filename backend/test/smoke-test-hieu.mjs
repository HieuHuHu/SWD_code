// End-to-end API test for UC40 - UC52 (Inventory, Warranty & Billing Settlement - Nguyễn Phồn Hiếu)
// Run: node test/smoke-test-hieu.mjs
import pg from 'pg';

const API = process.env.API ?? 'http://localhost:4001/api';
const db = new pg.Client({ host: 'localhost', user: 'autocare', password: 'autocare123', database: 'autocare' });
await db.connect();

let pass = 0, fail = 0;
const run = Date.now() % 1_000_000;

async function call(token, method, path, body) {
  const res = await fetch(API + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json().catch(() => ({})) };
}

const check = (name, cond, extra = '') => {
  if (cond) {
    pass++;
    console.log(`  ✔ ${name}`);
  } else {
    fail++;
    console.log(`  ✘ ${name} ${extra}`);
  }
};

const expect = async (name, p, code) => {
  const r = await p;
  check(`${name} → ${code}`, r.status === code, `(got ${r.status}: ${JSON.stringify(r.data.message)})`);
  return r;
};

const login = async (l, p = 'Password@123') => {
  const res = await call(null, 'POST', '/auth/login', { login: l, password: p });
  return res.data.accessToken;
};

console.log('--- Đăng nhập các vai trò để kiểm thử phân hệ của Hiếu ---');
const adminToken = await login('admin@autocare.vn');
const managerToken = await login('manager.cg@autocare.vn');
const recToken = await login('reception1.cg@autocare.vn');
const mechanicToken = await login('mechanic1.cg@autocare.vn');
const cashierToken = await login('cashier1.cg@autocare.vn');
const custToken = await login('customer1@gmail.com');

/* ================================================================== 5. KHO LINH KIỆN (UC40, UC41) */
console.log('\nUC40, UC41 – Quản lý kho: Kiểm kê & Lịch sử biến động bất biến');
// Lấy một inventory mẫu trong CSDL
const [invRow] = (await db.query('SELECT inventory_id, quantity_on_hand FROM inventories LIMIT 1')).rows;
const testInvId = invRow.inventory_id;
const oldQty = invRow.quantity_on_hand;
const targetQty = oldQty + 5;

// UC41: Điều chỉnh kiểm kê
let r = await expect(
  'Lễ tân kiểm kê điều chỉnh tồn kho',
  call(recToken, 'POST', '/inventory/adjustments', {
    inventoryId: testInvId,
    actualQuantity: targetQty,
    reason: `Kiểm kê định kỳ đợt ${run}`,
  }),
  200,
);
check('Tồn kho được cập nhật số mới', r.data.newQuantity === targetQty);

// UC40: Tra cứu lịch sử biến động bất biến
r = await expect('Xem lịch sử biến động kho', call(recToken, 'GET', `/inventory/transactions?inventoryId=${testInvId}`), 200);
check('Giao dịch ADJUST được ghi nhận vào lịch sử', r.data.transactions.some((t) => t.transactionType === 'ADJUST'));

// Khách hàng không có quyền xem kho
await expect('Khách hàng truy cập kho bị chặn (403)', call(custToken, 'GET', `/inventory/transactions?inventoryId=${testInvId}`), 403);

/* ================================================================== 6. BẢO HÀNH (UC43 - UC50) */
console.log('\nUC43 – Cấu hình chính sách bảo hành (Admin)');
const policyCode = `POL-${run}`;
r = await expect(
  'Admin tạo chính sách bảo hành động cơ 6 tháng / 10.000km',
  call(adminToken, 'POST', '/warranties/policies', {
    policyCode,
    policyName: `Bảo dưỡng động cơ ${run}`,
    appliesTo: 'SERVICE',
    serviceId: 1,
    durationMonths: 6,
    maxOdometerKm: 10000,
    terms: 'Bảo hành các lỗi phát sinh do kỹ thuật lắp đặt.',
  }),
  201,
);
const policyId = r.data.id;
check('Policy ID trả về hợp lệ', policyId > 0);

r = await expect('Xem danh sách chính sách bảo hành công khai', call(null, 'GET', '/warranties/policies'), 200);
check('Chính sách mới hiển thị trong danh sách', r.data.some((p) => p.code === policyCode));

console.log('\nUC44, UC45 – Tạo yêu cầu bảo hành (Khách hàng)');
// Tạo một warranty mẫu cho xe của customer1
const [vehRow] = (await db.query("SELECT vehicle_id, current_odometer FROM vehicles WHERE customer_id = 1 LIMIT 1")).rows;
const [roRow] = (await db.query("SELECT repair_order_id FROM repair_orders LIMIT 1")).rows;
const warCode = `WAR-TEST-${run}`;

await db.query(
  `INSERT INTO warranties (warranty_code, policy_id, vehicle_id, repair_order_id, start_date, end_date, start_odometer, max_odometer, status)
   VALUES ($1, $2, $3, $4, CURRENT_DATE - 10, CURRENT_DATE + 170, $5, $6, 'ACTIVE')`,
  [warCode, policyId, vehRow.vehicle_id, roRow.repair_order_id, vehRow.current_odometer, vehRow.current_odometer + 10000],
);
const [wCreated] = (await db.query('SELECT warranty_id FROM warranties WHERE warranty_code = $1', [warCode])).rows;

// Test ODO vượt hạn bảo hành
await expect(
  'Yêu cầu bảo hành bị từ chối nếu số km ODO vượt giới hạn',
  call(custToken, 'POST', '/warranties/claims', {
    warrantyId: wCreated.warranty_id,
    branchId: 1,
    issueDescription: 'Động cơ có tiếng kêu lạ',
    currentOdometer: vehRow.current_odometer + 15000, // Quá hạn 10000km
  }),
  400,
);

// Gửi yêu cầu hợp lệ
r = await expect(
  'Khách gửi yêu cầu bảo hành hợp lệ',
  call(custToken, 'POST', '/warranties/claims', {
    warrantyId: wCreated.warranty_id,
    branchId: 1,
    issueDescription: 'Động cơ có tiếng kêu lạ sau 1.000km',
    currentOdometer: vehRow.current_odometer + 1000,
  }),
  201,
);
const claimId = r.data.id;
check('Trạng thái khởi tạo là SUBMITTED', r.data.status === 'SUBMITTED');

console.log('\nUC46, UC47, UC48 – Thẩm định, Phê duyệt & Sửa chữa bảo hành');
// Thợ đánh giá
r = await expect(
  'Thợ sửa xe đánh giá lỗi kỹ thuật đủ điều kiện bảo hành',
  call(mechanicToken, 'PATCH', `/warranties/claims/${claimId}/assess`, {
    isEligible: true,
    assessmentNote: 'Lỗi lỏng ốc siết nắp quy lát khi bảo dưỡng, thuộc diện bảo hành',
  }),
  200,
);
check('Trạng thái chuyển sang ASSESSED', r.data.status === 'ASSESSED');

// Quản lý phê duyệt
r = await expect(
  'Quản lý chi nhánh duyệt bảo hành APPROVED',
  call(managerToken, 'PATCH', `/warranties/claims/${claimId}/approve`, {
    decision: 'APPROVED',
  }),
  200,
);
check('Trạng thái chuyển sang APPROVED', r.data.status === 'APPROVED');

// Lễ tân tạo phiếu sửa chữa bảo hành (0 đồng theo BR_WAR_3)
r = await expect(
  'Tạo phiếu sửa chữa bảo hành với chi phí thu khách = 0 đồng',
  call(recToken, 'POST', '/warranties/repairs', {
    requestId: claimId,
    repairOrderId: roRow.repair_order_id,
    internalCost: 150000,
    customerCharge: 0,
  }),
  201,
);
check('customerCharge đúng bằng 0', r.data.customerCharge === 0);

console.log('\nUC49, UC50 – Tra cứu bảo hành & Báo cáo chi phí bảo hành');
r = await expect('Khách hàng xem danh sách bảo hành của mình', call(custToken, 'GET', '/warranties/mine'), 200);
check('Danh sách bảo hành của khách chứa mã vừa tạo', r.data.some((w) => w.code === warCode));

r = await expect('Quản lý xem báo cáo chi phí bảo hành chi nhánh', call(managerToken, 'GET', '/warranties/reports/costs'), 200);
check('Báo cáo có số liệu tổng chi phí nội bộ', r.data.length > 0 && r.data[0].totalInternalCost >= 0);

/* ================================================================== 7. THUẾ & CHỐT PHÍ (UC51, UC52) */
console.log('\nUC51, UC52 – Cấu hình thuế GTGT & Chốt chi phí tính tiền');
// Cấu hình thuế GTGT 8%
r = await expect(
  'Admin cấu hình thuế VAT 8% cho Dịch vụ',
  call(adminToken, 'POST', '/billing/tax-rules', {
    itemType: 'SERVICE',
    vatRate: 8,
    effectiveFrom: '2026-01-01',
  }),
  201,
);
check('Cấu hình VAT 8% thành công', r.data.vatRate === 8);

// Dọn dẹp dữ liệu test
await db.end();
console.log(`\n========================================`);
console.log(`Tổng kết: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
