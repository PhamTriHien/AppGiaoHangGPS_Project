# Delivery integrations

## Central backend management

Open `http://127.0.0.1:8080/#/admin`, sign in to the separate Cloud Operator portal,
then select **API & Dich vu** in the sidebar. **Tai khoan cloud** shows the
Supabase project, email, Auth UUID and installation ID. Web admin calls require
a real Supabase operator session. Native local management accepts the private
relay token only on loopback. A SQLite admin login (`/legacy-admin`) does not
grant a cloud role.

**Quan ly API backend** loads metadata for the managed providers. Each service
has its own save, enable toggle and connection check. Secret fields are masked,
never returned by the API, and cleared from the input after a successful save.
Leaving a secret blank preserves it; the delete icon schedules an explicit clear.
History records actor, timestamp and changed field names, never their values.
Configured/enabled does not mean a connection has been verified; the last check
reports the real result. Checks do not send SMS, charge cards or create orders.

Run `npm run setup:central` once to copy existing native Google/SMTP/SMS settings
into the backend without overwriting values already present. Google/Gmail are
preserved. When `DATABASE_URL` is configured and migrated (`20261107_cloud_commercial_suite`),
all non-bootstrap managed settings and audit entries are persisted to RLS-locked
Cloud PostgreSQL tables (`public.delivery_backend_config` and
`public.delivery_backend_config_audit`, with zero `public`/`anon`/`authenticated`
PostgREST privileges), loaded authoritatively on server startup, and synchronized
live across backend instances (`syncIntegrationConfig` immediately on
`GET /admin/integrations`, `GET /integrations`, and `POST /admin/integrations/test/:provider`,
plus a 5-second cached refresh on `/delivery/*`), while
bootstrap/trust keys (`DATABASE_URL`, `DATABASE_CA_CERT`, `SUPABASE_URL`,
`SUPABASE_ANON_KEY`) remain local to the backend host alongside `.integration-config.json`.
That local file is private plaintext, not an encrypted vault: restrict Windows ACLs or Unix ownership to the
backend service account and protect backups. `.integration-audit.log` needs normal
log retention. Supabase identity URL/public-key changes are local-only to prevent
a remote operator replacing the authentication trust source. Reconfigure the
client and sign in again when switching projects.

**Trien khai backend** also stores `DATABASE_URL` as a masked operator-managed secret and
`PUBLIC_BASE_URL` for provider callbacks. Native Admin on loopback uses the local
relay identity for backend management even with a cloud session active. Web and
remote Admin require a verified Supabase operator to edit the database connection
or apply confirmed migrations. **San sang trien khai** checks catalog state and
offers migration according to server permissions; see [COMMERCE.md](COMMERCE.md).
Admin displays the connected backend address so local and remote configuration
are distinguishable. SMTP App Password, database and provider credentials are
saved on that backend, never returned to Flutter or copied to a different server.

