# Current Handoff

## Softened GHST Studio Geometry & Shadows (`tránh bị cứng`) with Original Dark Shell & Minh Nhan's `66aeb36` Palette - 2026-11-03

- Refined the visual geometry across consumer, partner, legacy, public tracking, and operator admin interfaces to eliminate Neo-Brutalist rigidity (`0px` square corners, `1.5px–2.0px` heavy `#0F172A` borders, and zero-blur `Offset(3..6, 3..6)` slab shadows -> `0` remaining `BorderRadius.zero` and `0` zero-blur `BoxShadow` across `gps_delivery_app/lib/`) while preserving 100% of the original GHST dark-shell identity (`#0F172A` 3D route-ribbon login backdrop, `#0F172A` desktop sidebar, `#0F172A` mobile header/bottom bar, `#0F172A` `G OPS` Admin showcase), Minh Nhan's `66aeb36` color palette, and `VietQrBankPaymentPanel` (`ISO/IEC 18004 V1-V9`):
  1. **Design Tokens & Shared Themes (`app_colors.dart`, `app_theme.dart`, `admin_studio_theme.dart`)**:
     - Kept Minh Nhan's `66aeb36` palette (`#F4F7FA` paper, `#FFFFFF` surface, `#F8FAFC` subtle surface, `#0F172A` ink/dark shell, `#1E293B` elevated dark panel, `#2563EB` primary blue, `#6EE7B7` mint accent, `#F43F5E` rose, `#F59E0B` amber) and added `controlBorder` (`#CBD5E1`), `primarySoft` (`#EFF6FF`), `primaryBorder` (`#BFDBFE`), `cardShadow`, and `elevatedShadow`.
     - Replaced `0.0` `AppSpacing` radii and sharp `BorderRadius.zero` borders with concentric `10px–24px` radii (`buttonRadius = 12`, `inputRadius = 12`, `cardRadius = 16`, `inputHeight = 50`), `1px` `#E2E8F0` / `#CBD5E1` hairlines, resting `#F8FAFC` inputs (`#2563EB` `1.8px` focused ring), pill `ChipThemeData`, and rounded `AdminStudioMark` / `AdminNeoBox` (`14px` radius + multi-layer diffused shadow).
  2. **Auth, Role-Synchronized Shell & Screens (`studio_user_auth_frame.dart`, `cloud_auth_screen.dart`, `ghst_user_shell.dart`, `ghst_home_screen.dart`, `admin_portal_screen.dart`, `architecture_dashboard_screen.dart`, `studio_design_widgets.dart`, & `/legacy` views)**:
     - Replaced the sharp blue `SegmentedButton` on `/` and `/legacy` login cards with a recessed `StudioAuthTabBar` (`14px` `#F1F5F9` track + `10px` elevated white active pill) inside a `24px` white floating card over the `#0F172A` 3D route-ribbon backdrop so only the primary CTA is `#2563EB`.
     - Softened `GhstUserShell` while keeping the dark `#0F172A` desktop sidebar and dark `#0F172A` mobile header/bottom bar: pill role-switcher chips, `10px` rounded sidebar menu items, `10px` rounded avatar badge, hairline `techLine`/`line` dividers, diffused elevation shadows, and rounded active bottom-nav pills.
     - Softened `GhstHomeScreen`, `GhstAiChatScreen`, `CloudPromoEventsScreen`, `PublicOrderTrackingScreen`, `AdminPortalScreen`, `AdminAccountsPanel`, `BackendIntegrationSettings`, `BackendReadinessDialog`, `InAppGoogleOAuthDialog`, `SystemStateScreens`, `VietQrBankPaymentPanel`, `StudioMarkWordmark`, and all `/legacy` subsystem views.
- Checks run:
  - Static & Automated Tests: `flutter analyze --no-pub` (`0` issues) and `flutter test --no-pub` across `14` suites (`129/129` passed: `unified_user_interface_test.dart`, `ghst_home_test.dart`, `ghst_ai_chat_test.dart`, `cloud_promo_events_test.dart`, `admin_accounts_panel_test.dart`, `backend_integration_settings_test.dart`, `backend_readiness_test.dart`, `cloud_orders_test.dart`, `cloud_order_details_test.dart`, `cloud_commerce_test.dart`, `competitor_features_test.dart`, `marketplace_test.dart`, `profile_push_shipping_coins_test.dart`, `clean_start_test.dart`).
  - Browser & Visual Verification: built `--no-web-resources-cdn` Web Release (`46` files, `0` secret leaks, `serviceWorkerVersion: 328896230`), passed `run-admin-browser-check.mjs` (`1440px` & `360px`, `errors: 0`), and visually verified rendered headless Edge screenshots across `/`, `/#/legacy`, `/#/admin`, and `/#/track` at `1440px` & `360px` (`overflow: 0`, `errors: 0`, `LocalDevPortsCount: 0`).
  - Live Deployments: pushed Web Admin commit `89a8292` to `origin/backend-admin`, rebuilt Windows Desktop Release (`build\windows\x64\runner\Release\gps_delivery_app.exe`), and relaunched `GHST - Khach Hang` & `GHST - Tai Xe` interactively on `SessionId: 1` (`Responding: True`). Skipped Android APK build/deploy and `graphify` per user instructions.
- Remaining limits & next step: Inspect the side-by-side Windows Desktop windows (`GHST - Khach Hang` & `GHST - Tai Xe`) and live Web portal; enter merchant `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready.

## Original GHST Studio Frame Restored with Minh Nhan's `66aeb36` Color Palette & VietQR Payment Flows - 2026-11-03

- Restored 100% of the original GHST Studio design, frame geometry, sharp `BorderRadius.zero` borders, solid offset slab shadows, dark 3D login backdrop, dark mobile header/bottom navigation bar, and chamfered `G OPS` Admin Portal from `af9e9e2`, while applying Minh Nhan's new color palette from commit `66aeb36` (`#F4F7FA` slate-white paper, `#0F172A` navy-ink/dark shell, `#1E293B` elevated panel, `#2563EB` primary blue, `#6EE7B7` mint accent, `#F43F5E` rose, `#F59E0B` amber) across the entire codebase and preserving 100% of `66aeb36`'s Bank Transfer & VietQR (`NAPAS 247`) payment flows:
  1. **Original GHST Studio Frame & Geometry (`af9e9e2`)**:
     - Restored `app_theme.dart` (`AppSpacing` `0.0` radii, sharp `BorderRadius.zero` cards/buttons/chips/inputs), `admin_studio_theme.dart` (chamfered `AdminStudioMark`, `AdminStudioGridBackdrop`, sharp `AdminNeoBox` with solid offset shadows), `studio_user_auth_frame.dart` (dark 3D route-ribbon backdrop + sharp floating card with triple offset shadows), `cloud_auth_screen.dart` (`SegmentedButton`), `ghst_user_shell.dart` (grouped dark desktop sidebar + dark mobile header & dark bottom bar), `ghst_home_screen.dart`, `ghst_ai_chat_screen.dart`, `cloud_promo_events_screen.dart`, `public_order_tracking_screen.dart`, `admin_portal_screen.dart`, `admin_accounts_panel.dart`, `backend_integration_settings.dart`, `backend_readiness_dialog.dart`, `architecture_dashboard_screen.dart`, `in_app_google_oauth_dialog.dart`, `studio_design_widgets.dart`, and `system_state_screens.dart`.
  2. **Minh Nhan's `66aeb36` Color Palette & VietQR Integration Unified Across All Screens**:
     - Applied `AppColors` and `AdminStudioColors` from `66aeb36` (`#F4F7FA`, `#0F172A`, `#1E293B`, `#2563EB`, `#6EE7B7`, `#F43F5E`, `#F59E0B`, `#EFF6FF`, `#ECFDF5`), updated `web/manifest.json` (`#F4F7FA` / `#2563EB`), aligned `VietQrBankPaymentPanel` (`vietqr_bank_payment_panel.dart`), `customer_subsystem_views.dart`, and `customer_order_and_pricing_views.dart` to the sharp GHST Studio frame, and replaced all remaining hardcoded old Neo-Brutalist color literals (`0` old `#5B33E6` / `#CBFF3E` / `#F5F1E8` / `#15131E` literals left across `lib/`).
- Checks run:
  - Static & Automated Tests: `flutter analyze --no-pub` (`0` issues) and `flutter test --no-pub` across `14` suites (`129/129` passed, incl. `unified_user_interface_test.dart`, `ghst_home_test.dart`, `ghst_ai_chat_test.dart`, `cloud_promo_events_test.dart`, `admin_accounts_panel_test.dart`, `backend_integration_settings_test.dart`, `backend_readiness_test.dart`, `cloud_orders_test.dart`, `cloud_order_details_test.dart`, `cloud_commerce_test.dart`, `competitor_features_test.dart`, `marketplace_test.dart`, `profile_push_shipping_coins_test.dart`, `clean_start_test.dart`).
  - Browser & Visual Verification: built `--no-web-resources-cdn` Web Release (`46` files, `0` secret leaks, `serviceWorkerVersion: 2592256565`), passed `run-admin-browser-check.mjs` (`1440px` & `360px`, `errors: 0`), and visually verified rendered headless Edge screenshots across `/`, `/#/legacy`, `/#/admin`, and `/#/track` at `1440px` & `360px` (`overflow: 0`, `errors: 0`).
  - Live Deployments: pushed Web Admin commit `bcfd8b4` to `origin/backend-admin`, rebuilt Windows Desktop Release (`build\windows\x64\runner\Release\gps_delivery_app.exe`), and relaunched `GHST - Khach Hang` & `GHST - Tai Xe` on `SessionId: 1` (`Responding: True`). Skipped Android APK build/deploy per user instruction.
- Remaining limits & next step: Inspect the running Windows Desktop windows (`GHST - Khach Hang` & `GHST - Tai Xe`) and live Web portal; enter merchant `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready.

## Bank Transfer & VietQR Payment (`VietQrBankPaymentPanel`, ISO/IEC 18004 V1-V9), Modern Super-App UI Refresh & Live Local Web Preview (`:8080`) - 2026-11-03

- Completed three user-requested upgrades and launched a live dual-stack local Web test server:
  1. **Bank Transfer (`Chuyển khoản ngân hàng`) & Scannable VietQR (`NAPAS 247` / EMVCo TLV + CRC16)**:
     - Extended `SecurityAndBarcodeUtils.generateEmvVietQrPayload` and upgraded `_QrMatrixPainter._encodeIso18004Matrix` to ISO/IEC 18004 Versions `1..9` Level L (`<= 230` bytes, 2-block RS interleaving for V6-V9, Annex E multi-alignment centers, Golay `(18,6)` Version Info for V7-V9) in `gps_delivery_app/lib/core/utils/security_and_barcode_utils.dart`.
     - Added reusable responsive `VietQrBankPaymentPanel` (`gps_delivery_app/lib/presentation/widgets/vietqr_bank_payment_panel.dart`) with 10 built-in Vietnam NAPAS 247 banks + live `BankDirectoryService` enrichment, scannable `QrMatrixPainterWidget`, beneficiary details, and 1-tap copy actions (account number, exact VND amount, and `GHST <shortRef>` transfer memo).
     - Integrated across canonical Cloud shipping & marketplace flows (`cloud_commerce_dialog.dart`, `cloud_order_form.dart`, `marketplace_view.dart`, `cloud_order_details_screen.dart` with server-authoritative `PAID` invariant preserved) and Legacy multi-role demo flows (`app_state_order_and_admin_ops.dart`, `customer_subsystem_views.dart`, `customer_order_and_pricing_views.dart`, `customer_grab_food_views.dart`, `customer_history_and_profile_views.dart`).
  2. **Clean, High-Contrast Modern Super-App UI Restyle**:
     - Refreshed `app_colors.dart`, `app_theme.dart`, `admin_studio_theme.dart`, `ghst_user_shell.dart`, `ghst_home_screen.dart`, `studio_user_auth_frame.dart`, `cloud_auth_screen.dart`, `vietqr_bank_payment_panel.dart`, and legacy customer views from harsh Neo-Brutalist `#F5F1E8` beige / `0px` square black borders / `Offset(5, 5)` hard shadows / `#CBFF3E` neon button text to a calm daylight palette (`#F4F7FA` soft slate background, `#FFFFFF` cards, `10px-16px` rounded geometry, `#E2E8F0` subtle borders, diffused shadows, `#2563EB` primary buttons with crisp white text, and `#0F172A`/`#475569` WCAG-compliant typography).
  3. **Live Dual-Stack Local Web Preview (`http://localhost:8080`)**:
     - Built `gps_delivery_app/build/web` (`--no-wasm-dry-run --no-web-resources-cdn --dart-define=DELIVERY_API_BASE_URL=/delivery/`) and started dual-stack `127.0.0.1:8080` + `[::1]:8080` preview server (`serve-test-preview.cjs`) with `/health` and `/delivery/*` proxied to `https://ghst-backend-admin.onrender.com` per explicit user test-link request.
- Checks run: `flutter analyze --no-pub` (`No issues found!`), `flutter test --no-pub` across `unified_user_interface_test.dart`, `ghst_home_test.dart`, `cloud_commerce_test.dart`, `cloud_order_details_test.dart`, `cloud_orders_test.dart`, `cloud_commercial_suite_test.dart`, `admin_accounts_panel_test.dart`, `backend_integration_settings_test.dart`, `cloud_account_session_test.dart`, `competitor_features_test.dart`, and `widget_test.dart` (`TC-01`) -> all passed at `360px` & `1440px`; `flutter build web` (exit `0`); HTTP `200` verified on `http://localhost:8080/`, `http://127.0.0.1:8080/`, `/legacy`, `/admin`, and `/health`.
- Remaining limits & next step: Local preview server `:8080` is intentionally kept running for active browser testing; commit/push to `origin/main` & `origin/backend-admin` when user confirms visual style and payment UX.

## Driver Cash/COD Settlement (`collect_cash`), `payOS` Webhook Auto-Verification (`20261112_shipping_cash_settlement`, workflow 18) & Multi-Platform Release Deploy - 2026-11-03

- Implemented both end-to-end payment workflows (`100%` server-authoritative PostgreSQL + Node Gateway + Flutter UI, `0` mock receipts or placeholder keys):
  1. **Driver & Operator Cash Shipping Fee / COD Settlement (`collect_cash`)**:
     - Added `cash_collected_fee`, `cash_collected_cod`, `cash_collected_at`, and `cash_collected_by` with `delivery_cloud_orders_cash_collected_check` on `public.delivery_cloud_orders` in `gps_delivery_app/database/migrations/20261112_shipping_cash_settlement.sql` (`migrate-cloud.mjs`, `deployment-readiness.mjs`, `workflowVersion: 18`), plus forward-compatible coin ledger constraint update in `20261110_cloud_promo_events.sql`.
     - Hardened `public.delivery_commerce_guard()` to block dual cash + online fee collection (`PT409`), extended `public.delivery_cloud_transition` + `POST /delivery/cloud/orders/:id/transition` (`cloud-orders.mjs`, `CLOUD_ORDERS.md`) with `'collect_cash'` (`payable_fee` -> `cash_collected_fee` + `PAID`, `cod_amount` -> `cash_collected_cod`, audited in `delivery_cloud_history`), and emitted unified notifications (`cash_collected` & `payment_paid`).
     - Wired `cloud_order_labels.dart`, `cloud_orders_screen.dart` (`Xác nhận thu tiền mặt` confirmation dialog, `Đã thu tiền mặt cước · Đã thu hộ COD`, and smart `'Thanh toán cước'` gating so non-operators only see online payment when actionable or paid online/in review), and `cloud_order_details_screen.dart` (`Cước và thu hộ` cash breakdown).
  2. **`payOS` VietQR Online Payment Readiness & Auto-Webhook Verification**:
     - Added `normalizeCredentialToken`, `publicBackendUrl`, `PAYOS_*` credential normalization, and live `testIntegration('payos')` in `gps_delivery_app/backend/otp-relay/integration-config.mjs` (automatically verifying all 3 keys and registering `${PUBLIC_BASE_URL}/delivery/payments/webhook` via `POST https://api-merchant.payos.vn/confirm-webhook`, or `/v2/payment-requests/0` on loopback), plus `resolvePayosRedirectUrl` HTTPS fallback in `payment-gateway.mjs`.
     - Added copyable `payos-webhook-url` banner in `backend_integration_settings.dart` (`/admin` -> `Tích hợp` -> `payOS thanh toán`) and `AppLifecycleState.resumed` auto-refresh + `provider_order_code` + `Kiểm tra thanh toán` button in `cloud_commerce_dialog.dart`.
- Checks run:
  - Backend & PostgreSQL 17: `npm test` (`128/128` passed, incl. new `collect_cash` & `testIntegration('payos')` tests), `npm run test:postgres` (`28/28` disposable PostgreSQL 17 checks passed), and `npm run migrate:cloud` on live Supabase PostgreSQL (`ready: true`, `migration: 20261112_shipping_cash_settlement`, `workflowVersion: 18`).
  - Flutter: `flutter analyze --no-pub` (`0` issues) and `flutter test --no-pub` across `7` suites (`82/82` passed: `cloud_commerce_test.dart`, `cloud_order_details_test.dart`, `cloud_orders_test.dart`, `backend_integration_settings_test.dart`, `backend_readiness_test.dart`, `profile_push_shipping_coins_test.dart`, `cloud_account_session_test.dart`).
  - Live Deployments: deployed zero-secret 46-file Web Admin + backend commit `bf2f290` (`serviceWorkerVersion: 1302150573`) to `origin/backend-admin` and verified live on `https://ghst-backend-admin.onrender.com/health` (`200`); rebuilt & relaunched dual Windows Desktop Release instances (`GHST - Khach Hang` & `GHST - Tai Xe`, `SessionId: 1`, `Responding: True`); rebuilt & installed `android-arm64` Release APK onto physical `Xiaomi 2602BRT18C` (`PZ8T6HQWCIFUUKXK`, `scrcpy` `SessionId: 1`, `Responding: True`, `localListeningPorts: 0`).
- Remaining limits & next step: Enter real merchant `PAYOS_CLIENT_ID`, `PAYOS_API_KEY`, and `PAYOS_CHECKSUM_KEY` in `/#/admin` -> `Tích hợp` -> `payOS thanh toán` and click `Lưu` + `Kiểm tra kết nối` to activate live VietQR checkout & webhook settlement.

