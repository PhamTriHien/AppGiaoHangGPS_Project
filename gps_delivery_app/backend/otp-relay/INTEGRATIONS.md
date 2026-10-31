# Delivery integrations

## Central backend management

Open `http://127.0.0.1:8080/#/admin`, sign in to the separate admin portal,
then select **API & Dich vu** in the sidebar. **Tai khoan cloud** shows the
Supabase project, email, Auth UUID and installation ID. Web admin calls require
a real Supabase operator session. Native local management accepts the private
relay token only on loopback. A SQLite admin login does not grant a cloud role.
The old RBAC screen links to this single management page.

**Quan ly API backend** loads metadata for the managed providers. Each service
has its own save, enable toggle and connection check. Secret fields are masked,
never returned by the API, and cleared from the input after a successful save.
Leaving a secret blank preserves it; the delete icon schedules an explicit clear.
History records actor, timestamp and changed field names, never their values.
Configured/enabled does not mean a connection has been verified; the last check
reports the real result. Checks do not send SMS, charge cards or create orders.

Run `npm run setup:central` once to copy existing native Google/SMTP/SMS settings
into the backend without overwriting values already present. Google/Gmail are
preserved. Admin changes are persisted by atomic file replacement in the ignored
`.integration-config.json` and loaded after `.env` on restart. That file is private
plaintext, not an encrypted vault: restrict Windows ACLs or Unix ownership to the
backend service account and protect backups. `.integration-audit.log` needs normal
log retention. Supabase identity URL/public-key changes are local-only to prevent
a remote operator replacing the authentication trust source. Reconfigure the
client and sign in again when switching projects.

**Trien khai backend** also stores DATABASE_URL as a masked operator-managed secret and
PUBLIC_BASE_URL for provider callbacks. Native Admin on loopback uses the local
relay identity for backend management even with a cloud session active. Web and
remote Admin require a verified Supabase operator to edit the database connection
or apply confirmed migrations. **San sang trien khai** checks catalog state and
offers migration according to server permissions; see [COMMERCE.md](COMMERCE.md).
Admin displays the connected backend address so local and remote configuration
are distinguishable. SMTP App Password, database and provider credentials are
saved on that backend, never returned to Flutter or copied to a different server.

For a cloud host, bootstrap SUPABASE_URL and SUPABASE_ANON_KEY in the host's
private environment and provision the first operator using SQL Editor as below.
The server then starts without RELAY_TOKEN: cloud Admin uses Supabase sessions.
RELAY_TOKEN is only for native loopback management, is never exposed in the Admin
API and must not be sent to a remote host. Infrastructure deployment still needs
to happen once outside the app; Admin configures an already running backend.
Mount persistent storage and set INTEGRATION_CONFIG_PATH to a file there before
editing cloud settings. Without it, an ephemeral host discards file changes on
restart/redeploy. Keep existing configuration privately when migrating servers;
do not commit secret files. SMTP also requires a host that allows SMTP egress.

App delivery calls now go through authenticated backend routes:

| Route under `/delivery` | Purpose |
| --- | --- |
| `GET /places`, `GET /reverse` | Managed Photon lookup |
| `GET /route`, `GET /matrix` | OSRM road routing and ETA |
| `GET /banks`, `GET /weather` | VietQR directory and MET forecast |
| `POST /ocr`, `/optimize`, `/support-summary` | OCR, VROOM and Gemini |
| `GET /admin/integrations` | Masked provider metadata |
| `POST /admin/integrations/config` | Save validated configuration |
| `POST /admin/integrations/test/:provider` | Bounded connectivity checks |
| `GET /admin/integrations/audit` | Last 30 configuration changes |
| `GET /admin/integrations/usage` | Process-lifetime outbound HTTP counters |
| `GET /admin/integrations/readiness` | Schema, privacy, permissions and provider prerequisites |
| `POST /admin/integrations/migrate-cloud` | Confirmed operator schema upgrade |
| `GET /admin/ghn/provinces`, `POST /admin/ghn/quote` | GHN legacy catalogue and fee preview |
| `POST /admin/search` | Search existing Meilisearch orders/merchants/drivers indexes |
| `/local-auth/config`, `/local-auth/google/exchange` | Private desktop Google settings and PKCE exchange |
| `/local-auth/sms`, `/local-auth/sms/verify` | Private SMS adapters / Twilio Verify |

