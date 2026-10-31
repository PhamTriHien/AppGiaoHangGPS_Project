const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require(
  process.env.PLAYWRIGHT_MODULE ||
    path.join(process.env.LOCALAPPDATA, 'Temp', 'ghst-browser-check', 'node_modules', 'playwright-core'),
);

const PNG_1X1 = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);

const CORS = {
  'access-control-allow-origin': 'http://127.0.0.1:8080',
  'access-control-allow-headers': '*',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
};

function makeJwt(uid) {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(
    JSON.stringify({ sub: uid, role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString('base64url');
  return `${header}.${payload}.acceptance`;
}

function makeUser(uid, email) {
  return {
    id: uid,
    aud: 'authenticated',
    role: 'authenticated',
    email,
    app_metadata: { provider: 'email', providers: ['email'] },
    user_metadata: {},
    identities: [],
    created_at: new Date().toISOString(),
  };
}

async function createSession(browser, { width = 1440, height = 1000, acceptanceRoot, gallery }) {
  const context = await browser.newContext({
    viewport: { width, height },
    serviceWorkers: 'block',
    permissions: ['clipboard-read', 'clipboard-write'],
  });
  const page = await context.newPage();
  page.setDefaultTimeout(12000);
  const errors = [];
  const dumpAndRethrow = async (step, err) => {
    try {
      await page.screenshot({ path: path.join(acceptanceRoot, 'last-failure.png') });
      const buttons = await page
        .locator('[role=button]')
        .evaluateAll(els => els.map(e => e.getAttribute('aria-label') || e.textContent).filter(Boolean));
      const textboxes = await page
        .locator('[role=textbox]')
        .evaluateAll(els => els.map(e => e.getAttribute('aria-label') || e.getAttribute('placeholder') || e.textContent));
      const texts = (await page.locator('flt-semantics').allTextContents()).join(' ').replace(/\s+/g, ' ').slice(-2000);
      console.error(`FAILURE AT [${step}] (${width}x${height}):`);
      console.error('BUTTONS:', JSON.stringify(buttons));
      console.error('TEXTBOXES:', JSON.stringify(textboxes));
      console.error('TEXTS:', texts);
    } catch (_) {}
    throw err;
  };
  page.on('pageerror', err => errors.push(err.message));
  page.on('console', msg => {
    if (msg.type() === 'error' && /overflowed|RenderFlex|EXCEPTION CAUGHT/.test(msg.text())) {
      errors.push(msg.text());
    }
  });
  await page.route('**/*tile.openstreetmap.org/**', route =>
    route.fulfill({ headers: { ...CORS, 'content-type': 'image/png' }, body: PNG_1X1 }),
  );
  await page.route('**/*photon.komoot.io/**', route =>
    route.fulfill({ headers: CORS, json: { type: 'FeatureCollection', features: [] } }),
  );

  const enableSemantics = async () => {
    await page.waitForFunction(
      () => document.querySelector('flt-semantics-placeholder') || document.querySelector('flt-semantics'),
      { timeout: 30000 },
    );
    await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(el => el.click()));
  };

  const ensureVisible = async target => {
    await target.waitFor({ state: 'attached' });
    const scrollX = width >= 860 ? Math.round(width * 0.6) : Math.round(width * 0.5);
    const scrollY = Math.round(height * 0.5);
    for (let i = 0; i < 8; i++) {
      const box = await target.boundingBox();
      if (box && box.y >= 16 && box.y + box.height <= height - 16) break;
      await page.mouse.move(scrollX, scrollY);
      await page.mouse.wheel(0, box && box.y < 16 ? -480 : 480);
      await page.waitForTimeout(180);
    }
    await target.scrollIntoViewIfNeeded();
  };

  const fill = async (name, value, index = 0) => {
    try {
      const field = page.getByRole('textbox', { name, exact: true }).nth(index);
      await ensureVisible(field);
      await field.click();
      await field.press('ControlOrMeta+a');
      await field.press('Backspace');
      await field.pressSequentially(String(value), { delay: 10 });
    } catch (err) {
      await dumpAndRethrow(`fill(${name})`, err);
    }
  };

  const clickButton = async (name, { last = false } = {}) => {
    try {
      const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const loc = page
        .getByRole('button', { name, exact: true })
        .or(page.locator(`[role="button"][aria-label="${name.replace(/"/g, '\\"')}"]`))
        .or(page.getByRole('button', { name: new RegExp(`^${escaped}(\\s+${escaped})?$`) }));
      const target = last ? loc.last() : loc.first();
      await ensureVisible(target);
      await target.click();
      await page.mouse.move(0, 0);
      await page.waitForTimeout(200);
    } catch (err) {
      await dumpAndRethrow(`clickButton(${name})`, err);
    }
  };

  const clickNav = async label => {
    try {
      const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const safeXpath = label.replace(/"/g, '');
      const target = page
        .getByRole('button', { name: label, exact: true })
        .or(page.getByRole('switch', { name: label, exact: true }))
        .or(page.getByRole('checkbox', { name: label, exact: true }))
        .or(page.getByLabel(new RegExp('^' + escaped)))
        .or(page.locator(`xpath=//*[contains(concat("\n", @aria-label, "\n"), "\n${safeXpath}\n")]`))
        .or(page.getByText(new RegExp('(^|\\n)' + escaped + '(\\n|$)')))
        .last();
      await ensureVisible(target);
      await target.click();
      await page.mouse.move(0, 0);
      await page.waitForTimeout(200);
    } catch (err) {
      await dumpAndRethrow(`clickNav(${label})`, err);
    }
  };

  const waitText = async label => {
    try {
      const pat = label instanceof RegExp ? label.source : String(label);
      const rx = label instanceof RegExp;
      await page.waitForFunction(
        ({ pattern, isRegex }) => {
          const matcher = isRegex ? new RegExp(pattern) : null;
          const match = s =>
            s ? (matcher ? matcher.test(s) : s === pattern || s.startsWith(pattern + '\n') || s.includes(pattern)) : false;
          for (const el of document.querySelectorAll('flt-semantics, input, textarea')) {
            if (match(el.textContent) || match(el.getAttribute('aria-label')) || match(el.value)) return true;
          }
          return false;
        },
        { pattern: pat, isRegex: rx },
      );
    } catch (err) {
      await dumpAndRethrow(`waitText(${label})`, err);
    }
  };

  const clickBack = async () => {
    try {
      await page.waitForTimeout(250);
      const back = page.getByRole('button', { name: /^(Back|Quay lại)$/ }).last();
      await back.click();
      await page.mouse.move(0, 0);
      await back.waitFor({ state: 'hidden' });
    } catch (err) {
      await dumpAndRethrow('clickBack()', err);
    }
  };

  const assertHealthy = async label => {
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    assert.equal(overflow, false, `Horizontal overflow detected at ${label}`);
    assert.deepEqual(errors, [], `Runtime UI errors at ${label}: ${errors.join(' | ')}`);
  };

  const snap = async (folder, file, description, features = []) => {
    await page.mouse.move(-20, -20);
    await page.waitForTimeout(400);
    await assertHealthy(`${folder}/${file}`);
    const dir = path.join(acceptanceRoot, folder);
    await fs.mkdir(dir, { recursive: true });
    const fullPath = path.join(dir, file);
    await page.screenshot({ path: fullPath });
    gallery.push({ folder, file, viewport: `${width}x${height}`, description, features });
  };

  return { context, page, errors, enableSemantics, fill, clickButton, clickNav, waitText, clickBack, assertHealthy, snap };
}

function attachSupabaseAuth(page, { user, token, googleEnabled = false, operatorProfile = false, onRecover } = {}) {
  return page.route('**/*.supabase.co/**', route => {
    const req = route.request();
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
    const u = new URL(req.url());
    if (u.pathname.startsWith('/storage/v1/object/')) {
      return route.fulfill({ headers: { ...CORS, 'content-type': 'image/png' }, body: PNG_1X1 });
    }
    if (u.pathname === '/auth/v1/settings') {
      return route.fulfill({ headers: CORS, json: { external: { google: googleEnabled } } });
    }
    if (u.pathname === '/auth/v1/recover') {
      if (onRecover) onRecover(req.postDataJSON());
      return route.fulfill({ headers: CORS, json: {} });
    }
    if (u.pathname === '/auth/v1/logout') {
      return route.fulfill({ status: 204, headers: CORS });
    }
    if (u.pathname === '/auth/v1/token' || u.pathname === '/auth/v1/signup') {
      return route.fulfill({
        headers: CORS,
        json: { access_token: token, token_type: 'bearer', expires_in: 3600, refresh_token: 'fixture-refresh', user },
      });
    }
    if (u.pathname === '/auth/v1/user') {
      return route.fulfill({ headers: CORS, json: user });
    }
    if (u.pathname === '/rest/v1/delivery_api_profiles') {
      return route.fulfill({ headers: CORS, json: operatorProfile ? [{ role: 'operator' }] : [] });
    }
    return route.fulfill({ status: 403, headers: CORS, json: { message: 'Isolated fixture denied' } });
  });
}

async function runSuite01AuthAndPublic(browser, acceptanceRoot, gallery) {
  const folder = '01-auth-and-public';
  const uid = '00000000-0000-0000-0000-000000000101';
  const user = makeUser(uid, 'auth-check@example.com');
  const token = makeJwt(uid);
  const trackingCode = 'CL-60000000000000000000000000000101';
  let recoverCalled = false;
  let profileSaved = false;

  const s1440 = await createSession(browser, { width: 1440, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(s1440.page, {
      user,
      token,
      googleEnabled: true,
      onRecover: body => {
        assert.equal(body.email, user.email);
        recoverCalled = true;
      },
    });
    await s1440.page.route('http://127.0.0.1:8787/**', route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
      const u = new URL(req.url());
      const body = req.method() === 'POST' ? req.postDataJSON() : null;
      if (u.pathname === '/delivery/cloud/profile') {
        if (req.method() === 'POST') {
          assert.equal(body.full_name, 'Nguyễn Minh Khôi');
          assert.equal(body.phone, '0912345678');
          profileSaved = true;
        }
        return route.fulfill({
          headers: CORS,
          json: {
            schema_version: 3,
            operator: false,
            account: profileSaved
              ? {
                  user_id: uid,
                  full_name: 'Nguyễn Minh Khôi',
                  phone: '0912345678',
                  role: 'customer',
                  blocked: false,
                  requested_role: null,
                  coin_balance: 0,
                  approved_roles: [],
                  staff_shops: [],
                  memberships: [],
                }
              : null,
          },
        });
      }
      if (u.pathname === '/delivery/cloud/addresses') {
        return route.fulfill({ headers: CORS, json: { addresses: [] } });
      }
      if (u.pathname === '/delivery/cloud/orders') {
        return route.fulfill({ headers: CORS, json: { orders: [], schema_version: 3 } });
      }
      if (u.pathname === '/delivery/cloud/marketplace/catalog') {
        return route.fulfill({ headers: CORS, json: { products: [], categories: [], next: null } });
      }
      if (u.pathname === '/delivery/tracking') {
        return route.fulfill({
          headers: CORS,
          json: {
            shop_name: 'Bếp Nhà Sài Gòn',
            state: 'ready',
            delivery_status: 'delivered',
            updated_at: '2026-10-31T09:30:00Z',
            expires_at: '2026-11-01T09:30:00Z',
            phone: 'HIDDEN_PRIVATE_PHONE',
          },
        });
      }
      if (u.pathname === '/delivery/tracking/lookup') {
        assert.equal(body.tracking_code, trackingCode);
        assert.equal(body.phone_last4, '5678');
        return route.fulfill({
          headers: CORS,
          json: {
            tracking_code: trackingCode,
            status: 'delivered',
            service_type: 'express',
            distance_meters: 3600,
            created_at: '2026-10-31T08:00:00Z',
            updated_at: '2026-10-31T08:35:00Z',
            timeline: [
              { action: 'create', status: 'searching', created_at: '2026-10-31T08:00:00Z' },
              { action: 'pickup', status: 'inTransit', created_at: '2026-10-31T08:15:00Z' },
              { action: 'deliver', status: 'delivered', created_at: '2026-10-31T08:35:00Z' },
            ],
          },
        });
      }
      return route.fulfill({ status: 403, headers: CORS, json: { error: 'Auth fixture denied' } });
    });

    await s1440.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
    await s1440.enableSemantics();
    await s1440.page.getByText('Tiếp tục với Google', { exact: true }).waitFor();
    await s1440.fill('Email', user.email);
    await s1440.fill('Mật khẩu', 'CheckPass123');
    await s1440.clickButton('Hiện mật khẩu');
    await s1440.clickButton('Ẩn mật khẩu');
    await s1440.snap(folder, '01-login-desktop-1440.png', 'Màn hình Đăng nhập người dùng Cloud (Desktop 1440px)', [
      'Đăng nhập',
      'Đăng ký tài khoản',
      'Hiện mật khẩu / Ẩn mật khẩu',
      'Quên mật khẩu?',
      'Tiếp tục với Google',
    ]);

    await s1440.clickNav('Đăng ký tài khoản');
    await s1440.page.getByRole('button', { name: 'Tạo tài khoản', exact: true }).waitFor();
    await s1440.snap(folder, '02-register-form-1440.png', 'Chế độ Đăng ký tài khoản Cloud mới', [
      'Đăng ký tài khoản',
      'Mật khẩu mới',
      'Tạo tài khoản',
      'Trở về đăng nhập',
    ]);

    await s1440.clickButton('Trở về đăng nhập');
    await s1440.clickButton('Quên mật khẩu?');
    await s1440.fill('Email', user.email);
    await s1440.clickButton('Gửi email khôi phục');
    await s1440.page.getByText('Yêu cầu đã được gửi. Vui lòng kiểm tra email.', { exact: true }).waitFor();
    assert.equal(recoverCalled, true);
    await s1440.snap(folder, '03-password-recovery-1440.png', 'Luồng Quên mật khẩu & Đặt mật khẩu mới qua OTP email', [
      'Gửi email khôi phục',
      'Mã xác nhận email',
      'Đặt mật khẩu mới',
    ]);

    await s1440.clickButton('Trở về đăng nhập');
    await s1440.fill('Email', user.email);
    await s1440.fill('Mật khẩu', 'CheckPass123');
    await s1440.clickButton('Đăng nhập', { last: true });
    await s1440.page.getByText('Hoàn tất hồ sơ GHST EXPRESS', { exact: true }).waitFor();
    await s1440.fill('Họ và tên', 'Nguyễn Minh Khôi');
    await s1440.fill('Số điện thoại', '0912345678');
    await s1440.snap(folder, '04-onboarding-incomplete-profile-1440.png', 'Hoàn tất hồ sơ lần đầu sau xác thực Cloud', [
      'Họ và tên',
      'Số điện thoại',
      'Lưu hồ sơ',
      'Đăng xuất',
    ]);
    await s1440.clickButton('Lưu hồ sơ');
    await s1440.page.getByText('Bạn muốn giao hàng hay đặt món đến đâu?', { exact: true }).waitFor();
    assert.equal(profileSaved, true);

    await s1440.page.goto('http://127.0.0.1:8080/#/share?token=' + 'b'.repeat(64), { waitUntil: 'domcontentloaded' });
    await s1440.enableSemantics();
    await s1440.page.getByLabel(/Đã giao hàng/).waitFor();
    assert.equal(await s1440.page.getByText('HIDDEN_PRIVATE_PHONE', { exact: false }).count(), 0);
    await s1440.snap(folder, '05-public-share-token-1440.png', 'Trang theo dõi công khai qua liên kết chia sẻ (ẩn PII)', [
      '/#/share?token=...',
      'Bảo vệ SĐT người nhận',
    ]);

    await s1440.page.goto('http://127.0.0.1:8080/#/track', { waitUntil: 'domcontentloaded' });
    await s1440.enableSemantics();
    await s1440.fill('Mã vận đơn (CL-...) hoặc mã chia sẻ', trackingCode);
    await s1440.fill('4 số cuối SĐT nhận', '5678');
    await s1440.clickButton('Tra cứu');
    await s1440.page.getByText('NHẬT KÝ HÀNH TRÌNH XÁC THỰC CLOUD', { exact: true }).waitFor();
    await s1440.clickButton('Sao chép mã');
    await s1440.snap(folder, '06-public-tracking-lookup-1440.png', 'Tra cứu vận đơn công khai bằng mã CL + 4 số cuối SĐT', [
      'Tra cứu',
      'Sao chép mã',
      'Trang chủ',
    ]);
  } finally {
    await s1440.context.close();
  }

  const s360 = await createSession(browser, { width: 360, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(s360.page, { user, token, googleEnabled: true });
    await s360.page.route('http://127.0.0.1:8787/**', route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
      const u = new URL(req.url());
      if (u.pathname === '/delivery/tracking/lookup') {
        return route.fulfill({
          headers: CORS,
          json: {
            tracking_code: trackingCode,
            status: 'delivered',
            service_type: 'express',
            distance_meters: 3600,
            created_at: '2026-10-31T08:00:00Z',
            updated_at: '2026-10-31T08:35:00Z',
            timeline: [{ action: 'deliver', status: 'delivered', created_at: '2026-10-31T08:35:00Z' }],
          },
        });
      }
      return route.fulfill({ status: 403, headers: CORS, json: { error: 'Mobile auth fixture' } });
    });
    await s360.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
    await s360.enableSemantics();
    await s360.page.getByRole('button', { name: 'Đăng nhập', exact: true }).last().waitFor();
    await s360.snap(folder, '07-login-mobile-360.png', 'Màn hình Đăng nhập người dùng trên Mobile 360px', [
      'Responsive 360px',
      'Đăng nhập',
    ]);

    await s360.page.goto('http://127.0.0.1:8080/#/track', { waitUntil: 'domcontentloaded' });
    await s360.enableSemantics();
    await s360.fill('Mã vận đơn (CL-...) hoặc mã chia sẻ', trackingCode);
    await s360.fill('4 số cuối SĐT nhận', '5678');
    await s360.clickButton('Tra cứu');
    await s360.page.getByText('NHẬT KÝ HÀNH TRÌNH XÁC THỰC CLOUD', { exact: true }).waitFor();
    await s360.snap(folder, '08-public-tracking-mobile-360.png', 'Tra cứu vận đơn công khai trên Mobile 360px', [
      'Tra cứu Mobile 360px',
    ]);
  } finally {
    await s360.context.close();
  }
}

async function runSuite02Customer(browser, acceptanceRoot, gallery) {
  const folder = '02-customer';
  const uid = '00000000-0000-0000-0000-000000000201';
  const user = makeUser(uid, 'customer-check@example.com');
  const token = makeJwt(uid);
  const shipSearchingId = '60000000-0000-0000-0000-000000000201';
  const shipDeliveredId = '60000000-0000-0000-0000-000000000202';
  const marketOrderId = '60000000-0000-0000-0000-000000000203';
  const purchaseId = '50000000-0000-0000-0000-000000000201';
  const shopId = '20000000-0000-0000-0000-000000000201';
  const productId = '10000000-0000-0000-0000-000000000201';

  const addresses = [
    {
      id: '30000000-0000-0000-0000-000000000201',
      label: 'Văn phòng Quận 1',
      recipient_name: 'Trần Thu Hà',
      recipient_phone: '0909111222',
      full_address: '12 Nguyễn Huệ, Quận 1, TP.HCM',
      latitude: 10.774,
      longitude: 106.703,
      is_default: true,
      version: 1,
    },
  ];
  const shippingOrders = [
    {
      id: shipDeliveredId,
      tracking_code: 'CL-60000000000000000000000000000202',
      status: 'delivered',
      version: 4,
      shipping_fee: 32000,
      cod_amount: 150000,
      payment_status: 'PAID',
      owner_id: uid,
      driver_id: '00000000-0000-0000-0000-000000000501',
      pod_photo_path: 'pod/CL-60000000000000000000000000000202/proof.webp',
      created_at: '2026-10-31T07:00:00Z',
      details: {
        pickup_address: '12 Nguyễn Huệ, Quận 1, TP.HCM',
        dropoff_address: '88 Lê Lợi, Quận 1, TP.HCM',
        pickup_lat: 10.774,
        pickup_lng: 106.703,
        dropoff_lat: 10.772,
        dropoff_lng: 106.698,
        recipient_name: 'Lê Hoàng Nam',
        recipient_phone: '0918222333',
        package_description: 'Tài liệu hợp đồng niêm phong',
        weight_kg: 1.5,
        service_type: 'express',
        payment_method: 'sender_cash',
        require_pod: true,
        require_otp: true,
      },
    },
  ];
  let shipPaymentRecord = null;
  let purchasePaymentRecord = null;
  let shipShares = [];
  let shopFollowing = false;
  let favorite = false;
  let cartVersion = 1;
  let cartQty = 0;
  let selectedVariantId = 'var-m';
  let checkoutDone = false;
  let reordered = false;
  let returnCreated = false;
  let productReviewed = false;
  let shopReviewed = false;
  let driverReviewed = false;
  let requestedMembership = false;
  let advancedQuoteChecked = false;
  const readNotices = new Set();
  const chatMessages = [
    { id: 'msg-1', body: 'Shop đang đóng gói kỹ cho bạn nhé.', actor_id: 'merchant', attachments: [] },
  ];

  const product = {
    id: productId,
    shop_id: shopId,
    shop_name: 'Cửa hàng Đặc Sản Sài Gòn',
    name: 'Combo Cà Phê Đặc Sản Rang Mộc',
    description: 'Hạt Arabica Cầu Đất rang mộc nguyên chất.',
    sku: 'CF-M',
    category: 'Đồ uống',
    price: 65000,
    flash_sale_price: 49000,
    variants_count: 2,
    stock: 12,
    weight_kg: 0.5,
    image_url: 'https://yvnbfurazjbhbopahtmx.supabase.co/storage/v1/object/public/delivery-market-media/coffee.webp',
    images: ['https://yvnbfurazjbhbopahtmx.supabase.co/storage/v1/object/public/delivery-market-media/coffee.webp'],
    published: true,
    shop_status: 'active',
    paused: false,
    available: true,
    preparation_minutes: 10,
    version: 1,
    option_groups: [
      {
        id: 'grind',
        name: 'Kiểu xay',
        min: 1,
        max: 1,
        options: [
          { id: 'phin', name: 'Xay pha phin', price: 0 },
          { id: 'espresso', name: 'Xay pha máy (+5k)', price: 5000 },
        ],
      },
    ],
  };
  const variants = [
    { id: 'var-m', product_id: productId, sku: 'CF-250G', title: 'Gói 250g', price: 65000, stock: 12, weight_kg: 0.25, published: true, version: 1 },
    { id: 'var-l', product_id: productId, sku: 'CF-500G', title: 'Size L 500g', price: 115000, stock: 8, weight_kg: 0.5, published: true, version: 1 },
  ];
  const voucher = {
    id: 'voc-1',
    code: 'GHST15K',
    title: 'Giảm 15k đơn từ 50k',
    discount_kind: 'fixed',
    discount_value: 15000,
    max_discount: 15000,
    min_subtotal: 50000,
    budget_total: 500000,
    remaining_budget: 485000,
    active: true,
  };

  const attachCustomerBackend = page =>
    page.route('http://127.0.0.1:8787/**', route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
      const u = new URL(req.url());
      const body = req.method() === 'POST' ? req.postDataJSON() : null;
      const p = u.pathname;

      if (p === '/delivery/cloud/profile') {
        return route.fulfill({
          headers: CORS,
          json: {
            schema_version: 3,
            operator: false,
            account: {
              user_id: uid,
              full_name: 'Trần Thu Hà',
              phone: '0909111222',
              role: 'customer',
              blocked: false,
              requested_role: requestedMembership ? 'merchant' : null,
              coin_balance: 1500,
              approved_roles: [],
              staff_shops: [],
              memberships: requestedMembership
                ? [{ role: 'merchant', state: 'pending', version: 1, reason: '' }]
                : [],
            },
          },
        });
      }
      if (p === '/delivery/cloud/memberships') {
        assert.equal(body.role, 'merchant');
        requestedMembership = true;
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === '/delivery/cloud/addresses') {
        return route.fulfill({ headers: CORS, json: { addresses } });
      }
      if (p.startsWith('/delivery/cloud/addresses/')) {
        const id = p.split('/').pop();
        addresses.push({ id, ...body.details, version: 1 });
        return route.fulfill({ headers: CORS, json: { addresses } });
      }
      if (p === '/delivery/cloud/merchants') {
        return route.fulfill({ headers: CORS, json: { merchants: [] } });
      }
      if (p === '/delivery/cloud/quote') {
        if (body && body.package_description === 'Hộp quà tặng doanh nghiệp') {
          advancedQuoteChecked =
            body.is_round_trip === true &&
            body.prefer_ev === true &&
            body.green_fund === true &&
            body.require_pod === true &&
            body.require_otp === true &&
            Array.isArray(body.extra_stops) &&
            body.extra_stops.length === 1;
        } else {
          return route.fulfill({
            headers: CORS,
            json: {
              pricing_version: 2,
              shipping_fee: 28000,
              distance_meters: 2400,
              breakdown: { base_fee: 18000, distance_fee: 10000, weight_fee: 0, express_fee: 0 },
            },
          });
        }
        return route.fulfill({
          headers: CORS,
          json: {
            pricing_version: 2,
            shipping_fee: 48000,
            distance_meters: 4200,
            volumetric_weight_kg: 2.4,
            estimated_co2_saved_grams: 310,
            breakdown: {
              base_fee: 18000,
              distance_fee: 11000,
              weight_fee: 0,
              express_fee: 0,
              stop_fee: 5000,
              round_trip_fee: 11000,
              insurance_fee: 2000,
              green_fee: 1000,
            },
          },
        });
      }
      if (p === '/delivery/cloud/orders') {
        if (req.method() === 'POST') {
          const created = {
            id: shipSearchingId,
            tracking_code: 'CL-60000000000000000000000000000201',
            status: 'searching',
            version: 1,
            shipping_fee: body.expected_fee,
            cod_amount: body.details.cod_amount,
            payment_status: 'UNPAID',
            owner_id: uid,
            driver_id: null,
            created_at: '2026-10-31T09:00:00Z',
            details: body.details,
          };
          shippingOrders.unshift(created);
          return route.fulfill({ headers: CORS, json: { order: created } });
        }
        return route.fulfill({ headers: CORS, json: { orders: shippingOrders, schema_version: 3 } });
      }
      if (p === `/delivery/cloud/orders/${shipSearchingId}/payment`) {
        if (req.method() === 'POST') {
          shipPaymentRecord = {
            status: 'PENDING',
            amount: 48000,
            checkout_url: 'https://pay.payos.vn/web/fixture-ship',
            expires_at: '2026-11-01T09:00:00Z',
          };
        }
        return route.fulfill({ headers: CORS, json: { configured: true, payment: shipPaymentRecord } });
      }
      if (p === `/delivery/cloud/orders/${shipSearchingId}/payment/refresh`) {
        shipPaymentRecord = { ...shipPaymentRecord, status: 'PAID' };
        shippingOrders[0].payment_status = 'PAID';
        return route.fulfill({ headers: CORS, json: { configured: true, payment: shipPaymentRecord } });
      }
      if (p === `/delivery/cloud/orders/${shipDeliveredId}/history`) {
        return route.fulfill({
          headers: CORS,
          json: {
            history: [
              { order_id: shipDeliveredId, version: 1, action: 'create', status: 'searching', created_at: '2026-10-31T07:00:00Z', reason: '' },
              { order_id: shipDeliveredId, version: 2, action: 'claim', status: 'accepted', created_at: '2026-10-31T07:05:00Z', reason: '' },
              { order_id: shipDeliveredId, version: 3, action: 'pickup', status: 'inTransit', created_at: '2026-10-31T07:15:00Z', reason: '' },
              { order_id: shipDeliveredId, version: 4, action: 'deliver', status: 'delivered', created_at: '2026-10-31T07:35:00Z', reason: '' },
            ],
          },
        });
      }
      if (p === `/delivery/cloud/orders/${shipDeliveredId}/otp`) {
        return route.fulfill({ headers: CORS, json: { recipient_otp: '654321' } });
      }
      if (p === `/delivery/cloud/orders/${shipDeliveredId}/shares`) {
        if (req.method() === 'POST') {
          const share = {
            id: 'ship-share-1',
            token: 'c'.repeat(64),
            share_url: 'http://127.0.0.1:8080/#/share?token=' + 'c'.repeat(64),
            expires_at: '2026-11-01T10:00:00Z',
            revoked_at: null,
          };
          shipShares = [share];
          return route.fulfill({ headers: CORS, json: share });
        }
        return route.fulfill({ headers: CORS, json: { shares: shipShares } });
      }
      if (p === `/delivery/cloud/orders/${shipDeliveredId}/shares/ship-share-1/revoke`) {
        shipShares = shipShares.map(s => ({ ...s, revoked_at: '2026-10-31T10:05:00Z' }));
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === '/delivery/cloud/pod/sign') {
        return route.fulfill({
          headers: CORS,
          json: { url: 'https://yvnbfurazjbhbopahtmx.supabase.co/storage/v1/object/sign/pod/proof.webp' },
        });
      }
      if (p === '/delivery/cloud/attachments') {
        assert.ok(body.image.length > 0);
        return route.fulfill({
          headers: CORS,
          json: { attachment: { name: `${body.scope}-evidence-01.webp`, scope: body.scope } },
        });
      }
      if (p === '/delivery/cloud/attachments/sign') {
        return route.fulfill({
          headers: CORS,
          json: { url: 'https://yvnbfurazjbhbopahtmx.supabase.co/storage/v1/object/sign/private/' + body.name },
        });
      }
      if (p === `/delivery/cloud/purchases/${purchaseId}/payment`) {
        if (req.method() === 'POST') {
          purchasePaymentRecord = {
            status: 'PENDING',
            amount: 128500,
            checkout_url: 'https://pay.payos.vn/web/fixture-purchase',
            expires_at: '2026-11-01T10:00:00Z',
          };
        }
        return route.fulfill({ headers: CORS, json: { configured: true, payment: purchasePaymentRecord } });
      }
      if (p === `/delivery/cloud/purchases/${purchaseId}/payment/refresh`) {
        purchasePaymentRecord = { ...purchasePaymentRecord, status: 'PAID' };
        return route.fulfill({ headers: CORS, json: { configured: true, payment: purchasePaymentRecord } });
      }

      if (p.startsWith('/delivery/cloud/marketplace/')) {
        const action = p.split('/').pop();
        if (action === 'catalog') {
          return route.fulfill({
            headers: CORS,
            json: {
              products: [product],
              categories: ['Đồ uống'],
              next: null,
              shop: body && body.shop_id
                ? {
                    id: shopId,
                    name: product.shop_name,
                    description: 'Đặc sản rang xay tại chỗ.',
                    address: '12 Nguyễn Huệ, Quận 1',
                    service_radius_km: 15,
                    banner_url: product.image_url,
                    paused: false,
                    open: true,
                    following: shopFollowing,
                    opening_schedule: [{ day: 1, open: 420, close: 1260 }],
                  }
                : null,
            },
          });
        }
        if (action === 'shop_follow_set') {
          shopFollowing = Boolean(body.enabled);
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'shop_details') {
          return route.fulfill({
            headers: CORS,
            json: {
              shop: { id: shopId, name: product.shop_name, followers: shopFollowing ? 129 : 128 },
              reviews: [],
            },
          });
        }
        if (action === 'favorites') {
          return route.fulfill({ headers: CORS, json: { products: favorite ? [product] : [], next: null } });
        }
        if (action === 'favorite_set') {
          favorite = Boolean(body.enabled);
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'product_details') {
          return route.fulfill({
            headers: CORS,
            json: {
              product,
              variants,
              flash_sale: { id: 'fs-1', sale_price: 49000, allocated_stock: 10, sold_stock: 2 },
              vouchers: [voucher],
              favorite,
              shop_following: shopFollowing,
              shop_followers: shopFollowing ? 129 : 128,
              reviews: productReviewed ? [{ id: 'rev-1', rating: 4, body: 'Cà phê thơm đậm vị.' }] : [],
            },
          });
        }
        if (action === 'vouchers') {
          return route.fulfill({ headers: CORS, json: { vouchers: [voucher] } });
        }
        if (action === 'coins') {
          return route.fulfill({
            headers: CORS,
            json: {
              balance: 1500,
              ledger: [
                { id: 'c-1', kind: 'earn_settlement', delta: 2000, created_at: '2026-10-30T10:00:00Z' },
                { id: 'c-2', kind: 'redeem_checkout', delta: -500, created_at: '2026-10-31T08:00:00Z' },
              ],
            },
          });
        }
        if (action === 'cart_set') {
          cartVersion++;
          cartQty = body.quantity;
          if (body.variant_id) selectedVariantId = body.variant_id;
        }
        if (action === 'cart' || action === 'cart_set') {
          const v = variants.find(x => x.id === selectedVariantId) || variants[0];
          return route.fulfill({
            headers: CORS,
            json: {
              version: cartVersion,
              items: cartQty
                ? [
                    {
                      ...product,
                      product_id: product.id,
                      line_id: 'line-var-l',
                      variant_id: v.id,
                      variant_title: v.title,
                      sku: v.sku,
                      quantity: cartQty,
                      unit_price: v.price + 5000,
                      selected_options: [{ group_id: 'grind', option_id: 'espresso' }],
                      options: [{ group_name: 'Kiểu xay', name: 'Xay pha máy (+5k)', price: 5000 }],
                    },
                  ]
                : [],
            },
          });
        }
        if (action === 'quote') {
          assert.equal(body.voucher_code, 'GHST15K');
          assert.equal(body.use_coins, true);
          assert.equal(body.prefer_ev, true);
          assert.equal(body.require_pod, true);
          assert.equal(body.require_otp, true);
          return route.fulfill({
            headers: CORS,
            json: {
              quote: {
                id: '40000000-0000-0000-0000-000000000201',
                expires_at: new Date(Date.now() + 300000).toISOString(),
                snapshot: {
                  shops: [
                    {
                      shop_name: product.shop_name,
                      items: [{ name: product.name, quantity: cartQty, unit_price: 120000, options: [{ group_name: 'Kiểu xay', name: 'Xay pha máy (+5k)' }] }],
                      subtotal: 120000,
                      voucher_discount: 15000,
                      coin_discount: 1500,
                      payable_subtotal: 103500,
                      shipping_fee: 25000,
                      details: { dropoff_address: addresses[0].full_address },
                    },
                  ],
                  voucher_discount: 15000,
                  coin_discount: 1500,
                  total: 128500,
                },
              },
            },
          });
        }
        if (action === 'checkout') {
          checkoutDone = true;
          cartQty = 0;
          return route.fulfill({
            headers: CORS,
            json: { purchase: { id: purchaseId, total: 128500, payment_status: 'UNPAID' } },
          });
        }
        if (action === 'orders') {
          return route.fulfill({
            headers: CORS,
            json: {
              orders: checkoutDone
                ? [
                    {
                      id: marketOrderId,
                      purchase_id: purchaseId,
                      owner_id: uid,
                      shop_id: shopId,
                      state: 'ready',
                      delivery_id: shipDeliveredId,
                      delivery_status: 'delivered',
                      delivered_at: '2026-10-31T09:30:00Z',
                      payment_method: 'prepaid',
                      payment_status: purchasePaymentRecord?.status === 'PAID' ? 'PAID' : 'UNPAID',
                      tracking_code: 'CL-60000000000000000000000000000203',
                      version: 2,
                      snapshot: {
                        shop_name: product.shop_name,
                        items: [{ product_id: product.id, line_id: 'line-var-l', name: product.name, quantity: 1, unit_price: 120000, options: [] }],
                        subtotal: 120000,
                        payable_subtotal: 103500,
                        shipping_fee: 25000,
                      },
                    },
                  ]
                : [],
              next: null,
            },
          });
        }
        if (action === 'order_services') {
          return route.fulfill({
            headers: CORS,
            json: {
              order: {
                id: marketOrderId,
                owner_id: uid,
                merchant_id: '00000000-0000-0000-0000-000000000301',
                shop_id: shopId,
                delivery_id: shipDeliveredId,
                state: 'ready',
                delivered_at: '2026-10-31T09:30:00Z',
                snapshot: {
                  shop_name: product.shop_name,
                  items: [{ product_id: product.id, line_id: 'line-var-l', name: product.name, quantity: 1, unit_price: 120000, options: [] }],
                  subtotal: 120000,
                  payable_subtotal: 103500,
                  shipping_fee: 25000,
                },
              },
              collected: 128500,
              refunded: 0,
              settled: 0,
              shipments: [{ parcel_no: 1, tracking_code: 'CL-60000000000000000000000000000203', status: 'delivered' }],
              partner_reviews: shopReviewed
                ? [{ id: 'pr-shop-1', target_kind: 'shop', rating: 5, body: 'Đóng gói cực kỳ cẩn thận.', reply: 'Cảm ơn quý khách!' }]
                : [],
              attachments: returnCreated ? [{ scope: 'return', name: 'return-evidence-01.webp' }] : [],
              returns: returnCreated
                ? [
                    {
                      id: 'ret-1',
                      order_id: marketOrderId,
                      product_id: product.id,
                      quantity: 1,
                      reason: 'Bao bì bị móp nhẹ khi vận chuyển',
                      state: 'requested',
                      response: '',
                      attachments: ['return-evidence-01.webp'],
                      version: 1,
                    },
                  ]
                : [],
              reviews: productReviewed ? [{ rating: 4, body: 'Cà phê thơm đậm vị.' }] : [],
              finance: [],
              shares: [],
            },
          });
        }
        if (action === 'reorder') {
          reordered = true;
          cartQty = 1;
          cartVersion++;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'partner_review_save') {
          if (body.target_kind === 'shop') shopReviewed = true;
          if (body.target_kind === 'driver') driverReviewed = true;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'review_save') {
          productReviewed = true;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'return_request') {
          assert.deepEqual(body.attachments, ['return-evidence-01.webp']);
          returnCreated = true;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'notifications' || action === 'notification_read') {
          if (action === 'notification_read') readNotices.add(body.id);
          return route.fulfill({
            headers: CORS,
            json: {
              notifications: [
                { id: 'n-msg', order_id: marketOrderId, kind: 'message', read_at: readNotices.has('n-msg') ? '2026-10-31T10:00:00Z' : null },
              ],
              next: null,
            },
          });
        }
        if (action === 'messages') {
          return route.fulfill({ headers: CORS, json: { messages: chatMessages, next: null } });
        }
        if (action === 'message_send') {
          chatMessages.push({
            id: 'msg-2',
            body: body.body,
            actor_id: uid,
            attachments: body.attachments || [],
          });
          return route.fulfill({ headers: CORS, json: { messages: chatMessages, next: null } });
        }
      }
      return route.fulfill({ status: 403, headers: CORS, json: { error: 'Customer fixture denied: ' + p } });
    });

  const s = await createSession(browser, { width: 1440, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(s.page, { user, token });
    await attachCustomerBackend(s.page);
    await s.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
    await s.enableSemantics();
    await s.fill('Email', user.email);
    await s.fill('Mật khẩu', 'CustomerPass123');
    await s.clickButton('Đăng nhập', { last: true });
    await s.page.getByText('Bạn muốn giao hàng hay đặt món đến đâu?', { exact: true }).waitFor({ timeout: 15000 });
    await s.clickButton('Tải lại trang chủ');
    const zoomIn = s.page.getByText(/^Phóng to \(hoặc cuộn chuột lên\)/).last();
    await zoomIn.scrollIntoViewIfNeeded();
    await zoomIn.click();
    await s.snap(folder, '01-home-and-live-map-1440.png', 'Trang chủ Khách hàng & Bản đồ định vị trực tiếp (Desktop 1440px)', [
      'Tải lại trang chủ',
      'Sổ địa chỉ',
      'Đơn hàng của tôi',
      '6 thẻ dịch vụ vận chuyển & ăn uống',
      'Phóng to / Thu nhỏ bản đồ',
    ]);

    await s.clickNav('Sổ địa chỉ nhận hàng');
    await s.page.getByText('Văn phòng Quận 1 · Mặc định', { exact: true }).waitFor();
    await s.clickButton('Thêm địa chỉ');
    await s.fill('Tên gợi nhớ', 'Nhà riêng Quận 3');
    await s.fill('Tên người nhận', 'Trần Thu Hà');
    await s.fill('Số điện thoại', '0909333444');
    await s.fill('Địa chỉ', '210 Võ Văn Tần, Quận 3, TP.HCM');
    await s.fill('Vĩ độ', '10.776');
    await s.fill('Kinh độ', '106.687');
    await s.snap(folder, '02-address-book-editor-1440.png', 'Form thêm địa chỉ mới trong Sổ địa chỉ Cloud', [
      'Thêm địa chỉ',
      'Tên gợi nhớ',
      'Vĩ độ / Kinh độ',
      'Lưu địa chỉ',
    ]);
    await s.clickButton('Lưu địa chỉ');
    await s.page.getByText('Nhà riêng Quận 3', { exact: true }).waitFor();
    await s.clickButton('Tải lại địa chỉ');
    await s.snap(folder, '03-address-book-saved-1440.png', 'Danh sách Sổ địa chỉ sau khi lưu đồng bộ Cloud', [
      'Tải lại địa chỉ',
      'Sửa địa chỉ',
      'Xóa địa chỉ',
    ]);
    await s.clickBack();

    await s.clickNav('Tạo đơn hàng mới');
    await s.clickButton('Chọn địa chỉ lấy đã lưu');
    await s.page.getByRole('button', { name: 'Chọn địa chỉ', exact: true }).first().click();
    await s.clickButton('Chọn địa chỉ giao đã lưu');
    await s.page.getByRole('button', { name: 'Chọn địa chỉ', exact: true }).last().click();
    await s.fill('Hàng hóa', 'Hộp quà tặng doanh nghiệp');
    await s.fill('Khối lượng (kg)', '2.5');
    await s.fill('Tiền thu hộ (đồng)', '250000');
    await s.clickNav('Tùy chọn nâng cao (Kích thước, Bảo hiểm, Đa điểm dừng, POD/OTP)');
    await s.fill('Dài (cm)', '30');
    await s.fill('Rộng (cm)', '20');
    await s.fill('Cao (cm)', '20');
    await s.fill('Khai giá bảo hiểm (đồng)', '2000000');
    await s.fill('Ghi chú giao hàng', 'Gọi trước 5 phút khi đến sảnh');
    await s.clickNav('Giao khứ hồi (+60% cước)');
    await s.clickNav('Ưu tiên tài xế xe điện (EV)');
    await s.clickNav('Đóng góp Quỹ Xanh (+1.000 đ)');
    await s.clickNav('Yêu cầu ảnh bằng chứng giao hàng (POD)');
    await s.clickNav('Yêu cầu mã OTP 6 số người nhận');
    await s.clickButton('Thêm điểm dừng trung gian (+5.000 đ)');
    await s.fill('Địa chỉ điểm dừng #1', '45 Pasteur, Quận 1, TP.HCM');
    await s.fill('Vĩ độ dừng #1', '10.775');
    await s.fill('Kinh độ dừng #1', '106.701');
    await s.clickButton('Lấy báo giá');
    await s.waitText(/Phụ phí đa điểm dừng:\s*5\.000/);
    assert.equal(advancedQuoteChecked, true);
    await s.page.mouse.move(860, 500);
    await s.page.mouse.wheel(0, 600);
    await s.page.waitForTimeout(200);
    await s.snap(folder, '04-shipping-advanced-quote-1440.png', 'Tạo đơn giao hàng nâng cao (Đa điểm dừng, Kích thước, Bảo hiểm, EV, POD/OTP)', [
      'Chọn địa chỉ lấy/giao đã lưu',
      'Tùy chọn nâng cao',
      'Thêm điểm dừng trung gian (+5.000 đ)',
      'Lấy báo giá',
      'Xác nhận tạo đơn',
    ]);
    await s.clickButton('Xác nhận tạo đơn');

    await s.waitText(/Hộp quà tặng doanh nghiệp/);
    await s.page.getByRole('button', { name: 'Thanh toán cước', exact: true }).first().click();
    await s.clickButton('Tạo liên kết payOS');
    await s.page.getByRole('button', { name: 'Mở thanh toán', exact: true }).waitFor();
    await s.clickButton('Sao chép liên kết');
    await s.snap(folder, '05-shipping-payos-dialog-1440.png', 'Thanh toán cước vận chuyển trực tuyến qua payOS', [
      'Thanh toán cước',
      'Tạo liên kết payOS',
      'Mở thanh toán',
      'Sao chép liên kết',
      'Hủy liên kết',
    ]);
    await s.clickButton('Tải lại');
    await s.page.getByText('Đã thanh toán', { exact: true }).waitFor();
    await s.clickButton('Đóng');

    await s.page.getByRole('button', { name: 'Chi tiết', exact: true }).last().click();
    await s.page.getByText('Chi tiết đơn hàng', { exact: true }).waitFor();
    await s.clickButton('Sao chép mã vận đơn');
    await s.clickButton('Sao chép thông tin đơn');
    await s.clickButton('Mã OTP người nhận');
    await s.waitText('Mã OTP giao hàng người nhận');
    await s.snap(folder, '06-shipping-recipient-otp-1440.png', 'Xem & sao chép Mã OTP 6 số giao hàng người nhận', [
      'Chi tiết',
      'Sao chép mã vận đơn',
      'Mã OTP người nhận',
    ]);
    await s.clickButton('Sao chép');

    await s.clickButton('Chia sẻ hành trình');
    await s.clickButton('Tạo & sao chép liên kết mới');
    await s.waitText(/Hiệu lực đến:/);
    await s.snap(folder, '07-shipping-share-links-1440.png', 'Tạo & quản lý liên kết chia sẻ hành trình đơn giao hàng', [
      'Chia sẻ hành trình',
      'Tạo & sao chép liên kết mới',
      'Thu hồi liên kết',
    ]);
    await s.clickButton('Thu hồi liên kết');
    await s.waitText('Đã thu hồi');
    await s.clickButton('Đóng');

    await s.clickButton('Xem ảnh POD');
    await s.waitText('Ảnh bằng chứng giao hàng (POD)');
    await s.snap(folder, '08-shipping-pod-viewer-1440.png', 'Xem ảnh bằng chứng giao hàng (POD) qua Signed URL', [
      'Xem ảnh POD',
    ]);
    await s.clickButton('Đóng');

    await s.clickButton('Đánh giá tài xế');
    await s.fill('Nhận xét chất lượng phục vụ', 'Tài xế giao đúng hẹn, lịch sự.');
    await s.snap(folder, '09-shipping-rate-driver-1440.png', 'Khách hàng đánh giá tài xế sau khi hoàn tất chuyến giao', [
      'Đánh giá tài xế',
      'Gửi đánh giá',
    ]);
    await s.clickButton('Gửi đánh giá');
    assert.equal(driverReviewed, true);
    await s.clickBack();

    await s.clickNav('Ăn uống & Mua sắm');
    await s.waitText('Combo Cà Phê Đặc Sản Rang Mộc');
    await s.clickNav('Còn hàng');
    await s.clickButton('Khoảng giá');
    await s.fill('Từ (đ)', '30000');
    await s.fill('Đến (đ)', '150000');
    await s.clickButton('Áp dụng');
    await s.clickNav('Cửa hàng Đặc Sản Sài Gòn');
    await s.clickNav('Theo dõi cửa hàng');
    await s.waitText('Đang theo dõi');
    await s.snap(folder, '10-catalog-shop-follow-1440.png', 'Danh mục Ăn uống & Mua sắm, lọc khoảng giá & Theo dõi cửa hàng', [
      'Còn hàng',
      'Khoảng giá',
      'Theo dõi cửa hàng',
      'Đánh giá cửa hàng',
    ]);

    await s.clickButton('Thêm vào giỏ');
    await s.waitText(/FLASH SALE:/);
    await s.clickButton('Yêu thích');
    await s.waitText('Bỏ yêu thích');
    await s.clickNav('Size L 500g');
    await s.clickNav('Xay pha máy (+5k)');
    await s.snap(folder, '11-product-details-sku-flash-1440.png', 'Chi tiết sản phẩm: Flash Sale, Biến thể SKU, Nhóm tùy chọn & Yêu thích', [
      'FLASH SALE',
      'Chọn phân loại SKU',
      'Yêu thích / Bỏ yêu thích',
      'Thêm vào giỏ',
    ]);
    await s.clickButton('Thêm vào giỏ', { last: true });
    await s.waitText('Đã thêm vào giỏ hàng.');
    await s.clickBack();

    await s.clickButton('Giỏ hàng');
    await s.clickButton('Tăng số lượng');
    await s.clickButton('Giảm số lượng');
    await s.clickNav('Trả trước trực tuyến (payOS)');
    await s.clickNav('Vận chuyển, Voucher & Xu thưởng');
    await s.clickButton('Chọn mã');
    await s.waitText('Kho mã giảm giá khả dụng');
    await s.snap(folder, '12-cart-voucher-browser-1440.png', 'Kho mã giảm giá khả dụng ngay trong Giỏ hàng', [
      'Chọn mã',
      'Dùng voucher GHST15K',
    ]);
    await s.clickButton('Dùng');

    await s.clickNav('Đổi Xu thưởng (1500 Xu khả dụng)');
    await s.clickNav('Ưu tiên xe điện (EV)');
    await s.clickNav('Yêu cầu ảnh bằng chứng giao (POD)');
    await s.clickNav('Yêu cầu mã OTP 6 số khi nhận');
    await s.fill('Ghi chú đơn hàng', 'Giao giờ hành chính');
    await s.clickButton('Cập nhật báo giá');
    await s.waitText(/Tổng giảm voucher:\s*-15\.000/);
    await s.waitText(/Tổng đổi Xu:\s*-1\.500/);
    await s.snap(folder, '13-cart-quote-voucher-coins-1440.png', 'Báo giá Giỏ hàng áp dụng Voucher + Xu thưởng + Trả trước payOS + EV/POD/OTP', [
      'Trả trước trực tuyến (payOS)',
      'Đổi Xu thưởng',
      'Cập nhật báo giá',
      'Đặt mua',
    ]);
    await s.clickButton('Đặt mua');
    await s.waitText('Giỏ hàng đang trống.');
    await s.clickBack();

    await s.clickNav('Đơn hàng');
    await s.clickNav('Đơn mua');
    await s.page.getByRole('button', { name: 'Thanh toán trả trước', exact: true }).waitFor();
    await s.clickButton('Thanh toán trả trước');
    await s.clickButton('Tạo liên kết payOS');
    await s.page.getByRole('button', { name: 'Mở thanh toán', exact: true }).waitFor();
    await s.snap(folder, '14-purchase-prepaid-payos-1440.png', 'Thanh toán trả trước payOS cho Đơn mua thương mại điện tử', [
      'Thanh toán trả trước',
      'Tạo liên kết payOS',
    ]);
    await s.clickButton('Tải lại');
    await s.waitText('Đã thanh toán');
    await s.clickButton('Đóng');

    await s.clickButton('Chi tiết và hậu mãi');
    await s.waitText('Trả hàng');
    await s.page.waitForTimeout(300);
    await s.clickButton('Mua lại');
    await s.waitText('Đã thêm sản phẩm vào giỏ theo giá hiện tại.');
    assert.equal(reordered, true);
    await s.clickButton('Đánh giá cửa hàng');
    await s.fill('Nhận xét chất lượng phục vụ', 'Đóng gói cực kỳ cẩn thận.');
    await s.clickButton('Gửi đánh giá');
    await s.clickButton('Đánh giá');
    await s.clickButton('4 sao');
    await s.fill('Nhận xét', 'Cà phê thơm đậm vị.');
    await s.clickButton('Gửi đánh giá');

    await s.clickButton('Trả hàng');
    const retChooser = s.page.waitForEvent('filechooser');
    await s.clickButton('Đính kèm ảnh minh chứng trả hàng');
    await (await retChooser).setFiles({ name: 'return-proof.png', mimeType: 'image/png', buffer: PNG_1X1 });
    await s.waitText(/Đã đính kèm 1 ảnh minh chứng/);
    await s.fill('Lý do', 'Bao bì bị móp nhẹ khi vận chuyển');
    await s.snap(folder, '15-aftersales-return-attachment-1440.png', 'Yêu cầu trả hàng kèm tải ảnh minh chứng bảo mật', [
      'Trả hàng',
      'Đính kèm ảnh minh chứng trả hàng',
      'Xác nhận',
    ]);
    await s.clickButton('Xác nhận');
    await s.waitText(/Trả 1 sản phẩm · Chờ duyệt/);
    await s.snap(folder, '16-aftersales-overview-1440.png', 'Tổng quan Hậu mãi đơn mua: Mua lại, Đánh giá shop/sản phẩm, Trả hàng & Minh chứng', [
      'Mua lại',
      'Đánh giá cửa hàng',
      'Xem ảnh minh chứng',
    ]);
    await s.clickBack();

    await s.clickNav('Trung tâm thông báo');
    await s.clickNav('Tin nhắn mới');
    await s.waitText('Trao đổi đơn hàng');
    const chatChooser = s.page.waitForEvent('filechooser');
    await s.clickButton('Đính kèm ảnh');
    await (await chatChooser).setFiles({ name: 'chat-photo.png', mimeType: 'image/png', buffer: PNG_1X1 });
    await s.waitText('Đã chọn 1 ảnh đính kèm');
    await s.fill('Tin nhắn', 'Mình gửi ảnh kiện hàng vừa nhận nhé.');
    await s.clickButton('Gửi tin nhắn');
    await s.waitText('Xem ảnh đính kèm');
    await s.clickNav('Xem ảnh đính kèm');
    await s.waitText('Tệp đính kèm bảo mật');
    await s.snap(folder, '17-order-chat-attachment-1440.png', 'Trao đổi đơn hàng thời gian thực kèm gửi/xem ảnh đính kèm bảo mật', [
      'Đính kèm ảnh',
      'Gửi tin nhắn',
      'Xem ảnh đính kèm',
    ]);
    await s.clickButton('Đóng');
    await s.clickBack();

    await s.clickNav('Hồ sơ cá nhân');
    await s.waitText('Sổ địa chỉ');
    await s.clickNav('Ví Xu thưởng');
    await s.waitText('Ví Xu thưởng GHST');
    await s.snap(folder, '18-account-coin-wallet-1440.png', 'Ví Xu thưởng GHST & lịch sử biến động sổ cái Xu', [
      'Ví Xu thưởng',
      'Số dư & lịch sử tích/đổi Xu',
    ]);
    await s.clickButton('Đóng');

    await s.clickNav('Sản phẩm yêu thích');
    await s.waitText('Combo Cà Phê Đặc Sản Rang Mộc');
    await s.clickBack();

    await s.clickButton('Hồ sơ cá nhân', { last: true });
    await s.waitText('Đăng ký đối tác');
    await s.page.getByRole('button', { name: 'Đăng ký', exact: true }).first().click();
    await s.waitText('Chờ duyệt');
    assert.equal(requestedMembership, true);
    await s.snap(folder, '19-account-partner-registration-1440.png', 'Hồ sơ cá nhân & Đăng ký đối tác Cửa hàng / Tài xế Cloud', [
      'Hồ sơ cá nhân',
      'Đăng ký đối tác (Cửa hàng / Tài xế)',
    ]);
    await s.clickBack();

    await s.clickNav('Nhập địa chỉ từ thiết bị');
    await s.fill('Tài khoản trên thiết bị', '0909111222');
    await s.fill('Mật khẩu trên thiết bị', 'LegacyPass123');
    await s.clickButton('Xác minh nguồn');
    await s.snap(folder, '20-account-local-import-1440.png', 'Công cụ Nhập địa chỉ từ thiết bị cục bộ lên tài khoản Cloud', [
      'Nhập địa chỉ từ thiết bị',
      'Xác minh nguồn',
    ]);
  } finally {
    await s.context.close();
  }

  const m360 = await createSession(browser, { width: 360, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(m360.page, { user, token });
    await attachCustomerBackend(m360.page);
    await m360.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
    await m360.enableSemantics();
    await m360.fill('Email', user.email);
    await m360.fill('Mật khẩu', 'CustomerPass123');
    await m360.clickButton('Đăng nhập', { last: true });
    await m360.page.getByText('Bạn muốn giao hàng hay đặt món đến đâu?', { exact: true }).waitFor({ timeout: 15000 });
    await m360.snap(folder, '21-customer-home-mobile-360.png', 'Trang chủ Khách hàng & Thanh điều hướng đáy trên Mobile 360px', [
      'Bottom Navigation 5 tab Mobile 360px',
    ]);
  } finally {
    await m360.context.close();
  }
}

async function runSuite03Merchant(browser, acceptanceRoot, gallery) {
  const folder = '03-merchant';
  const uid = '00000000-0000-0000-0000-000000000301';
  const user = makeUser(uid, 'merchant-check@example.com');
  const token = makeJwt(uid);
  const shopId = '20000000-0000-0000-0000-000000000301';
  const productId = '10000000-0000-0000-0000-000000000301';
  const mOrderId = '60000000-0000-0000-0000-000000000301';

  const shop = {
    id: shopId,
    owner_id: uid,
    name: 'Bếp Nhà Phố Cổ',
    description: 'Món ngon chuẩn vị truyền thống',
    address: '18 Hàng Bài, Quận 1, TP.HCM',
    latitude: 10.775,
    longitude: 106.702,
    service_radius_km: 12,
    banner_url: '',
    paused: false,
    status: 'active',
    version: 1,
    opening_schedule: [],
    open: true,
  };
  const product = {
    id: productId,
    shop_id: shopId,
    shop_name: shop.name,
    name: 'Set Bún Chả Hà Nội Đặc Biệt',
    description: 'Đầy đủ chả nướng than hoa và nem cua bể.',
    sku: 'BC-SET01',
    category: 'Món chính',
    price: 75000,
    stock: 25,
    weight_kg: 0.8,
    image_url: '',
    images: [],
    published: true,
    shop_status: 'active',
    paused: false,
    available: true,
    preparation_minutes: 15,
    option_groups: [],
    sale_schedule: [],
    variants: [],
    version: 1,
  };
  let staffList = [];
  let orderState = 'pending';
  let orderVersion = 1;
  let shipments = [];
  let voucherSaved = false;
  let flashSaved = false;
  let reviewReplyText = '';
  let returnState = 'requested';
  let returnDisposition = null;
  let settlementRequested = false;

  const attachMerchantBackend = page =>
    page.route('http://127.0.0.1:8787/**', route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
      const u = new URL(req.url());
      const body = req.method() === 'POST' ? req.postDataJSON() : null;
      const p = u.pathname;

      if (p === '/delivery/cloud/profile') {
        return route.fulfill({
          headers: CORS,
          json: {
            schema_version: 3,
            operator: false,
            account: {
              user_id: uid,
              full_name: 'Chủ Quán Phố Cổ',
              phone: '0903111222',
              role: 'merchant',
              blocked: false,
              requested_role: null,
              coin_balance: 500,
              approved_roles: ['merchant'],
              staff_shops: [],
              memberships: [{ role: 'merchant', state: 'active', version: 2, reason: '' }],
            },
          },
        });
      }
      if (p === '/delivery/cloud/addresses') return route.fulfill({ headers: CORS, json: { addresses: [] } });
      if (p === '/delivery/cloud/orders') return route.fulfill({ headers: CORS, json: { orders: [], schema_version: 3 } });
      if (p === '/delivery/cloud/media') {
        return route.fulfill({
          headers: CORS,
          json: { image_url: 'https://yvnbfurazjbhbopahtmx.supabase.co/storage/v1/object/public/delivery-market-media/merchant.webp' },
        });
      }
      if (p.startsWith('/delivery/cloud/marketplace/')) {
        const action = p.split('/').pop();
        if (action === 'catalog') {
          return route.fulfill({ headers: CORS, json: { products: [product], categories: ['Món chính'], next: null } });
        }
        if (action === 'workspace') {
          return route.fulfill({ headers: CORS, json: { shops: [shop], products: [product], staff: staffList, next: null } });
        }
        if (action === 'shop_save') {
          Object.assign(shop, body, { version: shop.version + 1 });
          return route.fulfill({ headers: CORS, json: { shop } });
        }
        if (action === 'product_save') {
          Object.assign(product, body, { version: product.version + 1 });
          return route.fulfill({ headers: CORS, json: { product } });
        }
        if (action === 'variant_save') {
          const saved = { id: 'var-new-1', version: 1, ...body };
          product.variants = [...(product.variants || []), saved];
          return route.fulfill({ headers: CORS, json: { variant: saved } });
        }
        if (action === 'voucher_save') {
          assert.equal(body.shop_id, shopId);
          voucherSaved = true;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'flash_sale_save') {
          assert.equal(body.product_id, productId);
          flashSaved = true;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'staff_save') {
          if (body.active === false) {
            staffList = [];
          } else {
            staffList = [
              { shop_id: shopId, user_id: '00000000-0000-0000-0000-000000000401', full_name: 'Phạm Nhân Viên', phone: '0987654321', role: body.role },
            ];
          }
          return route.fulfill({ headers: CORS, json: { staff: staffList } });
        }
        if (action === 'orders') {
          return route.fulfill({
            headers: CORS,
            json: {
              orders: [
                {
                  id: mOrderId,
                  shop_id: shopId,
                  merchant_id: uid,
                  owner_id: '00000000-0000-0000-0000-000000000201',
                  state: orderState,
                  delivery_status: orderState === 'ready' ? 'searching' : null,
                  delivered_at: '2026-10-31T10:30:00Z',
                  payment_method: 'cod',
                  payment_status: 'UNPAID',
                  version: orderVersion,
                  shipments,
                  snapshot: {
                    shop_name: shop.name,
                    items: [{ product_id: productId, name: product.name, quantity: 2, unit_price: 75000, options: [] }],
                    subtotal: 150000,
                    payable_subtotal: 150000,
                    shipping_fee: 25000,
                  },
                },
              ],
              next: null,
            },
          });
        }
        if (action === 'order_action') {
          orderState = body.action === 'accept' ? 'accepted' : 'ready';
          orderVersion++;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'order_shipment_split') {
          assert.equal(body.parcels.length, 2);
          orderState = 'ready';
          orderVersion++;
          shipments = [
            { parcel_no: 1, tracking_code: 'CL-60000000000000000000000000000311', status: 'searching' },
            { parcel_no: 2, tracking_code: 'CL-60000000000000000000000000000312', status: 'searching' },
          ];
          return route.fulfill({ headers: CORS, json: { ok: true, shipments } });
        }
        if (action === 'order_services') {
          return route.fulfill({
            headers: CORS,
            json: {
              order: {
                id: mOrderId,
                owner_id: '00000000-0000-0000-0000-000000000201',
                merchant_id: uid,
                shop_id: shopId,
                state: 'ready',
                delivered_at: '2026-10-31T10:30:00Z',
                snapshot: {
                  shop_name: shop.name,
                  items: [{ product_id: productId, name: product.name, quantity: 2, unit_price: 75000, options: [] }],
                  subtotal: 150000,
                  payable_subtotal: 150000,
                  shipping_fee: 25000,
                },
              },
              collected: 175000,
              refunded: 0,
              settled: 0,
              shipments,
              partner_reviews: [
                { id: 'pr-m-1', target_kind: 'shop', rating: 5, body: 'Bún chả nóng hổi rất ngon!', reply: reviewReplyText },
              ],
              returns: [
                {
                  id: 'ret-m-1',
                  order_id: mOrderId,
                  product_id: productId,
                  quantity: 1,
                  reason: 'Thiếu 1 phần nem cua bể',
                  state: returnState,
                  disposition: returnDisposition,
                  return_delivery_id: returnState !== 'requested' ? 'CL-RET-000301' : null,
                  response: returnState !== 'requested' ? 'Shop đồng ý nhận hoàn và bù hàng' : '',
                  version: returnState === 'requested' ? 1 : 2,
                },
              ],
              finance: settlementRequested
                ? [{ id: 'fin-m-1', order_id: mOrderId, kind: 'settlement', amount: 135000, state: 'requested', version: 1 }]
                : [],
            },
          });
        }
        if (action === 'review_reply') {
          reviewReplyText = body.reply;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'return_action') {
          if (body.action === 'approve') {
            assert.equal(body.create_return_shipment, true);
            returnState = 'approved';
          } else if (body.action === 'receive') {
            returnState = 'received';
            returnDisposition = body.disposition;
          }
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        if (action === 'finance_request') {
          assert.equal(body.kind, 'settlement');
          settlementRequested = true;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
      }
      return route.fulfill({ status: 403, headers: CORS, json: { error: 'Merchant fixture denied: ' + p } });
    });

  const s = await createSession(browser, { width: 1440, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(s.page, { user, token });
    await attachMerchantBackend(s.page);
    await s.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
    await s.enableSemantics();
    await s.fill('Email', user.email);
    await s.fill('Mật khẩu', 'MerchantPass123');
    await s.clickButton('Đăng nhập', { last: true });
    await s.waitText('Bạn muốn giao hàng hay đặt món đến đâu?');

    await s.clickNav('Cửa hàng của tôi');
    await s.waitText('Bếp Nhà Phố Cổ');
    await s.snap(folder, '01-merchant-workspace-1440.png', 'Không gian Cửa hàng của tôi (Chủ cửa hàng Merchant 1440px)', [
      'Sửa cửa hàng',
      'Thêm sản phẩm',
      'Voucher shop',
      'Flash Sale',
      'Nhân sự',
      'Biến thể SKU',
    ]);

    await s.clickButton('Sửa cửa hàng');
    await s.fill('Bán kính phục vụ tối đa (km, 0 = không giới hạn)', '15');
    const bannerChooser = s.page.waitForEvent('filechooser');
    await s.clickButton('Tải ảnh bìa cửa hàng');
    await (await bannerChooser).setFiles({ name: 'banner.png', mimeType: 'image/png', buffer: PNG_1X1 });
    await s.clickButton('Thêm khung giờ');
    await s.clickButton('Lưu', { last: true });
    await s.snap(folder, '02-merchant-shop-editor-1440.png', 'Chỉnh sửa thông tin cửa hàng: Bán kính phục vụ, Ảnh bìa & Giờ mở cửa', [
      'Bán kính phục vụ tối đa',
      'Tải ảnh bìa cửa hàng',
      'Thêm khung giờ',
      'Lưu',
    ]);
    await s.clickButton('Lưu');
    await s.page.getByRole('button', { name: 'Thêm sản phẩm', exact: true }).waitFor();

    await s.clickButton('Sửa sản phẩm');
    const prodChooser = s.page.waitForEvent('filechooser');
    await s.clickButton('Chọn ảnh');
    await (await prodChooser).setFiles({ name: 'buncha.png', mimeType: 'image/png', buffer: PNG_1X1 });
    await s.page.getByRole('button', { name: 'Bỏ ảnh', exact: true }).waitFor();
    await s.fill('Giá bán (đ)', '79000');
    await s.fill('Dài (cm)', '22');
    await s.fill('Rộng (cm)', '18');
    await s.fill('Cao (cm)', '12');
    await s.snap(folder, '03-merchant-product-editor-1440.png', 'Chỉnh sửa sản phẩm: Ảnh Cloud, Giá bán, Kích thước kiện (Dài/Rộng/Cao)', [
      'Chọn ảnh / Bỏ ảnh',
      'Giá bán (đ)',
      'Dài / Rộng / Cao (cm)',
      'Lưu',
    ]);
    await s.clickButton('Lưu');
    await s.page.getByRole('button', { name: 'Thêm sản phẩm', exact: true }).waitFor();

    await s.clickButton('Biến thể SKU');
    await s.fill('Mã SKU', 'BC-JUMBO');
    await s.fill('Tên biến thể (VD: Size L)', 'Phần Đặc Biệt 2 Người');
    await s.fill('Giá (đ)', '145000');
    await s.fill('Tồn kho', '15');
    await s.clickButton('Thêm SKU');
    await s.waitText(/Phần Đặc Biệt 2 Người/);
    await s.snap(folder, '04-merchant-sku-variants-1440.png', 'Quản lý Biến thể SKU (giá, tồn kho, khối lượng riêng)', [
      'Biến thể SKU',
      'Thêm SKU',
      'Sửa biến thể',
    ]);
    await s.clickButton('Đóng');

    await s.clickButton('Voucher shop');
    await s.fill('Mã voucher', 'PHOCO20K');
    await s.fill('Tên chương trình', 'Ưu đãi Bếp Phố Cổ 20k');
    await s.snap(folder, '05-merchant-voucher-dialog-1440.png', 'Tạo mã giảm giá riêng của cửa hàng (Voucher shop)', [
      'Voucher shop',
      'Lưu voucher',
    ]);
    await s.clickButton('Lưu voucher');
    assert.equal(voucherSaved, true);

    await s.clickButton('Flash Sale');
    await s.fill('Giá Flash Sale (đ)', '59000');
    await s.snap(folder, '06-merchant-flash-sale-1440.png', 'Thiết lập chương trình Flash Sale theo khung giờ và số suất', [
      'Flash Sale',
      'Lưu Flash Sale',
    ]);
    await s.clickButton('Lưu Flash Sale');
    assert.equal(flashSaved, true);

    await s.clickButton('Nhân sự');
    await s.fill('Số điện thoại hoặc UUID tài khoản cloud', '0987654321');
    await s.clickButton('Cấp quyền nhân sự');
    await s.waitText(/Phạm Nhân Viên/);
    await s.snap(folder, '07-merchant-staff-delegation-1440.png', 'Phân quyền & Thu hồi Nhân sự cửa hàng (Nhân viên / Quản lý)', [
      'Nhân sự',
      'Cấp quyền nhân sự',
      'Thu hồi quyền',
    ]);
    await s.clickButton('Thu hồi quyền');
    await s.waitText('Chưa có nhân viên được phân quyền.');
    await s.clickButton('Đóng');

    await s.clickNav('Đơn của cửa hàng');
    await s.clickButton('Xác nhận đơn');
    await s.page.getByRole('button', { name: 'Tách kiện giao', exact: true }).waitFor();
    await s.clickButton('Tách kiện giao');
    await s.waitText('Tách kiện vận chuyển');
    await s.snap(folder, '08-merchant-split-parcel-dialog-1440.png', 'Hộp thoại Tách kiện vận chuyển nhiều bưu kiện cho 1 đơn mua', [
      'Xác nhận đơn',
      'Tách kiện giao',
      'Tạo vận đơn tách kiện',
    ]);
    await s.clickButton('Tạo vận đơn tách kiện');
    await s.page.getByRole('button', { name: 'Tách kiện giao', exact: true }).waitFor({ state: 'hidden' });
    await s.waitText('Chờ nhận chuyến');
    assert.equal(shipments.length, 2);
    await s.snap(folder, '09-merchant-orders-multi-parcel-1440.png', 'Đơn của cửa hàng sau khi tách thành 2 mã vận đơn độc lập', [
      'Hiển thị đa kiện #1, #2',
      'Chi tiết và hậu mãi',
      'Trao đổi',
    ]);

    await s.clickButton('Chi tiết và hậu mãi');
    await s.waitText('Chấp nhận trả');
    await s.page.waitForTimeout(300);
    await s.clickButton('Phản hồi đánh giá shop');
    await s.fill('Nội dung phản hồi', 'Cảm ơn bạn đã ủng hộ Bếp Nhà Phố Cổ!');
    await s.clickButton('Gửi phản hồi');
    await s.waitText(/Phản hồi: Cảm ơn bạn đã ủng hộ Bếp Nhà Phố Cổ!/);

    await s.clickButton('Chấp nhận trả');
    await s.fill('Phản hồi / lý do', 'Shop đồng ý nhận hoàn và bù hàng');
    await s.clickNav('Tạo vận đơn thu hồi hàng trả (reverse logistics)');
    await s.clickButton('Xác nhận');
    await s.page.getByRole('button', { name: 'Đã nhận hàng trả', exact: true }).waitFor();

    await s.clickButton('Đã nhận hàng trả');
    await s.fill('Phản hồi / lý do', 'Đã kiểm tra và nhập lại kho');
    await s.clickButton('Xác nhận');
    await s.waitText(/Đã nhập lại kho/);

    await s.clickButton('Đề nghị trả tiền shop');
    await s.fill('Số tiền (VND)', '135000');
    await s.fill('Lý do', 'Đối soát doanh thu đơn hoàn tất');
    await s.fill('Mã chứng từ / tham chiếu', 'SETTLE-301');
    await s.clickButton('Xác nhận');
    await s.waitText(/Trả tiền shop · 135\.000/);
    await s.snap(folder, '10-merchant-aftersales-settlement-1440.png', 'Hậu mãi phía Cửa hàng: Phản hồi đánh giá, Reverse Logistics, Nhập kho & Đề nghị đối soát', [
      'Phản hồi đánh giá shop',
      'Chấp nhận trả (reverse logistics)',
      'Đã nhận hàng trả (nhập kho)',
      'Đề nghị trả tiền shop',
    ]);
  } finally {
    await s.context.close();
  }

  const m360 = await createSession(browser, { width: 360, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(m360.page, { user, token });
    await attachMerchantBackend(m360.page);
    await m360.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
    await m360.enableSemantics();
    await m360.fill('Email', user.email);
    await m360.fill('Mật khẩu', 'MerchantPass123');
    await m360.clickButton('Đăng nhập', { last: true });
    await m360.waitText('Bạn muốn giao hàng hay đặt món đến đâu?');
    await m360.clickNav('Hồ sơ');
    await m360.waitText('Sổ địa chỉ');
    await m360.clickNav('Cửa hàng của tôi');
    await m360.waitText('Bếp Nhà Phố Cổ');
    await m360.snap(folder, '11-merchant-workspace-mobile-360.png', 'Quản trị Cửa hàng của tôi trên Mobile 360px', [
      'Merchant Mobile 360px',
    ]);
  } finally {
    await m360.context.close();
  }
}

async function runSuite04ShopStaff(browser, acceptanceRoot, gallery) {
  const folder = '04-shop-staff';
  const shopId = '20000000-0000-0000-0000-000000000401';
  const ownerId = '00000000-0000-0000-0000-000000000399';
  const orderId = '60000000-0000-0000-0000-000000000401';

  for (const staffRole of ['staff', 'manager']) {
    const uid = staffRole === 'staff' ? '00000000-0000-0000-0000-000000000401' : '00000000-0000-0000-0000-000000000402';
    const user = makeUser(uid, `${staffRole}-check@example.com`);
    const token = makeJwt(uid);
    let orderState = 'pending';
    let orderVersion = 1;

    const s = await createSession(browser, { width: 1440, acceptanceRoot, gallery });
    try {
      await attachSupabaseAuth(s.page, { user, token });
      await s.page.route('http://127.0.0.1:8787/**', route => {
        const req = route.request();
        if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
        const u = new URL(req.url());
        const body = req.method() === 'POST' ? req.postDataJSON() : null;
        if (u.pathname === '/delivery/cloud/profile') {
          return route.fulfill({
            headers: CORS,
            json: {
              schema_version: 3,
              operator: false,
              account: {
                user_id: uid,
                full_name: staffRole === 'staff' ? 'Nhân Viên Xử Lý Đơn' : 'Quản Lý Cửa Hàng',
                phone: '0904111222',
                role: 'customer',
                blocked: false,
                requested_role: null,
                coin_balance: 0,
                approved_roles: [],
                staff_shops: [{ shop_id: shopId, shop_name: 'Tiệm Trà Thảo Mộc', role: staffRole }],
                memberships: [],
              },
            },
          });
        }
        if (u.pathname === '/delivery/cloud/addresses') return route.fulfill({ headers: CORS, json: { addresses: [] } });
        if (u.pathname === '/delivery/cloud/orders') return route.fulfill({ headers: CORS, json: { orders: [], schema_version: 3 } });
        if (u.pathname === '/delivery/cloud/marketplace/catalog') {
          return route.fulfill({ headers: CORS, json: { products: [], categories: [], next: null } });
        }
        if (u.pathname === '/delivery/cloud/marketplace/workspace') {
          return route.fulfill({
            headers: CORS,
            json: {
              shops: [{ id: shopId, owner_id: ownerId, name: 'Tiệm Trà Thảo Mộc', address: '55 Lý Tự Trọng', status: 'active', paused: false, version: 1 }],
              products: [{ id: 'prod-401', shop_id: shopId, name: 'Trà Hoa Cúc Mật Ong', sku: 'TEA-01', price: 45000, stock: 20, published: true, version: 1 }],
              staff: [],
              next: null,
            },
          });
        }
        if (u.pathname === '/delivery/cloud/marketplace/orders') {
          return route.fulfill({
            headers: CORS,
            json: {
              orders: [
                {
                  id: orderId,
                  shop_id: shopId,
                  state: orderState,
                  delivery_status: orderState === 'ready' ? 'searching' : null,
                  version: orderVersion,
                  payment_status: 'UNPAID',
                  snapshot: {
                    shop_name: 'Tiệm Trà Thảo Mộc',
                    items: [{ product_id: 'prod-401', name: 'Trà Hoa Cúc Mật Ong', quantity: 1, unit_price: 45000, options: [] }],
                    subtotal: 45000,
                    shipping_fee: 18000,
                  },
                },
              ],
              next: null,
            },
          });
        }
        if (u.pathname === '/delivery/cloud/marketplace/order_action') {
          orderState = body.action === 'accept' ? 'accepted' : 'ready';
          orderVersion++;
          return route.fulfill({ headers: CORS, json: { ok: true } });
        }
        return route.fulfill({ status: 403, headers: CORS, json: { error: 'Staff fixture denied' } });
      });

      await s.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
      await s.enableSemantics();
      await s.fill('Email', user.email);
      await s.fill('Mật khẩu', 'StaffPass123');
      await s.clickButton('Đăng nhập', { last: true });
      await s.waitText('Bạn muốn giao hàng hay đặt món đến đâu?');

      await s.clickNav('Cửa hàng của tôi');
      await s.waitText('Tiệm Trà Thảo Mộc');
      assert.equal(await s.page.getByRole('button', { name: 'Nhân sự', exact: true }).count(), 0);

      if (staffRole === 'staff') {
        assert.equal(await s.page.getByRole('button', { name: 'Sửa cửa hàng', exact: true }).isDisabled(), true);
        assert.equal(await s.page.getByRole('button', { name: 'Thêm sản phẩm', exact: true }).isDisabled(), true);
        assert.equal(await s.page.getByRole('button', { name: 'Voucher shop', exact: true }).count(), 0);
        assert.equal(await s.page.getByRole('button', { name: 'Flash Sale', exact: true }).count(), 0);
        await s.snap(folder, '01-shop-staff-readonly-workspace-1440.png', 'Phân quyền Nhân viên (staff): Khóa sửa cửa hàng/sản phẩm & ẩn Nhân sự/Khuyến mãi', [
          'Sửa cửa hàng (disabled)',
          'Thêm sản phẩm (disabled)',
          'Ẩn Nhân sự / Voucher / Flash Sale',
        ]);

        await s.clickNav('Đơn của cửa hàng');
        await s.clickButton('Xác nhận đơn');
        await s.page.getByRole('button', { name: 'Sẵn sàng giao', exact: true }).waitFor();
        assert.equal(await s.page.getByRole('button', { name: 'Tách kiện giao', exact: true }).count(), 0);
        await s.clickButton('Sẵn sàng giao');
        await s.waitText('Chờ nhận chuyến');
        await s.snap(folder, '02-shop-staff-order-ready-1440.png', 'Nhân viên cửa hàng (staff) xác nhận & bàn giao đơn (ẩn Tách kiện)', [
          'Xác nhận đơn',
          'Sẵn sàng giao',
          'Ẩn Tách kiện giao',
        ]);
      } else {
        assert.equal(await s.page.getByRole('button', { name: 'Sửa cửa hàng', exact: true }).isDisabled(), false);
        assert.equal(await s.page.getByRole('button', { name: 'Thêm sản phẩm', exact: true }).isDisabled(), false);
        assert.equal(await s.page.getByRole('button', { name: 'Voucher shop', exact: true }).count(), 1);
        assert.equal(await s.page.getByRole('button', { name: 'Flash Sale', exact: true }).count(), 1);
        await s.snap(folder, '03-shop-manager-workspace-1440.png', 'Phân quyền Quản lý (manager): Mở quản trị sản phẩm/voucher/SKU nhưng vẫn ẩn Nhân sự chủ shop', [
          'Sửa cửa hàng (enabled)',
          'Thêm sản phẩm / Voucher / Flash Sale (enabled)',
          'Ẩn Nhân sự (chỉ chủ shop)',
        ]);

        await s.clickNav('Đơn của cửa hàng');
        await s.clickButton('Xác nhận đơn');
        await s.page.getByRole('button', { name: 'Tách kiện giao', exact: true }).waitFor();
        await s.snap(folder, '04-shop-manager-split-enabled-1440.png', 'Quản lý cửa hàng (manager) được phép sử dụng Tách kiện giao', [
          'Tách kiện giao (enabled cho manager)',
        ]);
      }
    } finally {
      await s.context.close();
    }
  }
}

async function runSuite05Driver(browser, acceptanceRoot, gallery) {
  const folder = '05-driver';
  const uid = '00000000-0000-0000-0000-000000000501';
  const user = makeUser(uid, 'driver-check@example.com');
  const token = makeJwt(uid);
  const trip1Id = '60000000-0000-0000-0000-000000000501';
  const trip2Id = '60000000-0000-0000-0000-000000000502';

  const trip1 = {
    id: trip1Id,
    tracking_code: 'CL-60000000000000000000000000000501',
    status: 'searching',
    merchant_ready: true,
    version: 1,
    shipping_fee: 28000,
    cod_amount: 120000,
    owner_id: '00000000-0000-0000-0000-000000000201',
    driver_id: null,
    pod_photo_path: '',
    created_at: '2026-10-31T08:00:00Z',
    details: {
      pickup_address: '12 Nguyễn Huệ, Quận 1',
      dropoff_address: '88 Hai Bà Trưng, Quận 1',
      pickup_lat: 10.774,
      pickup_lng: 106.703,
      dropoff_lat: 10.781,
      dropoff_lng: 106.699,
      recipient_name: 'Phạm Quốc Bảo',
      recipient_phone: '0912999888',
      package_description: 'Linh kiện điện tử cần OTP & POD',
      weight_kg: 1.2,
      service_type: 'express',
      payment_method: 'sender_cash',
      require_pod: true,
      require_otp: true,
    },
  };
  const trip2 = {
    id: trip2Id,
    tracking_code: 'CL-60000000000000000000000000000502',
    status: 'inTransit',
    merchant_ready: true,
    version: 3,
    shipping_fee: 22000,
    cod_amount: 0,
    owner_id: '00000000-0000-0000-0000-000000000202',
    driver_id: uid,
    pod_photo_path: '',
    created_at: '2026-10-31T08:30:00Z',
    details: {
      pickup_address: '100 Điện Biên Phủ, Quận 3',
      dropoff_address: '250 Cách Mạng Tháng 8, Quận 3',
      pickup_lat: 10.785,
      pickup_lng: 106.692,
      dropoff_lat: 10.779,
      dropoff_lng: 106.685,
      recipient_name: 'Đỗ Thanh Tùng',
      recipient_phone: '0908777666',
      package_description: 'Bưu phẩm hoàn trả khi vắng mặt',
      weight_kg: 0.8,
      service_type: 'standard',
      payment_method: 'sender_cash',
    },
  };
  let podUploaded = false;

  const attachDriverBackend = page =>
    page.route('http://127.0.0.1:8787/**', route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
      const u = new URL(req.url());
      const body = req.method() === 'POST' ? req.postDataJSON() : null;
      const p = u.pathname;

      if (p === '/delivery/cloud/profile') {
        return route.fulfill({
          headers: CORS,
          json: {
            schema_version: 3,
            operator: false,
            account: {
              user_id: uid,
              full_name: 'Tài Xế Lê Văn Hùng',
              phone: '0905111222',
              role: 'driver',
              blocked: false,
              requested_role: null,
              coin_balance: 0,
              approved_roles: ['driver'],
              staff_shops: [],
              memberships: [{ role: 'driver', state: 'active', version: 2, reason: '' }],
            },
          },
        });
      }
      if (p === '/delivery/cloud/addresses') return route.fulfill({ headers: CORS, json: { addresses: [] } });
      if (p === '/delivery/cloud/merchants') return route.fulfill({ headers: CORS, json: { merchants: [] } });
      if (p === '/delivery/cloud/marketplace/catalog') {
        return route.fulfill({ headers: CORS, json: { products: [], categories: [], next: null } });
      }
      if (p === '/delivery/cloud/pod') {
        assert.equal(body.tracking_code, trip1.tracking_code);
        podUploaded = true;
        trip1.pod_photo_path = `pod/${trip1.tracking_code}/pod.webp`;
        return route.fulfill({ headers: CORS, json: { path: trip1.pod_photo_path } });
      }
      if (p === '/delivery/cloud/orders') {
        const isQueue = u.searchParams.get('queue') === 'true';
        const list = isQueue
          ? [trip1].filter(t => t.status === 'searching')
          : [trip1, trip2].filter(t => t.driver_id === uid);
        return route.fulfill({ headers: CORS, json: { orders: list, schema_version: 3 } });
      }
      if (p === `/delivery/cloud/orders/${trip1Id}/transition`) {
        if (body.action === 'claim') {
          trip1.status = 'accepted';
          trip1.driver_id = uid;
        } else if (body.action === 'arrive') trip1.status = 'arrivingPickup';
        else if (body.action === 'pickup') trip1.status = 'inTransit';
        else if (body.action === 'deliver') {
          assert.equal(podUploaded, true);
          assert.equal(body.reason, '654321');
          trip1.status = 'delivered';
        }
        trip1.version++;
        return route.fulfill({ headers: CORS, json: { order: trip1 } });
      }
      if (p === `/delivery/cloud/orders/${trip2Id}/transition`) {
        if (body.action === 'fail') trip2.status = 'failed';
        else if (body.action === 'retry') trip2.status = 'inTransit';
        else if (body.action === 'return') trip2.status = 'returning';
        else if (body.action === 'complete_return') trip2.status = 'returned';
        trip2.version++;
        return route.fulfill({ headers: CORS, json: { order: trip2 } });
      }
      return route.fulfill({ status: 403, headers: CORS, json: { error: 'Driver fixture denied: ' + p } });
    });

  const s = await createSession(browser, { width: 1440, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(s.page, { user, token });
    await attachDriverBackend(s.page);
    await s.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
    await s.enableSemantics();
    await s.fill('Email', user.email);
    await s.fill('Mật khẩu', 'DriverPass123');
    await s.clickButton('Đăng nhập', { last: true });
    await s.waitText('Bạn muốn giao hàng hay đặt món đến đâu?');

    await s.clickNav('Chuyến giao của tôi');
    await s.clickNav('Chờ nhận');
    await s.page.getByRole('button', { name: 'Nhận chuyến', exact: true }).waitFor();
    await s.snap(folder, '01-driver-queue-claim-1440.png', 'Hàng đợi Chờ nhận chuyến của Tài xế (Desktop Sidebar -> Chuyến giao của tôi)', [
      'Chuyến giao của tôi',
      'Chờ nhận',
      'Nhận chuyến',
    ]);
    await s.clickButton('Nhận chuyến');

    await s.clickNav('Chuyến của tôi');
    await s.clickButton('Đã đến lấy hàng');
    await s.clickButton('Đã lấy hàng');
    await s.page.getByRole('button', { name: 'Giao thành công', exact: true }).first().click();
    await s.waitText('Xác thực giao hàng (POD / OTP)');
    const podChooser = s.page.waitForEvent('filechooser');
    await s.clickButton('Tải ảnh bằng chứng giao hàng (POD)');
    await (await podChooser).setFiles({ name: 'pod.png', mimeType: 'image/png', buffer: PNG_1X1 });
    await s.waitText(/Đã tải lên ảnh POD/);
    await s.fill('Mã OTP 6 số từ người nhận', '654321');
    await s.snap(folder, '02-driver-pod-otp-dialog-1440.png', 'Tài xế tải ảnh bằng chứng POD & xác thực OTP 6 số người nhận khi giao', [
      'Đã đến lấy hàng',
      'Đã lấy hàng',
      'Giao thành công',
      'Tải ảnh bằng chứng giao hàng (POD)',
      'Mã OTP 6 số từ người nhận',
    ]);
    await s.clickButton('Đã giao');
    await s.waitText('Đã giao');

    await s.clickButton('Giao thất bại');
    await s.fill('Lý do', 'Khách hẹn giao lại sau 30 phút');
    await s.clickButton('Xác nhận');
    await s.page.getByRole('button', { name: 'Giao lại', exact: true }).waitFor();
    await s.snap(folder, '03-driver-failed-retry-options-1440.png', ' Xử lý Giao thất bại: Hiển thị nút Giao lại hoặc Hoàn hàng', [
      'Giao thất bại',
      'Giao lại',
      'Hoàn hàng',
    ]);

    await s.clickButton('Giao lại');
    await s.clickButton('Giao thất bại');
    await s.fill('Lý do', 'Không liên lạc được người nhận lần 2');
    await s.clickButton('Xác nhận');
    await s.clickButton('Hoàn hàng');
    await s.fill('Lý do', 'Hoàn trả kiện hàng về người gửi');
    await s.clickButton('Xác nhận');
    await s.page.getByRole('button', { name: 'Đã trả hàng cho người gửi', exact: true }).waitFor();
    await s.clickButton('Đã trả hàng cho người gửi');
    await s.waitText('Xác nhận hoàn hàng');
    await s.clickButton('Đã hoàn hàng');
    await s.waitText('Đã hoàn hàng');
    await s.snap(folder, '04-driver-return-completed-1440.png', 'Hoàn tất chu trình Giao lại -> Hoàn hàng -> Đã trả hàng cho người gửi', [
      'Đã trả hàng cho người gửi',
      'Đã hoàn hàng',
    ]);
  } finally {
    await s.context.close();
  }

  const m360 = await createSession(browser, { width: 360, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(m360.page, { user, token });
    await attachDriverBackend(m360.page);
    await m360.page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
    await m360.enableSemantics();
    await m360.fill('Email', user.email);
    await m360.fill('Mật khẩu', 'DriverPass123');
    await m360.clickButton('Đăng nhập', { last: true });
    await m360.waitText('Bạn muốn giao hàng hay đặt món đến đâu?');
    await m360.clickNav('Hồ sơ');
    await m360.waitText('Sổ địa chỉ');
    await m360.clickNav('Chuyến giao của tôi');
    await m360.waitText(/Linh kiện điện tử cần OTP & POD/);
    await m360.snap(folder, '05-driver-trips-mobile-360.png', 'Danh sách Chuyến giao của Tài xế trên Mobile 360px', [
      'Driver Mobile 360px',
    ]);
  } finally {
    await m360.context.close();
  }
}

async function runSuite06OperatorAdmin(browser, acceptanceRoot, gallery) {
  const folder = '06-operator-admin';
  const adminId = '00000000-0000-0000-0000-000000000901';
  const adminUser = makeUser(adminId, 'operator-admin@example.com');
  const token = makeJwt(adminId);
  const ghnOrderId = '60000000-0000-0000-0000-000000000901';
  const candidateId = '00000000-0000-0000-0000-000000000902';

  let isOperator = false;
  let pricing = { base_fee: 18000, per_km: 5500, express_fee: 12000, extra_kg: 4000, version: 3 };
  let shopStatus = 'pending';
  let shopVersion = 1;
  let reviewHidden = false;
  let driverApproved = false;
  let accountBlocked = false;
  let platformVoucherSaved = false;
  let jobsRan = false;
  let jobRetried = false;
  let ghnPreviewed = false;
  const financeRow = {
    id: '70000000-0000-0000-0000-000000000901',
    order_id: '60000000-0000-0000-0000-000000000301',
    kind: 'settlement',
    amount: 135000,
    state: 'requested',
    version: 1,
    proposer: '00000000-0000-0000-0000-000000000301',
    reason: 'Đối soát doanh thu cửa hàng',
    evidence: 'SETTLE-301',
  };

  const attachAdminBackend = page =>
    page.route('http://127.0.0.1:8787/**', route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
      const u = new URL(req.url());
      const body = req.method() === 'POST' ? req.postDataJSON() : null;
      const p = u.pathname;

      if (p === '/delivery/cloud/profile') {
        return route.fulfill({
          headers: CORS,
          json: {
            schema_version: 3,
            operator: isOperator,
            account: {
              user_id: adminId,
              full_name: 'Điều Hành Viên Cloud',
              phone: '0909000999',
              role: 'customer',
              blocked: false,
              requested_role: null,
              approved_roles: [],
              staff_shops: [],
              memberships: [],
            },
          },
        });
      }
      if (p === '/delivery/cloud/pricing') {
        if (req.method() === 'POST') {
          pricing = { ...body, version: pricing.version + 1 };
        }
        return route.fulfill({ headers: CORS, json: { pricing } });
      }
      if (p === '/delivery/cloud/audit') {
        return route.fulfill({
          headers: CORS,
          json: {
            entries: [
              { action: 'pricing', target_id: 'default', actor_id: adminId, created_at: '2026-10-31T10:00:00Z' },
              { action: 'membership', target_id: candidateId, actor_id: adminId, created_at: '2026-10-31T10:05:00Z' },
            ],
          },
        });
      }
      if (p === '/delivery/cloud/merchants') return route.fulfill({ headers: CORS, json: { merchants: [] } });
      if (p === '/delivery/cloud/orders') {
        return route.fulfill({
          headers: CORS,
          json: {
            schema_version: 3,
            orders: [
              {
                id: ghnOrderId,
                tracking_code: 'CL-60000000000000000000000000000901',
                status: 'searching',
                version: 1,
                shipping_fee: 30000,
                cod_amount: 90000,
                payment_status: 'PAID',
                owner_id: candidateId,
                created_at: '2026-10-31T09:00:00Z',
                details: {
                  pickup_address: '12 Nguyễn Huệ, Phường Bến Nghé, TP.HCM',
                  dropoff_address: '88 Lê Lợi, Phường Bến Thành, TP.HCM',
                  recipient_name: 'Khách Liên Tỉnh',
                  recipient_phone: '0911222333',
                  package_description: 'Hộp sách chuyên khảo',
                  weight_kg: 1.0,
                  service_type: 'standard',
                  payment_method: 'sender_cash',
                },
              },
            ],
          },
        });
      }
      if (p === `/delivery/cloud/orders/${ghnOrderId}/shipment`) {
        return route.fulfill({ headers: CORS, json: { configured: true, shipment: null } });
      }
      if (p === `/delivery/cloud/orders/${ghnOrderId}/shipment/preview`) {
        ghnPreviewed = true;
        return route.fulfill({ headers: CORS, json: { quote_id: 'ghn-q-1', total_fee: 27500 } });
      }
      if (p === '/delivery/cloud/accounts') {
        return route.fulfill({
          headers: CORS,
          json: {
            schema_version: 3,
            accounts: [
              {
                user_id: candidateId,
                full_name: 'Ứng Viên Tài Xế Mới',
                phone: '0977888999',
                role: 'customer',
                blocked: accountBlocked,
                requested_role: driverApproved ? null : 'driver',
                approved_roles: driverApproved ? ['driver'] : [],
                memberships: [
                  { role: 'driver', state: driverApproved ? 'active' : 'pending', version: driverApproved ? 2 : 1, reason: '' },
                ],
              },
            ],
          },
        });
      }
      if (p === `/delivery/cloud/accounts/${candidateId}/memberships/driver`) {
        assert.equal(body.decision, 'approve');
        driverApproved = true;
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === `/delivery/cloud/accounts/${candidateId}`) {
        accountBlocked = Boolean(body.blocked);
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === '/delivery/cloud/marketplace/admin_analytics') {
        return route.fulfill({
          headers: CORS,
          json: {
            cloud_orders: { total: 42, searching: 4, in_transit: 9, delivered: 29, shipping_fee_delivered: 890000 },
            market_orders: { total: 31, pending: 2, accepted_ready: 5, delivered: 22, cancelled: 2 },
            finance_totals: { collections_completed: 2450000, settlements_completed: 1820000, refunds_completed: 120000, pending_requests: financeRow.state === 'completed' ? 0 : 1 },
            shops: { active: shopStatus === 'active' ? 8 : 7, pending: shopStatus === 'pending' ? 1 : 0 },
            promotions: { active_vouchers: 4, voucher_budget_used: 210000, active_flash_sales: 2, coins_circulating: 18500 },
            memberships_pending: driverApproved ? 0 : 1,
            reported_reviews: reviewHidden ? 0 : 1,
            ledger_balances: { cash_clearing: 510000, merchant_payable: 135000 },
          },
        });
      }
      if (p === '/delivery/cloud/marketplace/workspace') {
        return route.fulfill({
          headers: CORS,
          json: {
            shops: [{ id: 'shop-mod-1', name: 'Cửa Hàng Chờ Duyệt Mới', address: '99 Đồng Khởi', status: shopStatus, paused: false, version: shopVersion }],
            products: [],
            next: null,
          },
        });
      }
      if (p === '/delivery/cloud/marketplace/shop_moderate') {
        shopStatus = body.status;
        shopVersion++;
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === '/delivery/cloud/marketplace/operations') {
        return route.fulfill({
          headers: CORS,
          json: {
            reported_reviews: reviewHidden
              ? []
              : [{ id: 'rep-rev-1', review_kind: 'product', rating: 1, report_count: 3, body: 'Bình luận spam quảng cáo trái phép', hidden: false }],
            finance: [financeRow],
            returns: [],
            jobs: { pending: jobsRan ? 0 : 2, failed: jobRetried ? 0 : 1, overdue: jobsRan ? 0 : 1 },
            failed_jobs: jobRetried ? [] : [{ id: 'job-1', order_id: '60000000-0000-0000-0000-000000000301', attempts: 3 }],
          },
        });
      }
      if (p === '/delivery/cloud/marketplace/review_moderate') {
        reviewHidden = Boolean(body.hidden);
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === '/delivery/cloud/marketplace/voucher_save') {
        platformVoucherSaved = true;
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === '/delivery/cloud/marketplace/jobs_run') {
        jobsRan = true;
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === '/delivery/cloud/marketplace/job_retry') {
        jobRetried = true;
        return route.fulfill({ headers: CORS, json: { ok: true } });
      }
      if (p === '/delivery/cloud/marketplace/finance_action') {
        financeRow.version++;
        financeRow.state = body.action === 'approve' ? 'approved' : 'completed';
        if (body.evidence) financeRow.completion_evidence = body.evidence;
        return route.fulfill({ headers: CORS, json: { finance: financeRow } });
      }
      if (p === '/delivery/admin/integrations') {
        return route.fulfill({
          headers: CORS,
          json: {
            local: false,
            providers: {
              smtp: {
                label: 'Gmail / SMTP',
                available: true,
                configured: true,
                enabled: true,
                fields: [
                  { key: 'SMTP_HOST', label: 'SMTP host', value: 'smtp.gmail.com', type: 'text', secret: false, configured: true },
                  { key: 'SMTP_PASS', label: 'App Password', secret: true, configured: true, type: 'text' },
                  { key: 'SMTP_ENABLED', label: 'Cho phép backend sử dụng', value: 'true', type: 'boolean' },
                ],
              },
            },
          },
        });
      }
      if (p === '/delivery/admin/integrations/usage') {
        return route.fulfill({
          headers: CORS,
          json: {
            since: '2026-10-31T08:00:00Z',
            providers: [{ provider: 'payOS', requests: 14, successes: 14, failures: 0, rateLimited: 0, averageMs: 82, lastStatus: 200 }],
          },
        });
      }
      if (p === '/delivery/admin/integrations/audit') {
        return route.fulfill({ headers: CORS, json: { entries: [] } });
      }
      if (p === '/delivery/admin/integrations/readiness') {
        return route.fulfill({
          headers: CORS,
          json: {
            checkedAt: '2026-10-31T10:30:00Z',
            databaseConfigured: false,
            canMigrate: true,
            liveTransactionsVerified: false,
            migrationVersion: '20261107_cloud_commercial_suite',
            databaseRevision: 'acceptance-fixture',
            checks: [
              { label: 'PostgreSQL backend', status: 'missing', detail: 'Lưu kết nối PostgreSQL tại Admin của backend đang kết nối.' },
              { label: 'payOS thanh toán', status: 'missing', detail: 'Thiếu khóa kết nối payOS.' },
            ],
            callbacks: [
              { label: 'payOS', url: 'https://delivery.example/backend/delivery/payments/webhook', authentication: 'Chữ ký checksum payOS' },
            ],
          },
        });
      }
      return route.fulfill({ status: 403, headers: CORS, json: { error: 'Admin fixture denied: ' + p } });
    });

  const s = await createSession(browser, { width: 1440, acceptanceRoot, gallery });
  try {
    await attachSupabaseAuth(s.page, { user: adminUser, token, operatorProfile: true });
    await attachAdminBackend(s.page);

    isOperator = false;
    await s.page.goto('http://127.0.0.1:8080/#/admin', { waitUntil: 'domcontentloaded' });
    await s.enableSemantics();
    await s.fill('Email quản trị', adminUser.email);
    await s.fill('Mật khẩu', 'AdminPass123');
    await s.clickButton('Đăng nhập');
    await s.waitText('Tài khoản cloud chưa có quyền operator.');
    await s.snap(folder, '01-admin-non-operator-guard-1440.png', 'Chặn tài khoản thường truy cập cổng /#/admin (Role Isolation Guard)', [
      'Tài khoản cloud chưa có quyền operator.',
      'Đăng xuất',
    ]);
    await s.clickButton('Đăng xuất');
    await s.waitText('Đăng nhập quản trị');

    isOperator = true;
    await s.fill('Email quản trị', adminUser.email);
    await s.fill('Mật khẩu', 'AdminPass123');
    await s.clickButton('Đăng nhập');
    await s.waitText('Chỉ số vận hành Cloud thời gian thực');
    await s.clickButton('Làm mới');
    await s.snap(folder, '02-admin-overview-analytics-1440.png', 'Tab 1 Tổng quan: Chỉ số vận hành Cloud & Kế toán kép thời gian thực', [
      'Tổng quan',
      'Làm mới',
      '4 bảng KPI vận hành & sổ cái kép',
    ]);

    await s.clickButton('Bảng giá cloud');
    await s.waitText(/Phí 2 km đầu \(đồng\)/);
    await s.fill('Phí 2 km đầu (đồng)', '19000');
    await s.snap(folder, '03-admin-pricing-dialog-1440.png', 'Hộp thoại cập nhật Bảng giá vận chuyển Cloud', [
      'Bảng giá cloud',
      'Lưu bảng giá',
    ]);
    await s.clickButton('Lưu bảng giá');
    assert.equal(pricing.base_fee, 19000);

    await s.clickButton('Nhật ký điều hành');
    await s.waitText('Nhật ký điều hành Cloud');
    await s.snap(folder, '04-admin-audit-log-1440.png', 'Nhật ký điều hành Cloud (Audit Trail)', [
      'Nhật ký điều hành',
    ]);
    await s.clickButton('Đóng');

    await s.clickNav('Đơn & Tài khoản');
    await s.waitText(/Hộp sách chuyên khảo/);
    await s.clickButton('Vận chuyển GHN');
    await s.fill('Tỉnh/thành điểm lấy (hệ hai cấp)', 'Hồ Chí Minh');
    await s.fill('Phường/xã điểm lấy', 'Phường Bến Nghé');
    await s.fill('Tỉnh/thành điểm giao (hệ hai cấp)', 'Hồ Chí Minh');
    await s.fill('Phường/xã điểm giao', 'Phường Bến Thành');
    await s.clickButton('Xem phí GHN');
    await s.page.getByRole('button', { name: 'Tạo vận đơn GHN', exact: true }).waitFor();
    assert.equal(ghnPreviewed, true);
    await s.snap(folder, '05-admin-orders-ghn-dispatch-1440.png', 'Tab 2 Đơn & Tài khoản: Báo giá & điều phối hãng vận chuyển GHN', [
      'Vận chuyển GHN',
      'Xem phí GHN',
      'Tạo vận đơn GHN',
    ]);
    await s.clickButton('Đóng');

    await s.clickNav('Tài khoản');
    await s.waitText(/Ứng Viên Tài Xế Mới/);
    await s.clickButton('Duyệt Tài xế');
    await s.fill('Ghi chú', 'Hồ sơ giấy tờ xe hợp lệ');
    await s.snap(folder, '06-admin-approve-driver-dialog-1440.png', 'Xét duyệt hồ sơ đối tác Tài xế Cloud', [
      'Tài khoản',
      'Duyệt Tài xế',
      'Xác nhận',
    ]);
    await s.clickButton('Xác nhận');
    await s.waitText('Tài xế · Đã duyệt');
    assert.equal(driverApproved, true);

    await s.clickButton('Khóa tài khoản');
    await s.clickButton('Xác nhận');
    await s.page.getByRole('button', { name: 'Mở khóa tài khoản', exact: true }).waitFor();
    await s.snap(folder, '07-admin-accounts-governance-1440.png', 'Quản trị tài khoản Cloud: Đã duyệt Tài xế & Khóa/Mở khóa tài khoản', [
      'Thu hồi Tài xế',
      'Khóa tài khoản / Mở khóa tài khoản',
    ]);

    await s.clickNav('Cửa hàng & Đánh giá');
    await s.waitText('Cửa Hàng Chờ Duyệt Mới');
    await s.clickButton('Duyệt hoạt động');
    await s.waitText('Đang hoạt động');
    await s.clickNav('Đánh giá bị báo cáo');
    await s.clickButton('Ẩn');
    await s.fill('Lý do kiểm duyệt', 'Spam quảng cáo vi phạm chính sách');
    await s.clickButton('Xác nhận');
    await s.waitText('Không có đánh giá bị báo cáo.');
    await s.snap(folder, '08-admin-moderation-complete-1440.png', 'Tab 3 Cửa hàng & Đánh giá: Duyệt cửa hàng & Ẩn đánh giá vi phạm', [
      'Duyệt hoạt động / Tạm khóa',
      'Đánh giá bị báo cáo -> Ẩn',
    ]);

    await s.clickNav('Khuyến mãi & Đối soát');
    await s.clickButton('Tạo voucher toàn sàn');
    await s.fill('Mã voucher', 'GHSTSAN30K');
    await s.fill('Tên chương trình', 'Trợ giá toàn sàn 30k');
    await s.clickButton('Lưu voucher');
    assert.equal(platformVoucherSaved, true);

    await s.clickButton('Xử lý đơn quá hạn');
    assert.equal(jobsRan, true);
    await s.clickButton('Thử lại tác vụ');
    assert.equal(jobRetried, true);

    await s.clickButton('Duyệt');
    await s.fill('Lý do quyết định', 'Đối chiếu sao kê hợp lệ');
    await s.clickButton('Xác nhận');
    await s.clickButton('Xác nhận thu/chi');
    await s.fill('Chứng từ giao dịch đã thực hiện', 'BANK-UNC-901');
    await s.clickButton('Xác nhận');
    await s.waitText('Đã xác nhận thu/chi');
    await s.snap(folder, '09-admin-promo-and-finance-1440.png', 'Tab 4 Khuyến mãi & Đối soát: Voucher sàn, Tác vụ nền & Kế toán kép 2 bước', [
      'Tạo voucher toàn sàn',
      'Xử lý đơn quá hạn',
      'Thử lại tác vụ',
      'Duyệt & Xác nhận thu/chi',
    ]);

    await s.clickNav('Tích hợp');
    await s.clickButton('Quản lý API backend');
    await s.clickNav('Gmail / SMTP');
    const secretInput = s.page.getByRole('textbox', { name: 'App Password' });
    await secretInput.scrollIntoViewIfNeeded();
    assert.equal(await secretInput.getAttribute('type'), 'password');
    assert.equal(await secretInput.inputValue(), '');
    await s.clickButton('Hoạt động API');
    await s.waitText(/payOS · 14 yêu cầu/);
    await s.snap(folder, '10-admin-integrations-masked-secret-1440.png', 'Tab 5 Tích hợp: Quản lý khóa API che mật khẩu & Giám sát lưu lượng', [
      'Quản lý API backend',
      'Che khóa bí mật (type=password)',
      'Hoạt động API',
    ]);

    await s.clickButton('Sẵn sàng triển khai');
    await s.waitText(/PostgreSQL backend · Còn thiếu/);
    await s.snap(folder, '11-admin-readiness-dialog-1440.png', 'Hộp thoại Kiểm tra Sẵn sàng triển khai Production', [
      'Sẵn sàng triển khai',
      'Cập nhật schema cloud (guarded)',
    ]);
    await s.clickButton('Đóng');
  } finally {
    await s.context.close();
  }

  const m360 = await createSession(browser, { width: 360, acceptanceRoot, gallery });
  try {
    isOperator = true;
    await attachSupabaseAuth(m360.page, { user: adminUser, token, operatorProfile: true });
    await attachAdminBackend(m360.page);
    await m360.page.goto('http://127.0.0.1:8080/#/admin', { waitUntil: 'domcontentloaded' });
    await m360.enableSemantics();
    await m360.waitText('GHST CLOUD ADMIN');
    await m360.snap(folder, '12-admin-login-mobile-360.png', 'Đăng nhập Quản trị GHST CLOUD ADMIN trên Mobile 360px', [
      'Header compact 360px không tràn dòng',
    ]);
    await m360.fill('Email quản trị', adminUser.email);
    await m360.fill('Mật khẩu', 'AdminPass123');
    await m360.clickButton('Đăng nhập');
    await m360.waitText('Chỉ số vận hành Cloud thời gian thực');
    await m360.snap(folder, '13-admin-overview-mobile-360.png', 'Cổng Quản trị Cloud với NavigationBar 5 tab trên Mobile 360px', [
      'NavigationBar 5 tab Mobile 360px',
    ]);
  } finally {
    await m360.context.close();
  }
}

async function writeManifest(acceptanceRoot, gallery) {
  const byFolder = new Map();
  for (const item of gallery) {
    if (!byFolder.has(item.folder)) byFolder.set(item.folder, []);
    byFolder.get(item.folder).push(item);
  }
  const titles = {
    '01-auth-and-public': '01. Xác thực Cloud, Hồ sơ lần đầu & Tra cứu công khai',
    '02-customer': '02. Vai trò Khách hàng (Trang chủ, Bản đồ, Sổ địa chỉ, Giao hàng, Ăn uống, Giỏ hàng, Hậu mãi, Chat, Ví Xu)',
    '03-merchant': '03. Vai trò Chủ cửa hàng (Cửa hàng, Sản phẩm, Biến thể SKU, Voucher, Flash Sale, Nhân sự, Tách kiện, Đối soát)',
    '04-shop-staff': '04. Vai trò Nhân sự cửa hàng được ủy quyền (Nhân viên xử lý đơn & Quản lý cửa hàng)',
    '05-driver': '05. Vai trò Tài xế (Hàng đợi chuyến, Xác thực POD + OTP 6 số, Giao thất bại, Giao lại & Hoàn hàng)',
    '06-operator-admin': '06. Vai trò Quản trị viên Operator (/#/admin độc lập, Bảng giá, GHN, Duyệt đối tác, Kiểm duyệt, Sổ cái kép, Tích hợp)',
  };

  const lines = [
    '# Bộ Ảnh Nghiệm Thu Toàn Diện Từng Nút Tính Năng & Từng Vai Trò UI',
    '',
    `- Thời điểm chụp nghiệm thu: \`${new Date().toISOString()}\``,
    `- Tổng số ảnh nghiệm thu: **${gallery.length} ảnh PNG** (0 lỗi runtime, 0 lỗi tràn bố cục ngang Desktop \`1440px\` & Mobile \`360px\`)`,
    '- Chế độ kiểm thử: Trình duyệt Microsoft Edge Headless trực tiếp trên bản build Web chính thức (`build/web`), cô lập hoàn toàn dữ liệu kiểm thử (không ghi dữ liệu mẫu lên cơ sở dữ liệu thật).',
    '',
  ];

  for (const [folder, items] of byFolder.entries()) {
    lines.push(`## ${titles[folder] || folder} (\`${folder}/\`)`, '');
    lines.push('| Ảnh nghiệm thu | Khung nhìn | Mô tả màn hình | Các nút & tính năng đã bấm kiểm chứng |');
    lines.push('| --- | --- | --- | --- |');
    for (const it of items) {
      lines.push(
        `| [\`${it.file}\`](./${folder}/${it.file}) | \`${it.viewport}\` | ${it.description} | ${it.features.join(', ')} |`,
      );
    }
    lines.push('');
  }

  await fs.writeFile(path.join(acceptanceRoot, 'INDEX.md'), lines.join('\n'), 'utf8');
  await fs.writeFile(
    path.join(acceptanceRoot, 'acceptance-report.json'),
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        totalScreenshots: gallery.length,
        roleFolders: Array.from(byFolder.keys()),
        items: gallery,
      },
      null,
      2,
    ),
    'utf8',
  );
}

(async () => {
  const acceptanceRoot = path.resolve(__dirname, '../build/verification/acceptance');
  await fs.rm(acceptanceRoot, { recursive: true, force: true });
  await fs.mkdir(acceptanceRoot, { recursive: true });

  const gallery = [];
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    await runSuite01AuthAndPublic(browser, acceptanceRoot, gallery);
    console.log('Suite 01 (Auth & Public): PASS');
    await runSuite02Customer(browser, acceptanceRoot, gallery);
    console.log('Suite 02 (Customer): PASS');
    await runSuite03Merchant(browser, acceptanceRoot, gallery);
    console.log('Suite 03 (Merchant): PASS');
    await runSuite04ShopStaff(browser, acceptanceRoot, gallery);
    console.log('Suite 04 (Shop Staff & Manager): PASS');
    await runSuite05Driver(browser, acceptanceRoot, gallery);
    console.log('Suite 05 (Driver): PASS');
    await runSuite06OperatorAdmin(browser, acceptanceRoot, gallery);
    console.log('Suite 06 (Operator Admin): PASS');
    await writeManifest(acceptanceRoot, gallery);
    console.log(`Full UI acceptance gallery complete: ${gallery.length} screenshots in ${acceptanceRoot}`);
  } finally {
    await browser.close();
  }
})().catch(err => {
  console.error(err);
  process.exitCode = 1;
});
