# GO-MAU / GHST Delivery Context

## Purpose And User Decisions

Flutter delivery app for customers, merchants, drivers, and administrators, moving
toward a commercial marketplace. The user wants the whole plan implemented and
tested in dependency order, a concise UI without duplicates or fake static content,
and a Windows desktop build they can inspect. Admin login is a separate page.
User correction on 2026-10-31: the frame/theme-only Marketplace redesign was
rejected. Restore the whole GHST EXPRESS customer composition: home, map,
shipping, food, orders and profile, then share that interface across buyer,
merchant and driver functions. The user explicitly selected the whole old app,
not only its login. Approved permissions reveal work sections inside that shared
shell, not separate role-specific applications.
Integrations and secrets belong in backend/Admin, not consumer settings. Existing
Google, Gmail/SMTP, and database configuration must be preserved.

The full roadmap is `gps_delivery_app/COMMERCIALIZATION_PLAN.md`. The current
priority is P0: unified identity, ownership, and data. Screen-level migration
status is tracked in `gps_delivery_app/P0_SYNC_MATRIX.md`. Current execution,
remaining requirements and acceptance are in `gps_delivery_app/EXECUTION_CHECKLIST.md`.

## Repository Map

All paths below are relative to this repository root.

| Area | Entry Points |
| --- | --- |
| App and routes | `gps_delivery_app/lib/main.dart` |
| Original shared user login presentation | `gps_delivery_app/lib/presentation/widgets/studio_user_auth_frame.dart` |
| Default canonical app and shopping | `gps_delivery_app/lib/presentation/screens/marketplace_screen.dart`, `marketplace_view.dart` |
| Original customer layout adapted to verified cloud data | `gps_delivery_app/lib/presentation/customer/ghst_user_shell.dart`, `ghst_home_screen.dart`, `ghst_shipping_screen.dart`, `ghst_ai_chat_screen.dart` |
| Customer AI chatbot & backend AI proxy | `gps_delivery_app/lib/presentation/customer/ghst_ai_chat_screen.dart`, `gps_delivery_app/backend/otp-relay/ai-assistant.mjs` |
| Purchase aftersales and financial operations | `gps_delivery_app/lib/presentation/screens/market_order_services_screen.dart` |
| Commercial vouchers, flash sales and coins | `gps_delivery_app/lib/presentation/widgets/market_commercial_sheets.dart` |
| Cloud logistics (bulk pickups, recipient trust, delivery instructions, 30-day stats, CSV order import, stop ordering) | `gps_delivery_app/database/migrations/20261108_cloud_logistics.sql`, `gps_delivery_app/lib/presentation/screens/cloud_pickup_screen.dart`, `cloud_order_import_screen.dart`, `gps_delivery_app/lib/presentation/widgets/cloud_logistics_panels.dart`, `gps_delivery_app/lib/core/gps/stop_order_optimizer.dart` |
| Public and token-shared cloud tracking | `gps_delivery_app/lib/presentation/screens/public_order_tracking_screen.dart`, `shared_tracking_screen.dart` |
| Private operations, commercial suite, expiry and share projection | `gps_delivery_app/database/migrations/20261031_market_operations.sql`, `20261107_cloud_commercial_suite.sql`, `gps_delivery_app/backend/otp-relay/market-operations.mjs` |
| Legacy consumer and admin archives | `gps_delivery_app/lib/presentation/screens/architecture_dashboard_screen.dart`, `legacy_admin_portal_screen.dart` |
| Cloud Admin operator portal | `gps_delivery_app/lib/presentation/screens/admin_portal_screen.dart` |
| Canonical cloud UI | `gps_delivery_app/lib/presentation/screens/cloud_orders_screen.dart` |
| Private cloud order details/history | `gps_delivery_app/lib/presentation/screens/cloud_order_details_screen.dart` |
| Verified cloud session | `gps_delivery_app/lib/core/integrations/cloud_account_session.dart` |
| Cloud transport and command IDs | `gps_delivery_app/lib/core/integrations/cloud_orders_service.dart` |
| Scoped cloud list reads | `gps_delivery_app/lib/data/repositories/cloud_orders_repository.dart` |
| Address book | `gps_delivery_app/lib/presentation/screens/cloud_address_book_screen.dart` |
| Legacy state and offline queue | `gps_delivery_app/lib/data/datasources/local/` |
| Realtime, role checks and APIs | `gps_delivery_app/lib/core/integrations/` |
| Express backend | `gps_delivery_app/backend/otp-relay/server.mjs` |
| Canonical SQL / RLS / RPC | `gps_delivery_app/database/migrations/` |
| Cloud contracts and setup | `gps_delivery_app/backend/otp-relay/CLOUD_ORDERS.md`, `COMMERCE.md`, `MARKETPLACE.md`, `INTEGRATIONS.md` |