## Git Mainline Deploy (`ebe6596`), Multi-Instance Desktop Session Slots (`--session-slot`) & Live Dual-Window Customer ↔ Driver UI E2E Acceptance - 2026-11-03

- Completed mainline Git deployment, isolated desktop multi-instance support, and live UI-driven two-role (Customer ↔ Driver) end-to-end verification on Windows Desktop against hosted Cloud PostgreSQL & Render Gateway:
  1. **Multi-Instance Desktop Session Isolation & Window Placement**:
     - Added `gps_delivery_app/lib/core/config/session_slot_storage.dart`, `session_slot_storage_stub.dart`, and `session_slot_storage_io.dart` (`LocalStorage` + `GotrueAsyncStorage` persisted per slot under `%LOCALAPPDATA%\GHST\sessions\<slot>.json`), wired through `gps_delivery_app/lib/main.dart` (`--session-slot=<slot>`, skipping shared SQLite lock acquisition on secondary slots while keeping primary instance behavior intact).
     - Extended `gps_delivery_app/windows/runner/main.cpp` to accept optional `--window-title=<title>` and `--window-bounds=<x>,<y>,<w>,<h>` for side-by-side desktop verification, and updated `.gitignore` (`*.url`).
  2. **Git Deployment (`origin/main` + `origin/backend-admin`)**:
     - Audited tracked/untracked diff for secrets (`0` credential leaks), committed and pushed `ebe6596` (`103` files) to `origin/main`, alongside live Render deployment `2fbc0a6` on `origin/backend-admin` (`https://ghst-backend-admin.onrender.com/health` `200`).
  3. **Live Dual-Window Customer ↔ Driver UI E2E Test (`windows-mcp`, `SessionId: 1`)**:
     - Launched two side-by-side native Windows Release instances on the active desktop (`1920x1080`, `localListeningPorts: 0`): `GHST - Khach Hang` (`0,0,960,1032`, verified Customer session) and `GHST - Tai Xe` (`960,0,960,1032`, `--session-slot=driver`, verified Driver Google OAuth PKCE session on `GHST DRIVER`).
     - Controlled `GHST - Khach Hang` UI (`Tạo đơn hàng mới`): pinned pickup & dropoff on Google Map, verified live `RecipientTrustPanel` (`88/100`), enabled `Dùng Xu giảm cước phí đơn hàng` (`shipping_fee: 25,000 VND`, `coin_discount: -50 VND`, `payable_fee: 24,950 VND`), quoted, and created real Cloud order `CL-4BB4BF93B7A741BF83C15D50F947597B`.
     - Controlled `GHST - Tai Xe` UI (`Sàn chuyến chờ nhận` -> `Chuyến giao của tôi`): refreshed queue (verifying pre-claim PII masking + intact `25,000 VND` driver tariff), clicked `Nhận chuyến`, verified instant Realtime update + unread badge + foreground alert on `GHST - Khach Hang`, stepped through `Đã đến lấy hàng` -> `Đã lấy hàng` -> `Giao thành công` -> `Đã giao`, and verified live `Đã giao` status across both windows plus native Windows 11 `Shell_NotifyIconW` toast notification and `5` unread Cloud notifications.
- Checks run: `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub test/clean_start_test.dart test/profile_push_shipping_coins_test.dart` (`8/8` passed), `flutter build windows --release --no-pub` (exit `0`), secret-pattern scan on staged diff (`0` leaks), and live dual-window `windows-mcp` UI E2E (`CL-4BB4BF93B7A741BF83C15D50F947597B` -> `Đã giao`).
- Remaining limits & next step: Both `GHST - Khach Hang` and `GHST - Tai Xe` remain open side-by-side on the desktop for live inspection/demo; configure optional `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and verify signed webhook settlement per `EXECUTION_CHECKLIST.md`.

## Cross-Platform Push & Unified Notification Center, Personal KYC Profile (`birth_date` & `citizen_id`), Shipping Fee Coin (`Xu`) Redemption/Accrual & Live Merchant Provisioning (`20261111_profile_push_shipping_coins`, workflow 17) - 2026-11-03

- Completed four production business & infrastructure upgrades across Cloud PostgreSQL, Node Gateway, Web Admin (`origin/backend-admin`), Windows Desktop, and physical Android (`scrcpy`):
  1. **Unified Cloud Notification Inbox & Cross-Platform Native Push (`Thông báo đẩy & Trung tâm thông báo`)**:
     - Added `public.delivery_user_notifications`, `public.delivery_notification_preferences`, domain event triggers, bidirectional sync/backfill with `public.delivery_market_notifications`, and `public.delivery_cloud_notifications(p_action, p_payload)` (`unread_count`, cursor-paginated `list`, `mark_read`, `mark_all_read`, `save_preferences`) in `gps_delivery_app/database/migrations/20261111_profile_push_shipping_coins.sql`, wired via fixed-action `POST /delivery/cloud/notifications/:action` in `gps_delivery_app/backend/otp-relay/cloud-orders.mjs` and `delivery-notifications.mjs` (`push_enabled` preference check before FCM dispatch).
     - Implemented native OS notification bridges across **Android** (`POST_NOTIFICATIONS` + high-importance `NotificationChannel("ghst_push_alerts")` in `gps_delivery_app/android/app/src/main/AndroidManifest.xml` & `MainActivity.kt`, plus optional FCM wrapped safely), **Windows Desktop** (Win32 `Shell_NotifyIconW` `NIF_INFO` toast banner in `gps_delivery_app/windows/runner/CMakeLists.txt`, `flutter_window.h`, `flutter_window.cpp`), and **Web** (`gps_delivery_app/lib/core/integrations/web_notification_bridge*.dart`).
     - Built `PushNotificationService` (`gps_delivery_app/lib/core/integrations/push_notification_service.dart`) and `CloudNotificationCenter` (`gps_delivery_app/lib/presentation/widgets/cloud_notification_center.dart`) with category/unread filters (`all`, `shipping`, `market`, `promo`, `account`), smart tap routing (shipping order, purchase services, purchase order chat on `kind == 'message'`, pickup, promo hub, profile), foreground `SnackBar`, and live unread badges across `GhstUserShell`, `MarketplaceScreen`, `MarketplaceView`, `AdminPortalScreen`, and `CloudOrdersScreen`.
  2. **Personal Profile KYC Identity (`Ngày tháng năm sinh` & `CCCD định danh`)**:
     - Added `birth_date date` (`1900-01-01` .. today) and `citizen_id text` (`^[0-9]{12}$` with unique partial index `delivery_cloud_accounts_citizen_id_key`) on `public.delivery_cloud_accounts`, exposed strictly to the account owner (`delivery_cloud_profile`) and Cloud Operators (`delivery_cloud_admin_accounts`), never in driver queues or public tracking.
     - Wired full validation, auto-inserting `dd/MM/yyyy` slash formatter (`BirthDateSlashFormatter` handling digit typing `15082001` -> `15/08/2001`, single-digit slash padding `5/` -> `05/`, ISO paste `2001-08-15` -> `15/08/2001`, and non-trapping Backspace), masking (`••••••••1234`), DatePicker, and KYC verification badges across `CloudAccountSession`, `CloudProfileForm`, `MarketplaceView._account()`, and Operator `AdminAccountsPanel` (`list` KPI/search/badge, `detail`, `_EditAccountProfileDialog`).
  3. **Coin (`Xu`) Redemption & Accrual on Shipping Order Fees (`Cước phí đơn hàng`)**:
     - Enabled server-authoritative `use_coins: true` on standalone shipping quotes & orders (`delivery_cloud_quote`, `delivery_cloud_create`, `delivery_cloud_orders_fee_sync`): redeems up to `20%` of `shipping_fee` (leaving `>= 1,000 VND` payable and keeping driver tariff `shipping_fee` intact while recording `coin_discount` & `payable_fee = shipping_fee - coin_discount`), charges `payable_fee` in `payment-gateway.mjs`, auto-refunds `release_shipping_cancel` on `cancelled`/`returned`, auto-credits `1%` `earn_shipping` on `delivered`, and extends `delivery_market_snapshot_v2` so Marketplace `20%` Xu cap covers `goods_total - voucher_disc + freight_total`.
     - Wired `Dùng Xu giảm cước phí đơn hàng` toggle, `payable_fee` quote breakdown, order cards/details, `CloudCommerceDialog`, and `MarketCommercialSheets` across Flutter.
  4. **Provisioned Live Merchant Account (`minhnhan@gmail.com`)**:
     - Provisioned and confirmed `minhnhan@gmail.com` (`user_id: 0c937976-6dda-4d06-aeab-465319458cc9`) in live Supabase Auth, upserted `delivery_cloud_accounts` (`role: 'merchant'`) and active `'merchant'` membership in `delivery_cloud_memberships` (`state: 'active'`), verified via live `POST /auth/v1/token` + `delivery_cloud_profile` RPC (`approvedRoles: ['merchant']`, `schemaVersion: 3`, `coinBalance: 0` — zero demo shops/products/orders/balances seeded), and removed the scratch script immediately.
- Checks run:
  - Backend & PostgreSQL 17: `npm test` (`126/126` passed, incl. `profile-push-coins.test.mjs`), `npm run test:postgres` (`28/28` disposable PostgreSQL 17 acceptance checks passed), and `npm run migrate:cloud` on live Supabase PostgreSQL (`ready: true`, `migration: 20261111_profile_push_shipping_coins`, `workflowVersion: 17`).
  - Flutter & Headless Edge: `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub` across `8` suites (`92/92` passed, incl. new `test/profile_push_shipping_coins_test.dart`), `run-admin-browser-check.mjs` (`1440px` & `360px` -> `errors: 0`), and `verify-live-render.cjs` on live `https://ghst-backend-admin.onrender.com/#/admin` (`1440px` & `360px` -> `status: 200`, `overflow: 0`, `errors: 0`).
  - Multi-Platform Builds & Deployments: deployed portable 46-file `--no-web-resources-cdn` Web Admin + backend commits `4504285`..`2fbc0a6` (`serviceWorkerVersion: 1747853443`, `0` secret leaks) to `origin/backend-admin` and verified live (`/health` `200`, `flutter_bootstrap.js` `1747853443`, `/delivery/cloud/notifications/unread_count` `401`); built & launched Windows Desktop Release (`gps_delivery_app.exe`, `PID: 19156`, `SessionId: 1`, `Responding: True`); rebuilt `android-arm64` Release APK (`27.5 MB`, `build\app\outputs\flutter-apk\app-release.apk`) with `BirthDateSlashFormatter` (previously installed `20261111` APK on `Xiaomi 2602BRT18C` / `PZ8T6HQWCIFUUKXK`; during the `2fbc0a6` APK install step `adb devices` had `0` connected devices, so reconnect USB/Wireless Debugging to run `adb install -r`; `localListeningPorts: 0`).
- Remaining limits & next step: Reconnect the physical Xiaomi phone (`PZ8T6HQWCIFUUKXK`) via USB/Wireless Debugging to install the updated `app-release.apk` (`BirthDateSlashFormatter`) and mirror via `scrcpy`; configure optional `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## OpenAI-Compatible Reasoning AI Gateway Resilience (`zai-org/GLM-5.3-Flash`), Timeout Alignment & Key Prefix Normalization - 2026-11-03

- Diagnosed why Customer AI Chat (`GhstAiChatScreen` -> `POST /delivery/cloud/ai-chat`) intermittently failed with `'Không kết nối được dịch vụ AI.'` on decentralized OpenAI-compatible reasoning models (`https://gate.joingonka.ai/v1/chat/completions`, `zai-org/GLM-5.3-Flash`):
  1. **Stale key in `public.delivery_backend_config`**: the previously saved `GEMINI_API_KEY` had been rotated on the provider dashboard and returned HTTP `401 authentication_error`.
  2. **Premature gateway & client timeouts (`25s` / `30s`)**: decentralized inference on `zai-org/GLM-5.3-Flash` empirically required up to `22s–32s` per multi-turn response, exceeding `callAiJson`'s `25000ms` timeout in `gps_delivery_app/backend/otp-relay/ai-assistant.mjs` and `DeliveryApiClient.request`'s `30s` timeout in `gps_delivery_app/lib/core/integrations/delivery_api_client.dart`.
  3. **Reasoning token starvation (`maxOutputTokens: 700`)**: `GLM-5.3-Flash` emits `150–700` `reasoning_tokens` before producing `message.content`; with `max_tokens: 700`, responses frequently hit `finish_reason: "length"` inside chain-of-thought without closing `</think>`, either starving `content` or leaking unseparated English reasoning.
  4. **Translated cURL header copy-paste**: browser auto-translation rendered `Authorization: Bearer ...` as `"Ủy quyền: Người mang ..."` on provider quickstart modals.
- Implemented production fixes across backend gateway and Flutter client:
  - `gps_delivery_app/backend/otp-relay/integration-config.mjs`: added `normalizeAiApiKey` (stripping accidental line wraps, quotes, and leading `Authorization:` / `Ủy quyền:` / `Bearer ` / `Người mang ` prefixes on both `updateIntegrationConfig` save and `testIntegration('gemini')` / runtime read) and raised `testIntegration('gemini')` `/models` + `/chat/completions` fallback bounds (`20s` / `25s`, `max_tokens: 32`).
  - `gps_delivery_app/backend/otp-relay/ai-assistant.mjs` & `delivery-integrations.mjs`: increased `callAiJson` timeout to `75000ms` (`504` on `TimeoutError`/`AbortError`), raised `maxOutputTokens` from `700` to `2048` across `generateAiReply`, `createCustomerAiChatHandler`, and `/support-summary`, stripped `<think>...</think>` blocks in `extractOpenAiContent`, blocked unseparated reasoning-exhausted `finish_reason: "length"` outputs from leaking raw chain-of-thought, and omitted the backend `model` identifier from `createCustomerAiChatHandler` responses.
  - `gps_delivery_app/lib/presentation/customer/ghst_ai_chat_screen.dart` & `gps_delivery_app/lib/core/integrations/delivery_api_client.dart`: removed backend model badge/label display (`activeModel`) from both `GhstAiFloatingBubble` (`CHAT AI GHST` -> `'Trợ lý trực tuyến'`) and `GhstAiChatScreen` (`TRỢ LÝ AI GHST EXPRESS`), and raised `effectiveTimeout` for `cloud/ai-chat`, `ai/chat`, and `support-summary` from `30s` to `90s`.
  - Synchronized the updated `GEMINI_*` settings (`GEMINI_BASE_URL`, `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_ENABLED`) into live Cloud PostgreSQL `public.delivery_backend_config`, removed all temporary probe scripts from `scratch/`, and upgraded `android-real-device-scrcpy` (`mirror-and-deploy-android.ps1` + Desktop `scrcpy.lnk`) to OpenGL mipmaps + hardware HEVC `24 Mbps` / `60fps` (`--render-driver=opengl --video-codec=h265 -m 1920 -b 24M --max-fps=60 -w`).
- Checks run:
  - Static & Automated Tests: `flutter analyze --no-pub` (`0` issues), `npm test` (`121/121` passed) + `node --test delivery-integrations.test.mjs integration-config.test.mjs` (`23/23` passed), and `flutter test --no-pub test/ghst_ai_chat_test.dart test/backend_integration_settings_test.dart test/unified_user_interface_test.dart` (`34/34` passed, verifying model identifier is never rendered in bubble or full-screen AI chat).
  - Live AI & Deployments: verified live `testIntegration('gemini')` (`ok: true`, `verified: true`, `1029ms`) and live multi-turn `generateAiReply` (`200`, Vietnamese reply in `3038ms`) against `gate.joingonka.ai`; deployed portable 46-file Web Admin + backend commit `de6df7a` (`serviceWorkerVersion: 1408623396`, `0` secret leaks) to `origin/backend-admin` and verified live on `https://ghst-backend-admin.onrender.com`; rebuilt & launched Windows Desktop Release (`gps_delivery_app.exe`, `PID: 19212`, `SessionId: 1`, `Responding: True`); rebuilt & installed `android-arm64` Release APK (`27.5 MB`) onto physical `Xiaomi 2602BRT18C` (`PZ8T6HQWCIFUUKXK`, `scrcpy` `PID: 11540`, `SessionId: 1`, `Responding: True`, `localListeningPorts: 0`).
- Remaining limits & next step: Configure remaining optional third-party credentials (`PAYOS_*`, `GHN_*`, `FCM`) in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Remove Unnecessary Parenthetical Notations `(...)` Across App UI, Admin Portal & Promo RPCs - 2026-11-03

