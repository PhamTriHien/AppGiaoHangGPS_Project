# Marketplace And Commercial Cloud Suite

This document covers the marketplace, operations, and P1–P6 commercial cloud suite
(`workflowVersion: 13`). See `gps_delivery_app/EXECUTION_CHECKLIST.md` for external
provider and deployment acceptance gates. No demo rows are inserted by migration.

## Install And Inspect

The operator-only Admin readiness/migration action includes migrations through
`20261107_cloud_commercial_suite.sql` (workflow 13).
On 2026-10-31, `npm run migrate:cloud` applied all additive migrations through
`20261107_cloud_commercial_suite.sql` to the configured cloud database (`workflowVersion: 13`),
and `MARKET_JOBS_ENABLED=true` was enabled on the local backend. Always review
and back up target environments before future migrations; reapplying them
preserves purchases and inventory history.
Backend DATABASE_URL and verified TLS settings remain in the existing backend
configuration. No database credentials are embedded in the Flutter UI.

Restart the backend to load the new routes. Inspect Admin readiness: the schema
checks verify the RPCs, protected RLS tables (11 core marketplace + 9 operations +
15 commercial suite tables), private evidence storage policies, and absence of raw
app-role access. Schema checks do not certify live provider transactions or load.

## Contract

`POST /delivery/cloud/marketplace/:action` and `POST /delivery/cloud/market-ops/:action`
require the verified Supabase user JWT. Local relay identities cannot use these
business APIs. Actions are fixed in the gateway; clients cannot select an RPC or
table. Writes execute in database transactions under `delivery_marketplace(text,jsonb)`
and `delivery_market_operations(text,jsonb)`. Raw tables and internal helpers
(including `delivery_market_record_prepaid_capture`) are inaccessible to
`anon`/`authenticated` roles.

| Area | Actions |
| --- | --- |
| Catalog & Shop | `catalog`, `workspace`, `shop_save`, `shop_moderate`, `shop_staff_save`, `shop_follow_toggle`, `product_save` |
| Buyer & Promotions | `cart`, `cart_set`, `quote`, `checkout`, `orders`, `vouchers`, `voucher_save`, `flash_sales`, `flash_sale_save`, `coins_wallet` |
| Operations & Aftersales | `order_action`, `order_shipment_split`, `overview`, `order_bundle`, `finance_propose`, `finance_decide`, `return_request`, `return_action`, `review_submit`, `review_reply`, `review_report`, `review_moderate`, `partner_review_submit`, `partner_reviews`, `favorites`, `favorite_toggle`, `reorder`, `share_create`, `share_revoke`, `jobs_run`, `admin_analytics` |
| Communication & Files | `messages`, `message_send`, `notifications`, `notification_read`, plus `/delivery/cloud/attachments*` (`delivery-private-evidence`), `/delivery/cloud/pod*`, `/delivery/cloud/purchases/:id/payment*`, `/delivery/tracking/lookup` |

All active accounts have basic buying rights. Merchant/driver memberships are
independently requested and approved in profile schema 3; operator is independent.
Shop owners can delegate `manager` (catalog + fulfillment) or `staff` (fulfillment +
chat) access in `delivery_market_shop_staff`. Operators can moderate without
creating a consumer business profile. Consumer login never maps a local email,
phone or password hash to a cloud owner. `/legacy` and `/legacy-admin` preserve
old local workflows as isolated archives without consumer nav links or fallbacks.

Shops begin pending; an operator must approve publication. Editing name/address
or coordinates requires approval again. Products represent one stock-managed SKU
each, with bounded topping/option groups, preparation time and a gallery.
Absolute stock edits require the product version and create an inventory entry.
Changing role/blocked state is always checked server-side.

Cart updates require cart version. Quotes bind the account address/version,
cart version, current shop/product versions, authoritative fees and prices, and
expire after five minutes. The quote payload accepts `address_id` and optional
integer `cart_version`/`address_version`; supplied versions must match the server
snapshot or return 409. Unknown fields and malformed versions return 400. Current
Flutter supplies displayed versions and refreshes conflicts before new consent;
older callers remain compatible. Confirmation displays snapshot items, options
and delivery address. Checkout locks shops, merchant accounts, products,
address and pricing, rebuilds the snapshot, and commits all shop orders together.
Any error rolls back all allocation. Request-key replay or reusing a consumed
quote returns the existing purchase, even after cart clearing or restart.

## Configured Catalog

