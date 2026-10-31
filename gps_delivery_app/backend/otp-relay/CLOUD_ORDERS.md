# Cloud accounts and orders

This adds an authoritative cloud workflow alongside existing device-local data.
Local accounts, local order IDs and local RBAC do not grant a Supabase identity or
cloud privileges. Existing local orders are not automatically uploaded.

## Install on the existing Supabase project

The public/publishable key cannot execute migrations. Use either:

1. In Supabase SQL Editor, run `database/migrations/20261028_cloud_orders.sql`.
   It requires `20261027_delivery_integrations.sql`, already used for live rooms.
   On a new project, run that integration migration first. Do not install the
   legacy `database/schema.sql` as a prerequisite.
2. Put the real PostgreSQL connection string from Supabase **Connect** in backend
   `.env` as `DATABASE_URL`, then run `npm run migrate:cloud`. Use the direct or
   session-pooler connection appropriate for the server network. URL-encode the
   database password. The runner uses verified TLS for remote databases, does
   not log credentials and installs the integration schema only if absent.

`npm run check:cloud` checks schema discovery with the public key only. It does
not sign in, create users, send email or write orders. A detected schema is not
proof that the authenticated workflow has been exercised on that project.

The migration is additive and can be reapplied. It creates `delivery_cloud_*`
tables, RLS, constrained transactions and event guards. No real/sample accounts
or orders are inserted. Its default tariff is 25,000 VND for the first 2 km,
5,000 per additional started km, 10,000 express surcharge, and 3,000 per started
kg over 5 kg. Admin can change these values in **Bang gia cloud**.

### Workflow version 2

Projects that already installed this file must run its current contents again.
It preserves accounts, tariffs, existing orders, history and login sessions.
It adds a separate `returned` terminal state and reasons on history events.
`GET /delivery/cloud/profile` reports `schema_version: 2` after the upgrade.
The backend refuses role, tariff and state mutations on older schemas instead
of allowing a return to be incorrectly recorded as a successful delivery.
An operator sees the upgrade requirement in the cloud administration screen.
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
responses. The legacy profile/address screens are not yet migrated to this API.

### Sign-in and role approval

The Flutter cloud order screen uses `CloudAccountSession` for verified account
and operator state. Restoring a Supabase session triggers profile verification;
SQLite accounts and pending role requests never grant cloud permissions. Auth
changes invalidate the previous identity, including signing in again as the
same user. A failed profile verification removes cached privileges and loaded
order/account lists. Refreshing the profile also invalidates those lists when
role, blocked status or operator access changes. This is client isolation in
addition to server/RLS authorization, not a replacement for it. The main legacy
dashboard login has not yet moved to this controller.

- User entry: `http://127.0.0.1:8080/#/cloud` or the cloud icon in each subsystem.
  Email/password sign-in and registration use the configured Supabase Auth project.
  Confirm email when required by that project's Auth policy.
- Admin entry: the separate `/admin` login has **Dang nhap quan tri cloud**, or
  visit `http://127.0.0.1:8080/#/cloud-admin`. The local admin sidebar also contains
  **Don hang cloud**. A verified Supabase operator is required for admin actions.
- Complete the cloud profile with name and phone. New profiles always start as
  customer; driver/merchant requests stay pending until an operator approves.
- Bootstrap the first operator in SQL Editor using an actual Auth user UUID:

```sql
insert into public.delivery_api_profiles(user_id,role)
values ('REPLACE_WITH_REAL_AUTH_USER_UUID'::uuid,'operator')
on conflict(user_id) do update set role='operator';
```

In admin **Don hang cloud > Tai khoan**, approve driver/merchant roles or block
business profiles. This does not grant/revoke the separate operator role. Role,
block and tariff changes have an immutable operator audit trail. The current UI
lists the most recent 200 business profiles; it is not a full identity directory.
Search and role/pending/blocked filters apply to those loaded profiles. Approval,
rejection, role changes and blocking each require confirmation. Blocking or
unblocking preserves a pending role request; explicit approval/rejection clears
it. A driver with an unfinished trip cannot be demoted. Blocking remains
available, with the operator responsible for completing/cancelling that trip.

## Complete workflow

1. Customer creates an order, optionally selecting an approved merchant. Approved
   merchants can also create orders for their own pickup operation.
2. Enter actual pickup/dropoff addresses and coordinates, recipient, package,
   weight and optional COD. Manual Photon lookup can populate coordinates.
3. Review the backend quote and confirm. Fees are computed in PostgreSQL; client
   price, owner, driver, payment status and role are never trusted.
4. If a merchant is attached, they confirm ready. Approved drivers then see the
   available queue, without recipient contact or exact address before claiming.
5. Driver claims, arrives at pickup, collects, then delivers; failure, retry and
   return steps are supported. Customer/merchant/operator can cancel before pickup
   with a reason. Operator can inspect orders and history.