- Removed unnecessary parenthetical notations (`(POD)`, `(EV)`, `(ISO-8601)`, `(COD)`, `(payOS)`, `(CL-...)`, `(kg)`, `(cm)`, `(đ)`, `(đồng)`, `(phút)`, `(30 ngày)`, `(P1–P6)`, `(DATABASE_URL)`, `(PEM)`, `(R / SR / SSR)`, count badges `(n)`, etc.) across user-visible UI labels, switches, form inputs, chips, dialogs, Admin readiness/integration panels, and server promo RPC texts, replacing inline unit parentheses with Material `InputDecoration.suffixText` (`kg`, `cm`, `đ`, `phút`, `giờ`, `%`, `km`) and clean `·` / `•` / `:` separators:
  - **Flutter Canonical UI (`23` files)**: `gps_delivery_app/lib/main.dart`, `cloud_order_form.dart` (`Hẹn giờ lấy hàng`, `Ưu tiên tài xế xe điện`, `Yêu cầu ảnh bằng chứng giao hàng`, `Giao khứ hồi · Phụ thu 60% cước`, `Đóng góp Quỹ Xanh · 1.000 đ`, `Tùy chọn nâng cao: Kích thước, Bảo hiểm & Điểm dừng`, `suffixText` units), `cloud_orders_screen.dart`, `cloud_order_details_screen.dart`, `cloud_order_import_screen.dart`, `cloud_pickup_screen.dart`, `cloud_order_labels.dart` (`Ca sáng · 09:00 - 11:00`, etc.), `cloud_logistics_panels.dart`, `cloud_pricing_dialog.dart`, `cloud_commerce_dialog.dart`, `marketplace_view.dart`, `market_order_services_screen.dart`, `public_order_tracking_screen.dart` (`Mã vận đơn hoặc mã chia sẻ`), `cloud_promo_events_screen.dart`, `marketplace_editor.dart`, `market_catalog_fields.dart`, `market_product_details.dart`, `market_commercial_sheets.dart`, `admin_portal_screen.dart`, `admin_accounts_panel.dart`, `backend_integration_settings.dart`, `system_state_screens.dart`, and `in_app_google_oauth_dialog.dart`.
  - **PostgreSQL Promo RPC & Backend Gateway (`4` files)**: `gps_delivery_app/database/migrations/20261110_cloud_promo_events.sql` (`Giao hàng xanh Xe điện`, `Giảm 50% · 35K`, `Đơn từ ... · 7 ngày`, etc.), `gps_delivery_app/backend/otp-relay/deployment-readiness.mjs` (`Thương mại điện tử toàn diện P1–P6`), `market-media.mjs`, and `integration-config.mjs`.
  - **Test & Browser Suites (`14` files)**: updated matching UI label assertions in `admin_accounts_panel_test.dart`, `backend_integration_settings_test.dart`, `cloud_commerce_test.dart`, `cloud_commercial_suite_test.dart`, `cloud_logistics_test.dart`, `cloud_orders_test.dart`, `cloud_promo_events_test.dart`, `ghst_home_test.dart`, `marketplace_test.dart`, `market_configuration_test.dart`, `tool/check-admin-browser.cjs`, `tool/check-cloud-browser.cjs`, `tool/check-marketplace-browser.cjs`, and `tool/check-full-ui-acceptance.cjs`.
- Checks run:
  - Static & Automated Tests: `flutter analyze --no-pub` (`0` issues), `npm test` (`121/121` passed), `npm run test:postgres` (`28/28` passed), `flutter test --no-pub` across `16` suites (`130` + `21` + `1` = `152/152` passed), headless Edge `tool/check-admin-browser.cjs` on `build/web` (`1440px` & `360px` -> `errors: 0`, `0` secret leaks across `46` files, `:8080` closed immediately -> `0` local listening ports), and live headless Edge check on `https://ghst-backend-admin.onrender.com/#/admin` (`1440px` & `360px` -> `status: 200`, `overflow: 0`, `errors: 0`).
  - Live Database & Deployments: applied updated `20261110_cloud_promo_events.sql` via `npm run migrate:cloud` (`ready: true`, `workflowVersion: 16`); pushed portable zero-secret Web Admin + backend commit `4dac44b` to `origin/backend-admin` and verified live (`https://ghst-backend-admin.onrender.com/health` `200`, `flutter_bootstrap.js` `serviceWorkerVersion: 2791573160`); rebuilt & launched Windows Desktop Release (`gps_delivery_app.exe`, `PID: 23100`, `SessionId: 1`, `Responding: True`); rebuilt & installed `android-arm64` Release APK (`27.5 MB`) onto physical `Xiaomi 2602BRT18C` (`PZ8T6HQWCIFUUKXK`, `ResumedActivity: .MainActivity`, `scrcpy` `PID: 22156`, `SessionId: 1`, `Responding: True`). Skipped local ports and `graphify` per user workflow settings.
- Remaining limits & next step: Unlock the physical Xiaomi phone screen if asleep to inspect the live `scrcpy` window; configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Remove `"Cloud"` Implementation Labels Across User-Visible UI, Promo RPCs & Admin Portal - 2026-11-03

- Removed `"Cloud"` / `"cloud"` / `"CLOUD"` and backend storage implementation jargon from user-visible text across consumer, driver, merchant, promo events, public tracking, and operator admin interfaces while preserving internal Dart/SQL/API identifiers (`CloudAccountSession`, `delivery_cloud_*`, `/delivery/cloud/*`, `cloud_postgres`) and real third-party brand names (`Cloudflare Turnstile`):
  - **Flutter UI & State (`23` files)**: `gps_delivery_app/lib/presentation/screens/admin_portal_screen.dart` (`GHST ADMIN`, `Bảng giá cước`, `Nhật ký điều hành`, `Chỉ số vận hành thời gian thực`, `Đơn vận chuyển`, `Sự kiện Vòng xoay & Hộp mù`), `cloud_promo_events_screen.dart` (`VÒNG XOAY MAY MẮN`, `Ví Xu`, `HỘP MÙ BÍ ẨN`, `Kho Voucher khả dụng`), `cloud_orders_screen.dart`, `marketplace_screen.dart`, `marketplace_view.dart` (`Cổng Quản trị`), `public_order_tracking_screen.dart` (`NHẬT KÝ HÀNH TRÌNH XÁC THỰC`), `legacy_admin_portal_screen.dart` (`Mở Cổng Quản trị`), `ghst_user_shell.dart` (`Quản trị`, `GHST DRIVER • ĐỐI TÁC TÀI XẾ`), `ghst_ai_chat_screen.dart`, `admin_subsystem_views.dart`, `driver_subsystem_views.dart`, `admin_accounts_panel.dart` (`Trung tâm Quản trị Danh tính & Phân quyền`), `backend_integration_settings.dart`, `backend_readiness_dialog.dart` (`Cập nhật cấu trúc dữ liệu`), `cloud_pricing_dialog.dart`, `delivery_integration_status.dart`, `live_order_connection.dart`, `market_commercial_sheets.dart`, `cloud_orders_service.dart`, `delivery_api_client.dart`, `live_delivery_service.dart`, `app_state_live_delivery_ops.dart`, and `app_state_auth_and_gps_ops.dart`.
  - **PostgreSQL Promo RPC & Backend Gateway (`4` files)**: cleaned mission titles/subtitles, wheel/blind-box reward titles & summaries, and `PT401`/`PT403`/`PT409` messages in `gps_delivery_app/database/migrations/20261110_cloud_promo_events.sql`, plus user-visible check/provider/error strings in `gps_delivery_app/backend/otp-relay/ai-assistant.mjs`, `deployment-readiness.mjs`, and `integration-config.mjs` (`Supabase Auth & Dữ liệu`).
  - **Test & Browser Suites (`14` files)**: updated matching label assertions in `admin_accounts_panel_test.dart`, `backend_integration_settings_test.dart`, `backend_readiness_test.dart`, `clean_start_test.dart`, `cloud_commercial_suite_test.dart`, `cloud_orders_test.dart`, `cloud_private_views_test.dart`, `cloud_promo_events_test.dart`, `unified_user_interface_test.dart`, `widget_test.dart`, `tool/check-admin-browser.cjs`, `tool/check-marketplace-browser.cjs`, `tool/check-cloud-browser.cjs`, and `tool/check-full-ui-acceptance.cjs`.
- Checks run:
  - Static & Unit/DB: `flutter analyze --no-pub` (`0` issues), `npm test` (`121/121` passed), `npm run test:postgres` (`28/28` passed), `flutter test --no-pub` across `11` suites (`108/108` + `18/18` = `126/126` passed), and headless Edge `tool/check-admin-browser.cjs` at `1440px` & `360px` (`errors: 0`, transient `:8080` closed immediately -> `0` local listening ports).
  - Live Database & Deployments: applied updated `20261110_cloud_promo_events.sql` via `npm run migrate:cloud` (`ready: true`, `workflowVersion: 16`); pushed portable zero-secret Web Admin + backend commit `9ee97ed` to `origin/backend-admin` and verified live on `https://ghst-backend-admin.onrender.com` (`/health` `200`, `flutter_bootstrap.js` `serviceWorkerVersion: 2711832899`); rebuilt & launched Windows Desktop Release (`gps_delivery_app.exe`, `PID: 13740`, `SessionId: 1`, `Responding: True`); rebuilt & installed `android-arm64` Release APK (`27.5 MB`) onto physical `Xiaomi 2602BRT18C` (`PZ8T6HQWCIFUUKXK`, `ResumedActivity: .MainActivity`, `scrcpy` `PID: 22156`, `SessionId: 1`, `Responding: True`). Skipped local ports and `graphify` per user workflow settings.
- Remaining limits & next step: Unlock the physical Xiaomi phone screen if asleep to inspect the live `scrcpy` window; configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Cloud Session Background Persistence, Server-Authoritative Promo Events Suite (`20261110_cloud_promo_events`, workflow 16) & `nghienai.click` Studio Admin Redesign - 2026-11-03

- Completed three coordinated production upgrades across Cloud PostgreSQL, Node Gateway, Web Admin (`origin/backend-admin`), Windows Desktop, and physical Android (`scrcpy`):
  1. **Cross-Platform Cloud Connection Persistence Across Background / Tab Switch**:
     - Diagnosed why switching tabs or backgrounding disconnected Cloud sessions across Web, Android, and Windows Desktop: `MarketplaceScreen._onLifecycle` was calling `session.refresh()` on mere desktop/tab focus loss (`AppLifecycleState.inactive` / `hidden`), `CloudAccountSession.refresh()` treated transient socket/TLS/gateway errors (`ClientException`, `TimeoutException`, HTTP `502`–`504`/`429`) right after OS resume as fatal `sessionError`s (tearing down `CloudSessionBoundary` leases), `CloudOrdersRepository._run` discarded already-loaded order lists on transient `PublicApiException`s, stale half-open pooled sockets in `DeliveryApiClient` failed the first post-resume request, and `%LOCALAPPDATA%\GHST\auth-providers.json` on Windows Desktop still pointed `deliveryApiBaseUrl` to the stopped local `:8787` port.
     - Fixed in `gps_delivery_app/lib/core/integrations/delivery_api_client.dart` (`resetConnectionPool()` + single `refreshSession()` retry on `401` + transient retry on idempotent `GET`s), `cloud_account_session.dart` (`hasTransientRefreshWarning` preserving verified state for the same `identityScope` on transient network errors while immediately revoking on `401`/`403`, `503` missing schema, `blocked == true`, role revocation, `FormatException`, or `signedOut`/account switch), `cloud_orders_repository.dart`, `marketplace_screen.dart` (refresh only after real `paused` -> `resumed`), `cloud_orders_screen.dart`, `admin_portal_screen.dart` (`WidgetsBindingObserver` resume refresh), `env_config.dart`, and `main.dart` (preventing loopback `auth-providers.json` URLs from hijacking Cloud-built release binaries, plus updating `%LOCALAPPDATA%\GHST\auth-providers.json` to `https://ghst-backend-admin.onrender.com/delivery/`).
  2. **Server-Authoritative Cloud Promo Events Suite (`20261110_cloud_promo_events.sql`, `workflowVersion: 16`) & Customer Home Hub**:
     - Replaced Minh Nhan's `/legacy` client-side `Random()` + SQLite promo prototype with 100% server-authoritative PostgreSQL RPC `public.delivery_cloud_promo_events(p_action, p_payload)` (`gps_delivery_app/database/migrations/20261110_cloud_promo_events.sql`): `delivery_promo_event_settings`, `delivery_promo_event_wallets`, `delivery_promo_event_claims`, and `delivery_market_vouchers.owner_user_id` (enforced in `delivery_marketplace` quote/checkout), using cryptographic `gen_random_bytes(4)` inside `FOR UPDATE` transactions for Daily 7-Day Check-in (`daily_checkin`), 8-Slice Lucky Spin Wheel (`spin_wheel`), 6-Slot R/SR/SSR Mystery Blind Box (`open_blind_box`, `reset_blind_boxes`), Real Delivered-Order Missions (`claim_mission` verified against `delivery_cloud_orders` & `delivery_market_shop_orders`), Coin Exchange (`exchange_coins` debiting `delivery_market_coin_wallets` + `delivery_market_coin_ledger`), and Operator governance (`admin_settings_save`). Zero demo shops/vouchers/balances seeded into live DB.
     - Wired fixed-action gateway route `POST /delivery/cloud/promo-events/:action` (`gps_delivery_app/backend/otp-relay/cloud-orders.mjs`, `migrate-cloud.mjs`, `deployment-readiness.mjs`, `CLOUD_ORDERS.md`) and built Customer UI in `gps_delivery_app/lib/presentation/screens/cloud_promo_events_screen.dart`, quick-launch hub on `GhstHomeScreen` (`ghst_home_screen.dart`, `marketplace_screen.dart`), Marketplace header (`marketplace_view.dart`), `PERSONAL` badge in `market_commercial_sheets.dart`, and Operator event toggle/KPI strip in `AdminPortalScreen`.
  3. **Backend Admin Redesign in `https://nghienai.click/` Neo-Brutalist Studio Theme**:
     - Created `gps_delivery_app/lib/core/theme/admin_studio_theme.dart` (`AdminStudioColors` `#F5F1E8` paper, `#15131E` ink, `#171421` dark studio grid + `#5B33E6` radial glow, `#CBFF3E` acid, `#FF5E83` pink, `#FFD75E` gold, sharp `BorderRadius.zero`, hard `Offset(4, 4)`/`Offset(3, 3)` shadows, chamfered `AdminStudioMark` `G` + `OPS`) and redesigned `admin_portal_screen.dart`, `admin_accounts_panel.dart`, `backend_integration_settings.dart`, and `backend_readiness_dialog.dart` while keeping signed-out `/admin` strictly separate from consumer login and preserving 100% of labels, keys, tooltips, and masked secret inputs.
- Checks run:
  - Backend: `npm test` (`121/121` passed) + `npm run test:postgres` (`28/28` native PostgreSQL 17 suites passed, incl. `promo-events.test.mjs`) + `npm run migrate:cloud` on live Supabase PostgreSQL (`ready: true`, `migration: 20261110_cloud_promo_events`, `workflowVersion: 16`).
  - Flutter & Headless Edge: `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub` across all 10 affected suites (`cloud_promo_events_test.dart`, `ghst_home_test.dart`, `admin_accounts_panel_test.dart`, `backend_integration_settings_test.dart`, `backend_readiness_test.dart`, `auth_configuration_test.dart`, `cloud_account_session_test.dart`, `cloud_orders_repository_test.dart`, `cloud_orders_test.dart`, `unified_user_interface_test.dart` -> `100%` passed), and `node tool/check-admin-browser.cjs` on portable `/delivery/` Web build (`1440px` & `360px` -> `errors: 0`, `overflow: false`, `0` secret leaks across `46` files, temporary `:8080` closed immediately -> `localListeningPorts: 0`).
  - Live Deployments: pushed portable zero-secret Web Admin + backend commit `b320684` to `origin/backend-admin` and verified live on Render (`https://ghst-backend-admin.onrender.com/health` `200`, `/admin` `200`, `flutter_bootstrap.js` exact match, `/delivery/cloud/promo-events/status` `401`); built & launched Cloud-direct Windows Desktop Release (`gps_delivery_app.exe`, `PID: 8808`, `SessionId: 1`, `Responding: True`); built & installed Cloud-direct `android-arm64` Release APK (`27.5 MB`) onto physical `Xiaomi 2602BRT18C` (`PZ8T6HQWCIFUUKXK`, `ResumedActivity: .MainActivity`, `scrcpy` `PID: 22156`, `SessionId: 1`, `Responding: True`). Skipped local ports and `graphify` per user workflow settings.
- Remaining limits & next step: Live Cloud DB intentionally starts with `0` shops/products/public vouchers until created by Merchant/Operator accounts; configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Map Viewport Enlargement, Retina `@2x` Tile Sharpness, Clean GPS UI & Locate Zoom Preservation - 2026-11-03

- Resolved four map UX/rendering issues reported from real-device testing:
  1. **Removed redundant "GPS Thật / GPS của bạn" text clutter (`gps_delivery_app/lib/presentation/widgets/system_state_screens.dart`)**: removed the bottom-left `'GPS Thật (lat, lng ±m)'` / `'Định vị GPS thật'` button inside `Map3dPerspectiveWidget` (keeping only the compact layer switcher `Bản đồ | Giao thông | Vệ tinh | Địa hình`), removed the floating `'GPS của bạn ±m'` callout badge above the live blue dot + Web Mercator accuracy ring, removed the repetitive `'Đã định vị GPS thật: ...'` SnackBar on every locate tap, and simplified locate tooltips to `'Vị trí hiện tại của tôi'`.
  2. **Enlarged map viewports & touch controls (`ghst_home_screen.dart`, `cloud_order_form.dart`, `system_state_screens.dart`)**: increased customer Home map height (`330` -> `440`), dynamic `Bản đồ hành trình` (`trackingOnly`) height (`(viewportHeight - 220).clamp(480.0, 760.0)`), `CloudOrderForm` map height (`270` -> `390`), and right-side circular map buttons (`29×29` -> `34×34`).
  3. **Retina `@2x` (`512×512`) tiles, pixel-grid snapping & responsive gestures (`env_config.dart`, `system_state_screens.dart`)**: appended `&scale=2` to `EnvConfig.buildGoogleMapTileUrl`, upgraded tile `Image.network` to `FilterQuality.medium` + `gaplessPlayback: true` + physical-pixel snapping (`snapToPixelGrid`) in 2D mode, retained `_previousZoomLevel` as a scaled backdrop while new zoom tiles stream in, extended zoom ceiling to `20`, anchored scroll/double-tap/pinch zoom around the focal point with continuous `_pinchVisualScale` during active pinch (`1.0` at rest), and scoped `GestureDetector` strictly to the map canvas so floating `+`/`−`/locate/layer buttons respond without `300ms` double-tap latency.
  4. **Preserved user zoom on Locate (`system_state_screens.dart`)**: tapping `btn_map_my_real_gps` (inline or fullscreen modal) centers on the live GPS point while preserving `_zoomLevel` whenever `_userAdjustedZoom` is true or `_zoomLevel >= 16` (only lifting `< 16` -> `16` when the user has not adjusted zoom).
