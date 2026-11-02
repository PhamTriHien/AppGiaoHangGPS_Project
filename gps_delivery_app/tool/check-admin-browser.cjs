const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || path.join(process.env.LOCALAPPDATA, 'Temp', 'ghst-browser-check', 'node_modules', 'playwright-core'));

// Isolated Cloud Operator (/admin) and Consumer (/) separation UI verification.
(async () => {
  const appRoot = path.resolve(__dirname, '..');
  const output = path.join(appRoot, 'build', 'verification');
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  let activePage;
  try {
    const widths = process.env.CHECK_WIDTH ? [Number(process.env.CHECK_WIDTH)] : [1440, 360];
    for (const width of widths) {
      const context = await browser.newContext({ viewport: { width, height: 1000 }, serviceWorkers: 'block' });
      const page = await context.newPage();
      activePage = page;
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', m => {
        if (m.type() === 'error' && /overflowed|RenderFlex|EXCEPTION CAUGHT/.test(m.text())) {
          errors.push(m.text());
        }
      });

      const cors = {
        'access-control-allow-origin': 'http://127.0.0.1:8080',
        'access-control-allow-headers': '*',
        'access-control-allow-methods': 'GET,POST,OPTIONS',
      };
      const adminId = '00000000-0000-0000-0000-000000000099';
      const adminUser = {
        id: adminId,
        aud: 'authenticated',
        role: 'authenticated',
        email: 'admin-fixture@example.com',
        app_metadata: { provider: 'email', providers: ['email'] },
        user_metadata: {},
        identities: [],
        created_at: new Date().toISOString(),
      };
      const token = `${Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url')}.${Buffer.from(JSON.stringify({ sub: adminId, role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')}.admin-fixture`;

      let gatewayLoads = 0;
      let shopStatus = 'pending';
      let shopVersion = 1;
      let reviewHidden = false;

      await page.route('**/*.supabase.co/**', route => {
        const req = route.request();
        if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
        const pathname = new URL(req.url()).pathname;
        if (pathname === '/auth/v1/settings') return route.fulfill({ headers: cors, json: { external: { google: false } } });
        if (pathname === '/auth/v1/token') return route.fulfill({ headers: cors, json: { access_token: token, token_type: 'bearer', expires_in: 3600, refresh_token: 'admin-fixture-refresh', user: adminUser } });
        if (pathname === '/auth/v1/user') return route.fulfill({ headers: cors, json: adminUser });
        if (pathname === '/rest/v1/delivery_api_profiles') return route.fulfill({ headers: cors, json: [{ role: 'operator' }] });
        return route.fulfill({ status: 403, headers: cors, json: { message: 'Isolated Admin fixture' } });
      });

      await page.route('http://127.0.0.1:8787/**', route => {
        const request = route.request();
        if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
        const pathname = new URL(request.url()).pathname;
        const body = request.method() === 'POST' ? request.postDataJSON() : null;
        if (pathname === '/delivery/local-auth/config') {
          return route.fulfill({ json: { googleClientId: '', sms: false }, headers: cors });
        }
        if (pathname === '/delivery/cloud/profile') {
          return route.fulfill({
            headers: cors,
            json: {
              schema_version: 3,
              operator: true,
              account: {
                user_id: adminId,
                full_name: 'Quản trị Cloud',
                phone: '0901234567',
                role: 'customer',
                blocked: false,
                requested_role: null,
                approved_roles: [],
                memberships: [],
              },
            },
          });
        }
        if (pathname === '/delivery/cloud/marketplace/admin_analytics') {
          return route.fulfill({
            headers: cors,
            json: {
              cloud_orders: { total: 12, searching: 2, in_transit: 3, delivered: 7, shipping_fee_delivered: 175000 },
              market_orders: { total: 8, pending: 1, accepted_ready: 2, delivered: 4, cancelled: 1 },
              finance_totals: { collections_completed: 450000, settlements_completed: 320000, refunds_completed: 50000, pending_requests: 1 },
              shops: { active: shopStatus === 'active' ? 4 : 3, pending: shopStatus === 'pending' ? 1 : 0 },
              promotions: { active_vouchers: 2, voucher_budget_used: 30000, active_flash_sales: 1, coins_circulating: 5000 },
              memberships_pending: 1,
              reported_reviews: reviewHidden ? 0 : 1,
              ledger_balances: { cash_clearing: 80000 },
            },
          });
        }
        if (pathname === '/delivery/cloud/logistics/stats') {
          return route.fulfill({
            headers: cors,
            json: {
              scope: 'network',
              summary: {
                total: 12,
                delivered: 7,
                failed_or_returned: 1,
                cancelled: 0,
                active: 4,
                avg_delivery_minutes: 34,
                avg_transit_minutes: 21,
                by_service: [{ service_type: 'express', total: 7, delivered: 7, avg_delivery_minutes: 28 }],
              },
              pickups: { requested: 1, assigned: 2 },
              drivers: { approved: 3, on_trip: 1 },
            },
          });
        }
        if (pathname === '/delivery/cloud/marketplace/workspace') {
          return route.fulfill({
            headers: cors,
            json: {
              shops: [{
                id: '20000000-0000-0000-0000-000000000001',
                name: 'Cửa hàng chờ duyệt',
                address: '12 Nguyễn Huệ',
                status: shopStatus,
                paused: false,
                version: shopVersion,
              }],
              products: [],
              next: null,
            },
          });
        }
        if (pathname === '/delivery/cloud/marketplace/shop_moderate') {
          assert.equal(body.version, shopVersion);
          shopStatus = body.status;
          shopVersion++;
          return route.fulfill({ headers: cors, json: { ok: true } });
        }
        if (pathname === '/delivery/cloud/marketplace/operations') {
          return route.fulfill({
            headers: cors,
            json: {
              reported_reviews: reviewHidden ? [] : [{
                id: '90000000-0000-0000-0000-000000000001',
                review_kind: 'product',
                rating: 1,
                report_count: 2,
                body: 'Nội dung đánh giá bị báo cáo kiểm thử',
                hidden: false,
              }],
              finance: [],
              returns: [],
              jobs: { pending: 0, failed: 0, overdue: 0 },
              failed_jobs: [],
            },
          });
        }
        if (pathname === '/delivery/cloud/marketplace/review_moderate') {
          assert.equal(body.hidden, true);
          assert.ok(body.reason.length >= 3);
          reviewHidden = true;
          return route.fulfill({ headers: cors, json: { ok: true } });
        }
        if (pathname === '/delivery/admin/integrations/readiness') {
          return route.fulfill({
            headers: cors,
            json: {
              checkedAt: '2026-10-31T10:00:00Z',
              databaseConfigured: false,
              canMigrate: true,
              liveTransactionsVerified: false,
              migrationVersion: '20261108_cloud_logistics',
              databaseRevision: 'ui-fixture',
              checks: [
                { label: 'PostgreSQL backend', status: 'missing', detail: 'Lưu kết nối PostgreSQL tại Admin của backend đang kết nối.' },
                { label: 'Schema bộ thương mại hóa Cloud (P1-P6)', status: 'unchecked', detail: 'Cần kiểm tra database và chạy migration cloud.' },
                { label: 'payOS thanh toán', status: 'missing', detail: 'Thiếu: PAYOS_CLIENT_ID, PAYOS_API_KEY, PAYOS_CHECKSUM_KEY' },
                { label: 'GHN vận chuyển', status: 'missing', detail: 'Thiếu: GHN_TOKEN, GHN_SHOP_ID, GHN_WEBHOOK_SECRET' },
              ],
              callbacks: [
                { label: 'payOS', url: 'https://delivery.example/backend/delivery/payments/webhook', authentication: 'Chữ ký checksum payOS' },
                { label: 'GHN', url: null, authentication: 'Header X-GHN-Webhook-Secret' },
              ],
            },
          });
        }
        if (pathname === '/delivery/admin/integrations') {
          gatewayLoads++;
          return route.fulfill({
            headers: cors,
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
                    { key: 'SMTP_PASS', label: 'App Password', secret: true, configured: true, maskedValue: '••••••••••••abcd', type: 'text' },
                    { key: 'SMTP_ENABLED', label: 'Cho phép backend sử dụng', value: 'true', type: 'boolean' },
                  ],
                },
                momo: { label: 'MoMo', available: false, configured: false, enabled: false, fields: [] },
              },
            },
          });
        }
        return route.fulfill({ status: 403, headers: cors, json: { error: 'UI verification only' } });
      });

      const enableSemantics = async () => {
        await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder') || document.querySelector('flt-semantics'), { timeout: 30000 });
        await page.locator('flt-semantics-placeholder').evaluateAll(nodes => nodes.forEach(e => e.click()));
      };
      const fillField = async (name, value) => {
        const field = page.getByRole('textbox', { name, exact: true });
        await field.scrollIntoViewIfNeeded();
        await field.click();
        await field.press('ControlOrMeta+A');
        await field.pressSequentially(value, { delay: 15 });
        await field.press('Tab');
      };

      await page.goto('http://127.0.0.1:8080/', { waitUntil: 'domcontentloaded' });
      await enableSemantics();
      await page.getByRole('button', { name: 'Đăng nhập', exact: true }).last().waitFor();
      assert.equal(await page.getByRole('button', { name: 'Thiết lập quản trị viên đầu tiên' }).count(), 0);
      assert.equal(await page.getByText('GHST CLOUD ADMIN', { exact: true }).count(), 0);
      assert.equal(await page.getByText('Đơn hàng cloud', { exact: true }).count(), 0);
      await page.screenshot({ path: path.join(output, `user-login-${width}.png`) });

      await page.goto('about:blank');
      await page.goto('http://127.0.0.1:8080/#/admin', { waitUntil: 'domcontentloaded' });
      await enableSemantics();
      await page.getByText('GHST CLOUD ADMIN', { exact: true }).waitFor();
      await page.getByText('Đăng nhập quản trị', { exact: true }).waitFor();
      await fillField('Email quản trị', adminUser.email);
      await fillField('Mật khẩu', 'Ui-check-2026');
      await page.getByRole('button', { name: 'Đăng nhập', exact: true }).click();

      const clickTab = name =>
        page.getByLabel(new RegExp('^' + name)).or(page.getByText(new RegExp('^' + name))).last().click();

      await page.getByText(/Đơn vận chuyển Cloud/).first().waitFor({ timeout: 15000 });
      await page.getByText(/Đối soát & Kế toán kép/).first().waitFor();
      await page.screenshot({ path: path.join(output, `cloud-admin-overview-${width}.png`) });

      await clickTab('Cửa hàng & Đánh giá');
      await page.getByText('Cửa hàng chờ duyệt', { exact: false }).first().waitFor();
      await page.getByRole('button', { name: 'Duyệt hoạt động', exact: true }).click();
      await page.getByText('Đang hoạt động', { exact: false }).first().waitFor();
      assert.equal(shopStatus, 'active');

      await page.getByLabel(/Đánh giá bị báo cáo/).or(page.getByText(/Đánh giá bị báo cáo/)).last().click();
      await page.getByRole('button', { name: 'Ẩn', exact: true }).click();
      await fillField('Lý do kiểm duyệt', 'Nội dung vi phạm quy chuẩn');
      await page.getByRole('button', { name: 'Xác nhận', exact: true }).click();
      await page.getByText('Không có đánh giá bị báo cáo.', { exact: false }).first().waitFor();
      assert.equal(reviewHidden, true);
      await page.screenshot({ path: path.join(output, `cloud-admin-moderation-${width}.png`) });

      await clickTab('Tích hợp');
      const manage = page.getByRole('button', { name: 'Quản lý API backend', exact: true });
      await manage.scrollIntoViewIfNeeded();
      await manage.click();
      await page.getByText('Gmail / SMTP', { exact: false }).first().click();
      const password = page.getByRole('textbox', { name: 'App Password' });
      await password.scrollIntoViewIfNeeded();
      assert.equal(await password.getAttribute('type'), 'password');
      assert.equal(await password.inputValue(), '');
      assert.equal(gatewayLoads, 1);
      await page.screenshot({ path: path.join(output, `backend-admin-${width}.png`) });

      const readiness = page.getByRole('button', { name: 'Sẵn sàng triển khai', exact: true });
      await readiness.scrollIntoViewIfNeeded();
      await readiness.click();
      await page.getByText('PostgreSQL backend · Còn thiếu', { exact: true }).waitFor();
      await page.waitForTimeout(350);
      await page.screenshot({ path: path.join(output, `backend-readiness-${width}.png`) });
      assert.equal(await page.getByRole('button', { name: 'Cập nhật schema cloud', exact: true }).isDisabled(), true);
      await page.getByRole('button', { name: 'Đóng', exact: true }).click();

      assert.deepEqual(errors, []);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
      assert.equal(overflow, false);
      console.log(JSON.stringify({ width, adminPage: true, cloudOperator: true, maskedSecret: true, fixtureApi: true, errors: errors.length }));
      await context.close();
    }
  } catch (error) {
    if (activePage && !activePage.isClosed()) {
      await activePage.screenshot({ path: path.join(output, 'admin-browser-failure.png') });
      console.log((await activePage.locator('flt-semantics').allTextContents()).join(' ').slice(-3500));
    }
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
