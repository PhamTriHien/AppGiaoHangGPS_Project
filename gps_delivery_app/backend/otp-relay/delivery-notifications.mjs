import express from 'express';
import crypto from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { IntegrationError, providerJson, secureEqual } from './delivery-integrations.mjs';
import { providerConfigured } from './integration-config.mjs';

function marketNotificationBody(kind) {
  switch (kind) {
    case 'new_order': return 'Cửa hàng vừa có đơn mua hàng mới.';
    case 'message': return 'Bạn có tin nhắn mới trong đơn mua hàng.';
    case 'return_requested': return 'Có yêu cầu trả hàng mới cần xử lý.';
    case 'review_replied': return 'Cửa hàng đã phản hồi đánh giá của bạn.';
    case 'acceptance_expired': return 'Đơn mua hàng đã hết hạn xác nhận.';
    default: return 'Đơn mua hàng vừa cập nhật trạng thái.';
  }
}

export function createNotificationRouter({ env = process.env, authenticate, fetcher = fetch,
  sendPush = null } = {}) {
  const router = express.Router();
  const completed = new Map();
  const supabase = async (path, options = {}, token = env.SUPABASE_SERVICE_ROLE_KEY) => {
    if (!providerConfigured('supabase', env) || !token) throw new IntegrationError(503, 'Chua cau hinh cloud thong bao.');
    const secretKey = token.startsWith('sb_secret_');
    return providerJson(new URL(`/rest/v1/${path}`, env.SUPABASE_URL), {
      ...options, headers: { apikey: secretKey ? token : env.SUPABASE_ANON_KEY,
        ...(!secretKey ? { Authorization: `Bearer ${token}` } : {}),
        'Content-Type': 'application/json', ...options.headers },
    }, fetcher);
  };
  async function dispatchFcm(tokens, notification, data) {
    if (!tokens.length || env.FIREBASE_ENABLED === 'false' || (!sendPush && !providerConfigured('firebase', env))) return 0;
    let app;
    if (!sendPush) {
      const json = await readFile(env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8');
      const name = `delivery-${crypto.createHash('sha256').update(json).digest('hex').slice(0, 16)}`;
      app = getApps().find(candidate => candidate.name === name) || initializeApp({ credential: cert(JSON.parse(json)) }, name);
    }
    const send = sendPush || (message => getMessaging(app).sendEachForMulticast(message));
    const result = await send({ tokens: tokens.slice(0, 500).map(t => t.token), notification, data });
    for (const [i, response] of result.responses.entries()) {
      if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(response.error?.code)) {
        await supabase(`delivery_device_tokens?user_id=eq.${encodeURIComponent(tokens[i].user_id)}&token=eq.${encodeURIComponent(tokens[i].token)}`, {
          method: 'DELETE', headers: { Prefer: 'return=representation' },
        });
      }
    }
    if (result.failureCount && !result.responses.every(r => r.success ||
        ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(r.error?.code))) {
      throw new IntegrationError(502, 'Gui thong bao chua hoan tat, webhook can thu lai.');
    }
    return result.successCount;
  }
  router.post('/push/register', authenticate, async (req, res, next) => {
    try {
      const identity = req.deliveryIdentity;
      const token = req.body?.token;
      if (identity.local) return res.status(409).json({ error: 'Can dang nhap cloud de dang ky thong bao.' });
      if (typeof token !== 'string' || token.length < 20 || token.length > 4096)
        throw new IntegrationError(400, 'Token thiet bi khong hop le.');
      await supabase('delivery_device_tokens?on_conflict=user_id,token', {
        method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=representation' },
        body: JSON.stringify({ user_id: identity.id, token, updated_at: new Date().toISOString() }),
      }, identity.token);
      res.json({ registered: true });
    } catch (e) { next(e); }
  });
  router.post('/push/unregister', authenticate, async (req, res, next) => {
    try {
      if (!req.deliveryIdentity.local && typeof req.body?.token === 'string') {
        await supabase(`delivery_device_tokens?user_id=eq.${encodeURIComponent(req.deliveryIdentity.id)}&token=eq.${encodeURIComponent(req.body.token)}`, {
          method: 'DELETE', headers: { Prefer: 'return=representation' },
        }, req.deliveryIdentity.token);
      }
      res.json({ unregistered: true });
    } catch (e) { next(e); }
  });
  async function handleWebhook(req, res, next) {
    if (!secureEqual(req.get('authorization'), `Bearer ${env.DELIVERY_WEBHOOK_SECRET || ''}`) || !env.DELIVERY_WEBHOOK_SECRET)
      return res.status(401).json({ error: 'Unauthorized' });
    try {
      const payload = req.body;
      const record = payload?.record;
      for (const [id, time] of completed) if (time < Date.now() - 86400000) completed.delete(id);
      if (payload?.type === 'INSERT' && payload?.table === 'delivery_user_notifications' && typeof record?.id === 'string') {
        const dedupKey = `user_notif:${record.id}`;
        if (completed.has(dedupKey)) return res.json({ duplicate: true });
        const stored = await supabase(`delivery_user_notifications?id=eq.${encodeURIComponent(record.id)}&select=id,user_id,category,kind,title,body,reference_type,reference_id`);
        const notif = stored[0];
        if (!notif) return res.json({ skipped: true });
        const prefs = await supabase(`delivery_notification_preferences?user_id=eq.${encodeURIComponent(notif.user_id)}&select=push_enabled`);
        if (prefs[0]?.push_enabled === false) {
          if (completed.size >= 5000) completed.delete(completed.keys().next().value);
          completed.set(dedupKey, Date.now());
          return res.json({ sent: 0, skipped: true });
        }
        const tokens = await supabase(`delivery_device_tokens?user_id=eq.${encodeURIComponent(notif.user_id)}&select=user_id,token`);
        const sent = await dispatchFcm(tokens,
          { title: notif.title || 'GHST EXPRESS', body: notif.body },
          {
            notificationId: String(notif.id),
            category: String(notif.category),
            kind: String(notif.kind),
            ...(notif.reference_type ? { referenceType: String(notif.reference_type) } : {}),
            ...(notif.reference_id ? { referenceId: String(notif.reference_id) } : {}),
          },
        );
        if (completed.size >= 5000) completed.delete(completed.keys().next().value);
        completed.set(dedupKey, Date.now());
        return res.json({ sent });
      }
      if (payload?.type === 'INSERT' && payload?.table === 'delivery_market_notifications' && typeof record?.id === 'string') {
        const dedupKey = `market:${record.id}`;
        if (completed.has(dedupKey)) return res.json({ duplicate: true });
        const stored = await supabase(`delivery_market_notifications?id=eq.${encodeURIComponent(record.id)}&select=id,user_id,order_id,kind`);
        const notif = stored[0];
        if (!notif) return res.json({ skipped: true });
        const tokens = await supabase(`delivery_device_tokens?user_id=eq.${encodeURIComponent(notif.user_id)}&select=user_id,token`);
        const sent = await dispatchFcm(tokens,
          { title: 'GHST EXPRESS', body: marketNotificationBody(notif.kind) },
          { marketOrderId: String(notif.order_id), notificationId: String(notif.id), kind: String(notif.kind) },
        );
        if (completed.size >= 5000) completed.delete(completed.keys().next().value);
        completed.set(dedupKey, Date.now());
        return res.json({ sent });
      }
      if (payload?.type !== 'INSERT' || payload?.table !== 'delivery_live_events' ||
          typeof record?.id !== 'string' || typeof record?.room_id !== 'string')
        throw new IntegrationError(400, 'Webhook khong hop le.');
      if (completed.has(record.id)) return res.json({ duplicate: true });
      // Re-read the event: webhook data alone never selects recipients or notification content.
      const stored = await supabase(`delivery_live_events?id=eq.${encodeURIComponent(record.id)}&select=id,room_id,sender_id,kind,payload`);
      const event = stored[0];
      if (!event || !['status', 'chat'].includes(event.kind)) return res.json({ skipped: true });
      const members = await supabase(`delivery_live_members?room_id=eq.${encodeURIComponent(event.room_id)}&select=user_id`);
      const recipients = [...new Set(members.filter(m => !event.sender_id || m.user_id !== event.sender_id).map(m => m.user_id))];
      let tokens = [];
      if (recipients.length) tokens = await supabase(`delivery_device_tokens?user_id=in.(${recipients.map(encodeURIComponent).join(',')})&select=user_id,token`);
      const sent = await dispatchFcm(tokens,
        { title: 'GHST EXPRESS', body: event.kind === 'chat' ? 'Bạn có tin nhắn mới trong đơn hàng.' : 'Đơn hàng vừa cập nhật trạng thái.' },
        { roomId: event.room_id, eventId: event.id },
      );
      if (providerConfigured('telegram', env) &&
          event.kind === 'status' && ['failed', 'returning'].includes(event.payload?.status)) {
        const result = await providerJson(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
            chat_id: env.TELEGRAM_CHAT_ID, text: `GHST EXPRESS: Đơn ${event.room_id} cần kiểm tra · ${event.payload.status}.`,
          }),
        }, fetcher);
        if (!result.ok) throw new IntegrationError(502, 'Chua gui duoc canh bao noi bo.');
      }
      if (completed.size >= 5000) completed.delete(completed.keys().next().value);
      completed.set(record.id, Date.now());
      res.json({ sent });
    } catch (e) { next(e); }
  }
  router.post('/order-webhook', handleWebhook);
  router.post('/market-notification-webhook', handleWebhook);
  return router;
}
