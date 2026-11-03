import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { IntegrationError } from './provider-http.mjs';

let processing = 0;
export async function normalizeMarketImage(raw) {
  if (typeof raw !== 'string' || raw.length > 6_666_668 || !raw.length || raw.length % 4 !== 0 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(raw)) throw new IntegrationError(400, 'Chọn ảnh JPEG, PNG hoặc WebP tối đa 5 MB.');
  const bytes = Buffer.from(raw, 'base64');
  if (!bytes.length || bytes.length > 5_000_000 || bytes.toString('base64') !== raw) throw new IntegrationError(400, 'Ảnh không hợp lệ.');
  if (processing >= 2) throw new IntegrationError(429, 'Đang xử lý ảnh. Vui lòng thử lại.');
  processing++;
  try {
    const input = sharp(bytes, { limitInputPixels: 20_000_000, failOn: 'warning' });
    const info = await input.metadata();
    if (!['jpeg', 'png', 'webp'].includes(info.format) || info.pages > 1 || !info.width || !info.height ||
      info.width > 8000 || info.height > 8000) throw new Error('Invalid image');
    // Decode completely and re-encode to remove metadata, appended payloads and
    // untrusted filenames. Public product images never retain device GPS/EXIF.
    return await input.rotate().resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true })
      .webp({ quality: 85 }).timeout({ seconds: 10 }).toBuffer();
  } catch { throw new IntegrationError(400, 'Ảnh bị hỏng hoặc vượt giới hạn kích thước.'); }
  finally { processing--; }
}

async function verifyDuplicateBytes(fetcher, url, headers, hash) {
  const existing = await fetcher(url, { redirect: 'error', signal: AbortSignal.timeout(10000), headers });
  if (!existing.ok) throw new Error('Missing duplicate');
  const chunks = []; let size = 0;
  for await (const chunk of existing.body ?? []) {
    size += chunk.length;
    if (size > 5_000_000) throw new Error('Oversized duplicate');
    chunks.push(chunk);
  }
  if (createHash('sha256').update(Buffer.concat(chunks)).digest('hex') !== hash) throw new Error('Mismatched duplicate');
}

async function signPrivateObject({ env, fetcher, req, bucket, objectPath }) {
  let response;
  try {
    response = await fetcher(new URL(`/storage/v1/object/sign/${bucket}/${objectPath}`, env.SUPABASE_URL), {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${req.deliveryIdentity.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ expiresIn: 300 }),
    });
  } catch { throw new IntegrationError(502, 'Không tạo được liên kết xem bằng chứng tạm thời.'); }
  if (response.status === 400 || response.status === 403 || response.status === 404) {
    await response.body?.cancel();
    throw new IntegrationError(403, 'Không có quyền xem tệp bằng chứng hoặc tệp không tồn tại.');
  }
  if (!response.ok) {
    await response.body?.cancel();
    throw new IntegrationError(502, 'Không lấy được liên kết xem bằng chứng.');
  }
  let data;
  try { data = await response.json(); } catch { throw new IntegrationError(502, 'Phản hồi lưu trữ không hợp lệ.'); }
  const rawPath = data?.signedURL || data?.signedUrl;
  if (typeof rawPath !== 'string' || !rawPath.startsWith('/')) throw new IntegrationError(502, 'Liên kết ký tạm thời không hợp lệ.');
  const normalized = rawPath.startsWith('/storage/v1/') ? rawPath : `/storage/v1${rawPath}`;
  return { url: new URL(normalized, env.SUPABASE_URL).href, expires_in: 300 };
}

