# Changelog

Notable user-facing changes are recorded here. The current `solidus_nexi` rewrite has not been tagged or published.

## Unreleased

### Added

- A Solidus-native integration for the current Nexi Checkout Payment API.
- Hosted checkout creation with exact order serialization and validated redirect URLs.
- Full capture, cancellation, and refund support through Solidus payment APIs.
- Authenticated, deduplicated webhooks and provider-backed reconciliation.
- Durable operation records for idempotency and unknown network outcomes.
- Admin payment status, manual reconciliation tasks, and webhook-secret rotation.
- SQLite, PostgreSQL, and MySQL coverage across the supported Solidus and Ruby matrix.
- An opt-in merchant TEST API contract and a documented hosted-card release gate.

### Changed

- Replaced the historical `spree_dibs` extension with the `solidus_nexi` gem and `SolidusNexi` namespace.
- Moved payment-detail collection entirely to Nexi's hosted checkout.
- Limited financial mutations to full amounts until exact partial item allocation can be guaranteed.
- Required the maintained Rails 7.2 line and patched Rails releases.

### Fixed

- Recover checkout creation when the provider accepted the request but the local response was lost.
- Reconcile asynchronous refund completion and failure by exact provider refund ID.
- Requeue failed or abandoned webhook work without duplicating active or terminal receipts.
- Preserve idempotency keys across retries and flag provider-success/local-failure races for reconciliation.
- Prevent late webhooks from regressing terminal payment state or applying to the wrong checkout.
- Reject invalid tax allocations, unsupported money values, and unsafe public URLs before provider dispatch.
- Match Solidus foreign-key widths on MySQL.
- Bind hosted checkout reuse and reconciliation to the exact serialized order context, even when totals match.

### Security

- Store provider credentials as encrypted Solidus preferences and require a 32-byte preferences master key.
- Authenticate callbacks before persistence and accept one previous webhook secret during rotation.
- Bound provider responses and logs without retaining request bodies, webhook bodies, or cardholder data.
- Require RubyGems MFA metadata and restrict package publication to RubyGems.org.

## 2.1.0 — 2014-03-01

Final historical `spree_dibs` source line. The archived tree is preserved by the `v2.1.0` tag and is unsupported.

### Changed

- Updated the legacy gateway for the Spree 2.2 development line.
- Refreshed its version handling, dependencies, test app, and documentation.

## 2.0.3 — 2013-06-19

Initial public `spree_dibs` extension for Spree 2.0.

### Added

- The original ActiveMerchant-backed DIBS gateway and Spree payment integration.

### Historical limitations

- Relied on an unmerged ActiveMerchant fork and obsolete transport workarounds.
