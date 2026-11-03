import express from 'express';
import { fetchWithRetry, IntegrationError } from './provider-http.mjs';
import { providerConfigured } from './integration-config.mjs';
import { createCustomerAiChatHandler } from './ai-assistant.mjs';
import {
  createMarketMedia,
  createPrivateAttachmentUpload,
  createPrivateAttachmentSign,
  createPodUpload,
  createPodSign,
} from './market-media.mjs';

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function uuid(value) {
  if (typeof value !== 'string' || !uuidPattern.test(value)) throw new IntegrationError(400, 'Mã định danh không hợp lệ.');
  return value;
}
function integer(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 100_000_000) throw new IntegrationError(400, 'Giá trị số không hợp lệ.');
  return value;
}
export const CLOUD_WORKFLOW_VERSION = 2;
const migrationMessage = 'Cloud cần cập nhật: chạy lại database/migrations/20261028_cloud_orders.sql trên Supabase SQL Editor.';

function attachShareUrl(result, env) {
  if (/^[a-f0-9]{64}$/.test(result?.token) && env.PUBLIC_APP_URL) {
    try {
      const url = new URL(env.PUBLIC_APP_URL);
      if (url.protocol === 'https:' && !url.username && !url.password) {
        url.hash = `/share?token=${result.token}`;
        result.share_url = url.href;
      }
    } catch {}
  }
  return result;
}

