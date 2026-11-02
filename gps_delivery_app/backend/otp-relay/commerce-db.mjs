import pg from 'pg';
import { IntegrationError } from './provider-http.mjs';
import { databaseConnectionOptions } from './database-connection.mjs';

export function createCommerceDatabase(env = process.env) {
  let pool, source;
  function connection() {
    if (!env.DATABASE_URL?.trim()) throw new IntegrationError(503, 'Cần DATABASE_URL backend và migration 20261029_payments_ghn.sql.');
    const revision = JSON.stringify([env.DATABASE_URL, env.DATABASE_CA_CERT]);
    if (source === revision && pool) return pool;
    const options = databaseConnectionOptions(env);
    if (pool) pool.end().catch(() => {});
    pool = new pg.Pool({ ...options,
      max: 4, connectionTimeoutMillis: 15000, query_timeout: 10000, idleTimeoutMillis: 10000, keepAlive: true });
    pool.on('error', () => {});
    source = revision;
    return pool;
  }
  function failure(error) {
    if (error instanceof IntegrationError) return error;
    if (/^PT(400|401|403|404|409)$/.test(error.code)) return new IntegrationError(Number(error.code.slice(2)),String(error.message).slice(0,500));
    return new IntegrationError(503, ['42P01', '42703', '42883'].includes(error.code)
      ? 'Cần chạy migration 20261029_payments_ghn.sql trên Supabase.'
      : 'Không kết nối được database giao dịch. Kiểm tra cấu hình backend.');
  }
  return {
    async query(sql, params) {
      try { return await connection().query(sql, params); } catch (error) { throw failure(error); }
    },
    async transaction(operation) {
      let client;
      try {
        client = await connection().connect();
        await client.query('begin');
        const result = await operation(client);
        await client.query('commit');
        return result;
      } catch (error) {
        if (client) await client.query('rollback').catch(() => {});
        throw failure(error);
      } finally { client?.release(); }
    },
    async close() { if (pool) await pool.end(); pool = null; },
  };
}

export function cloudActor(req) {
  const identity = req.deliveryIdentity;
  if (!identity || identity.local || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(identity.id)) {
    throw new IntegrationError(401, 'Cần đăng nhập tài khoản Supabase.');
  }
  return identity;
}

export function orderId(value) {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value)) {
    throw new IntegrationError(400, 'Mã đơn cloud không hợp lệ.');
  }
  return value;
}

export async function ownedOrder(db, req, id, { lock = false, operator = false } = {}) {
  const identity = cloudActor(req);
  if (operator && identity.role !== 'operator') throw new IntegrationError(403, 'Cần quyền operator cloud.');
  const found = await db.query(`select o.*,a.full_name as sender_name,a.phone as sender_phone
    from public.delivery_cloud_orders o join public.delivery_cloud_accounts a on a.user_id=coalesce(o.merchant_id,o.owner_id)
    where o.id=$1 and ($3 or (o.owner_id=$2 or o.merchant_id=$2 or o.driver_id=$2))
    ${lock ? 'for update of o' : ''}`,
  [orderId(id), identity.id, identity.role === 'operator']);
  const row = found.rows[0];
  if (!row) throw new IntegrationError(404, 'Không tìm thấy đơn cloud.');
  if (identity.role !== 'operator') {
    const active = await db.query('select user_id from public.delivery_cloud_accounts where user_id=$1 and not blocked', [identity.id]);
    if (!active.rows.length) throw new IntegrationError(403, 'Tài khoản cloud đang bị khóa hoặc thiếu hồ sơ.');
  }
  return row;
}

export async function ownedPurchase(db, req, id, { lock = false, operator = false } = {}) {
  const identity = cloudActor(req);
  if (operator && identity.role !== 'operator') throw new IntegrationError(403, 'Cần quyền operator cloud.');
  const found = await db.query(`select p.*
    from public.delivery_market_purchases p
    where p.id=$1 and ($3 or p.owner_id=$2 or exists(
      select 1 from public.delivery_market_shop_orders so where so.purchase_id=p.id and so.merchant_id=$2
    ))
    ${lock ? 'for update of p' : ''}`,
  [orderId(id), identity.id, identity.role === 'operator']);
  const row = found.rows[0];
  if (!row) throw new IntegrationError(404, 'Không tìm thấy giao dịch mua hàng.');
  if (identity.role !== 'operator') {
    const active = await db.query('select user_id from public.delivery_cloud_accounts where user_id=$1 and not blocked', [identity.id]);
    if (!active.rows.length) throw new IntegrationError(403, 'Tài khoản cloud đang bị khóa hoặc thiếu hồ sơ.');
  }
  return row;
}
