# AutoCare – Inventory, Warranty & Billing Settlement (Nguyễn Phồn Hiếu)

Hiện thực các use case từ **UC40 đến UC52** của **Nguyễn Phồn Hiếu** trên nền tảng **Next.js + NestJS + PostgreSQL**, dùng chung cơ sở dữ liệu `autocare` với phân hệ của Toàn và Giang.

---

## 1. Bảng ánh xạ Use Case (UC40 – UC52)

| UC ID | Mã UC | Tên chức năng | Phân hệ | Độ phức tạp | Tác nhân (Actor) | Endpoint API | Màn hình Frontend |
|:---:|:---|:---|:---|:---:|:---|:---|:---|
| **UC40** | 5.8 | Lịch sử biến động kho | Kho linh kiện | Simple | Lễ tân, Quản lý chi nhánh | `GET /api/inventory/transactions?inventoryId=` | `/inventory/history` |
| **UC41** | 5.9 | Adjust Inventory (Điều chỉnh kiểm kê) | Kho linh kiện | Medium | Lễ tân, Quản lý chi nhánh | `POST /api/inventory/adjustments` | `/inventory/adjust` |
| **UC42** | 5.10 | Điều chuyển linh kiện liên chi nhánh | Kho linh kiện | Complex | Lễ tân, Quản lý chi nhánh | `POST /api/inventory/transfers` | `/inventory/transfers` |
| **UC43** | 6.1 | Cấu hình chính sách bảo hành | Bảo hành | Medium | Quản trị viên (Admin) | `POST /api/warranties/policies`<br>`GET /api/warranties/policies` | `/admin/warranties` |
| **UC44** | 6.2 | Tạo hồ sơ bảo hành tự động | Bảo hành | Medium | Hệ thống, Lễ tân | Tự động sinh sau bàn giao xe | Tự động |
| **UC45** | 6.3 | Yêu cầu bảo hành (Warranty Claim) | Bảo hành | Medium | Khách hàng, Lễ tân | `POST /api/warranties/claims` | `/warranty/claim` |
| **UC46** | 6.4 | Assess Warranty (Thợ đánh giá lỗi) | Bảo hành | Complex | Thợ sửa xe, Lễ tân | `PATCH /api/warranties/claims/:id/assess` | `/workshop/warranty-assess` |
| **UC47** | 6.5 | Approve Warranty (Duyệt bảo hành) | Bảo hành | Complex | Quản lý chi nhánh | `PATCH /api/warranties/claims/:id/approve` | `/manager/warranty-approvals` |
| **UC48** | 6.6 | Sửa chữa bảo hành (Phiếu 0 đồng) | Bảo hành | Complex | Lễ tân, Thợ sửa xe | `POST /api/warranties/repairs` | `/repair-orders/warranty-create` |
| **UC49** | 6.7 | Theo dõi trạng thái bảo hành | Bảo hành | Simple | Khách hàng | `GET /api/warranties/mine` | `/my-warranties` |
| **UC50** | 6.8 | Theo dõi chi phí bảo hành | Bảo hành | Medium | Quản lý chi nhánh, QTV | `GET /api/warranties/reports/costs` | `/reports/warranty-cost` |
| **UC51** | 7.1 | Cấu hình thuế GTGT & Hóa đơn | Thuế & HĐĐT | Medium | Quản trị viên (Admin) | `POST /api/billing/tax-rules`<br>`GET /api/billing/tax-rules/active` | `/admin/tax-config` |
| **UC52** | 7.2 | Finalize Charges (Chốt phí & tính tiền) | Thuế & HĐĐT | Complex | Nhân viên thu ngân | `POST /api/billing/invoices/finalize` | `/cashier/checkout` |

---

## 2. Quy tắc nghiệp vụ (Business Rules - BR) cốt lõi

1. **Kho linh kiện (UC40 – UC42):**
   - **BR_INV_1 (Lịch sử bất biến):** Bảng `inventory_transactions` chỉ cho phép `INSERT`, cấm tuyệt đối `UPDATE` hoặc `DELETE`. Mọi điều chỉnh kho ghi nhận qua giao dịch đối ứng `ADJUST`.
   - **BR_INV_2 (Phê duyệt kiểm kê):** Lễ tân hoặc Quản lý chi nhánh thực hiện điều chỉnh khi kiểm kê lệch; ghi nhận số lượng trước, số lượng sau và lý do kiểm kê.
