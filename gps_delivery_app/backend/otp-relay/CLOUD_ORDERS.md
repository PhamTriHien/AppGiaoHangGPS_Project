# Cloud accounts and orders

This adds an authoritative cloud workflow alongside existing device-local data.
Local accounts, local order IDs and local RBAC do not grant a Supabase identity or
cloud privileges. Existing local orders are not automatically uploaded.

## Install on the existing Supabase project

The public/publishable key cannot execute migrations. Use either:

1. In Supabase SQL Editor, run `database/migrations/20261028_cloud_orders.sql`
   (after `20261027_delivery_integrations.sql`) and subsequent additive migrations
   through `20261115_cross_role_linkage_complete.sql`. Do not install the legacy
   `database/schema.sql` as a prerequisite.
2. Put the real PostgreSQL connection string from Supabase **Connect** in backend
   `.env` as `DATABASE_URL`, then run `npm run migrate:cloud`. Use the direct or
   session-pooler connection appropriate for the server network. URL-encode the
   database password. The runner uses verified TLS for remote databases, does
   not log credentials and installs all additive migrations idempotently.

`npm run check:cloud` checks schema discovery with the public key only. It does
not sign in, create users, send email or write orders. A detected schema is not
proof that the authenticated workflow has been exercised on that project.

The migration is additive and can be reapplied. It creates `delivery_cloud_*`
tables, RLS, constrained transactions and event guards. No real/sample accounts
or orders are inserted. Its default tariff is 25,000 VND for the first 2 km,
5,000 per additional started km, 10,000 express surcharge, and 3,000 per started
kg over 5 kg. Admin can change these values in **Bang gia cloud**.

### Workflow version 21 & profile schema 3

`npm run migrate:cloud` applies all additive migrations through
`database/migrations/20261115_cross_role_linkage_complete.sql` (`workflowVersion: 21`),
preserving accounts, tariffs, existing orders, history and login sessions.
`GET /delivery/cloud/profile` reports `schema_version: 3` with independently
approved `merchant` and `driver` memberships (`delivery_cloud_memberships`,
requiring verified `birth_date` and 12-digit `citizen_id` before requesting,
approving or granting partner roles), `coin_balance`, `unread_notifications`,
`ui_preferences` (`theme_mode`, `preferred_role`), and owner-only `shipping_draft`.
The backend refuses role, tariff and state mutations on older schemas (`< 2`)
instead of allowing a return to be incorrectly recorded as a successful delivery.
The public key and an operator login cannot execute SQL migrations; the SQL
Editor or an authorized PostgreSQL `DATABASE_URL` is required.

## Accounts and approval

### Cloud address book

Apply `database/migrations/20261029_cloud_addresses.sql` after the cloud-order
migration, or run `npm run migrate:cloud`. It adds no demo addresses and does not
upload addresses from local accounts. The address icon in cloud orders opens
the address book; the order form offers saved pickup/dropoff selection. A saved
dropoff also fills recipient name and phone. Coordinates are range-validated,
not proof of correspondence to a physical address.

`GET /delivery/cloud/addresses` lists only the current active account's addresses.
`POST /delivery/cloud/addresses/:id` accepts `{details}` for creation with a stable
client UUID, `{details,version}` for edits, or `{delete:true,version}` for deletion.
Details contain `label`, `recipient_name`, `recipient_phone`, `full_address`,
numeric `latitude`/`longitude` and boolean `is_default`; owner fields are rejected.
There are at most 25 entries per account. RPC locks the account to serialize
default-address edits. Direct table writes are denied; RLS also excludes blocked
accounts. Other users, including operators, cannot access someone else's book
through this API. Editing an older version returns 409; reload before editing
again. Deleting the default promotes another entry if one remains.

An address edit never changes an existing order. Selecting an address invalidates
the current quote; fee validation and ownership checks still occur during order
creation. Authentication changes clear the address editor/list and discard stale
responses. Legacy SQLite profile/address screens remain isolated at `/legacy`.

### Sign-in and role approval

The default consumer shell (`/`, `/#/cloud`) and cloud order screens use
`CloudAccountSession` for verified account and operator state; legacy SQLite
screens remain isolated archives at `/legacy` and `/legacy-admin`. Restoring a
Supabase session triggers profile verification; SQLite accounts and pending role
requests never grant cloud permissions. Auth changes invalidate the previous
identity, including signing in again as the same user. A failed profile
verification removes cached privileges and loaded order/account lists. Refreshing
the profile also invalidates those lists when role, blocked status or operator
access changes. This is client isolation in addition to server/RLS authorization,
not a replacement for it.

- User entry: `http://127.0.0.1:8080/` (shared GHST EXPRESS shell) or
  `http://127.0.0.1:8080/#/cloud` (opens directly at shipping orders).
  Email/password sign-in, Google OAuth PKCE and registration use the configured
  Supabase Auth project. Confirm email when required by that project's Auth policy.
