# Solidus Nexi

[![Test](https://github.com/futhr/solidus_nexi/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/futhr/solidus_nexi/actions/workflows/test.yml)
[![Codecov](https://codecov.io/gh/futhr/solidus_nexi/branch/main/graph/badge.svg)](https://codecov.io/gh/futhr/solidus_nexi)
[![Status](https://img.shields.io/badge/status-unreleased-orange)](CHANGELOG.md)
[![Ruby](https://img.shields.io/badge/Ruby-3.2%2B-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Solidus](https://img.shields.io/badge/Solidus-4.6%E2%80%934.7-2B59C3)](https://solidus.io/)
[![License](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](LICENSE.md)

`solidus_nexi` connects Solidus to the current Nexi Checkout Payment API. The customer enters payment details on Nexi's hosted checkout page; Solidus stores only the identifiers and financial state it needs to operate the payment.

This project succeeds the historical `spree_dibs` extension. It is a complete rewrite under the `SolidusNexi` namespace and is not API-compatible with `Spree::Gateway::Dibs`. The final legacy source is preserved by the `v2.1.0` repository tag.

The gem is still unreleased. Its version constant is a development prerelease identifier; no `solidus_nexi` version has been tagged or published. Complete a merchant-specific Nexi test-environment run before enabling it in production.

## Compatibility and scope

The primary target is Solidus 4.7. Solidus 4.6 remains a secondary target while it can be supported without compromising the integration. Ruby 3.2 and newer and the maintained Rails 7.2 line are supported; CI covers Ruby 3.2 through 4.0 on the primary target and runs the full suite on SQLite, PostgreSQL 16, and MySQL 8.4.

The initial release supports:

- one-time payments through `HostedPaymentPage`;
- reservation/authorization with optional immediate capture;
- full capture of an authorized payment;
- full cancellation before capture;
- full refund of a captured payment;
- authenticated webhook synchronization;
- manual and background reconciliation from Nexi's payment resource; and
- CHF, CZK, DKK, EUR, GBP, NOK, PLN, SEK, and USD.

It does not support subscriptions, stored payment profiles, embedded checkout, partial capture, partial cancellation, or partial refund. Partial financial operations need an exact order-item allocation that Solidus's amount-only gateway calls cannot prove, so the adapter rejects them before contacting Nexi.

## How a payment moves through the system

The extension creates a local payment source and durable operation before making a provider request. Nexi returns a `paymentId` and a hosted checkout URL, and the browser is redirected to Nexi. A customer return only schedules reconciliation; it is never accepted as proof that money moved.

Webhooks are authenticated with the Authorization value registered on the payment. Their event IDs are deduplicated in the database, and a background job retrieves the complete Nexi payment before changing Solidus financial state. This retrieval step makes duplicate and out-of-order notifications safe and is also how the extension resolves most uncertain network outcomes.

Capture and refund requests reuse one persisted Nexi idempotency key for the same logical action. Refund initiation remains pending until authoritative retrieval reports completion or failure; a failed provider refund restores Solidus's refundable balance. Payment creation and cancellation are not replayed after an uncertain response because the current endpoint contracts do not expose equivalent idempotency protection.

## Installation

Once the first release is published to RubyGems, add the renamed gem to the host application:

```ruby
gem "solidus_nexi", "0.1.0.alpha.1"
```

Until then, development installations can use the renamed GitHub repository:

```ruby
gem "solidus_nexi", github: "futhr/solidus_nexi"
```

Install the bundle, mount the engine, copy its migrations, and migrate:

```sh
bundle install
bin/rails generate solidus_nexi:install --auto-run-migrations
```

The generator creates `config/initializers/solidus_nexi.rb` and mounts the engine at `/solidus_nexi`. Without `--auto-run-migrations`, it asks before running migrations and prints the command to run later when declined.

The host application must provide a 32-byte `SOLIDUS_PREFERENCES_MASTER_KEY`. Solidus uses this key to encrypt the API key and webhook secrets stored as payment-method preferences.

### Free Nexi test account

Yes, the Nexi test account is free. New Checkout Portal accounts start in test mode.

1. [Register with Nexi](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/create-a-checkout-portal-account/) using an email address and phone number, verify the email, and sign in.
2. In the Checkout Portal, open **Company → Integration** and copy the **test Secret API key**. This hosted integration does not use the public Checkout key.
3. Generate the two local secrets:

   ```sh
   openssl rand -hex 16 # SOLIDUS_PREFERENCES_MASTER_KEY: 32 characters
   openssl rand -hex 24 # NEXI_CHECKOUT_WEBHOOK_SECRET
   ```

4. Run `bin/setup`. It creates `.env` from [.env.example](.env.example) when missing. Put the generated values and test Secret API key there, leave the previous webhook secret empty, then run `bin/check-env`. Keep `NEXI_CHECKOUT_ENVIRONMENT=test` and use a public HTTPS origin for `NEXI_CHECKOUT_PUBLIC_BASE_URL`; a local server needs an HTTPS tunnel so Nexi can reach its webhook.
5. Install the payment method as described below, then pay with a card from Nexi's [test-card list](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/test-card-processing/). Test payments move no real money.

Before requesting a live account, run both payment paths: reserve → capture and reserve → cancel with auto-capture off, then charge → refund with auto-capture on. Confirm the webhook reaches the app, repeated reconciliation creates no duplicate capture or refund, and the matching payment is visible in the Checkout Portal. Nexi's [test-environment guide](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/test-environment/) lists the test endpoints and data.

## Configuration

The generated initializer can register an environment-backed preference source. These values belong in the application's secret manager, not in source control.

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `SOLIDUS_PREFERENCES_MASTER_KEY` | Yes | — | Encrypts secret Solidus preferences; must be exactly 32 bytes. |
| `NEXI_CHECKOUT_API_KEY` | Yes | — | Portal Secret key sent in the Payment API Authorization header; this is not the Checkout key. |
| `NEXI_CHECKOUT_WEBHOOK_SECRET` | Yes | — | Alphanumeric callback credential, 8–64 characters. |
| `NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET` | During rotation | — | Previous callback credential accepted for payments created before rotation. |
| `NEXI_CHECKOUT_ENVIRONMENT` | No | `test` | Use `test` or `live`; any other value is treated as test by the generated initializer. |
| `NEXI_CHECKOUT_COUNTRY` | No | `SWE` | Three-letter ISO checkout country code. |
| `NEXI_CHECKOUT_TERMS_URL` | Yes | — | Public HTTPS terms-and-conditions page. |
| `NEXI_CHECKOUT_MERCHANT_TERMS_URL` | No | — | Public HTTPS privacy and cookie page. |
| `NEXI_CHECKOUT_PUBLIC_BASE_URL` | Yes | — | HTTPS origin where the mounted return and webhook routes are reachable. |

Development and test commands load the repository-root `.env` without overwriting variables already exported by the shell. Staging and production never load it. See [.env.example](.env.example) for the complete template; its `.example` URLs are deliberately non-runnable and must be replaced. `bin/check-env` rejects reserved names and private, loopback, link-local, and documentation IP literals. Supplying both the API key and current webhook secret activates the generated static preference source; at that point the terms URL must also be present.

Create a `SolidusNexi::PaymentMethod` in the Solidus admin, associate it with the intended stores, and select the `nexi_checkout_env_credentials` preference source. Solidus's `auto_capture` setting controls whether the checkout asks Nexi to charge immediately after reservation. Secret preferences are deliberately absent from the generic admin form.

### Rotating the webhook secret

Put the new value in `NEXI_CHECKOUT_WEBHOOK_SECRET` and move the old value to `NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET`. New payments register the new value while callbacks for existing payments can authenticate with either generation.

Keep the previous value until payments that registered it are no longer operational or refundable, then remove it. Only one previous generation is supported. Deactivating a payment method prevents new checkouts but does not disable authenticated callbacks for its existing payments.

## Storefront integration

The engine ships payment partials for storefronts that render Solidus payment-method partials. A custom or headless storefront can start or reuse a hosted checkout directly:

```http
POST /solidus_nexi/checkout_sessions
Content-Type: application/json

{
  "order_number": "R123456789",
  "guest_token": "the-order-guest-token",
  "payment_method_id": 4
}
```

The guest token is always required, including for a signed-in customer. An order number by itself is not sufficient authorization to create a provider payment.

JSON requests receive the local payment number, Nexi payment ID, hosted URL, and whether the open checkout was reused. Browser form requests receive an HTTP 303 redirect to the validated Nexi hosted URL.

The default return and cancellation resolvers point to `/checkout/confirm` and `/checkout/payment`. Override them for a custom storefront:

```ruby
SolidusNexi.configure do |config|
  config.public_base_url = ENV.fetch("NEXI_CHECKOUT_PUBLIC_BASE_URL")
  config.return_path_resolver = lambda do |source|
    "/orders/#{source.payments.last.order.number}"
  end
  config.cancel_path_resolver = ->(_source) { "/checkout/payment" }
end
```

Return and cancellation URLs contain an opaque source token. They schedule a provider retrieval when a Nexi payment ID is known and then redirect locally; neither endpoint trusts browser parameters as financial state.

## Operating the integration

Admin payment views expose the provider payment ID, charge ID, latest provider-derived status, reconciliation time, and whether an operation needs reconciliation. The extension intentionally does not retain whole Nexi responses or webhook payloads because those documents may contain customer or payment-method data that Solidus does not need.

To enqueue reconciliation for one payment source:

```sh
bin/rails 'solidus_nexi:reconcile[42]'
```

To enqueue every known source with a stale or uncertain operation:

```sh
bin/rails solidus_nexi:reconcile
```

The all-sources task can only retrieve records that already have a Nexi payment ID. An uncertain creation without a stored ID must be recovered from an authenticated webhook carrying the order reference; do not create another checkout blindly.

See [Operations](docs/operations.md) for the state model, retry policy, secret rotation, and incident checklist. See [Migration from spree_dibs](docs/migration.md) before replacing a historical installation, and read [Security](SECURITY.md) before production deployment. Maintainers preparing the future RubyGems package should follow [Releasing](docs/releasing.md).

## Development

Set up the isolated bundle and dummy application, then run the suite:

```sh
bin/setup
bin/check-env
bin/rake extension:test_app
CI=1 bin/rake
bundle exec rubocop
bundle exec bundler-audit check --update --ignore CVE-2026-47736 CVE-2026-47737
```

Use `SOLIDUS_BRANCH=v4.6 RAILS_VERSION=7.2` to exercise the secondary Solidus target. The CI matrix is the source of truth for the complete supported Ruby/Solidus combinations.

Provider examples are sanitized under `spec/fixtures/nexi`. They make local tests deterministic but do not replace a real merchant test-environment run covering hosted completion, authenticated callbacks, repeated idempotent mutations, cancellation, refund, and lost-response reconciliation.

Run `NEXI_TEST_ENVIRONMENT=1 bundle exec rspec spec/provider` for the opt-in merchant API contract. It refuses live mode and creates one uncompleted disposable TEST checkout. The ordinary suite never contacts Nexi. See [Testing](docs/testing.md) for the Solidus system-test coverage and the hosted card/3D Secure release gate.

## Provider references

- [Nexi Checkout Payment API](https://developer.nexigroup.com/nexi-checkout/en-EU/api/payment-v1/)
- [Nexi hosted Checkout integration](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/web-integration/integrate-checkout-on-your-website-hosted/)
- [Nexi webhook integration](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/track-events-using-webhooks/)
- [Solidus payments and refunds](https://guides.solidus.io/next/advanced-solidus/payments-and-refunds/)

## License

Copyright © 2014–2026 Tobias Bohwalli and contributors. The legacy project's original copyright attribution is preserved in the [BSD 3-Clause License](LICENSE.md).