## Architecture Facts

- Default consumer login uses Supabase Auth with the original GHST/Studio frame
  shared with the old login. All consumer/merchant/driver functions use the same
  GHST EXPRESS user shell and original AppTheme.lightTheme. Desktop restores
  the grouped original customer sidebar/white header; mobile restores its dark
  header and original five tabs: Trang chu, Giao hang, An uong, Don hang, Ho so.
  Home restores the destination strip, service grid, map and recent-order/discovery
  composition using cloud requests and scoped leases. The map only uses cloud
  order endpoints/saved coordinates and physical device GPS, with no legacy
  route/fleet fallback. Merchant workspace/orders and shipping/driver work change
  shell content in place. Orders switches between shipping and purchases;
  shipping embeds CloudOrderForm and returns to orders after verified creation.
  Unsupported cloud services stay disabled without made-up fares. Local rewards/
  lottery balances are not imported into this cloud home. `/cloud` opens this same
  shell at shipping orders, including after sign-in; Admin remains separate.
  Presentation sharing never binds a
  cloud identity to the SQLite password/OTP handlers. Old SQLite screens remain
  at `/legacy`, without a consumer nav
  link or automatic data fallback. They are not migrated or deleted. A Gmail
  App Password is neither a Google OAuth Client ID nor Supabase Auth setup.
- Supabase Google availability comes from that project's public Auth settings.
  Google was enabled on the hosted project on 2026-10-31 using the saved backend
  credentials and authorized Management API access. Management read-back and
  public settings verified Google true/email true; real account OAuth and
  Google Console callback/consent acceptance still require end-to-end checking.
  A subsequent real sign-in screenshot reported redirect_uri_mismatch. After
  the user updated configuration, a fresh public OAuth probe on 2026-10-31
  reached Google's /v3/signin/identifier with HTTP 200 and no mismatch error.
  On 2026-10-31, real Windows desktop Google OAuth completed the browser
  handshake and delivered a PKCE code to `http://127.0.0.1:8766/auth/callback`.
  Desktop callback HTML, Win32 foreground focus (`ghst/window`), focus-loss
  lifecycle handling (`AppLifecycleState.inactive`), and first-time profile
  onboarding inside `StudioUserAuthFrame` were updated and rebuilt. One-time
  profile phone completion and live multi-device session checks remain to verify.
  The hosted /auth/v1/callback belongs on the matching Google Web
  client; Supabase's app redirect allow list does not configure Google.
  The setup-google-cloud backend helper preserves other Auth configuration and
  adds the local web/desktop redirects. Management credentials stay out of app.
  Native Google uses PKCE with callback `http://127.0.0.1:8766/auth/callback`
  across Windows desktop and Android (`OAuthKeepAliveService` `shortService`
  prevents Android's Cached-Apps Freezer from freezing the `:8766` loopback
  listener during external Chrome sign-in, parameterless `/auth/callback`
  reloads and `/auth/done` history replacement prevent stale-tab collisions, and
  `intent://auth/return#Intent;scheme=com.giaohanggps.gpsdelivery;...` returns
  Chrome directly to `MainActivity` in `singleTop` mode with
  `flutter_deeplinking_enabled=false`; iOS declares
  `com.giaohanggps.gpsdelivery://auth/callback`, also included in
  `setup-google-cloud.mjs`). Verified hands-free end-to-end on Android `Pixel_10_Pro`
  on 2026-11-02.
  Legacy Google/Gmail settings remain intact. When `SMTP_*` is configured in the
  backend, `setup-google-cloud.mjs` (`./setup-google-cloud.ps1 -Apply`) also syncs
  Supabase Auth Custom SMTP (`smtp.gmail.com`) and 6-digit OTP templates
  (`mailer_otp_length: 6`, `{{ .Token }}` in recovery/confirmation HTML) — applied
  and verified live (`POST /auth/v1/recover` -> `200 OK` + `auth.one_time_tokens`
  `recovery_token`) on 2026-11-02; Google OAuth URLs pass `prompt=select_account`
  so browsers always show the account chooser. See MARKETPLACE.md before rollout.
- Canonical cloud business data uses `delivery_cloud_*`, authenticated backend
  routes, fixed RPCs, and server-side ownership/pricing/state checks. Do not
  expose caller-selected tables/RPCs or move service-role keys into the app.