2. **Chính sách & Hồ sơ Bảo hành (UC43 – UC45):**
   - **BR_WAR_1 (Điều kiện kích hoạt):** Khi hoàn tất bàn giao xe, hồ sơ bảo hành tự động được tạo với:
     $$\text{Ngày hết hạn} = \text{Ngày bàn giao} + \text{Thời hạn chính sách (tháng)}$$
     $$\text{Giới hạn ODO} = \text{ODO hiện tại} + \text{Số km bảo hành tối đa}$$
   - **BR_WAR_2 (Kiểm tra hợp lệ khi yêu cầu):** Khách hàng chỉ được gửi yêu cầu bảo hành (UC45) khi thời điểm gửi $\le$ ngày hết hạn **VÀ** số ODO hiện tại $\le$ giới hạn ODO.
3. **Thẩm định & Thực hiện Bảo hành (UC46 – UC48, UC50):**
   - **BR_WAR_3 (Đơn giá 0 đồng):** Hạng mục nằm trong phạm vi bảo hành hợp lệ được áp dụng đơn giá $0$ VNĐ cho khách hàng (`customer_charge = 0`), chi phí thực tế được tính vào chi phí nội bộ (`internal_cost > 0`).
   - **BR_WAR_4 (Tách biệt doanh thu):** Chi phí bảo hành được hạch toán riêng, không tính gộp vào doanh thu bán hàng tại UC50.
4. **Thuế GTGT & Chốt chi phí (UC51 – UC52):**
   - **BR_TAX_1 (Hiệu lực thuế suất):** Thuế GTGT được áp dụng theo ngày chốt chi phí căn cứ vào bảng `tax_rules` đang có hiệu lực `[effective_from, effective_to]`.
   - **BR_TAX_2 (Công thức chốt hóa đơn):**
     $$\text{Subtotal} = \sum (\text{Đơn giá công} + \text{Đơn giá linh kiện})$$
     $$\text{VAT Amount} = \text{Subtotal} \times \text{Thuế suất (\%)}$$
     $$\text{Total Amount} = \text{Subtotal} + \text{VAT Amount} - \text{Discount}$$
   - **BR_TAX_3 (Khóa trạng thái):** Sau khi thu ngân thực hiện `Finalize Charges` (UC52), phiếu sửa chữa và lịch hẹn chuyển sang `WAITING_PAYMENT`, ngăn chặn thêm bớt hạng mục.

---

## 3. Cấu trúc mã nguồn

```
Hieu/
├── README.md                         # Tài liệu hướng dẫn phân hệ của Hiếu
├── database/export/autocare_full.sql # Schema CSDL dùng chung
├── backend/
│   ├── src/
│   │   ├── controller/
│   │   │   └── hieu.controller.ts    # InventoryController, WarrantyController, BillingController
│   │   ├── service/
│   │   │   ├── inventory/inventory.service.ts
│   │   │   ├── warranty/warranty.service.ts
│   │   │   └── billing/billing.service.ts
│   │   ├── dao/
│   │   │   └── hieu.dao.ts           # InventoryDao, WarrantyDao, BillingDao
│   │   ├── dto/
│   │   │   └── hieu.dto.ts           # DTOs cho UC40 - UC52
│   │   └── app.module.ts             # Đăng ký Controller, Service, DAO vào NestJS
│   └── test/
│       └── smoke-test-hieu.mjs       # Script kiểm thử tự động toàn bộ phân hệ
└── frontend/                         # Next.js App Router UI
```

---

## 4. Chạy ứng dụng & Kiểm thử tự động

```powershell
# Chạy Backend (Cổng 4001)
cd backend
npm install
npm run dev

# Chạy kiểm thử tự động cho phân hệ UC40 - UC52 (Hiếu)
node test/smoke-test-hieu.mjs
```
