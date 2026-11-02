# Commercialization Execution And Acceptance

Updated: 2026-11-01. This checklist records evidence, not release approval.
The detailed scope remains in COMMERCIALIZATION_PLAN.md.

| Order | Phase | Implemented & Cloud Schema Synced (`workflowVersion: 13`) | Operational & External Acceptance Gates |
| --- | --- | --- | --- |
| 1 | P0 | Supabase Auth + Google OAuth PKCE desktop/web, `StudioUserAuthFrame`, profile schema 3 (`delivery_cloud_memberships`), unified `/admin` Cloud Operator Portal (`AdminPortalScreen`, archive at `/legacy-admin`), explicit local address import (`delivery_cloud_imports`), account-scoped leases & offline queue v9 | Complete live one-time Google profile save & recovery email check; live two-device session/role acceptance; `/legacy` local orders/CSV/drafts/KYC remain separate & manual |
| 2 | P1 | Cloud shops/products, cover `banner_url`, `service_radius_km` geofence, shop staff delegation (`delivery_market_shop_staff`: `manager`/`staff`), multi-SKU variants (`delivery_market_variants`), parcel dimensions (`length_cm`, `width_cm`, `height_cm`), scoped WebP gallery (`delivery_market_media`), option groups, prep time, schedules, stock audit & `terms_version` (`20261103`–`20261107` live on DB) | Live multi-device cloud catalog, WebP upload & concurrent stock acceptance on deployed target |
| 3 | P2 | Server filters, keyset sorting, scoped shop page + follows (`delivery_market_shop_follows`), configured cloud cart lines (`line_id`), version-bound quotes, interactive map direct-tap (`/delivery/reverse`) + address search (`/delivery/places`) with zero manual coordinate fields in `CloudOrderForm`, all 5 Cloud shipping modes (`standard`, `express`, `saving`, `same_day_2h`, `truck`), volumetric/multi-stop/round-trip/insurance/EV/Green Fund, `buyer_note`, `scheduled_at`, & atomic multi-shop COD/prepaid checkout | Live physical two-device multi-shop checkout acceptance on deployed HTTPS target |
| 4 | P3 | Manual COD collection, prepaid multi-shop `payOS` intents (`/delivery/cloud/purchases/:id/payment*`), double-entry capture (`delivery_market_record_prepaid_capture` with `promo_expense`), line-bounded refunds, 7-day shop payout guard, dual-actor approval & immutable balanced ledger (`20261107` live on DB) | Configure real `payOS` merchant keys (`PAYOS_*`) & public HTTPS webhook; operational finance policy sign-off; live receipt/payout reconciliation |
| 5 | P4 | Shop accept/ready, single or split parcel shipments (`delivery_market_shipments` + `order_shipment_split`), recipient OTP (`delivery_cloud_order_secrets` + `delivery_cloud_order_otp`), mandatory POD/OTP gate on `deliver`, server GPS speed/jump guard (`<= 120 km/h`), active `MARKET_JOBS_ENABLED=true` worker, revocable `/share` & Cloud `/track` (`delivery_cloud_public_lookup` + `delivery_cloud_shares`) | Configure real `GHN` credentials (`GHN_*`) & HTTPS callbacks; live driver POD/OTP & split-parcel acceptance |
| 6 | P5 | Order-bound chat, private evidence bucket `'delivery-private-evidence'` (`delivery_market_attachments`: `chat`, `return`, `finance`), item returns/disputes, reverse return shipments, `restock`/`writeoff` inspection disposition, separate product/shop/driver reviews (`delivery_partner_reviews`), review reply/report (`delivery_market_review_reports`), favorites/reorder & FCM push opt-in | Configure Firebase/FCM server credentials for real-device push delivery; live dispute/return shipment acceptance |
| 7 | P6 | Server-budgeted vouchers (`delivery_market_vouchers`, `voucher_usages`), server-window flash sales (`delivery_market_flash_sales`, `flash_claims`), server coin wallet & immutable ledger (`delivery_market_coin_wallets`, `coin_ledger`: 20% cap, 1% earn, cancel/refund reversals), & operator `admin_analytics` (`20261107` live on DB) | Promotional campaign budget sign-off & live multi-user promotion redemption acceptance |
| 8 | P7 | Local/CI workflow definitions, read-only readiness inspector (`commercial_suite_schema` + `market_jobs`), IPv4-first DB connection resilience, & additive migration runner (`workflowVersion: 13`) | Public HTTPS deployment (`PUBLIC_BASE_URL`), live provider webhooks, hosted CI run, backup/restore drill, load testing, legal policies & controlled pilot |

## Verification Order

1. Additive SQL migration in isolated PostgreSQL-compatible test database.
2. Direct RPC/RLS access, blocked users, foreign ownership, forged price/state.
3. Catalog version and stock conflict, quote expiration, checkout replay/rollback.
4. Backend route authentication, validation, fixed RPC mapping and bounded reads.
5. Flutter session isolation, auth recovery, states, shopping workflow.
6. Full backend/Flutter suites and static analysis after implementation stabilizes.
7. Web and Windows builds; browser desktop/mobile; desktop launch.
8. Separate deployed-environment acceptance. Do not infer this from fixture tests.

## Current Execution