Provider secrets and SMTP/SMS/Google token exchange run on the server. Google
authorization still opens the system browser. Supabase Auth/Realtime/private
Storage SDK connections and map tiles still use their native client protocols
and access controls; they are not arbitrary proxies through the backend.

SMS supports TextBee, eSMS, SpeedSMS and Twilio with fixed upstream URLs. SMS
acceptance is not handset delivery confirmation. Legacy client-issued OTP and
local account verification remain a local compatibility flow, not cloud login.
Do not expose these local-auth/OTP routes publicly or embed the relay token in a
web build. Desktop Google adds state and S256 PKCE; it has not been exercised with
a real interactive Google login in automated checks. OAuth client redirect must
allow `http://127.0.0.1:8765/oauth2callback`.

GHN defaults to staging. Cloud-order shipment preview, creation, refresh,
cancellation and callbacks now have a durable backend workflow supporting
two-level address names. payOS links, signed receipts and reconciliation also
operate on cloud orders; see [COMMERCE.md](COMMERCE.md) for database, credentials,
HTTPS callbacks and operating limits. The older catalogue/quote endpoints still
use district/ward codes. Meilisearch requires server-curated indexes; automatic
indexing is not implemented. MoMo/VNPAY remain unavailable adapters. No payment
is reported successful from configuration alone.

`node build-local-web.mjs` builds web with only public Supabase settings and the
local backend URL. Never add provider keys or `RELAY_TOKEN` as Dart defines.
`npm run configure:desktop` updates native connection settings; restart the
desktop app to reload public backend auth policy. Provider saves take effect
without restarting Node. Client public catalogue caches may remain visible until
their normal expiry; the backend checks enable flags before its own cache.

The complete setup, provider limits, SQL migration, security boundaries and live
verification commands are documented here. The short version for local Windows:

```powershell
npm ci
npm run setup:integrations
npm run configure:desktop
npm start
node check-integrations.mjs ../../build/verification/ocr-label.png
```

`setup:integrations` preserves the existing Gmail/Google configuration, downloads
the Vietnamese and English OCR models, and configures manual Photon lookup. OCR is
limited to one in-memory PNG/JPEG job at a time, 5 MB and 16 megapixels; recognized
fields are shown for confirmation before being copied into an order.

The customer and merchant order screens now include Photon address lookup and OCR
label scanning. Live order connection adds order-scoped Supabase Realtime events,
chat/status/GPS synchronization, private delivery evidence storage and optional
FCM notifications. The SQL migration is
`database/migrations/20261027_delivery_integrations.sql`. This integration migration can run on its own;
do not deploy the legacy business schema with real data before adding RLS and
removing public password-hash access. It enables RLS, membership checks, immutable event validation and private
evidence storage. Local SQLite accounts are not automatically Supabase Auth users.
Create cloud users, mark the first operator in `delivery_api_profiles`, then grant
each order member from Admin > API & Dich vu. No public or anon event access is enabled.

VROOM is an optional self-hosted route proposal service. Configure `VROOM_BASE_URL`
only after running the official Docker image with an owned OSRM/Valhalla/ORS router.
The UI proposes routes for at most 30 waiting orders and 10 idle verified drivers;
it does not silently assign them. Docker installation was attempted on this host
but Windows rejected the administrator installer step, so VROOM is not running here.

Turnstile, Firebase FCM, Telegram and Gemini are optional. Their secrets stay in
the backend `.env` and are shown as unavailable until configured. FCM is not enabled
for Windows. Gemini support summaries require a redacted operator-reviewed request
and never authorize refunds. Telegram is restricted to internal failed/returning
order alerts. Turnstile protects OTP relay requests only.