The user rejected the frame-only Marketplace redesign. The user interface now
restores the GHST EXPRESS customer home composition, grouped desktop sidebar,
dark mobile header and five original home/shipping/food/orders/profile tabs.
One shared shell serves buyer, merchant and driver functions. Home reads scoped
cloud addresses/orders/catalog; shipping embeds the real quote/order form.
Unsupported cloud service modes stay disabled; legacy reward balances are not
displayed as cloud funds. Approved partner sections change that shell's content;
`/cloud` enters the same shell at shipping orders, including after login. Admin is
separate. The shared login presentation does not reuse legacy SQLite password,
QR or OTP authorization for cloud accounts. Supabase Auth remains authoritative.

`20261106_catalog_configuration.sql` adds:

- Up to six option groups, 12 distinct choices per group, minimum/maximum counts
  and integer VND surcharges. The private selection helper derives the unit price;
  caller prices and unknown/duplicate choices are rejected.
- Cart identity is `(user_id,line_id)`; normalized selections deterministically
  identify a configured line. Empty selection keeps the old product UUID.
  `cart_set` accepts `selected_options` on add, and `line_id` for quantity/removal.
  Aggregate quantity across choices cannot exceed SKU stock or 99 units; the cart
  supports 50 lines. Retired choices remain unavailable and removable.
- Immutable checkout snapshots retain line identity, option names/prices and
  preparation time. Reorder revalidates current choices. Return quantities and
  refund limits use the exact purchased line. Legacy snapshots fall back to
  product UUID.
- Shop opening/product sale schedules use bounded nonoverlapping ISO weekday
  slots `{day:1..7,open:0..1439,close:1..1440}`. Start is inclusive; end exclusive.
  Times use Asia/Ho_Chi_Minh. Empty schedule means unrestricted. Split overnight
  windows across two weekdays. Cart/quote/checkout enforce server time;
  browse/details expose availability while products remain visible outside hours.
- Product galleries contain up to eight HTTPS images. Managed uploads decode,
  remove metadata and re-encode WebP in the backend. The public product bucket
  must never store private attachments. Reservations enforce 5 MB/image,
  60 new/hour/shop, 2,000/shop, 100 MB/shop and 500 MB total. Content retries do
  not consume a second reservation.

The merchant editor provides file selection, primary-image choice, option fields
and schedule controls. Buyers select choices before adding configurable products;
cart and aftersales display purchased choices. Migration seeds no products.

COD stock is allocated immediately. With 20261031_market_operations.sql installed,
pending orders have a 15-minute acceptance deadline and a durable expiry job.
The merchant accepts and marks
ready, producing one linked internal shipment with immutable purchased prices.
Before shipment, permitted cancellation releases allocated stock once. Cancellation
through the shipping API also releases the purchase allocation atomically. Carrier
callbacks record a carrier source and do not impersonate the merchant.

Delivery success does not mark purchase money paid. Purchase payment status starts
UNPAID. The operations RPC adds an evidence-based manual COD collection, refund
and shop payout workflow; it does not invoke a payment provider or transfer money.
Existing payOS payments remain shipping fee payments, not purchase payments.

## Operations Migration And Policy

Install 20261031_market_operations.sql after the marketplace migration using the
existing operator Admin migration action. No accounts, orders or balances are
seeded. Nine additional private/RLS tables are accessible only through fixed RPCs;
the public tracking RPC exposes a separately whitelisted projection.

- Pending inventory allocation expires after 15 minutes if a shop has not accepted.
  The SQL transaction locks the order/products, returns inventory once, emits a
  system-sourced audit and notifies both participants. A failed job rolls back
  business changes, stores only its SQLSTATE, retries after a minute and stops
  after five attempts. Admin can retry failed jobs and run a bounded due batch.
- Enable MARKET_JOBS_ENABLED in Admin backend settings after installation/policy
  review. The backend checks every 15 seconds, coalesces overlapping ticks and
  stops cleanly. A persistent database job survives relay restarts; a continuously
  running backend is still required. The toggle defaults off, including for old
  configured projects. It is not silently enabled by a local test/build.
- Collection requires a delivered linked order and the exact goods plus shipping
  amount. The assigned driver or an operator proposes it with a receipt reference.
  A different cloud operator approves, then explicitly confirms actual collection
  with evidence. Ordinary buyers/merchants cannot assert that cash was collected.
- Refunds require a received item return and are limited by its purchased quantity,
  immutable unit price, remaining collected money and prior payouts/refunds. Shop
  payout waits seven days after delivery and cannot consume money owed for an open
  or unrefunded return. Every completion rechecks limits under the order lock.
