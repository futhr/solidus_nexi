# Solidus Nexi

[![Test](https://github.com/futhr/solidus_nexi/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/futhr/solidus_nexi/actions/workflows/test.yml)
[![codecov](https://codecov.io/github/futhr/solidus_nexi/graph/badge.svg?token=6H54X0YWAG)](https://codecov.io/github/futhr/solidus_nexi)
[![Ruby](https://img.shields.io/badge/Ruby-3.2%2B-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Solidus](https://img.shields.io/badge/Solidus-4.6%E2%80%934.7-2B59C3)](https://solidus.io/)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE.md)

`solidus_nexi` adds Nexi Checkout to Solidus. Card and wallet details stay on Nexi's hosted checkout; the store keeps only the provider identifiers and financial state needed to operate the payment.

This is an unreleased rewrite of `spree_dibs` under the `SolidusNexi` namespace. It is not API-compatible with the old gateway.

## Support

| Component | Supported |
| --- | --- |
| Solidus | 4.7; 4.6 as a secondary target |
| Rails | 7.2 |
| Ruby | 3.2–4.0 |
| Databases | SQLite, PostgreSQL, MySQL |

The gem supports hosted one-time payments, authorization, optional auto-capture, full capture, full cancellation, full refund, authenticated webhooks, and reconciliation. It supports CHF, CZK, DKK, EUR, GBP, NOK, PLN, SEK, and USD.

Subscriptions, stored payment profiles, embedded checkout, and partial financial operations are not supported.

## Installation

Until the first RubyGems release, install from GitHub:

```ruby
gem "solidus_nexi", github: "futhr/solidus_nexi"
```

Then install the engine and its migrations:

```sh
bundle install
bin/rails generate solidus_nexi:install --auto-run-migrations
```

The generator mounts the engine at `/solidus_nexi` and creates `config/initializers/solidus_nexi.rb`. The host application must provide a 32-byte `SOLIDUS_PREFERENCES_MASTER_KEY` so Solidus can encrypt provider credentials.

See [Configuration](docs/configuration.md) for environment variables, payment-method setup, secret rotation, and custom storefront paths.

## Nexi TEST sandbox

A [Nexi Checkout Portal test account](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/create-a-checkout-portal-account/) is free. Copy the **test Secret API key** from **Company → Integration**. This hosted flow does not use the portal Checkout Key.

For repository development:

```sh
bin/setup
# edit .env and add the TEST Secret API key
NEXI_TEST_ENVIRONMENT=1 bundle exec rspec spec/provider
```

The provider contract creates and retrieves one uncompleted 100 SEK TEST checkout. The `.example` HTTPS URLs are sufficient for this isolated API check because no card is entered and no callback is expected.

A complete hosted-card test is different: Nexi must be able to reach the engine's webhook route, so the local app needs a public HTTPS tunnel. `NEXI_CHECKOUT_TERMS_URL` is a required Nexi checkout field; in TEST it may point to a sandbox page. A real merchant terms page is needed only when preparing the live store.

Run `bin/check-env` when testing the complete hosted flow. It deliberately rejects placeholder and private URLs. The release checklist is in [Testing](docs/testing.md).

## Storefront

The engine includes Solidus payment partials. A headless storefront can start or reuse a checkout with:

```http
POST /solidus_nexi/checkout_sessions
Content-Type: application/json

{
  "order_number": "R123456789",
  "guest_token": "the-order-guest-token",
  "payment_method_id": 4
}
```

The guest token is always required. Browser requests receive a `303` redirect to Nexi; JSON requests receive the local payment number, provider payment ID, hosted URL, and reuse status.

## Operations

Reconcile one source or every source requiring attention:

```sh
bin/rails 'solidus_nexi:reconcile[42]'
bin/rails solidus_nexi:reconcile
bin/rails solidus_nexi:recover_webhooks
```

Browser returns and webhook payloads are never treated as proof of payment. Financial state changes only after the complete payment is retrieved from Nexi.

## Documentation

- [Architecture and code map](docs/README.md)
- [Configuration](docs/configuration.md)
- [Testing](docs/testing.md)
- [Operations](docs/operations.md)
- [Migration from `spree_dibs`](docs/migration.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Releasing](docs/releasing.md)
- [Changelog](CHANGELOG.md)

## Development

```sh
bin/setup
bin/rake extension:test_app
CI=1 bin/rake
bin/zeitwerk-check
bundle exec rubocop
bundle exec bundler-audit check --update --ignore CVE-2026-47736 CVE-2026-47737
```

The normal suite never contacts Nexi. Provider tests are explicit and restricted to the TEST environment.

## License

[BSD 3-Clause](LICENSE.md). Copyright © 2014–2026 Tobias Bohwalli and contributors.