For a cloud host, bootstrap `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the host's
private environment and provision the first operator using SQL Editor as below.
The server then starts without `RELAY_TOKEN`: cloud Admin uses Supabase sessions.
`RELAY_TOKEN` is only for native loopback management, is never exposed in the Admin
API and must not be sent to a remote host. Mount persistent storage and set
`INTEGRATION_CONFIG_PATH` to a file there before editing cloud settings.

App delivery calls go through authenticated backend routes:

| Route under `/delivery` | Purpose |
| --- | --- |
| `GET /places`, `GET /reverse` | Managed TrackAsia / Google Maps / Photon address lookup & reverse geocoding |
| `GET /route`, `GET /matrix` | Managed TrackAsia / Google Routes API / OSRM road routing and ETA |
| `GET /banks`, `GET /weather` | VietQR directory and MET forecast |
| `POST /ocr`, `/optimize`, `/support-summary` | OCR, VROOM and Operator AI summary (`GEMINI_BASE_URL` + `GEMINI_API_KEY`) |
| `POST /cloud/ai-chat`, `POST /ai/chat` | Authenticated customer AI chatbot using backend-managed `GEMINI_BASE_URL`, `GEMINI_API_KEY` and `GEMINI_MODEL` (supports both Google Gemini `:generateContent` and OpenAI-compatible `/chat/completions`, with read-only RLS-scoped customer order context) |
| `GET /admin/integrations` | Masked provider metadata |
| `POST /admin/integrations/config` | Save validated configuration |
| `POST /admin/integrations/test/:provider` | Bounded connectivity checks |
| `GET /admin/integrations/audit` | Last 30 configuration changes |
| `GET /admin/integrations/usage` | Process-lifetime outbound HTTP counters |
| `GET /admin/integrations/readiness` | Schema (`workflowVersion: 13`), worker, privacy, permissions and provider prerequisites |
| `POST /admin/integrations/migrate-cloud` | Confirmed operator schema upgrade |
| `GET /admin/ghn/provinces`, `POST /admin/ghn/quote` | GHN legacy catalogue and fee preview |
| `POST /admin/search` | Search existing Meilisearch orders/merchants/drivers indexes |
| `/local-auth/config`, `/local-auth/google/exchange` | Private desktop Google settings and PKCE exchange |
| `/local-auth/sms`, `/local-auth/sms/verify` | Private SMS adapters / Twilio Verify |

Provider secrets and SMTP/SMS/Google token exchange run on the server. `createIdentity`
verifies Supabase bearer tokens in parallel with `delivery_api_profiles`, caches
verified claims briefly (20s), and preserves upstream connectivity/rate-limit errors
as `502`/`429` rather than `401` so transient network glitches do not invalidate
active client sessions. On Windows/PPPoE networks, `database-connection.mjs` uses
an IPv4-first DNS resolver (`1.1.1.1`, `8.8.8.8` plus system IPv4), fastest-IP
TCP `:443` probing, and classical TLS 1.3 ECDH curves (`X25519:prime256v1:secp384r1`)
to prevent Post-Quantum `ClientHello` fragmentation over 1492-byte MTU links.

### TrackAsia, Photon & optional Google Maps Platform proxy (`trackasia` / `google_maps`)

- **TrackAsia Maps Vietnam (`TRACKASIA_ENABLED=true`)**: When `TRACKASIA_API_KEY` is
  configured in backend `.env` or Admin **Quan ly API backend**, `/delivery/places`
  proxies to `maps.track-asia.com/api/v1/autocomplete` (with `api/v2/place/textsearch/json`
  fallback and Vietnam coordinate focus), `/delivery/reverse` proxies to
  `api/v2/geocode/json`, `/delivery/route` proxies to `route/v1/car`, and
  `/delivery/matrix` proxies to `distance-matrix/v1/car` — allowing both
  `PHOTON_ENABLED=false` and `OSRM_ENABLED=false` with zero credit-card requirement
  and zero client-side key exposure.
- **OpenStreetMap fallback (`TRACKASIA_ENABLED=false`, `GOOGLE_MAPS_ENABLED=false`)**: `/delivery/places` and `/delivery/reverse`
  query OpenStreetMap / Photon with required `User-Agent: GHSTDelivery/1.0`,
  Vietnam location bias, shared caching and lookup rate limiting. Set an owned
  `PHOTON_BASE_URL` and `PHOTON_AUTOCOMPLETE=true` for high-volume production typing
  suggestions.
- **Optional server-side Google Maps proxy (`GOOGLE_MAPS_ENABLED=true`)**: When
  `GOOGLE_MAPS_API_KEY` is configured in backend `.env` or Admin **Quan ly API backend**,
  `/delivery/places` proxies to **Places API (New)** (`places:searchText` with
  explicit `X-Goog-FieldMask`, `regionCode: 'VN'`, `languageCode: 'vi'`),
  `/delivery/reverse` proxies to **Geocoding API**, and `/delivery/route` +
  `/delivery/matrix` proxy to **Routes API** (`directions/v2:computeRoutes` and
  `distanceMatrix/v2:computeRouteMatrix`) without exposing the API key to the
  browser/app — allowing `PHOTON_ENABLED=false` and `OSRM_ENABLED=false` when
  running exclusively on Google Maps Platform. Restrict `GOOGLE_MAPS_API_KEY` by
  server IP and limit API access strictly to Places API (New), Geocoding API, and
  Routes API, and review Google Maps Platform Terms of Service / Prohibited
  Territories (including regional applicability for Vietnam) before enabling in
  commercial production.

### Other managed providers

SMS supports TextBee, eSMS, SpeedSMS and Twilio with fixed upstream URLs. Legacy
client-issued OTP and local account verification remain a `/legacy` compatibility
flow, not cloud login. Native Supabase Google OAuth PKCE uses callback
`http://127.0.0.1:8766/auth/callback` (while legacy local Google uses
`http://127.0.0.1:8765/oauth2callback`).