export function createMarketMedia({ env, fetcher, rpc }) {
  return async req => {
    const d = req.body;
    if (!d || Array.isArray(d) || Object.keys(d).some(k => !['shop_id', 'image'].includes(k)) ||
      typeof d.shop_id !== 'string' || !/^[a-f0-9-]{36}$/i.test(d.shop_id)) throw new IntegrationError(400, 'Yêu cầu ảnh không hợp lệ.');
    const workspace = await rpc(req, 'delivery_marketplace', { p_action: 'workspace', p_payload: {} });
    if (!workspace.shops?.some(s => s.id === d.shop_id)) throw new IntegrationError(403, 'Không có quyền tải ảnh cho cửa hàng này.');
    const bytes = await normalizeMarketImage(d.image);
    const hash = createHash('sha256').update(bytes).digest('hex');
    const reserved = await rpc(req, 'delivery_market_media_reserve', { p_shop: d.shop_id, p_hash: hash, p_bytes: bytes.length });
    const expected = `${req.deliveryIdentity.id}/${d.shop_id}/${hash}.webp`;
    if (reserved?.bucket !== 'delivery-market-media' || reserved?.name !== expected) throw new IntegrationError(502, 'Phản hồi lưu ảnh không hợp lệ.');
    const target = new URL(`/storage/v1/object/delivery-market-media/${expected}`, env.SUPABASE_URL);
    const publicUrl = new URL(`/storage/v1/object/public/delivery-market-media/${expected}`, env.SUPABASE_URL);
    let response;
    try {
      response = await fetcher(target, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: {
          apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${req.deliveryIdentity.token}`,
          'Content-Type': 'image/webp', 'x-upsert': 'false', 'Cache-Control': 'max-age=31536000',
        },
        body: bytes,
      });
      if (response.status === 409 || response.status === 400) {
        await verifyDuplicateBytes(fetcher, publicUrl, {}, hash);
      } else if (!response.ok) throw new Error('Storage rejected upload');
      await response.body?.cancel();
    } catch { throw new IntegrationError(502, 'Chưa lưu được ảnh. Vui lòng thử lại.'); }
    return { image_url: publicUrl.href, byte_size: bytes.length };
  };
}

export function createPrivateAttachmentUpload({ env, fetcher, rpc }) {
  return async req => {
    const d = req.body;
    if (!d || Array.isArray(d) || Object.keys(d).some(k => !['order_id', 'scope', 'image'].includes(k)) ||
      typeof d.order_id !== 'string' || !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(d.order_id) ||
      !['chat', 'return', 'finance'].includes(d.scope)) {
      throw new IntegrationError(400, 'Yêu cầu tệp bằng chứng không hợp lệ.');
    }
    const bytes = await normalizeMarketImage(d.image);
    const hash = createHash('sha256').update(bytes).digest('hex');
    const reserved = await rpc(req, 'delivery_market_attachment_reserve', {
      p_order: d.order_id, p_scope: d.scope, p_hash: hash, p_bytes: bytes.length,
    });
    const expected = `${d.scope}/${d.order_id.toLowerCase()}/${hash}.webp`;
    if (reserved?.bucket !== 'delivery-private-evidence' || reserved?.name !== expected) {
      throw new IntegrationError(502, 'Phản hồi đặt chỗ tệp bằng chứng không hợp lệ.');
    }
    const authHeaders = { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${req.deliveryIdentity.token}` };
    const target = new URL(`/storage/v1/object/delivery-private-evidence/${expected}`, env.SUPABASE_URL);
    const authReadUrl = new URL(`/storage/v1/object/authenticated/delivery-private-evidence/${expected}`, env.SUPABASE_URL);
    let response;
    try {
      response = await fetcher(target, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: { ...authHeaders, 'Content-Type': 'image/webp', 'x-upsert': 'false' },
        body: bytes,
      });
      if (response.status === 409 || response.status === 400) {
        await verifyDuplicateBytes(fetcher, authReadUrl, authHeaders, hash);
      } else if (!response.ok) throw new Error('Storage rejected private attachment');
      await response.body?.cancel();
    } catch { throw new IntegrationError(502, 'Chưa lưu được tệp bằng chứng riêng tư.'); }
    return { attachment: { id: reserved.id, name: expected, scope: d.scope, byte_size: bytes.length } };
  };
}

export function createPrivateAttachmentSign({ env, fetcher }) {
  return async req => {
    const d = req.body;
    if (!d || Array.isArray(d) || Object.keys(d).some(k => k !== 'name') ||
      typeof d.name !== 'string' || !/^(chat|return|finance)\/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\/[a-f0-9]{64}\.webp$/i.test(d.name)) {
      throw new IntegrationError(400, 'Đường dẫn tệp bằng chứng không hợp lệ.');
    }
    return signPrivateObject({ env, fetcher, req, bucket: 'delivery-private-evidence', objectPath: d.name });
  };
}

export function createPodUpload({ env, fetcher }) {
  return async req => {
    const d = req.body;
    if (!d || Array.isArray(d) || Object.keys(d).some(k => !['tracking_code', 'image'].includes(k)) ||
      typeof d.tracking_code !== 'string' || !/^CL-[A-F0-9]{32}$/.test(d.tracking_code)) {
      throw new IntegrationError(400, 'Yêu cầu tải ảnh POD không hợp lệ.');
    }
    const bytes = await normalizeMarketImage(d.image);
    const hash = createHash('sha256').update(bytes).digest('hex');
    const objectPath = `${d.tracking_code}/pod-${hash}.webp`;
    const authHeaders = { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${req.deliveryIdentity.token}` };
    const target = new URL(`/storage/v1/object/delivery-evidence/${objectPath}`, env.SUPABASE_URL);
    const authReadUrl = new URL(`/storage/v1/object/authenticated/delivery-evidence/${objectPath}`, env.SUPABASE_URL);
    let uploadResp;
    try {
      uploadResp = await fetcher(target, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: { ...authHeaders, 'Content-Type': 'image/webp', 'x-upsert': 'false' },
        body: bytes,
      });
      if (uploadResp.status === 403 || uploadResp.status === 401) {
        await uploadResp.body?.cancel();
        throw new IntegrationError(403, 'Chỉ tài xế đang giao chuyến này hoặc quản trị viên được tải ảnh POD.');
      }
      if (uploadResp.status === 409 || uploadResp.status === 400) {
        await verifyDuplicateBytes(fetcher, authReadUrl, authHeaders, hash);
      } else if (!uploadResp.ok) throw new Error('POD upload failed');
      await uploadResp.body?.cancel();
    } catch (error) {
      if (error instanceof IntegrationError) throw error;
      throw new IntegrationError(502, 'Chưa lưu được ảnh bằng chứng giao hàng.');
    }
    let eventResp;
    try {
      eventResp = await fetcher(new URL('/rest/v1/delivery_live_events', env.SUPABASE_URL), {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
        headers: { ...authHeaders, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify({ room_id: d.tracking_code, kind: 'pod', payload: { path: objectPath, hash, byte_size: bytes.length } }),
      });
      await eventResp.body?.cancel();
    } catch { throw new IntegrationError(502, 'Không ghi nhận được sự kiện POD.'); }
    if (eventResp.status === 401 || eventResp.status === 403) {
      throw new IntegrationError(403, 'Không có quyền ghi nhận bằng chứng POD cho chuyến này.');
    }
    if (!eventResp.ok) throw new IntegrationError(502, 'Cơ sở dữ liệu từ chối sự kiện POD.');
    return { path: objectPath, byte_size: bytes.length };
  };
}

export function createPodSign({ env, fetcher }) {
  return async req => {
    const d = req.body;
    if (!d || Array.isArray(d) || Object.keys(d).some(k => k !== 'path') ||
      typeof d.path !== 'string' || !/^CL-[A-F0-9]{32}\/pod-[a-f0-9]{64}\.(webp|jpg|jpeg|png)$/i.test(d.path)) {
      throw new IntegrationError(400, 'Đường dẫn ảnh POD không hợp lệ.');
    }
    return signPrivateObject({ env, fetcher, req, bucket: 'delivery-evidence', objectPath: d.path });
  };
}
