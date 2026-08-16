# Changelog

This file records user-visible changes in reverse chronological order. The current `solidus_nexi` history is tied to the Conventional Commit operations that produced each release so a maintainer can move from a release note to the exact change.

The legacy repository did not retain release tags for its original `2.0.3` and `2.1.0` versions. Those entries are reconstructed from the versions declared in the gemspec and version file. The `v2.1.0` tag was added on 2026-08-16 to preserve the final legacy tree before the rewrite.

## 0.1.0.alpha.1 — 2026-08-16

This is the first tagged source prerelease under the renamed `solidus_nexi` gem and `SolidusNexi` namespace. It has not yet been published to RubyGems. This is a replacement for `spree_dibs`, not an API-compatible update.

### Added

- Added a framework-light client for the current Nexi Checkout Payment API, including typed failures, strict timeouts, minor-unit money handling, response bounds, and safe structured logging.
- Added hosted checkout creation with exact order serialization and trusted Nexi redirect validation.
- Added durable payment-source, operation, and webhook-receipt records with database uniqueness constraints.
- Added full capture, full cancellation, and full refund through Solidus payment seams.
- Added authenticated, deduplicated webhook processing and provider-retrieval reconciliation.
- Added explicit unknown-outcome handling, manual reconciliation tasks, admin status visibility, and webhook-secret rotation.
- Added sanitized provider fixtures and compatibility coverage for Solidus 4.7 and 4.6.

### Changed

- Renamed the repository and gem identity to `solidus_nexi`, and the Ruby namespace to `SolidusNexi`.
- Replaced process-global ActiveMerchant behavior with per-payment-method Nexi test/live clients.
- Moved card-data collection entirely to Nexi's hosted checkout.

### Removed

- Removed `Spree::Gateway::Dibs`, the legacy ActiveMerchant fork dependency, card-year mutation, SSL workaround, and DIBS frontend assets.
- Removed support for partial capture and partial refund until an exact Solidus-to-Nexi order-item allocation can be proven.
- Removed compatibility aliases for the historical gateway and payment sources.

### Security

- Store API and webhook credentials as encrypted Solidus preferences.
- Compare current and previous webhook Authorization secrets safely without persisting the callback body.
- Reject unauthenticated callbacks before database mutation and acknowledge valid callbacks with HTTP 200 exactly.

### Git operation log

- `aaef6f4` — `feat!`: replace DIBS gateway with Solidus Nexi foundation.
- `af53d51` — `feat`: implement hosted Nexi Checkout lifecycle.
- `3bf4a7b` — `test`: cover Nexi payment reliability contracts.
- `ae7de46` — `ci`: test supported Solidus and Ruby versions.
- `e2724f0` — `docs`: document Nexi cutover and operations.
- `c460fcf` — `docs`: align guides for the RubyGems release.

## 2.1.0 — 2014-03-01

This was the final `spree_dibs` line. The version was introduced by `f64a220`; later maintenance through `83c7775` remained on `2.1.0`. The final tree is preserved by the archive tag `v2.1.0`.

### Changed

- Updated the legacy gateway and development dependencies for Spree 2.2 and the then-current Spree master branch.
- Reworked version handling around `Gem::Version` and explicit version components.
- Refreshed the gemspec, test variables, Rails bin scripts, and project documentation.

### Git operation log

- `f64a220` — Update for Spree 2.2.0 and declare version 2.1.0.
- `c8e42a3` — Move development to the Spree 2.3 beta line.
- `3a2e0bf` through `83c7775` — Complete the final documentation, gemspec, test, and Rails bin maintenance.

## 2.0.3 — 2013-06-19

This was the initial public repository version of `spree_dibs`. Its recorded development range runs from `0c26bcd` through `9cdf0f3`.

### Added

- Added the original ActiveMerchant-backed DIBS payment gateway for Spree 2.0.
- Added authorize, capture, void, credit, and refund delegation to the DIBS gateway.
- Added the original extension engine, payment-method registration, account configuration, and gateway specs.

### Changed

- Moved the version from the gemspec into `SpreeDibs::VERSION`.
- Updated the legacy Spree development branches, test-app tooling, dependencies, README, and license presentation during the 2.0.x line.

### Historical limitations

- Required an unmerged ActiveMerchant fork for DIBS support.
- Required merchant credentials in the old test configuration.
- Documented an SSLv3 workaround that must not be carried into modern deployments.