GHN defaults to staging. Cloud-order shipment preview, creation, refresh,
cancellation and callbacks have a durable backend workflow supporting two-level
address names. `payOS` links, signed receipts and reconciliation operate on both
standalone cloud orders and prepaid multi-shop purchases; see [COMMERCE.md](COMMERCE.md).

`node build-local-web.mjs` builds web with only public Supabase settings and the
local backend URL. Never add provider keys or `RELAY_TOKEN` as Dart defines.
`npm run configure:desktop` updates native connection settings.

```powershell
npm ci
npm run setup:integrations
npm run configure:desktop
npm start
node check-integrations.mjs ../../build/verification/ocr-label.png
```

`setup:integrations` preserves existing Gmail/Google configuration, downloads
Vietnamese/English OCR models, and configures Photon lookup. OCR is limited to
one in-memory PNG/JPEG job at a time (5 MB, 16 megapixels); recognized fields
require user confirmation before copying into an order.

VROOM is an optional self-hosted route proposal service (`VROOM_BASE_URL`)
proposing routes for at most 30 waiting orders and 10 idle verified drivers.
Turnstile, Firebase FCM, Telegram and Gemini remain optional server-managed
providers; unconfigured providers report unavailable rather than fabricating data.

Provider references: [Supabase Realtime](https://supabase.com/docs/reference/dart/stream),
[Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging/flutter/get-started),
[Photon](https://github.com/komoot/photon),
[Google Maps Platform Terms](https://cloud.google.com/maps-platform/terms),
[VROOM Docker](https://github.com/VROOM-Project/vroom-docker),
[Turnstile validation](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/),
[Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).

## Cloud configuration & push webhooks

The transactional Cloud order and Marketplace workflows are documented in
[CLOUD_ORDERS.md](CLOUD_ORDERS.md) and [MARKETPLACE.md](MARKETPLACE.md).

For push notifications, supply actual platform configuration through FlutterFire,
set `GOOGLE_APPLICATION_CREDENTIALS` to the server Firebase service-account JSON
path, and set `SUPABASE_SERVICE_ROLE_KEY` plus `DELIVERY_WEBHOOK_SECRET` in
backend `.env` only. Configure Supabase Database Webhooks to POST to the public
HTTPS endpoints `/delivery/order-webhook` (`delivery_live_events`) and
`/delivery/market-notification-webhook` (`delivery_market_notifications`) using
`Authorization: Bearer <DELIVERY_WEBHOOK_SECRET>`. Webhook recipients are
re-read from Supabase and sanitized so private chat text and customer addresses
are never transmitted in push payloads.

## Validation

Run `npm test` (`118/118`), `npm run test:postgres` (`22/22`) and `npm audit` for
backend checks; run `flutter analyze --no-pub` and `flutter test --no-pub` (`280+`
passed) for Flutter API/UI checks.
