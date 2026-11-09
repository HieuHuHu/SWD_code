-- =====================================================================
-- AutoCare – FULL DATABASE (schema + sample data) – portable SQL, PostgreSQL 12+
-- How to load (run inside an EMPTY database, e.g. "autocare"):
--   psql -U autocare -h localhost -d autocare -f autocare_full.sql
-- 45 tables · 3 branches · 22 staff · 12 customers · 37 appointments · 21 repair orders · 9 invoices
-- All demo accounts use password: Password@123   (see Giang/README.md)
-- =====================================================================
SET client_encoding = 'UTF8';

-- =====================================================================
-- AutoCare – Vehicle Repair, Maintenance Booking & Garage Service Management
-- Physical database schema – PostgreSQL 16
-- Naming convention: snake_case, plural table names, <table>_id surrogate keys,
--   fk columns named after referenced key, idx_<table>_<cols>, chk_/uq_ prefixes
-- =====================================================================

-- BRANCHES — Garage branches of the AutoCare network (UC60).
CREATE TABLE branches (
    branch_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_code            VARCHAR(20) NOT NULL UNIQUE,
    branch_name            VARCHAR(150) NOT NULL,
    address                VARCHAR(255) NOT NULL,
    phone                  VARCHAR(20),
    email                  VARCHAR(150),
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_branches_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

-- ROLES — System roles used for role-based access control (BR4).
CREATE TABLE roles (
    role_id                SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_code              VARCHAR(30) NOT NULL UNIQUE,
    role_name              VARCHAR(100) NOT NULL,
    description            VARCHAR(255)
);

-- USERS — Login accounts of customers and staff (UC01–UC04).
CREATE TABLE users (
    user_id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id                SMALLINT NOT NULL
        REFERENCES roles(role_id) ON DELETE RESTRICT,
    email                  VARCHAR(150) NOT NULL UNIQUE,
    phone                  VARCHAR(20) UNIQUE,
    password_hash          VARCHAR(255) NOT NULL,
    full_name              VARCHAR(150) NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    failed_login_count     SMALLINT NOT NULL DEFAULT 0,
    locked_until           TIMESTAMPTZ,
    last_login_at          TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_users_1 CHECK (status IN ('ACTIVE','LOCKED','INACTIVE')),
    CONSTRAINT chk_users_2 CHECK (failed_login_count >= 0)
);
CREATE INDEX idx_users_role_id ON users(role_id);

-- CUSTOMERS — Customer profile linked 1–1 to a user account.
CREATE TABLE customers (
    customer_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id                BIGINT NOT NULL UNIQUE
        REFERENCES users(user_id) ON DELETE RESTRICT,
    date_of_birth          DATE,
    gender                 VARCHAR(10),
    address                VARCHAR(255),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_customers_1 CHECK (gender IN ('MALE','FEMALE','OTHER'))
);

-- STAFF — Internal staff profile with branch assignment (UC61, BR5, BR48).
CREATE TABLE staff (
    staff_id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id                BIGINT NOT NULL UNIQUE
        REFERENCES users(user_id) ON DELETE RESTRICT,
    branch_id              BIGINT
        REFERENCES branches(branch_id) ON DELETE RESTRICT,
    staff_code             VARCHAR(20) NOT NULL UNIQUE,
    position               VARCHAR(30) NOT NULL,
    hired_date             DATE,
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_staff_1 CHECK (position IN ('RECEPTIONIST','MECHANIC','CASHIER','BRANCH_MANAGER','SYS_ADMIN'))
);
CREATE INDEX idx_staff_branch_id_position ON staff(branch_id, position);

-- BILLING_INFORMATION — Reusable buyer information for e-invoices (UC09, BR40).
CREATE TABLE billing_information (
    billing_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id            BIGINT NOT NULL
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    buyer_type             VARCHAR(20) NOT NULL DEFAULT 'INDIVIDUAL',
    buyer_name             VARCHAR(150) NOT NULL,
    company_name           VARCHAR(255),
    tax_code               VARCHAR(14),
    billing_address        VARCHAR(255) NOT NULL,
    invoice_email          VARCHAR(150) NOT NULL,
    is_default             BOOLEAN NOT NULL DEFAULT FALSE,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_billing_information_1 CHECK (buyer_type IN ('INDIVIDUAL','COMPANY')),
    CONSTRAINT chk_billing_information_2 CHECK (buyer_type = 'INDIVIDUAL' OR tax_code IS NOT NULL)
);
CREATE INDEX idx_billing_information_customer_id ON billing_information(customer_id);

-- NOTIFICATIONS — E-mail / in-app notifications sent by the Notification component (UC24).
CREATE TABLE notifications (
    notification_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id                BIGINT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT,
    channel                VARCHAR(20) NOT NULL DEFAULT 'EMAIL',
    title                  VARCHAR(200) NOT NULL,
    content                TEXT NOT NULL,
    reference_type         VARCHAR(50),
    reference_id           BIGINT,
    status                 VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    sent_at                TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_notifications_1 CHECK (channel IN ('EMAIL','IN_APP')),
    CONSTRAINT chk_notifications_2 CHECK (status IN ('PENDING','SENT','FAILED','READ'))
);
CREATE INDEX idx_notifications_user_id_status ON notifications(user_id, status);

-- AUDIT_LOGS — Append-only audit trail of important transactions (BR50).
CREATE TABLE audit_logs (
    audit_id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id                BIGINT
        REFERENCES users(user_id) ON DELETE RESTRICT,
    action                 VARCHAR(50) NOT NULL,
    entity_name            VARCHAR(50) NOT NULL,
    entity_id              BIGINT NOT NULL,
    old_value              JSONB,
    new_value              JSONB,
    ip_address             VARCHAR(45),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_logs_entity_name_entity_id ON audit_logs(entity_name, entity_id);

-- VEHICLES — Vehicles registered by customers (UC05–UC08).
CREATE TABLE vehicles (
    vehicle_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id            BIGINT NOT NULL
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    license_plate          VARCHAR(15) NOT NULL UNIQUE,
    vehicle_type           VARCHAR(20) NOT NULL,
    brand                  VARCHAR(50) NOT NULL,
    model                  VARCHAR(50) NOT NULL,
    manufacture_year       SMALLINT,
    vin                    VARCHAR(17) UNIQUE,
    color                  VARCHAR(30),
    current_odometer       INTEGER NOT NULL DEFAULT 0,
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_vehicles_1 CHECK (vehicle_type IN ('MOTORCYCLE','CAR')),
    CONSTRAINT chk_vehicles_2 CHECK (current_odometer >= 0),
    CONSTRAINT chk_vehicles_3 CHECK (status IN ('ACTIVE','INACTIVE'))
);
CREATE INDEX idx_vehicles_customer_id ON vehicles(customer_id);

-- SERVICES — Shared catalog of repair / maintenance services (UC10–UC11, UC62).
CREATE TABLE services (
    service_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_code           VARCHAR(20) NOT NULL UNIQUE,
    service_name           VARCHAR(150) NOT NULL,
    description            TEXT,
    vehicle_type           VARCHAR(20) NOT NULL DEFAULT 'ALL',
    base_price             NUMERIC(14,2) NOT NULL,
    estimated_minutes      INTEGER NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_services_1 CHECK (base_price >= 0),
    CONSTRAINT chk_services_2 CHECK (estimated_minutes > 0)
);

-- BRANCH_SERVICES — Services enabled per branch, with optional branch price.
CREATE TABLE branch_services (
    branch_id              BIGINT NOT NULL
        REFERENCES branches(branch_id) ON DELETE RESTRICT,
    service_id             BIGINT NOT NULL
        REFERENCES services(service_id) ON DELETE RESTRICT,
    is_enabled             BOOLEAN NOT NULL DEFAULT TRUE,
    branch_price           NUMERIC(14,2),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_branch_services PRIMARY KEY (branch_id, service_id)
);

-- TIME_SLOTS — Bookable reception slots with capacity per branch (UC12, UC63).
CREATE TABLE time_slots (
    slot_id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id              BIGINT NOT NULL
        REFERENCES branches(branch_id) ON DELETE RESTRICT,
    slot_date              DATE NOT NULL,
    start_time             TIME NOT NULL,
    end_time               TIME NOT NULL,
    capacity               SMALLINT NOT NULL,
    booked_count           SMALLINT NOT NULL DEFAULT 0,
    status                 VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    CONSTRAINT uq_time_slots_branch_id_slot_date_start_time UNIQUE (branch_id, slot_date, start_time),
    CONSTRAINT chk_time_slots_1 CHECK (end_time > start_time),
    CONSTRAINT chk_time_slots_2 CHECK (capacity > 0),
    CONSTRAINT chk_time_slots_3 CHECK (booked_count BETWEEN 0 AND capacity),
    CONSTRAINT chk_time_slots_4 CHECK (status IN ('OPEN','CLOSED'))
);
CREATE INDEX idx_time_slots_branch_id_slot_date ON time_slots(branch_id, slot_date);

-- APPOINTMENTS — Service appointments booked by customers (UC13–UC19).
CREATE TABLE appointments (
    appointment_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_code       VARCHAR(20) NOT NULL UNIQUE,
    customer_id            BIGINT NOT NULL
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    vehicle_id             BIGINT NOT NULL
        REFERENCES vehicles(vehicle_id) ON DELETE RESTRICT,
    branch_id              BIGINT NOT NULL
        REFERENCES branches(branch_id) ON DELETE RESTRICT,
    slot_id                BIGINT NOT NULL
        REFERENCES time_slots(slot_id) ON DELETE RESTRICT,
    status                 VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    customer_note          VARCHAR(500),
    reject_reason          VARCHAR(255),
    cancel_reason          VARCHAR(255),
    confirmed_by           BIGINT
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_appointments_1 CHECK (status IN ('PENDING','CONFIRMED','REJECTED','CHECKED_IN','IN_SERVICE','WAITING_PAYMENT','COMPLETED','CANCELLED'))
);
CREATE INDEX idx_appointments_branch_id_status ON appointments(branch_id, status);
CREATE INDEX idx_appointments_customer_id ON appointments(customer_id);
CREATE INDEX idx_appointments_slot_id ON appointments(slot_id);

-- APPOINTMENT_SERVICES — Services requested in an appointment (M–N).
CREATE TABLE appointment_services (
    appointment_id         BIGINT NOT NULL
        REFERENCES appointments(appointment_id) ON DELETE RESTRICT,
    service_id             BIGINT NOT NULL
        REFERENCES services(service_id) ON DELETE RESTRICT,
    estimated_price        NUMERIC(14,2) NOT NULL,
    CONSTRAINT pk_appointment_services PRIMARY KEY (appointment_id, service_id)
);

-- SERVICE_RATINGS — One customer rating per completed appointment (UC64, BR46–BR47).
CREATE TABLE service_ratings (
    rating_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id         BIGINT NOT NULL UNIQUE
        REFERENCES appointments(appointment_id) ON DELETE RESTRICT,
    customer_id            BIGINT NOT NULL
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    score                  SMALLINT NOT NULL,
    comment                VARCHAR(1000),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_service_ratings_1 CHECK (score BETWEEN 1 AND 5)
);

-- VEHICLE_RECEPTIONS — Check-in record with odometer and condition (UC20, BR15).
CREATE TABLE vehicle_receptions (
    reception_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id         BIGINT NOT NULL UNIQUE
        REFERENCES appointments(appointment_id) ON DELETE RESTRICT,
    received_by            BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    odometer_reading       INTEGER NOT NULL,
    vehicle_condition      VARCHAR(1000) NOT NULL,
    checked_in_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_vehicle_receptions_1 CHECK (odometer_reading >= 0)
);

-- INSPECTIONS — Technical inspection assigned to a mechanic (UC21–UC22).
CREATE TABLE inspections (
    inspection_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reception_id           BIGINT NOT NULL UNIQUE
        REFERENCES vehicle_receptions(reception_id) ON DELETE RESTRICT,
    mechanic_id            BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    assigned_by            BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    status                 VARCHAR(20) NOT NULL DEFAULT 'ASSIGNED',
    result_summary         TEXT,
    assigned_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at           TIMESTAMPTZ,
    CONSTRAINT chk_inspections_1 CHECK (status IN ('ASSIGNED','IN_PROGRESS','COMPLETED'))
);
CREATE INDEX idx_inspections_mechanic_id_status ON inspections(mechanic_id, status);

-- PARTS — Shared spare-parts catalog (UC33).
CREATE TABLE parts (
    part_id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku                    VARCHAR(30) NOT NULL UNIQUE,
    part_name              VARCHAR(150) NOT NULL,
    category               VARCHAR(50),
    unit                   VARCHAR(20) NOT NULL DEFAULT 'pcs',
    unit_price             NUMERIC(14,2) NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_parts_1 CHECK (unit_price >= 0)
);

-- INSPECTION_ITEMS — Work and parts recommended by the mechanic, without prices (UC22, 22.E1).
CREATE TABLE inspection_items (
    inspection_item_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inspection_id          BIGINT NOT NULL
        REFERENCES inspections(inspection_id) ON DELETE RESTRICT,
    item_type              VARCHAR(10) NOT NULL,
    service_id             BIGINT
        REFERENCES services(service_id) ON DELETE RESTRICT,
    part_id                BIGINT
        REFERENCES parts(part_id) ON DELETE RESTRICT,
    description            VARCHAR(255) NOT NULL,
    quantity               NUMERIC(10,2) NOT NULL DEFAULT 1,
    priority               VARCHAR(10) NOT NULL DEFAULT 'MEDIUM',
    note                   VARCHAR(500),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_inspection_items_1 CHECK (item_type IN ('SERVICE','PART','LABOR')),
    CONSTRAINT chk_inspection_items_2 CHECK (quantity > 0),
    CONSTRAINT chk_inspection_items_3 CHECK (priority IN ('HIGH','MEDIUM','LOW'))
);
CREATE INDEX idx_inspection_items_inspection_id ON inspection_items(inspection_id);

-- QUOTATIONS — Priced quotation produced from an inspection (UC23–UC25, BR18).
CREATE TABLE quotations (
    quotation_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quotation_code         VARCHAR(20) NOT NULL UNIQUE,
    inspection_id          BIGINT NOT NULL
        REFERENCES inspections(inspection_id) ON DELETE RESTRICT,
    prepared_by            BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    parent_quotation_id    BIGINT
        REFERENCES quotations(quotation_id) ON DELETE RESTRICT,
    subtotal               NUMERIC(14,2) NOT NULL DEFAULT 0,
    vat_amount             NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_amount           NUMERIC(14,2) NOT NULL DEFAULT 0,
    status                 VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
    valid_until            TIMESTAMPTZ,
    sent_at                TIMESTAMPTZ,
    responded_at           TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_quotations_1 CHECK (total_amount >= 0),
    CONSTRAINT chk_quotations_2 CHECK (status IN ('DRAFT','SENT','PARTIALLY_APPROVED','APPROVED','REJECTED','EXPIRED'))
);
CREATE INDEX idx_quotations_inspection_id ON quotations(inspection_id);

-- QUOTATION_ITEMS — Line items with item-level customer decision (BR19–BR20).
CREATE TABLE quotation_items (
    item_id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quotation_id           BIGINT NOT NULL
        REFERENCES quotations(quotation_id) ON DELETE RESTRICT,
    item_type              VARCHAR(10) NOT NULL,
    service_id             BIGINT
        REFERENCES services(service_id) ON DELETE RESTRICT,
    part_id                BIGINT
        REFERENCES parts(part_id) ON DELETE RESTRICT,
    description            VARCHAR(255) NOT NULL,
    quantity               NUMERIC(10,2) NOT NULL DEFAULT 1,
    unit_price             NUMERIC(14,2) NOT NULL,
    line_total             NUMERIC(14,2) NOT NULL,
    is_warranty            BOOLEAN NOT NULL DEFAULT FALSE,
    expected_wait_days     SMALLINT,
    decision               VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    decided_at             TIMESTAMPTZ,
    CONSTRAINT chk_quotation_items_1 CHECK (item_type IN ('SERVICE','PART','LABOR')),
    CONSTRAINT chk_quotation_items_2 CHECK (quantity > 0),
    CONSTRAINT chk_quotation_items_3 CHECK (unit_price >= 0),
    CONSTRAINT chk_quotation_items_4 CHECK (decision IN ('PENDING','APPROVED','REJECTED'))
);
CREATE INDEX idx_quotation_items_quotation_id ON quotation_items(quotation_id);

-- REPAIR_ORDER_TYPES — Repair order categories with SLA.
CREATE TABLE repair_order_types (
    type_id                SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_code              VARCHAR(20) NOT NULL UNIQUE,
    type_name              VARCHAR(100) NOT NULL,
    sla_hours              SMALLINT,
    description            VARCHAR(255)
);

-- REPAIR_ORDERS — Workshop repair order created from approved items (UC26–UC32, BR21).
CREATE TABLE repair_orders (
    repair_order_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ro_code                VARCHAR(20) NOT NULL UNIQUE,
    quotation_id           BIGINT NOT NULL UNIQUE
        REFERENCES quotations(quotation_id) ON DELETE RESTRICT,
    branch_id              BIGINT NOT NULL
        REFERENCES branches(branch_id) ON DELETE RESTRICT,
    type_id                SMALLINT NOT NULL
        REFERENCES repair_order_types(type_id) ON DELETE RESTRICT,
    created_by             BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    status                 VARCHAR(20) NOT NULL DEFAULT 'NEW',
    total_cost             NUMERIC(14,2) NOT NULL DEFAULT 0,
    started_at             TIMESTAMPTZ,
    completed_at           TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_repair_orders_1 CHECK (status IN ('NEW','ASSIGNED','IN_PROGRESS','WAITING_PARTS','COMPLETED','CLOSED')),
    CONSTRAINT chk_repair_orders_2 CHECK (total_cost >= 0)
);
CREATE INDEX idx_repair_orders_branch_id_status ON repair_orders(branch_id, status);

-- REPAIR_TASKS — Tasks of a repair order assigned to mechanics (BR22).
CREATE TABLE repair_tasks (
    task_id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    repair_order_id        BIGINT NOT NULL
        REFERENCES repair_orders(repair_order_id) ON DELETE RESTRICT,
    quotation_item_id      BIGINT
        REFERENCES quotation_items(item_id) ON DELETE RESTRICT,
    mechanic_id            BIGINT
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    task_name              VARCHAR(200) NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'TODO',
    progress_percent       SMALLINT NOT NULL DEFAULT 0,
    labor_hours            NUMERIC(5,2) NOT NULL DEFAULT 0,
    started_at             TIMESTAMPTZ,
    finished_at            TIMESTAMPTZ,
    CONSTRAINT chk_repair_tasks_1 CHECK (status IN ('TODO','DOING','BLOCKED','DONE')),
    CONSTRAINT chk_repair_tasks_2 CHECK (progress_percent BETWEEN 0 AND 100),
    CONSTRAINT chk_repair_tasks_3 CHECK (labor_hours >= 0)
);
CREATE INDEX idx_repair_tasks_repair_order_id ON repair_tasks(repair_order_id);
CREATE INDEX idx_repair_tasks_mechanic_id_status ON repair_tasks(mechanic_id, status);

-- REPAIR_NOTES — Technical notes recorded during repair (UC30).
CREATE TABLE repair_notes (
    note_id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    repair_order_id        BIGINT NOT NULL
        REFERENCES repair_orders(repair_order_id) ON DELETE RESTRICT,
    task_id                BIGINT
        REFERENCES repair_tasks(task_id) ON DELETE RESTRICT,
    author_id              BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    content                TEXT NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_repair_notes_repair_order_id ON repair_notes(repair_order_id);

-- WAREHOUSES — Spare-part storage of each branch.
CREATE TABLE warehouses (
    warehouse_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id              BIGINT NOT NULL
        REFERENCES branches(branch_id) ON DELETE RESTRICT,
    warehouse_name         VARCHAR(100) NOT NULL,
    location               VARCHAR(255),
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
);
CREATE INDEX idx_warehouses_branch_id ON warehouses(branch_id);

-- INVENTORIES — On-hand and reserved stock per warehouse and part (UC35, BR25–BR26).
CREATE TABLE inventories (
    inventory_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_id           BIGINT NOT NULL
        REFERENCES warehouses(warehouse_id) ON DELETE RESTRICT,
    part_id                BIGINT NOT NULL
        REFERENCES parts(part_id) ON DELETE RESTRICT,
    quantity_on_hand       INTEGER NOT NULL DEFAULT 0,
    quantity_reserved      INTEGER NOT NULL DEFAULT 0,
    reorder_level          INTEGER NOT NULL DEFAULT 0,
    version                INTEGER NOT NULL DEFAULT 0,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_inventories_warehouse_id_part_id UNIQUE (warehouse_id, part_id),
    CONSTRAINT chk_inventories_1 CHECK (quantity_on_hand >= 0),
    CONSTRAINT chk_inventories_2 CHECK (quantity_reserved BETWEEN 0 AND quantity_on_hand),
    CONSTRAINT chk_inventories_3 CHECK (reorder_level >= 0)
);

-- INVENTORY_RECEIPTS — Stock receiving documents (UC34).
CREATE TABLE inventory_receipts (
    receipt_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_code           VARCHAR(20) NOT NULL UNIQUE,
    warehouse_id           BIGINT NOT NULL
        REFERENCES warehouses(warehouse_id) ON DELETE RESTRICT,
    supplier_name          VARCHAR(150) NOT NULL,
    received_by            BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    receipt_date           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    note                   VARCHAR(500)
);

-- INVENTORY_RECEIPT_ITEMS — Parts, quantities and costs in a receipt.
CREATE TABLE inventory_receipt_items (
    receipt_item_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_id             BIGINT NOT NULL
        REFERENCES inventory_receipts(receipt_id) ON DELETE RESTRICT,
    part_id                BIGINT NOT NULL
        REFERENCES parts(part_id) ON DELETE RESTRICT,
    quantity               INTEGER NOT NULL,
    unit_cost              NUMERIC(14,2) NOT NULL,
    CONSTRAINT chk_inventory_receipt_items_1 CHECK (quantity > 0),
    CONSTRAINT chk_inventory_receipt_items_2 CHECK (unit_cost >= 0)
);
CREATE INDEX idx_inventory_receipt_items_receipt_id ON inventory_receipt_items(receipt_id);

-- PART_RESERVATIONS — Parts reserved for a repair order (UC36, BR26).
CREATE TABLE part_reservations (
    reservation_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    repair_order_id        BIGINT NOT NULL
        REFERENCES repair_orders(repair_order_id) ON DELETE RESTRICT,
    quotation_item_id      BIGINT
        REFERENCES quotation_items(item_id) ON DELETE RESTRICT,
    inventory_id           BIGINT NOT NULL
        REFERENCES inventories(inventory_id) ON DELETE RESTRICT,
    quantity               INTEGER NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'RESERVED',
    reserved_by            BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_part_reservations_1 CHECK (quantity > 0),
    CONSTRAINT chk_part_reservations_2 CHECK (status IN ('RESERVED','ISSUED','RELEASED'))
);
CREATE INDEX idx_part_reservations_repair_order_id ON part_reservations(repair_order_id);

-- PART_REQUESTS — Internal parts request from a mechanic to the receptionist (UC37).
CREATE TABLE part_requests (
    request_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_code           VARCHAR(20) NOT NULL UNIQUE,
    repair_order_id        BIGINT NOT NULL
        REFERENCES repair_orders(repair_order_id) ON DELETE RESTRICT,
    task_id                BIGINT
        REFERENCES repair_tasks(task_id) ON DELETE RESTRICT,
    requested_by           BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    status                 VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    note                   VARCHAR(500),
    processed_by           BIGINT
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    processed_at           TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_part_requests_1 CHECK (status IN ('PENDING','PARTIALLY_ISSUED','ISSUED','REJECTED'))
);
CREATE INDEX idx_part_requests_repair_order_id ON part_requests(repair_order_id);
CREATE INDEX idx_part_requests_status ON part_requests(status);

-- PART_REQUEST_ITEMS — Parts and quantities in a parts request (UC37–UC38).
CREATE TABLE part_request_items (
    request_item_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id             BIGINT NOT NULL
        REFERENCES part_requests(request_id) ON DELETE RESTRICT,
    quotation_item_id      BIGINT NOT NULL
        REFERENCES quotation_items(item_id) ON DELETE RESTRICT,
    part_id                BIGINT NOT NULL
        REFERENCES parts(part_id) ON DELETE RESTRICT,
    quantity_requested     INTEGER NOT NULL,
    quantity_issued        INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT chk_part_request_items_1 CHECK (quantity_requested > 0),
    CONSTRAINT chk_part_request_items_2 CHECK (quantity_issued BETWEEN 0 AND quantity_requested)
);
CREATE INDEX idx_part_request_items_request_id ON part_request_items(request_id);

-- REPAIR_TASK_PARTS — Parts actually issued to / returned from a repair task (UC38–UC39, BR28).
CREATE TABLE repair_task_parts (
    task_part_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    task_id                BIGINT NOT NULL
        REFERENCES repair_tasks(task_id) ON DELETE RESTRICT,
    inventory_id           BIGINT NOT NULL
        REFERENCES inventories(inventory_id) ON DELETE RESTRICT,
    reservation_id         BIGINT
        REFERENCES part_reservations(reservation_id) ON DELETE RESTRICT,
    request_item_id        BIGINT
        REFERENCES part_request_items(request_item_id) ON DELETE RESTRICT,
    quantity_issued        INTEGER NOT NULL,
    quantity_returned      INTEGER NOT NULL DEFAULT 0,
    unit_price             NUMERIC(14,2) NOT NULL,
    issued_by              BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    issued_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_repair_task_parts_1 CHECK (quantity_issued > 0),
    CONSTRAINT chk_repair_task_parts_2 CHECK (quantity_returned BETWEEN 0 AND quantity_issued)
);
CREATE INDEX idx_repair_task_parts_task_id ON repair_task_parts(task_id);

-- INVENTORY_TRANSACTIONS — Immutable stock movement ledger (UC40, BR27).
CREATE TABLE inventory_transactions (
    transaction_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inventory_id           BIGINT NOT NULL
        REFERENCES inventories(inventory_id) ON DELETE RESTRICT,
    transaction_type       VARCHAR(20) NOT NULL,
    quantity               INTEGER NOT NULL,
    balance_after          INTEGER NOT NULL,
    reference_type         VARCHAR(30) NOT NULL,
    reference_id           BIGINT NOT NULL,
    performed_by           BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_inventory_transactions_1 CHECK (transaction_type IN ('RECEIPT','RESERVE','RELEASE','ISSUE','RETURN','ADJUST')),
    CONSTRAINT chk_inventory_transactions_2 CHECK (quantity <> 0)
);
CREATE INDEX idx_inventory_transactions_inventory_id_created_at ON inventory_transactions(inventory_id, created_at);

-- WARRANTY_POLICIES — Warranty terms for services or parts (UC43).
CREATE TABLE warranty_policies (
    policy_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    policy_code            VARCHAR(20) NOT NULL UNIQUE,
    policy_name            VARCHAR(150) NOT NULL,
    applies_to             VARCHAR(10) NOT NULL,
    service_id             BIGINT
        REFERENCES services(service_id) ON DELETE RESTRICT,
    part_id                BIGINT
        REFERENCES parts(part_id) ON DELETE RESTRICT,
    duration_months        SMALLINT NOT NULL,
    max_odometer_km        INTEGER,
    terms                  TEXT NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_warranty_policies_1 CHECK (applies_to IN ('SERVICE','PART')),
    CONSTRAINT chk_warranty_policies_2 CHECK (duration_months > 0),
    CONSTRAINT chk_warranty_policies_3 CHECK ((applies_to='SERVICE' AND service_id IS NOT NULL) OR (applies_to='PART' AND part_id IS NOT NULL))
);

-- WARRANTIES — Warranty records auto-created after settlement (UC44, BR35).
CREATE TABLE warranties (
    warranty_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warranty_code          VARCHAR(20) NOT NULL UNIQUE,
    policy_id              BIGINT NOT NULL
        REFERENCES warranty_policies(policy_id) ON DELETE RESTRICT,
    vehicle_id             BIGINT NOT NULL
        REFERENCES vehicles(vehicle_id) ON DELETE RESTRICT,
    repair_order_id        BIGINT NOT NULL
        REFERENCES repair_orders(repair_order_id) ON DELETE RESTRICT,
    quotation_item_id      BIGINT
        REFERENCES quotation_items(item_id) ON DELETE RESTRICT,
    start_date             DATE NOT NULL,
    end_date               DATE NOT NULL,
    start_odometer         INTEGER NOT NULL,
    max_odometer           INTEGER,
    status                 VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_warranties_1 CHECK (end_date > start_date),
    CONSTRAINT chk_warranties_2 CHECK (status IN ('ACTIVE','EXPIRED','VOID'))
);
CREATE INDEX idx_warranties_vehicle_id_status ON warranties(vehicle_id, status);

-- WARRANTY_REQUESTS — Customer warranty claims and their assessment/approval (UC45–UC47, UC49).
CREATE TABLE warranty_requests (
    request_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_code           VARCHAR(20) NOT NULL UNIQUE,
    warranty_id            BIGINT NOT NULL
        REFERENCES warranties(warranty_id) ON DELETE RESTRICT,
    customer_id            BIGINT NOT NULL
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    branch_id              BIGINT NOT NULL
        REFERENCES branches(branch_id) ON DELETE RESTRICT,
    issue_description      TEXT NOT NULL,
    current_odometer       INTEGER NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'SUBMITTED',
    is_eligible            BOOLEAN,
    assessed_by            BIGINT
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    assessment_note        TEXT,
    approved_by            BIGINT
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    decided_at             TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_warranty_requests_1 CHECK (status IN ('SUBMITTED','ASSESSED','APPROVED','REJECTED','IN_REPAIR','COMPLETED'))
);
CREATE INDEX idx_warranty_requests_branch_id_status ON warranty_requests(branch_id, status);

-- WARRANTY_REPAIRS — Repair performed for an approved claim with internal cost (UC48, UC50, BR34, BR36).
CREATE TABLE warranty_repairs (
    warranty_repair_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id             BIGINT NOT NULL UNIQUE
        REFERENCES warranty_requests(request_id) ON DELETE RESTRICT,
    repair_order_id        BIGINT NOT NULL
        REFERENCES repair_orders(repair_order_id) ON DELETE RESTRICT,
    internal_cost          NUMERIC(14,2) NOT NULL DEFAULT 0,
    customer_charge        NUMERIC(14,2) NOT NULL DEFAULT 0,
    repair_date            DATE NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_warranty_repairs_1 CHECK (internal_cost >= 0),
    CONSTRAINT chk_warranty_repairs_2 CHECK (customer_charge >= 0)
);

-- TAX_RULES — Effective-dated VAT rules (UC51, BR38).
CREATE TABLE tax_rules (
    tax_rule_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_type              VARCHAR(10) NOT NULL,
    vat_rate               NUMERIC(5,2) NOT NULL,
    effective_from         DATE NOT NULL,
    effective_to           DATE,
    created_by             BIGINT NOT NULL
        REFERENCES users(user_id) ON DELETE RESTRICT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_tax_rules_1 CHECK (vat_rate BETWEEN 0 AND 100),
    CONSTRAINT chk_tax_rules_2 CHECK (effective_to IS NULL OR effective_to > effective_from)
);
CREATE INDEX idx_tax_rules_item_type_effective_from ON tax_rules(item_type, effective_from);

-- EINVOICE_CONFIGS — Seller and MISA meInvoice integration settings (UC51).
CREATE TABLE einvoice_configs (
    config_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    provider               VARCHAR(30) NOT NULL DEFAULT 'MISA_MEINVOICE',
    seller_name            VARCHAR(255) NOT NULL,
    seller_tax_code        VARCHAR(14) NOT NULL,
    seller_address         VARCHAR(255) NOT NULL,
    api_base_url           VARCHAR(255) NOT NULL,
    invoice_template       VARCHAR(20) NOT NULL,
    invoice_series         VARCHAR(10) NOT NULL,
    credential_ref         VARCHAR(255) NOT NULL,
    is_active              BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- INVOICES — Finalized charges of a repair order (UC52, BR37, BR39).
CREATE TABLE invoices (
    invoice_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_code           VARCHAR(20) NOT NULL UNIQUE,
    repair_order_id        BIGINT NOT NULL UNIQUE
        REFERENCES repair_orders(repair_order_id) ON DELETE RESTRICT,
    billing_id             BIGINT
        REFERENCES billing_information(billing_id) ON DELETE RESTRICT,
    subtotal               NUMERIC(14,2) NOT NULL DEFAULT 0,
    discount_amount        NUMERIC(14,2) NOT NULL DEFAULT 0,
    vat_amount             NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_amount           NUMERIC(14,2) NOT NULL DEFAULT 0,
    payment_status         VARCHAR(20) NOT NULL DEFAULT 'UNPAID',
    status                 VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
    finalized_by           BIGINT
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    finalized_at           TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_invoices_1 CHECK (total_amount >= 0),
    CONSTRAINT chk_invoices_2 CHECK (payment_status IN ('UNPAID','PAID')),
    CONSTRAINT chk_invoices_3 CHECK (status IN ('DRAFT','FINALIZED','VOID'))
);
CREATE INDEX idx_invoices_payment_status_created_at ON invoices(payment_status, created_at);

-- INVOICE_LINES — Charge lines from performed services, labour and issued parts.
CREATE TABLE invoice_lines (
    line_id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id             BIGINT NOT NULL
        REFERENCES invoices(invoice_id) ON DELETE RESTRICT,
    quotation_item_id      BIGINT
        REFERENCES quotation_items(item_id) ON DELETE RESTRICT,
    item_type              VARCHAR(10) NOT NULL,
    description            VARCHAR(255) NOT NULL,
    quantity               NUMERIC(10,2) NOT NULL,
    unit_price             NUMERIC(14,2) NOT NULL,
    vat_rate               NUMERIC(5,2) NOT NULL,
    vat_amount             NUMERIC(14,2) NOT NULL,
    line_total             NUMERIC(14,2) NOT NULL,
    is_warranty_covered    BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT chk_invoice_lines_1 CHECK (quantity > 0),
    CONSTRAINT chk_invoice_lines_2 CHECK (unit_price >= 0)
);
CREATE INDEX idx_invoice_lines_invoice_id ON invoice_lines(invoice_id);

-- PAYMENTS — Payment transactions recorded by the cashier (UC53).
CREATE TABLE payments (
    payment_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id             BIGINT NOT NULL
        REFERENCES invoices(invoice_id) ON DELETE RESTRICT,
    amount                 NUMERIC(14,2) NOT NULL,
    method                 VARCHAR(20) NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'SUCCESS',
    transaction_ref        VARCHAR(100),
    received_by            BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    paid_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_payments_1 CHECK (amount > 0),
    CONSTRAINT chk_payments_2 CHECK (method IN ('CASH','CARD','BANK_TRANSFER','E_WALLET')),
    CONSTRAINT chk_payments_3 CHECK (status IN ('SUCCESS','FAILED','REFUNDED'))
);
CREATE INDEX idx_payments_invoice_id ON payments(invoice_id);

-- E_INVOICES — Electronic invoices issued via MISA meInvoice incl. corrections (UC54–UC57, BR40–BR43).
CREATE TABLE e_invoices (
    e_invoice_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id             BIGINT NOT NULL
        REFERENCES invoices(invoice_id) ON DELETE RESTRICT,
    config_id              BIGINT NOT NULL
        REFERENCES einvoice_configs(config_id) ON DELETE RESTRICT,
    original_e_invoice_id  BIGINT
        REFERENCES e_invoices(e_invoice_id) ON DELETE RESTRICT,
    buyer_name             VARCHAR(255) NOT NULL,
    buyer_tax_code         VARCHAR(14),
    buyer_address          VARCHAR(255) NOT NULL,
    buyer_email            VARCHAR(150) NOT NULL,
    external_invoice_no    VARCHAR(20),
    invoice_series         VARCHAR(10) NOT NULL,
    lookup_code            VARCHAR(50),
    external_status        VARCHAR(30),
    attempt_count          SMALLINT NOT NULL DEFAULT 0,
    status                 VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    correction_type        VARCHAR(20),
    correction_reason      VARCHAR(500),
    response_payload       JSONB,
    issued_at              TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_e_invoices_1 CHECK (status IN ('PENDING','ISSUED','FAILED','ADJUSTED','REPLACED','CANCELLED')),
    CONSTRAINT chk_e_invoices_2 CHECK (correction_type IS NULL OR correction_type IN ('ADJUSTMENT','REPLACEMENT'))
);
CREATE INDEX idx_e_invoices_invoice_id ON e_invoices(invoice_id);
CREATE INDEX idx_e_invoices_status ON e_invoices(status);

-- VEHICLE_HANDOVERS — Vehicle handover after payment (UC59, BR44–BR45).
CREATE TABLE vehicle_handovers (
    handover_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id         BIGINT NOT NULL UNIQUE
        REFERENCES appointments(appointment_id) ON DELETE RESTRICT,
    invoice_id             BIGINT NOT NULL
        REFERENCES invoices(invoice_id) ON DELETE RESTRICT,
    handed_by              BIGINT NOT NULL
        REFERENCES staff(staff_id) ON DELETE RESTRICT,
    odometer_out           INTEGER NOT NULL,
    customer_confirmed     BOOLEAN NOT NULL DEFAULT FALSE,
    note                   VARCHAR(500),
    handed_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partial unique indexes for business rules
CREATE UNIQUE INDEX uq_billing_default ON billing_information(customer_id) WHERE is_default;
CREATE UNIQUE INDEX uq_einvoice_config_active ON einvoice_configs(is_active) WHERE is_active;

-- Immutable inventory ledger (BR27): forbid UPDATE / DELETE
CREATE OR REPLACE FUNCTION fn_block_modify() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'inventory_transactions is append-only'; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_inventory_tx_immutable BEFORE UPDATE OR DELETE ON inventory_transactions
    FOR EACH ROW EXECUTE FUNCTION fn_block_modify();

-- Seed roles
INSERT INTO roles(role_code, role_name) VALUES
  ('CUSTOMER','Customer'),('RECEPTIONIST','Receptionist'),('MECHANIC','Mechanic'),
  ('CASHIER','Cashier'),('BRANCH_MANAGER','Branch Manager'),('SYS_ADMIN','System Administrator');

-- Capacity-safe booking (NFR-4) – executed inside one transaction:
--   SELECT * FROM time_slots WHERE slot_id = $1 FOR UPDATE;
--   UPDATE time_slots SET booked_count = booked_count + 1
--     WHERE slot_id = $1 AND booked_count < capacity;   -- 0 rows => slot full

-- =====================================================================
-- AutoCare – sample data for the whole project (generated by seed_generator.py)
-- Run AFTER 01_schema.sql.  All demo accounts: password = Password@123
-- =====================================================================
BEGIN;

-- branches (3 rows)
INSERT INTO branches (branch_id, branch_code, branch_name, address, phone, email, status, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'HN-CG01', 'AutoCare Cầu Giấy', '123 Trần Duy Hưng, Cầu Giấy, Hà Nội', '024 3999 1111', 'caugiay@autocare.vn', 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (2, 'HN-HD01', 'AutoCare Hà Đông', '45 Quang Trung, Hà Đông, Hà Nội', '024 3999 2222', 'hadong@autocare.vn', 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (3, 'HCM-Q701', 'AutoCare Quận 7', '88 Nguyễn Thị Thập, Quận 7, TP.HCM', '028 3999 3333', 'quan7@autocare.vn', 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07');

-- users (34 rows)
INSERT INTO users (user_id, role_id, email, phone, password_hash, full_name, status, failed_login_count, locked_until, last_login_at, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 6, 'admin@autocare.vn', '0900000001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Nguyễn Trường Giang', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (2, 5, 'manager.cg@autocare.vn', '0910000001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Phạm Minh Quân', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (3, 2, 'reception1.cg@autocare.vn', '0910100001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Lê Thu Hà', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (4, 2, 'reception2.cg@autocare.vn', '0910200001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Nguyễn Hoàng Nam', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (5, 4, 'cashier.cg@autocare.vn', '0910300001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Trần Bảo Ngọc', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (6, 3, 'mechanic1.cg@autocare.vn', '0910400001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Đỗ Văn Hùng', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (7, 3, 'mechanic2.cg@autocare.vn', '0910500001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Vũ Đức Thắng', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (8, 3, 'mechanic3.cg@autocare.vn', '0910600001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Bùi Quốc Khánh', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (9, 5, 'manager.hd@autocare.vn', '0920000002', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Hoàng Thị Lan', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (10, 2, 'reception1.hd@autocare.vn', '0920100002', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Ngô Quang Huy', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (11, 2, 'reception2.hd@autocare.vn', '0920200002', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Đặng Mai Anh', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (12, 4, 'cashier.hd@autocare.vn', '0920300002', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Phan Thanh Tùng', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (13, 3, 'mechanic1.hd@autocare.vn', '0920400002', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Trịnh Văn Long', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (14, 3, 'mechanic2.hd@autocare.vn', '0920500002', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Lý Minh Tuấn', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (15, 3, 'mechanic3.hd@autocare.vn', '0920600002', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Mai Xuân Phúc', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (16, 5, 'manager.q7@autocare.vn', '0930000003', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Võ Thị Hồng', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (17, 2, 'reception1.q7@autocare.vn', '0930100003', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Huỳnh Gia Bảo', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (18, 2, 'reception2.q7@autocare.vn', '0930200003', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Châu Ngọc Trâm', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (19, 4, 'cashier.q7@autocare.vn', '0930300003', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Dương Minh Khoa', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (20, 3, 'mechanic1.q7@autocare.vn', '0930400003', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Tạ Văn Lộc', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (21, 3, 'mechanic2.q7@autocare.vn', '0930500003', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'La Hoàng Sơn', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (22, 3, 'mechanic3.q7@autocare.vn', '0930600003', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Kiều Anh Dũng', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-01-06 08:00:00+07', '2026-01-06 08:00:00+07'),
  (23, 1, 'customer1@gmail.com', '0912000001', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Nguyễn Văn An', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (24, 1, 'customer2@gmail.com', '0912000002', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Trần Thị Bình', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (25, 1, 'customer3@gmail.com', '0912000003', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Lê Hoàng Cường', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (26, 1, 'customer4@gmail.com', '0912000004', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Phạm Thu Dung', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (27, 1, 'customer5@gmail.com', '0912000005', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Hoàng Minh Đức', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (28, 1, 'customer6@gmail.com', '0912000006', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Vũ Thị Giang', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (29, 1, 'customer7@gmail.com', '0912000007', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Đặng Quốc Huy', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (30, 1, 'customer8@gmail.com', '0912000008', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Bùi Thanh Hương', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (31, 1, 'customer9@gmail.com', '0912000009', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Ngô Đức Khải', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (32, 1, 'customer10@gmail.com', '0912000010', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Đỗ Thị Lan', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (33, 1, 'customer11@gmail.com', '0912000011', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Phan Văn Minh', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07'),
  (34, 1, 'customer12@gmail.com', '0912000012', '$2a$10$xtHB3STb9XwUrZZAfXRN.uTnUIfGXvyLj0tvOT/PwwzzoC.SnIJ76', 'Trịnh Ngọc Oanh', 'ACTIVE', 0, NULL, '2026-11-07 17:30:00+07', '2026-02-01 08:00:00+07', '2026-02-01 08:00:00+07');

-- customers (12 rows)
INSERT INTO customers (customer_id, user_id, date_of_birth, gender, address, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 23, '1986-02-11', 'MALE', '12 Láng Hạ, Đống Đa, Hà Nội', '2026-02-01 08:00:00+07'),
  (2, 24, '1987-03-12', 'FEMALE', '56 Kim Mã, Ba Đình, Hà Nội', '2026-02-01 08:00:00+07'),
  (3, 25, '1988-04-13', 'MALE', '8 Xuân Thủy, Cầu Giấy, Hà Nội', '2026-02-01 08:00:00+07'),
  (4, 26, '1989-05-14', 'FEMALE', '102 Nguyễn Trãi, Thanh Xuân, Hà Nội', '2026-02-01 08:00:00+07'),
  (5, 27, '1990-06-15', 'MALE', '21 Hoàng Quốc Việt, Cầu Giấy, Hà Nội', '2026-02-01 08:00:00+07'),
  (6, 28, '1991-07-16', 'FEMALE', '77 Lê Văn Lương, Thanh Xuân, Hà Nội', '2026-02-01 08:00:00+07'),
  (7, 29, '1992-08-17', 'MALE', '15 Quang Trung, Hà Đông, Hà Nội', '2026-02-01 08:00:00+07'),
  (8, 30, '1993-09-18', 'FEMALE', '40 Trần Phú, Hà Đông, Hà Nội', '2026-02-01 08:00:00+07'),
  (9, 31, '1994-01-10', 'MALE', '9 Duy Tân, Cầu Giấy, Hà Nội', '2026-02-01 08:00:00+07'),
  (10, 32, '1995-02-11', 'FEMALE', '200 Nguyễn Văn Linh, Quận 7, TP.HCM', '2026-02-01 08:00:00+07'),
  (11, 33, '1996-03-12', 'MALE', '31 Phạm Hùng, Nam Từ Liêm, Hà Nội', '2026-02-01 08:00:00+07'),
  (12, 34, '1985-04-13', 'FEMALE', '66 Mễ Trì, Nam Từ Liêm, Hà Nội', '2026-02-01 08:00:00+07');

-- staff (22 rows)
INSERT INTO staff (staff_id, user_id, branch_id, staff_code, position, hired_date, status, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, NULL, 'NV0001', 'SYS_ADMIN', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (2, 2, 1, 'NV0002', 'BRANCH_MANAGER', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (3, 3, 1, 'NV0003', 'RECEPTIONIST', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (4, 4, 1, 'NV0004', 'RECEPTIONIST', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (5, 5, 1, 'NV0005', 'CASHIER', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (6, 6, 1, 'NV0006', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (7, 7, 1, 'NV0007', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (8, 8, 1, 'NV0008', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (9, 9, 2, 'NV0009', 'BRANCH_MANAGER', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (10, 10, 2, 'NV0010', 'RECEPTIONIST', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (11, 11, 2, 'NV0011', 'RECEPTIONIST', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (12, 12, 2, 'NV0012', 'CASHIER', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (13, 13, 2, 'NV0013', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (14, 14, 2, 'NV0014', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (15, 15, 2, 'NV0015', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (16, 16, 3, 'NV0016', 'BRANCH_MANAGER', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (17, 17, 3, 'NV0017', 'RECEPTIONIST', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (18, 18, 3, 'NV0018', 'RECEPTIONIST', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (19, 19, 3, 'NV0019', 'CASHIER', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (20, 20, 3, 'NV0020', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (21, 21, 3, 'NV0021', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07'),
  (22, 22, 3, 'NV0022', 'MECHANIC', '2026-01-01', 'ACTIVE', '2026-01-06 08:00:00+07');

-- billing_information (6 rows)
INSERT INTO billing_information (billing_id, customer_id, buyer_type, buyer_name, company_name, tax_code, billing_address, invoice_email, is_default, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 'INDIVIDUAL', 'Nguyễn Văn An', NULL, NULL, '12 Láng Hạ, Đống Đa, Hà Nội', 'customer1@gmail.com', TRUE, '2026-02-02 08:00:00+07', '2026-02-02 08:00:00+07'),
  (2, 2, 'COMPANY', 'Trần Thị Bình', 'Công ty TNHH Bình An', '0101234567', '56 Kim Mã, Ba Đình, Hà Nội', 'customer2@gmail.com', TRUE, '2026-02-02 08:00:00+07', '2026-02-02 08:00:00+07'),
  (3, 3, 'INDIVIDUAL', 'Lê Hoàng Cường', NULL, NULL, '8 Xuân Thủy, Cầu Giấy, Hà Nội', 'customer3@gmail.com', TRUE, '2026-02-02 08:00:00+07', '2026-02-02 08:00:00+07'),
  (4, 6, 'COMPANY', 'Vũ Thị Giang', 'Công ty CP Vận tải Giang Sơn', '0109876543', '77 Lê Văn Lương, Thanh Xuân, Hà Nội', 'customer6@gmail.com', TRUE, '2026-02-02 08:00:00+07', '2026-02-02 08:00:00+07'),
  (5, 7, 'INDIVIDUAL', 'Đặng Quốc Huy', NULL, NULL, '15 Quang Trung, Hà Đông, Hà Nội', 'customer7@gmail.com', TRUE, '2026-02-02 08:00:00+07', '2026-02-02 08:00:00+07'),
  (6, 10, 'INDIVIDUAL', 'Đỗ Thị Lan', NULL, NULL, '200 Nguyễn Văn Linh, Quận 7, TP.HCM', 'customer10@gmail.com', TRUE, '2026-02-02 08:00:00+07', '2026-02-02 08:00:00+07');

-- vehicles (28 rows)
INSERT INTO vehicles (vehicle_id, customer_id, license_plate, vehicle_type, brand, model, manufacture_year, vin, color, current_odometer, status, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, '30A-123.45', 'CAR', 'Toyota', 'Vios 1.5G', 2020, NULL, 'Đen', 45200, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (2, 2, '30G-456.78', 'CAR', 'Honda', 'City RS', 2022, NULL, 'Bạc', 21800, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (3, 1, '29B1-234.56', 'MOTORCYCLE', 'Honda', 'Wave Alpha', 2019, NULL, 'Đỏ', 30500, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (4, 3, '30E-987.65', 'CAR', 'Mazda', 'Mazda3 1.5', 2021, NULL, 'Xanh', 38700, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (5, 4, '30F-111.22', 'CAR', 'Kia', 'Morning', 2018, NULL, 'Trắng', 72100, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (6, 5, '30H-222.33', 'CAR', 'Hyundai', 'Accent 1.4AT', 2021, NULL, 'Đen', 40100, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (7, 6, '29C-345.67', 'CAR', 'Ford', 'Ranger XLS', 2020, NULL, 'Bạc', 88400, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (8, 6, '29C-345.68', 'CAR', 'Ford', 'Transit', 2019, NULL, 'Đỏ', 120300, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (9, 7, '29D-456.12', 'CAR', 'Toyota', 'Innova 2.0E', 2019, NULL, 'Xanh', 95000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (10, 8, '30K-567.89', 'CAR', 'Mitsubishi', 'Xpander AT', 2022, NULL, 'Trắng', 26500, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (11, 9, '30L-678.90', 'CAR', 'VinFast', 'Fadil', 2021, NULL, 'Đen', 33300, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (12, 10, '51G-789.01', 'CAR', 'Toyota', 'Corolla Cross', 2023, NULL, 'Bạc', 15800, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (13, 10, '59X1-890.12', 'MOTORCYCLE', 'Yamaha', 'Exciter 155', 2022, NULL, 'Đỏ', 18200, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (14, 11, '30M-901.23', 'CAR', 'Toyota', 'Innova Cross', 2023, NULL, 'Xanh', 12400, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (15, 12, '30N-012.34', 'CAR', 'Honda', 'CR-V L', 2022, NULL, 'Trắng', 30900, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (16, 12, '29E1-135.79', 'MOTORCYCLE', 'Honda', 'Air Blade', 2021, NULL, 'Đen', 22000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (17, 8, '29F-246.80', 'CAR', 'Kia', 'Seltos', 2023, NULL, 'Bạc', 9800, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (18, 3, '29G-112.23', 'CAR', 'Suzuki', 'XL7', 2022, NULL, 'Đỏ', 41000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (19, 2, '30G-789.12', 'CAR', 'Toyota', 'Camry 2.5Q', 2021, NULL, 'Xanh', 52000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (20, 5, '30H-345.21', 'CAR', 'Honda', 'Civic RS', 2022, NULL, 'Trắng', 28000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (21, 9, '29A-654.32', 'CAR', 'Mazda', 'CX-5 2.0', 2020, NULL, 'Đen', 61000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (22, 11, '29H1-777.88', 'MOTORCYCLE', 'Honda', 'SH 150i', 2023, NULL, 'Bạc', 8000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (23, 4, '30E-246.13', 'CAR', 'Hyundai', 'Tucson 2.0', 2022, NULL, 'Đỏ', 35500, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (24, 6, '30K-135.79', 'CAR', 'Toyota', 'Fortuner 2.7', 2021, NULL, 'Xanh', 58000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (25, 12, '30L-864.20', 'CAR', 'Kia', 'Carnival', 2022, NULL, 'Trắng', 31000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (26, 3, '30M-555.66', 'CAR', 'Ford', 'Everest', 2020, NULL, 'Đen', 76000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (27, 8, '30A-246.80', 'CAR', 'Honda', 'HR-V', 2023, NULL, 'Bạc', 12000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07'),
  (28, 11, '30F-777.12', 'CAR', 'Mazda', 'CX-3', 2022, NULL, 'Đỏ', 20000, 'ACTIVE', '2026-02-03 08:00:00+07', '2026-02-03 08:00:00+07');

-- services (10 rows)
INSERT INTO services (service_id, service_code, service_name, description, vehicle_type, base_price, estimated_minutes, status, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'SV-OIL', 'Thay dầu động cơ', 'Xả dầu cũ, thay dầu mới và lọc dầu', 'ALL', 350000, 30, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (2, 'SV-BRAKE', 'Kiểm tra & thay má phanh', 'Kiểm tra hệ thống phanh, thay má phanh, xả gió dầu phanh', 'CAR', 250000, 60, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (3, 'SV-MAINT10', 'Bảo dưỡng định kỳ 10.000 km', 'Gói bảo dưỡng tổng quát theo khuyến cáo hãng', 'CAR', 900000, 120, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (4, 'SV-AC', 'Vệ sinh & nạp gas điều hòa', 'Vệ sinh dàn lạnh, kiểm tra rò rỉ và nạp gas', 'CAR', 600000, 90, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (5, 'SV-TIRE', 'Đảo lốp & cân bằng động', 'Đảo lốp, cân bằng động và kiểm tra áp suất', 'CAR', 300000, 45, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (6, 'SV-BATT', 'Kiểm tra & thay ắc quy', 'Đo điện áp, kiểm tra máy phát và thay ắc quy', 'ALL', 150000, 30, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (7, 'SV-ENGINE', 'Chẩn đoán động cơ', 'Đọc lỗi OBD, kiểm tra bugi, kim phun', 'CAR', 400000, 60, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (8, 'SV-SUSP', 'Kiểm tra hệ thống treo', 'Kiểm tra giảm xóc, rotuyn, cao su chân máy', 'CAR', 350000, 60, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (9, 'SV-MOTO-MAINT', 'Bảo dưỡng xe máy', 'Thay nhớt, vệ sinh nồi, kiểm tra xích và bugi', 'MOTORCYCLE', 200000, 45, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (10, 'SV-WASH', 'Rửa xe & vệ sinh nội thất', 'Rửa bọt tuyết, hút bụi, lau nội thất', 'ALL', 150000, 40, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07');

-- branch_services (30 rows)
INSERT INTO branch_services (branch_id, service_id, is_enabled, branch_price, updated_at) VALUES
  (1, 1, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 2, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 3, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 4, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 5, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 6, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 7, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 8, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 9, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (1, 10, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 1, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 2, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 3, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 4, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 5, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 6, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 7, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 8, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 9, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (2, 10, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 1, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 2, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 3, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 4, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 5, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 6, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 7, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 8, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 9, TRUE, NULL, '2026-01-05 08:00:00+07'),
  (3, 10, TRUE, NULL, '2026-01-05 08:00:00+07');

-- parts (20 rows)
INSERT INTO parts (part_id, sku, part_name, category, unit, unit_price, status, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'OIL-5W30-1L', 'Dầu động cơ 5W-30 (1L)', 'Dầu nhớt', 'liter', 180000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (2, 'FLT-OIL', 'Lọc dầu động cơ', 'Lọc', 'pcs', 120000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (3, 'FLT-AIR', 'Lọc gió động cơ', 'Lọc', 'pcs', 250000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (4, 'FLT-CABIN', 'Lọc gió điều hòa', 'Lọc', 'pcs', 220000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (5, 'BRK-PAD-FR', 'Má phanh trước (bộ)', 'Phanh', 'set', 850000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (6, 'BRK-DISC-FR', 'Đĩa phanh trước', 'Phanh', 'pcs', 1200000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (7, 'BRK-FLUID-DOT4', 'Dầu phanh DOT4 (0.5L)', 'Phanh', 'pcs', 150000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (8, 'BAT-12V-45AH', 'Ắc quy 12V 45Ah', 'Điện', 'pcs', 1650000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (9, 'AC-GAS-R134A', 'Gas điều hòa R134a (bình)', 'Điều hòa', 'pcs', 450000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (10, 'SPK-PLUG-IR', 'Bugi Iridium', 'Đánh lửa', 'pcs', 280000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (11, 'SHOCK-FR', 'Giảm xóc trước', 'Treo', 'pcs', 1900000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (12, 'TIRE-185-60R15', 'Lốp 185/60R15', 'Lốp', 'pcs', 1450000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (13, 'WIPER-24', 'Gạt mưa 24 inch', 'Phụ kiện', 'pcs', 180000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (14, 'COOLANT-1L', 'Nước làm mát (1L)', 'Dung dịch', 'liter', 120000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (15, 'BELT-ALT', 'Dây curoa máy phát', 'Động cơ', 'pcs', 520000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (16, 'MOTO-OIL-08L', 'Dầu nhớt xe máy 0.8L', 'Dầu nhớt', 'pcs', 110000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (17, 'MOTO-SPK', 'Bugi xe máy', 'Đánh lửa', 'pcs', 60000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (18, 'MOTO-CHAIN', 'Bộ nhông xích xe máy', 'Truyền động', 'set', 650000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (19, 'BULB-H4', 'Bóng đèn pha H4', 'Điện', 'pcs', 160000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07'),
  (20, 'TRANS-OIL-1L', 'Dầu hộp số (1L)', 'Dầu nhớt', 'liter', 230000, 'ACTIVE', '2026-01-05 08:00:00+07', '2026-01-05 08:00:00+07');

-- repair_order_types (4 rows)
INSERT INTO repair_order_types (type_id, type_code, type_name, sla_hours, description) OVERRIDING SYSTEM VALUE VALUES
  (1, 'MAINTENANCE', 'Bảo dưỡng', 4, 'Bảo dưỡng định kỳ'),
  (2, 'REPAIR', 'Sửa chữa', 24, 'Sửa chữa thông thường'),
  (3, 'BREAKDOWN', 'Cứu hộ / hỏng hóc', 48, 'Xe hỏng phải kéo về xưởng'),
  (4, 'WARRANTY', 'Bảo hành', 24, 'Sửa chữa bảo hành');

-- warehouses (3 rows)
INSERT INTO warehouses (warehouse_id, branch_id, warehouse_name, location, status) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 'Kho phụ tùng chính', 'Tầng 1, khu B', 'ACTIVE'),
  (2, 2, 'Kho phụ tùng chính', 'Tầng 1, khu B', 'ACTIVE'),
  (3, 3, 'Kho phụ tùng chính', 'Tầng 1, khu B', 'ACTIVE');

-- inventories (60 rows)
INSERT INTO inventories (inventory_id, warehouse_id, part_id, quantity_on_hand, quantity_reserved, reorder_level, version, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, 99, 16, 5, 0, '2026-11-08 07:00:00+07'),
  (2, 1, 2, 45, 3, 5, 0, '2026-11-08 07:00:00+07'),
  (3, 1, 3, 39, 2, 5, 0, '2026-11-08 07:00:00+07'),
  (4, 1, 4, 29, 2, 5, 0, '2026-11-08 07:00:00+07'),
  (5, 1, 5, 26, 1, 5, 0, '2026-11-08 07:00:00+07'),
  (6, 1, 6, 6, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (7, 1, 7, 29, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (8, 1, 8, 7, 1, 5, 0, '2026-11-08 07:00:00+07'),
  (9, 1, 9, 28, 1, 5, 0, '2026-11-08 07:00:00+07'),
  (10, 1, 10, 26, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (11, 1, 11, 4, 2, 5, 0, '2026-11-08 07:00:00+07'),
  (12, 1, 12, 12, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (13, 1, 13, 4, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (14, 1, 14, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (15, 1, 15, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (16, 1, 16, 30, 1, 5, 0, '2026-11-08 07:00:00+07'),
  (17, 1, 17, 30, 1, 5, 0, '2026-11-08 07:00:00+07'),
  (18, 1, 18, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (19, 1, 19, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (20, 1, 20, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (21, 2, 1, 76, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (22, 2, 2, 29, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (23, 2, 3, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (24, 2, 4, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (25, 2, 5, 30, 1, 5, 0, '2026-11-08 07:00:00+07'),
  (26, 2, 6, 6, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (27, 2, 7, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (28, 2, 8, 8, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (29, 2, 9, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (30, 2, 10, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (31, 2, 11, 4, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (32, 2, 12, 12, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (33, 2, 13, 4, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (34, 2, 14, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (35, 2, 15, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (36, 2, 16, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (37, 2, 17, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (38, 2, 18, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (39, 2, 19, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (40, 2, 20, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (41, 3, 1, 80, 5, 5, 0, '2026-11-08 07:00:00+07'),
  (42, 3, 2, 30, 1, 5, 0, '2026-11-08 07:00:00+07'),
  (43, 3, 3, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (44, 3, 4, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (45, 3, 5, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (46, 3, 6, 6, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (47, 3, 7, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (48, 3, 8, 8, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (49, 3, 9, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (50, 3, 10, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (51, 3, 11, 4, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (52, 3, 12, 12, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (53, 3, 13, 4, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (54, 3, 14, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (55, 3, 15, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (56, 3, 16, 29, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (57, 3, 17, 29, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (58, 3, 18, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (59, 3, 19, 30, 0, 5, 0, '2026-11-08 07:00:00+07'),
  (60, 3, 20, 30, 0, 5, 0, '2026-11-08 07:00:00+07');

-- inventory_receipts (4 rows)
INSERT INTO inventory_receipts (receipt_id, receipt_code, warehouse_id, supplier_name, received_by, receipt_date, note) OVERRIDING SYSTEM VALUE VALUES
  (1, 'GR-261001-001', 1, 'Công ty CP Phụ tùng Ô tô Việt', 3, '2026-10-01 09:00:00+07', 'Nhập kho đầu kỳ'),
  (2, 'GR-261001-002', 2, 'Công ty CP Phụ tùng Ô tô Việt', 10, '2026-10-01 09:00:00+07', 'Nhập kho đầu kỳ'),
  (3, 'GR-261001-003', 3, 'Công ty CP Phụ tùng Ô tô Việt', 17, '2026-10-01 09:00:00+07', 'Nhập kho đầu kỳ'),
  (4, 'GR-261102-001', 1, 'Công ty TNHH Dầu nhớt Sài Gòn', 4, '2026-11-02 14:00:00+07', 'Bổ sung dầu nhớt và lọc');

-- inventory_receipt_items (63 rows)
INSERT INTO inventory_receipt_items (receipt_item_id, receipt_id, part_id, quantity, unit_cost) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, 80, 126000.0),
  (2, 1, 2, 30, 84000.0),
  (3, 1, 3, 30, 175000.0),
  (4, 1, 4, 30, 154000.0),
  (5, 1, 5, 30, 595000.0),
  (6, 1, 6, 6, 840000.0),
  (7, 1, 7, 30, 105000.0),
  (8, 1, 8, 8, 1155000.0),
  (9, 1, 9, 30, 315000.0),
  (10, 1, 10, 30, 196000.0),
  (11, 1, 11, 4, 1330000.0),
  (12, 1, 12, 12, 1015000.0),
  (13, 1, 13, 4, 126000.0),
  (14, 1, 14, 30, 84000.0),
  (15, 1, 15, 30, 364000.0),
  (16, 1, 16, 30, 77000.0),
  (17, 1, 17, 30, 42000.0),
  (18, 1, 18, 30, 455000.0),
  (19, 1, 19, 30, 112000.0),
  (20, 1, 20, 30, 161000.0),
  (21, 2, 1, 80, 126000.0),
  (22, 2, 2, 30, 84000.0),
  (23, 2, 3, 30, 175000.0),
  (24, 2, 4, 30, 154000.0),
  (25, 2, 5, 30, 595000.0),
  (26, 2, 6, 6, 840000.0),
  (27, 2, 7, 30, 105000.0),
  (28, 2, 8, 8, 1155000.0),
  (29, 2, 9, 30, 315000.0),
  (30, 2, 10, 30, 196000.0),
  (31, 2, 11, 4, 1330000.0),
  (32, 2, 12, 12, 1015000.0),
  (33, 2, 13, 4, 126000.0),
  (34, 2, 14, 30, 84000.0),
  (35, 2, 15, 30, 364000.0),
  (36, 2, 16, 30, 77000.0),
  (37, 2, 17, 30, 42000.0),
  (38, 2, 18, 30, 455000.0),
  (39, 2, 19, 30, 112000.0),
  (40, 2, 20, 30, 161000.0),
  (41, 3, 1, 80, 126000.0),
  (42, 3, 2, 30, 84000.0),
  (43, 3, 3, 30, 175000.0),
  (44, 3, 4, 30, 154000.0),
  (45, 3, 5, 30, 595000.0),
  (46, 3, 6, 6, 840000.0),
  (47, 3, 7, 30, 105000.0),
  (48, 3, 8, 8, 1155000.0),
  (49, 3, 9, 30, 315000.0),
  (50, 3, 10, 30, 196000.0),
  (51, 3, 11, 4, 1330000.0),
  (52, 3, 12, 12, 1015000.0),
  (53, 3, 13, 4, 126000.0),
  (54, 3, 14, 30, 84000.0),
  (55, 3, 15, 30, 364000.0),
  (56, 3, 16, 30, 77000.0),
  (57, 3, 17, 30, 42000.0),
  (58, 3, 18, 30, 455000.0),
  (59, 3, 19, 30, 112000.0),
  (60, 3, 20, 30, 161000.0),
  (61, 4, 1, 40, 126000.0),
  (62, 4, 2, 20, 84000.0),
  (63, 4, 3, 10, 175000.0);

-- warranty_policies (4 rows)
INSERT INTO warranty_policies (policy_id, policy_code, policy_name, applies_to, service_id, part_id, duration_months, max_odometer_km, terms, status, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'WP-BRAKE-6M', 'Bảo hành dịch vụ phanh 6 tháng', 'SERVICE', 2, NULL, 6, 10000, 'Bảo hành tay nghề thay má phanh trong 6 tháng hoặc 10.000 km.', 'ACTIVE', '2026-01-05 08:00:00+07'),
  (2, 'WP-MAINT-3M', 'Bảo hành bảo dưỡng 3 tháng', 'SERVICE', 3, NULL, 3, 5000, 'Bảo hành lỗi do quá trình bảo dưỡng.', 'ACTIVE', '2026-01-05 08:00:00+07'),
  (3, 'WP-PAD-6M', 'Bảo hành má phanh 6 tháng', 'PART', NULL, 5, 6, 10000, 'Bảo hành lỗi vật liệu má phanh.', 'ACTIVE', '2026-01-05 08:00:00+07'),
  (4, 'WP-BATT-12M', 'Bảo hành ắc quy 12 tháng', 'PART', NULL, 8, 12, NULL, 'Bảo hành 1 đổi 1 khi ắc quy lỗi nhà sản xuất.', 'ACTIVE', '2026-01-05 08:00:00+07');

-- tax_rules (6 rows)
INSERT INTO tax_rules (tax_rule_id, item_type, vat_rate, effective_from, effective_to, created_by, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'SERVICE', 10, '2025-01-01', '2025-12-31', 1, '2025-12-20 08:00:00+07'),
  (2, 'PART', 10, '2025-01-01', '2025-12-31', 1, '2025-12-20 08:00:00+07'),
  (3, 'LABOR', 10, '2025-01-01', '2025-12-31', 1, '2025-12-20 08:00:00+07'),
  (4, 'SERVICE', 8, '2026-01-01', NULL, 1, '2025-12-20 08:00:00+07'),
  (5, 'PART', 8, '2026-01-01', NULL, 1, '2025-12-20 08:00:00+07'),
  (6, 'LABOR', 8, '2026-01-01', NULL, 1, '2025-12-20 08:00:00+07');

-- einvoice_configs (1 rows)
INSERT INTO einvoice_configs (config_id, provider, seller_name, seller_tax_code, seller_address, api_base_url, invoice_template, invoice_series, credential_ref, is_active, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'MISA_MEINVOICE', 'Công ty CP Dịch vụ Ô tô AutoCare', '0108888888', '123 Trần Duy Hưng, Cầu Giấy, Hà Nội', 'https://testapi.meinvoice.vn/api/integration', '1', 'C26TAC', 'secret://autocare/misa-meinvoice', TRUE, '2026-01-05 08:00:00+07');

-- time_slots: 08:00–16:00 hourly, 01/10/2026 – 30/11/2026, capacity 4, all branches
INSERT INTO time_slots(branch_id, slot_date, start_time, end_time, capacity, booked_count, status)
SELECT b.branch_id, d::date, make_time(h,0,0), make_time(h+1,0,0), 4, 0, 'OPEN'
FROM branches b, generate_series(DATE '2026-10-01', DATE '2026-11-30', INTERVAL '1 day') d, generate_series(8,16) h;

-- appointments (37 rows)
INSERT INTO appointments (appointment_id, appointment_code, customer_id, vehicle_id, branch_id, slot_id, status, customer_note, reject_reason, cancel_reason, confirmed_by, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'APT-261012-0001', 1, 1, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-10-12' AND start_time='08:00'), 'COMPLETED', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-10-09 08:00:00+07', '2026-10-12 08:00:00+07'),
  (2, 'APT-261020-0001', 2, 2, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-10-20' AND start_time='09:00'), 'COMPLETED', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-10-17 09:00:00+07', '2026-10-20 09:00:00+07'),
  (3, 'APT-261105-0001', 3, 4, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-05' AND start_time='08:00'), 'WAITING_PAYMENT', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-02 08:00:00+07', '2026-11-05 08:00:00+07'),
  (4, 'APT-261106-0001', 4, 5, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-06' AND start_time='10:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-03 10:00:00+07', '2026-11-06 10:00:00+07'),
  (5, 'APT-261107-0001', 5, 6, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-07' AND start_time='08:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-04 08:00:00+07', '2026-11-07 08:00:00+07'),
  (6, 'APT-261107-0002', 6, 7, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-07' AND start_time='09:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-04 09:00:00+07', '2026-11-07 09:00:00+07'),
  (7, 'APT-261107-0003', 8, 10, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-07' AND start_time='13:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-04 13:00:00+07', '2026-11-07 13:00:00+07'),
  (8, 'APT-261108-0001', 9, 11, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='08:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 08:00:00+07', '2026-11-08 08:00:00+07'),
  (9, 'APT-261108-0002', 11, 14, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='09:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 09:00:00+07', '2026-11-08 09:00:00+07'),
  (10, 'APT-261108-0003', 12, 15, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='10:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 10:00:00+07', '2026-11-08 10:00:00+07'),
  (11, 'APT-261108-0004', 1, 3, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='10:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 10:00:00+07', '2026-11-08 10:00:00+07'),
  (12, 'APT-261108-0005', 10, 12, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='11:00'), 'CHECKED_IN', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 11:00:00+07', '2026-11-08 11:00:00+07'),
  (13, 'APT-261108-0006', 12, 16, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='13:00'), 'CHECKED_IN', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 13:00:00+07', '2026-11-08 13:00:00+07'),
  (14, 'APT-261110-0001', 1, 1, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-10' AND start_time='08:00'), 'CONFIRMED', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-07 08:00:00+07', '2026-11-10 08:00:00+07'),
  (15, 'APT-261111-0001', 2, 2, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-11' AND start_time='09:00'), 'PENDING', 'Đèn check engine sáng', NULL, NULL, NULL, '2026-11-08 09:00:00+07', '2026-11-11 09:00:00+07'),
  (16, 'APT-261112-0001', 3, 18, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-12' AND start_time='14:00'), 'PENDING', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, NULL, '2026-11-09 14:00:00+07', '2026-11-12 14:00:00+07'),
  (17, 'APT-261103-0001', 3, 4, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-03' AND start_time='09:00'), 'CANCELLED', 'Xe cần kiểm tra theo lịch hẹn', NULL, 'Khách bận đột xuất', NULL, '2026-10-31 09:00:00+07', '2026-11-03 09:00:00+07'),
  (18, 'APT-261104-0001', 6, 8, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-04' AND start_time='15:00'), 'REJECTED', 'Xe cần kiểm tra theo lịch hẹn', 'Xưởng quá tải trong khung giờ này', NULL, NULL, '2026-11-01 15:00:00+07', '2026-11-04 15:00:00+07'),
  (19, 'APT-261015-0001', 7, 9, 2, (SELECT slot_id FROM time_slots WHERE branch_id=2 AND slot_date='2026-10-15' AND start_time='09:00'), 'COMPLETED', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 10, '2026-10-12 09:00:00+07', '2026-10-15 09:00:00+07'),
  (20, 'APT-261107-0004', 8, 17, 2, (SELECT slot_id FROM time_slots WHERE branch_id=2 AND slot_date='2026-11-07' AND start_time='10:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 10, '2026-11-04 10:00:00+07', '2026-11-07 10:00:00+07'),
  (21, 'APT-261108-0007', 7, 9, 2, (SELECT slot_id FROM time_slots WHERE branch_id=2 AND slot_date='2026-11-08' AND start_time='14:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 10, '2026-11-05 14:00:00+07', '2026-11-08 14:00:00+07'),
  (22, 'APT-261112-0002', 7, 9, 2, (SELECT slot_id FROM time_slots WHERE branch_id=2 AND slot_date='2026-11-12' AND start_time='10:00'), 'PENDING', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, NULL, '2026-11-09 10:00:00+07', '2026-11-12 10:00:00+07'),
  (23, 'APT-261025-0001', 10, 13, 3, (SELECT slot_id FROM time_slots WHERE branch_id=3 AND slot_date='2026-10-25' AND start_time='08:00'), 'COMPLETED', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 17, '2026-10-22 08:00:00+07', '2026-10-25 08:00:00+07'),
  (24, 'APT-261108-0008', 10, 12, 3, (SELECT slot_id FROM time_slots WHERE branch_id=3 AND slot_date='2026-11-08' AND start_time='09:00'), 'IN_SERVICE', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 17, '2026-11-05 09:00:00+07', '2026-11-08 09:00:00+07'),
  (25, 'APT-261113-0001', 10, 12, 3, (SELECT slot_id FROM time_slots WHERE branch_id=3 AND slot_date='2026-11-13' AND start_time='09:00'), 'CONFIRMED', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 17, '2026-11-10 09:00:00+07', '2026-11-13 09:00:00+07'),
  (26, 'APT-261109-0001', 2, 19, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-09' AND start_time='09:00'), 'CONFIRMED', 'Xe đến hạn bảo dưỡng 50.000 km', NULL, NULL, 3, '2026-11-06 09:00:00+07', '2026-11-09 09:00:00+07'),
  (27, 'APT-261109-0002', 5, 20, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-09' AND start_time='10:00'), 'CONFIRMED', 'Phanh hơi kêu, lốp mòn không đều', NULL, NULL, 3, '2026-11-06 10:00:00+07', '2026-11-09 10:00:00+07'),
  (28, 'APT-261109-0003', 11, 22, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-09' AND start_time='14:00'), 'PENDING', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, NULL, '2026-11-06 14:00:00+07', '2026-11-09 14:00:00+07'),
  (29, 'APT-261109-0004', 6, 8, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-09' AND start_time='08:00'), 'CHECKED_IN', 'Đèn check engine sáng, máy rung khi chạy không tải', NULL, NULL, NULL, '2026-11-06 08:00:00+07', '2026-11-09 08:00:00+07'),
  (30, 'APT-261109-0005', 4, 23, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-09' AND start_time='09:00'), 'CHECKED_IN', 'Điều hòa không mát', NULL, NULL, 3, '2026-11-06 09:00:00+07', '2026-11-09 09:00:00+07'),
  (31, 'APT-261108-0009', 9, 21, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='15:00'), 'CHECKED_IN', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 15:00:00+07', '2026-11-08 15:00:00+07'),
  (32, 'APT-261108-0010', 2, 2, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='16:00'), 'CHECKED_IN', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 16:00:00+07', '2026-11-08 16:00:00+07'),
  (33, 'APT-261108-0011', 6, 24, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='08:00'), 'WAITING_PAYMENT', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 08:00:00+07', '2026-11-08 08:00:00+07'),
  (34, 'APT-261108-0012', 12, 25, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-08' AND start_time='11:00'), 'WAITING_PAYMENT', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-05 11:00:00+07', '2026-11-08 11:00:00+07'),
  (35, 'APT-261107-0005', 3, 26, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-07' AND start_time='14:00'), 'WAITING_PAYMENT', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-04 14:00:00+07', '2026-11-07 14:00:00+07'),
  (36, 'APT-261106-0002', 8, 27, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-06' AND start_time='15:00'), 'WAITING_PAYMENT', 'Xe cần kiểm tra theo lịch hẹn', NULL, NULL, 3, '2026-11-03 15:00:00+07', '2026-11-06 15:00:00+07'),
  (37, 'APT-261107-0006', 11, 28, 1, (SELECT slot_id FROM time_slots WHERE branch_id=1 AND slot_date='2026-11-07' AND start_time='10:00'), 'WAITING_PAYMENT', 'Bảo hành má phanh – không thu phí', NULL, NULL, 3, '2026-11-04 10:00:00+07', '2026-11-07 10:00:00+07');

-- appointment_services (52 rows)
INSERT INTO appointment_services (appointment_id, service_id, estimated_price) VALUES
  (1, 3, 900000),
  (1, 2, 250000),
  (2, 4, 600000),
  (2, 6, 150000),
  (2, 5, 300000),
  (3, 1, 350000),
  (3, 5, 300000),
  (4, 2, 250000),
  (5, 7, 400000),
  (5, 1, 350000),
  (6, 3, 900000),
  (6, 8, 350000),
  (7, 2, 250000),
  (7, 5, 300000),
  (8, 4, 600000),
  (8, 6, 150000),
  (9, 1, 350000),
  (9, 10, 150000),
  (10, 3, 900000),
  (11, 9, 200000),
  (12, 1, 350000),
  (12, 7, 400000),
  (13, 9, 200000),
  (14, 10, 150000),
  (15, 7, 400000),
  (16, 1, 350000),
  (17, 1, 350000),
  (18, 3, 900000),
  (19, 1, 350000),
  (20, 2, 250000),
  (21, 5, 300000),
  (22, 4, 600000),
  (23, 9, 200000),
  (24, 3, 900000),
  (25, 10, 150000),
  (26, 3, 900000),
  (27, 2, 250000),
  (27, 5, 300000),
  (28, 9, 200000),
  (29, 7, 400000),
  (30, 4, 600000),
  (31, 8, 350000),
  (31, 1, 350000),
  (32, 2, 250000),
  (32, 8, 350000),
  (32, 6, 150000),
  (33, 1, 350000),
  (33, 5, 300000),
  (34, 3, 900000),
  (35, 2, 250000),
  (36, 4, 600000),
  (37, 2, 250000);

-- vehicle_receptions (27 rows)
INSERT INTO vehicle_receptions (reception_id, appointment_id, received_by, odometer_reading, vehicle_condition, checked_in_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 3, 45320, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-10-12 08:00:00+07'),
  (2, 2, 3, 21920, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-10-20 09:00:00+07'),
  (3, 3, 3, 38820, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-05 08:00:00+07'),
  (4, 4, 3, 72220, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-06 10:00:00+07'),
  (5, 5, 3, 40220, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-07 08:00:00+07'),
  (6, 6, 3, 88520, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-07 09:00:00+07'),
  (7, 7, 3, 26620, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-07 13:00:00+07'),
  (8, 8, 3, 33420, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 08:00:00+07'),
  (9, 9, 3, 12520, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 09:00:00+07'),
  (10, 10, 3, 31020, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 10:00:00+07'),
  (11, 11, 3, 30620, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 10:00:00+07'),
  (12, 12, 3, 15920, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 11:00:00+07'),
  (13, 13, 3, 22120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 13:00:00+07'),
  (14, 19, 10, 95120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-10-15 09:00:00+07'),
  (15, 20, 10, 9920, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-07 10:00:00+07'),
  (16, 21, 10, 95120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 14:00:00+07'),
  (17, 23, 17, 18320, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-10-25 08:00:00+07'),
  (18, 24, 17, 15920, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 09:00:00+07'),
  (19, 29, 3, 120420, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-09 08:00:00+07'),
  (20, 30, 3, 35620, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-09 09:00:00+07'),
  (21, 31, 3, 61120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 15:00:00+07'),
  (22, 32, 3, 21920, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 16:00:00+07'),
  (23, 33, 3, 58120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 08:00:00+07'),
  (24, 34, 3, 31120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-08 11:00:00+07'),
  (25, 35, 3, 76120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-07 14:00:00+07'),
  (26, 36, 3, 12120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-06 15:00:00+07'),
  (27, 37, 3, 20120, 'Xe trầy nhẹ cản sau, nhiên liệu 1/2 bình, không có đồ giá trị', '2026-11-07 10:00:00+07');

-- inspections (26 rows)
INSERT INTO inspections (inspection_id, reception_id, mechanic_id, assigned_by, status, result_summary, assigned_at, completed_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-10-12 08:10:00+07', '2026-10-12 08:50:00+07'),
  (2, 2, 7, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-10-20 09:10:00+07', '2026-10-20 09:50:00+07'),
  (3, 3, 7, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-05 08:10:00+07', '2026-11-05 08:50:00+07'),
  (4, 4, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-06 10:10:00+07', '2026-11-06 10:50:00+07'),
  (5, 5, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-07 08:10:00+07', '2026-11-07 08:50:00+07'),
  (6, 6, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-07 09:10:00+07', '2026-11-07 09:50:00+07'),
  (7, 7, 7, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-07 13:10:00+07', '2026-11-07 13:50:00+07'),
  (8, 8, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 08:10:00+07', '2026-11-08 08:50:00+07'),
  (9, 9, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 09:10:00+07', '2026-11-08 09:50:00+07'),
  (10, 10, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 10:10:00+07', '2026-11-08 10:50:00+07'),
  (11, 11, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 10:10:00+07', '2026-11-08 10:50:00+07'),
  (12, 12, 8, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 11:10:00+07', '2026-11-08 11:50:00+07'),
  (13, 13, 8, 3, 'ASSIGNED', NULL, '2026-11-08 13:10:00+07', NULL),
  (14, 14, 13, 10, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-10-15 09:10:00+07', '2026-10-15 09:50:00+07'),
  (15, 15, 13, 10, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-07 10:10:00+07', '2026-11-07 10:50:00+07'),
  (16, 16, 13, 10, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 14:10:00+07', '2026-11-08 14:50:00+07'),
  (17, 17, 20, 17, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-10-25 08:10:00+07', '2026-10-25 08:50:00+07'),
  (18, 18, 20, 17, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 09:10:00+07', '2026-11-08 09:50:00+07'),
  (19, 20, 6, 3, 'ASSIGNED', NULL, '2026-11-09 09:10:00+07', NULL),
  (20, 21, 7, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 15:10:00+07', '2026-11-08 15:50:00+07'),
  (21, 22, 8, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 16:10:00+07', '2026-11-08 16:50:00+07'),
  (22, 23, 7, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 08:10:00+07', '2026-11-08 08:50:00+07'),
  (23, 24, 8, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-08 11:10:00+07', '2026-11-08 11:50:00+07'),
  (24, 25, 6, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-07 14:10:00+07', '2026-11-07 14:50:00+07'),
  (25, 26, 7, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-06 15:10:00+07', '2026-11-06 15:50:00+07'),
  (26, 27, 8, 3, 'COMPLETED', 'Đã kiểm tra tổng quát; đề xuất các hạng mục bên dưới.', '2026-11-07 10:10:00+07', '2026-11-07 10:50:00+07');

-- inspection_items (90 rows)
INSERT INTO inspection_items (inspection_item_id, inspection_id, item_type, service_id, part_id, description, quantity, priority, note, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 'HIGH', NULL, '2026-10-12 08:50:00+07'),
  (2, 1, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 'MEDIUM', NULL, '2026-10-12 08:50:00+07'),
  (3, 1, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 4, 'MEDIUM', NULL, '2026-10-12 08:50:00+07'),
  (4, 1, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-10-12 08:50:00+07'),
  (5, 1, 'PART', NULL, 5, 'Cần thay má phanh trước (bộ)', 1, 'MEDIUM', NULL, '2026-10-12 08:50:00+07'),
  (6, 2, 'SERVICE', 4, NULL, 'Vệ sinh & nạp gas điều hòa', 1, 'HIGH', NULL, '2026-10-20 09:50:00+07'),
  (7, 2, 'SERVICE', 6, NULL, 'Kiểm tra & thay ắc quy', 1, 'MEDIUM', NULL, '2026-10-20 09:50:00+07'),
  (8, 2, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 'MEDIUM', NULL, '2026-10-20 09:50:00+07'),
  (9, 2, 'PART', NULL, 4, 'Cần thay lọc gió điều hòa', 1, 'MEDIUM', NULL, '2026-10-20 09:50:00+07'),
  (10, 2, 'PART', NULL, 8, 'Cần thay ắc quy 12v 45ah', 1, 'MEDIUM', NULL, '2026-10-20 09:50:00+07'),
  (11, 2, 'PART', NULL, 9, 'Cần thay gas điều hòa r134a (bình)', 1, 'MEDIUM', NULL, '2026-10-20 09:50:00+07'),
  (12, 3, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 'HIGH', NULL, '2026-11-05 08:50:00+07'),
  (13, 3, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 'MEDIUM', NULL, '2026-11-05 08:50:00+07'),
  (14, 3, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 4, 'MEDIUM', NULL, '2026-11-05 08:50:00+07'),
  (15, 3, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-05 08:50:00+07'),
  (16, 4, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 'HIGH', NULL, '2026-11-06 10:50:00+07'),
  (17, 4, 'PART', NULL, 5, 'Cần thay má phanh trước (bộ)', 1, 'MEDIUM', NULL, '2026-11-06 10:50:00+07'),
  (18, 4, 'PART', NULL, 7, 'Cần thay dầu phanh dot4 (0.5l)', 1, 'MEDIUM', NULL, '2026-11-06 10:50:00+07'),
  (19, 5, 'SERVICE', 7, NULL, 'Chẩn đoán động cơ', 1, 'HIGH', NULL, '2026-11-07 08:50:00+07'),
  (20, 5, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-07 08:50:00+07'),
  (21, 5, 'PART', NULL, 10, 'Cần thay bugi iridium', 4, 'MEDIUM', NULL, '2026-11-07 08:50:00+07'),
  (22, 5, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 4, 'MEDIUM', NULL, '2026-11-07 08:50:00+07'),
  (23, 5, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-07 08:50:00+07'),
  (24, 6, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 'HIGH', NULL, '2026-11-07 09:50:00+07'),
  (25, 6, 'SERVICE', 8, NULL, 'Kiểm tra hệ thống treo', 1, 'MEDIUM', NULL, '2026-11-07 09:50:00+07'),
  (26, 6, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 6, 'MEDIUM', NULL, '2026-11-07 09:50:00+07'),
  (27, 6, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-07 09:50:00+07'),
  (28, 6, 'PART', NULL, 3, 'Cần thay lọc gió động cơ', 1, 'MEDIUM', NULL, '2026-11-07 09:50:00+07'),
  (29, 6, 'PART', NULL, 11, 'Cần thay giảm xóc trước', 2, 'MEDIUM', NULL, '2026-11-07 09:50:00+07'),
  (30, 7, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 'HIGH', NULL, '2026-11-07 13:50:00+07'),
  (31, 7, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 'MEDIUM', NULL, '2026-11-07 13:50:00+07'),
  (32, 7, 'PART', NULL, 6, 'Cần thay đĩa phanh trước', 2, 'MEDIUM', NULL, '2026-11-07 13:50:00+07'),
  (33, 7, 'PART', NULL, 5, 'Cần thay má phanh trước (bộ)', 1, 'MEDIUM', NULL, '2026-11-07 13:50:00+07'),
  (34, 8, 'SERVICE', 4, NULL, 'Vệ sinh & nạp gas điều hòa', 1, 'HIGH', NULL, '2026-11-08 08:50:00+07'),
  (35, 8, 'SERVICE', 6, NULL, 'Kiểm tra & thay ắc quy', 1, 'MEDIUM', NULL, '2026-11-08 08:50:00+07'),
  (36, 8, 'PART', NULL, 4, 'Cần thay lọc gió điều hòa', 1, 'MEDIUM', NULL, '2026-11-08 08:50:00+07'),
  (37, 8, 'PART', NULL, 9, 'Cần thay gas điều hòa r134a (bình)', 1, 'MEDIUM', NULL, '2026-11-08 08:50:00+07'),
  (38, 8, 'PART', NULL, 8, 'Cần thay ắc quy 12v 45ah', 1, 'MEDIUM', NULL, '2026-11-08 08:50:00+07'),
  (39, 9, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 'HIGH', NULL, '2026-11-08 09:50:00+07'),
  (40, 9, 'SERVICE', 10, NULL, 'Rửa xe & vệ sinh nội thất', 1, 'MEDIUM', NULL, '2026-11-08 09:50:00+07'),
  (41, 9, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 5, 'MEDIUM', NULL, '2026-11-08 09:50:00+07'),
  (42, 9, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-08 09:50:00+07'),
  (43, 10, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 'HIGH', NULL, '2026-11-08 10:50:00+07'),
  (44, 10, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 5, 'MEDIUM', NULL, '2026-11-08 10:50:00+07'),
  (45, 10, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-08 10:50:00+07'),
  (46, 10, 'PART', NULL, 3, 'Cần thay lọc gió động cơ', 1, 'MEDIUM', NULL, '2026-11-08 10:50:00+07'),
  (47, 10, 'PART', NULL, 4, 'Cần thay lọc gió điều hòa', 1, 'MEDIUM', NULL, '2026-11-08 10:50:00+07'),
  (48, 11, 'SERVICE', 9, NULL, 'Bảo dưỡng xe máy', 1, 'HIGH', NULL, '2026-11-08 10:50:00+07'),
  (49, 11, 'PART', NULL, 16, 'Cần thay dầu nhớt xe máy 0.8l', 1, 'MEDIUM', NULL, '2026-11-08 10:50:00+07'),
  (50, 11, 'PART', NULL, 17, 'Cần thay bugi xe máy', 1, 'MEDIUM', NULL, '2026-11-08 10:50:00+07'),
  (51, 12, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 'HIGH', NULL, '2026-11-08 11:50:00+07'),
  (52, 12, 'SERVICE', 7, NULL, 'Chẩn đoán động cơ', 1, 'MEDIUM', NULL, '2026-11-08 11:50:00+07'),
  (53, 12, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 4, 'MEDIUM', NULL, '2026-11-08 11:50:00+07'),
  (54, 12, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-08 11:50:00+07'),
  (55, 14, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 'HIGH', NULL, '2026-10-15 09:50:00+07'),
  (56, 14, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 4, 'MEDIUM', NULL, '2026-10-15 09:50:00+07'),
  (57, 14, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-10-15 09:50:00+07'),
  (58, 15, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 'HIGH', NULL, '2026-11-07 10:50:00+07'),
  (59, 15, 'PART', NULL, 5, 'Cần thay má phanh trước (bộ)', 1, 'MEDIUM', NULL, '2026-11-07 10:50:00+07'),
  (60, 16, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 'HIGH', NULL, '2026-11-08 14:50:00+07'),
  (61, 17, 'SERVICE', 9, NULL, 'Bảo dưỡng xe máy', 1, 'HIGH', NULL, '2026-10-25 08:50:00+07'),
  (62, 17, 'PART', NULL, 16, 'Cần thay dầu nhớt xe máy 0.8l', 1, 'MEDIUM', NULL, '2026-10-25 08:50:00+07'),
  (63, 17, 'PART', NULL, 17, 'Cần thay bugi xe máy', 1, 'MEDIUM', NULL, '2026-10-25 08:50:00+07'),
  (64, 18, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 'HIGH', NULL, '2026-11-08 09:50:00+07'),
  (65, 18, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 5, 'MEDIUM', NULL, '2026-11-08 09:50:00+07'),
  (66, 18, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-08 09:50:00+07'),
  (67, 20, 'SERVICE', 8, NULL, 'Kiểm tra hệ thống treo', 1, 'HIGH', NULL, '2026-11-08 15:50:00+07'),
  (68, 20, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-08 15:50:00+07'),
  (69, 20, 'PART', NULL, 11, 'Cần thay giảm xóc trước', 4, 'MEDIUM', NULL, '2026-11-08 15:50:00+07'),
  (70, 20, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 4, 'MEDIUM', NULL, '2026-11-08 15:50:00+07'),
  (71, 20, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-08 15:50:00+07'),
  (72, 21, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 'HIGH', NULL, '2026-11-08 16:50:00+07'),
  (73, 21, 'SERVICE', 8, NULL, 'Kiểm tra hệ thống treo', 1, 'MEDIUM', NULL, '2026-11-08 16:50:00+07'),
  (74, 21, 'SERVICE', 6, NULL, 'Kiểm tra & thay ắc quy', 1, 'MEDIUM', NULL, '2026-11-08 16:50:00+07'),
  (75, 21, 'PART', NULL, 5, 'Cần thay má phanh trước (bộ)', 1, 'MEDIUM', NULL, '2026-11-08 16:50:00+07'),
  (76, 21, 'PART', NULL, 11, 'Cần thay giảm xóc trước', 4, 'MEDIUM', NULL, '2026-11-08 16:50:00+07'),
  (77, 22, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 'HIGH', NULL, '2026-11-08 08:50:00+07'),
  (78, 22, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 'MEDIUM', NULL, '2026-11-08 08:50:00+07'),
  (79, 22, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 4, 'MEDIUM', NULL, '2026-11-08 08:50:00+07'),
  (80, 22, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-08 08:50:00+07'),
  (81, 23, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 'HIGH', NULL, '2026-11-08 11:50:00+07'),
  (82, 23, 'PART', NULL, 1, 'Cần thay dầu động cơ 5w-30 (1l)', 5, 'MEDIUM', NULL, '2026-11-08 11:50:00+07'),
  (83, 23, 'PART', NULL, 2, 'Cần thay lọc dầu động cơ', 1, 'MEDIUM', NULL, '2026-11-08 11:50:00+07'),
  (84, 23, 'PART', NULL, 3, 'Cần thay lọc gió động cơ', 1, 'MEDIUM', NULL, '2026-11-08 11:50:00+07'),
  (85, 24, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 'HIGH', NULL, '2026-11-07 14:50:00+07'),
  (86, 24, 'PART', NULL, 5, 'Cần thay má phanh trước (bộ)', 1, 'MEDIUM', NULL, '2026-11-07 14:50:00+07'),
  (87, 25, 'SERVICE', 4, NULL, 'Vệ sinh & nạp gas điều hòa', 1, 'HIGH', NULL, '2026-11-06 15:50:00+07'),
  (88, 25, 'PART', NULL, 9, 'Cần thay gas điều hòa r134a (bình)', 1, 'MEDIUM', NULL, '2026-11-06 15:50:00+07'),
  (89, 26, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 'HIGH', NULL, '2026-11-07 10:50:00+07'),
  (90, 26, 'PART', NULL, 5, 'Cần thay má phanh trước (bộ)', 1, 'MEDIUM', NULL, '2026-11-07 10:50:00+07');

-- quotations (23 rows)
INSERT INTO quotations (quotation_id, quotation_code, inspection_id, prepared_by, parent_quotation_id, subtotal, vat_amount, total_amount, status, valid_until, sent_at, responded_at, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'QT-261012-0001', 1, 3, NULL, 2840000, 227200, 3067200, 'APPROVED', '2026-10-15 08:00:00+07', '2026-10-12 09:00:00+07', '2026-10-12 10:00:00+07', '2026-10-12 09:00:00+07'),
  (2, 'QT-261020-0001', 2, 3, NULL, 3070000, 245600, 3315600, 'PARTIALLY_APPROVED', '2026-10-23 09:00:00+07', '2026-10-20 10:00:00+07', '2026-10-20 11:00:00+07', '2026-10-20 10:00:00+07'),
  (3, 'QT-261105-0001', 3, 3, NULL, 1490000, 119200, 1609200, 'APPROVED', '2026-11-08 08:00:00+07', '2026-11-05 09:00:00+07', '2026-11-05 10:00:00+07', '2026-11-05 09:00:00+07'),
  (4, 'QT-261106-0001', 4, 3, NULL, 1250000, 100000, 1350000, 'APPROVED', '2026-11-09 10:00:00+07', '2026-11-06 11:00:00+07', '2026-11-06 12:00:00+07', '2026-11-06 11:00:00+07'),
  (5, 'QT-261107-0001', 5, 3, NULL, 2710000, 216800, 2926800, 'APPROVED', '2026-11-10 08:00:00+07', '2026-11-07 09:00:00+07', '2026-11-07 10:00:00+07', '2026-11-07 09:00:00+07'),
  (6, 'QT-261107-0002', 6, 3, NULL, 6500000, 520000, 7020000, 'APPROVED', '2026-11-10 09:00:00+07', '2026-11-07 10:00:00+07', '2026-11-07 11:00:00+07', '2026-11-07 10:00:00+07'),
  (7, 'QT-261107-0003', 7, 3, NULL, 3800000, 304000, 4104000, 'APPROVED', '2026-11-10 13:00:00+07', '2026-11-07 14:00:00+07', '2026-11-07 15:00:00+07', '2026-11-07 14:00:00+07'),
  (8, 'QT-261108-0001', 8, 3, NULL, 3070000, 245600, 3315600, 'APPROVED', '2026-11-11 08:00:00+07', '2026-11-08 09:00:00+07', '2026-11-08 10:00:00+07', '2026-11-08 09:00:00+07'),
  (9, 'QT-261108-0002', 9, 3, NULL, 1520000, 121600, 1641600, 'APPROVED', '2026-11-11 09:00:00+07', '2026-11-08 10:00:00+07', '2026-11-08 11:00:00+07', '2026-11-08 10:00:00+07'),
  (10, 'QT-261108-0003', 10, 3, NULL, 2390000, 191200, 2581200, 'APPROVED', '2026-11-11 10:00:00+07', '2026-11-08 11:00:00+07', '2026-11-08 12:00:00+07', '2026-11-08 11:00:00+07'),
  (11, 'QT-261108-0004', 11, 3, NULL, 370000, 29600, 399600, 'APPROVED', '2026-11-11 10:00:00+07', '2026-11-08 11:00:00+07', '2026-11-08 12:00:00+07', '2026-11-08 11:00:00+07'),
  (12, 'QT-261108-0005', 12, 3, NULL, 1590000, 127200, 1717200, 'SENT', '2026-11-11 11:00:00+07', '2026-11-08 12:00:00+07', NULL, '2026-11-08 12:00:00+07'),
  (13, 'QT-261015-0001', 14, 10, NULL, 1190000, 95200, 1285200, 'APPROVED', '2026-10-18 09:00:00+07', '2026-10-15 10:00:00+07', '2026-10-15 11:00:00+07', '2026-10-15 10:00:00+07'),
  (14, 'QT-261107-0004', 15, 10, NULL, 1100000, 88000, 1188000, 'APPROVED', '2026-11-10 10:00:00+07', '2026-11-07 11:00:00+07', '2026-11-07 12:00:00+07', '2026-11-07 11:00:00+07'),
  (15, 'QT-261108-0006', 16, 10, NULL, 300000, 24000, 324000, 'APPROVED', '2026-11-11 14:00:00+07', '2026-11-08 15:00:00+07', '2026-11-08 16:00:00+07', '2026-11-08 15:00:00+07'),
  (16, 'QT-261025-0001', 17, 17, NULL, 370000, 29600, 399600, 'APPROVED', '2026-10-28 08:00:00+07', '2026-10-25 09:00:00+07', '2026-10-25 10:00:00+07', '2026-10-25 09:00:00+07'),
  (17, 'QT-261108-0007', 18, 17, NULL, 1920000, 153600, 2073600, 'APPROVED', '2026-11-11 09:00:00+07', '2026-11-08 10:00:00+07', '2026-11-08 11:00:00+07', '2026-11-08 10:00:00+07'),
  (18, 'QT-261108-0008', 21, 3, NULL, 9050000, 724000, 9774000, 'PARTIALLY_APPROVED', '2026-11-11 16:00:00+07', '2026-11-08 17:00:00+07', '2026-11-08 18:00:00+07', '2026-11-08 17:00:00+07'),
  (19, 'QT-261108-0009', 22, 3, NULL, 1490000, 119200, 1609200, 'APPROVED', '2026-11-11 08:00:00+07', '2026-11-08 09:00:00+07', '2026-11-08 10:00:00+07', '2026-11-08 09:00:00+07'),
  (20, 'QT-261108-0010', 23, 3, NULL, 2170000, 173600, 2343600, 'APPROVED', '2026-11-11 11:00:00+07', '2026-11-08 12:00:00+07', '2026-11-08 13:00:00+07', '2026-11-08 12:00:00+07'),
  (21, 'QT-261107-0005', 24, 3, NULL, 1100000, 88000, 1188000, 'APPROVED', '2026-11-10 14:00:00+07', '2026-11-07 15:00:00+07', '2026-11-07 16:00:00+07', '2026-11-07 15:00:00+07'),
  (22, 'QT-261106-0002', 25, 3, NULL, 1050000, 84000, 1134000, 'APPROVED', '2026-11-09 15:00:00+07', '2026-11-06 16:00:00+07', '2026-11-06 17:00:00+07', '2026-11-06 16:00:00+07'),
  (23, 'QT-261107-0006', 26, 3, NULL, 1100000, 88000, 1188000, 'APPROVED', '2026-11-10 10:00:00+07', '2026-11-07 11:00:00+07', '2026-11-07 12:00:00+07', '2026-11-07 11:00:00+07');

-- quotation_items (85 rows)
INSERT INTO quotation_items (item_id, quotation_id, item_type, service_id, part_id, description, quantity, unit_price, line_total, is_warranty, decision, decided_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 900000, 900000, FALSE, 'APPROVED', '2026-10-12 10:00:00+07'),
  (2, 1, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 250000, 250000, FALSE, 'APPROVED', '2026-10-12 10:00:00+07'),
  (3, 1, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 4, 180000, 720000, FALSE, 'APPROVED', '2026-10-12 10:00:00+07'),
  (4, 1, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-10-12 10:00:00+07'),
  (5, 1, 'PART', NULL, 5, 'Má phanh trước (bộ)', 1, 850000, 850000, FALSE, 'APPROVED', '2026-10-12 10:00:00+07'),
  (6, 2, 'SERVICE', 4, NULL, 'Vệ sinh & nạp gas điều hòa', 1, 600000, 600000, FALSE, 'APPROVED', '2026-10-20 11:00:00+07'),
  (7, 2, 'SERVICE', 6, NULL, 'Kiểm tra & thay ắc quy', 1, 150000, 150000, FALSE, 'APPROVED', '2026-10-20 11:00:00+07'),
  (8, 2, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 300000, 300000, FALSE, 'REJECTED', '2026-10-20 11:00:00+07'),
  (9, 2, 'PART', NULL, 4, 'Lọc gió điều hòa', 1, 220000, 220000, FALSE, 'APPROVED', '2026-10-20 11:00:00+07'),
  (10, 2, 'PART', NULL, 8, 'Ắc quy 12V 45Ah', 1, 1650000, 1650000, FALSE, 'APPROVED', '2026-10-20 11:00:00+07'),
  (11, 2, 'PART', NULL, 9, 'Gas điều hòa R134a (bình)', 1, 450000, 450000, FALSE, 'APPROVED', '2026-10-20 11:00:00+07'),
  (12, 3, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 350000, 350000, FALSE, 'APPROVED', '2026-11-05 10:00:00+07'),
  (13, 3, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 300000, 300000, FALSE, 'APPROVED', '2026-11-05 10:00:00+07'),
  (14, 3, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 4, 180000, 720000, FALSE, 'APPROVED', '2026-11-05 10:00:00+07'),
  (15, 3, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-11-05 10:00:00+07'),
  (16, 4, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-06 12:00:00+07'),
  (17, 4, 'PART', NULL, 5, 'Má phanh trước (bộ)', 1, 850000, 850000, FALSE, 'APPROVED', '2026-11-06 12:00:00+07'),
  (18, 4, 'PART', NULL, 7, 'Dầu phanh DOT4 (0.5L)', 1, 150000, 150000, FALSE, 'APPROVED', '2026-11-06 12:00:00+07'),
  (19, 5, 'SERVICE', 7, NULL, 'Chẩn đoán động cơ', 1, 400000, 400000, FALSE, 'APPROVED', '2026-11-07 10:00:00+07'),
  (20, 5, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 350000, 350000, FALSE, 'APPROVED', '2026-11-07 10:00:00+07'),
  (21, 5, 'PART', NULL, 10, 'Bugi Iridium', 4, 280000, 1120000, FALSE, 'APPROVED', '2026-11-07 10:00:00+07'),
  (22, 5, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 4, 180000, 720000, FALSE, 'APPROVED', '2026-11-07 10:00:00+07'),
  (23, 5, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-11-07 10:00:00+07'),
  (24, 6, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 900000, 900000, FALSE, 'APPROVED', '2026-11-07 11:00:00+07'),
  (25, 6, 'SERVICE', 8, NULL, 'Kiểm tra hệ thống treo', 1, 350000, 350000, FALSE, 'APPROVED', '2026-11-07 11:00:00+07'),
  (26, 6, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 6, 180000, 1080000, FALSE, 'APPROVED', '2026-11-07 11:00:00+07'),
  (27, 6, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-11-07 11:00:00+07'),
  (28, 6, 'PART', NULL, 3, 'Lọc gió động cơ', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-07 11:00:00+07'),
  (29, 6, 'PART', NULL, 11, 'Giảm xóc trước', 2, 1900000, 3800000, FALSE, 'APPROVED', '2026-11-07 11:00:00+07'),
  (30, 7, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-07 15:00:00+07'),
  (31, 7, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 300000, 300000, FALSE, 'APPROVED', '2026-11-07 15:00:00+07'),
  (32, 7, 'PART', NULL, 6, 'Đĩa phanh trước', 2, 1200000, 2400000, FALSE, 'APPROVED', '2026-11-07 15:00:00+07'),
  (33, 7, 'PART', NULL, 5, 'Má phanh trước (bộ)', 1, 850000, 850000, FALSE, 'APPROVED', '2026-11-07 15:00:00+07'),
  (34, 8, 'SERVICE', 4, NULL, 'Vệ sinh & nạp gas điều hòa', 1, 600000, 600000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (35, 8, 'SERVICE', 6, NULL, 'Kiểm tra & thay ắc quy', 1, 150000, 150000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (36, 8, 'PART', NULL, 4, 'Lọc gió điều hòa', 1, 220000, 220000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (37, 8, 'PART', NULL, 9, 'Gas điều hòa R134a (bình)', 1, 450000, 450000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (38, 8, 'PART', NULL, 8, 'Ắc quy 12V 45Ah', 1, 1650000, 1650000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (39, 9, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 350000, 350000, FALSE, 'APPROVED', '2026-11-08 11:00:00+07'),
  (40, 9, 'SERVICE', 10, NULL, 'Rửa xe & vệ sinh nội thất', 1, 150000, 150000, FALSE, 'APPROVED', '2026-11-08 11:00:00+07'),
  (41, 9, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 5, 180000, 900000, FALSE, 'APPROVED', '2026-11-08 11:00:00+07'),
  (42, 9, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-11-08 11:00:00+07'),
  (43, 10, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 900000, 900000, FALSE, 'APPROVED', '2026-11-08 12:00:00+07'),
  (44, 10, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 5, 180000, 900000, FALSE, 'APPROVED', '2026-11-08 12:00:00+07'),
  (45, 10, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-11-08 12:00:00+07'),
  (46, 10, 'PART', NULL, 3, 'Lọc gió động cơ', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-08 12:00:00+07'),
  (47, 10, 'PART', NULL, 4, 'Lọc gió điều hòa', 1, 220000, 220000, FALSE, 'APPROVED', '2026-11-08 12:00:00+07'),
  (48, 11, 'SERVICE', 9, NULL, 'Bảo dưỡng xe máy', 1, 200000, 200000, FALSE, 'APPROVED', '2026-11-08 12:00:00+07'),
  (49, 11, 'PART', NULL, 16, 'Dầu nhớt xe máy 0.8L', 1, 110000, 110000, FALSE, 'APPROVED', '2026-11-08 12:00:00+07'),
  (50, 11, 'PART', NULL, 17, 'Bugi xe máy', 1, 60000, 60000, FALSE, 'APPROVED', '2026-11-08 12:00:00+07'),
  (51, 12, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 350000, 350000, FALSE, 'PENDING', NULL),
  (52, 12, 'SERVICE', 7, NULL, 'Chẩn đoán động cơ', 1, 400000, 400000, FALSE, 'PENDING', NULL),
  (53, 12, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 4, 180000, 720000, FALSE, 'PENDING', NULL),
  (54, 12, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'PENDING', NULL),
  (55, 13, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 350000, 350000, FALSE, 'APPROVED', '2026-10-15 11:00:00+07'),
  (56, 13, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 4, 180000, 720000, FALSE, 'APPROVED', '2026-10-15 11:00:00+07'),
  (57, 13, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-10-15 11:00:00+07'),
  (58, 14, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-07 12:00:00+07'),
  (59, 14, 'PART', NULL, 5, 'Má phanh trước (bộ)', 1, 850000, 850000, FALSE, 'APPROVED', '2026-11-07 12:00:00+07'),
  (60, 15, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 300000, 300000, FALSE, 'APPROVED', '2026-11-08 16:00:00+07'),
  (61, 16, 'SERVICE', 9, NULL, 'Bảo dưỡng xe máy', 1, 200000, 200000, FALSE, 'APPROVED', '2026-10-25 10:00:00+07'),
  (62, 16, 'PART', NULL, 16, 'Dầu nhớt xe máy 0.8L', 1, 110000, 110000, FALSE, 'APPROVED', '2026-10-25 10:00:00+07'),
  (63, 16, 'PART', NULL, 17, 'Bugi xe máy', 1, 60000, 60000, FALSE, 'APPROVED', '2026-10-25 10:00:00+07'),
  (64, 17, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 900000, 900000, FALSE, 'APPROVED', '2026-11-08 11:00:00+07'),
  (65, 17, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 5, 180000, 900000, FALSE, 'APPROVED', '2026-11-08 11:00:00+07'),
  (66, 17, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-11-08 11:00:00+07'),
  (67, 18, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-08 18:00:00+07'),
  (68, 18, 'SERVICE', 8, NULL, 'Kiểm tra hệ thống treo', 1, 350000, 350000, FALSE, 'APPROVED', '2026-11-08 18:00:00+07'),
  (69, 18, 'SERVICE', 6, NULL, 'Kiểm tra & thay ắc quy', 1, 150000, 150000, FALSE, 'REJECTED', '2026-11-08 18:00:00+07'),
  (70, 18, 'PART', NULL, 5, 'Má phanh trước (bộ)', 1, 850000, 850000, FALSE, 'APPROVED', '2026-11-08 18:00:00+07'),
  (71, 18, 'PART', NULL, 11, 'Giảm xóc trước', 4, 1900000, 7600000, FALSE, 'APPROVED', '2026-11-08 18:00:00+07'),
  (72, 19, 'SERVICE', 1, NULL, 'Thay dầu động cơ', 1, 350000, 350000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (73, 19, 'SERVICE', 5, NULL, 'Đảo lốp & cân bằng động', 1, 300000, 300000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (74, 19, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 4, 180000, 720000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (75, 19, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-11-08 10:00:00+07'),
  (76, 20, 'SERVICE', 3, NULL, 'Bảo dưỡng định kỳ 10.000 km', 1, 900000, 900000, FALSE, 'APPROVED', '2026-11-08 13:00:00+07'),
  (77, 20, 'PART', NULL, 1, 'Dầu động cơ 5W-30 (1L)', 5, 180000, 900000, FALSE, 'APPROVED', '2026-11-08 13:00:00+07'),
  (78, 20, 'PART', NULL, 2, 'Lọc dầu động cơ', 1, 120000, 120000, FALSE, 'APPROVED', '2026-11-08 13:00:00+07'),
  (79, 20, 'PART', NULL, 3, 'Lọc gió động cơ', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-08 13:00:00+07'),
  (80, 21, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-07 16:00:00+07'),
  (81, 21, 'PART', NULL, 5, 'Má phanh trước (bộ)', 1, 850000, 850000, FALSE, 'APPROVED', '2026-11-07 16:00:00+07'),
  (82, 22, 'SERVICE', 4, NULL, 'Vệ sinh & nạp gas điều hòa', 1, 600000, 600000, FALSE, 'APPROVED', '2026-11-06 17:00:00+07'),
  (83, 22, 'PART', NULL, 9, 'Gas điều hòa R134a (bình)', 1, 450000, 450000, FALSE, 'APPROVED', '2026-11-06 17:00:00+07'),
  (84, 23, 'SERVICE', 2, NULL, 'Kiểm tra & thay má phanh', 1, 250000, 250000, FALSE, 'APPROVED', '2026-11-07 12:00:00+07'),
  (85, 23, 'PART', NULL, 5, 'Má phanh trước (bộ)', 1, 850000, 850000, FALSE, 'APPROVED', '2026-11-07 12:00:00+07');

-- repair_orders (21 rows)
INSERT INTO repair_orders (repair_order_id, ro_code, quotation_id, branch_id, type_id, created_by, status, total_cost, started_at, completed_at, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'RO-261012-0001', 1, 1, 1, 3, 'CLOSED', 2840000, '2026-10-12 10:50:00+07', '2026-10-12 14:20:00+07', '2026-10-12 10:20:00+07', '2026-10-12 14:20:00+07'),
  (2, 'RO-261020-0001', 2, 1, 1, 3, 'CLOSED', 3070000, '2026-10-20 11:50:00+07', '2026-10-20 15:20:00+07', '2026-10-20 11:20:00+07', '2026-10-20 15:20:00+07'),
  (3, 'RO-261105-0001', 3, 1, 1, 3, 'COMPLETED', 1490000, '2026-11-05 10:50:00+07', '2026-11-05 14:20:00+07', '2026-11-05 10:20:00+07', '2026-11-05 14:20:00+07'),
  (4, 'RO-261106-0001', 4, 1, 2, 3, 'COMPLETED', 1250000, '2026-11-06 12:50:00+07', '2026-11-06 16:20:00+07', '2026-11-06 12:20:00+07', '2026-11-06 16:20:00+07'),
  (5, 'RO-261107-0001', 5, 1, 2, 3, 'IN_PROGRESS', 2710000, '2026-11-07 10:50:00+07', NULL, '2026-11-07 10:20:00+07', '2026-11-07 10:20:00+07'),
  (6, 'RO-261107-0002', 6, 1, 1, 3, 'IN_PROGRESS', 6500000, '2026-11-07 11:50:00+07', NULL, '2026-11-07 11:20:00+07', '2026-11-07 11:20:00+07'),
  (7, 'RO-261107-0003', 7, 1, 2, 3, 'WAITING_PARTS', 3800000, '2026-11-07 15:50:00+07', NULL, '2026-11-07 15:20:00+07', '2026-11-07 15:20:00+07'),
  (8, 'RO-261108-0001', 8, 1, 1, 3, 'IN_PROGRESS', 3070000, '2026-11-08 10:50:00+07', NULL, '2026-11-08 10:20:00+07', '2026-11-08 10:20:00+07'),
  (9, 'RO-261108-0002', 9, 1, 1, 3, 'ASSIGNED', 1520000, NULL, NULL, '2026-11-08 11:20:00+07', '2026-11-08 11:20:00+07'),
  (10, 'RO-261108-0003', 10, 1, 1, 3, 'NEW', 2390000, NULL, NULL, '2026-11-08 12:20:00+07', '2026-11-08 12:20:00+07'),
  (11, 'RO-261108-0004', 11, 1, 1, 3, 'NEW', 370000, NULL, NULL, '2026-11-08 12:20:00+07', '2026-11-08 12:20:00+07'),
  (12, 'RO-261015-0001', 13, 2, 1, 10, 'CLOSED', 1190000, '2026-10-15 11:50:00+07', '2026-10-15 15:20:00+07', '2026-10-15 11:20:00+07', '2026-10-15 15:20:00+07'),
  (13, 'RO-261107-0004', 14, 2, 1, 10, 'IN_PROGRESS', 1100000, '2026-11-07 12:50:00+07', NULL, '2026-11-07 12:20:00+07', '2026-11-07 12:20:00+07'),
  (14, 'RO-261108-0005', 15, 2, 1, 10, 'NEW', 300000, NULL, NULL, '2026-11-08 16:20:00+07', '2026-11-08 16:20:00+07'),
  (15, 'RO-261025-0001', 16, 3, 1, 17, 'CLOSED', 370000, '2026-10-25 10:50:00+07', '2026-10-25 14:20:00+07', '2026-10-25 10:20:00+07', '2026-10-25 14:20:00+07'),
  (16, 'RO-261108-0006', 17, 3, 1, 17, 'ASSIGNED', 1920000, NULL, NULL, '2026-11-08 11:20:00+07', '2026-11-08 11:20:00+07'),
  (17, 'RO-261108-0007', 19, 1, 1, 3, 'COMPLETED', 1490000, '2026-11-08 10:50:00+07', '2026-11-08 14:20:00+07', '2026-11-08 10:20:00+07', '2026-11-08 14:20:00+07'),
  (18, 'RO-261108-0008', 20, 1, 1, 3, 'COMPLETED', 2170000, '2026-11-08 13:50:00+07', '2026-11-08 17:20:00+07', '2026-11-08 13:20:00+07', '2026-11-08 17:20:00+07'),
  (19, 'RO-261107-0005', 21, 1, 1, 3, 'COMPLETED', 1100000, '2026-11-07 16:50:00+07', '2026-11-07 20:20:00+07', '2026-11-07 16:20:00+07', '2026-11-07 20:20:00+07'),
  (20, 'RO-261106-0002', 22, 1, 1, 3, 'COMPLETED', 1050000, '2026-11-06 17:50:00+07', '2026-11-06 21:20:00+07', '2026-11-06 17:20:00+07', '2026-11-06 21:20:00+07'),
  (21, 'RO-261107-0006', 23, 1, 4, 3, 'COMPLETED', 1100000, '2026-11-07 12:50:00+07', '2026-11-07 16:20:00+07', '2026-11-07 12:20:00+07', '2026-11-07 16:20:00+07');

-- repair_tasks (30 rows)
INSERT INTO repair_tasks (task_id, repair_order_id, quotation_item_id, mechanic_id, task_name, status, progress_percent, labor_hours, started_at, finished_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, 6, 'Bảo dưỡng định kỳ 10.000 km', 'DONE', 100, 1.5, '2026-10-12 10:50:00+07', '2026-10-12 14:20:00+07'),
  (2, 1, 2, 6, 'Kiểm tra & thay má phanh', 'DONE', 100, 1.5, '2026-10-12 11:00:00+07', '2026-10-12 14:00:00+07'),
  (3, 2, 6, 7, 'Vệ sinh & nạp gas điều hòa', 'DONE', 100, 1.5, '2026-10-20 11:50:00+07', '2026-10-20 15:20:00+07'),
  (4, 2, 7, 7, 'Kiểm tra & thay ắc quy', 'DONE', 100, 1.5, '2026-10-20 12:00:00+07', '2026-10-20 15:00:00+07'),
  (5, 3, 12, 7, 'Thay dầu động cơ', 'DONE', 100, 1.5, '2026-11-05 10:50:00+07', '2026-11-05 14:20:00+07'),
  (6, 3, 13, 7, 'Đảo lốp & cân bằng động', 'DONE', 100, 1.5, '2026-11-05 11:00:00+07', '2026-11-05 14:00:00+07'),
  (7, 4, 16, 6, 'Kiểm tra & thay má phanh', 'DONE', 100, 1.5, '2026-11-06 12:50:00+07', '2026-11-06 16:20:00+07'),
  (8, 5, 19, 6, 'Chẩn đoán động cơ', 'DONE', 100, 1.5, '2026-11-07 10:50:00+07', '2026-11-07 14:20:00+07'),
  (9, 5, 20, 6, 'Thay dầu động cơ', 'DONE', 100, 1.5, '2026-11-07 11:00:00+07', '2026-11-07 14:00:00+07'),
  (10, 6, 24, 6, 'Bảo dưỡng định kỳ 10.000 km', 'DOING', 40, 0.6, '2026-11-07 11:50:00+07', NULL),
  (11, 6, 25, 6, 'Kiểm tra hệ thống treo', 'TODO', 0, 0.0, NULL, NULL),
  (12, 7, 30, 7, 'Kiểm tra & thay má phanh', 'BLOCKED', 30, 0.45, '2026-11-07 15:50:00+07', NULL),
  (13, 7, 31, 7, 'Đảo lốp & cân bằng động', 'DONE', 100, 1.5, '2026-11-07 16:00:00+07', '2026-11-07 19:00:00+07'),
  (14, 8, 34, 6, 'Vệ sinh & nạp gas điều hòa', 'DOING', 50, 0.75, '2026-11-08 10:50:00+07', NULL),
  (15, 8, 35, 6, 'Kiểm tra & thay ắc quy', 'TODO', 0, 0.0, NULL, NULL),
  (16, 9, 39, 6, 'Thay dầu động cơ', 'TODO', 0, 0.0, NULL, NULL),
  (17, 9, 40, 6, 'Rửa xe & vệ sinh nội thất', 'TODO', 0, 0.0, NULL, NULL),
  (18, 10, 43, NULL, 'Bảo dưỡng định kỳ 10.000 km', 'TODO', 0, 0.0, NULL, NULL),
  (19, 11, 48, NULL, 'Bảo dưỡng xe máy', 'TODO', 0, 0.0, NULL, NULL),
  (20, 12, 55, 13, 'Thay dầu động cơ', 'DONE', 100, 1.5, '2026-10-15 11:50:00+07', '2026-10-15 15:20:00+07'),
  (21, 13, 58, 13, 'Kiểm tra & thay má phanh', 'DOING', 60, 0.9, '2026-11-07 12:50:00+07', NULL),
  (22, 14, 60, NULL, 'Đảo lốp & cân bằng động', 'TODO', 0, 0.0, NULL, NULL),
  (23, 15, 61, 20, 'Bảo dưỡng xe máy', 'DONE', 100, 1.5, '2026-10-25 10:50:00+07', '2026-10-25 14:20:00+07'),
  (24, 16, 64, 20, 'Bảo dưỡng định kỳ 10.000 km', 'TODO', 0, 0.0, NULL, NULL),
  (25, 17, 72, 7, 'Thay dầu động cơ', 'DONE', 100, 1.5, '2026-11-08 10:50:00+07', '2026-11-08 14:20:00+07'),
  (26, 17, 73, 7, 'Đảo lốp & cân bằng động', 'DONE', 100, 1.5, '2026-11-08 11:00:00+07', '2026-11-08 14:00:00+07'),
  (27, 18, 76, 8, 'Bảo dưỡng định kỳ 10.000 km', 'DONE', 100, 1.5, '2026-11-08 13:50:00+07', '2026-11-08 17:20:00+07'),
  (28, 19, 80, 6, 'Kiểm tra & thay má phanh', 'DONE', 100, 1.5, '2026-11-07 16:50:00+07', '2026-11-07 20:20:00+07'),
  (29, 20, 82, 7, 'Vệ sinh & nạp gas điều hòa', 'DONE', 100, 1.5, '2026-11-06 17:50:00+07', '2026-11-06 21:20:00+07'),
  (30, 21, 84, 8, 'Kiểm tra & thay má phanh', 'DONE', 100, 1.5, '2026-11-07 12:50:00+07', '2026-11-07 16:20:00+07');

-- repair_notes (16 rows)
INSERT INTO repair_notes (note_id, repair_order_id, task_id, author_id, content, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, 6, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-10-12 10:55:00+07'),
  (2, 2, 3, 7, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-10-20 11:55:00+07'),
  (3, 3, 5, 7, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-05 10:55:00+07'),
  (4, 4, 7, 6, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-06 12:55:00+07'),
  (5, 5, 8, 6, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-07 10:55:00+07'),
  (6, 6, 10, 6, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-07 11:55:00+07'),
  (7, 7, 12, 7, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-07 15:55:00+07'),
  (8, 8, 14, 6, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-08 10:55:00+07'),
  (9, 12, 20, 13, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-10-15 11:55:00+07'),
  (10, 13, 21, 13, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-07 12:55:00+07'),
  (11, 15, 23, 20, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-10-25 10:55:00+07'),
  (12, 17, 25, 7, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-08 10:55:00+07'),
  (13, 18, 27, 8, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-08 13:55:00+07'),
  (14, 19, 28, 6, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-07 16:55:00+07'),
  (15, 20, 29, 7, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-06 17:55:00+07'),
  (16, 21, 30, 8, 'Đã kiểm tra lại các hạng mục, bắt đầu thực hiện.', '2026-11-07 12:55:00+07');

-- part_reservations (44 rows)
INSERT INTO part_reservations (reservation_id, repair_order_id, quotation_item_id, inventory_id, quantity, status, reserved_by, created_at, updated_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 3, 1, 4, 'ISSUED', 3, '2026-10-12 10:25:00+07', '2026-10-12 11:25:00+07'),
  (2, 1, 4, 2, 1, 'ISSUED', 3, '2026-10-12 10:25:00+07', '2026-10-12 11:25:00+07'),
  (3, 1, 5, 5, 1, 'ISSUED', 3, '2026-10-12 10:25:00+07', '2026-10-12 11:25:00+07'),
  (4, 2, 9, 4, 1, 'ISSUED', 3, '2026-10-20 11:25:00+07', '2026-10-20 12:25:00+07'),
  (5, 2, 10, 8, 1, 'ISSUED', 3, '2026-10-20 11:25:00+07', '2026-10-20 12:25:00+07'),
  (6, 2, 11, 9, 1, 'ISSUED', 3, '2026-10-20 11:25:00+07', '2026-10-20 12:25:00+07'),
  (7, 3, 14, 1, 4, 'ISSUED', 3, '2026-11-05 10:25:00+07', '2026-11-05 11:25:00+07'),
  (8, 3, 15, 2, 1, 'ISSUED', 3, '2026-11-05 10:25:00+07', '2026-11-05 11:25:00+07'),
  (9, 4, 17, 5, 1, 'ISSUED', 3, '2026-11-06 12:25:00+07', '2026-11-06 13:25:00+07'),
  (10, 4, 18, 7, 1, 'ISSUED', 3, '2026-11-06 12:25:00+07', '2026-11-06 13:25:00+07'),
  (11, 5, 21, 10, 4, 'ISSUED', 3, '2026-11-07 10:25:00+07', '2026-11-07 11:25:00+07'),
  (12, 5, 22, 1, 4, 'ISSUED', 3, '2026-11-07 10:25:00+07', '2026-11-07 11:25:00+07'),
  (13, 5, 23, 2, 1, 'ISSUED', 3, '2026-11-07 10:25:00+07', '2026-11-07 11:25:00+07'),
  (14, 6, 26, 1, 6, 'RESERVED', 3, '2026-11-07 11:25:00+07', '2026-11-07 11:25:00+07'),
  (15, 6, 27, 2, 1, 'RESERVED', 3, '2026-11-07 11:25:00+07', '2026-11-07 11:25:00+07'),
  (16, 6, 28, 3, 1, 'RESERVED', 3, '2026-11-07 11:25:00+07', '2026-11-07 11:25:00+07'),
  (17, 6, 29, 11, 2, 'RESERVED', 3, '2026-11-07 11:25:00+07', '2026-11-07 11:25:00+07'),
  (18, 7, 33, 5, 1, 'RESERVED', 3, '2026-11-07 15:25:00+07', '2026-11-07 15:25:00+07'),
  (19, 8, 36, 4, 1, 'RESERVED', 3, '2026-11-08 10:25:00+07', '2026-11-08 10:25:00+07'),
  (20, 8, 37, 9, 1, 'RESERVED', 3, '2026-11-08 10:25:00+07', '2026-11-08 10:25:00+07'),
  (21, 8, 38, 8, 1, 'RESERVED', 3, '2026-11-08 10:25:00+07', '2026-11-08 10:25:00+07'),
  (22, 9, 41, 1, 5, 'RESERVED', 3, '2026-11-08 11:25:00+07', '2026-11-08 11:25:00+07'),
  (23, 9, 42, 2, 1, 'RESERVED', 3, '2026-11-08 11:25:00+07', '2026-11-08 11:25:00+07'),
  (24, 10, 44, 1, 5, 'RESERVED', 3, '2026-11-08 12:25:00+07', '2026-11-08 12:25:00+07'),
  (25, 10, 45, 2, 1, 'RESERVED', 3, '2026-11-08 12:25:00+07', '2026-11-08 12:25:00+07'),
  (26, 10, 46, 3, 1, 'RESERVED', 3, '2026-11-08 12:25:00+07', '2026-11-08 12:25:00+07'),
  (27, 10, 47, 4, 1, 'RESERVED', 3, '2026-11-08 12:25:00+07', '2026-11-08 12:25:00+07'),
  (28, 11, 49, 16, 1, 'RESERVED', 3, '2026-11-08 12:25:00+07', '2026-11-08 12:25:00+07'),
  (29, 11, 50, 17, 1, 'RESERVED', 3, '2026-11-08 12:25:00+07', '2026-11-08 12:25:00+07'),
  (30, 12, 56, 21, 4, 'ISSUED', 10, '2026-10-15 11:25:00+07', '2026-10-15 12:25:00+07'),
  (31, 12, 57, 22, 1, 'ISSUED', 10, '2026-10-15 11:25:00+07', '2026-10-15 12:25:00+07'),
  (32, 13, 59, 25, 1, 'RESERVED', 10, '2026-11-07 12:25:00+07', '2026-11-07 12:25:00+07'),
  (33, 15, 62, 56, 1, 'ISSUED', 17, '2026-10-25 10:25:00+07', '2026-10-25 11:25:00+07'),
  (34, 15, 63, 57, 1, 'ISSUED', 17, '2026-10-25 10:25:00+07', '2026-10-25 11:25:00+07'),
  (35, 16, 65, 41, 5, 'RESERVED', 17, '2026-11-08 11:25:00+07', '2026-11-08 11:25:00+07'),
  (36, 16, 66, 42, 1, 'RESERVED', 17, '2026-11-08 11:25:00+07', '2026-11-08 11:25:00+07'),
  (37, 17, 74, 1, 4, 'ISSUED', 3, '2026-11-08 10:25:00+07', '2026-11-08 11:25:00+07'),
  (38, 17, 75, 2, 1, 'ISSUED', 3, '2026-11-08 10:25:00+07', '2026-11-08 11:25:00+07'),
  (39, 18, 77, 1, 5, 'ISSUED', 3, '2026-11-08 13:25:00+07', '2026-11-08 14:25:00+07'),
  (40, 18, 78, 2, 1, 'ISSUED', 3, '2026-11-08 13:25:00+07', '2026-11-08 14:25:00+07'),
  (41, 18, 79, 3, 1, 'ISSUED', 3, '2026-11-08 13:25:00+07', '2026-11-08 14:25:00+07'),
  (42, 19, 81, 5, 1, 'ISSUED', 3, '2026-11-07 16:25:00+07', '2026-11-07 17:25:00+07'),
  (43, 20, 83, 9, 1, 'ISSUED', 3, '2026-11-06 17:25:00+07', '2026-11-06 18:25:00+07'),
  (44, 21, 85, 5, 1, 'ISSUED', 3, '2026-11-07 12:25:00+07', '2026-11-07 13:25:00+07');

-- part_requests (14 rows)
INSERT INTO part_requests (request_id, request_code, repair_order_id, task_id, requested_by, status, note, processed_by, processed_at, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'PR-261012-0001', 1, 1, 6, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-10-12 11:25:00+07', '2026-10-12 11:10:00+07'),
  (2, 'PR-261020-0001', 2, 3, 7, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-10-20 12:25:00+07', '2026-10-20 12:10:00+07'),
  (3, 'PR-261105-0001', 3, 5, 7, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-11-05 11:25:00+07', '2026-11-05 11:10:00+07'),
  (4, 'PR-261106-0001', 4, 7, 6, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-11-06 13:25:00+07', '2026-11-06 13:10:00+07'),
  (5, 'PR-261107-0001', 5, 8, 6, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-11-07 11:25:00+07', '2026-11-07 11:10:00+07'),
  (6, 'PR-261107-0002', 6, 10, 6, 'PENDING', 'Cần phụ tùng để tiếp tục công việc', NULL, NULL, '2026-11-07 12:30:00+07'),
  (7, 'PR-261107-0003', 7, 12, 7, 'PENDING', 'Cần phụ tùng để tiếp tục công việc', NULL, NULL, '2026-11-07 16:30:00+07'),
  (8, 'PR-261015-0001', 12, 20, 13, 'ISSUED', 'Lấy phụ tùng theo báo giá', 10, '2026-10-15 12:25:00+07', '2026-10-15 12:10:00+07'),
  (9, 'PR-261025-0001', 15, 23, 20, 'ISSUED', 'Lấy phụ tùng theo báo giá', 17, '2026-10-25 11:25:00+07', '2026-10-25 11:10:00+07'),
  (10, 'PR-261108-0001', 17, 25, 7, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-11-08 11:25:00+07', '2026-11-08 11:10:00+07'),
  (11, 'PR-261108-0002', 18, 27, 8, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-11-08 14:25:00+07', '2026-11-08 14:10:00+07'),
  (12, 'PR-261107-0004', 19, 28, 6, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-11-07 17:25:00+07', '2026-11-07 17:10:00+07'),
  (13, 'PR-261106-0002', 20, 29, 7, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-11-06 18:25:00+07', '2026-11-06 18:10:00+07'),
  (14, 'PR-261107-0005', 21, 30, 8, 'ISSUED', 'Lấy phụ tùng theo báo giá', 3, '2026-11-07 13:25:00+07', '2026-11-07 13:10:00+07');

-- part_request_items (28 rows)
INSERT INTO part_request_items (request_item_id, request_id, quotation_item_id, part_id, quantity_requested, quantity_issued) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 3, 1, 4, 4),
  (2, 1, 4, 2, 1, 1),
  (3, 1, 5, 5, 1, 1),
  (4, 2, 9, 4, 1, 1),
  (5, 2, 10, 8, 1, 1),
  (6, 2, 11, 9, 1, 1),
  (7, 3, 14, 1, 4, 4),
  (8, 3, 15, 2, 1, 1),
  (9, 4, 17, 5, 1, 1),
  (10, 4, 18, 7, 1, 1),
  (11, 5, 21, 10, 4, 4),
  (12, 5, 22, 1, 4, 4),
  (13, 5, 23, 2, 1, 1),
  (14, 6, 26, 1, 6, 0),
  (15, 6, 27, 2, 1, 0),
  (16, 7, 32, 6, 2, 0),
  (17, 8, 56, 1, 4, 4),
  (18, 8, 57, 2, 1, 1),
  (19, 9, 62, 16, 1, 1),
  (20, 9, 63, 17, 1, 1),
  (21, 10, 74, 1, 4, 4),
  (22, 10, 75, 2, 1, 1),
  (23, 11, 77, 1, 5, 5),
  (24, 11, 78, 2, 1, 1),
  (25, 11, 79, 3, 1, 1),
  (26, 12, 81, 5, 1, 1),
  (27, 13, 83, 9, 1, 1),
  (28, 14, 85, 5, 1, 1);

-- repair_task_parts (25 rows)
INSERT INTO repair_task_parts (task_part_id, task_id, inventory_id, reservation_id, request_item_id, quantity_issued, quantity_returned, unit_price, issued_by, issued_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, 1, 1, 4, 0, 180000, 3, '2026-10-12 11:25:00+07'),
  (2, 1, 2, 2, 2, 1, 0, 120000, 3, '2026-10-12 11:25:00+07'),
  (3, 1, 5, 3, 3, 1, 0, 850000, 3, '2026-10-12 11:25:00+07'),
  (4, 3, 4, 4, 4, 1, 0, 220000, 3, '2026-10-20 12:25:00+07'),
  (5, 3, 8, 5, 5, 1, 0, 1650000, 3, '2026-10-20 12:25:00+07'),
  (6, 3, 9, 6, 6, 1, 0, 450000, 3, '2026-10-20 12:25:00+07'),
  (7, 5, 1, 7, 7, 4, 0, 180000, 3, '2026-11-05 11:25:00+07'),
  (8, 5, 2, 8, 8, 1, 0, 120000, 3, '2026-11-05 11:25:00+07'),
  (9, 7, 5, 9, 9, 1, 0, 850000, 3, '2026-11-06 13:25:00+07'),
  (10, 7, 7, 10, 10, 1, 0, 150000, 3, '2026-11-06 13:25:00+07'),
  (11, 8, 10, 11, 11, 4, 0, 280000, 3, '2026-11-07 11:25:00+07'),
  (12, 8, 1, 12, 12, 4, 0, 180000, 3, '2026-11-07 11:25:00+07'),
  (13, 8, 2, 13, 13, 1, 0, 120000, 3, '2026-11-07 11:25:00+07'),
  (14, 20, 21, 30, 17, 4, 0, 180000, 10, '2026-10-15 12:25:00+07'),
  (15, 20, 22, 31, 18, 1, 0, 120000, 10, '2026-10-15 12:25:00+07'),
  (16, 23, 56, 33, 19, 1, 0, 110000, 17, '2026-10-25 11:25:00+07'),
  (17, 23, 57, 34, 20, 1, 0, 60000, 17, '2026-10-25 11:25:00+07'),
  (18, 25, 1, 37, 21, 4, 0, 180000, 3, '2026-11-08 11:25:00+07'),
  (19, 25, 2, 38, 22, 1, 0, 120000, 3, '2026-11-08 11:25:00+07'),
  (20, 27, 1, 39, 23, 5, 0, 180000, 3, '2026-11-08 14:25:00+07'),
  (21, 27, 2, 40, 24, 1, 0, 120000, 3, '2026-11-08 14:25:00+07'),
  (22, 27, 3, 41, 25, 1, 0, 250000, 3, '2026-11-08 14:25:00+07'),
  (23, 28, 5, 42, 26, 1, 0, 850000, 3, '2026-11-07 17:25:00+07'),
  (24, 29, 9, 43, 27, 1, 0, 450000, 3, '2026-11-06 18:25:00+07'),
  (25, 30, 5, 44, 28, 1, 0, 850000, 3, '2026-11-07 13:25:00+07');

-- inventory_transactions (132 rows)
INSERT INTO inventory_transactions (transaction_id, inventory_id, transaction_type, quantity, balance_after, reference_type, reference_id, performed_by, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 'RECEIPT', 80, 80, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (2, 2, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (3, 3, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (4, 4, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (5, 5, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (6, 6, 'RECEIPT', 6, 6, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (7, 7, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (8, 8, 'RECEIPT', 8, 8, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (9, 9, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (10, 10, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (11, 11, 'RECEIPT', 4, 4, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (12, 12, 'RECEIPT', 12, 12, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (13, 13, 'RECEIPT', 4, 4, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (14, 14, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (15, 15, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (16, 16, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (17, 17, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (18, 18, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (19, 19, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (20, 20, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 1, 3, '2026-10-01 09:00:00+07'),
  (21, 21, 'RECEIPT', 80, 80, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (22, 22, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (23, 23, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (24, 24, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (25, 25, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (26, 26, 'RECEIPT', 6, 6, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (27, 27, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (28, 28, 'RECEIPT', 8, 8, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (29, 29, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (30, 30, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (31, 31, 'RECEIPT', 4, 4, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (32, 32, 'RECEIPT', 12, 12, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (33, 33, 'RECEIPT', 4, 4, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (34, 34, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (35, 35, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (36, 36, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (37, 37, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (38, 38, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (39, 39, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (40, 40, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 2, 10, '2026-10-01 09:00:00+07'),
  (41, 41, 'RECEIPT', 80, 80, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (42, 42, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (43, 43, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (44, 44, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (45, 45, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (46, 46, 'RECEIPT', 6, 6, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (47, 47, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (48, 48, 'RECEIPT', 8, 8, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (49, 49, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (50, 50, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (51, 51, 'RECEIPT', 4, 4, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (52, 52, 'RECEIPT', 12, 12, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (53, 53, 'RECEIPT', 4, 4, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (54, 54, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (55, 55, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (56, 56, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (57, 57, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (58, 58, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (59, 59, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (60, 60, 'RECEIPT', 30, 30, 'INVENTORY_RECEIPT', 3, 17, '2026-10-01 09:00:00+07'),
  (61, 1, 'RESERVE', 4, 80, 'REPAIR_ORDER', 1, 3, '2026-10-12 10:25:00+07'),
  (62, 2, 'RESERVE', 1, 30, 'REPAIR_ORDER', 1, 3, '2026-10-12 10:25:00+07'),
  (63, 5, 'RESERVE', 1, 30, 'REPAIR_ORDER', 1, 3, '2026-10-12 10:25:00+07'),
  (64, 1, 'ISSUE', -4, 76, 'PART_REQUEST', 1, 3, '2026-10-12 11:25:00+07'),
  (65, 2, 'ISSUE', -1, 29, 'PART_REQUEST', 1, 3, '2026-10-12 11:25:00+07'),
  (66, 5, 'ISSUE', -1, 29, 'PART_REQUEST', 1, 3, '2026-10-12 11:25:00+07'),
  (67, 21, 'RESERVE', 4, 80, 'REPAIR_ORDER', 12, 10, '2026-10-15 11:25:00+07'),
  (68, 22, 'RESERVE', 1, 30, 'REPAIR_ORDER', 12, 10, '2026-10-15 11:25:00+07'),
  (69, 21, 'ISSUE', -4, 76, 'PART_REQUEST', 8, 10, '2026-10-15 12:25:00+07'),
  (70, 22, 'ISSUE', -1, 29, 'PART_REQUEST', 8, 10, '2026-10-15 12:25:00+07'),
  (71, 4, 'RESERVE', 1, 30, 'REPAIR_ORDER', 2, 3, '2026-10-20 11:25:00+07'),
  (72, 8, 'RESERVE', 1, 8, 'REPAIR_ORDER', 2, 3, '2026-10-20 11:25:00+07'),
  (73, 9, 'RESERVE', 1, 30, 'REPAIR_ORDER', 2, 3, '2026-10-20 11:25:00+07'),
  (74, 4, 'ISSUE', -1, 29, 'PART_REQUEST', 2, 3, '2026-10-20 12:25:00+07'),
  (75, 8, 'ISSUE', -1, 7, 'PART_REQUEST', 2, 3, '2026-10-20 12:25:00+07'),
  (76, 9, 'ISSUE', -1, 29, 'PART_REQUEST', 2, 3, '2026-10-20 12:25:00+07'),
  (77, 56, 'RESERVE', 1, 30, 'REPAIR_ORDER', 15, 17, '2026-10-25 10:25:00+07'),
  (78, 57, 'RESERVE', 1, 30, 'REPAIR_ORDER', 15, 17, '2026-10-25 10:25:00+07'),
  (79, 56, 'ISSUE', -1, 29, 'PART_REQUEST', 9, 17, '2026-10-25 11:25:00+07'),
  (80, 57, 'ISSUE', -1, 29, 'PART_REQUEST', 9, 17, '2026-10-25 11:25:00+07'),
  (81, 1, 'RECEIPT', 40, 116, 'INVENTORY_RECEIPT', 4, 4, '2026-11-02 14:00:00+07'),
  (82, 2, 'RECEIPT', 20, 49, 'INVENTORY_RECEIPT', 4, 4, '2026-11-02 14:00:00+07'),
  (83, 3, 'RECEIPT', 10, 40, 'INVENTORY_RECEIPT', 4, 4, '2026-11-02 14:00:00+07'),
  (84, 1, 'RESERVE', 4, 116, 'REPAIR_ORDER', 3, 3, '2026-11-05 10:25:00+07'),
  (85, 2, 'RESERVE', 1, 49, 'REPAIR_ORDER', 3, 3, '2026-11-05 10:25:00+07'),
  (86, 1, 'ISSUE', -4, 112, 'PART_REQUEST', 3, 3, '2026-11-05 11:25:00+07'),
  (87, 2, 'ISSUE', -1, 48, 'PART_REQUEST', 3, 3, '2026-11-05 11:25:00+07'),
  (88, 5, 'RESERVE', 1, 29, 'REPAIR_ORDER', 4, 3, '2026-11-06 12:25:00+07'),
  (89, 7, 'RESERVE', 1, 30, 'REPAIR_ORDER', 4, 3, '2026-11-06 12:25:00+07'),
  (90, 5, 'ISSUE', -1, 28, 'PART_REQUEST', 4, 3, '2026-11-06 13:25:00+07'),
  (91, 7, 'ISSUE', -1, 29, 'PART_REQUEST', 4, 3, '2026-11-06 13:25:00+07'),
  (92, 9, 'RESERVE', 1, 29, 'REPAIR_ORDER', 20, 3, '2026-11-06 17:25:00+07'),
  (93, 9, 'ISSUE', -1, 28, 'PART_REQUEST', 13, 3, '2026-11-06 18:25:00+07'),
  (94, 10, 'RESERVE', 4, 30, 'REPAIR_ORDER', 5, 3, '2026-11-07 10:25:00+07'),
  (95, 1, 'RESERVE', 4, 112, 'REPAIR_ORDER', 5, 3, '2026-11-07 10:25:00+07'),
  (96, 2, 'RESERVE', 1, 48, 'REPAIR_ORDER', 5, 3, '2026-11-07 10:25:00+07'),
  (97, 10, 'ISSUE', -4, 26, 'PART_REQUEST', 5, 3, '2026-11-07 11:25:00+07'),
  (98, 1, 'ISSUE', -4, 108, 'PART_REQUEST', 5, 3, '2026-11-07 11:25:00+07'),
  (99, 2, 'ISSUE', -1, 47, 'PART_REQUEST', 5, 3, '2026-11-07 11:25:00+07'),
  (100, 1, 'RESERVE', 6, 108, 'REPAIR_ORDER', 6, 3, '2026-11-07 11:25:00+07'),
  (101, 2, 'RESERVE', 1, 47, 'REPAIR_ORDER', 6, 3, '2026-11-07 11:25:00+07'),
  (102, 3, 'RESERVE', 1, 40, 'REPAIR_ORDER', 6, 3, '2026-11-07 11:25:00+07'),
  (103, 11, 'RESERVE', 2, 4, 'REPAIR_ORDER', 6, 3, '2026-11-07 11:25:00+07'),
  (104, 25, 'RESERVE', 1, 30, 'REPAIR_ORDER', 13, 10, '2026-11-07 12:25:00+07'),
  (105, 5, 'RESERVE', 1, 28, 'REPAIR_ORDER', 21, 3, '2026-11-07 12:25:00+07'),
  (106, 5, 'ISSUE', -1, 27, 'PART_REQUEST', 14, 3, '2026-11-07 13:25:00+07'),
  (107, 5, 'RESERVE', 1, 27, 'REPAIR_ORDER', 7, 3, '2026-11-07 15:25:00+07'),
  (108, 5, 'RESERVE', 1, 27, 'REPAIR_ORDER', 19, 3, '2026-11-07 16:25:00+07'),
  (109, 5, 'ISSUE', -1, 26, 'PART_REQUEST', 12, 3, '2026-11-07 17:25:00+07'),
  (110, 4, 'RESERVE', 1, 29, 'REPAIR_ORDER', 8, 3, '2026-11-08 10:25:00+07'),
  (111, 9, 'RESERVE', 1, 28, 'REPAIR_ORDER', 8, 3, '2026-11-08 10:25:00+07'),
  (112, 8, 'RESERVE', 1, 7, 'REPAIR_ORDER', 8, 3, '2026-11-08 10:25:00+07'),
  (113, 1, 'RESERVE', 4, 108, 'REPAIR_ORDER', 17, 3, '2026-11-08 10:25:00+07'),
  (114, 2, 'RESERVE', 1, 47, 'REPAIR_ORDER', 17, 3, '2026-11-08 10:25:00+07'),
  (115, 1, 'RESERVE', 5, 108, 'REPAIR_ORDER', 9, 3, '2026-11-08 11:25:00+07'),
  (116, 2, 'RESERVE', 1, 47, 'REPAIR_ORDER', 9, 3, '2026-11-08 11:25:00+07'),
  (117, 41, 'RESERVE', 5, 80, 'REPAIR_ORDER', 16, 17, '2026-11-08 11:25:00+07'),
  (118, 42, 'RESERVE', 1, 30, 'REPAIR_ORDER', 16, 17, '2026-11-08 11:25:00+07'),
  (119, 1, 'ISSUE', -4, 104, 'PART_REQUEST', 10, 3, '2026-11-08 11:25:00+07'),
  (120, 2, 'ISSUE', -1, 46, 'PART_REQUEST', 10, 3, '2026-11-08 11:25:00+07'),
  (121, 1, 'RESERVE', 5, 104, 'REPAIR_ORDER', 10, 3, '2026-11-08 12:25:00+07'),
  (122, 2, 'RESERVE', 1, 46, 'REPAIR_ORDER', 10, 3, '2026-11-08 12:25:00+07'),
  (123, 3, 'RESERVE', 1, 40, 'REPAIR_ORDER', 10, 3, '2026-11-08 12:25:00+07'),
  (124, 4, 'RESERVE', 1, 29, 'REPAIR_ORDER', 10, 3, '2026-11-08 12:25:00+07'),
  (125, 16, 'RESERVE', 1, 30, 'REPAIR_ORDER', 11, 3, '2026-11-08 12:25:00+07'),
  (126, 17, 'RESERVE', 1, 30, 'REPAIR_ORDER', 11, 3, '2026-11-08 12:25:00+07'),
  (127, 1, 'RESERVE', 5, 104, 'REPAIR_ORDER', 18, 3, '2026-11-08 13:25:00+07'),
  (128, 2, 'RESERVE', 1, 46, 'REPAIR_ORDER', 18, 3, '2026-11-08 13:25:00+07'),
  (129, 3, 'RESERVE', 1, 40, 'REPAIR_ORDER', 18, 3, '2026-11-08 13:25:00+07'),
  (130, 1, 'ISSUE', -5, 99, 'PART_REQUEST', 11, 3, '2026-11-08 14:25:00+07'),
  (131, 2, 'ISSUE', -1, 45, 'PART_REQUEST', 11, 3, '2026-11-08 14:25:00+07'),
  (132, 3, 'ISSUE', -1, 39, 'PART_REQUEST', 11, 3, '2026-11-08 14:25:00+07');

-- invoices (9 rows)
INSERT INTO invoices (invoice_id, invoice_code, repair_order_id, billing_id, subtotal, discount_amount, vat_amount, total_amount, payment_status, status, finalized_by, finalized_at, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'INV-261012-0001', 1, 1, 2840000, 0, 227200, 3067200, 'PAID', 'FINALIZED', 5, '2026-10-12 15:00:00+07', '2026-10-12 15:00:00+07'),
  (2, 'INV-261020-0001', 2, 2, 3070000, 0, 245600, 3315600, 'PAID', 'FINALIZED', 5, '2026-10-20 16:00:00+07', '2026-10-20 16:00:00+07'),
  (3, 'INV-261015-0001', 12, 5, 1190000, 0, 95200, 1285200, 'PAID', 'FINALIZED', 12, '2026-10-15 16:00:00+07', '2026-10-15 16:00:00+07'),
  (4, 'INV-261025-0001', 15, 6, 370000, 0, 29600, 399600, 'PAID', 'FINALIZED', 19, '2026-10-25 15:00:00+07', '2026-10-25 15:00:00+07'),
  (5, 'INV-261108-0001', 17, 4, 1490000, 0, 119200, 1609200, 'UNPAID', 'FINALIZED', 5, '2026-11-08 15:00:00+07', '2026-11-08 15:00:00+07'),
  (6, 'INV-261108-0002', 18, NULL, 2170000, 0, 173600, 2343600, 'UNPAID', 'FINALIZED', 5, '2026-11-08 18:00:00+07', '2026-11-08 18:00:00+07'),
  (7, 'INV-261107-0001', 19, 3, 1100000, 0, 88000, 1188000, 'PAID', 'FINALIZED', 5, '2026-11-07 21:00:00+07', '2026-11-07 21:00:00+07'),
  (8, 'INV-261106-0001', 20, NULL, 1050000, 0, 84000, 1134000, 'PAID', 'FINALIZED', 5, '2026-11-06 22:00:00+07', '2026-11-06 22:00:00+07'),
  (9, 'INV-261107-0002', 21, NULL, 0, 0, 0, 0, 'UNPAID', 'FINALIZED', 5, '2026-11-07 17:00:00+07', '2026-11-07 17:00:00+07');

-- invoice_lines (30 rows)
INSERT INTO invoice_lines (line_id, invoice_id, quotation_item_id, item_type, description, quantity, unit_price, vat_rate, vat_amount, line_total, is_warranty_covered) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, 'SERVICE', 'Bảo dưỡng định kỳ 10.000 km', 1, 900000, 8, 72000, 972000, FALSE),
  (2, 1, 2, 'SERVICE', 'Kiểm tra & thay má phanh', 1, 250000, 8, 20000, 270000, FALSE),
  (3, 1, 3, 'PART', 'Dầu động cơ 5W-30 (1L)', 4, 180000, 8, 57600, 777600, FALSE),
  (4, 1, 4, 'PART', 'Lọc dầu động cơ', 1, 120000, 8, 9600, 129600, FALSE),
  (5, 1, 5, 'PART', 'Má phanh trước (bộ)', 1, 850000, 8, 68000, 918000, FALSE),
  (6, 2, 6, 'SERVICE', 'Vệ sinh & nạp gas điều hòa', 1, 600000, 8, 48000, 648000, FALSE),
  (7, 2, 7, 'SERVICE', 'Kiểm tra & thay ắc quy', 1, 150000, 8, 12000, 162000, FALSE),
  (8, 2, 9, 'PART', 'Lọc gió điều hòa', 1, 220000, 8, 17600, 237600, FALSE),
  (9, 2, 10, 'PART', 'Ắc quy 12V 45Ah', 1, 1650000, 8, 132000, 1782000, FALSE),
  (10, 2, 11, 'PART', 'Gas điều hòa R134a (bình)', 1, 450000, 8, 36000, 486000, FALSE),
  (11, 3, 55, 'SERVICE', 'Thay dầu động cơ', 1, 350000, 8, 28000, 378000, FALSE),
  (12, 3, 56, 'PART', 'Dầu động cơ 5W-30 (1L)', 4, 180000, 8, 57600, 777600, FALSE),
  (13, 3, 57, 'PART', 'Lọc dầu động cơ', 1, 120000, 8, 9600, 129600, FALSE),
  (14, 4, 61, 'SERVICE', 'Bảo dưỡng xe máy', 1, 200000, 8, 16000, 216000, FALSE),
  (15, 4, 62, 'PART', 'Dầu nhớt xe máy 0.8L', 1, 110000, 8, 8800, 118800, FALSE),
  (16, 4, 63, 'PART', 'Bugi xe máy', 1, 60000, 8, 4800, 64800, FALSE),
  (17, 5, 72, 'SERVICE', 'Thay dầu động cơ', 1, 350000, 8, 28000, 378000, FALSE),
  (18, 5, 73, 'SERVICE', 'Đảo lốp & cân bằng động', 1, 300000, 8, 24000, 324000, FALSE),
  (19, 5, 74, 'PART', 'Dầu động cơ 5W-30 (1L)', 4, 180000, 8, 57600, 777600, FALSE),
  (20, 5, 75, 'PART', 'Lọc dầu động cơ', 1, 120000, 8, 9600, 129600, FALSE),
  (21, 6, 76, 'SERVICE', 'Bảo dưỡng định kỳ 10.000 km', 1, 900000, 8, 72000, 972000, FALSE),
  (22, 6, 77, 'PART', 'Dầu động cơ 5W-30 (1L)', 5, 180000, 8, 72000, 972000, FALSE),
  (23, 6, 78, 'PART', 'Lọc dầu động cơ', 1, 120000, 8, 9600, 129600, FALSE),
  (24, 6, 79, 'PART', 'Lọc gió động cơ', 1, 250000, 8, 20000, 270000, FALSE),
  (25, 7, 80, 'SERVICE', 'Kiểm tra & thay má phanh', 1, 250000, 8, 20000, 270000, FALSE),
  (26, 7, 81, 'PART', 'Má phanh trước (bộ)', 1, 850000, 8, 68000, 918000, FALSE),
  (27, 8, 82, 'SERVICE', 'Vệ sinh & nạp gas điều hòa', 1, 600000, 8, 48000, 648000, FALSE),
  (28, 8, 83, 'PART', 'Gas điều hòa R134a (bình)', 1, 450000, 8, 36000, 486000, FALSE),
  (29, 9, 84, 'SERVICE', 'Kiểm tra & thay má phanh', 1, 250000, 8, 0, 0, TRUE),
  (30, 9, 85, 'PART', 'Má phanh trước (bộ)', 1, 850000, 8, 0, 0, TRUE);

-- payments (6 rows)
INSERT INTO payments (payment_id, invoice_id, amount, method, status, transaction_ref, received_by, paid_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 3067200, 'CASH', 'SUCCESS', NULL, 5, '2026-10-12 15:10:00+07'),
  (2, 2, 3315600, 'BANK_TRANSFER', 'SUCCESS', 'FT26000002', 5, '2026-10-20 16:10:00+07'),
  (3, 3, 1285200, 'CASH', 'SUCCESS', NULL, 12, '2026-10-15 16:10:00+07'),
  (4, 4, 399600, 'BANK_TRANSFER', 'SUCCESS', 'FT26000004', 19, '2026-10-25 15:10:00+07'),
  (5, 7, 1188000, 'CASH', 'SUCCESS', NULL, 5, '2026-11-07 21:10:00+07'),
  (6, 8, 1134000, 'BANK_TRANSFER', 'SUCCESS', 'FT26000008', 5, '2026-11-06 22:10:00+07');

-- e_invoices (6 rows)
INSERT INTO e_invoices (e_invoice_id, invoice_id, config_id, original_e_invoice_id, buyer_name, buyer_tax_code, buyer_address, buyer_email, external_invoice_no, invoice_series, lookup_code, external_status, attempt_count, status, correction_type, correction_reason, response_payload, issued_at, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, NULL, 'Nguyễn Văn An', NULL, '12 Láng Hạ, Đống Đa, Hà Nội', 'customer1@gmail.com', '00000001', 'C26TAC', 'MISA-000001A', 'ISSUED', 1, 'ISSUED', NULL, NULL, '{"success": true}', '2026-10-12 15:15:00+07', '2026-10-12 15:15:00+07'),
  (2, 2, 1, NULL, 'Công ty TNHH Bình An', '0101234567', '56 Kim Mã, Ba Đình, Hà Nội', 'customer2@gmail.com', '00000002', 'C26TAC', 'MISA-000002A', 'REPLACED', 1, 'REPLACED', NULL, NULL, '{"success": true}', '2026-10-20 16:15:00+07', '2026-10-20 16:15:00+07'),
  (3, 2, 1, 2, 'Công ty TNHH Bình An', '0101234567', '56 Kim Mã, Ba Đình, Hà Nội', 'customer2@gmail.com', '00000502', 'C26TAC', 'MISA-000002B', 'ISSUED', 1, 'ISSUED', 'REPLACEMENT', 'Sai tên đơn vị mua hàng', '{"success": true}', '2026-10-21 16:10:00+07', '2026-10-21 16:10:00+07'),
  (4, 3, 1, NULL, 'Đặng Quốc Huy', NULL, '15 Quang Trung, Hà Đông, Hà Nội', 'customer7@gmail.com', '00000003', 'C26TAC', 'MISA-000003A', 'ISSUED', 1, 'ISSUED', NULL, NULL, '{"success": true}', '2026-10-15 16:15:00+07', '2026-10-15 16:15:00+07'),
  (5, 4, 1, NULL, 'Đỗ Thị Lan', NULL, '200 Nguyễn Văn Linh, Quận 7, TP.HCM', 'customer10@gmail.com', '00000004', 'C26TAC', 'MISA-000004A', 'ISSUED', 1, 'ISSUED', NULL, NULL, '{"success": true}', '2026-10-25 15:15:00+07', '2026-10-25 15:15:00+07'),
  (6, 8, 1, NULL, 'Công ty TNHH Thương mại Hưng Phát', '9990001234', '25 Tô Hiệu, Hà Đông, Hà Nội', 'customer8@gmail.com', NULL, 'C26TAC', NULL, 'REJECTED', 1, 'FAILED', NULL, NULL, '{"success": false, "errorCode": "InvalidTaxCode", "message": "Mã số thuế người mua không tồn tại"}', NULL, '2026-11-06 22:15:00+07');

-- vehicle_handovers (4 rows)
INSERT INTO vehicle_handovers (handover_id, appointment_id, invoice_id, handed_by, odometer_out, customer_confirmed, note, handed_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, 3, 45322, TRUE, 'Khách đã kiểm tra và nhận xe', '2026-10-12 15:30:00+07'),
  (2, 2, 2, 3, 21922, TRUE, 'Khách đã kiểm tra và nhận xe', '2026-10-20 16:30:00+07'),
  (3, 19, 3, 10, 95122, TRUE, 'Khách đã kiểm tra và nhận xe', '2026-10-15 16:30:00+07'),
  (4, 23, 4, 17, 18322, TRUE, 'Khách đã kiểm tra và nhận xe', '2026-10-25 15:30:00+07');

-- service_ratings (4 rows)
INSERT INTO service_ratings (rating_id, appointment_id, customer_id, score, comment, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, 5, 'Dịch vụ rất tốt, nhân viên nhiệt tình', '2026-10-12 18:30:00+07'),
  (2, 2, 2, 4, 'Hài lòng, thời gian chờ hơi lâu', '2026-10-20 19:30:00+07'),
  (3, 19, 7, 5, 'Dịch vụ rất tốt, nhân viên nhiệt tình', '2026-10-15 19:30:00+07'),
  (4, 23, 10, 4, 'Hài lòng, thời gian chờ hơi lâu', '2026-10-25 18:30:00+07');

-- warranties (4 rows)
INSERT INTO warranties (warranty_id, warranty_code, policy_id, vehicle_id, repair_order_id, quotation_item_id, start_date, end_date, start_odometer, max_odometer, status, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'WR-261012-0001', 2, 1, 1, 1, '2026-10-12', '2027-01-12', 45322, 50322, 'ACTIVE', '2026-10-12 15:30:00+07'),
  (2, 'WR-261012-0002', 1, 1, 1, 2, '2026-10-12', '2027-04-12', 45322, 55322, 'ACTIVE', '2026-10-12 15:30:00+07'),
  (3, 'WR-261012-0003', 3, 1, 1, 5, '2026-10-12', '2027-04-12', 45322, 55322, 'ACTIVE', '2026-10-12 15:30:00+07'),
  (4, 'WR-261020-0001', 4, 2, 2, 10, '2026-10-20', '2027-10-20', 21922, NULL, 'ACTIVE', '2026-10-20 16:30:00+07');

-- warranty_requests (2 rows)
INSERT INTO warranty_requests (request_id, request_code, warranty_id, customer_id, branch_id, issue_description, current_odometer, status, is_eligible, assessed_by, assessment_note, approved_by, decided_at, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 'WQ-261107-0001', 4, 2, 1, 'Ắc quy yếu, sáng ra khó đề nổ', 22700, 'SUBMITTED', NULL, NULL, NULL, NULL, NULL, '2026-11-07 08:30:00+07'),
  (2, 'WQ-261106-0001', 2, 1, 1, 'Phanh kêu rít khi đạp nhẹ', 46700, 'ASSESSED', TRUE, 8, 'Má phanh lắp lệch, thuộc phạm vi bảo hành tay nghề', NULL, NULL, '2026-11-06 14:00:00+07');

-- notifications (58 rows)
INSERT INTO notifications (notification_id, user_id, channel, title, content, reference_type, reference_id, status, sent_at, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 23, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 1, 'SENT', '2026-10-12 09:00:00+07', '2026-10-12 09:00:00+07'),
  (2, 6, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261012-0001 đã được giao cho bạn.', 'REPAIR_ORDER', 1, 'SENT', '2026-10-12 10:35:00+07', '2026-10-12 10:35:00+07'),
  (3, 24, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 2, 'SENT', '2026-10-20 10:00:00+07', '2026-10-20 10:00:00+07'),
  (4, 7, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261020-0001 đã được giao cho bạn.', 'REPAIR_ORDER', 2, 'SENT', '2026-10-20 11:35:00+07', '2026-10-20 11:35:00+07'),
  (5, 25, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 3, 'SENT', '2026-11-05 09:00:00+07', '2026-11-05 09:00:00+07'),
  (6, 7, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261105-0001 đã được giao cho bạn.', 'REPAIR_ORDER', 3, 'SENT', '2026-11-05 10:35:00+07', '2026-11-05 10:35:00+07'),
  (7, 5, 'IN_APP', 'Hồ sơ chờ thanh toán', 'Lệnh RO-261105-0001 đã hoàn tất kỹ thuật, chờ thu ngân.', 'REPAIR_ORDER', 3, 'SENT', '2026-11-05 14:40:00+07', '2026-11-05 14:40:00+07'),
  (8, 26, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 4, 'SENT', '2026-11-06 11:00:00+07', '2026-11-06 11:00:00+07'),
  (9, 6, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261106-0001 đã được giao cho bạn.', 'REPAIR_ORDER', 4, 'SENT', '2026-11-06 12:35:00+07', '2026-11-06 12:35:00+07'),
  (10, 3, 'IN_APP', 'Lệnh sửa chữa đã hoàn thành', 'Lệnh RO-261106-0001 chờ lễ tân xác nhận.', 'REPAIR_ORDER', 4, 'SENT', '2026-11-06 16:20:00+07', '2026-11-06 16:20:00+07'),
  (11, 27, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 5, 'SENT', '2026-11-07 09:00:00+07', '2026-11-07 09:00:00+07'),
  (12, 6, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261107-0001 đã được giao cho bạn.', 'REPAIR_ORDER', 5, 'SENT', '2026-11-07 10:35:00+07', '2026-11-07 10:35:00+07'),
  (13, 28, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 6, 'SENT', '2026-11-07 10:00:00+07', '2026-11-07 10:00:00+07'),
  (14, 6, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261107-0002 đã được giao cho bạn.', 'REPAIR_ORDER', 6, 'SENT', '2026-11-07 11:35:00+07', '2026-11-07 11:35:00+07'),
  (15, 3, 'IN_APP', 'Yêu cầu xuất phụ tùng mới', 'Lệnh RO-261107-0002 yêu cầu phụ tùng.', 'PART_REQUEST', 6, 'SENT', '2026-11-07 12:30:00+07', '2026-11-07 12:30:00+07'),
  (16, 30, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 7, 'SENT', '2026-11-07 14:00:00+07', '2026-11-07 14:00:00+07'),
  (17, 7, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261107-0003 đã được giao cho bạn.', 'REPAIR_ORDER', 7, 'SENT', '2026-11-07 15:35:00+07', '2026-11-07 15:35:00+07'),
  (18, 3, 'IN_APP', 'Yêu cầu xuất phụ tùng mới', 'Lệnh RO-261107-0003 yêu cầu phụ tùng.', 'PART_REQUEST', 7, 'SENT', '2026-11-07 16:30:00+07', '2026-11-07 16:30:00+07'),
  (19, 31, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 8, 'SENT', '2026-11-08 09:00:00+07', '2026-11-08 09:00:00+07'),
  (20, 6, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261108-0001 đã được giao cho bạn.', 'REPAIR_ORDER', 8, 'SENT', '2026-11-08 10:35:00+07', '2026-11-08 10:35:00+07'),
  (21, 33, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 9, 'SENT', '2026-11-08 10:00:00+07', '2026-11-08 10:00:00+07'),
  (22, 6, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261108-0002 đã được giao cho bạn.', 'REPAIR_ORDER', 9, 'SENT', '2026-11-08 11:35:00+07', '2026-11-08 11:35:00+07'),
  (23, 34, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 10, 'SENT', '2026-11-08 11:00:00+07', '2026-11-08 11:00:00+07'),
  (24, 23, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 11, 'SENT', '2026-11-08 11:00:00+07', '2026-11-08 11:00:00+07'),
  (25, 32, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 12, 'SENT', '2026-11-08 12:00:00+07', '2026-11-08 12:00:00+07'),
  (26, 8, 'IN_APP', 'Bạn được phân công kiểm tra xe', 'Lịch hẹn APT-261108-0006 – xe 29E1-135.79', 'INSPECTION', 13, 'SENT', '2026-11-08 13:10:00+07', '2026-11-08 13:10:00+07'),
  (27, 23, 'IN_APP', 'Lịch hẹn đã được xác nhận', 'Lịch hẹn ngày 2026-11-10 08:00 đã được xác nhận.', 'APPOINTMENT', 14, 'SENT', '2026-11-08 08:00:00+07', '2026-11-08 08:00:00+07'),
  (28, 29, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 13, 'SENT', '2026-10-15 10:00:00+07', '2026-10-15 10:00:00+07'),
  (29, 13, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261015-0001 đã được giao cho bạn.', 'REPAIR_ORDER', 12, 'SENT', '2026-10-15 11:35:00+07', '2026-10-15 11:35:00+07'),
  (30, 30, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 14, 'SENT', '2026-11-07 11:00:00+07', '2026-11-07 11:00:00+07'),
  (31, 13, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261107-0004 đã được giao cho bạn.', 'REPAIR_ORDER', 13, 'SENT', '2026-11-07 12:35:00+07', '2026-11-07 12:35:00+07'),
  (32, 29, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 15, 'SENT', '2026-11-08 15:00:00+07', '2026-11-08 15:00:00+07'),
  (33, 32, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 16, 'SENT', '2026-10-25 09:00:00+07', '2026-10-25 09:00:00+07'),
  (34, 20, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261025-0001 đã được giao cho bạn.', 'REPAIR_ORDER', 15, 'SENT', '2026-10-25 10:35:00+07', '2026-10-25 10:35:00+07'),
  (35, 32, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 17, 'SENT', '2026-11-08 10:00:00+07', '2026-11-08 10:00:00+07'),
  (36, 20, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261108-0006 đã được giao cho bạn.', 'REPAIR_ORDER', 16, 'SENT', '2026-11-08 11:35:00+07', '2026-11-08 11:35:00+07'),
  (37, 32, 'IN_APP', 'Lịch hẹn đã được xác nhận', 'Lịch hẹn ngày 2026-11-13 09:00 đã được xác nhận.', 'APPOINTMENT', 25, 'SENT', '2026-11-11 09:00:00+07', '2026-11-11 09:00:00+07'),
  (38, 24, 'IN_APP', 'Lịch hẹn đã được xác nhận', 'Lịch hẹn ngày 2026-11-09 09:00 đã được xác nhận.', 'APPOINTMENT', 26, 'SENT', '2026-11-07 09:00:00+07', '2026-11-07 09:00:00+07'),
  (39, 27, 'IN_APP', 'Lịch hẹn đã được xác nhận', 'Lịch hẹn ngày 2026-11-09 10:00 đã được xác nhận.', 'APPOINTMENT', 27, 'SENT', '2026-11-07 10:00:00+07', '2026-11-07 10:00:00+07'),
  (40, 6, 'IN_APP', 'Bạn được phân công kiểm tra xe', 'Lịch hẹn APT-261109-0005 – xe 30E-246.13', 'INSPECTION', 19, 'SENT', '2026-11-09 09:10:00+07', '2026-11-09 09:10:00+07'),
  (41, 3, 'IN_APP', 'Kết quả kiểm tra mới', 'Xe 29A-654.32 đã kiểm tra xong, mời lập báo giá.', 'INSPECTION', 20, 'SENT', '2026-11-08 15:50:00+07', '2026-11-08 15:50:00+07'),
  (42, 24, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 18, 'SENT', '2026-11-08 17:00:00+07', '2026-11-08 17:00:00+07'),
  (43, 3, 'IN_APP', 'Khách đã duyệt báo giá', 'Báo giá QT-261108-0008 đã được duyệt, mời tạo lệnh sửa chữa.', 'QUOTATION', 18, 'SENT', '2026-11-08 18:00:00+07', '2026-11-08 18:00:00+07'),
  (44, 28, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 19, 'SENT', '2026-11-08 09:00:00+07', '2026-11-08 09:00:00+07'),
  (45, 7, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261108-0007 đã được giao cho bạn.', 'REPAIR_ORDER', 17, 'SENT', '2026-11-08 10:35:00+07', '2026-11-08 10:35:00+07'),
  (46, 5, 'IN_APP', 'Hồ sơ chờ thanh toán', 'Lệnh RO-261108-0007 đã hoàn tất kỹ thuật, chờ thu ngân.', 'REPAIR_ORDER', 17, 'SENT', '2026-11-08 14:40:00+07', '2026-11-08 14:40:00+07'),
  (47, 34, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 20, 'SENT', '2026-11-08 12:00:00+07', '2026-11-08 12:00:00+07'),
  (48, 8, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261108-0008 đã được giao cho bạn.', 'REPAIR_ORDER', 18, 'SENT', '2026-11-08 13:35:00+07', '2026-11-08 13:35:00+07'),
  (49, 5, 'IN_APP', 'Hồ sơ chờ thanh toán', 'Lệnh RO-261108-0008 đã hoàn tất kỹ thuật, chờ thu ngân.', 'REPAIR_ORDER', 18, 'SENT', '2026-11-08 17:40:00+07', '2026-11-08 17:40:00+07'),
  (50, 25, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 21, 'SENT', '2026-11-07 15:00:00+07', '2026-11-07 15:00:00+07'),
  (51, 6, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261107-0005 đã được giao cho bạn.', 'REPAIR_ORDER', 19, 'SENT', '2026-11-07 16:35:00+07', '2026-11-07 16:35:00+07'),
  (52, 5, 'IN_APP', 'Hồ sơ chờ thanh toán', 'Lệnh RO-261107-0005 đã hoàn tất kỹ thuật, chờ thu ngân.', 'REPAIR_ORDER', 19, 'SENT', '2026-11-07 20:40:00+07', '2026-11-07 20:40:00+07'),
  (53, 30, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 22, 'SENT', '2026-11-06 16:00:00+07', '2026-11-06 16:00:00+07'),
  (54, 7, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261106-0002 đã được giao cho bạn.', 'REPAIR_ORDER', 20, 'SENT', '2026-11-06 17:35:00+07', '2026-11-06 17:35:00+07'),
  (55, 5, 'IN_APP', 'Hồ sơ chờ thanh toán', 'Lệnh RO-261106-0002 đã hoàn tất kỹ thuật, chờ thu ngân.', 'REPAIR_ORDER', 20, 'SENT', '2026-11-06 21:40:00+07', '2026-11-06 21:40:00+07'),
  (56, 33, 'IN_APP', 'Báo giá sửa chữa mới', 'Vui lòng xem và phê duyệt báo giá cho xe của bạn.', 'QUOTATION', 23, 'SENT', '2026-11-07 11:00:00+07', '2026-11-07 11:00:00+07'),
  (57, 8, 'IN_APP', 'Bạn được phân công lệnh sửa chữa', 'Lệnh RO-261107-0006 đã được giao cho bạn.', 'REPAIR_ORDER', 21, 'SENT', '2026-11-07 12:35:00+07', '2026-11-07 12:35:00+07'),
  (58, 5, 'IN_APP', 'Hồ sơ chờ thanh toán', 'Lệnh RO-261107-0006 đã hoàn tất kỹ thuật, chờ thu ngân.', 'REPAIR_ORDER', 21, 'SENT', '2026-11-07 16:40:00+07', '2026-11-07 16:40:00+07');

-- audit_logs (61 rows)
INSERT INTO audit_logs (audit_id, user_id, action, entity_name, entity_id, old_value, new_value, ip_address, created_at) OVERRIDING SYSTEM VALUE VALUES
  (1, 23, 'QUOTATION_APPROVED', 'quotations', 1, NULL, NULL, '127.0.0.1', '2026-10-12 10:00:00+07'),
  (2, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 1, NULL, NULL, '127.0.0.1', '2026-10-12 10:35:00+07'),
  (3, 5, 'CHARGES_FINALIZED', 'invoices', 1, NULL, NULL, '127.0.0.1', '2026-10-12 15:00:00+07'),
  (4, 5, 'PAYMENT_RECORDED', 'payments', 1, NULL, NULL, '127.0.0.1', '2026-10-12 15:10:00+07'),
  (5, 24, 'QUOTATION_APPROVED', 'quotations', 2, NULL, NULL, '127.0.0.1', '2026-10-20 11:00:00+07'),
  (6, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 2, NULL, NULL, '127.0.0.1', '2026-10-20 11:35:00+07'),
  (7, 5, 'CHARGES_FINALIZED', 'invoices', 2, NULL, NULL, '127.0.0.1', '2026-10-20 16:00:00+07'),
  (8, 5, 'PAYMENT_RECORDED', 'payments', 2, NULL, NULL, '127.0.0.1', '2026-10-20 16:10:00+07'),
  (9, 25, 'QUOTATION_APPROVED', 'quotations', 3, NULL, NULL, '127.0.0.1', '2026-11-05 10:00:00+07'),
  (10, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 3, NULL, NULL, '127.0.0.1', '2026-11-05 10:35:00+07'),
  (11, 3, 'REPAIR_VERIFIED', 'repair_orders', 3, NULL, NULL, '127.0.0.1', '2026-11-05 14:40:00+07'),
  (12, 26, 'QUOTATION_APPROVED', 'quotations', 4, NULL, NULL, '127.0.0.1', '2026-11-06 12:00:00+07'),
  (13, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 4, NULL, NULL, '127.0.0.1', '2026-11-06 12:35:00+07'),
  (14, 27, 'QUOTATION_APPROVED', 'quotations', 5, NULL, NULL, '127.0.0.1', '2026-11-07 10:00:00+07'),
  (15, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 5, NULL, NULL, '127.0.0.1', '2026-11-07 10:35:00+07'),
  (16, 28, 'QUOTATION_APPROVED', 'quotations', 6, NULL, NULL, '127.0.0.1', '2026-11-07 11:00:00+07'),
  (17, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 6, NULL, NULL, '127.0.0.1', '2026-11-07 11:35:00+07'),
  (18, 30, 'QUOTATION_APPROVED', 'quotations', 7, NULL, NULL, '127.0.0.1', '2026-11-07 15:00:00+07'),
  (19, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 7, NULL, NULL, '127.0.0.1', '2026-11-07 15:35:00+07'),
  (20, 31, 'QUOTATION_APPROVED', 'quotations', 8, NULL, NULL, '127.0.0.1', '2026-11-08 10:00:00+07'),
  (21, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 8, NULL, NULL, '127.0.0.1', '2026-11-08 10:35:00+07'),
  (22, 33, 'QUOTATION_APPROVED', 'quotations', 9, NULL, NULL, '127.0.0.1', '2026-11-08 11:00:00+07'),
  (23, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 9, NULL, NULL, '127.0.0.1', '2026-11-08 11:35:00+07'),
  (24, 34, 'QUOTATION_APPROVED', 'quotations', 10, NULL, NULL, '127.0.0.1', '2026-11-08 12:00:00+07'),
  (25, 23, 'QUOTATION_APPROVED', 'quotations', 11, NULL, NULL, '127.0.0.1', '2026-11-08 12:00:00+07'),
  (26, 29, 'QUOTATION_APPROVED', 'quotations', 13, NULL, NULL, '127.0.0.1', '2026-10-15 11:00:00+07'),
  (27, 10, 'MECHANIC_ASSIGNED', 'repair_orders', 12, NULL, NULL, '127.0.0.1', '2026-10-15 11:35:00+07'),
  (28, 12, 'CHARGES_FINALIZED', 'invoices', 3, NULL, NULL, '127.0.0.1', '2026-10-15 16:00:00+07'),
  (29, 12, 'PAYMENT_RECORDED', 'payments', 3, NULL, NULL, '127.0.0.1', '2026-10-15 16:10:00+07'),
  (30, 30, 'QUOTATION_APPROVED', 'quotations', 14, NULL, NULL, '127.0.0.1', '2026-11-07 12:00:00+07'),
  (31, 10, 'MECHANIC_ASSIGNED', 'repair_orders', 13, NULL, NULL, '127.0.0.1', '2026-11-07 12:35:00+07'),
  (32, 29, 'QUOTATION_APPROVED', 'quotations', 15, NULL, NULL, '127.0.0.1', '2026-11-08 16:00:00+07'),
  (33, 32, 'QUOTATION_APPROVED', 'quotations', 16, NULL, NULL, '127.0.0.1', '2026-10-25 10:00:00+07'),
  (34, 17, 'MECHANIC_ASSIGNED', 'repair_orders', 15, NULL, NULL, '127.0.0.1', '2026-10-25 10:35:00+07'),
  (35, 19, 'CHARGES_FINALIZED', 'invoices', 4, NULL, NULL, '127.0.0.1', '2026-10-25 15:00:00+07'),
  (36, 19, 'PAYMENT_RECORDED', 'payments', 4, NULL, NULL, '127.0.0.1', '2026-10-25 15:10:00+07'),
  (37, 32, 'QUOTATION_APPROVED', 'quotations', 17, NULL, NULL, '127.0.0.1', '2026-11-08 11:00:00+07'),
  (38, 17, 'MECHANIC_ASSIGNED', 'repair_orders', 16, NULL, NULL, '127.0.0.1', '2026-11-08 11:35:00+07'),
  (39, 24, 'QUOTATION_APPROVED', 'quotations', 18, NULL, NULL, '127.0.0.1', '2026-11-08 18:00:00+07'),
  (40, 28, 'QUOTATION_APPROVED', 'quotations', 19, NULL, NULL, '127.0.0.1', '2026-11-08 10:00:00+07'),
  (41, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 17, NULL, NULL, '127.0.0.1', '2026-11-08 10:35:00+07'),
  (42, 3, 'REPAIR_VERIFIED', 'repair_orders', 17, NULL, NULL, '127.0.0.1', '2026-11-08 14:40:00+07'),
  (43, 5, 'CHARGES_FINALIZED', 'invoices', 5, NULL, NULL, '127.0.0.1', '2026-11-08 15:00:00+07'),
  (44, 34, 'QUOTATION_APPROVED', 'quotations', 20, NULL, NULL, '127.0.0.1', '2026-11-08 13:00:00+07'),
  (45, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 18, NULL, NULL, '127.0.0.1', '2026-11-08 13:35:00+07'),
  (46, 3, 'REPAIR_VERIFIED', 'repair_orders', 18, NULL, NULL, '127.0.0.1', '2026-11-08 17:40:00+07'),
  (47, 5, 'CHARGES_FINALIZED', 'invoices', 6, NULL, NULL, '127.0.0.1', '2026-11-08 18:00:00+07'),
  (48, 25, 'QUOTATION_APPROVED', 'quotations', 21, NULL, NULL, '127.0.0.1', '2026-11-07 16:00:00+07'),
  (49, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 19, NULL, NULL, '127.0.0.1', '2026-11-07 16:35:00+07'),
  (50, 3, 'REPAIR_VERIFIED', 'repair_orders', 19, NULL, NULL, '127.0.0.1', '2026-11-07 20:40:00+07'),
  (51, 5, 'CHARGES_FINALIZED', 'invoices', 7, NULL, NULL, '127.0.0.1', '2026-11-07 21:00:00+07'),
  (52, 5, 'PAYMENT_RECORDED', 'payments', 5, NULL, NULL, '127.0.0.1', '2026-11-07 21:10:00+07'),
  (53, 30, 'QUOTATION_APPROVED', 'quotations', 22, NULL, NULL, '127.0.0.1', '2026-11-06 17:00:00+07'),
  (54, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 20, NULL, NULL, '127.0.0.1', '2026-11-06 17:35:00+07'),
  (55, 3, 'REPAIR_VERIFIED', 'repair_orders', 20, NULL, NULL, '127.0.0.1', '2026-11-06 21:40:00+07'),
  (56, 5, 'CHARGES_FINALIZED', 'invoices', 8, NULL, NULL, '127.0.0.1', '2026-11-06 22:00:00+07'),
  (57, 5, 'PAYMENT_RECORDED', 'payments', 6, NULL, NULL, '127.0.0.1', '2026-11-06 22:10:00+07'),
  (58, 33, 'QUOTATION_APPROVED', 'quotations', 23, NULL, NULL, '127.0.0.1', '2026-11-07 12:00:00+07'),
  (59, 3, 'MECHANIC_ASSIGNED', 'repair_orders', 21, NULL, NULL, '127.0.0.1', '2026-11-07 12:35:00+07'),
  (60, 3, 'REPAIR_VERIFIED', 'repair_orders', 21, NULL, NULL, '127.0.0.1', '2026-11-07 16:40:00+07'),
  (61, 5, 'CHARGES_FINALIZED', 'invoices', 9, NULL, NULL, '127.0.0.1', '2026-11-07 17:00:00+07');

-- booked_count = active appointments per slot
UPDATE time_slots s SET booked_count = x.n FROM (SELECT slot_id, COUNT(*) n FROM appointments WHERE status NOT IN ('CANCELLED','REJECTED') GROUP BY slot_id) x WHERE x.slot_id = s.slot_id;

-- move identity sequences past the seeded ids
SELECT setval(pg_get_serial_sequence('branches', 'branch_id'), (SELECT MAX(branch_id) FROM branches));
SELECT setval(pg_get_serial_sequence('users', 'user_id'), (SELECT MAX(user_id) FROM users));
SELECT setval(pg_get_serial_sequence('customers', 'customer_id'), (SELECT MAX(customer_id) FROM customers));
SELECT setval(pg_get_serial_sequence('staff', 'staff_id'), (SELECT MAX(staff_id) FROM staff));
SELECT setval(pg_get_serial_sequence('billing_information', 'billing_id'), (SELECT MAX(billing_id) FROM billing_information));
SELECT setval(pg_get_serial_sequence('vehicles', 'vehicle_id'), (SELECT MAX(vehicle_id) FROM vehicles));
SELECT setval(pg_get_serial_sequence('services', 'service_id'), (SELECT MAX(service_id) FROM services));
SELECT setval(pg_get_serial_sequence('parts', 'part_id'), (SELECT MAX(part_id) FROM parts));
SELECT setval(pg_get_serial_sequence('repair_order_types', 'type_id'), (SELECT MAX(type_id) FROM repair_order_types));
SELECT setval(pg_get_serial_sequence('warehouses', 'warehouse_id'), (SELECT MAX(warehouse_id) FROM warehouses));
SELECT setval(pg_get_serial_sequence('inventories', 'inventory_id'), (SELECT MAX(inventory_id) FROM inventories));
SELECT setval(pg_get_serial_sequence('inventory_receipts', 'receipt_id'), (SELECT MAX(receipt_id) FROM inventory_receipts));
SELECT setval(pg_get_serial_sequence('inventory_receipt_items', 'receipt_item_id'), (SELECT MAX(receipt_item_id) FROM inventory_receipt_items));
SELECT setval(pg_get_serial_sequence('warranty_policies', 'policy_id'), (SELECT MAX(policy_id) FROM warranty_policies));
SELECT setval(pg_get_serial_sequence('tax_rules', 'tax_rule_id'), (SELECT MAX(tax_rule_id) FROM tax_rules));
SELECT setval(pg_get_serial_sequence('einvoice_configs', 'config_id'), (SELECT MAX(config_id) FROM einvoice_configs));
SELECT setval(pg_get_serial_sequence('appointments', 'appointment_id'), (SELECT MAX(appointment_id) FROM appointments));
SELECT setval(pg_get_serial_sequence('vehicle_receptions', 'reception_id'), (SELECT MAX(reception_id) FROM vehicle_receptions));
SELECT setval(pg_get_serial_sequence('inspections', 'inspection_id'), (SELECT MAX(inspection_id) FROM inspections));
SELECT setval(pg_get_serial_sequence('inspection_items', 'inspection_item_id'), (SELECT MAX(inspection_item_id) FROM inspection_items));
SELECT setval(pg_get_serial_sequence('quotations', 'quotation_id'), (SELECT MAX(quotation_id) FROM quotations));
SELECT setval(pg_get_serial_sequence('quotation_items', 'item_id'), (SELECT MAX(item_id) FROM quotation_items));
SELECT setval(pg_get_serial_sequence('repair_orders', 'repair_order_id'), (SELECT MAX(repair_order_id) FROM repair_orders));
SELECT setval(pg_get_serial_sequence('repair_tasks', 'task_id'), (SELECT MAX(task_id) FROM repair_tasks));
SELECT setval(pg_get_serial_sequence('repair_notes', 'note_id'), (SELECT MAX(note_id) FROM repair_notes));
SELECT setval(pg_get_serial_sequence('part_reservations', 'reservation_id'), (SELECT MAX(reservation_id) FROM part_reservations));
SELECT setval(pg_get_serial_sequence('part_requests', 'request_id'), (SELECT MAX(request_id) FROM part_requests));
SELECT setval(pg_get_serial_sequence('part_request_items', 'request_item_id'), (SELECT MAX(request_item_id) FROM part_request_items));
SELECT setval(pg_get_serial_sequence('repair_task_parts', 'task_part_id'), (SELECT MAX(task_part_id) FROM repair_task_parts));
SELECT setval(pg_get_serial_sequence('inventory_transactions', 'transaction_id'), (SELECT MAX(transaction_id) FROM inventory_transactions));
SELECT setval(pg_get_serial_sequence('invoices', 'invoice_id'), (SELECT MAX(invoice_id) FROM invoices));
SELECT setval(pg_get_serial_sequence('invoice_lines', 'line_id'), (SELECT MAX(line_id) FROM invoice_lines));
SELECT setval(pg_get_serial_sequence('payments', 'payment_id'), (SELECT MAX(payment_id) FROM payments));
SELECT setval(pg_get_serial_sequence('e_invoices', 'e_invoice_id'), (SELECT MAX(e_invoice_id) FROM e_invoices));
SELECT setval(pg_get_serial_sequence('vehicle_handovers', 'handover_id'), (SELECT MAX(handover_id) FROM vehicle_handovers));
SELECT setval(pg_get_serial_sequence('service_ratings', 'rating_id'), (SELECT MAX(rating_id) FROM service_ratings));
SELECT setval(pg_get_serial_sequence('warranties', 'warranty_id'), (SELECT MAX(warranty_id) FROM warranties));
SELECT setval(pg_get_serial_sequence('warranty_requests', 'request_id'), (SELECT MAX(request_id) FROM warranty_requests));
SELECT setval(pg_get_serial_sequence('notifications', 'notification_id'), (SELECT MAX(notification_id) FROM notifications));
SELECT setval(pg_get_serial_sequence('audit_logs', 'audit_id'), (SELECT MAX(audit_id) FROM audit_logs));
SELECT setval(pg_get_serial_sequence('roles', 'role_id'), (SELECT MAX(role_id) FROM roles));

COMMIT;
