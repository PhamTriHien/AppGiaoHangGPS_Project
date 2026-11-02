import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

export async function testCloudLogistics({ db, as, operator, merchant, driver, buyers, check }) {
  const logistics = (id, action, payload = {}) => as(id, 'delivery_cloud_logistics', [action, payload]);
  const code = async (promise, expected) => {
    await assert.rejects(promise, error => error.code === expected, `expected ${expected}`);
  };
  const localDate = async offset => (await db.query(
    "select ((now() at time zone 'Asia/Ho_Chi_Minh')::date + $1::integer)::text as d", [offset])).rows[0].d;
  const sender = buyers[6], stranger = buyers[5];

  await check('L0 reapplying 20261108_cloud_logistics keeps orders and passes the deployment schema check', async () => {
    await db.query(await readFile(new URL('../../../database/migrations/20261108_cloud_logistics.sql', import.meta.url), 'utf8'));
    const { DEPLOYMENT_SCHEMA_SQL } = await import('../deployment-readiness.mjs');
    assert.equal((await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0].logistics_schema, true);
    for (const role of ['anon', 'authenticated']) {
      await assert.rejects(db.query(`set role ${role}; select * from public.delivery_cloud_pickups`), /permission denied/);
      await db.query('reset role');
    }
  });

  let pickup;
  await check('L1 bulk pickup uses the merchant address book, vehicle capacity, schedule window and idempotent keys', async () => {
    const warehouse = (await as(merchant, 'delivery_cloud_addresses_manage', [randomUUID(), {
      label: 'Kho chính', recipient_name: 'Thủ kho', recipient_phone: '0907654321',
      full_address: '12 Nguyen Hue TP HCM', latitude: 10.77, longitude: 106.7, is_default: false,
    }, false, null])).addresses.find(a => a.label === 'Kho chính');
    const foreign = (await as(sender, 'delivery_cloud_addresses_manage')).addresses[0];
    const tomorrow = await localDate(1);
    const base = { address_id: warehouse.id, vehicle_type: 'van_500kg', pickup_date: tomorrow, time_slot: 'afternoon',
      package_count: 15, total_weight_kg: 25, note: 'Cửa kho số 2' };
    await code(logistics(sender, 'pickup_create', { ...base, request_key: randomUUID() }), 'PT403');
    await code(logistics(merchant, 'pickup_create', { ...base, request_key: randomUUID(), total_weight_kg: 600 }), 'PT400');
    await code(logistics(merchant, 'pickup_create', { ...base, request_key: randomUUID(), pickup_date: await localDate(-1) }), 'PT400');
    await code(logistics(merchant, 'pickup_create', { ...base, request_key: randomUUID(), pickup_date: await localDate(15) }), 'PT400');
    await code(logistics(merchant, 'pickup_create', { ...base, request_key: randomUUID(), package_count: 1.5 }), 'PT400');
    await code(logistics(merchant, 'pickup_create', { ...base, request_key: randomUUID(), address_id: foreign.id }), 'PT404');
    const key = randomUUID();
    pickup = await logistics(merchant, 'pickup_create', { ...base, request_key: key });
    assert.equal(pickup.status, 'requested');
    assert.equal(pickup.pickup_address, '12 Nguyen Hue TP HCM');
    assert.equal(pickup.contact_phone, '0907654321');
    assert.equal(pickup.request_payload, undefined);
    assert.equal((await logistics(merchant, 'pickup_create', { ...base, request_key: key })).id, pickup.id);
    await code(logistics(merchant, 'pickup_create', { ...base, request_key: key, package_count: 16 }), 'PT409');
    const truck = await logistics(merchant, 'pickup_create', { ...base, request_key: randomUUID(),
      vehicle_type: 'box_truck_1500kg', total_weight_kg: 1200.5, time_slot: 'morning' });
    assert.equal(Number(truck.total_weight_kg), 1200.5);
    assert.ok((await logistics(merchant, 'pickup_list')).pickups.some(p => p.id === pickup.id));
    assert.equal((await logistics(sender, 'pickup_list')).pickups.length, 0);
    const operatorView = await logistics(operator, 'pickup_list');
    assert.ok(operatorView.pickups.some(p => p.id === pickup.id));
    assert.ok(operatorView.drivers.some(d => d.user_id === driver));
    assert.ok(!operatorView.drivers.some(d => d.user_id === sender));
    assert.deepEqual((await logistics(merchant, 'pickup_list')).drivers, []);
  });

  await check('L2 only operators dispatch approved drivers with optimistic versions and audit', async () => {
    await code(logistics(merchant, 'pickup_assign', { id: pickup.id, version: pickup.version, driver_id: driver }), 'PT403');
    await code(logistics(operator, 'pickup_assign', { id: pickup.id, version: pickup.version, driver_id: sender }), 'PT409');
    await code(logistics(operator, 'pickup_assign', { id: pickup.id, version: pickup.version + 1, driver_id: driver }), 'PT409');
    const assigned = await logistics(operator, 'pickup_assign', { id: pickup.id, version: pickup.version, driver_id: driver });
    assert.equal(assigned.status, 'assigned');
    assert.equal(assigned.driver_id, driver);
    assert.equal(assigned.version, pickup.version + 1);
    await code(logistics(operator, 'pickup_assign', { id: pickup.id, version: assigned.version, driver_id: driver }), 'PT409');
    const driverView = (await logistics(driver, 'pickup_list')).pickups.find(p => p.id === pickup.id);
    assert.equal(driverView.contact_phone, '0907654321');
    const audit = (await db.query("select count(*)::int n from delivery_cloud_admin_audit where action='pickup_assign' and target_id=$1", [pickup.id])).rows[0].n;
    assert.equal(audit, 1);
  });

  const details = phone => ({ pickup_address: '12 Nguyen Hue', dropoff_address: '20 Le Loi', recipient_name: 'Người nhận',
    recipient_phone: phone, package_description: 'Logistics acceptance', pickup_lat: 10.77, pickup_lng: 106.7,
    dropoff_lat: 10.78, dropoff_lng: 106.71, weight_kg: 1, cod_amount: 0, service_type: 'standard', payment_method: 'sender_cash' });
  const createOrder = async (owner, phone) => {
    const quote = await as(owner, 'delivery_cloud_quote', [details(phone)]);
    return as(owner, 'delivery_cloud_create', [details(phone), randomUUID(), quote.pricing_version, quote.shipping_fee]);
  };

  await check('L3 recipient trust counts only the caller shipments and keeps risk flags private', async () => {
    const phone = '0388000111';
    const delivered = await createOrder(sender, phone), returned = await createOrder(sender, phone);
    await createOrder(sender, phone).then(cancelled => db.query("update delivery_cloud_orders set status='cancelled' where id=$1", [cancelled.id]));
    await db.query("update delivery_cloud_orders set status='delivered' where id=$1", [delivered.id]);
    await db.query("update delivery_cloud_orders set status='returned' where id=$1", [returned.id]);
    await code(logistics(sender, 'recipient_trust', { phone: '123' }), 'PT400');
    const own = await logistics(sender, 'recipient_trust', { phone });
    assert.deepEqual([own.delivered, own.failed_or_returned, own.score, own.tier, own.flagged], [1, 1, 70, 'confirm', false]);
    const other = await logistics(stranger, 'recipient_trust', { phone });
    assert.deepEqual([other.delivered, other.failed_or_returned, other.score, other.tier], [0, 0, 88, 'trusted']);
    const flagged = await logistics(sender, 'recipient_flag', { phone, flagged: true });
    assert.deepEqual([flagged.flagged, flagged.score, flagged.tier], [true, 25, 'high_risk']);
    assert.equal((await logistics(stranger, 'recipient_trust', { phone })).flagged, false);
    assert.equal((await logistics(sender, 'recipient_flag', { phone, flagged: false })).score, 70);
  });

  await check('L4 delivery instruction is owner-only, versioned, recorded in history and closed after completion', async () => {
    const order = await createOrder(sender, '0912345678');
    await code(logistics(stranger, 'instruction_set', { order_id: order.id, version: order.version, instruction: 'Gọi trước 5 phút' }), 'PT404');
    await code(logistics(sender, 'instruction_set', { order_id: order.id, version: order.version + 1, instruction: 'Gọi trước 5 phút' }), 'PT409');
    await code(logistics(sender, 'instruction_set', { order_id: order.id, version: order.version, instruction: 'x'.repeat(201) }), 'PT400');
    const updated = await logistics(sender, 'instruction_set', { order_id: order.id, version: order.version, instruction: ' Gọi trước 5 phút ' });
    assert.equal(updated.delivery_instruction, 'Gọi trước 5 phút');
    assert.equal(updated.version, order.version + 1);
    assert.equal((await logistics(sender, 'instruction_set', { order_id: order.id, version: updated.version, instruction: 'Gọi trước 5 phút' })).version, updated.version);
    const history = await as(sender, 'delivery_cloud_history_read', [order.id]);
    assert.ok(JSON.stringify(history).includes('instruction'));
    const listed = (await as(sender, 'delivery_cloud_list', [false, null, null])).orders.find(o => o.id === order.id);
    assert.equal(listed.delivery_instruction, 'Gọi trước 5 phút');
    await db.query("update delivery_cloud_orders set status='delivered' where id=$1", [order.id]);
    await code(logistics(sender, 'instruction_set', { order_id: order.id, version: updated.version, instruction: '' }), 'PT409');
  });

  await check('L5 statistics are scoped to the caller and derived from real transition history', async () => {
    const courier = randomUUID();
    await db.query('insert into auth.users values($1)', [courier]);
    await as(courier, 'delivery_cloud_profile', [{ full_name: 'Logistics courier', phone: '0901234567', requested_role: 'customer' }]);
    await as(courier, 'delivery_cloud_membership', ['driver', 'request']);
    await as(operator, 'delivery_cloud_membership', ['driver', 'approve', courier, 1, '']);
    let order = await createOrder(sender, '0912345678');
    for (const action of ['claim', 'arrive', 'pickup', 'deliver']) {
      order = await as(courier, 'delivery_cloud_transition', [order.id, action, order.version, randomUUID(), '']);
    }
    assert.equal(order.status, 'delivered');
    const own = await logistics(sender, 'stats');
    const expected = (await db.query("select count(*)::int n from delivery_cloud_orders where (owner_id=$1 or merchant_id=$1 or driver_id=$1) and created_at>=now()-interval '30 days'", [sender])).rows[0].n;
    assert.equal(own.scope, 'account');
    assert.equal(own.summary.total, expected);
    assert.ok(own.summary.delivered >= 1);
    assert.equal(typeof own.summary.avg_delivery_minutes, 'number');
    assert.equal(typeof own.summary.avg_transit_minutes, 'number');
    assert.equal(own.drivers, null);
    assert.ok(own.summary.by_service.some(s => s.service_type === 'standard'));
    const courierStats = await logistics(courier, 'stats');
    assert.equal(courierStats.summary.total, 1);
    const network = await logistics(operator, 'stats');
    assert.equal(network.scope, 'network');
    assert.ok(network.summary.total >= own.summary.total);
    assert.ok(network.drivers.approved >= 3);
    assert.ok(network.pickups.assigned >= 1);
    const eta = await logistics(stranger, 'service_eta');
    const standard = eta.services.find(s => s.service_type === 'standard');
    assert.ok(standard.samples >= 1);
    assert.equal(typeof standard.avg_delivery_minutes, 'number');
    assert.equal(JSON.stringify(eta).includes(sender), false);
  });
}
