# Logic And UI Audit

Checked 2026-10-30. Scope: canonical cloud marketplace, adjacent shipping/private
views and separate Admin compatibility. This is local/isolated acceptance, not
certification of every roadmap item or deployed provider transaction.

## Resolved In Source

| Finding | Result |
| --- | --- |
| UI can show an old cart/address while quote uses newer server data | Quote checks displayed versions, rejects conflicts, and displays authoritative snapshot items/options/address |
| Conflict leaves old quantities and purchase consent visible | Cart reloads and clears quote; aftersales refreshes current details |
| Address outage hides a successfully loaded cart | Cart remains visible, address error is explicit and quote submission is disabled |
| Failed list load claims empty data or offers to create an existing shop | Empty/create states require a successful read; retry remains available |
| Changed filter can retain products from the previous category | Fresh filter reads discard the old products and cursor |
| Access failure can retain private data or repeatedly recreate a denied view | Current lease revokes and clears; explicit retry, no immediate refresh loop; late old-lease failures cannot revoke a newer session |
| Deleted/revoked object remains visible after 404 | Product, order services and conversation clear stale private content |
| Delivered/returned purchases still say handed to shipping | Labels use shipping state, with delivered timestamp fallback |
| Returning from aftersales leaves parent orders outdated | Parent list refreshes on return |
| Notification tap only marks read | Opens the referenced order services or order conversation and refreshes on return |
| Chat read failure claims there are no messages | Empty state requires a successful read |

## Fresh Verification

- Native disposable PostgreSQL: 17 groups passed, including stale cart/address
  versions, forged quote fields, stock concurrency and migration reapplication.
- Backend: 94 passed. Flutter analyze: no issues. Flutter: 249 passed, one
  optional external-service test skipped. New audit suite: 21 widget regressions.
- Web and Windows release builds passed. Existing third-party Windows
  Nuget/CMake warnings did not fail the build.
  The new Windows app was launched and its window was responsive; backend and
  preview returned HTTP 200 at close-out. This is not a real purchase test.
- Browser: eight marketplace role/viewport cases, six cloud compatibility cases
  and two separate Admin cases passed. Widths: 360 and 1440. Marketplace includes
  options, quote/address confirmation, purchase, aftersales, notifications/chat,
  merchant media/configuration and operator finance fixtures.
- Fresh cart/notification/chat screenshots were viewed at mobile/desktop widths;
  no observed overlap. Artifacts: build/verification/market-*.png and
  postgres-acceptance.json. ordered-checks.json is the earlier configured-catalog
  run; it was not relabeled as this audit.

## Remaining Deployment Gap

Read-only check at 2026-10-30T16:49:31Z connected to the saved cloud database with
verified TLS. Cloud shipping/address and commerce schema/privacy/permissions
passed metadata checks. Marketplace, operations, memberships, import, stock
terms, media, browse and configuration schemas are missing. Existing Admin
migration package targets 20261106_catalog_configuration, workflow 12.

payOS, GHN and public HTTPS are incomplete; background expiry worker is disabled.
No cloud migrations/writes or provider transactions were performed by this audit.
Real Auth/role and two-device shopping acceptance must follow rollout. Remaining
feature gaps are listed separately in EXECUTION_CHECKLIST.md; P0-P7 is incomplete.