6. Failure and initiating a return each require a reason. A failed trip can be
   retried or returned. Completing a return records `returned`, never `delivered`,
   and releases the driver to claim another trip. This does not settle payment
   or COD. Reasons remain visible in the authorized order history.

Quotes include an authoritative breakdown of base, additional distance, excess
weight and express fees. Tariff values must be bounded nonnegative integers in
both the gateway and PostgreSQL, including direct Data API calls. Order search
and status filters apply to loaded pages; the displayed matched/loaded count
keeps that scope explicit. Load more to include older records.

Each creation/transition has an account-scoped persistent command key. Repeating
the same request returns the committed result; a reused key with a different
payload fails. A row lock protects competing claims; a driver lock prevents the
same driver claiming two active orders. Optimistic versions reject stale writes.
The tariff version and expected fee must still match at order confirmation.
The client remembers only command IDs/hashes and a draft ID, not the form's PII.
Reopening an unconfirmed draft requires re-entering the same data to reuse its
request fingerprint. A successful new draft receives a new ID.

Orders automatically provision their existing live room/membership and publish
committed status notifications. Direct legacy status events cannot change the
authoritative order state. The list refreshes every 20 seconds while visible;
it is not yet a full Realtime order-list subscription. Per-order GPS/chat/POD
continue through the existing live-room integration. The new cloud order list
does not yet expose those per-order chat/POD controls.

## API

All routes are under `/delivery/cloud`, require a real user JWT and reject the
private local relay identity. PostgreSQL functions repeat authorization checks
even when called through Supabase Data API directly. No service-role key is
needed for normal order operations.

| Method/path | Action |
| --- | --- |
| GET/POST `/profile` | Read/save own profile, request a business role |
| GET `/merchants` | Approved merchant IDs/names only |
| GET `/accounts`, POST `/accounts/:id` | Operator approval and business blocking |
| GET/POST `/pricing`, GET `/audit` | Operator tariff and audit |
| POST `/quote` | Server-computed estimate |
| GET `/orders?queue=true` | Redacted queue for approved drivers |
| GET `/orders` | Up to 50 accessible orders, optional `before` timestamp + `before_id` cursor |
| POST `/orders` | Versioned price-confirmed, idempotent creation |
| POST `/orders/:id/transition` | Transactional action with expected version; `complete_return` closes a return |
| GET `/orders/:id/history` | Authorized immutable order history |

## Limits

Flutter order lists use `CloudOrdersRepository`, bound to the verified
`CloudAccountSession` and its project, Auth user and permission revision. Switching
identity or list view invalidates pending reads and pagination. The cache is
in memory only and never falls back to legacy SQLite orders. Pagination uses
the server timestamp and ID cursor; transient next-page errors retain already
loaded rows for retry, while authorization errors discard them. This repository
is used by the cloud order screen, not yet by the legacy main login/history.

Cloud pricing currently uses great-circle distance multiplied by 1.3, explicitly
shown as an estimate; it does not bill from OSRM road length or live traffic.
Service choices are standard/express, one dropoff, up to 30 kg, estimated 200 km,
and integer COD from zero to 20 million VND. Addresses/coordinates are validated
but not independently proven to describe the same real place.

Sender/recipient cash fees remain available. Eligible sender-paid orders also
support payOS prepaid shipping and operator-managed GHN fulfillment after the
additional migration and backend setup in [COMMERCE.md](COMMERCE.md). Delivery
does not itself mark a payment settled, transfer a wallet balance, settle COD
or invoke MoMo/VNPAY. Delivery
confirmation has no mandatory photo/OTP gate yet. Driver availability cannot be
an identity or location verification guarantee. Document/KYC review is an operator
process, not automatically verified by role approval.

The existing localhost backend must be deployed over HTTPS before separate
physical devices or Supabase webhooks can reach it. This change does not publish
the backend, configure a domain, activate FCM or claim production readiness.

Validation: `npm test`, `flutter test test/cloud_orders_test.dart`, and
`flutter analyze`. PostgreSQL behavior is exercised in isolated PGlite, including
role denial, RLS, fee changes, retries, stale/conflicting claims, immutable
history, blocked users and forged status events. It does not replace a real
Supabase multi-device acceptance test after schema installation.

The full Flutter suite passes with `flutter test --concurrency=1`, including the
older local-business tests and CSV/location regression checks. The optional
external live-API test is skipped unless explicitly enabled. Backend tests also
pass. Run memory-intensive suites sequentially on limited-memory machines.
Browser fixtures at 360/1440 pixels never create real Supabase users or orders.
Passing those checks does not establish that the installed cloud schema was
upgraded. Confirm `schema_version: 2` using a real authenticated profile request
before accepting the migration rollout.