- [x] Recover current context and inspect current source without resetting changes.
- [x] Main canonical account, unified `/admin` Cloud Operator portal and `/track` Cloud public lookup (code, fixture & schema sync).
- [x] Catalog, shop cover/geofence, shop staff delegation, multi-SKU variants, parcel dimensions, stock audit and merchant editor.
- [x] Persistent cart, fresh quote, interactive map tap + address search without manual coordinate fields (`CloudOrderForm`), 5 Cloud shipping modes (`standard`, `express`, `saving`, `same_day_2h`, `truck`), multi-stop/round-trip/insurance/EV/Green Fund and atomic COD/prepaid purchase submission.
- [x] Shop accept/ready/cancel, single & split parcel shipments, mandatory POD/OTP gate (`otp_code`), GPS jump guard and order-bound chat + private evidence attachments.
- [x] Manual COD, prepaid `payOS` capture (`delivery_market_record_prepaid_capture`), partial refund/payout accounting and independent approval checks (isolated SQL/HTTP/UI fixtures).
- [x] Durable pending-order/payment expiry (`MARKET_JOBS_ENABLED=true`), rollback/retry and revocable SHA-256 `/share` & Cloud `/track` checks.
- [x] Item return limits/dispute/reverse shipment/`restock`|`writeoff` disposition, verified product/shop/driver reviews + reply/report, shop follows, favorites/reorder.
- [x] Budgeted server vouchers, time-windowed flash sales, server coin wallet/ledger (20% cap, 1% earn, reversals) and `admin_analytics` (isolated SQL/HTTP/UI fixtures).
- [x] Native PostgreSQL 17 migration/privacy (`22/22` checks), Node backend suite (`111/111` tests), Flutter analyzer (`0` issues) & test suite (`277` passed, `1` optional external skip), isolated Playwright suites (`check-cloud-browser.cjs` `6/6`, `check-full-ui-acceptance.cjs` `6/6` suites / `62` PNGs), single-host zero-mock live Supabase multi-role E2E (`build/verification/live-e2e/live-e2e-report.json`, `16` PNGs, clean DB baseline restored), Web/Windows release builds and interactive desktop launch.
- [ ] Deployed HTTPS environment, live external provider credentials (`payOS`, `GHN`, FCM), physical multi-device live acceptance over public HTTPS, backup/restore drill and controlled pilot.

No production seed data, commits, pushes or public deployments are implied by this
file. External acceptance must be recorded with its actual environment.

## Current Live Cloud Sync And Readiness

Additive cloud migration `npm run migrate:cloud` completed on `2026-10-31`
through `20261107_cloud_commercial_suite.sql` (`workflowVersion: 13`, profile
`schema_version: 3`), and `MARKET_JOBS_ENABLED=true` was enabled on the local
backend. Subsequent read-only readiness inspection at `2026-10-31T08:50:44.736Z`
verified `ok` across all 17 database, schema, worker, permission, RLS privacy,
and Supabase checks:
`database`, `cloud_schema`, `membership_schema`, `import_schema`,
`stock_terms_schema`, `market_media_schema`, `browse_schema`,
`configuration_schema`, `commercial_suite_schema`, `address_schema`,
`marketplace_schema`, `operations_schema`, `market_jobs`, `commerce_schema`,
`database_permissions`, `commerce_privacy`, and `supabase`.

Remaining external readiness blockers before commercial rollout:
- `payos`: `missing` (`PAYOS_CLIENT_ID`, `PAYOS_API_KEY`, `PAYOS_CHECKSUM_KEY`).
- `ghn`: `missing` (`GHN_TOKEN`, `GHN_SHOP_ID`, `GHN_WEBHOOK_SECRET`).
- `public_https`: `missing` (`PUBLIC_BASE_URL` is still loopback `http://127.0.0.1:8787`, unreachable by external webhooks or separate networks).

Verification summary through `2026-11-01`:
- `npm run test:postgres` (`2026-10-31`): `22/22` native PostgreSQL 17 checks passed (`0` failed).
- `npm test` (`2026-11-01`): `111/111` Node backend tests passed (`0` failed).
- `flutter analyze --no-pub` (`2026-11-01`): `No issues found!` (`0` errors, `0` warnings).
- `flutter test --no-pub` (`2026-11-01`): `277` passed, `1` optional external-service skip, `0` failed.
- `check-cloud-browser.cjs` (`2026-11-01`): `6/6` passed across `1440px` and `360px` (`0` errors).
- Zero-mock single-host live Cloud E2E (`2026-11-01`, `build/verification/live-e2e/live-e2e-report.json`): `16` live Microsoft Edge screenshots exercising `buyer`, `merchant`, `driver`, `operator` (`/#/admin`), and public `/#/track` directly against live Supabase Auth + PostgreSQL + `:8787`, with verified exact restoration of the pre-test DB baseline (`cleanBaselineRestored: true`).
- `flutter build windows --release --no-pub` and `flutter build web --no-pub --no-wasm-dry-run --no-web-resources-cdn`: both exited `0`.

## Operations Scope And Limits

The finance workflow records verified prepaid `payOS` captures (when provider
keys are configured) and independently verified manual COD / bank transfer
evidence; operator approval alone posts nothing, and an operator cannot approve
or complete their own proposal. The SQL double-entry journal (`delivery_market_journals` /
`delivery_market_ledger`) must balance on every transaction (including `promo_expense`
for server vouchers and redeemed coins) and cannot be edited. Payout excludes
open/unrefunded returns and waits seven days. Pending COD and unpaid prepaid
orders have a 15-minute deadline enforced by `delivery_market_run_jobs`
(`MARKET_JOBS_ENABLED=true`). Private chat/return/finance attachments are stored
in the RLS-locked `'delivery-private-evidence'` bucket (`delivery_market_attachments`),
never in the public product gallery bucket.

All P1–P6 Cloud application, RPC, RLS, and UI workflows are implemented and
schema-synced (`workflowVersion: 13`), while P7 external deployment, live third-party
credentials (`payOS`, `GHN`, FCM, HTTPS `PUBLIC_BASE_URL`), backup/restore drills,
and controlled pilot acceptance remain required before commercial launch.