- Checks run: `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub test/ghst_home_test.dart test/cloud_orders_test.dart test/cloud_address_book_test.dart test/unified_user_interface_test.dart` (`56/56` passed), `flutter test --no-pub --plain-name "TC-04" test/widget_test.dart` (`1/1` passed), `flutter test --no-pub --plain-name "TC-22" test/widget_test.dart` (`1/1` passed, verifying `scale=2`, absence of `'GPS Thật'`/`'GPS của bạn'`, and zoom preservation at both `z=18` and `z=14`), built & installed Cloud-direct `android-arm64` Release APK (`27.3 MB`) onto physical `Xiaomi 2602BRT18C` (`PZ8T6HQWCIFUUKXK`, `ResumedActivity: .MainActivity`, `scrcpy` `SessionId: 1`, `Responding: True`), and built & launched Cloud-direct Windows Desktop Release (`gps_delivery_app.exe`, `SessionId: 1`, `Responding: True`). Skipped local ports and `graphify` per user workflow settings.
- Remaining limits & next step: Inspect map sharpness and zoom/locate feel directly on the Xiaomi phone (`scrcpy` window) and Windows Desktop app; decide whether to migrate Minh Nhan's Lucky Spin Wheel / Promo Hub onto server-verified Cloud PostgreSQL RPCs next.

## Cloud-Only Client Workflow, Real Android `scrcpy` Skill & Minh Nhan Feature Audit - 2026-11-03

- Stopped local port daemons (`:8787` backend, `:8080` web preview) and Android Emulator (`emulator-5554`), switching workflow per user decision (`PROJECT_CONTEXT.md`) to:
  1. Test client apps directly against live Cloud (`https://ghst-backend-admin.onrender.com/delivery/`) without local servers, and skip `graphify` updates unless requested.
  2. Build single-ABI `android-arm64` Release APK (`27.3 MB`) and deploy directly to the physical Android phone (`Xiaomi 2602BRT18C`, Android 17, `arm64-v8a`), mirrored live onto Windows Desktop (`SessionId: 1`, `Responding: True`) via `scrcpy` v5.0.1 alongside Windows Desktop (`gps_delivery_app.exe`, `SessionId: 1`).
  3. Created global reusable Antigravity skill `android-real-device-scrcpy` (`C:\Users\PhamTriHien\.gemini\config\skills\android-real-device-scrcpy\SKILL.md` + `scripts/mirror-and-deploy-android.ps1`) automating emulator teardown, physical ABI detection, `SessionId: 1` `scrcpy` mirroring, single-ABI deployment, and binary-safe screenshot verification.
- Audited Minh Nhan's commits (`8fd6719`, `b8da30a`, `1b98207`) vs Cloud App:
  - **Already integrated on real Cloud PostgreSQL**: UC30-UC40 smart logistics (`20261108_cloud_logistics.sql`: bulk pickups, CSV import, recipient trust, delivery instructions, road-distance stop optimizer, 30-day stats), Store/Marketplace catalog + SKU variants + options + shop staff (`MarketplaceView`), and Cloud Vouchers / Flash Sales / Coin Wallet (`20261107_cloud_commercial_suite.sql` + `market_commercial_sheets.dart`, currently `0` rows in live Cloud DB because demo seeding is prohibited).
  - **Not yet migrated from `/legacy` SQLite to Cloud**: Lucky Spin Wheel (`Vòng xoay may mắn`) & Mystery Blind Box (`Hộp mù bí ẩn`) in `customer_promo_events_views.dart` / `promo_event_gamification_engine.dart` (currently client-side `Random()` + SQLite `AppStateStore`), plus quick Promo/Voucher/Flash Sale hub entry cards on `GhstHomeScreen`.
- Remaining limits & next step: Await user confirmation on whether to port Lucky Spin Wheel / Promo Hub onto real server-verified Cloud PostgreSQL RPCs (zero fake/client-minted rewards) and/or expose quick Voucher/Flash Sale/Coin cards directly on `GhstHomeScreen`.

## Role-Synchronized Cloud Workspaces Across Consumer, Driver, Merchant & Operator Logins - 2026-11-03

- Diagnosed why accounts with approved Cloud roles (`driver`, `merchant` / `shop_staff`, `isOperator`) logging into the app (`/`) all landed on the same `GHST EXPRESS` customer shell (`GhstHomeScreen`):
  - `MarketplaceScreen` (`gps_delivery_app/lib/presentation/screens/marketplace_screen.dart`) hardcoded `_section = widget.initialShipping ? GhstUserSection.orders : GhstUserSection.home` after `CloudAccountSession.verified` without inspecting `isOperator`, `account['role']`, `hasRole('driver')`, or `hasMerchantAccess`, and `AdminPortalScreen` was only reachable via `/#/admin` on Web.
- Implemented server-verified role-synchronized Cloud workspaces (`100%` real `CloudAccountSession` + PostgreSQL RLS/RPCs, `0` mock/SQLite fallback, keeping signed-out `/admin` login strictly separate from signed-out `CloudAuthScreen`):
  - **Operator (`isOperator`)**: automatically opens `AdminPortalScreen` (`GHST CLOUD ADMIN`) directly inside the app on `/` (`gps_delivery_app/lib/presentation/screens/admin_portal_screen.dart`, `marketplace_screen.dart`, `marketplace_view.dart`), with `'Giao diện Khách hàng'` (`admin-switch-user-mode`) to enter consumer/partner mode, `'Vai trò Quản trị Cloud'` (`ghst-role-operator`) to return, and a `'Quay lại Quản trị Cloud'` escape button if an operator's consumer profile is incomplete or blocked.
  - **Driver (`hasRole('driver')`)**: opens the dedicated `GHST DRIVER` workspace (`#059669` emerald branding in `gps_delivery_app/lib/presentation/customer/ghst_user_shell.dart`) defaulting to `Sàn chuyến chờ nhận` (`CloudOrdersScreen(embedded: true, initialQueue: true)` in `gps_delivery_app/lib/presentation/screens/cloud_orders_screen.dart`), with Driver desktop sidebar & 5-tab mobile bar (`Chờ nhận`, `Chuyến giao`, `Thu gom`, `Hiệu suất`, `Hồ sơ`).
  - **Merchant / Shop Staff (`hasMerchantAccess`)**: opens the dedicated `GHST MERCHANT` workspace (`#D97706` amber branding) defaulting to `Cửa hàng của tôi` (`workspace`), with Merchant B2B desktop sidebar & 5-tab mobile bar (`Cửa hàng`, `Đơn shop`, `Gửi hàng` 3-tab `Đơn lẻ | Nhập CSV | Đã gửi` for owners, `Thu gom`, `Hồ sơ`).
  - **Customer & Multi-Role Switching**: pure customer accounts open `GHST EXPRESS` (`GhstHomeScreen`, or consumer shipping on `/cloud`); multi-role accounts render a `Wrap`-based role-switcher strip (`VAI TRÒ:` / `CHẾ ĐỘ VAI TRÒ`) with zero horizontal overflow at `360px` & `1440px`, automatic live role-grant upgrade when unselected, and immediate workspace revocation without leaking partner/admin views.
- Checks run: `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub test/unified_user_interface_test.dart` (`23/23` passed) + full `flutter test --no-pub` (`302` passed, `1` external skip), `node tool/check-marketplace-browser.cjs` (`10/10` passed across `customer`, `merchant`, `shop_staff`, `partner`, `operator` at `360px` & `1440px`, `errors: 0`, `overflow: false`), `node tool/check-admin-browser.cjs` (`2/2` passed at `1440px` & `360px`, `errors: 0`), rebuilt & verified live Cloud Android `x86_64` Release APK on `Pixel_10_Pro` (`emulator-5554` automatically landed signed-in Driver session on `GHST DRIVER • TÀI XẾ CLOUD` -> `Sàn chuyến chờ nhận`), rebuilt & launched Windows Desktop Release (`gps_delivery_app.exe`, `SessionId: 1`, `Responding: True`), and ran `graphify update .`.
- Remaining limits & next step: Configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` (or directly in Operator app login) when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Consumer Google Login Button Cold-Start Resilience & Register-Tab Visibility - 2026-11-03

- Diagnosed why `'Tiếp tục với Google'` intermittently disappeared on `CloudAuthScreen` (`Pixel_10_Pro` cold-start screenshot right after APK install vs Hosted Supabase `GET /auth/v1/settings` returning `external.google = true`):
  1. **One-shot unretried 5s probe**: `CloudOrdersService.googleSignInAvailable()` (`gps_delivery_app/lib/core/integrations/cloud_orders_service.dart`) performed a single 5-second `http.get` to `${_cloud.cloudUrl}/auth/v1/settings` and returned `false` on any cold-start network/DNS/TLS timeout, while `CloudAuthScreen.initState()` (`gps_delivery_app/lib/presentation/screens/cloud_auth_screen.dart`) only probed once at mount and never retried.
  2. **Hidden on Register tab**: `CloudAuthScreen` only rendered `'Tiếp tục với Google'` under `_AuthMode.login` (`Đăng nhập`), hiding it whenever the user switched to `_AuthMode.register` (`Đăng ký tài khoản`).
- Implemented production fix in `cloud_orders_service.dart`, `cloud_auth_screen.dart`, and `test/unified_user_interface_test.dart` (keeping `/#/admin` `AdminPortalScreen` completely separate without Google login):
  - Added `cachedGoogleSignInAvailable` + `probeGoogleSignIn()` (`2` attempts, `8s` timeout + `800ms` backoff, caching authoritative HTTP `200` per Supabase project scope while marking transient timeouts/`5xx` as `authoritative: false`).
  - Added `WidgetsBindingObserver` + `_checkGoogleAvailability()` on `CloudAuthScreen` with automatic 3-second background retry when non-authoritative, re-check on `AppLifecycleState.resumed` and tab switches, and `'Tiếp tục với Google'` rendered on both `Đăng nhập` and `Đăng ký tài khoản`.
- Checks run: `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub test/unified_user_interface_test.dart test/auth_configuration_test.dart test/clean_start_test.dart` (`33/33` passed, incl. transient cold-start recovery + Login/Register visibility test), rebuilt & cold-started `x86_64` Release APK on `Pixel_10_Pro` (`emulator-5554`, verified via cold-start screenshot with `'Tiếp tục với Google'` visibly rendered), rebuilt & launched Windows Desktop (`gps_delivery_app.exe`, `SessionId: 1`, `Responding: True`), rebuilt local Web preview (`:8080`), and ran `graphify update .` (`5563` nodes, `8953` edges, `213` communities).
- Remaining limits & next step: Configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Cloud Account Governance Workspace Redesign (`20261109_admin_account_management`, workflow 15) - 2026-11-03

- Redesigned Cloud Account Management in `/#/admin` (`AdminPortalScreen`) from the old 3-line toggle inside `CloudOrdersScreen` into a dedicated **Tài khoản** module (`AdminAccountsPanel`, `gps_delivery_app/lib/presentation/widgets/admin_accounts_panel.dart`) backed 100% by real Cloud PostgreSQL data (`0` mock/static numbers):
  - **SQL & RLS/RPC (`gps_delivery_app/database/migrations/20261109_admin_account_management.sql`)**: added private helpers `delivery_cloud_auth_providers` & `delivery_cloud_admin_account_row` (unified `auth.users` + `auth.identities` + `delivery_cloud_accounts` + `delivery_cloud_memberships` + `delivery_api_profiles` + coins/shops/orders/trips counts), extended `delivery_cloud_membership` with `p_decision = 'grant'` (`membership_grant` audit, `version = 0` when unrequested), and added Operator-only `delivery_cloud_admin_accounts` (`list` with server `summary` KPIs, `detail` with owned shops + last 25 audit rows, `update_profile` upserting incomplete Auth users or fixing names/phones, `set_blocked` with `PT409` self-lock guard, and `set_operator` with mandatory audit reason and `PT409` self-demote guard).
  - **Backend & Readiness (`gps_delivery_app/backend/otp-relay/cloud-orders.mjs`, `migrate-cloud.mjs`, `deployment-readiness.mjs`, `CLOUD_ORDERS.md`)**: added fixed-action `POST /delivery/cloud/admin-accounts/:action`, `'grant'` decision on `POST /delivery/cloud/accounts/:id/memberships/:role`, `admin_accounts_schema` readiness check, and `workflowVersion: 15`.
  - **Flutter Admin UI (`admin_portal_screen.dart`, `admin_accounts_panel.dart`, `cloud_orders_screen.dart`, `cloud_orders_service.dart`, `P0_SYNC_MATRIX.md`)**: 6 dedicated Admin modules (`Tổng quan`, `Tài khoản`, `Vận đơn`, `Cửa hàng & Đánh giá`, `Khuyến mãi & Đối soát`, `Tích hợp`), responsive 6-card KPI summary, search & status/role filter chips (`all`, `pending`, `operator`, `driver`, `merchant`, `incomplete`, `blocked`), Auth provider badges (`Google OAuth` / `Email / Mật khẩu`), profile editor, direct partner grant/approval/rejection/revocation, Operator grant/revoke, self-lockout protection, and per-account shop/audit dialog (`showAccountsToggle = true` preserved by default on standalone `CloudOrdersScreen`).
- Checks run: `npm test` (`120/120` passed), `npm run test:postgres` (`28/28` native PostgreSQL 17 checks passed), `npm run migrate:cloud` on live Supabase PostgreSQL (`ready: true`, `migration: 20261109_admin_account_management`, `workflowVersion: 15`), `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub` (`300` passed, `1` skip, `0` failed, incl. new `test/admin_accounts_panel_test.dart` at `360px` & `1440px`), `node tool/check-admin-browser.cjs` (`2/2` at `1440px` & `360px`, `errors: 0`, `overflow: false`), portable zero-secret Web Admin deployed to `origin/backend-admin` (`949639a`) and verified `live` on Render (`dep-dbkdj5ui0phs73as7g3g` -> `/health` `200`, `/admin` `200`, `/delivery/cloud/admin-accounts/list` `401`), restarted local `:8787` + `:8080`, rebuilt & relaunched Windows Desktop (`gps_delivery_app.exe`, `SessionId: 1`) and Android Emulator (`Pixel_10_Pro` `emulator-5554`), and ran `graphify update .` (`5553` nodes, `8938` edges, `210` communities).
- Remaining limits & next step: Configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## One-Way Masked Secret Previews in Backend Admin (`9883eeb`) - 2026-11-03

- Added safe one-way masked secret previews (`maskedValue`) so Cloud Operators clearly see which secret API keys are saved in `/#/admin` -> `Tích hợp` without ever returning raw secret values over the network:
  - `gps_delivery_app/backend/otp-relay/integration-config.mjs` (`maskSecretValue`, `integrationStatus`) & `INTEGRATIONS.md`: omits `value` for all `secret: true` fields while returning `maskedValue` (`••••••••••••` + last 4 chars for secrets `>= 12` chars, `••••••••••` + last 2 chars for `8..11` chars, `••••••••` with 0 chars exposed for `< 8` chars, and `postgresql://••••••••@host:port/db` for `DATABASE_URL`).
  - `gps_delivery_app/lib/presentation/widgets/backend_integration_settings.dart`: displays `maskedValue` directly inside `InputDecoration.hintText` with `FloatingLabelBehavior.always` while keeping `controller.text` empty (preserving `obscureText: true` and leave-blank-to-preserve semantics).
  - Updated `gps_delivery_app/backend/otp-relay/delivery-integrations.test.mjs`, `gps_delivery_app/test/backend_integration_settings_test.dart`, and `gps_delivery_app/tool/check-admin-browser.cjs` (including `/delivery/cloud/logistics/stats` fixture for `_AdminAnalyticsPanel`).
- Checks run: `npm test` (`119/119` passed), `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub test/backend_integration_settings_test.dart` (`5/5` passed), `node tool/check-admin-browser.cjs` (`2/2` at `1440px` & `360px`, `errors: 0`), portable Web Admin deployed to `origin/backend-admin` (`9883eeb`) and verified `live` on Render (`dep-dbkcedlg1s2s738v8pb0`, `/health` `200`, `/admin` `200`), restarted local `:8787` + `:8080`, rebuilt & relaunched Windows Desktop (`gps_delivery_app.exe`, `SessionId: 1`) and Android Emulator (`Pixel_10_Pro` `emulator-5554`), and ran `graphify update .` (`5452` nodes, `8779` edges).
- Remaining limits & next step: Configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Merge Nhan `1b98207` & Cloud Logistics Suite (`20261108_cloud_logistics`, workflow 14) - 2026-11-02

- Fast-forwarded `main` to Nhan's latest `origin/main` commit `1b98207` (UC30-UC40 legacy merchant workflows, 2 report `.docx`); no file overlapped the uncommitted working tree.
- Re-implemented the features the cloud app lacked, on real cloud data:
  - `gps_delivery_app/database/migrations/20261108_cloud_logistics.sql`: `delivery_cloud_pickups`, `delivery_cloud_recipient_flags` (RLS, no anon/authenticated grants), `delivery_cloud_orders.delivery_instruction`, RPC `delivery_cloud_logistics` (`pickup_list/create/assign`, `recipient_trust/flag`, `instruction_set`, `stats`, `service_eta`).
  - Backend: `cloud-orders.mjs` route `POST /delivery/cloud/logistics/:action` (fixed action set), `delivery-gateway.mjs` `GET /matrix?full=1` (TrackAsia/Google/OSRM all-pairs), `migrate-cloud.mjs` and `deployment-readiness.mjs` (`logistics_schema`, `COMMERCE_MIGRATION=20261108_cloud_logistics`).
  - Flutter: `cloud_pickup_screen.dart` (merchant/operator/driver), `cloud_order_import_screen.dart` + `core/utils/cloud_order_csv.dart` (replaces seeded Shopee/TikTok/Sapo sync), `widgets/cloud_logistics_panels.dart` (recipient trust, `Chỉ dẫn giao` menu, 30-day stats), `core/gps/stop_order_optimizer.dart` + `CloudOrderForm` stop ordering on road distances and service ETA; entries in merchant workspace, `CloudOrdersScreen` (driver/operator icons), Admin analytics.