// RPCs execute as the authenticated user. No service-role key or caller-selected RPC.
export function createCloudOrders({ env = process.env, authenticate, fetcher = fetch } = {}) {
  const router = express.Router();
  router.use(authenticate);
  router.use((req, res, next) => {
    res.set('Cache-Control', 'no-store');
    if (!req.deliveryIdentity || req.deliveryIdentity.local) return res.status(401).json({ error: 'Cần đăng nhập tài khoản Supabase để dùng đơn hàng cloud.' });
    if (!providerConfigured('supabase', env)) return res.status(503).json({ error: 'Dịch vụ Supabase đang tắt hoặc chưa cấu hình.' });
    next();
  });
  const rpc = async (req, name, body) => {
    let response;
    try {
      response = await fetchWithRetry(new URL(`/rest/v1/rpc/${name}`, env.SUPABASE_URL), {
        method: 'POST',
        headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${req.deliveryIdentity.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }, fetcher);
    } catch { throw new IntegrationError(502, 'Không kết nối được cơ sở dữ liệu cloud.'); }
    const chunks = []; let size = 0;
    for await (const chunk of response.body ?? []) {
      size += chunk.length;
      if (size > 1_000_000) throw new IntegrationError(502, 'Phản hồi cloud quá lớn.');
      chunks.push(chunk);
    }
    let data;
    try { data = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch { throw new IntegrationError(502, 'Phản hồi cloud không hợp lệ.'); }
    if (!response.ok) {
      if (['PGRST202', '42P01', '42883'].includes(data.code)) throw new IntegrationError(503,
        ['delivery_marketplace','delivery_market_operations','delivery_market_browse','delivery_market_media_reserve','delivery_market_attachment_reserve','delivery_cloud_order_otp','delivery_cloud_share_manage','delivery_cloud_logistics','delivery_cloud_admin_accounts','delivery_cloud_promo_events','delivery_cloud_notifications'].includes(name)
          ? 'Dữ liệu mua hàng cần được cập nhật trong trang quản trị.'
          : name === 'delivery_cloud_addresses_manage'
          ? 'Chưa cài sổ địa chỉ cloud. Chạy migration 20261029_cloud_addresses.sql trên Supabase.'
          : 'Chưa cài schema đơn hàng cloud. Chạy migration 20261028_cloud_orders.sql trên Supabase.');
      if (/^PT(400|401|403|404|409)$/.test(data.code)) throw new IntegrationError(Number(data.code.slice(2)), String(data.message).slice(0, 500));
      if (response.status === 401 || response.status === 403) throw new IntegrationError(response.status, 'Phiên cloud hết hạn hoặc chưa đủ quyền.');
      if (['22P02','22003','23514','23502','22007','22008'].includes(data.code)) throw new IntegrationError(400, 'Dữ liệu yêu cầu không hợp lệ.');
      if (data.code === '23505') throw new IntegrationError(409, 'Mã dữ liệu đã tồn tại. Hãy tải lại và kiểm tra.');
      throw new IntegrationError(502, 'Không xử lý được yêu cầu cloud.');
    }
    return data;
  };
  const requireWorkflow = async req => {
    const profile = await rpc(req, 'delivery_cloud_profile', {});
    if (Number(profile.schema_version || 1) < CLOUD_WORKFLOW_VERSION) throw new IntegrationError(503, migrationMessage);
  };
  const route = fn => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);
  const media = createMarketMedia({ env, fetcher, rpc });
  const uploadAttachment = createPrivateAttachmentUpload({ env, fetcher, rpc });
  const signAttachment = createPrivateAttachmentSign({ env, fetcher });
  const uploadPod = createPodUpload({ env, fetcher });
  const signPod = createPodSign({ env, fetcher });
  router.post('/media', express.json({ limit: '7mb' }), route(async (req, res) => res.json(await media(req))));
  router.post('/attachments', express.json({ limit: '7mb' }), route(async (req, res) => res.json(await uploadAttachment(req))));
  router.post('/attachments/sign', route(async (req, res) => res.json(await signAttachment(req))));
  router.post('/pod', express.json({ limit: '7mb' }), route(async (req, res) => res.json(await uploadPod(req))));
  router.post('/pod/sign', route(async (req, res) => res.json(await signPod(req))));

  const marketActions = new Set([
    'catalog','workspace','shop_save','staff_save','shop_moderate','product_save','variant_save',
    'voucher_save','flash_sale_save','cart','cart_set','quote','checkout','orders',
    'order_action','order_shipment_split','messages','message_send','notifications','notification_read',
  ]);
  const operationActions = new Set([
    'favorites','favorite_set','product_details','shop_details','shop_follow_set','vouchers','coins',
    'admin_analytics','operations','review_moderate','finance_request','finance_action','order_services',
    'tracking_share','tracking_revoke','reorder','review_save','partner_review_save','review_reply',
    'review_report','return_request','return_action','job_retry','jobs_run',
  ]);
  router.post('/marketplace/:action', route(async (req, res) => {
    if ((!marketActions.has(req.params.action) && !operationActions.has(req.params.action)) || !req.body || Array.isArray(req.body) ||
        typeof req.body !== 'object' || Buffer.byteLength(JSON.stringify(req.body)) > 16000) {
      throw new IntegrationError(400, 'Yêu cầu mua hàng không hợp lệ.');
    }
    const result = req.params.action === 'catalog'
      ? await rpc(req, 'delivery_market_browse', { p_payload: req.body })
      : await rpc(req, operationActions.has(req.params.action) ? 'delivery_market_operations' : 'delivery_marketplace', { p_action: req.params.action, p_payload: req.body });
    if (req.params.action === 'tracking_share') attachShareUrl(result, env);
    res.json(result);
  }));
  const logisticsActions = new Set([
    'pickup_list','pickup_create','pickup_assign','recipient_trust','recipient_flag','instruction_set','stats','service_eta',
  ]);
  router.post('/logistics/:action', route(async (req, res) => {
    if (!logisticsActions.has(req.params.action) || !req.body || Array.isArray(req.body) ||
        typeof req.body !== 'object' || Buffer.byteLength(JSON.stringify(req.body)) > 4000) {
      throw new IntegrationError(400, 'Yêu cầu vận hành không hợp lệ.');
    }
    res.json(await rpc(req, 'delivery_cloud_logistics', { p_action: req.params.action, p_payload: req.body }));
  }));
  const adminAccountActions = new Set([
    'list','detail','update_profile','set_blocked','set_operator',
  ]);
  router.post('/admin-accounts/:action', route(async (req, res) => {
    if (!adminAccountActions.has(req.params.action) || !req.body || Array.isArray(req.body) ||
        typeof req.body !== 'object' || Buffer.byteLength(JSON.stringify(req.body)) > 4000) {
      throw new IntegrationError(400, 'Yêu cầu quản trị tài khoản không hợp lệ.');
    }
    res.json(await rpc(req, 'delivery_cloud_admin_accounts', { p_action: req.params.action, p_payload: req.body }));
  }));
  const promoEventActions = new Set([
    'status','checkin','claim_mission','exchange_coins','spin_wheel','open_blind_box','reset_blind_boxes','admin_settings_save',
  ]);
  router.post('/promo-events/:action', route(async (req, res) => {
    if (!promoEventActions.has(req.params.action) || !req.body || Array.isArray(req.body) ||
        typeof req.body !== 'object' || Buffer.byteLength(JSON.stringify(req.body)) > 4000) {
      throw new IntegrationError(400, 'Yêu cầu sự kiện khuyến mãi không hợp lệ.');
    }
    res.json(await rpc(req, 'delivery_cloud_promo_events', { p_action: req.params.action, p_payload: req.body }));
  }));
  const notificationActions = new Set([
    'list','unread_count','mark_read','mark_all_read','save_preferences',
  ]);
  router.post('/notifications/:action', route(async (req, res) => {
    if (!notificationActions.has(req.params.action) || !req.body || Array.isArray(req.body) ||
        typeof req.body !== 'object' || Buffer.byteLength(JSON.stringify(req.body)) > 4000) {
      throw new IntegrationError(400, 'Yêu cầu thông báo không hợp lệ.');
    }
    res.json(await rpc(req, 'delivery_cloud_notifications', { p_action: req.params.action, p_payload: req.body }));
  }));
  const aiChat = createCustomerAiChatHandler({ env, fetcher, rpc });
  router.post('/ai-chat', route(aiChat));
  router.get('/profile', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_profile', {}))));
  router.post('/profile', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_profile', { p_details: req.body }))));
  router.post('/memberships', route(async (req, res) => {
    if (!req.body || Object.keys(req.body).some(key => key !== 'role') || !['merchant','driver'].includes(req.body.role)) {
      throw new IntegrationError(400, 'Yêu cầu đối tác không hợp lệ.');
    }
    res.json(await rpc(req, 'delivery_cloud_membership', { p_role: req.body.role, p_decision: 'request' }));
  }));
  router.post('/accounts/:id/memberships/:role', route(async (req, res) => {
    const body = req.body;
    const minVersion = body?.decision === 'grant' ? 0 : 1;
    if (!body || Object.keys(body).some(key => !['decision','version','reason'].includes(key)) ||
        !['merchant','driver'].includes(req.params.role) || !['grant','approve','reject','revoke'].includes(body.decision) ||
        !Number.isSafeInteger(body.version) || body.version < minVersion || body.version > 2147483646 ||
        typeof body.reason !== 'string' || body.reason.length > 500 ||
        (['reject','revoke'].includes(body.decision) && body.reason.trim().length < 3)) {
      throw new IntegrationError(400, 'Quyết định đối tác không hợp lệ.');
    }
    res.json(await rpc(req, 'delivery_cloud_membership', { p_user: uuid(req.params.id), p_role: req.params.role,
      p_decision: body.decision, p_version: body.version, p_reason: body.reason.trim() }));
  }));
  router.get('/addresses', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_addresses_manage', {}))));
  router.post('/imports/:action', route(async (req, res) => {
    if (!['preview','commit'].includes(req.params.action) || !req.body || Object.keys(req.body).some(k=>k!=='items') ||
      !Array.isArray(req.body.items) || req.body.items.length < 1 || req.body.items.length > 25 ||
      Buffer.byteLength(JSON.stringify(req.body))>50000) throw new IntegrationError(400,'Yêu cầu nhập dữ liệu không hợp lệ.');
    res.json(await rpc(req,'delivery_cloud_import',{p_action:req.params.action,p_items:req.body.items}));
  }));
  router.post('/addresses/:id', route(async (req, res) => {
    const body = req.body;
    if (!body || Object.keys(body).some(key => !['details','delete','version'].includes(key)) ||
        (body.delete !== undefined && typeof body.delete !== 'boolean') ||
        (body.version !== undefined && (!Number.isSafeInteger(body.version) || body.version < 1 || body.version > 2147483646))) {
      throw new IntegrationError(400, 'Thao tác địa chỉ không hợp lệ.');
    }
    res.json(await rpc(req, 'delivery_cloud_addresses_manage', {
      p_id: uuid(req.params.id), p_details: body.details ?? null,
      p_delete: body.delete ?? false, p_version: body.version ?? null,
    }));
  }));
  router.get('/accounts', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_accounts_manage', {}))));
  router.post('/accounts/:id', route(async (req, res) => {
    if (!['customer','merchant','driver'].includes(req.body?.role) || typeof req.body?.blocked !== 'boolean') throw new IntegrationError(400, 'Vai trò không hợp lệ.');
    await requireWorkflow(req);
    res.json(await rpc(req, 'delivery_cloud_accounts_manage', { p_user: uuid(req.params.id), p_role: req.body.role, p_blocked: req.body.blocked }));
  }));
  router.get('/merchants', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_merchants', {}))));
  router.get('/pricing', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_pricing_manage', {}))));
  router.post('/pricing', route(async (req, res) => {
    const limits = { base_fee: 1000000, per_km: 100000, express_fee: 1000000, extra_kg: 100000, version: 2147483646 };
    for(const [key, max] of Object.entries(limits)) {
      const value = req.body?.[key];
      if (!Number.isSafeInteger(value) || value < (key === 'version' ? 1 : 0) || value > max) throw new IntegrationError(400, 'Bảng giá cần số nguyên trong giới hạn cho phép.');
    }
    if (Object.keys(req.body).some(key => !Object.hasOwn(limits, key))) throw new IntegrationError(400, 'Thông tin bảng giá không hợp lệ.');
    await requireWorkflow(req);
    res.json(await rpc(req, 'delivery_cloud_pricing_manage', { p_values: req.body }));
  }));
  router.get('/audit', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_audit_read', {}))));
  router.post('/quote', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_quote', { p_details: req.body }))));
  router.get('/orders', route(async (req, res) => {
    const before = req.query.before;
    if (before && (typeof before !== 'string' || before.length > 40 || !Number.isFinite(Date.parse(before)))) throw new IntegrationError(400, 'Mốc phân trang không hợp lệ.');
    const beforeId = req.query.before_id ? uuid(req.query.before_id) : null;
    res.json(await rpc(req, 'delivery_cloud_list', { p_queue: req.query.queue === 'true', p_before: before || null, p_before_id: beforeId }));
  }));
  router.post('/orders', route(async (req, res) => {
    res.json({ order: await rpc(req, 'delivery_cloud_create', { p_details: req.body?.details,
      p_request_key: uuid(req.body?.request_key), p_pricing_version: integer(req.body?.pricing_version), p_expected_fee: integer(req.body?.expected_fee) }) });
  }));
  router.get('/orders/:id/history', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_history_read', { p_order: uuid(req.params.id) }))));
  router.get('/orders/:id/otp', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_order_otp', { p_order: uuid(req.params.id) }))));
  router.get('/orders/:id/shares', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_share_manage', { p_order: uuid(req.params.id), p_action: 'list', p_share: null }))));
  router.post('/orders/:id/shares', route(async (req, res) => {
    const result = await rpc(req, 'delivery_cloud_share_manage', { p_order: uuid(req.params.id), p_action: 'create', p_share: null });
    res.json(attachShareUrl(result, env));
  }));
  router.post('/orders/:id/shares/:shareId/revoke', route(async (req, res) => res.json(await rpc(req, 'delivery_cloud_share_manage', {
    p_order: uuid(req.params.id), p_action: 'revoke', p_share: uuid(req.params.shareId),
  }))));
  router.post('/orders/:id/transition', route(async (req, res) => {
    if (!['ready','claim','cancel','arrive','pickup','deliver','fail','retry','return','complete_return','collect_cash'].includes(req.body?.action) ||
      (req.body.reason != null && (typeof req.body.reason !== 'string' || req.body.reason.length > 500))) throw new IntegrationError(400, 'Thao tác không hợp lệ.');
    if (['cancel','fail','return'].includes(req.body.action) && (req.body.reason || '').trim().length < 3) throw new IntegrationError(400, 'Cần nhập lý do ít nhất 3 ký tự.');
    await requireWorkflow(req);
    res.json({ order: await rpc(req, 'delivery_cloud_transition', { p_order: uuid(req.params.id),
      p_action: req.body.action, p_version: integer(req.body.version), p_request_key: uuid(req.body.request_key), p_reason: req.body.reason || '' }) });
  }));
  return router;
}
