# payOS and GHN cloud orders

These integrations operate on real `delivery_cloud_orders` and `delivery_market_purchases`,
not local SQLite orders. They require a verified Supabase user, a backend PostgreSQL
connection and the delivery migrations. No sample orders or payment success records
are inserted by setup. Automated tests use an isolated database and mock provider
responses; they do not charge money or create real shipments.

## Setup

1. In Supabase **Connect**, obtain a direct or session-pooler PostgreSQL connection
   string for this project. Save it in Admin > API & Dich vu > Quan ly API
   backend > Trien khai backend, or in backend `.env` as `DATABASE_URL`. URL-encode
   the password and keep the connection string server-side. The public key and
   Supabase login password cannot replace the database password.
2. In Admin, open **San sang trien khai** (checklist icon), review
   the checks and select **Cap nhat schema cloud**, then confirm. The server
   requires a verified cloud operator or local loopback relay identity, an exact migration version and
   an opaque database revision from the latest check. Changing database or
   restarting the backend invalidates an older confirmation. Only one UI
   migration runs at a time; database connection edits are refused during that run.
   Cloud operators can configure DATABASE_URL and apply confirmed migrations on
   the connected backend. Alternatively run `npm ci`, then `npm run migrate:cloud`.
   The migration runner applies all additive migrations through
   `20261107_cloud_commercial_suite.sql` and reports `workflowVersion: 13` without
   deleting existing data. Profile `schema_version: 3` includes independently
   approved merchant/driver memberships. Shipping (`order_id`) and multi-shop
   purchase (`purchase_id`) payment workflows remain distinct.
3. Restart the backend after changing `.env`; Admin saves take effect without
   restart. Remote PostgreSQL uses verified TLS.
   A missing database or migration returns an unavailable error, never a local
   substitute or simulated successful transaction.
4. Open `http://127.0.0.1:8080/#/admin`, then **API & Dich vu**. Provider keys,
   enable flags and redirects are saved in **Quan ly API backend**. Cloud operator
   rights must already exist in `delivery_api_profiles`; a local admin account
   alone does not authorize cloud payment or carrier actions.

### payOS

Create a real payOS payment channel and enter its `PAYOS_CLIENT_ID`,
`PAYOS_API_KEY` and `PAYOS_CHECKSUM_KEY` in Admin. Set `PAYOS_RETURN_URL` and
`PAYOS_CANCEL_URL` to the actual app URLs, then enable `PAYOS_ENABLED`.
Local development permits http://127.0.0.1 or localhost redirects; public
redirects require HTTPS. The default local redirect opens `/#/cloud`.

Deploy the backend behind a public HTTPS endpoint and register its callback in
payOS: `https://YOUR_BACKEND/delivery/payments/webhook`. payOS cannot call
localhost. The callback validates the official SDK's signature before writing.
The server also verifies signed provider responses during creation, cancellation
and refresh. Merely visiting the return URL never marks an order or purchase paid.

- **Standalone shipping orders**: Open an own cloud order, select **Thanh toan cuoc**
  and create/open its payOS link. Eligibility: positive shipping fee, sender pays,
  searching, no internal driver and no carrier reservation. COD remains a separate
  collection amount.
- **Prepaid Marketplace purchases**: Checkout with `payment_method = 'prepaid'`
  creates a pending purchase (`UNPAID`) and supports `/delivery/cloud/purchases/:id/payment*`.
  Upon verified capture, `delivery_market_record_prepaid_capture` posts an
  immutable balanced double-entry journal (including any `promo_expense` for
  vouchers/coins) once per transaction.

The server reads amounts from PostgreSQL and ignores caller-supplied prices.
Links expire after 15 minutes at the provider; `delivery_market_run_jobs`
(`MARKET_JOBS_ENABLED=true`) also expires stale pending prepaid purchases.

Receipts are durable and deduplicated by provider reference. Only an exact VND
receipt total matching the saved order/purchase payable amount can produce PAID.
Partial, overpaid, late, canceled-order or otherwise inconsistent transfers
require REVIEW. Refunds and automatic release from REVIEW are not automated via
provider APIs; never change REVIEW to PAID without checking actual bank receipts.

An uncertain create retries with the same saved `provider_order_code`. New checkout
creation is blocked while CREATING/PENDING/REVIEW exists. Disabling the provider
blocks new checkouts but continues to accept verified receipts and reconcile/cancel
existing links while its keys remain configured.

### GHN