- Removed static data from the merged legacy code: seeded marketplace orders, fixed "AI SLA"/hotspot figures, placeholder `ghst-gps.app` share link, invented route/fee factors, default pickup quantities and fallback warehouse/merchant values; updated `test/smart_logistics_upgrades_test.dart` accordingly.
- Checks run: `npm test` (`119/119`), `npm run test:postgres` (all groups incl. new `L0`-`L5`), `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub` (`296` passed, `1` skip), `npm run migrate:cloud` on the configured Supabase project (`ready: true`, workflow 14), live read-only `DEPLOYMENT_SCHEMA_SQL` (all checks true incl. `logistics_schema`), portable Web Admin clean build (`46` files, `0` secret leaks, exact `/delivery/` relative base URL) pushed to `origin/backend-admin` (`b48ed26`) and verified live on Render (`dep-dbkc5iqvcj2c73fvt0kg`, `status: live` -> `/health` `200`, `/admin` `200`, `/assets/fonts/MaterialIcons-Regular.otf` `200`, `/delivery/cloud/logistics/stats` `401`, `/delivery/matrix?full=1` `401`), restarted local backend `:8787` (`/health` `200`, `/delivery/cloud/logistics/stats` `401`, `/delivery/matrix?full=1` `401`), rebuilt Windows Desktop Release (`build/windows/x64/runner/Release/gps_delivery_app.exe`), Android Release APK (`build/app/outputs/flutter-apk/app-release.apk`, `arm64`+`x64`, `52.8 MB`), and local Web preview (`:8080`), plus `graphify update .`.
- Remaining limits & next step: No authenticated live logistics transaction has been executed against production data yet; legacy SQLite pickups/flags/instructions remain un-reloaded after restart in `/legacy` (pre-existing). Next: configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` when ready and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Backend API Configuration Cloud PostgreSQL Persistence & Multi-Instance Sync (`b9c5425`) - 2026-11-02

- Diagnosed why API keys and settings saved in `/#/admin` -> `Tích hợp` (`BackendIntegrationSettings` -> `POST /delivery/admin/integrations/config`) failed to persist to Cloud PostgreSQL and appeared lost across Render restarts or between Cloud Render and local `:8787`:
  1. **Production Cloud DB write skip**: `updateIntegrationConfig` (`gps_delivery_app/backend/otp-relay/integration-config.mjs`) constructed `const candidate = { ...env, ...patch }` (`candidate !== process.env`) and passed `candidate` into `withConfigDb(candidate, db, ...)` which guarded `if (env !== process.env || !configValue('DATABASE_URL', env)) return null;` when `db === undefined`. As a result, 100% of production saves skipped `public.delivery_backend_config` and `public.delivery_backend_config_audit` (`17` rows remained stuck on `updated_by = 'bootstrap'` with only `1` initial seed audit row), writing only to ephemeral container `.integration-config.json`.
  2. **Multi-instance drift**: `loadIntegrationConfig` only pulled `public.delivery_backend_config` once at boot, so saves on Render (`https://ghst-backend-admin.onrender.com`) and local `:8787` did not sync into running instances without a restart, and keys previously written only to local `.integration-config.json` were treated as unchanged (`changed = []`) when re-saved.
  3. **Admin UX feedback & secret field state**: In `gps_delivery_app/lib/presentation/widgets/backend_integration_settings.dart`, clearing `controller.text = ''` after saving a `secret: true` field caused Material 3 `InputDecoration` to collapse `labelText` over `hintText: 'Đã lưu tại backend'` when unfocused (looking empty), while `_message` rendered only at the top of 20 cards off-screen.
- Implemented production fix across backend, Admin UI, tests, and live Render deployment:
  - `gps_delivery_app/backend/otp-relay/integration-config.mjs`, `delivery-integrations.mjs`, `server.mjs`, `INTEGRATIONS.md`: replaced per-call `pg.Client` with a shared `pg.Pool` (`max: 2`, `keepAlive: true`, `allowExitOnIdle: true`), preserved `allowLiveDb` across `candidate` patches while keeping synthetic unit-test `env` objects isolated, added `syncIntegrationConfig({ env, db, connectPool, maxAgeMs })` (`maxAgeMs: 0` on Admin read/test routes and `maxAgeMs: 5000` middleware on `/delivery`), compared `patch` against both in-memory `env` and live `public.delivery_backend_config` rows, tolerated read-only container cache files once `persistedToCloud === true`, returned `storage: 'cloud_postgres' | 'local_file'`, and refined `assertSafeAiUrl` with a clear Vietnamese message when `?key=...` query params are pasted into `GEMINI_BASE_URL`.
  - `gps_delivery_app/lib/presentation/widgets/backend_integration_settings.dart`: rendered `_statusBanner()` inline right above `Lưu` / `Kiểm tra kết nối` inside the active provider card, set `floatingLabelBehavior: savedSecret ? FloatingLabelBehavior.always : null` + `helperText` (`Khóa bảo mật đã đồng bộ Cloud PostgreSQL — để trống nếu giữ nguyên`) so saved secret fields stay visibly confirmed when unfocused, and surfaced actionable guidance when credentials are saved while `Cho phép backend sử dụng` is still off.
  - Added multi-instance `configPool` PGlite sync + query-param SSRF tests in `gps_delivery_app/backend/otp-relay/delivery-integrations.test.mjs` and Cloud sync / secret-field widget assertions in `gps_delivery_app/test/backend_integration_settings_test.dart`.
  - Synced portable zero-secret Web Admin + backend commit `b9c5425` to `origin/backend-admin` and verified Render deployment `dep-dbkak73m8hqs738mc8dg` reached `status: live` on `https://ghst-backend-admin.onrender.com`.