- An operator cannot approve or complete their own proposal. Approval alone posts
  no money. Actual completion writes an immutable journal with deferred balance
  checks; duplicate/stale transitions cannot post it twice. Amounts are integer
  VND. There is no consumer wallet or automated provider refund/split payment.
- Buyers can request item returns within seven days, escalate a rejection, and
  review purchased products within 30 days after delivery. Merchant/operator
  receipt confirmation does not automatically refund or restock inspected goods.
  Public reviews omit buyer/order IDs; operators can hide them with an audit.
- Favorites are account scoped. Reorder reads current selling rights, availability
  and stock, updates the versioned cart atomically, and uses durable request keys.
  A reorder is a cart edit, not a purchase or a promise of the previous price.
- Tracking shares contain 256-bit random tokens, store only SHA-256 hashes, expire
  after 24 hours and can be revoked. Up to five active links per order. The public
  projection contains shop name, workflow/delivery status and timestamps only;
  no recipient details, amount, GPS, OTP or proof files. PUBLIC_APP_URL optionally
  produces an HTTPS app link at `/#/share?token=...`, while `/#/track` provides
  public Cloud shipping lookup (`delivery_cloud_public_lookup` + `delivery_cloud_shares`).
- Operator financial/dispute lists use timestamp+ID pagination. Per-order financial
  and return requests are capped at 100; active share reads are bounded. These are
  initial operational policies to review before accepting commercial transactions.

Consumer entry: order list -> Chi tiet va hau mai; account -> favorites.
Operator entry: separate cloud Admin -> Doi soat va hau mai. All private screens
and nested forms use session leases and discard late data on invalidation.

Chat is text-only, participant-bound, idempotent and limited to 20 sends/minute per
account. Notifications contain an order reference and event kind, not message
contents or recipient addresses. Reads are bounded and use keyset pagination;
messages/notifications use timestamp plus ID to preserve tied timestamps.

## Auth Setup Boundaries

The main shell uses Supabase Auth. Google visibility is read from public Supabase
Auth settings; saved native Google/Gmail settings are preserved separately.
Google through Supabase must be enabled in that project's Auth provider settings.
The native PKCE callback is `http://127.0.0.1:8766/auth/callback`; add this exact
redirect to the project's allowed redirects. Web Google returns to the site root.
No native Google client secret or provider token is used as a Supabase identity.

Password recovery uses Supabase email recovery (`verifyOTP` with `OtpType.recovery`),
not the legacy relay OTP. When saved backend `SMTP_*` settings are enabled,
`setup-google-cloud.mjs` (`./setup-google-cloud.ps1 -Apply`) synchronizes Supabase
Auth Custom SMTP (`smtp_host`, `smtp_port`, `smtp_user`, `smtp_pass`, `smtp_admin_email`)
and 6-digit OTP templates (`mailer_otp_length: 6`, `{{ .Token }}` in recovery and
confirmation templates) — applied and verified live (`POST /auth/v1/recover` -> `200 OK`)
on 2026-11-02. Editing `SMTP_*` in the relay alone still requires rerunning
`./setup-google-cloud.ps1 -Apply` (or updating Supabase Dashboard SMTP) to push changes
to Supabase Auth.

`npm run setup:google-cloud -- --check` reads public provider status and reports
whether the saved backend/native Google fields exist, without printing secrets.
`--apply` uses `SUPABASE_ACCESS_TOKEN` or a local token file specified by
`SUPABASE_ACCESS_TOKEN_FILE` (default: the native GHST settings directory plus
`supabase-management-token.txt`). This is a Supabase Management API token, not
the publishable key, service-role key or Google secret. It stays out of Flutter
and managed integration settings. Do not put it in source control or chat.
On Windows after `supabase login`, run `./setup-google-cloud.ps1` to preview,
then `./setup-google-cloud.ps1 -Apply` to apply. The wrapper reads only the
official CLI's `Supabase CLI:supabase` Windows credential and passes it to the
child process in memory, restoring the original environment afterward.
The helper reads current Auth settings, rejects a conflicting Google client,
patches only Google plus additive local/app redirects and checks the result.
It preserves the Site URL, other providers and existing redirects. Run a real
Google sign-in afterward; enabling the provider does not certify Google's Web
client type, allowed callback, consent configuration or account/profile setup.
The Google Web client's authorized callback must include the hosted project's
`https://<project-ref>.supabase.co/auth/v1/callback`.