Provider references: [Supabase Realtime](https://supabase.com/docs/reference/dart/stream),
[Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging/flutter/get-started),
[Photon](https://github.com/komoot/photon),
[VROOM Docker](https://github.com/VROOM-Project/vroom-docker),
[Turnstile validation](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/),
[Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).

## Cloud configuration

The new account/transactional order workflow is documented in
[CLOUD_ORDERS.md](CLOUD_ORDERS.md). Install its additional migration before using
the cloud order screens. The legacy integration below remains for device-local
orders connected to manually provisioned event rooms.

Set `SUPABASE_URL` and the public `SUPABASE_ANON_KEY` in `.env`, then run
`npm run configure:desktop`. Create real Supabase Auth email/password users.
Bootstrap the first cloud operator in SQL Editor with the actual Auth UUID:

```sql
insert into public.delivery_api_profiles(user_id,role)
values ('00000000-0000-0000-0000-000000000000','operator')
on conflict(user_id) do update set role='operator';
```

Sign into this cloud account in Admin > API & Dich vu > Tai khoan cloud. Grant the
real tracking code and participant Auth UUID a customer/merchant/driver role.
Open the corresponding order on each device and connect its cloud session.
The integration currently synchronizes events for orders already on the device;
it does not yet provide cloud order creation or complete database migration.
GPS is limited to one recent hardware fix per 15 seconds. The event query loads
the most recent 100 records per order. Failed cloud chat sends remain local and
are marked as unsent; automatic offline chat retries are not implemented.
Status events do not execute settlement or refund accounting.

For push, supply actual platform configuration through FlutterFire, and set
`GOOGLE_APPLICATION_CREDENTIALS` to the absolute path of the server Firebase
service-account JSON. Also set `SUPABASE_SERVICE_ROLE_KEY` and a random
`DELIVERY_WEBHOOK_SECRET` in backend `.env` only. Configure a Supabase Database
Webhook on INSERT into `delivery_live_events`, POST to the public HTTPS endpoint
`/delivery/order-webhook`, using `Authorization: Bearer <DELIVERY_WEBHOOK_SECRET>`.
Supabase cloud cannot reach this computer's localhost. Webhook recipients are
resolved from actual room membership, never from caller-supplied tokens.
Retry deduplication is in-memory for 24 hours and at most 500 tokens are processed
per event; persistent deduplication and larger broadcast batches need further work.

For Turnstile, set real `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY`,
`TURNSTILE_HOSTNAME`, `PUBLIC_BASE_URL`, then `TURNSTILE_ENFORCE_OTP=true`.
The app opens a system-browser challenge, checks a short-lived session and submits
a single-use grant. Server verification checks the hostname and `otp` action.
For Telegram, set an authorized internal `TELEGRAM_CHAT_ID`, `TELEGRAM_BOT_TOKEN`,
and `TELEGRAM_ALERTS_ENABLED=true`. Tests and setup never send Telegram messages.
For Gemini, set `GEMINI_API_KEY` and an available free-tier `GEMINI_MODEL`.
The operator must remove names/addresses from the preview; automatic masking only
covers emails and phone patterns. Free-tier content may improve Google's products.

## Operating limits

The backend binds to loopback by default. Local desktop integration calls accept
the existing relay token from loopback only; remote integration requests require
Supabase authentication and operator roles from server-controlled profiles.
The legacy SMTP route still requires its relay token and must stay private until
OTP issuance and verification are migrated to server-owned sessions.

Photon's public demo is for limited manual development use, with shared caching
and lookup rate limiting. Set an owned `PHOTON_BASE_URL` and explicitly enable
`PHOTON_AUTOCOMPLETE=true` for typing suggestions. Public demo availability is not
guaranteed. There are no paid credentials or unlimited-production assumptions.

The VROOM screen displays proposals with conservative 30 kg motorbike / 500 kg
truck-or-van capacity and pickup-before-delivery constraints. It uses car routing,
not live traffic. The HTTP adapter supports delivery time windows, but this UI
does not yet expose shift/window editors or apply multiple active assignments.

Run `npm test` and `npm audit` for backend checks; run
`flutter test test/advanced_delivery_api_test.dart` for API/UI checks.
The migration and RLS rules are exercised with PGlite PostgreSQL, including an
outsider, customer, driver and operator, invalid state transitions and private
evidence. Actual Supabase websocket connectivity and device push delivery still
require real project credentials and have not been validated live on this machine.