- `CloudAccountSession` verifies profile/operator rights and rejects stale
  responses. The cloud order screen revalidates when returning to foreground.
- `GpsDeliveryApp` owns one shared cloud session for the main shell, `/cloud`, `/admin`, and `/cloud-admin` (legacy SQLite admin remains archived separately at `/legacy-admin`).
  `AdminPortalScreen` (`/admin`) is unified on Cloud Operator (`CloudAccountSession` + `isOperator`) with standalone Admin Cloud login, operator analytics (`admin_analytics`), shop/account moderation, voucher/flash-sale management, job runner, and integration readiness.
  `CloudProfileForm` edits only supported profile fields. `CloudSessionBoundary`
  and `CloudSessionLease` guard private child pages/dialogs and discard old
  permissions, including nested confirmations, after invalidation. The default
  shell uses these gates; old local history remains separate. Supabase streams replay
  the latest event; distinguish a replay of the opening Session from a new login.
- `CloudOrdersRepository` keeps immutable in-memory data scoped to project,
  Auth ID, and permission revision. It clears on invalidation, rejects late
  responses, and owns list switching and timestamp-plus-ID pagination.
- Offline queue v9 captures project/Auth/local ownership before sending. Old
  unbound commands are retained rather than assigned to the next login. Keep
  persisted command/draft key compatibility so retries do not duplicate orders.
- Cloud address book, shipping quotes/orders/transitions, and payOS/GHN gateways
  exist. `CloudOrderForm` selects pickup, dropoff, and intermediate stops directly
  by tapping the embedded interactive map (`/delivery/reverse`) or searching addresses
  (`/delivery/places`), with manual latitude/longitude text fields removed; backend
  `trackasia` (`TRACKASIA_ENABLED`, `TRACKASIA_API_KEY`) and `google_maps`
  (`GOOGLE_MAPS_ENABLED`, `GOOGLE_MAPS_API_KEY`) are managed server-side proxies covering
  `/places`, `/reverse`, `/route`, and `/matrix` so Photon and OSRM can both be disabled
  when running on TrackAsia or Google Maps Platform. Cloud shipping supports all five service modes (`standard`, `express`,
  `saving`, `same_day_2h`, `truck`), volumetric weight (`L*W*H/5000`), multi-stop
  waypoints (`extra_stops`, `+5,000 VND/stop`), round-trip (`+60%`), cargo insurance
  (`declared_value`, `0.5%` clamped `2,000..150,000 VND` up to `30M`), Green Fund
  (`+1,000 VND`), EV CO2 (`48 g/km`), scheduled pickup (`scheduled_at`), recipient
  OTP (`delivery_cloud_order_secrets` + `delivery_cloud_order_otp`), mandatory
  POD/OTP gates on `delivery_cloud_transition('deliver')`, and server-side GPS
  jump/speed validation (`<= 120 km/h`, `<= 30m` at `dt <= 0`).
  `delivery_market_*` tables/RPCs implement catalog, shop cover (`banner_url`),
  service-area radius (`service_radius_km`), shop staff delegation
  (`delivery_market_shop_staff`: `manager` vs `staff`), multi-SKU variants
  (`delivery_market_variants`), parcel dimensions (`length_cm`, `width_cm`,
  `height_cm`), stock audit, cart, expiring quote, and atomic multi-shop COD or
  prepaid checkout (`payment_method IN ('cod','prepaid')`).
  Checkout supports `buyer_note`, `service_type`, `scheduled_at`, `voucher_code`,
  `use_coins`, `prefer_ev`, `require_pod`, and `require_otp`, plus purchase
  `payOS` payment intents (`/delivery/cloud/purchases/:id/payment*`) and webhook/
  refresh double-entry capture (`delivery_market_record_prepaid_capture` with
  `promo_expense` balancing). Shop ready creates linked internal shipping orders
  or multi-parcel split shipments (`delivery_market_shipments` +
  `order_shipment_split`); shipping cancellation releases inventory atomically.
  Order chat supports participant-bound text and private evidence attachments;
  notifications contain no message/address and support optional FCM push delivery.
  Bounded option groups and SKU variants derive server prices; normalized selections
  identify separate cart lines. Checkout snapshots retain variant/option names and
  prices; reorder/returns/refunds match each line (legacy snapshots fall back to
  product ID). Shop/product schedules use Asia/Ho_Chi_Minh; cart and checkout
  enforce server opening times. The merchant editor manages variants, parcel
  dimensions, cover/service radius, staff, options, galleries, preparation time
  and schedule slots. Product uploads decode/re-encode to WebP, remove metadata
  and use scoped Supabase Storage inserts; private chat/return/finance attachments
  use the RLS-locked `'delivery-private-evidence'` bucket (`delivery_market_attachments`).
  Target migration is `20261108_cloud_logistics`, workflow 14. Isolated tests
  do not certify deployed transactions.
  Quotes optionally bind the client's displayed cart/address versions and reject
  stale data; current Flutter sends both available versions. Confirmation renders
  authoritative snapshot items/options/address. Conflicts refresh cart/details;
  failed reads remain errors rather than successful empty states. Notifications
  open their referenced order or conversation; returning from aftersales refreshes
  the order list. Current-lease access failures clear private data and require
  revalidation; old revoked leases cannot invalidate a newer verified session.
  Catalog has server filters, keyset sorting and a scoped shop page with shop
  follows (`delivery_market_shop_follows`).