- Admin entry: `http://127.0.0.1:8080/#/admin` (`AdminPortalScreen`, unified on
  Cloud Operator) or `http://127.0.0.1:8080/#/cloud-admin` (legacy SQLite admin
  is archived separately at `/#/legacy-admin`). A verified Supabase operator is
  required for admin actions.
- Complete the cloud profile with name and phone. New profiles always start as
  customer; driver/merchant requests stay pending until an operator approves.
- Bootstrap the first operator in SQL Editor using an actual Auth user UUID:

```sql
insert into public.delivery_api_profiles(user_id,role)
values ('REPLACE_WITH_REAL_AUTH_USER_UUID'::uuid,'operator')
on conflict(user_id) do update set role='operator';
```

In Admin **Tài khoản** (`/#/admin` -> `AdminAccountsPanel`), verified Cloud
Operators inspect the unified Auth + profile directory (`delivery_cloud_admin_accounts`),
including Auth providers (`google` / `email`), incomplete Auth sign-ups, profile
edits (`update_profile`), direct partner grants (`grant`) or pending request
approvals/rejections/revocations (`merchant` / `driver`), business lock/unlock
(`set_blocked`, with self-lock guard), and Operator privilege grant/revoke
(`set_operator`, requiring audit reason and self-demote guard). Every mutation
records an immutable entry in `delivery_cloud_admin_audit`. Revoking a partner
membership cannot strand an unfinished active trip.

## Complete workflow

1. Customer creates an order, optionally selecting an approved merchant. Approved
   merchants can also create orders for their own pickup operation.
2. Select pickup `[A]`, dropoff `[B]` and optional intermediate stops (`#1..#5`)
   directly on the embedded interactive map (`/delivery/reverse`), via device GPS,
   via saved Cloud Address Book entries, or via live address search (`/delivery/places`)
   — manual latitude/longitude text fields are removed from `CloudOrderForm`. Enter
   recipient, package, weight/dimensions, service mode (`standard`, `express`,
   `saving`, `same_day_2h`, `truck`), optional COD, insurance, round-trip, EV/Green
   Fund and POD/OTP gates.
3. Review the backend quote and confirm. Fees are computed in PostgreSQL; client
   price, owner, driver, payment status and role are never trusted.
4. If a merchant is attached, they confirm ready. Approved drivers then see the
   available queue, without tracking code, recipient contact or exact address
   before claiming.
