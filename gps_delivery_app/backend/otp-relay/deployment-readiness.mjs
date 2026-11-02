import crypto from 'node:crypto';
import { configValue, INTEGRATION_DEFINITIONS, providerConfigured } from './integration-config.mjs';
import { createCommerceDatabase } from './commerce-db.mjs';

export const COMMERCE_MIGRATION = '20261109_admin_account_management';
const revisionKey = crypto.randomBytes(32);
export const databaseRevision = env => crypto.createHmac('sha256', revisionKey)
  .update(JSON.stringify([configValue('DATABASE_URL', env), configValue('DATABASE_CA_CERT', env)])).digest('hex');
const migrations = ['20261027_delivery_integrations.sql', '20261028_cloud_orders.sql', '20261029_payments_ghn.sql', '20261029_cloud_addresses.sql', '20261030_marketplace.sql', '20261031_market_operations.sql', '20261101_partner_memberships.sql', '20261102_local_address_import.sql', '20261103_catalog_stock_versions.sql', '20261104_market_media.sql', '20261105_market_browse.sql', '20261106_catalog_configuration.sql', '20261107_cloud_commercial_suite.sql', '20261108_cloud_logistics.sql', '20261109_admin_account_management.sql'];

// Catalog-only queries: never create users, orders, provider requests or payments.
export const DEPLOYMENT_SCHEMA_SQL = `with commerce_tables as (
  select to_regclass('public.' || name) as oid from unnest(array[
    'delivery_payment_transactions','delivery_payment_receipts',
    'delivery_ghn_quotes','delivery_ghn_shipments','delivery_ghn_events']) as name
), marketplace_tables as (
  select to_regclass('public.delivery_market_' || name) as oid from unnest(array[
    'shops','products','stock','carts','cart_items','quotes','purchases','shop_orders','events','messages','notifications']) as name
), required_columns as (
  select column_name from information_schema.columns where table_schema='public'
    and table_name='delivery_cloud_orders' and column_name in ('fulfillment_provider','carrier_code','carrier_status')
)
select
  to_regprocedure('public.delivery_market_attachment_reserve(uuid,text,text,integer)') is not null
    and to_regprocedure('public.delivery_cloud_public_lookup(text,text)') is not null
    and to_regprocedure('public.delivery_cloud_order_otp(uuid)') is not null
    and to_regprocedure('public.delivery_cloud_share_manage(uuid,text,uuid)') is not null
    and to_regprocedure('public.delivery_market_record_prepaid_capture(uuid,text)') is not null
    and exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='delivery_payment_transactions' and column_name='purchase_id')
    and (select count(*)=17 and bool_and(c.relrowsecurity) from pg_class c where c.oid in (
      select to_regclass('public.'||n) from unnest(array[
        'delivery_market_shop_staff','delivery_market_variants','delivery_market_shipments',
        'delivery_cloud_order_secrets','delivery_cloud_shares','delivery_market_attachments',
        'delivery_partner_reviews','delivery_market_review_reports','delivery_market_shop_follows',
        'delivery_market_vouchers','delivery_market_voucher_usages','delivery_market_flash_sales',
        'delivery_market_flash_claims','delivery_market_coin_wallets','delivery_market_coin_ledger',
        'delivery_backend_config','delivery_backend_config_audit']) n))
    and not exists(select 1 from unnest(array[
        'delivery_market_shop_staff','delivery_market_variants','delivery_market_shipments',
        'delivery_cloud_order_secrets','delivery_cloud_shares','delivery_market_attachments',
        'delivery_partner_reviews','delivery_market_review_reports','delivery_market_shop_follows',
        'delivery_market_vouchers','delivery_market_voucher_usages','delivery_market_flash_sales',
        'delivery_market_flash_claims','delivery_market_coin_wallets','delivery_market_coin_ledger',
        'delivery_backend_config','delivery_backend_config_audit']) n
      cross join (select oid from pg_roles where rolname in ('anon','authenticated')) r
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
      where coalesce(has_table_privilege(r.oid,to_regclass('public.'||n),p.privilege),false))
    and not exists(select 1 from (select oid from pg_roles where rolname in ('anon','authenticated')) r
      where has_function_privilege(r.oid,to_regprocedure('public.delivery_market_record_prepaid_capture(uuid,text)'),'EXECUTE'))
    and exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
      and policyname='delivery_private_evidence_insert' and cmd='INSERT')
    and exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
      and policyname='delivery_private_evidence_select' and cmd='SELECT') as commercial_suite_schema,
  to_regprocedure('public.delivery_cloud_logistics(text,jsonb)') is not null
    and exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='delivery_cloud_orders' and column_name='delivery_instruction')
    and (select count(*)=2 and bool_and(c.relrowsecurity) from pg_class c where c.oid in (
      to_regclass('public.delivery_cloud_pickups'),to_regclass('public.delivery_cloud_recipient_flags')))
    and not exists(select 1 from unnest(array['delivery_cloud_pickups','delivery_cloud_recipient_flags']) n
      cross join (select oid from pg_roles where rolname in ('anon','authenticated')) r
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
      where coalesce(has_table_privilege(r.oid,to_regclass('public.'||n),p.privilege),false)) as logistics_schema,
  to_regprocedure('public.delivery_cloud_admin_accounts(text,jsonb)') is not null
    and to_regprocedure('public.delivery_cloud_admin_account_row(uuid)') is not null
    and to_regprocedure('public.delivery_cloud_auth_providers(uuid,jsonb)') is not null
    and not exists(select 1 from (select oid from pg_roles where rolname in ('anon','authenticated')) r
      where has_function_privilege(r.oid,to_regprocedure('public.delivery_cloud_admin_account_row(uuid)'),'EXECUTE')
        or has_function_privilege(r.oid,to_regprocedure('public.delivery_cloud_auth_providers(uuid,jsonb)'),'EXECUTE'))
    and not has_function_privilege((select oid from pg_roles where rolname='anon'),
      to_regprocedure('public.delivery_cloud_admin_accounts(text,jsonb)'),'EXECUTE') as admin_accounts_schema,
  to_regprocedure('public.delivery_market_selection(uuid,jsonb)') is not null
    and to_regprocedure('public.delivery_market_configured_cart()') is not null
    and (select count(*)=4 from information_schema.columns where table_schema='public'
      and table_name='delivery_market_products' and column_name in ('option_groups','sale_schedule','preparation_minutes','images'))
    and exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='delivery_market_cart_items' and column_name='line_id')
    and exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='delivery_market_returns' and column_name='line_id')
    and not exists(select 1 from (select oid from pg_roles where rolname in ('anon','authenticated')) r
      where has_function_privilege(r.oid,to_regprocedure('public.delivery_market_selection(uuid,jsonb)'),'EXECUTE')
        or has_function_privilege(r.oid,to_regprocedure('public.delivery_market_configured_cart()'),'EXECUTE')) as configuration_schema,
  to_regprocedure('public.delivery_market_browse(jsonb)') is not null as browse_schema,
  to_regprocedure('public.delivery_market_media_reserve(uuid,text,integer)') is not null
    and exists(select 1 from pg_class where oid=to_regclass('public.delivery_market_media') and relrowsecurity)
    and not exists(select 1 from (select oid from pg_roles where rolname in ('anon','authenticated')) r
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
      where coalesce(has_table_privilege(r.oid,to_regclass('public.delivery_market_media'),p.privilege),false))
    and exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
      and policyname='delivery_market_media_insert' and cmd='INSERT') as market_media_schema,
  exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='delivery_market_products' and column_name='terms_version')
    and exists(select 1 from pg_trigger where tgrelid=to_regclass('public.delivery_market_products')
      and tgname='delivery_market_product_terms' and tgenabled in ('O','A') and not tgisinternal) as stock_terms_schema,
  to_regprocedure('public.delivery_cloud_import(text,jsonb)') is not null
    and exists(select 1 from pg_class where oid=to_regclass('public.delivery_cloud_imports') and relrowsecurity)
    and not exists(select 1 from (select oid from pg_roles where rolname in ('anon','authenticated')) r
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
      where coalesce(has_table_privilege(r.oid,to_regclass('public.delivery_cloud_imports'),p.privilege),false)) as import_schema,
  to_regprocedure('public.delivery_cloud_membership(text,text,uuid,integer,text)') is not null
    and exists(select 1 from pg_class where oid=to_regclass('public.delivery_cloud_memberships') and relrowsecurity)
    and not exists(select 1 from (select oid from pg_roles where rolname in ('anon','authenticated')) r
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
      where coalesce(has_table_privilege(r.oid,to_regclass('public.delivery_cloud_memberships'),p.privilege),false)) as membership_schema,
  to_regprocedure('public.delivery_market_operations(text,jsonb)') is not null
    and to_regprocedure('public.delivery_market_run_jobs(integer)') is not null
    and to_regprocedure('public.delivery_market_public_tracking(text)') is not null
    and (select count(*)=9 and bool_and(c.relrowsecurity) from pg_class c where c.oid in (
      select to_regclass('public.delivery_market_'||n) from unnest(array['jobs','favorites','reviews','returns','finance','journals','ledger','shares','commands']) n))
    and not exists(select 1 from unnest(array['jobs','favorites','reviews','returns','finance','journals','ledger','shares','commands']) n
      cross join (select oid from pg_roles where rolname in ('anon','authenticated')) r
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
      where coalesce(has_table_privilege(r.oid,to_regclass('public.delivery_market_'||n),p.privilege),false)) as operations_schema,
  to_regprocedure('public.delivery_marketplace(text,jsonb)') is not null
    and (select count(*)=11 and coalesce(bool_and(c.relrowsecurity),false) from marketplace_tables t join pg_class c on c.oid=t.oid)
    and not exists(select 1 from marketplace_tables t cross join (select oid from pg_roles where rolname in ('anon','authenticated')) r
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
      where has_table_privilege(r.oid,t.oid,p.privilege)) as marketplace_schema,
  to_regprocedure('public.delivery_cloud_addresses_manage(uuid,jsonb,boolean,integer)') is not null
    and exists(select 1 from pg_class where oid=to_regclass('public.delivery_cloud_addresses') and relrowsecurity)
    as address_schema,
  to_regprocedure('public.delivery_cloud_create(jsonb,uuid,integer,integer)') is not null
    and to_regprocedure('public.delivery_cloud_transition(uuid,text,integer,uuid,text)') is not null
    and to_regclass('public.delivery_cloud_orders') is not null as cloud_schema,
  (select bool_and(oid is not null) from commerce_tables)
    and (select count(*)=3 from required_columns) as commerce_schema,
  exists(select 1 from pg_trigger where tgrelid=to_regclass('public.delivery_cloud_orders')
    and tgname='delivery_commerce_guard' and tgenabled in ('O','A') and not tgisinternal) as commerce_guard,
  (select coalesce(bool_and(coalesce(has_table_privilege(current_user,t.oid,p.privilege),false)),false)
    from commerce_tables t cross join unnest(array['SELECT','INSERT','UPDATE']) p(privilege))
    and coalesce(has_sequence_privilege(current_user,to_regclass('public.delivery_payment_transactions_provider_order_code_seq'),'USAGE'),false)
    as commerce_permissions,
  (select count(*)=5 and coalesce(bool_and(c.relrowsecurity),false) from commerce_tables t join pg_class c on c.oid=t.oid)
    and not exists(select 1 from commerce_tables t cross join (select oid from pg_roles where rolname in ('anon','authenticated')) r
      cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
      where has_table_privilege(r.oid,t.oid,p.privilege)) as commerce_privacy`;