- All active cloud accounts can buy. Profile schema 3 has independently approved
  merchant/driver memberships; operator remains separate, and approved shop staff
  (`isStaffOfShop` / `isManagerOfShop`) can operate delegated shops without
  impersonating owners. Leases/cache revisions include approved roles and staff
  assignments. Revoking a partner cannot strand active fulfillment.
  The operations and commercial suite migrations add manual COD collection,
  prepaid purchase capture, partial item-return refunds, shop payouts with
  independent operator approval/evidence, immutable balanced journals, bounded
  returns/disputes with reverse return shipments and `restock`/`writeoff`
  inventory disposition, verified product/shop/driver reviews
  (`delivery_partner_reviews`) with reply and moderation reports
  (`delivery_market_review_reports`), budgeted vouchers
  (`delivery_market_vouchers`, `delivery_market_voucher_usages`), server-window
  flash sales (`delivery_market_flash_sales`, `delivery_market_flash_claims`),
  and server coin wallets/ledgers (`delivery_market_coin_wallets`,
  `delivery_market_coin_ledger`: 20% redeem cap, 1% settled earn, cancel/refund
  reversals). Delivery never marks COD money collected automatically.
- Explicit legacy address import verifies the local account password on-device,
  previews only its addresses, reports drafts for manual recreation and requires
  destination confirmation. Server rejects owner/money fields and commits with
  account-scoped source hashes. Passwords/orders/money are never imported.
- `terms_version` separates product commercial changes from stock allocation;
  checkout still locks inventory and rejects changed prices/visibility.
  `npm run test:postgres` provisions a disposable loopback PostgreSQL cluster;
  it never loads saved cloud credentials. CI includes this acceptance command.
- Pending COD/prepaid allocations have a 15-minute acceptance/payment deadline
  and durable expiry jobs (`delivery_market_run_jobs`). `MARKET_JOBS_ENABLED=true`
  is enabled in the configured local backend environment. Failed jobs retain
  SQLSTATE only; operator can retry/run bounded batches.
  Current return/review windows are seven/30 days; payout waits seven days and
  excludes open/unrefunded returns. See MARKETPLACE.md before commercial use.
- Additive cloud migrations through `20261107_cloud_commercial_suite.sql`
  (workflow 13, profile schema 3) were applied to the configured Supabase
  PostgreSQL project on 2026-10-31, and `20261108_cloud_logistics.sql`
  (workflow 14) on 2026-11-02 (`npm run migrate:cloud`).
