const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || path.join(process.env.LOCALAPPDATA, 'Temp', 'ghst-browser-check', 'node_modules', 'playwright-core'));

// Isolated browser fixtures only: block all real provider/cloud requests.
(async () => {
  const root = path.resolve(__dirname, '..');
  const output = path.join(root, 'build', 'verification');
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  let activePage;
  try {
    const widths = process.env.CHECK_WIDTH ? [Number(process.env.CHECK_WIDTH)] : [1440, 360];
    const roles = process.env.CHECK_ROLE ? [process.env.CHECK_ROLE] : ['customer', 'driver', 'operator'];
    for (const width of widths) {
      for (const role of roles) {
        const context = await browser.newContext({ viewport: { width, height: 1000 } });
        const page = await context.newPage();
        activePage = page;
        const fillField = async (field, value) => {
          await field.waitFor({ state: 'attached' });
          for (let i = 0; i < 6; i++) {
            const box = await field.boundingBox();
            if (box && box.y >= 16 && box.y + box.height <= 960) break;
            await page.mouse.move(width / 2, 600);
            await page.mouse.wheel(0, box && box.y < 16 ? -420 : 420);
            await page.waitForTimeout(160);
          }
          await field.scrollIntoViewIfNeeded();
          await field.click();
          await field.press('ControlOrMeta+A');
          await field.pressSequentially(value, { delay: 20 });
          await page.waitForTimeout(150);
        };
        const errors = [];
        const userId = '00000000-0000-0000-0000-000000000001';
        const user = { id: userId, aud: 'authenticated', role: 'authenticated', email: 'ui-check@example.com',
          app_metadata: { provider: 'email', providers: ['email'] }, user_metadata: {}, identities: [], created_at: new Date().toISOString() };
        const token = `${Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url')}.${Buffer.from(JSON.stringify({ sub: userId, role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')}.ui-fixture`;
        let orderCreated = false, approved = false;
        let account = { user_id: userId, full_name: 'UI Verification', phone: '0901234567',
          role: role === 'operator' ? 'customer' : role, requested_role: null, blocked: false };
        let addresses = [];
        let paymentCreated = false, paymentReconciled = false;
        page.on('pageerror', error => errors.push(error.message));
        const cors = { 'access-control-allow-origin': 'http://127.0.0.1:8080',
          'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,OPTIONS' };
        await page.route('**/*.supabase.co/**', route => {
          if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
          const url = new URL(route.request().url());
          if (url.pathname === '/auth/v1/token') return route.fulfill({ headers: cors, json: { access_token: token, token_type: 'bearer', expires_in: 3600, refresh_token: 'ui-fixture-refresh', user } });
          if (url.pathname === '/auth/v1/user') return route.fulfill({ headers: cors, json: user });
          if (url.pathname === '/rest/v1/delivery_api_profiles') return route.fulfill({ headers: cors, json: [{ role: role === 'operator' ? 'operator' : 'user' }] });
          return route.fulfill({ headers: cors, status: 403, json: { message: 'UI fixture only' } });
        });
        await page.route('http://127.0.0.1:8787/**', route => {
          const request = route.request();
          if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
          const url = new URL(request.url());
          const data = { headers: cors };
          if (url.pathname.startsWith('/delivery/cloud/addresses')) {
            if (request.method() === 'POST') {
              const body = request.postDataJSON();
              addresses = body.delete ? [] : [{ ...body.details, id: url.pathname.split('/').pop(), version: 1 }];
            }
            return route.fulfill({ ...data, json: { addresses } });
          }
          if (/\/orders\/[^/]+\/payment(?:\/refresh)?$/.test(url.pathname)) {
            if (request.method() === 'POST') {
              paymentCreated = true;
              if (url.pathname.endsWith('/refresh')) paymentReconciled = true;
            }
            return route.fulfill({ ...data, json: { configured: true, payment: paymentCreated ? {
              id: 'payment-ui-fixture', status: paymentReconciled ? 'PAID' : 'PENDING', amount: 25000,
              checkout_url: 'https://pay.payos.vn/web/ui-fixture', expires_at: '2026-11-01T10:00:00Z',
            } : null } });
          }
          if (/\/orders\/[^/]+\/shipment$/.test(url.pathname)) {
            return route.fulfill({ ...data, json: { configured: true, shipment: {
              ghn_order_code: 'GHN-UI-VERIFICATION', status: 'ready_to_pick', total_fee: 28000,
              expected_delivery_time: '2026-11-01T10:00:00Z',
            } } });
          }
          if (url.pathname === '/delivery/cloud/profile') {
            if (request.method() === 'POST') {
              const body = request.postDataJSON();
              assert.deepEqual(Object.keys(body).sort(), ['full_name', 'phone', 'requested_role']);
              account = { ...account, full_name: body.full_name, phone: body.phone,
                requested_role: body.requested_role === account.role ? null : body.requested_role };
            }
            return route.fulfill({ ...data, json: { schema_version: 2, operator: role === 'operator', account } });
          }
          if (url.pathname === '/delivery/cloud/merchants') return route.fulfill({ ...data, json: { merchants: [] } });
          if (url.pathname === '/delivery/cloud/marketplace/catalog') return route.fulfill({ ...data, json: { products: [], next: null, categories: [] } });
          if (url.pathname.startsWith('/delivery/cloud/accounts/') && request.method() === 'POST') {
            const body = request.postDataJSON();
            assert.equal(body.role, 'driver'); assert.equal(body.blocked, false);
            approved = true;
            return route.fulfill({ ...data, json: {} });
          }
          if (url.pathname === '/delivery/cloud/accounts') return route.fulfill({ ...data, json: { accounts: [{ user_id: userId, full_name: 'UI Verification', phone: '0901234567', role: approved ? 'driver' : 'customer', requested_role: approved ? null : 'driver', blocked: false }] } });
          if (url.pathname === '/delivery/cloud/quote') return route.fulfill({ ...data, json: { shipping_fee: 25000, distance_meters: 1800, pricing_version: 1, breakdown: { base_fee: 25000, distance_fee: 0, weight_fee: 0, express_fee: 0 } } });
          if (url.pathname === '/delivery/cloud/pricing') return route.fulfill({ ...data, json: { pricing: { base_fee: 25000, per_km: 5000, express_fee: 10000, extra_kg: 3000, version: 1 } } });
          if (/\/orders\/[^/]+\/history$/.test(url.pathname)) return route.fulfill({ ...data, json: { history: [
            { order_id: '10000000-0000-0000-0000-000000000001', action: 'create', status: 'searching', version: 1, created_at: '2026-10-29T00:00:00Z', reason: null },
          ] } });
          if (url.pathname === '/delivery/cloud/orders') {
            const order = { id: '10000000-0000-0000-0000-000000000001', tracking_code: 'CL-UI-VERIFICATION', status: 'searching',
              merchant_ready: true, version: 1, shipping_fee: 25000, cod_amount: 100000, owner_id: userId, created_at: new Date().toISOString(),
              details: { pickup_address: '12 Nguyen Hue', dropoff_address: '20 Le Loi', pickup_lat: 10.77, pickup_lng: 106.7, dropoff_lat: 10.78, dropoff_lng: 106.71, recipient_name: 'UI Receiver', recipient_phone: '0912345678', package_description: 'Documents', weight_kg: 1, service_type: 'standard', payment_method: 'sender_cash' } };
            if (request.method() === 'POST') { orderCreated = true; return route.fulfill({ ...data, json: { order } }); }
            return route.fulfill({ ...data, json: { orders: role !== 'customer' || orderCreated ? [order] : [] } });
          }
          if (url.pathname === '/delivery/places') {
            const q = url.searchParams.get('q') || '';
            const isPickup = q.includes('12') || q.toLowerCase().includes('nguyen hue');
            return route.fulfill({
              ...data,
              json: {
                autocomplete: true,
                attribution: 'Google Maps',
                places: [
                  isPickup
                    ? { title: '12 Nguyễn Huệ', address: '12 Nguyen Hue', latitude: 10.77, longitude: 106.7 }
                    : { title: '20 Lê Lợi', address: '20 Le Loi', latitude: 10.78, longitude: 106.71 },
                ],
              },
            });
          }
          if (url.pathname === '/delivery/reverse') {
            return route.fulfill({ ...data, json: { address: '12 Nguyen Hue', attribution: 'Google Maps' } });
          }
          return route.fulfill({ ...data, status: 403, json: { error: 'UI fixture only' } });
        });
        await page.goto(`http://127.0.0.1:8080/#/${role === 'operator' ? 'cloud-admin' : 'cloud'}`, { waitUntil: 'domcontentloaded' });
        const enable = page.locator('flt-semantics-placeholder');
        await enable.waitFor({ timeout: 30000 });
        await enable.evaluate(element => element.click());
        await fillField(page.getByRole('textbox', { name: 'Email', exact: true }), user.email);
        const password = page.getByRole('textbox', { name: 'Mật khẩu', exact: true });
        await password.click();
        await password.pressSequentially('ui-only-password', { delay: 20 });
        await page.waitForTimeout(200);
        await page.getByRole('button', { name: 'Đăng nhập', exact: true }).last().click();
        const navigate = async name => {
          const label = name === 'Tài khoản' ? (width < 860 ? 'Hồ sơ' : 'Hồ sơ cá nhân') : name === 'Gửi hàng' ? 'Đơn hàng' : name;
          await page
            .getByRole('button', { name: label, exact: true })
            .or(page.getByLabel(new RegExp('^' + label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))))
            .or(page.getByText(label, { exact: true }))
            .first()
            .click();
        };
        const profileAction = () => role === 'operator'
          ? page.getByRole('button', { name: 'Thông tin tài khoản', exact: true })
          : page.getByRole('button', { name: 'Hồ sơ cá nhân', exact: true }).last();
        if (role !== 'operator') {
          await navigate('Tài khoản');
          await page.getByRole('button', { name: 'Sổ địa chỉ', exact: true }).waitFor({ timeout: 10000 });
        }
        try {
          await profileAction().waitFor({ timeout: 10000 });
        } catch (error) {
          await page.screenshot({ path: path.join(output, 'cloud-signin-failure.png') });
          console.log((await page.locator('flt-semantics').allTextContents()).join(' ').slice(0, 1800));
          throw error;
        }
        await profileAction().click();
        const profileName = page.getByRole('textbox', { name: 'Họ và tên', exact: true });
        await fillField(profileName, `Verified ${role}`);
        await page.screenshot({ path: path.join(output, `cloud-profile-${role}-${width}.png`) });
        await page.getByRole('button', { name: 'Lưu hồ sơ', exact: true }).click();
        await profileName.waitFor({ state: 'hidden' });
        assert.equal(account.full_name, `Verified ${role}`);
        assert.equal(account.role, role === 'operator' ? 'customer' : role);
        await profileAction().waitFor();
        if (role === 'customer') {
          await page.getByRole('button', { name: 'Sổ địa chỉ', exact: true }).click();
          try {
            await page.getByRole('button', { name: 'Thêm địa chỉ', exact: true }).click();
          } catch (error) {
            await page.screenshot({ path: path.join(output, `cloud-address-failure-${width}.png`) });
            console.log((await page.locator('flt-semantics').allTextContents()).join(' ').slice(0, 1800));
            throw error;
          }
          for (const [name, value] of [['Tên gợi nhớ', 'Home'], ['Tên người nhận', 'UI Receiver'],
            ['Số điện thoại', '0912345678'], ['Địa chỉ', '20 Le Loi'], ['Vĩ độ', '10.78'], ['Kinh độ', '106.71']]) {
            const field = page.getByRole('textbox', { name, exact: true });
            await fillField(field, value);
          }
          const saveAddress = page.getByRole('button', { name: 'Lưu địa chỉ', exact: true });
          await saveAddress.scrollIntoViewIfNeeded(); await saveAddress.click();
          await page.getByText('Home · Mặc định', { exact: true }).waitFor();
          assert.equal(addresses.length, 1); assert.equal(addresses[0].is_default, true);
          await page.screenshot({ path: path.join(output, `cloud-addresses-${width}.png`) });
          await page.getByRole('button', { name: /^(Back|Quay lại)$/ }).last().click();
          await navigate('Gửi hàng');
          await page.getByRole('button', { name: 'Tạo đơn hàng', exact: true }).click();
          assert.equal(await page.getByRole('textbox', { name: 'Vĩ độ', exact: true }).count(), 0);
          assert.equal(await page.getByRole('textbox', { name: 'Kinh độ', exact: true }).count(), 0);
          await fillField(page.getByRole('textbox', { name: 'Địa chỉ lấy hàng', exact: true }), '12 Nguyen Hue');
          const findPickup = page.getByRole('button', { name: 'Tìm điểm lấy trên Google Map', exact: true });
          await findPickup.scrollIntoViewIfNeeded();
          await findPickup.click();
          const pickupOption = page.getByText('12 Nguyen Hue', { exact: true }).last();
          await pickupOption.waitFor({ timeout: 5000 });
          await pickupOption.click();
          await fillField(page.getByRole('textbox', { name: 'Địa chỉ giao hàng', exact: true }), '20 Le Loi');
          const findDropoff = page.getByRole('button', { name: 'Tìm điểm giao trên Google Map', exact: true });
          await findDropoff.scrollIntoViewIfNeeded();
          await findDropoff.click();
          const dropoffOption = page.getByText('20 Le Loi', { exact: true }).last();
          await dropoffOption.waitFor({ timeout: 5000 });
          await dropoffOption.click();
          for (const [name, value] of [
            ['Tên người nhận', 'UI Receiver'], ['Số điện thoại người nhận', '0912345678'],
            ['Hàng hóa', 'Documents'], ['Khối lượng (kg)', '1'], ['Tiền thu hộ (đồng)', '100000'],
          ]) {
            await fillField(page.getByRole('textbox', { name, exact: true }), value);
          }
          const quote = page.getByRole('button', { name: 'Lấy báo giá', exact: true });
          await page.mouse.move(width / 2, 800); await page.mouse.wheel(0, 1800); await page.waitForTimeout(400);
          await quote.scrollIntoViewIfNeeded(); await quote.click();
          const confirm = page.getByRole('button', { name: 'Xác nhận tạo đơn', exact: true });
          await page.waitForTimeout(300); await page.mouse.wheel(0, 500); await page.waitForTimeout(300);
          await confirm.scrollIntoViewIfNeeded();
          await page.screenshot({ path: path.join(output, `cloud-quote-${width}.png`) });
          await confirm.click();
          try {
            await page.getByRole('button', { name: 'Chi tiết', exact: true }).waitFor({ timeout: 10000 });
          } catch (error) {
            await page.screenshot({ path: path.join(output, 'cloud-create-failure.png') });
            console.log(JSON.stringify({ orderCreated, errors }));
            console.log((await page.locator('flt-semantics').allTextContents()).join(' ').slice(0, 1800));
            throw error;
          }
        }
        if (role === 'driver') await navigate('Gửi hàng');
        const detail = page.getByRole('button', { name: 'Chi tiết', exact: true });
        await detail.scrollIntoViewIfNeeded(); await detail.click();
        await page.getByRole('button', { name: 'Sao chép mã vận đơn', exact: true }).waitFor({ timeout: 10000 });
        await page.screenshot({ path: path.join(output, `cloud-details-${role}-${width}.png`) });
        const history = page.getByText('Lịch sử đơn hàng', { exact: true });
        await history.scrollIntoViewIfNeeded();
        await page.mouse.move(width / 2, 700);
        await page.mouse.wheel(0, 1000);
        await page.waitForTimeout(400);
        await page.getByText('Tạo đơn', { exact: true }).waitFor();
        await page.screenshot({ path: path.join(output, `cloud-history-${role}-${width}.png`) });
        if (role === 'customer') {
          const repeat = page.getByRole('button', { name: 'Gửi lại đơn', exact: true });
          await repeat.scrollIntoViewIfNeeded(); await repeat.click();
          await page.getByRole('textbox', { name: 'Địa chỉ lấy hàng', exact: true }).waitFor();
          const quote = page.getByRole('button', { name: 'Lấy báo giá', exact: true });
          await quote.scrollIntoViewIfNeeded(); await quote.click();
          const confirm = page.getByRole('button', { name: 'Xác nhận tạo đơn', exact: true });
          await confirm.waitFor(); await confirm.scrollIntoViewIfNeeded();
          await page.screenshot({ path: path.join(output, `cloud-repeat-${width}.png`) });
          await confirm.click();
          await page.getByRole('button', { name: 'Chi tiết', exact: true }).waitFor();
        } else {
          assert.equal(await page.getByRole('button', { name: 'Gửi lại đơn', exact: true }).count(), role === 'operator' ? 1 : 0);
          await page.getByRole('button', { name: /^(Back|Quay lại)$/ }).last().click();
        }
        if (role !== 'driver') {
          const payment = page.getByRole('button', { name: 'Thanh toán cước', exact: true });
          await payment.scrollIntoViewIfNeeded(); await payment.click();
          const createPayment = page.getByRole('button', { name: 'Tạo liên kết payOS', exact: true });
          await createPayment.click();
          await page.getByRole('button', { name: 'Mở thanh toán', exact: true }).waitFor();
          await page.screenshot({ path: path.join(output, `commerce-payment-${role}-${width}.png`) });
          await page.getByRole('button', { name: 'Tải lại', exact: true }).last().click();
          await page.getByText('Đã thanh toán', { exact: true }).waitFor();
          assert.equal(paymentReconciled, true);
          await page.getByRole('button', { name: 'Đóng', exact: true }).click();
          if (role === 'operator') {
            const carrier = page.getByRole('button', { name: 'Vận chuyển GHN', exact: true });
            await carrier.scrollIntoViewIfNeeded(); await carrier.click();
            await page.getByText('Trạng thái hãng: ready_to_pick', { exact: true }).waitFor();
            await page.screenshot({ path: path.join(output, `commerce-shipment-${width}.png`) });
            await page.getByRole('button', { name: 'Đóng', exact: true }).click();
          }
        }
        if (role === 'operator') {
          await page.getByRole('button', { name: 'Bảng giá cloud', exact: true }).click();
          await page.getByRole('button', { name: 'Lưu bảng giá', exact: true }).waitFor();
          await page.waitForTimeout(400);
          await page.screenshot({ path: path.join(output, `cloud-pricing-${width}.png`) });
          await page.getByRole('button', { name: 'Đóng', exact: true }).click();
          await page.getByRole('button', { name: 'Tài khoản', exact: true }).click();
          const approve = page.getByRole('button', { name: 'Duyệt Tài xế', exact: true });
          await approve.scrollIntoViewIfNeeded();
          await approve.click();
          assert.equal(approved, false);
          await page.getByRole('button', { name: 'Xác nhận', exact: true }).click();
          await approve.waitFor({ state: 'hidden' });
          assert.equal(approved, true);
        }
        await page.screenshot({ path: path.join(output, `cloud-${role}-${width}.png`) });
        assert.deepEqual(errors, []);
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
        console.log(JSON.stringify({ width, role, fixtureOnly: true, created: orderCreated, errors: errors.length }));
        await context.close();
      }
    }
  } catch (error) {
    if (activePage && !activePage.isClosed()) {
      await activePage.screenshot({ path: path.join(output, 'cloud-browser-failure.png') });
      console.log((await activePage.locator('flt-semantics').allTextContents()).join(' ').slice(-4500));
    }
    throw error;
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