## Commercial Suite (`20261107_cloud_commercial_suite.sql`, workflow 13)

- **Catalog & Staff**: Shops add `banner_url`, `service_radius_km`, and `delivery_market_shop_staff` (`manager` vs `staff`). Products add parcel dimensions (`length_cm`, `width_cm`, `height_cm`) and multi-SKU `delivery_market_variants` with independent SKU stock and price overrides.
- **5 Cloud Shipping Modes & Guards**: `delivery_cloud_quote` and `delivery_cloud_create` compute server fees for `standard`, `express`, `saving`, `same_day_2h`, and `truck`, including volumetric weight (`L*W*H/5000`), `extra_stops` (`+5,000 VND/stop`), `round_trip` (`+60%`), cargo insurance (`declared_value`, `0.5%` clamped `2,000..150,000 VND` up to `30M`), Green Fund (`+1,000 VND`), EV CO2 (`48 g/km`), `scheduled_at`, recipient OTP (`delivery_cloud_order_secrets` + `delivery_cloud_order_otp`), mandatory POD/OTP gate on `delivery_cloud_transition('deliver')`, and server GPS jump/speed rejection (`<= 120 km/h`, `<= 30m` at `dt <= 0`).
- **Prepaid Multi-Shop Checkout & Split Shipments**: `checkout` supports `payment_method IN ('cod','prepaid')`, `buyer_note`, `service_type`, `scheduled_at`, `voucher_code`, `use_coins`, `prefer_ev`, `require_pod`, and `require_otp`. `delivery_payment_transactions` adds `purchase_id` (with nullable `order_id`), `/delivery/cloud/purchases/:id/payment*` creates/refreshes `payOS` intents, and `delivery_market_record_prepaid_capture` posts balanced double-entry journals (including `promo_expense`) once per captured transaction. Shops can split fulfillments into multiple parcels via `delivery_market_shipments` (`order_shipment_split`).
- **Private Evidence, Return Shipments & Partner Reviews**: Private attachments (`chat`, `return`, `finance`) reserve and verify objects in the RLS-locked `'delivery-private-evidence'` Storage bucket (`delivery_market_attachments`). `return_action` supports reverse return shipment creation and inspected inventory `disposition` (`restock` vs `writeoff`). Buyers can submit separate shop and driver reviews (`delivery_partner_reviews`), merchants can reply once (`review_reply`), and participants can report abusive reviews (`delivery_market_review_reports`).
- **Vouchers, Flash Sales, Coin Ledger & Public Lookup**: Server-budgeted vouchers (`delivery_market_vouchers`, `delivery_market_voucher_usages`), time-windowed flash sales (`delivery_market_flash_sales`, `delivery_market_flash_claims`), server coin wallets/ledgers (`delivery_market_coin_wallets`, `delivery_market_coin_ledger`: 20% redeem cap, 1% settled earn, automatic cancel/refund reversals), `admin_analytics`, and public cloud shipping lookup (`POST /delivery/tracking/lookup` -> `delivery_cloud_public_lookup` + `delivery_cloud_shares`).

## Evidence And Limits

`marketplace.test.mjs`, `market-operations.test.mjs`, and `commercial-suite.test.mjs`
exercise SQL/RPC permissions, stale prices, replay, multi-shop rollback, prepaid
double-entry capture, split shipments, POD/OTP gates, vouchers/flash sales/coins,
and HTTP boundaries (`111/111` backend tests passing). `postgres-acceptance.mjs`
(`npm run test:postgres`) verifies `22/22` native PostgreSQL 17 checks including
concurrent stock/checkout/claim/import and Storage/table RLS privacy without
touching saved cloud credentials. Flutter static analysis (`0` issues) and widget/
unit suites (`277` passed, `1` optional external skip) use isolated fixtures, and
on `2026-11-01` a zero-mock single-host browser E2E run verified live `buyer`,
`merchant`, `driver`, `operator` (`/#/admin`), and `/#/track` workflows against
Supabase Auth + PostgreSQL before restoring the exact pre-test DB baseline
(`build/verification/live-e2e/live-e2e-report.json`).

Still required before commercial launch: configure real `payOS`, `GHN`, FCM and
public non-loopback `PUBLIC_BASE_URL` HTTPS credentials, run physical multi-device
Auth/checkout/provider webhook acceptance over HTTPS, execute backup/restore drills,
and complete controlled pilot sign-off.