- `delivery_cloud_logistics(action,payload)` (route `/delivery/cloud/logistics/:action`)
  owns bulk pickups (`delivery_cloud_pickups`: approved merchant, address-book
  snapshot, vehicle capacity, slot within 14 days, operator dispatch with version
  and audit), private recipient trust flags (`delivery_cloud_recipient_flags`,
  counting only the caller's own shipments), owner delivery instructions
  (`delivery_cloud_orders.delivery_instruction`, versioned with history), and
  30-day stats/service ETA derived from transition history. CSV import reuses
  quote/order creation; stop ordering uses `/delivery/matrix?full=1`.
  Nhan's merged legacy UC30-UC40 code (`1b98207`) stays SQLite-only at `/legacy`;
  its seeded marketplace orders, fixed "AI SLA" figures, placeholder share link
  and invented route/fee factors were removed.
  `MARKET_JOBS_ENABLED=true` is active on the local backend; `payOS`, `GHN`, and
  public non-loopback `PUBLIC_BASE_URL` HTTPS remain unconfigured until real
  merchant credentials and public hosting are supplied. Do not infer live
  transaction certification or commercial deployment readiness from schema
  installation, local builds, or isolated fixtures.
- Cloud order details recheck server history authorization before showing the
  immutable order-list snapshot. History is validated against order ID/version,
  and OTP completion reasons are sanitized in history records.
  Repeat shipping copies only editable inputs into a new form, uses current
  merchant choices and requires a fresh quote; it never reuses payment state,
  old command keys or prices. It is not a marketplace product reorder.
- Public tracking (`/track`, `PublicOrderTrackingScreen`) now uses Cloud lookup
  (`POST /delivery/tracking/lookup` -> `delivery_cloud_public_lookup`) by Cloud
  order UUID + 4-digit recipient phone suffix or 64-hex shipping share token
  (`delivery_cloud_shares`), without reading local `AppStateStore`. Do not re-add
  the `/track` button to the login UI unless requested.
- Canonical purchase sharing uses `/share` (`delivery_market_shares`), while
  standalone shipping orders also support revocable 256-bit tokens in
  `delivery_cloud_shares` (`delivery_cloud_share_manage`). Both store SHA-256
  hashes only and project non-PII status/timestamps, never address/phone/GPS/money.
- Supabase PostgreSQL is configured through ignored backend settings with a CA
  certificate and verified TLS. Real cloud schema checks were run in earlier
  batches, but current readiness and provider setup must be rechecked as needed.
  Local builds and fixture tests do not certify real purchases or deployment.

## Configuration And Local Operations

Check that services/processes still exist; recorded ports are not live evidence.

- Workspace on this machine: `C:/baiTap_LTDiDongDaNenTang/DoAn_PhatTrienUngDungDiDongDaNenTang`.
- Flutter: `C:/src/flutter/bin/flutter.bat`; Dart: `C:/src/flutter/bin/dart.bat`.
- Backend settings: ignored `gps_delivery_app/backend/otp-relay/.integration-config.json`,
  environment variables, and RLS-locked Cloud PostgreSQL tables
  (`public.delivery_backend_config` and `public.delivery_backend_config_audit`) for
  non-bootstrap managed settings when `DATABASE_URL` is configured (`DATABASE_URL`,
  `DATABASE_CA_CERT`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY` remain local bootstrap
  keys). Use the existing configuration loader and database helper. Never print
  their contents into handoffs or test output.
- Native saved settings: `%LOCALAPPDATA%/GHST/auth-providers.json`.
- Backend health: `http://127.0.0.1:8787/health`; API base:
  `http://127.0.0.1:8787/delivery/`.
- Web preview: `http://127.0.0.1:8080/`; Admin: `http://127.0.0.1:8080/#/admin`.
- Desktop: `gps_delivery_app/build/windows/x64/runner/Release/gps_delivery_app.exe`.
  Confirm the executable path and close its window before rebuilding to avoid
  locked DLLs; reopen with its Release directory as the working directory.
- Hidden backend/static helpers use `Start-Process -WindowStyle Hidden`.
  The visible desktop app is explicitly requested by the user.

From `gps_delivery_app/`:

```powershell
C:/src/flutter/bin/flutter.bat analyze --no-pub
C:/src/flutter/bin/flutter.bat test --no-pub
C:/src/flutter/bin/flutter.bat build windows --release --no-pub
C:/src/flutter/bin/flutter.bat build web --no-pub --no-wasm-dry-run --no-web-resources-cdn --dart-define=DELIVERY_API_BASE_URL=http://127.0.0.1:8787/delivery/
```

Backend checks run with `npm test` inside `gps_delivery_app/backend/otp-relay/`.
Run only checks proportional to the change. `tool/check-cloud-browser.cjs` and
`tool/check-admin-browser.cjs` use isolated Playwright/Edge fixtures; they do not
create production users or orders. `CHECK_ROLE` and `CHECK_WIDTH` can isolate a
case. The local Playwright module is under
`%LOCALAPPDATA%/Temp/ghst-browser-check/node_modules/playwright-core`.
Allow Flutter renderer/font assets when intercepting browser requests; blocking
all non-loopback requests can prevent the UI from loading.

## Working Tree

At the latest handoff, HEAD was `1b98207` on `main` (fast-forwarded to Nhan's
latest `origin/main` commit on 2026-11-02) with extensive staged,
unstaged, and untracked implementation. Nhan's earlier feature work has been
combined with local changes; do not reset or restore files from HEAD to resume.
Inspect the live tree and diffs. Commit/push only when requested for the current
work; do not assume an old push request covers new changes.