- Checks run: `npm test` (`118/118` backend tests passed), `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub test/backend_integration_settings_test.dart test/backend_readiness_test.dart` (`12/12` passed), live zero-mock Cloud PostgreSQL `POST /delivery/admin/integrations/config` save + `public.delivery_backend_config` / `public.delivery_backend_config_audit` read-back + cross-instance `syncIntegrationConfig` pull (`liveCloudSaveVerified: true`, `liveCrossInstancePullVerified: true`), `flutter build web` (portable `/delivery/` with `0` secret leaks across `46` files + local `:8080`), `flutter build windows --release --no-pub`, `node tool/check-admin-browser.cjs` (`2/2` at `1440px` & `360px`, `errors: 0`), live headless Microsoft Edge check on `https://ghst-backend-admin.onrender.com/#/admin` (`200 OK`, `overflow: false`, `errors: 0` at `1440px` & `360px`), and `graphify update .` (`5213` nodes, `8396` edges, `196` communities).
- Remaining limits & next step: Bootstrap anchors (`DATABASE_URL`, `DATABASE_CA_CERT`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`) remain host-scoped by security design; configure `GEMINI_*` / `PAYOS_*` / `GHN_*` / `FCM` credentials in `/#/admin` -> `Tích hợp` (remembering to toggle `Cho phép backend sử dụng` on `defaultOff` providers) and run live two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Supabase Auth Custom SMTP, 6-Digit Recovery OTP, Account Chooser & Cloud Driver Grant - 2026-11-02

- Diagnosed broken "Quên mật khẩu" email OTP delivery against live Supabase Management API (`GET /v1/projects/yvnbfurazjbhbopahtmx/config/auth`) and `auth.users`:
  1. Hosted Supabase Auth had Custom SMTP unconfigured (`smtp_host: null`, `rate_limit_email_sent: 2`/hour restricted to Supabase organization members only), while backend Gmail SMTP (`smtp.gmail.com:465`) was only stored in the relay (`MARKETPLACE.md`).
  2. Default `mailer_templates_recovery_content` only rendered `<a href="{{ .ConfirmationURL }}">` pointing to `http://localhost:3000` without `{{ .Token }}`, so no verification code was sent for `CloudAuthScreen`'s `Mã xác nhận email` input.
- Extended `gps_delivery_app/backend/otp-relay/setup-google-cloud.mjs` (+ `setup-google-cloud.test.mjs`, `npm test` `117/117` passed) and applied live via `./setup-google-cloud.ps1 -Apply`:
  - Synced verified backend Gmail SMTP (`smtp.gmail.com:465`, `smtp_sender_name: 'GHST EXPRESS'`, `smtp_max_frequency: 15`, `rate_limit_email_sent: 30`) and 6-digit OTP templates (`mailer_otp_length: 6`, `mailer_otp_exp: 900`, `{{ .Token }}` in recovery and confirmation HTML) plus `com.giaohanggps.gpsdelivery://auth/callback` to Hosted Supabase Auth (`managementVerified: true`, `smtpSynced: true`, `recoveryOtpEnabled: true`), without logging any credentials.
  - Verified live zero-mock recovery email dispatch on Hosted Supabase (`POST /auth/v1/recover` -> `200 OK`, `recovery_sent: true`, `auth.one_time_tokens` `ott_count: 1`, disposable check user immediately deleted).
  - Hardened `gps_delivery_app/lib/presentation/screens/cloud_auth_screen.dart` (`didUpdateWidget` switch to `_AuthMode.password` after `AuthChangeEvent.passwordRecovery` so password validation retries never re-consume a used OTP, `Gửi lại mã xác nhận`, numeric OTP keyboard/autofill, and clear Vietnamese `otp_expired` / `same_password` / `429` error messages; `28/28` tests in `unified_user_interface_test.dart` + `marketplace_test.dart`).
- Fixed browser auto-relogging into a single remembered Google session when signing in or switching Google accounts:
  - Verified live Supabase `/auth/v1/authorize?provider=google` returns `302` to `accounts.google.com` with `prompt=null` by default, and forwards `prompt=select_account` when supplied.
  - Added `googleOAuthQueryParams = {'prompt': 'select_account'}` to both `gps_delivery_app/lib/core/auth/cloud_oauth_io.dart` (`getOAuthSignInUrl` on Android/Windows and `signInWithOAuth` on iOS) and `gps_delivery_app/lib/core/auth/cloud_oauth_web.dart` (`signInWithOAuth` on Web), plus unit test coverage in `gps_delivery_app/test/unified_user_interface_test.dart` (`19/19` passed). Rebuilt Android `x86_64` release APK (installed directly onto `Pixel_10_Pro` `emulator-5554`), Web bundle, and Windows desktop release.
- Granted the requested Google Cloud account approved `driver` partner membership (`state: 'active'`, `version: 2`, `approved_roles: ['driver']`, `role: 'driver'`, `blocked: false`, `schema_version: 3`) directly on hosted Supabase PostgreSQL via canonical RPCs (`public.delivery_cloud_membership('driver', 'request')` followed by verified Cloud Operator `public.delivery_cloud_membership('driver', 'approve', ...)`), preserving immutable audit records in `public.delivery_cloud_admin_audit` (`membership_request` + `membership_approve`) without writing any account PII or credentials to repository files; verified read-back via `public.delivery_cloud_profile()` and driver queue authorization via `public.delivery_cloud_list(true, null, null)` (`driverQueueAuthorized: true`).
- Diagnosed Android Google login failure on `Pixel_10_Pro` (`API 37.1`, `targetSdk=36`, `freezer_cutoff_adj=900`) against live Supabase `auth.flow_state` (`code_issued: true`, `referrer: "http://127.0.0.1:8766/auth/callback"`), `/proc/net/tcp`, and `adb logcat`:
  1. Stale Chrome tabs left at `/auth/callback` (from `history.replaceState(null, '', '/auth/callback')`) hit `HttpServer` on `:8766` without `?code=`, triggering `AuthException('Google authentication failed')` and closing `:8766` before the active Google tab redirected (`ERR_CONNECTION_REFUSED`).
  2. Long interactive password/2FA flows in external Chrome moved the app into background cached state (`CachedAppOptimizer` freezer) without a short foreground service.
  3. `window.close()` and Windows-only `_focusDesktopWindow()` could not close Android Chrome or return focus to `.MainActivity`.
- Implemented production fix across Android, iOS, Flutter, and backend setup helper:
  - `gps_delivery_app/android/app/src/main/kotlin/com/giaohanggps/gps_delivery_app/OAuthKeepAliveService.kt`, `MainActivity.kt`, and `gps_delivery_app/android/app/src/main/AndroidManifest.xml`: added `OAuthKeepAliveService` (`foregroundServiceType="shortService"`), `ghst/window` (`startOAuthKeepAlive`, `stopOAuthKeepAlive`, `focus`), `flutter_deeplinking_enabled=false`, and `<intent-filter>` (`scheme="com.giaohanggps.gpsdelivery"`, `host="auth"`).
  - `gps_delivery_app/lib/core/auth/cloud_oauth_io.dart`: replaced `/auth/callback` history rewrite with `/auth/done`, ignored parameterless `/auth/callback` prefetches/reloads unless `error`/`error_code` is present, added `_OAuthLifecycleWatcher` so swiping Back from Chrome without logging in cleanly cancels the pending wait without stuck `_busy` state, and added automatic Android return redirect (`intent://auth/return#Intent;scheme=com.giaohanggps.gpsdelivery;package=com.giaohanggps.gps_delivery_app;end`) + fallback button.
  - `gps_delivery_app/lib/presentation/screens/cloud_auth_screen.dart`, `marketplace_screen.dart`, `ios/Runner/Info.plist`, `backend/otp-relay/setup-google-cloud.mjs`, `setup-google-cloud.test.mjs`, and `test/unified_user_interface_test.dart`: wired async `authChanges` stream `AuthException` error display without unhandled zone errors, registered `com.giaohanggps.gpsdelivery` URL scheme for iOS and `setup-google-cloud.mjs`, and added widget regression coverage.
  - Optimized local workstation Android Emulator `Pixel_10_Pro` (`GpuPreference=2;` on RTX 3050 + `Vulkan = on` + `GLDirectMem = on` + `4096 MB` RAM + `6` cores + `1080x2400 @ 420dpi`, measured `59.9 FPS` average on `SurfaceFlinger --latency`).
- Checks run: `npm test` (`116/116` backend tests passed), `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub test/unified_user_interface_test.dart test/cloud_account_session_test.dart` (`32/32` passed), `flutter build apk --release --target-platform android-x64 --no-pub --dart-define=DELIVERY_API_BASE_URL=https://ghst-backend-admin.onrender.com/delivery/`, `flutter build windows --release --no-pub`, `graphify update .`, and live zero-mock hands-free Google OAuth test on `Pixel_10_Pro` after `pm clear` (`OAuthKeepAliveService` allowed -> Google + Supabase PKCE exchange -> `LAUNCH_SINGLE_TOP` auto-return from Chrome to `.MainActivity` in `3.12s` -> landed on verified `Trang chủ` GHST EXPRESS).
- Remaining limits & next step: When deploying to iOS, supply a Supabase Management API token and run `node setup-google-cloud.mjs --apply` (or add `com.giaohanggps.gpsdelivery://auth/callback` in Supabase Auth Redirect URLs); configure `GEMINI_*` / `PAYOS_*` / `GHN_*` credentials in `/#/admin` -> `Tích hợp` when ready for live AI and payment gateway acceptance.

## Customer AI Chatbot, Floating Bubble & Backend AI Gateway (`0b3d912`) - 2026-11-02

- Added server-managed AI configuration and multi-provider AI proxy in `gps_delivery_app/backend/otp-relay/`:
  - `integration-config.mjs`: expanded `INTEGRATION_DEFINITIONS.gemini` (`AI Chatbot & Trợ lý (Gemini / OpenAI API)`) with `GEMINI_BASE_URL`, `GEMINI_API_KEY`, `GEMINI_MODEL`, and `GEMINI_ENABLED` persisted to `public.delivery_backend_config` + `public.delivery_backend_config_audit` without exposing secrets to clients, guarded by `assertSafeAiUrl` SSRF checks and `POST /delivery/admin/integrations/test/gemini`.
  - `ai-assistant.mjs`, `cloud-orders.mjs`, `delivery-integrations.mjs`, `server.mjs`, `INTEGRATIONS.md`, `.env.example`: auto-detects Google Gemini `:generateContent` endpoints and OpenAI-compatible `/chat/completions` endpoints, exposes authenticated rate-limited `POST /delivery/cloud/ai-chat` (injecting read-only RLS-scoped customer profile & recent shipping/market orders without OTP/phone secrets) and `POST /delivery/ai/chat`, and returns honest `503` when unconfigured (`0` mock/canned bot replies).
  - `commerce-db.mjs`: added `keepAlive: true` and `pool.on('error', () => {})` to prevent unhandled `ECONNRESET` crashes when Supabase Supavisor recycles idle PostgreSQL connections; pushed backend update `0b3d912` to `origin/backend-admin` and verified live Render deployment (`GET https://ghst-backend-admin.onrender.com/health` -> `200 OK`, unauthenticated `POST /delivery/ai/chat` -> `401`).
- Added both full-screen Customer AI Assistant and draggable Floating Chat Bubble in `gps_delivery_app/lib/`:
  - `lib/presentation/customer/ghst_ai_chat_screen.dart`: `GhstAiChatController` (bounded 16-turn session history, immediate wipe on `CloudSessionLease` invalidation), `GhstAiChatScreen` (`TRỢ LÝ AI GHST EXPRESS`), `GhstAiFloatingBubble` (`CHAT AI GHST` in-stack draggable bubble + compact overlay panel with `Mở toàn màn hình` and `Thu gọn bong bóng chat`, without pushing routes), and shared `GhstAiChatBody`.
  - `lib/presentation/customer/ghst_user_shell.dart`, `ghst_home_screen.dart`, `lib/presentation/screens/marketplace_screen.dart`, `lib/core/integrations/cloud_orders_service.dart`, `delivery_api_client.dart`: wired `GhstUserSection.aiAssistant`, sidebar `'Trợ lý AI'`, header AI button, Home `'Hỏi Trợ lý AI'`, and `floatingOverlay` across all non-AI user shell sections sharing one session-scoped `GhstAiChatController`.
- Checks run: `npm test` (`116/116` backend tests passed), `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub test/ghst_ai_chat_test.dart test/unified_user_interface_test.dart test/ghst_home_test.dart` (`27` test suites passed, `0` failed), `flutter build web` (`http://127.0.0.1:8787/delivery/`), `node tool/check-marketplace-browser.cjs` (`10/10` across all 5 roles at `360px` & `1440px`, capturing `ghst-ai-bubble-*.png` and `ghst-ai-chat-*.png`) + `node tool/check-admin-browser.cjs` (`2/2` at `360px` & `1440px`, `errors: 0`), `flutter build windows --release --no-pub`, live Render endpoint check (`healthOk: true`, `/delivery/ai/chat` -> `401`), and `graphify update .` (`5162` nodes, `8307` edges, `200` communities).
- Remaining limits & next step: Supply `GEMINI_BASE_URL`, `GEMINI_API_KEY`, and `GEMINI_MODEL` in `/#/admin` -> `Tích hợp` -> `AI Chatbot & Trợ lý (Gemini / OpenAI API)` to enable live AI replies (`503` returned until configured); `payOS`, `GHN`, and FCM credentials remain unconfigured until merchant credentials are supplied.

## Backend Admin UI Redesign & Live Render Sync (`c9d2468`) - 2026-11-01

- Redesigned the standalone Cloud Operator Admin Portal (`gps_delivery_app/lib/presentation/screens/admin_portal_screen.dart`) and embedded backend gateway configuration panel (`gps_delivery_app/lib/presentation/widgets/backend_integration_settings.dart`) while keeping consumer UI (`GhstUserShell`, `StudioUserAuthFrame`, `/legacy`, `/legacy-admin`) untouched and preserving 100% real Cloud data (`0` mock/static numbers):
  - **Operator Login (`/#/admin`)**: responsive split-screen layout (`>= 900px`) with dark emerald-slate showcase (`GHST CLOUD ADMIN`, security/ledger/moderation/PostgreSQL RLS pillars) + elevated login card, and compact dark top banner + centered login card on `< 900px`.
  - **Operator Workspace**: dark-slate `256px` sidebar (`PHÂN HỆ QUẢN TRỊ`, active pill indicator, verified Operator identity card) + white command bar (`Bảng giá cloud`, `Nhật ký điều hành`, `Đăng xuất`) on `>= 960px`, switching cleanly to a compact dark banner + 5-tab `NavigationBar` on `< 960px`.
  - **Realtime Analytics (`_AdminAnalyticsPanel`)**: dark gradient header, 4 responsive KPI summary tiles (`4` columns on `>= 920px`, `2×2` grid on `< 920px` including `360px` mobile), pending-task `ActionChip` shortcuts (`Xét duyệt đối tác`, `Kiểm duyệt gian hàng & báo cáo`, `Duyệt đối soát`), and 4 structured domain cards with verified completion ratios (`ExcludeSemantics` progress bars preserving full accessibility/semantics labels).
  - **Integration Gateway (`BackendIntegrationSettings`)**: `Material`-backed card surfaces (preserving `ListTile` / `ExpansionTile` / `SwitchListTile` ink splashes without `DecoratedBox` occlusion), active service counter + `Lưu trữ PostgreSQL Cloud` indicator, semantic provider icons, and color-coded status pills (`Đang bật`, `Đang tắt`, `Thiếu cấu hình`, `Chưa có luồng giao dịch`).
- Rebuilt portable zero-secret Web Admin (`flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn --dart-define=DELIVERY_API_BASE_URL=/delivery/`), verified `0` leaked credentials, synced `public-admin/` to orphan branch `backend-admin` (`c9d2468` pushed to `origin/backend-admin`), and verified Render auto-deploy `dep-dbjkfrvavr4c73c5evrg` reached `status: live` on `https://ghst-backend-admin.onrender.com/#/admin`.
- Checks run: `flutter analyze --no-pub` (`0` issues), focused Flutter widget suites (`backend_integration_settings_test.dart`, `clean_start_test.dart`, `cloud_commercial_suite_test.dart`, `widget_test.dart` -> `32/32` passed), `flutter build web` (local `:8080` + portable `/delivery/`), `flutter build windows --release --no-pub`, `node tool/check-admin-browser.cjs` (`2/2` passed at `1440px` and `360px` with `0` errors), live headless Microsoft Edge verification against `https://ghst-backend-admin.onrender.com/#/admin` (`200 OK`, `overflow: 0`, `errors: 0` at `1440px` and `360px`), and `graphify update .` (`5085` nodes, `8152` edges).
- Remaining limits & next step: Configured 10-minute `cron-job.org` keep-alive monitor (`GHST Backend Keep-Alive` -> `GET https://ghst-backend-admin.onrender.com/health`, verified `200 OK` in `236 ms` on `2026-11-02`) to keep the single Render Free service warm within the 750h/month allowance; Render Free still blocks outbound SMTP ports, and `payOS`, `GHN`, and FCM credentials remain unconfigured until merchant credentials are supplied. Next: configure `payOS`/`GHN` credentials in `/#/admin` -> `Tích hợp` when ready and run live physical two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Live Render.com Cloud Deployment (`ghst-backend-admin`) - 2026-11-01

- Provisioned and deployed Docker Web Service `ghst-backend-admin` (`srv-dbjiid0ae00c73ebaln0`, region `singapore`, plan `free`, branch `backend-admin`, `healthCheckPath: /health`) on Render.com via Render REST API v1 (`RENDER_API_KEY` stored outside the repository at `%USERPROFILE%\.env` with restricted user-only ACLs; zero secrets written to repository files).
- Configured environment variables (`DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `PUBLIC_BASE_URL=https://ghst-backend-admin.onrender.com`, `TRUST_PROXY=1`, `ADMIN_PORTAL_ONLY=true`, `SUPABASE_ENABLED=true`, `MARKET_JOBS_ENABLED=true`) and verified automatic seeding of `PUBLIC_BASE_URL=https://ghst-backend-admin.onrender.com` into `public.delivery_backend_config` alongside `TRACKASIA_ENABLED=true` and `MARKET_JOBS_ENABLED=true`.
- Live HTTPS & Microsoft Edge checks verified against `https://ghst-backend-admin.onrender.com` (commit `ba69068` on `origin/backend-admin`, after fixing `GET /` `302 /#/admin` fragment redirect loop in `server.mjs` -> `200 OK` with client-side `#/admin` hash bootstrap; `npm test` `115/115`):
  - `GET /health` -> `200 OK` (`ok: true`, container bound on `0.0.0.0:10000`).
  - `https://ghst-backend-admin.onrender.com/`, `https://ghst-backend-admin.onrender.com/#/admin`, and `https://ghst-backend-admin.onrender.com/admin` -> all `200 OK` in headless Microsoft Edge, rendering `GHST CLOUD ADMIN` login form with `0` console/page errors.
  - `POST /delivery/tracking/lookup` -> `404` domain JSON response from live Supabase PostgreSQL RPC `public.delivery_cloud_public_lookup` over verified TLS (`SUPABASE_ROOT_2021_CA`).
  - `GET /delivery/places` without token -> `401` (enforcing Supabase Auth bearer check).
- Remaining limits & next step: Render Free tier spins down after 15 minutes of inactivity (~50-60s cold start, without losing config stored in `public.delivery_backend_config`) and blocks outbound SMTP ports (`25`/`465`/`587`, affecting only legacy `/otp-email`); `payOS`, `GHN`, and FCM credentials remain unconfigured until merchant credentials are supplied. Rotate the shared `RENDER_API_KEY` in Render Account Settings if desired, and build client apps with `--dart-define=DELIVERY_API_BASE_URL=https://ghst-backend-admin.onrender.com/delivery/` when targeting the Cloud backend.

## Standalone `backend-admin` Cloud Deployment Branch - 2026-11-01

- Hardened Cloud container portability across `gps_delivery_app/backend/otp-relay/server.mjs`, `database-connection.mjs`, `server-startup.test.mjs`, and `gps_delivery_app/lib/core/config/env_config.dart`:
  - `EnvConfig.deliveryApiBaseUrl` (`env_config.dart`) now resolves relative paths (`/delivery/`) against `Uri.base` (`http`/`https`) so a single Web Admin bundle runs on any Cloud domain (`*.onrender.com`, `*.up.railway.app`, custom HTTPS, or loopback) without hardcoding `127.0.0.1:8787`.
  - `server.mjs` enables `app.set('trust proxy', 1)` under reverse proxies (`TRUST_PROXY=1`, `RENDER=true`, `RAILWAY_ENVIRONMENT`), permits same-origin + platform origins (`PUBLIC_BASE_URL`, `PUBLIC_APP_URL`, `RENDER_EXTERNAL_URL`, `RAILWAY_PUBLIC_DOMAIN`) in CORS while blocking foreign origins (`403`), and serves static Web Admin bundles (`STATIC_WEB_DIR` / `./public-admin`) with `GET /` -> `302 /#/admin`.
  - `database-connection.mjs` trusts Supabase's public Root 2021 CA (`CN=Supabase Root 2021 CA`, `rejectUnauthorized: true`) automatically for `*.supabase.com` / `*.supabase.co` when `DATABASE_CA_CERT` is omitted, allowing Cloud hosts to boot with only `DATABASE_URL`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY`.
- Created isolated orphan deployment branch `backend-admin` (`4ce8e04`) via temporary Git worktree (preserving `main` working tree intact) and pushed to `origin/backend-admin`:
  - Contains `Dockerfile` (`node:22-bookworm-slim`, non-root `node`, `ca-certificates`, `/health`), `.dockerignore`, `render.yaml`, `railway.json`, root `package.json`, `README.md`, `gps_delivery_app/database/migrations/` (13 SQL files), `gps_delivery_app/backend/otp-relay/`, and pre-built zero-secret `public-admin/` (`118` files total, `0` leaked secrets verified across all files including `main.dart.js`).
- Verified ephemeral Cloud container simulation from `backend-admin` with zero `.env`/`.integration-config.json` files and only `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`: `GET /` -> `302 /#/admin`, `GET /admin` -> `200`, `GET /delivery/admin/integrations` -> `200` (`storage: "cloud_postgres"`, `trackasiaAutoLoadedFromCloudDb: true`, `smtpAutoLoadedFromCloudDb: true`, `marketJobsAutoLoadedFromCloudDb: true`), `GET /delivery/admin/integrations/readiness` -> `200` (`database: "ok"`, `commercial_suite_schema: "ok"`), `GET /delivery/places` -> `200` (`attribution: "TrackAsia"`).
- Checks run: `flutter analyze --no-pub` (`0` issues), `npm test` (`115/115` backend tests), ephemeral Cloud container E2E test, secret leak scan (`0` leaks), and `graphify update .`.
- Remaining limits & next step: Deploy `origin/backend-admin` on Render / Railway by supplying `DATABASE_URL`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY`, then set `PUBLIC_BASE_URL` to the assigned HTTPS URL when configuring `payOS` / `GHN` webhooks.

## Cloud Operator Provisioning & Cloud PostgreSQL Backend Config Sync - 2026-11-01

- Added RLS-locked, backend-only configuration & audit tables (`public.delivery_backend_config` and `public.delivery_backend_config_audit`, with `revoke all ... from public, anon, authenticated`) to `gps_delivery_app/database/migrations/20261107_cloud_commercial_suite.sql` (`workflowVersion: 13`) and expanded `commercial_suite_schema` in `gps_delivery_app/backend/otp-relay/deployment-readiness.mjs` (`17` RLS-locked tables verified).
- Updated `gps_delivery_app/backend/otp-relay/integration-config.mjs` and `delivery-integrations.mjs`:
  - Syncs all non-bootstrap managed backend configuration keys (`14` active keys including `TRACKASIA_*`, `SMTP_*`, `GOOGLE_*`, `PHOTON_*`, `OSRM_*`, `GOOGLE_MAPS_*`, `MARKET_JOBS_ENABLED`) and audit entries into `public.delivery_backend_config` and `public.delivery_backend_config_audit` whenever `DATABASE_URL` is configured, while keeping bootstrap/identity anchors (`DATABASE_URL`, `DATABASE_CA_CERT`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`) local to the backend host.
  - Exposes `storage: 'cloud_postgres'` metadata on `GET /delivery/admin/integrations` without returning secret values.
- Applied `npm run migrate:cloud` on the live Supabase PostgreSQL database (`{"ready":true,"migration":"20261107_cloud_commercial_suite","workflowVersion":13}`), provisioned the requested verified Supabase Auth email/password Cloud Operator account (`delivery_api_profiles.role = 'operator'` + active unblocked `delivery_cloud_accounts` profile, without recording credentials in repository files), restarted backend `:8787`, and verified end-to-end:
  - Live `POST /auth/v1/token?grant_type=password` -> `200 OK`; `GET /delivery/cloud/profile` -> `200 OK` (`operator: true`, `schema_version: 3`); `GET /delivery/admin/integrations` -> `200 OK` (`storage: 'cloud_postgres'`, `trackasia.enabled: true`, `smtp.enabled: true`); `POST /delivery/admin/integrations/config` -> `200 OK` persisted to Cloud PostgreSQL + audit table; `GET /delivery/admin/integrations/readiness` -> `200 OK` (`commercial_suite_schema: 'ok'`, `database: 'ok'`, `market_jobs: 'ok'`); direct PostgREST `GET /rest/v1/delivery_backend_config` with authenticated user JWT -> `403` blocked.
- Checks run: `npm test` (`114/114` backend tests passed, including new `PGlite` Cloud PostgreSQL config sync + RLS denial test in `delivery-integrations.test.mjs`), `npm run test:postgres` (`22/22` native PostgreSQL 17 checks passed), `npm run migrate:cloud`, live Admin E2E verification on `:8787` / `:8080`, and `graphify update .`.
- Remaining limits & next step: `payOS`, `GHN`, FCM server credentials, and public non-loopback `PUBLIC_BASE_URL` HTTPS remain unconfigured until production merchant credentials and public hosting are supplied. Next: supply production `payOS`/`GHN`/HTTPS credentials and run live physical two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Direct Google Map Order Picker & Zero-Mock Live Cloud E2E - 2026-11-01

- Updated `CloudOrderForm` (`gps_delivery_app/lib/presentation/widgets/cloud_order_form.dart`), `PhotonAddressLookup` (`photon_address_lookup.dart`), and `PhotonAddressService` (`photon_address_service.dart`):
  - Removed all manual coordinate inputs (`Vĩ độ`, `Kinh độ`, `Vĩ độ dừng`, `Kinh độ dừng`) from Create Order while keeping `CloudAddressBookScreen` and `MarketplaceEditor` intact.
  - Added interactive embedded map picker (`Map3dPerspectiveWidget`, `ValueKey('cloud-order-google-map')`) with target selector chips (`[A]`, `[B]`, `#1..#5`), device GPS shortcut (`Vị trí hiện tại (GPS)`), tap-to-pin + automatic `/delivery/reverse` street-name fill, live `[A] -> [B]` route preview, debounced + manual address search (`Tìm điểm lấy/giao/điểm dừng trên Google Map`), and `_ensureCoordinatesResolved()` submit-time geocoding fallback.
- Updated backend (`gps_delivery_app/backend/otp-relay/integration-config.mjs`, `integration-monitor.mjs`, `delivery-integrations.mjs`, `delivery-gateway.mjs`, `database-connection.mjs`, `provider-http.mjs`, `cloud-orders.mjs`, `server.mjs`):
  - Added server-side `trackasia` (`TRACKASIA_ENABLED`, `TRACKASIA_API_KEY`) and optional `google_maps` (`GOOGLE_MAPS_ENABLED`, `GOOGLE_MAPS_API_KEY`) proxies across `/places`, `/reverse`, `/route`, and `/matrix` with 3-service `testIntegration` health checks; configured local gitignored `.integration-config.json` with `TRACKASIA_ENABLED=true`, `PHOTON_ENABLED=false`, `OSRM_ENABLED=false`, `GOOGLE_MAPS_ENABLED=false` and verified live `/places`, `/reverse`, `/route`, `/matrix` on `:8787`.
  - Fixed two production issues uncovered during live zero-mock E2E: (1) `CloudOrderDetailsScreen._showOtp` (`cloud_order_details_screen.dart`) now reads PostgreSQL's `otp_code` key (`res['otp_code'] ?? res['recipient_otp']`); (2) `createIdentity` (`delivery-integrations.mjs`) preserves upstream `502`/`429` errors instead of returning `401 Unauthorized` so transient network drops do not invalidate `CloudSessionLease`.
  - Hardened Windows/PPPoE networking in `database-connection.mjs`: IPv4-only DNS resolver (`1.1.1.1`/`8.8.8.8` + system IPv4, bypassing dead IPv6 fallback DNS), TCP `:443` fastest-IP probing, and classical ECDH curves (`X25519:prime256v1:secp384r1`) to avoid OpenSSL 3.5 Post-Quantum TLS 1.3 `ClientHello` fragmentation over 1492-byte PPPoE MTU.
- Executed real zero-mock multi-role browser E2E (`gps_delivery_app/build/verification/live-e2e/live-e2e-report.json` + `16` live PNG screenshots `01`..`16`) in Microsoft Edge against live `http://127.0.0.1:8080/`, live backend `http://127.0.0.1:8787/delivery/`, and live Supabase Auth + PostgreSQL without any `page.route` interception:
  - Verified first-time Buyer profile creation, direct map tap reverse-geocoding + address search + OSRM route quote + order creation with 6-digit OTP, unauthenticated `/#/track` lookup, Merchant & Driver partner requests, Operator `/#/admin` realtime analytics + partner/shop approvals, Merchant catalog publishing, Buyer cart/quote/checkout, Merchant `Sẵn sàng giao`, and Driver queue claim (`Nhận chuyến`) -> `Đã đến lấy hàng` -> `Đã lấy hàng` -> `Giao thành công` with real 6-digit OTP verification in PostgreSQL.
  - Scoped cleanup removed only disposable `@ghst-live.test` test rows and verified exact pre-test baseline restoration (`{"auth_users":2,"cloud_accounts":2,"operators":1,"shops":0,"products":0,"purchases":0,"shipping_orders":0}`).
- Checks run: `npm test` (`113/113` backend tests), `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub` (`277` passed, `1` optional skip, `0` failed), `check-cloud-browser.cjs` (`6/6` at `1440px`/`360px`), `flutter build web --no-pub --no-wasm-dry-run --no-web-resources-cdn`, `flutter build windows --release --no-pub`, `graphify update .`, live zero-mock E2E (`16` PNGs, `cleanBaselineRestored: true`), live TrackAsia E2E probe on `:8787`, and `gps_delivery_app.exe` relaunched interactively in Session 1 (`PID 9492`, `Responding: True`).
- Synchronized repository documentation (`README.md`, `gps_delivery_app/README.md`, `P0_SYNC_MATRIX.md`, `EXECUTION_CHECKLIST.md`, `backend/otp-relay/CLOUD_ORDERS.md`, `COMMERCE.md`, `INTEGRATIONS.md`, `MARKETPLACE.md`, and `.env.example`) with `workflowVersion: 13`, interactive map order picker (zero manual coordinate inputs), server-side `trackasia` & `google_maps` proxies, `otp_code` 6-digit recipient OTP gate, and `2026-11-01` verification counts (`113/113` Node, `277` Flutter, `22/22` PostgreSQL 17, `16` zero-mock live E2E PNGs).
- Remaining limits & next step: `GOOGLE_MAPS_ENABLED` defaults to `false` (note Google Maps Platform Prohibited Territories restrictions for Vietnam), and `payOS`, `GHN`, FCM server credentials, and public non-loopback `PUBLIC_BASE_URL` HTTPS remain unconfigured until production merchant credentials and public hosting are supplied. Next: supply production `payOS`/`GHN`/HTTPS credentials and run live physical two-device + signed webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Full Ordered Verification & 62-Screenshot UI Acceptance Gallery - 2026-10-31

- Executed full direct UI button-by-button and role-by-role acceptance across Desktop (`1440px`) and Mobile (`360px`) in headless Microsoft Edge against `build/web` with isolated test fixtures (zero production writes), and ran the complete 10-step ordered suite (`gps_delivery_app/tool/verify-commercialization.ps1 -Browser` -> `gps_delivery_app/build/verification/ordered-checks.json` with `selectedChecksPassed: true` at `2026-10-31T15:57:19Z`).
- Uncovered and fixed 4 genuine UI/runtime defects during direct button testing:
  1. `gps_delivery_app/lib/presentation/screens/market_order_services_screen.dart` (`_returnList`): PostgreSQL `delivery_market_returns.attachments` stores JSONB string paths (`["return/...webp"]`), causing `_rows(r['attachments'])` (`e as Map`) to throw `TypeError` and render a gray `ErrorWidget` after submitting a return with evidence; fixed list guard and hardened `Clipboard.setData` in `_share()`.
  2. `gps_delivery_app/lib/presentation/customer/ghst_user_shell.dart` & `gps_delivery_app/lib/presentation/screens/marketplace_screen.dart`: wired `onDriverOrders: _openShipping` so desktop sidebar `'Chuyến giao của tôi'` resets `_purchaseOrders = false` instead of staying on `'Đơn mua'`.
  3. `gps_delivery_app/lib/presentation/screens/admin_portal_screen.dart`: fixed `_moderate` skipping refresh while `_busy == true` (`await _loadReports(force: true)`) and added compact `< 600px` header layout so `360px` mobile never clips `GHST CLOUD ADMIN`.
  4. `gps_delivery_app/lib/presentation/screens/cloud_order_details_screen.dart` & `gps_delivery_app/lib/presentation/widgets/market_commercial_sheets.dart`: hardened `Clipboard.setData` calls against browser permission rejection.
- Added regression tests in `gps_delivery_app/test/cloud_commercial_suite_test.dart` and `gps_delivery_app/test/unified_user_interface_test.dart`, updated `gps_delivery_app/tool/check-cloud-browser.cjs`, added the 6-suite Playwright acceptance harness `gps_delivery_app/tool/check-full-ui-acceptance.cjs`, and registered Step 10 in `gps_delivery_app/tool/verify-commercialization.ps1`.
- Produced organized acceptance gallery in `gps_delivery_app/build/verification/acceptance/` (`INDEX.md`, `acceptance-report.json`, and **62 PNG screenshots** with `0` runtime errors and `0` horizontal overflow across `01-auth-and-public/` [8], `02-customer/` [21], `03-merchant/` [11], `04-shop-staff/` [4], `05-driver/` [5], `06-operator-admin/` [13]).
- Checks actually run (`10/10` passed in `ordered-checks.json`): (1) `npm run test:postgres` (`22/22` native PostgreSQL 17 checks), (2) `npm test` (`108/108` backend tests), (3) `flutter analyze --no-pub` (`0` issues), (4) `flutter test --no-pub` (`275` passed, `0` failed), (5) `flutter build web --no-pub --no-wasm-dry-run --no-web-resources-cdn`, (6) `flutter build windows --release --no-pub`, (7) `check-marketplace-browser.cjs` (`10/10` across `customer`, `merchant`, `shop_staff`, `partner`, `operator` at `360px`/`1440px`), (8) `check-cloud-browser.cjs` (`6/6` at `360px`/`1440px`), (9) `check-admin-browser.cjs` (`2/2` at `360px`/`1440px`), (10) `check-full-ui-acceptance.cjs` (`6/6` suites, `62` PNGs). Also ran `graphify update .` (`5012` nodes, `8009` edges) and relaunched `gps_delivery_app.exe` interactively in Windows Session 1 (`PID 19768`).
- Remaining limits & next step: `commercializationComplete` remains `false` in `ordered-checks.json` because isolated browser fixtures do not certify live multi-device Auth, real `payOS`/`GHN`/FCM credentials, public non-loopback `PUBLIC_BASE_URL` HTTPS, hosted CI, backup restore, or pilot operations; `/legacy` and `/legacy-admin` remain isolated archives. Next: supply production `payOS`/`GHN`/HTTPS credentials and run live two-device & webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Full Cloud Commercial Suite Sync (P1–P6, /admin & /track) - 2026-10-31

- Completed end-to-end Cloud logic synchronization across PostgreSQL (`gps_delivery_app/database/migrations/20261107_cloud_commercial_suite.sql`, `workflowVersion: 13`), Node backend (`gps_delivery_app/backend/otp-relay/`), and Flutter UI (`gps_delivery_app/lib/`), while keeping legacy SQLite screens isolated as archives at `/legacy` and `/legacy-admin` (`legacy_admin_portal_screen.dart`):
  - **P1 Catalog & Staff**: shop cover (`banner_url`), service-area geofence (`service_radius_km`), shop staff delegation (`delivery_market_shop_staff`: `manager`/`staff` + `isStaffOfShop`/`isManagerOfShop` in `CloudAccountSession`), multi-SKU variants (`delivery_market_variants`), and parcel dimensions (`length_cm`, `width_cm`, `height_cm`) in `marketplace_editor.dart` and `market_product_details.dart`.
  - **P2 Shipping & Checkout**: all 5 Cloud shipping modes (`standard`, `express`, `saving`, `same_day_2h`, `truck`), volumetric weight (`L*W*H/5000`), `extra_stops` (`+5,000 VND/stop`), `round_trip` (`+60%`), cargo insurance (`declared_value`, `0.5%` clamped `2,000..150,000 VND` up to `30M`), Green Fund (`+1,000 VND`), EV CO2 (`48 g/km`), `scheduled_at`, and checkout `buyer_note` / `service_type` / `payment_method` / `voucher_code` / `use_coins` / `prefer_ev` / `require_pod` / `require_otp` across `ghst_home_screen.dart`, `cloud_order_form.dart`, and `marketplace_view.dart`.
  - **P3 Prepaid Multi-Shop Finance**: `payment_method IN ('cod','prepaid')`, `purchase_id` FK on `delivery_payment_transactions`, `/delivery/cloud/purchases/:id/payment*` `payOS` intents (`payment-gateway.mjs`, `cloud_commerce_dialog.dart`), double-entry prepaid capture (`delivery_market_record_prepaid_capture` with `promo_expense` balancing), and stale payment expiry in `delivery_market_run_jobs`.
  - **P4 Fulfillment, POD/OTP, GPS & `/track`**: multi-parcel split shipments (`delivery_market_shipments` + `order_shipment_split`), recipient OTP (`delivery_cloud_order_secrets` + `delivery_cloud_order_otp`), mandatory POD/OTP gate on `delivery_cloud_transition('deliver')` with sanitized history reason, server GPS jump/speed guard (`<= 120 km/h`, `<= 30m` at `dt <= 0`), revocable shipping share tokens (`delivery_cloud_shares` + `delivery_cloud_share_manage`), and Cloud public lookup (`POST /delivery/tracking/lookup` -> `delivery_cloud_public_lookup`) replacing `AppStateStore` on `/track` (`public_order_tracking_screen.dart`).
  - **P5 Evidence, Returns, Reviews & Push**: RLS-locked `'delivery-private-evidence'` Storage bucket + `delivery_market_attachments` (`/delivery/cloud/attachments*` for `chat`, `return`, `finance`), reverse return shipment creation & `restock`/`writeoff` inventory disposition on `return_action`, separate shop & driver reviews (`delivery_partner_reviews`) + review reply/report (`delivery_market_review_reports`), shop follows (`delivery_market_shop_follows`), and FCM notification delivery + `push_notification_service.dart` opt-in toggle.
  - **P6 Incentives & Unified Cloud `/admin`**: server-budgeted vouchers (`delivery_market_vouchers`, `voucher_usages`), time-windowed flash sales (`delivery_market_flash_sales`, `flash_claims`), coin wallet & immutable ledger (`delivery_market_coin_wallets`, `coin_ledger`: 20% redeem cap, 1% settled earn, cancel/refund reversals), `market_commercial_sheets.dart`, `admin_analytics`, and unifying `/admin` (`admin_portal_screen.dart`) on Cloud Operator (`CloudAccountSession` + `isOperator`).
- Applied live additive migration `npm run migrate:cloud` -> `{"ready":true,"migration":"20261107_cloud_commercial_suite","workflowVersion":13}`, enabled `MARKET_JOBS_ENABLED=true` in managed backend config and `.env`, added IPv4-first DNS resolution in `database-connection.mjs` to avoid 15s IPv6 pooler timeouts on Windows, and verified live read-only readiness (`2026-10-31T08:50:44.736Z`): all 17 DB/schema/worker/RLS/permission/Supabase checks returned `ok` (`commercial_suite_schema: ok`, `market_jobs: ok`). Updated `PROJECT_CONTEXT.md`, `EXECUTION_CHECKLIST.md`, `P0_SYNC_MATRIX.md`, and `backend/otp-relay/MARKETPLACE.md`.
- Checks run: `npm run test:postgres` (`22/22` native PostgreSQL 17 checks passed), `npm test` (`108/108` backend tests passed) + `database-connection.test.mjs` (`1/1`), `flutter analyze --no-pub` (`0` issues), `flutter test --no-pub` (`274` passed, `1` optional external skip, `0` failed; including new `test/cloud_commercial_suite_test.dart`), `flutter build windows --release --no-pub`, `flutter build web --no-pub --no-wasm-dry-run --no-web-resources-cdn`, `graphify update .`, backend daemon running on `http://127.0.0.1:8787`, and `gps_delivery_app.exe` relaunched interactively in Session 1 (`PID 17800`).
- Remaining limits & next step: `payos`, `ghn`, FCM server credentials, and public non-loopback `PUBLIC_BASE_URL` HTTPS remain unconfigured until real merchant credentials and public hosting are supplied; `/legacy` and `/legacy-admin` remain isolated archives. Next: supply production `payOS`/`GHN`/HTTPS settings and run live two-device & webhook acceptance per `EXECUTION_CHECKLIST.md`.

## Cloud Schema Sync, OAuth UI Fix & Scope Audit - 2026-10-31

- Real desktop Google OAuth PKCE callback (`127.0.0.1:8766/auth/callback`) confirmed
  end-to-end Google -> Supabase `/auth/v1/callback` -> desktop code handoff, and
  exposed two UX/lifecycle bugs: raw plain-text `Return to GO-MAU.` in Chrome
  without window focus, and `MarketplaceScreen` tearing down `GhstUserShell` into
  an unstyled `GO-MAU` `AppBar` spinner on `AppLifecycleState.inactive` (focus loss)
  or unframed verification/onboarding states.
- Fixed in `gps_delivery_app/windows/runner/flutter_window.h`/`.cpp` (native
  `ghst/window` `focus` channel), `lib/core/auth/cloud_oauth_io.dart` (styled UTF-8
  GHST EXPRESS callback HTML with `Cache-Control: no-store`, `history.replaceState`
  code stripping, `window.close()`, and native window focus after `exchangeCodeForSession`),
  `lib/presentation/screens/marketplace_screen.dart` (only `hidden`/`paused`/`detached`
  clear `_foreground`; verification/error/blocked/incomplete states stay inside
  `StudioUserAuthFrame`), `lib/presentation/widgets/cloud_profile_form.dart`
  (prefill Google `userMetadata` name on first-time profile), and
  `test/unified_user_interface_test.dart` (added 2 regression groups across
  `360.0` and `1440.0` widths).
- Synchronized additive cloud PostgreSQL migrations (`20261027`–`20261106`) on the
  configured Supabase database via `npm run migrate:cloud` ->
  `{"ready":true,"migration":"20261106_catalog_configuration","workflowVersion":12}`
  (including `notify pgrst, 'reload schema'`). Live `GET /delivery/admin/integrations/readiness`
  at `2026-10-31T06:00:21.934Z` returned `ok` across all 14 DB/schema/RLS/permission
  checks (`database`, `cloud_schema`, `membership_schema`, `import_schema`,
  `stock_terms_schema`, `market_media_schema`, `browse_schema`,
  `configuration_schema`, `address_schema`, `marketplace_schema`,
  `operations_schema`, `commerce_schema`, `database_permissions`,
  `commerce_privacy`, `supabase`); `npm run check:cloud` -> `present-auth-required`.
  Updated `PROJECT_CONTEXT.md`, `EXECUTION_CHECKLIST.md`, `P0_SYNC_MATRIX.md`,
  and `backend/otp-relay/MARKETPLACE.md`.
- Checks run: `flutter analyze --no-pub` (0 issues), focused widget suites
  (`unified_user_interface_test.dart` 16/16, `marketplace_test.dart`,
  `ghst_home_test.dart`, `market_consistency_test.dart`, `cloud_orders_test.dart`),
  `flutter build windows --release --no-pub`, `flutter build web --no-pub --no-wasm-dry-run --no-web-resources-cdn`,
  `graphify update .`, and relaunched `gps_delivery_app.exe` interactively (`PID 23356`).
- Remaining limits & next step: `market_jobs` disabled (`MARKET_JOBS_ENABLED=false`),
  `payos`/`ghn`/`public_https` missing, legacy `/legacy` SQLite data intentionally
  unmigrated, and P1–P6 roadmap items still pending. Next: verify first-time cloud
  profile save after Google sign-in, real email recovery, two-device E2E acceptance,
  and proceed with `MARKET_JOBS_ENABLED` / provider credentials / P1–P6 batches.

## Graphify Antigravity & Project Setup - 2026-10-31

- Installed `Graphify-Labs/graphify` 0.9.99 (`v8` @ `a0946f96`) with `[sql,mcp]`
  via `uv tool install --force`, replacing the broken sandbox trampoline in
  `%USERPROFILE%/.local/bin` (`graphify.exe` and `graphify-mcp.exe`).
- Configured Antigravity globally (`~/.gemini/config/skills/graphify/` Windows
  PowerShell skill and `~/.gemini/config/mcp_config.json` stdio MCP server) and
  at project scope (`.agents/skills/graphify/` and `.agents/rules/graphify.md`,
  without deprecated `.agents/workflows/`). Updated `AGENTS.md` and `GRAPHIFY.md`.
- Rebuilt and ran `graphify update .` locally (AST-only, honoring `.graphifyignore`
  with zero `.env`/`.integration-config.json`/`.agents`/`.codex` leaks): 261
  scanned files, 4,678 nodes, 7,260 edges, 197 communities (indexing `GhstUserShell`
  and related 2026-10-31 files). Verified CLI (`explain`/`query`) and live stdio
  MCP JSON-RPC (`initialize`, `tools/list` -> 10 tools, `query_graph`, `get_node`).
- Limits: Dart extraction remains regex-based (16 files yielded no symbols);
  existing Antigravity sessions require refreshing MCP Servers to load the new
  `graphify` server. No app code, cloud settings, DB records, commit or push
  changed. Prior application handoff below remains active: verify real Google
  sign-in from the running app and continue P1-P7 commercialization items.

## Google Public OAuth Reaches Sign-in - 2026-10-31

- After the user reported updating configuration, a fresh read-only check
  confirmed the saved Google ID/secret are present and Supabase Google is enabled.
  Authorize returned 302 to accounts.google.com with the matching saved client
  ID and hosted Supabase callback. The public Google OAuth handshake returned
  302 to /v3/signin/identifier, then HTTP 200, without redirect_uri_mismatch.
  This supersedes the previously observed mismatch for this handshake only;
  actual account authentication, consent and resulting app session/profile
  remain unverified. No account credentials or OAuth state were logged.
- In-app browser access still reports disabled in Work settings, preventing
  signed-in Console inspection or interactive account verification. Existing
  configuration remains STEPS_PROSE; no Codex settings were changed.
- Preview 8080 returned HTTP 200. Backend 8787 was stopped and was restarted
  hidden using the existing saved configuration; /health then returned HTTP 200.
  Backend process at this check: 22252; logs are in %LOCALAPPDATA%/GHST/logs.
  No Auth settings, application code, database records, commit or push changed.
  Next: perform Google sign-in from the running app and verify its real
  Supabase session and owned cloud profile.

## Google Callback Mismatch Confirmed - 2026-10-31

- User's actual Google sign-in screenshot reports HTTP 400
  redirect_uri_mismatch. Google provider is enabled, but real sign-in is blocked
  by the Google OAuth client's authorized callback configuration. This supersedes
  the previous unverified Google Console callback status below.
- Fresh read-only authorize probe returned 302 to accounts.google.com with the
  saved Google client ID and exact callback
  https://yvnbfurazjbhbopahtmx.supabase.co/auth/v1/callback.
  Register this exact URI in that client's Google Cloud Authorized redirect URIs.
  If the existing credential is Desktop rather than Web application, configure
  a Web client and then deliberately update Supabase using its corresponding ID
  and secret; the app's loopback callback is not Google's Supabase callback.
- Browser access still returns "Local browser use is disabled in Work settings".
  Requested opening Google Auth Platform /auth/clients; UI returned queued.
  No Google Console settings could be inspected or changed. Targeted Downloads
  search found no client-secret/OAuth JSON export to establish the client type.
  No additional Auth writes, app edits or tests in this diagnostic turn.
  Next: add Google Web client's callback in Console, save, then start a fresh
  app Google login and verify its resulting Supabase session/profile.

## Google Provider Enabled On Cloud - 2026-10-31

This supersedes the blocked Google setup entry below. User authorized reusing
saved Google credentials and configuring Supabase, then completed official CLI
verification. Initial CLI session failed in the dashboard and was cancelled;
the replacement session signed in successfully. All interactive sessions closed.

- Applied saved backend Google Client ID/Secret to the existing hosted project's
  Management API. Existing Auth settings were read first; only Google enabled,
  matching Google ID/secret and additive app redirects were patched. Site URL,
  other providers and existing redirects preserved. Google callback points to
  the hosted project's /auth/v1/callback. Allowed app redirects now include
  http://127.0.0.1:8080/, http://localhost:8080/ and desktop PKCE callback
  http://127.0.0.1:8766/auth/callback.
- Management read-back verified the submitted Google ID/enabled/redirects. Fresh
  public Auth settings returned HTTP 200 with Google true and email true.
  A fresh public authorize request returned 302 to accounts.google.com with
  the expected saved client ID and hosted Supabase callback. A subsequent
  anonymous Google endpoint probe timed out; no real Google session was opened.
  Authenticated Google account sign-in remains unverified; the user must select
  their Google account in the OAuth browser. Google Console Web-client callback,
  consent restrictions and end-to-end cloud profile still need that real check.
- Added backend/otp-relay/setup-google-cloud.mjs and Windows wrapper
  setup-google-cloud.ps1, plus npm setup:google-cloud and MARKETPLACE.md guidance.
  Check mode previews changes; apply mode uses saved Google settings and the
  official CLI Windows credential (or an explicit Management API token).
  No credentials or verification codes are printed by these helpers or embedded
  in Flutter/source/docs. Scoped token fallback file remains empty outside Git.
  Conflicting Google IDs/incomplete reads abort; existing client IDs/redirects
  survive. TLS is verified; read requests can retry, uncertain writes never do.
- Supabase management connectivity was intermittent on this host. IPv4 DNS
  selection reached the alternate official address without hardcoding IPs or
  disabling TLS. Final live apply/read-back passed; some independent probes
  timed out. A successful provider setting does not certify a real OAuth session.
- Focused tests: 16 passed (11 setup cases and five integration-config cases).
  git diff --check passed. No Flutter source changed or rebuild needed.
  Reopened Windows release PID 24488, confirmed responsive. Backend/preview
  launch attempts exited with EADDRINUSE because those ports already had
  listeners; preserved the existing servers. Final loopback preview 8080 and
  backend 8787/health checks both returned HTTP 200. Do not reuse the exited
  launch PIDs 17516/27068 as service ownership evidence.
  Current logs: build/verification/google-login-*.log. Recheck live processes
  next turn. No database migration, application data write, commit or push.

## Google Cloud Login Follow-up - 2026-10-31

- User requests Google account sign-in. Existing canonical CloudAuthScreen and
  cloud_oauth web/native adapters already implement Supabase Google OAuth; the
  button is hidden unless public Auth settings report Google enabled.
- Fresh read-only inspection: Google Client ID and Client Secret are still
  present in both managed backend configuration and native GHST settings. No
  values were printed, copied into documentation or changed. Default project's
  public /auth/v1/settings returned HTTP 200 with Google false, email true.
- No Supabase management token was present in the checked backend environment;
  no Supabase CLI command was available. Browser setup returned "Local browser
  use is disabled in Work settings", so dashboard configuration could not be
  inspected or changed. Requested opening the project's provider dashboard;
  UI tool returned queued, not confirmation of an opened/authenticated page.
- Google login remains blocked on enabling/configuring the hosted provider.
  Google Web OAuth callback must point to the project's /auth/v1/callback;
  Supabase allowed app redirects need http://127.0.0.1:8080/ for the current
  web preview and http://127.0.0.1:8766/auth/callback for the desktop PKCE flow.
  Do not bypass this with legacy SQLite identity or infer cloud identity from
  Google email/userinfo. No app changes, tests, provider writes or real Google
  sign-in were performed in this follow-up. Next: obtain dashboard access or
  authorized Management API access, preserve existing settings, enable Google,
  then verify a real Google account session and owned cloud data.

## Whole Original GHST EXPRESS Interface - 2026-10-31

User rejected the previous frame-only Marketplace restoration and explicitly
selected the whole original customer UI: Home, map, Shipping, Food, Orders and
Profile. This entry supersedes the presentation claims in the entry below.
Buyer, merchant and driver functions share this interface; Admin stays separate.

- Added ghst_user_shell.dart, ghst_home_screen.dart and ghst_shipping_screen.dart.
  Restored the original grouped desktop sidebar, white desktop header, dark
  mobile header and five customer tabs. Home restores its destination strip,
  six-service grid, discovery list, map and recent orders, in two desktop columns.
- MarketplaceScreen now defaults to this Home. Food, cart, purchase/shipping
  orders, profile, notifications, addresses and approved partner work remain
  connected to canonical cloud operations within the common interface. /cloud
  selects shipping orders, including after sign-in. Admin remains separate.
- Reused Map3dPerspectiveWidget with scoped cloud addresses/order endpoints and
  physical device GPS. Map selections open shipping coordinates. No legacy
  local route, driver, balance, rewards, prices or catalog fallback is imported.
  Unsupported cloud 2H, saving and truck modes stay disabled.
- Embedded CloudOrderForm retains authoritative quotes and returns to orders
  after creation without popping the app route. Session leases reject late
  private responses; identity changes clear private forms/navigation. Revoked
  partner rights return to the shared profile. Original login styling restored
  while preserving Supabase identity, recovery and configured Google availability.
- Fresh verification: Flutter analyze clean; full Flutter suite 265 passed,
  one optional external-service skip (ghst-original-full-tests.log). New Home
  cases cover cloud/map routing, failed-read retry, revoked late responses and
  embedded quote/create; role/navigation coverage includes 360/1440 widths.
  Final Web and Windows release builds passed.
- Browser fixtures: eight marketplace cases, six cloud compatibility cases and
  two separate Admin cases passed at 360/1440. Final partner desktop rerun fixed
  a strict selector matching both sidebar/profile shortcuts; operator desktop
  rerun passed too. Viewed Home, mobile map and login captures, including map
  tile rendering and zoom interaction. Fixture data is isolated from production.
- Final Windows app PID 3596 was responsive. Preview 127.0.0.1:8080 and backend
  127.0.0.1:8787/health returned HTTP 200 at close-out. Screenshots and test logs
  are in gps_delivery_app/build/verification. Recheck these live states next time.
- Updated PROJECT_CONTEXT.md and backend/otp-relay/MARKETPLACE.md. Existing
  staged/unstaged/untracked work and saved configuration preserved. No cloud
  migrations, live writes, commits, pushes or deployment in this batch.
  Prior cloud schema/provider/HTTPS gaps still apply; isolated checks do not
  certify deployed transactions or complete the whole commercialization plan.

## Shared Original User Interface - 2026-10-31

Latest user correction: preserve the original GHST/Studio login and share the
user interface across buyers, merchants and drivers. Admin remains separate.
This entry supersedes earlier presentation choices, not the cloud rollout limits.

- Extracted the original login frame/brand into StudioUserAuthFrame and reused
  it in both original and canonical authentication screens. Canonical login
  keeps Supabase Auth, recovery and configured Google availability; presentation
  sharing does not route cloud users through SQLite password/OTP authorization.
- MarketplaceScreen is the common responsive shell with original AppTheme,
  desktop sidebar and five mobile destinations. Merchant workspaces and shipping/
  driver work open inside that shell according to verified permissions. Revoking
  merchant access clears its workspace. Admin routes remain separate; /cloud
  opens the shared shell at shipping. Removed global viewport text scaling.
- Embedded shipping omits the duplicate account/logout header, uses available
  layout height and exposes refresh. Account shortcuts reuse shell navigation.
  Corrected the inherited white AppBar title color; visually checked final
  desktop catalog, mobile notifications and original login screenshots.
- Verification for this batch: full Flutter suite 261 passed, one optional
  external-service skip (build/verification/unified-user-full-tests.log), including
  12 shared-UI regressions. Eight marketplace, six cloud compatibility and two
  separate Admin browser fixtures passed before the final title-color change.
  After that color-only change, customer browser flows passed at 360/1440;
  Web and Windows release builds passed and Flutter analyze reported no issues.
- Opened the final Windows release for the user. Preview and backend health
  returned HTTP 200 at 127.0.0.1:8080 and 127.0.0.1:8787/health. Browser fixtures
  use isolated test data; no demo accounts/catalog were added to production.
- No cloud migrations, live writes, commit, push or deployment in this batch.
  Cloud migration/provider/HTTPS gaps in the prior audit still apply. This
  verifies presentation and isolated flows, not deployed real transactions or
  completion of the P0-P7 commercialization plan.

## Logic And UI Audit - 2026-10-30

Latest request: check logic/data consistency and broken UI flows. This entry
supersedes the historical implementation status below. The whole P0-P7 plan
remains incomplete. Preserved existing work and saved configuration; no cloud
writes, migrations, production seeds, commits, pushes or deployments.

- Completed configured-catalog implementation through migration
  20261106_catalog_configuration, workflow 12: options/surcharges, schedules,
  gallery, preparation time, distinct configured cart lines and exact-line
  reorder/returns/refunds. Earlier notes saying it is unimplemented are obsolete.
- Fixed displayed-cart versus quote mismatch: Flutter sends cart/address versions;
  SQL rejects stale or forged input, preserves legacy optional-version callers,
  and still derives all prices. Confirmation shows snapshot items/options/address.
- Cart conflicts reload actual cart/addresses and discard quote consent. Address
  outages retain the cart, expose a retry state and disable quote submission.
  Failed initial reads no longer claim empty orders/cart/notifications or invite
  shop creation. Filter failures discard results from the previous filter.
- 401/403 revoke the current private-view lease and clear data; no immediate
  profile-refresh loop. Revoked old leases cannot invalidate a newer session.
  Object-level 404 clears stale product/order/chat data. Aftersales 409 refreshes
  current details. Chat distinguishes successful emptiness from failed reads.
- Purchase labels reflect delivered/in-transit/returned states and omit null
  reasons. Returning from aftersales refreshes the parent order list.
  Notification taps mark read and open the referenced order or conversation.
- Fresh verification after audit: native PostgreSQL 17 groups; backend 94 tests;
  Flutter analyze clean; Flutter 249 passed and one external-service skip.
  Web and Windows release builds passed. Browser fixtures: eight marketplace,
  six cloud compatibility, two separate Admin cases passed at 360/1440, with
  notification/order/chat navigation and authoritative quote confirmation.
  Viewed fresh cart/notification/chat screenshots; no observed overlap.
  Launched the new Windows build; its window was responsive. Backend 8787 and
  preview 8080 returned HTTP 200 at close-out. Recheck before future claims.
- test/market_consistency_test.dart adds 21 regression cases. Native configured
  catalog acceptance adds stale cart/address and forged quote payload checks.
  Screenshots/reports remain under gps_delivery_app/build/verification.
  ordered-checks.json predates this audit; use this entry and UI_LOGIC_AUDIT.md
  for the fresh evidence rather than relabeling the older ordered run.
- Read-only live inspection at 2026-10-30T16:49:31Z: verified-TLS database,
  cloud/address/commerce schema and permissions/privacy passed. Membership,
  import, marketplace, operations, stock terms, media, browse and configuration
  schemas are absent. payOS/GHN/public HTTPS are incomplete; worker disabled.
  Real cloud purchases and two-device/provider transactions are NOT certified.

Next: review/apply the existing Admin migration package through workflow 12 in
an authorized rollout, then verify real Auth/ownership and two-device shopping.
Continue remaining P1-P7 gaps in EXECUTION_CHECKLIST.md; they include unfinished
features as well as external setup. This record does not grant cloud-write
permission. Do not replace cloud failures with demo/local production data.

## Project Skill Consistency Rule - 2026-10-30

- Updated the installed delivery-codebase-memory/SKILL.md at the user's request:
  app logic, feature, and UI changes must keep affected screens, navigation,
  permissions, state, data contracts, and displayed results connected.
- Require checks of affected user flows and explicit reporting of unverified
  connections; preserve cloud versus legacy identity/data boundaries.
- Skill Creator quick_validate.py passed. Documentation-only change; no app
  tests run or app behavior changed. Continue the implementation handoff below
  using this rule for subsequent changes.

## Graphify Integration - 2026-10-30

- User requested Graphify installation for Codex in this repository. Installed
  uv and isolated graphifyy[sql] 0.9.97; updated user executable PATH. Project
  installer created .codex/skills/graphify (with references), .codex/hooks.json
  and appended AGENTS.md guidance. Adapted guidance to preserve project rules,
  permit source verification, use $graphify, and keep the initial index local.
- Added .graphifyignore, root .gitignore entries and GRAPHIFY.md usage/limits.
  Generated graphify-out/ is local/ignored. Initial code-only extraction with
  SQL support and cluster-only --no-label succeeded: 4,375 nodes, 6,842 edges,
  168 communities. HTML/report/JSON generated. explain CloudAccountSession and
  query CloudOrdersRepository succeeded. No application tests were run for this
  tooling change; these checks do not certify application or cloud behavior.
- Dart extraction is regex-based; 15 scanned source files yielded no symbols.
  No semantic API calls, live database reads/writes, commit, push or deployment.
  Existing application changes preserved. Next: Codex can use the project skill
  on the next turn; update graph after source changes. Prior implementation
  handoff below remains separate from this tooling request.

## Historical Implementation Notes

The implementation status below predates the configured-catalog completion and
audit above. Retained for history, not current execution instructions.

Updated: 2026-10-30. Working handoff, not deployment or release certification.

## Request And Current Work

The user wants the complete P0-P7 commercialization plan implemented and tested
in dependency order. Latest steering is to continue. The plan is NOT complete;
do not stop at a feature batch and claim full delivery. Existing dirty work and
saved credentials are preserved. No cloud writes, seeds, deployment, commit or
push were performed. The memory skill was used, not reinstalled.

Current additions beyond the prior operations baseline:

- 20261101_partner_memberships: independent merchant/driver requests, operator
  review/version/reason/audit and revoke guards for active fulfillment; profile
  schema 3, strict immutable session roles, leases/repository/Admin/UI gates.
- 20261102_local_address_import: verifies actual legacy password only on device,
  reads only that local owner's addresses, previews and confirms destination;
  atomic server import, duplicate/conflict report and account-scoped source hash.
  Does not import Auth passwords/orders/money or send local password to backend.
- 20261103_catalog_stock_versions: fixed real concurrent checkout rejecting the
  second buyer despite available stock; terms_version changes independently of
  stock/version/updated_at. Price/visibility changes still invalidate quotes.
- 20261104_market_media: backend decodes JPEG/PNG/WebP, strips EXIF and re-encodes
  bounded WebP with sharp; scoped immutable content-hash Storage insert and
  reservation budget. Consumer editor selects files, never provider secrets.
  Public product bucket must never receive KYC/return/private evidence.
- 20261105_market_browse: fixed authenticated catalog RPC, server category/stock/
  price filters, keyset sort with tied prices, safe shop projection and shop page.
  Flutter clears/reloads filter pages, deduplicates products and validates prices.
- Migration helper/readiness/Admin target is 20261105_market_browse, workflow 11.
  New tool/verify-commercialization.ps1 provides ordered checks and a report;
  it has not yet been run end to end. tool/serve-preview.cjs serves only build/web
  on loopback. CI source adds native PostgreSQL checks/artifact, not hosted proof.

## Actual Verification So Far

- Full backend suite AFTER media/browse changes: 94 passed.
- flutter analyze after filter changes: no issues. Full Flutter run was still
  being polled; it reached 217 passes and one external skip without errors but
  final completion output was lost after the session closed. Do not invent final
  evidence. Earlier full run before filter additions: 217 passed, one skip.
- Focused marketplace/operations/partner import: 20 passed before two new filter
  cases; marketplace suite with filter cases: eight passed (360/1440).
- Native PostgreSQL acceptance: nine groups passed through migration 1105:
  schema/privacy; eight buyers/stock two; checkout replay; stale price/visibility;
  real Storage RLS/ownership/blocking; tied-price pagination/shop projection;
  revoke versus trip claim; competing drivers; concurrent import dedup.
  Report build/verification/postgres-acceptance.json. Native runner never loads
  dotenv or caller DATABASE_URL. Dependency embedded-postgres is dev-only.
  Media budget limits were added after this run and require rerunning acceptance.
- Web release build passed after media/browse changes. Marketplace browser
  fixtures customer/merchant/combined partner/operator at 360/1440: all eight
  passed, including file picker/media preview and existing shopping/aftersales.
  Screenshots build/verification/market-*.png. These are isolated identities and
  requests, not real Auth/provider transactions. Cloud compatibility and separate
  Admin browser suites have not been rerun in this batch.
- Windows release build is in progress at handoff; known Nuget/CMake warnings.
  Check tool session/result before claiming success or launching the app.
- Loopback backend and web preview were started; recheck health before sharing
  URLs. No current cloud readiness inspection this batch. Prior timeout remains
  prior evidence, not proof about the configured cloud today.

## Next Concrete Steps

1. Finish Windows build and inspect screenshot output; do not rebuild while its
   desktop executable holds DLLs open. Poll remaining verification as needed.
2. Current direction: finish P1 option groups, multiple configured cart lines per
   SKU and sale schedules. This touches checkout snapshots, reorder and per-line
   return/refund quantities; do not add multi-line cart while keeping ambiguous
   product-only refunds. No option/schedule implementation exists yet.
3. Keep full objective: P2 advanced checkout; P3 prepaid purchase provider
   reconciliation/real finance acceptance; P4 proof/advanced/partial delivery;
   P5 private files/return shipping/inspection/shop-driver reviews/push; P6 atomic
   funded incentives; P7 HTTPS/callbacks/hosted CI/restore/load/pilot.
4. Run ordered local acceptance after source stabilizes; record only fresh checks.
   External acceptance and cloud migration remain separate. Existing Admin UI
   offers reviewable migrations; this document grants no cloud-write permission.

## Conventions

Architecture in PROJECT_CONTEXT.md, scope in COMMERCIALIZATION_PLAN.md,
execution in EXECUTION_CHECKLIST.md and identity migration in P0_SYNC_MATRIX.md.
Never record secrets, customer data, full connections or credential output here.