5. Driver claims, arrives at pickup, collects, then delivers (uploading POD photo
   and/or entering the recipient's 6-digit OTP when required); failure, retry and
   return steps are supported. Customer/merchant/operator can cancel before pickup
   with a reason. Operator can inspect orders and history.
6. Failure and initiating a return each require a reason. A failed trip can be
   retried or returned. Completing a return records `returned`, never `delivered`,
   and releases the driver to claim another trip. This does not settle payment
   or COD. Reasons remain visible in the authorized order history, while verified
   6-digit OTPs are stripped from stored history reasons.

Quotes include an authoritative breakdown of base, additional distance, excess
weight, service mode, extra stops, round-trip, cargo insurance and Green Fund fees.
Tariff values must be bounded nonnegative integers in both the gateway and
PostgreSQL, including direct Data API calls. Order search and status filters apply
to loaded pages; the displayed matched/loaded count keeps that scope explicit.

Each creation/transition has an account-scoped persistent command key. Repeating
the same request returns the committed result; a reused key with a different
payload fails. A row lock protects competing claims; a driver lock prevents the
same driver claiming two active orders. Optimistic versions reject stale writes.
The tariff version and expected fee must still match at order confirmation.
The client remembers only command IDs/hashes and a draft ID, not the form's PII.

Orders automatically provision their live room/membership and publish committed
status notifications. Direct legacy status events cannot change the authoritative
order state. The list refreshes every 20 seconds while visible.

## API

All routes below are under `/delivery/cloud` (plus public lookup at
`/delivery/tracking/lookup`), require a real user JWT for authenticated actions,
and reject the private local relay identity. PostgreSQL functions repeat
authorization checks even when called through Supabase Data API directly.

| Method/path | Action |
| --- | --- |
| GET/POST `/profile` | Read/save own profile (`full_name`, `phone`, optional `birth_date`, optional 12-digit `citizen_id`), view/request independent memberships (`schema_version: 3`) |
| POST `/preferences/:action` | Sync `ui_preferences` (`get`, `save_ui`) and owner-scoped `shipping_draft` (`save_draft`, `clear_draft`) across devices |
| POST `/ai-history/:action` | Sync multi-turn AI Assistant conversation history (`list`, `clear`) in `delivery_ai_chat_messages` |
| POST `/order-live/:action` | Authorized shipping trip telemetry, Customer ↔ Driver ↔ Merchant (`owner`/`manager`/`staff`) chat, multi-stop/round-trip checkpoints & reviews (`snapshot`, `push_gps`, `send_chat`, `mark_checkpoint`, `driver_reviews`) |
| POST `/merchant/:action` | Dedicated Merchant & delegated Shop Staff suite (`dashboard`, `shop_quick_pause`, `product_quick_update`, `stock_ledger`, `promotions`, `orders_list`, `aftersales_inbox`) via `delivery_merchant_suite` |
| POST `/driver-finance/:action` | Driver wallet (`85%` net trip earnings / `15%` platform commission), COD remittance & payout settlements (`summary`, `remit_cod`, `request_payout`, `admin_list`, `admin_decide`) via `delivery_driver_finance` |
| POST `/notifications/:action` | Unified notification inbox & preferences (`list`, `unread_count`, `mark_read`, `mark_all_read`, `save_preferences`) |
| POST `/memberships/:role`, POST `/accounts/:id/memberships/:role` | Request or operator-decide (`approve`, `reject`, `revoke`, `grant`) `merchant` / `driver` membership (requires KYC `birth_date` + `citizen_id`) |
| GET `/merchants` | Approved merchant IDs/names only |
| GET `/accounts`, POST `/accounts/:id` | Legacy operator business profile list and blocking |
| POST `/admin-accounts/:action` | Operator identity governance (`list`, `detail`, `update_profile`, `set_blocked`, `set_operator`) |
| GET/POST `/pricing`, GET `/audit` | Operator tariff and audit |
| POST `/quote` | Server-computed estimate (5 service modes, volumetric weight, extra stops, round-trip, insurance, EV/Green Fund, optional `use_coins` up to 20% discount) |
| GET `/orders?queue=true` | Redacted queue for approved drivers (anti-self-dealing excludes own/delegated-shop orders) |
| GET `/orders` | Up to 50 accessible orders (including delegated shop staff), optional `before` timestamp + `before_id` cursor |
| GET `/orders/:id` | Single authorized order lookup with live enrichment (`delivery_cloud_get`) |
| POST `/orders` | Versioned price-confirmed (`expected_fee == payable_fee`), idempotent creation with atomic `use_coins` deduction |
| POST `/orders/:id/transition` | Transactional action with expected version (`ready`, `claim`, `arrive`, `pickup`, `deliver`, `fail`, `retry`, `return`, `complete_return`, `collect_cash`, `release`, `reassign`, `cancel`); enforces POD photo & 6-digit OTP on `deliver` |
| GET `/orders/:id/history` | Authorized immutable order history (OTP codes sanitized from reasons) |
| GET `/orders/:id/otp` | Authorized 6-digit `otp_code` read for sender, merchant, delegated shop staff or operator (`delivery_cloud_order_otp`) |
| GET/POST `/orders/:id/shares`, POST `/orders/:id/shares/:shareId/revoke` | Revocable 256-bit SHA-256 shipping tracking shares (`delivery_cloud_shares`) |
| POST `/pod`, POST `/pod/sign` | Private POD photo upload and short-lived signed read URL |
| POST `/logistics/:action` | Fixed `delivery_cloud_logistics` actions: `pickup_list`, `pickup_create` (approved merchant or delegated shop staff, warehouse address or `shop_id`, vehicle capacity, slot within 14 days, idempotent `request_key`), `pickup_assign` (operator), `pickup_transition` (`claim`, `arrive`, `pickup`, `complete`, `cancel`), `recipient_trust` / `recipient_flag`, `instruction_set`, `stats`, `service_eta` |
| POST `/delivery/tracking/lookup` | Public non-PII status lookup by Cloud order UUID + 4-digit phone suffix or 64-hex share token |

## Limits

Flutter order lists use `CloudOrdersRepository`, bound to the verified
`CloudAccountSession` and its project, Auth user and permission revision. Switching
identity or list view invalidates pending reads and pagination. The cache is
in memory only and never falls back to legacy SQLite orders. Pagination uses
the server timestamp and ID cursor; transient next-page errors retain already
loaded rows for retry, while authorization errors discard them.

Cloud pricing uses great-circle leg distances multiplied by 1.3 (including any
`extra_stops` waypoints), explicitly shown as an estimate; it does not bill from
OSRM road length or live traffic. Supported modes are `standard`, `express`,
`saving`, `same_day_2h` and `truck`, with volumetric weight (`L*W*H/5000`), up to
5 extra stops (`+5,000 VND/stop`), round-trip (`+60%`), declared-value insurance
(`0.5%` clamped `2,000..150,000 VND` up to `30M`), Green Fund (`+1,000 VND`) and
integer COD up to 20 million VND.

Sender/recipient cash fees remain available. Eligible sender-paid orders and
prepaid Marketplace purchases support `payOS` intents, and operator-managed GHN
fulfillment is documented in [COMMERCE.md](COMMERCE.md). Delivery does not itself
mark a payment settled, transfer a wallet balance, settle COD or invoke MoMo/VNPAY.
When `require_pod` or `require_otp` is enabled on an order, `deliver` enforces a
verified POD object path and/or exact 6-digit OTP match in PostgreSQL while
sanitizing the OTP out of `delivery_cloud_order_events.reason`. Document/KYC
review remains an operator process.

The localhost backend must be deployed over HTTPS before separate physical
devices or external provider webhooks can reach it. Confirm `schema_version: 3`
and `workflowVersion: 21` using Admin readiness before accepting rollout on a new
environment.
