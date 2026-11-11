// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
// End-to-end API test for UC01, UC02, UC05, UC10, UC13 (+UC12 slots, NFR-4 concurrency, NFR-5 lock-out).
// Requires the shared seed database and this API running on :4001.   Run:  node test/smoke-test.mjs
// The test ADDS data (accounts, vehicles, appointments) – reload the seed afterwards with Giang/database/reset-db.ps1
import pg from 'pg';

const API = process.env.API ?? 'http://localhost:4001/api';
const db = new pg.Client({ host: 'localhost', user: 'autocare', password: 'autocare123', database: 'autocare' });
await db.connect();
let pass = 0, fail = 0;
const run = Date.now() % 1_000_000;

async function call(token, method, path, body) {
  const res = await fetch(API + path, {
    method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json().catch(() => ({})) };
}
const check = (name, cond, extra = '') => { if (cond) { pass++; console.log(`  ✔ ${name}`); } else { fail++; console.log(`  ✘ ${name} ${extra}`); } };
const expect = async (name, p, code) => { const r = await p; check(`${name} → ${code}`, r.status === code, `(got ${r.status}: ${JSON.stringify(r.data.message)})`); return r; };
const login = async (l, p = 'Password@123') => (await call(null, 'POST', '/auth/login', { login: l, password: p })).data.accessToken;
const phone = (i) => '097' + String((run * 7 + i) % 10_000_000).padStart(7, '0');
const plate = (i) => `${(run % 89) + 10}TT-${String(i).padStart(3, '0')}.${String(run % 100).padStart(2, '0')}`;

console.log('\nUC01 – Register Account');
const me = { fullName: 'Khách Kiểm Thử', phone: phone(0), email: `test.${run}@example.com`, password: 'Matkhau123', confirmPassword: 'Matkhau123' };
let r = await expect('register new customer', call(null, 'POST', '/auth/register', me), 201);
check('returns customerId', r.data.customerId > 0);
const [u] = (await db.query('SELECT password_hash, status FROM users WHERE email = $1', [me.email])).rows;
check('password stored as bcrypt hash (BR1)', u.password_hash.startsWith('$2') && u.password_hash !== me.password);
await expect('duplicate email (01.E2, BR2)', call(null, 'POST', '/auth/register', { ...me, phone: phone(1) }), 409);
await expect('duplicate phone (01.E2, BR2)', call(null, 'POST', '/auth/register', { ...me, email: `x.${run}@example.com` }), 409);
await expect('invalid phone format (01.E1)', call(null, 'POST', '/auth/register', { ...me, phone: '12345', email: `y.${run}@example.com` }), 400);
await expect('weak password', call(null, 'POST', '/auth/register', { ...me, password: 'abcdefgh', confirmPassword: 'abcdefgh', email: `z.${run}@example.com`, phone: phone(2) }), 400);
await expect('confirm password mismatch', call(null, 'POST', '/auth/register', { ...me, confirmPassword: 'Khac12345', email: `w.${run}@example.com`, phone: phone(3) }), 400);
await expect('missing full name', call(null, 'POST', '/auth/register', { ...me, fullName: '', email: `v.${run}@example.com`, phone: phone(4) }), 400);

console.log('\nUC02 – Login');
r = await expect('login by email', call(null, 'POST', '/auth/login', { login: me.email, password: me.password }), 200);
const cust = r.data.accessToken;
check('customer session has role & customerId', r.data.user.role === 'CUSTOMER' && r.data.user.customerId > 0);
await expect('login by phone', call(null, 'POST', '/auth/login', { login: me.phone, password: me.password }), 200);
r = await expect('wrong password (02.E1)', call(null, 'POST', '/auth/login', { login: me.email, password: 'Sai123456' }), 401);
check('message shows remaining attempts', /còn 4 lần/.test(r.data.message));
r = await expect('staff login resolves role and branch (BR4)', call(null, 'POST', '/auth/login', { login: 'reception1.cg@autocare.vn', password: 'Password@123' }), 200);
check('receptionist scope = branch 1', r.data.user.role === 'RECEPTIONIST' && r.data.user.branchId === 1);
const rec = r.data.accessToken;
const recHD = await login('reception1.hd@autocare.vn');
for (let i = 0; i < 4; i++) await call(null, 'POST', '/auth/login', { login: me.phone, password: 'Sai123456' });
await expect('locked after 5 failures (NFR-5)', call(null, 'POST', '/auth/login', { login: me.email, password: me.password }), 403);
await db.query('UPDATE users SET locked_until = NULL, failed_login_count = 0 WHERE email = $1', [me.email]);   // unlock for the rest of the test

console.log('\nUC05 – Add Vehicle');
const car = { licensePlate: plate(0).toLowerCase(), vehicleType: 'CAR', brand: 'Toyota', model: 'Vios', manufactureYear: 2021, currentOdometer: 15000 };
r = await expect('add vehicle', call(cust, 'POST', '/vehicles', car), 201);
check('plate normalised to upper case', r.data.vehicle.licensePlate === plate(0));
check('vehicle list refreshed', r.data.vehicles.length === 1);
const carId = r.data.vehicle.id;
await expect('duplicate plate (05.E1)', call(cust, 'POST', '/vehicles', { ...car, licensePlate: '30A-123.45' }), 409);
await expect('invalid plate', call(cust, 'POST', '/vehicles', { ...car, licensePlate: 'ABC' }), 400);
await expect('missing brand', call(cust, 'POST', '/vehicles', { ...car, licensePlate: plate(1), brand: '' }), 400);
await expect('invalid VIN', call(cust, 'POST', '/vehicles', { ...car, licensePlate: plate(1), vin: 'SHORT' }), 400);
await expect('receptionist cannot add to own list', call(rec, 'POST', '/vehicles', { ...car, licensePlate: plate(1) }), 403);
r = await expect('add motorcycle', call(cust, 'POST', '/vehicles', { licensePlate: plate(2).replace('TT', 'T1'), vehicleType: 'MOTORCYCLE', brand: 'Honda', model: 'Vision', currentOdometer: 500 }), 201);
const motoId = r.data.vehicle.id;
await expect('no token', call(null, 'GET', '/vehicles/mine'), 401);

console.log('\nUC10 – View Service List');
r = await expect('branches', call(null, 'GET', '/branches'), 200);
check('3 active branches', r.data.length === 3);
r = await expect('services of branch 1 (public)', call(null, 'GET', '/branches/1/services'), 200);
check('10 services with price & duration', r.data.length === 10 && r.data.every((s) => s.price > 0 && s.estimatedMinutes > 0));
r = await call(null, 'GET', '/branches/1/services?vehicleType=MOTORCYCLE');
check('motorcycle filter hides car-only services', r.data.length > 0 && r.data.every((s) => ['ALL', 'MOTORCYCLE'].includes(s.vehicleType)));
await expect('unknown branch', call(null, 'GET', '/branches/99/services'), 404);
await db.query(`UPDATE branch_services SET is_enabled = FALSE WHERE branch_id = 2 AND service_id = (SELECT service_id FROM services WHERE service_code = 'SV-WASH')`);
r = await call(null, 'GET', '/branches/2/services');
check('disabled service not shown at that branch', r.data.length === 9 && !r.data.some((s) => s.code === 'SV-WASH'));
await db.query(`UPDATE branch_services SET is_enabled = TRUE WHERE branch_id = 2`);

console.log('\nUC12/UC13 – Time slots & Create Service Appointment');
r = await expect('slots of 20/11/2026', call(null, 'GET', '/branches/1/slots?date=2026-11-20'), 200);
check('9 hourly slots 08:00–16:00', r.data.slots.length === 9 && r.data.slots[0].startTime === '08:00');
const freeSlots = r.data.slots.filter((s) => s.available);
const slot = freeSlots[0];
r = await call(null, 'GET', '/branches/1/slots?date=2026-11-01');
check('past slots are not available', r.data.slots.every((s) => !s.available) && r.data.message);
const services = (await call(null, 'GET', '/branches/1/services?vehicleType=CAR')).data;
const oil = services.find((s) => s.code === 'SV-OIL'), brake = services.find((s) => s.code === 'SV-BRAKE');
const motoSvc = (await call(null, 'GET', '/branches/1/services')).data.find((s) => s.code === 'SV-MOTO-MAINT');
const book = { vehicleId: carId, branchId: 1, slotId: slot.id, serviceIds: [oil.id, brake.id], note: 'Phanh kêu' };
await expect('service not applicable to a car', call(cust, 'POST', '/appointments', { ...book, serviceIds: [motoSvc.id] }), 400);
await expect('vehicle of another customer (BR6)', call(cust, 'POST', '/appointments', { ...book, vehicleId: 1 }), 403);
const otherBranchSlot = (await call(null, 'GET', '/branches/2/slots?date=2026-11-20')).data.slots[0];
await expect('slot of another branch', call(cust, 'POST', '/appointments', { ...book, slotId: otherBranchSlot.id }), 400);
const pastSlot = (await call(null, 'GET', '/branches/1/slots?date=2026-11-01')).data.slots[0];
await expect('past slot', call(cust, 'POST', '/appointments', { ...book, slotId: pastSlot.id }), 409);
await expect('no service selected', call(cust, 'POST', '/appointments', { ...book, serviceIds: [] }), 400);
const before = (await db.query('SELECT booked_count FROM time_slots WHERE slot_id = $1', [slot.id])).rows[0].booked_count;
r = await expect('create appointment', call(cust, 'POST', '/appointments', book), 201);
check('status PENDING (BR11)', r.data.status === 'PENDING');
check('code APT-261120-xxxx', /^APT-261120-\d{4}$/.test(r.data.code));
check('estimated total = 350k + 250k', r.data.estimatedTotal === oil.price + brake.price);
const after = (await db.query('SELECT booked_count FROM time_slots WHERE slot_id = $1', [slot.id])).rows[0].booked_count;
check('slot utilisation +1 (BR10)', after === before + 1);
await expect('same vehicle twice the same day', call(cust, 'POST', '/appointments', { ...book, slotId: freeSlots[1].id }), 409);
r = await call(cust, 'GET', '/auth/notifications');
check('customer notified', r.data.some((n) => n.title === 'Đặt lịch thành công'));
r = await call(rec, 'GET', '/auth/notifications');
check('branch receptionist notified', r.data.some((n) => n.title === 'Lịch hẹn mới chờ xác nhận'));
r = await call(cust, 'GET', '/appointments/mine');
check('appears in my appointments', r.data.length === 1 && r.data[0].services.length === 2);

console.log('\n13.A1 – Receptionist books for a walk-in customer');
r = await expect('find customer by phone', call(rec, 'GET', `/customers?q=${me.phone}`), 200);
check('customer found', r.data.length === 1);
const custId = r.data[0].id;
r = await call(rec, 'GET', `/customers/${custId}/vehicles`);
check('customer vehicles listed', r.data.length === 2);
await expect('customer must be chosen', call(rec, 'POST', '/appointments', { ...book, vehicleId: motoId, serviceIds: [motoSvc.id] }), 400);
await expect('receptionist of another branch (BR48)', call(recHD, 'POST', '/appointments', { ...book, customerId: custId, vehicleId: motoId, serviceIds: [motoSvc.id] }), 403);
r = await expect('receptionist creates appointment', call(rec, 'POST', '/appointments', { ...book, customerId: custId, vehicleId: motoId, serviceIds: [motoSvc.id], note: 'Khách gọi điện' }), 201);
check('PENDING for that customer', r.data.status === 'PENDING' && r.data.customerName === me.fullName);

console.log('\nNFR-4 – 100 customers race for the last place of a slot');
const race = (await call(null, 'GET', '/branches/3/slots?date=2026-11-27')).data.slots.find((s) => s.startTime === '15:00');
await db.query('UPDATE time_slots SET capacity = 1, booked_count = 0 WHERE slot_id = $1', [race.id]);
const racers = [];
for (let i = 1; i <= 100; i++) {
  const acc = { fullName: `Khách đua ${i}`, phone: phone(100 + i), email: `race${i}.${run}@example.com`, password: 'Matkhau123', confirmPassword: 'Matkhau123' };
  await call(null, 'POST', '/auth/register', acc);
  const t = await login(acc.email, acc.password);
  const v = await call(t, 'POST', '/vehicles', { licensePlate: plate(100 + i), vehicleType: 'CAR', brand: 'Kia', model: 'Morning', currentOdometer: 1000 });
  racers.push({ t, vehicleId: v.data.vehicle.id });
}
const svc3 = (await call(null, 'GET', '/branches/3/services?vehicleType=CAR')).data[0];
const results = await Promise.all(racers.map((x) => call(x.t, 'POST', '/appointments', { vehicleId: x.vehicleId, branchId: 3, slotId: race.id, serviceIds: [svc3.id] })));
const ok = results.filter((x) => x.status === 201).length;
const full = results.filter((x) => x.status === 409 && /hết chỗ/.test(x.data.message)).length;
check(`exactly 1 of 100 succeeds (got ${ok})`, ok === 1);
check(`the other 99 get a clear "slot full" message (got ${full})`, full === 99);
const [s] = (await db.query('SELECT booked_count, capacity FROM time_slots WHERE slot_id = $1', [race.id])).rows;
check('booked_count never exceeds capacity', s.booked_count === 1 && s.capacity === 1);

await db.end();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