export function publicBackendUrl(value) {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '');
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
        !host.includes('.') || host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local') ||
        /^(?:127\.|10\.|0\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(host) ||
        host.includes(':')) return null;
    return new URL(url.href.endsWith('/') ? url.href : `${url.href}/`);
  } catch { return null; }
}

export function createDeploymentReadiness({ env = process.env, database = createCommerceDatabase(env), now = () => new Date() } = {}) {
  let pending;
  async function inspect() {
    const revision = databaseRevision(env);
    const checks = [];
    const add = (id, label, status, detail, extra = {}) => checks.push({id,label,status,detail,...extra});
    const databaseConfigured = Boolean(configValue('DATABASE_URL', env));
    let schema;
    if (!databaseConfigured) {
      add('database','PostgreSQL backend','missing','Lưu kết nối PostgreSQL tại Admin → Triển khai backend của máy chủ đang kết nối.');
    } else {
      try {
        schema = (await database.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
        if (databaseRevision(env) !== revision) throw new Error('Database configuration changed');
        if (!schema || !['cloud_schema','commerce_schema','commerce_guard','commerce_permissions','commerce_privacy'].every(key => typeof schema[key] === 'boolean')) throw new Error('Invalid catalog response');
        add('database','PostgreSQL backend','ok','Đã kết nối và đọc catalog PostgreSQL.');
      } catch {
        schema = undefined;
        add('database','PostgreSQL backend','error','Không kiểm tra được database. Kiểm tra kết nối, TLS và quyền truy cập.');
      }
    }
    add('cloud_schema','Schema đơn hàng cloud',schema ? schema.cloud_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.cloud_schema ? 'Đã tìm thấy các hàm tạo đơn và chuyển trạng thái.' : 'Cần kiểm tra database và chạy migration cloud.');
    add('membership_schema','Tư cách cửa hàng và tài xế',schema ? schema.membership_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.membership_schema ? 'Đã có quyền đối tác độc lập và bảng riêng tư.' : 'Cần migration 20261101_partner_memberships.sql.');
    add('import_schema','Nhập địa chỉ có xác nhận',schema ? schema.import_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.import_schema ? 'Đã có xem trước, kiểm tra trùng và nhập địa chỉ nguyên tử.' : 'Cần migration 20261102_local_address_import.sql.');
    add('stock_terms_schema','Báo giá và cạnh tranh tồn kho',schema ? schema.stock_terms_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.stock_terms_schema ? 'Giá và tồn kho có phiên bản độc lập.' : 'Cần migration 20261103_catalog_stock_versions.sql.');
    add('market_media_schema','Ảnh sản phẩm',schema ? schema.market_media_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.market_media_schema ? 'Đã có vùng lưu ảnh công khai và quyền ghi theo cửa hàng.' : 'Cần migration 20261104_market_media.sql.');
    add('browse_schema','Danh mục, bộ lọc và gian hàng',schema ? schema.browse_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.browse_schema ? 'Đã có tìm kiếm, lọc giá/tồn và phân trang tại server.' : 'Cần migration 20261105_market_browse.sql.');
    add('configuration_schema','Lựa chọn, lịch bán và giỏ hàng',schema ? schema.configuration_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.configuration_schema ? 'Đã có giá lựa chọn tại server, giỏ theo từng dòng và giới hạn hoàn hàng.' : 'Cần migration 20261106_catalog_configuration.sql.');
    add('commercial_suite_schema','Thương mại cloud toàn diện (P1–P6)',schema ? schema.commercial_suite_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.commercial_suite_schema ? 'Đã có biến thể SKU, nhân sự shop, trả trước multi-shop, bằng chứng riêng tư, voucher, flash sale và xu.' : 'Cần migration 20261107_cloud_commercial_suite.sql.');
    add('logistics_schema','Thu gom, tín nhiệm người nhận và thống kê giao hàng',schema ? schema.logistics_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.logistics_schema ? 'Đã có phiếu thu gom, chỉ dẫn giao hàng, cờ rủi ro người nhận riêng tư và thống kê từ đơn cloud.' : 'Cần migration 20261108_cloud_logistics.sql.');
    add('admin_accounts_schema','Quản trị danh tính và phân quyền tài khoản',schema ? schema.admin_accounts_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.admin_accounts_schema ? 'Đã có quản trị danh tính Auth, cấp quyền đối tác trực tiếp, bảo vệ tự khóa Operator và nhật ký kiểm toán.' : 'Cần migration 20261109_admin_account_management.sql.');
    const commerceSchema = schema?.commerce_schema && schema?.commerce_guard;
    add('address_schema','Sổ địa chỉ tài khoản',schema ? schema.address_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.address_schema ? 'Đã có RPC và RLS sổ địa chỉ.' : 'Cần migration 20261029_cloud_addresses.sql.');
    add('marketplace_schema','Catalog và đặt mua nhiều cửa hàng',schema ? schema.marketplace_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.marketplace_schema ? 'Đã tìm thấy RPC và quyền riêng tư của 11 bảng mua hàng. Chưa nghiệm thu giao dịch thật.' : 'Cần migration 20261030_marketplace.sql.');
    add('operations_schema','Đối soát, hậu mãi và theo dõi',schema ? schema.operations_schema ? 'ok' : 'missing' : 'unchecked',
      schema?.operations_schema ? 'Đã có nghiệp vụ và quyền riêng tư của 9 bảng vận hành; chưa nghiệm thu giao dịch thật.' : 'Cần migration 20261031_market_operations.sql.');
    add('market_jobs','Xử lý đơn mua quá hạn',env.MARKET_JOBS_ENABLED === 'true' ? 'ok' : 'disabled',
      env.MARKET_JOBS_ENABLED === 'true' ? 'Đã bật worker; xem số đơn quá hạn và lỗi tại Đối soát và hậu mãi.' : 'Bật sau khi cập nhật schema và kiểm tra chính sách hết hạn đơn.');
    add('commerce_schema','Schema payOS / GHN',schema ? commerceSchema ? 'ok' : 'missing' : 'unchecked',
      commerceSchema ? 'Đã tìm thấy bảng giao dịch, cột vận chuyển và trigger bảo vệ đơn.' : 'Cần migration thanh toán/GHN, gồm trigger bảo vệ điều phối.');
    add('database_permissions','Quyền ghi giao dịch',schema ? schema.commerce_permissions ? 'ok' : 'missing' : 'unchecked',
      schema?.commerce_permissions ? 'Kết nối backend có quyền ghi các bảng giao dịch.' : 'Backend cần quyền đọc/ghi bảng giao dịch và sử dụng sequence.');
    add('commerce_privacy','Bảo vệ dữ liệu giao dịch',schema ? schema.commerce_privacy ? 'ok' : 'missing' : 'unchecked',
      schema?.commerce_privacy ? 'RLS đã bật; anon/authenticated không được đọc hoặc ghi trực tiếp.' : 'Cần áp dụng quyền riêng tư của migration commerce.');
    for (const provider of ['supabase','payos','ghn']) {
      const definition = INTEGRATION_DEFINITIONS[provider];
      const required = [...definition.required, ...(provider === 'ghn' ? ['GHN_WEBHOOK_SECRET'] : [])];
      const missingFields = required.filter(key => !configValue(key,env));
      const enabled = providerConfigured(provider,env);
      add(provider,definition.label,missingFields.length ? 'missing' : enabled ? 'ok' : 'disabled',
        missingFields.length ? `Thiếu: ${missingFields.join(', ')}` : enabled ? 'Đủ trường bắt buộc và đang bật; chưa xác minh giao dịch thật.' : 'Đã có cấu hình nhưng đang tắt.',
        {missingFields});
    }
    const base = publicBackendUrl(configValue('PUBLIC_BASE_URL',env));
    add('public_https','Webhook HTTPS công khai',base ? 'ok' : 'missing',
      base ? 'URL HTTPS hợp lệ về định dạng; chưa xác minh truy cập từ ngoài hoặc đăng ký callback.' : 'Đặt PUBLIC_BASE_URL thành URL HTTPS công khai; localhost không nhận được callback cloud.');
    const callbacks = [
      {provider:'payos',label:'payOS',path:'delivery/payments/webhook',authentication:'Chữ ký checksum payOS'},
      {provider:'ghn',label:'GHN',path:'delivery/webhooks/ghn',authentication:'Header X-GHN-Webhook-Secret'},
    ].map(({path,...callback}) => ({...callback,url:base ? new URL(path,base).href : null,path:`/${path}`,registrationVerified:false}));
    const common = ['database','cloud_schema','commerce_schema','database_permissions','commerce_privacy','supabase','public_https'];
    return {checkedAt:now().toISOString(),checks,callbacks,migrations,migrationVersion:COMMERCE_MIGRATION,
      databaseConfigured,databaseRevision:revision,liveTransactionsVerified:false,
      features:Object.fromEntries(['payos','ghn'].map(provider => [provider,{
        prerequisitesMet:[...common,provider].every(id=>checks.find(check=>check.id===id)?.status==='ok'),
        liveVerified:false,
      }]))};
  }
  return async () => {
    if (pending) return pending;
    pending = inspect();
    try { return await pending; } finally { pending = undefined; }
  };
}
