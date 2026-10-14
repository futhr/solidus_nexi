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

- Use published Solidus 4.8, patched Rails series, Net::HTTP 0.10, source-built pg 1.7, and current lint/test dependencies; refresh CI action and PostgreSQL image pins.

- Qualify PostgreSQL 18.6 with a source-built pg 1.7 client; consolidate automatic CI into one PR job and retain the broader profiles manually.

- Replaced the historical `spree_dibs` extension with the `solidus_nexi` gem and `SolidusNexi` namespace.
- Moved payment-detail collection entirely to Nexi's hosted checkout.
- Limited financial mutations to full amounts until exact partial item allocation can be guaranteed.
- Support Rails 7.2, 8.0, and 8.1; use published Solidus 4.8 and Rails 8.1 for development.

### Fixed

- Declare the pagination dependency still loaded by Solidus 4.8 core so the packaged engine boots without development gems.

- Classify malformed HTTP responses as transport failures for retrievals and unknown outcomes for financial mutations.

- Recover checkout creation when the provider accepted the request but the local response was lost.
- Reconcile asynchronous refund completion and failure by exact provider refund ID.
- Requeue failed or abandoned webhook work without duplicating active or terminal receipts.
- Preserve idempotency keys across retries and flag provider-success/local-failure races for reconciliation.
- Prevent late webhooks from regressing terminal payment state or applying to the wrong checkout.
- Reject invalid tax allocations, unsupported money values, and unsafe public URLs before provider dispatch.
- Match Solidus foreign-key widths on MySQL.
- Bind hosted checkout reuse and reconciliation to the exact serialized order context, even when totals match.

- Reject fractional, non-finite, and malformed provider amounts and operation collections.
- Reject cancelled, refunded, and mismatched payments during gateway verification.
- Preserve malformed cancellation and TLS failures as uncertain mutation outcomes.
- Validate recovered payment identities before binding them and retry stale financial snapshots.
- Recover stale dispatched operations and checkout IDs retained only on operation records.
- Handle cancelled and expired refunds, keeping a later pending refund visible after an earlier failure.
- Isolate duplicate inserts in savepoints so PostgreSQL can recover within an existing transaction.
- Require post-expiry financial verification before replacing a checkout; never abandon a dispatched unknown payment on elapsed time alone.
- Declare the HTTP transport and the Sprockets railtie required to boot a core-only Solidus bundle.
- Exclude hidden files and symlinks from gems and verify packaged metadata and file bytes.

### Security

- Store provider credentials as encrypted Solidus preferences and require a 32-byte preferences master key.
- Authenticate callbacks before persistence and accept one previous webhook secret during rotation.
- Bound provider responses and logs without retaining request bodies, webhook bodies, or cardholder data.
- Require RubyGems MFA metadata and restrict package publication to RubyGems.org.

## 2.1.0 — 2014-03-01

Final historical `spree_dibs` source line. The archived tree is preserved by the `v2.1.0` tag and is unsupported.

### Changed

- Qualify PostgreSQL 18.6 with a source-built pg 1.6.3 client; consolidate automatic CI into one PR job and retain the broader profiles manually.

- Updated the legacy gateway for the Spree 2.2 development line.
- Refreshed its version handling, dependencies, test app, and documentation.

## 2.0.3 — 2013-06-19

Initial public `spree_dibs` extension for Spree 2.0.

### Added

- The original ActiveMerchant-backed DIBS gateway and Spree payment integration.

### Historical limitations

- Relied on an unmerged ActiveMerchant fork and obsolete transport workarounds.