Obtain a GHN token and Shop ID for the chosen environment. Set `GHN_TOKEN`,
`GHN_SHOP_ID`, a separate random `GHN_WEBHOOK_SECRET`, and `GHN_BASE_URL`:

- Staging: `https://dev-online-gateway.ghn.vn/shiip/public-api/`
- Production: `https://online-gateway.ghn.vn/shiip/public-api/`

Enable GHN only after choosing the intended environment. In GHN callback settings,
register `https://YOUR_BACKEND/delivery/webhooks/ghn` with the custom header
`X-GHN-Webhook-Secret` equal to your backend secret. Staging and production
callbacks are separate. A localhost address is unreachable from GHN.

In **Don hang cloud**, an operator opens **GHN**, supplies the two-level
province/ward names, package dimensions in cm and inspection policy, then previews
the actual provider fee. Creating the shipment requires explicit confirmation.
The quote is valid 10 minutes and binds the order version, Shop ID and environment.
Recipient, sender contact, addresses, weight and COD come from the saved cloud
order. GHN charges the shop (`payment_type_id: 1`); that carrier cost is displayed
separately and does not silently replace the customer's agreed shipping fee.

Reservation durably assigns fulfillment to GHN and hides internal driver actions.
The stable `client_order_code` and payload are reused after uncertain create results.
Callbacks authenticate the custom header and then fetch authoritative GHN detail;
callback status/COD fields alone cannot settle an order. Duplicate and stale
events do not regress status or duplicate history.

## Endpoints

All paths below begin with `/delivery`. Payment/shipment routes require a real
Supabase JWT; public callbacks use their own signature/secret authentication.

| Method/path | Purpose |
| --- | --- |
| GET/POST `/cloud/orders/:id/payment` | Saved shipping payment intent or link creation/retry |
| POST `/cloud/orders/:id/payment/refresh` | Signed provider reconciliation for shipping fee |
| POST `/cloud/orders/:id/payment/cancel` | Verified shipping link cancellation |
| GET/POST `/cloud/purchases/:id/payment` | Saved Marketplace purchase payment intent or link creation/retry |
| POST `/cloud/purchases/:id/payment/refresh` | Signed provider reconciliation + double-entry capture |
| POST `/cloud/purchases/:id/payment/cancel` | Verified purchase link cancellation |
| POST `/payments/webhook` | Signed payment receipt (shipping or purchase) |
| GET `/cloud/orders/:id/shipment` | Saved carrier status |
| POST `/cloud/orders/:id/shipment/preview` | Operator fee preview |
| POST `/cloud/orders/:id/shipment` | Operator-confirmed durable reservation/create |
| POST `/cloud/orders/:id/shipment/refresh` | Participant-authorized status refresh |
| POST `/cloud/orders/:id/shipment/cancel` | Operator cancellation request |
| POST `/webhooks/ghn` | Header-authenticated authoritative refresh |
| GET `/admin/integrations/usage` | Operator API HTTP counters |
| GET `/admin/integrations/readiness` | Read-only database, schema (`workflowVersion: 13`), worker, privacy, permissions and provider prerequisites |
| POST `/admin/integrations/migrate-cloud` | Confirmed schema migrations |

Commerce tables and identity sequence deny `anon`/`authenticated` Data API access.
Only the backend database connection writes receipts, quotes and shipments.

## Monitoring and validation

**Hoat dong API** shows observed outbound HTTP requests, HTTP successes/errors,
429 responses and latency since backend startup without storing keys, contacts
or receipt data.

**San sang trien khai** distinguishes a missing connection from an unreachable
database and a missing migration. Even all-green schema/worker prerequisites
leave real provider transaction acceptance unverified until `PAYOS_*`, `GHN_*`
and public HTTPS `PUBLIC_BASE_URL` are configured.

Run `npm test` (`111/111`), `npm run test:postgres` (`22/22`), `flutter analyze --no-pub`
and `flutter test --no-pub` (`277` passed).

References: [payOS Node SDK](https://payos.vn/docs/sdks/back-end/node/),
[payOS webhook](https://payos.vn/docs/du-lieu-tra-ve/webhook/),
[GHN create](https://developer.ghn.vn/vi/docs/order/create),
[GHN preview](https://developer.ghn.vn/vi/docs/order/preview),
[GHN details](https://developer.ghn.vn/vi/docs/order/info),
[GHN cancel](https://developer.ghn.vn/vi/docs/order/cancel),
[GHN callback](https://developer.ghn.vn/en/docs/webhook/callback-order-status).
