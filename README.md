# Solidus Nexi

`solidus_nexi` is a Solidus-native integration for the current Nexi Checkout Payment API. It uses Nexi's hosted payment page so card details remain outside Solidus, then synchronizes authorization, capture, cancellation, and refund state through authenticated webhooks and provider retrieval.

This is the successor to `spree_dibs`, not an API-compatible upgrade of its historical ActiveMerchant gateway. The legacy code is preserved by the `v2.1.0` repository tag.

## Supported versions and scope

- Solidus 4.7 (primary) and 4.6 (secondary)
- Ruby 3.2 or newer
- one-time hosted Checkout payments
- authorization/reservation and optional immediate capture
- full capture, full cancellation, and full refund
- authenticated, deduplicated webhook processing
- durable mutation records and reconciliation after an ambiguous response

Partial capture and partial refund are deliberately rejected. Nexi requires exact order-item allocation for partial operations, and Solidus's amount-only gateway calls do not prove that allocation.

## Installation

Add the renamed gem to the application:

```ruby
gem "solidus_nexi", github: "futhr/solidus-nexi"
```

Then install and migrate:

```sh
bundle install
bin/rails generate solidus_nexi:install
bin/rails db:migrate
```

Set a 32-byte `SOLIDUS_PREFERENCES_MASTER_KEY` using the same secret-management system as the application. Nexi credentials are encrypted Solidus preferences backed by this key.

Configure these environment values before creating the payment method:

```sh
NEXI_CHECKOUT_API_KEY=replace-with-test-or-live-key
NEXI_CHECKOUT_WEBHOOK_SECRET=RandomAlphanumericSecret123
NEXI_CHECKOUT_ENVIRONMENT=test
NEXI_CHECKOUT_COUNTRY=SWE
NEXI_CHECKOUT_TERMS_URL=https://shop.example/terms
NEXI_CHECKOUT_MERCHANT_TERMS_URL=https://shop.example/privacy
NEXI_CHECKOUT_PUBLIC_BASE_URL=https://shop.example
```

The public base URL must be the HTTPS origin at which the mounted engine is reachable. The webhook is created per Nexi payment and uses an opaque, 8–64 character alphanumeric Authorization value.

To rotate webhook Authorization safely, move the old value to `NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET` and put the new value in `NEXI_CHECKOUT_WEBHOOK_SECRET`. New payments register the new value while callbacks from existing payments accept either value. Keep the previous value through the operational/refund lifetime of payments that registered it, then remove it; only one previous generation is accepted.

Create `SolidusNexi::PaymentMethod` in the Solidus admin, select the `nexi_checkout_env_credentials` preference source, associate it with the relevant stores, and choose whether `auto_capture` should ask Nexi Checkout to charge immediately after reservation. API keys and webhook secrets are intentionally not rendered back through the generic admin preference form.

## Starting hosted Checkout

The install generator mounts the engine at `/solidus_nexi`. A storefront can start or reuse a Checkout session with:

```http
POST /solidus_nexi/checkout_sessions
Content-Type: application/json

{
  "order_number": "R123456789",
  "guest_token": "the-order-guest-token",
  "payment_method_id": 4
}
```

JSON requests receive the Nexi `checkout_url`; browser form requests are redirected there. The guest token is always required, including for signed-in checkout, so an order number alone cannot initiate payment.

The browser return endpoint only schedules reconciliation and redirects using `config.return_path_resolver`. It never treats a customer redirect as proof of payment.

```ruby
SolidusNexi.configure do |config|
  config.public_base_url = ENV.fetch("NEXI_CHECKOUT_PUBLIC_BASE_URL")
  config.return_path_resolver = ->(source) { "/orders/#{source.payments.last.order.number}" }
  config.cancel_path_resolver = ->(_source) { "/checkout/payment" }
end
```

## Reliability model

Before any create, capture, cancellation, or refund request, the extension persists a unique logical operation. Capture and refund reuse the same persisted Nexi idempotency key on retry. Current Nexi references do not advertise idempotency for payment creation or cancellation, so those operations are never blindly replayed after an uncertain result.

Webhook event IDs are stored under a database unique constraint. The receiver verifies Authorization before mutation, persists only safe envelope metadata, enqueues reconciliation, and returns HTTP 200 exactly. Reconciliation retrieves the payment by Nexi `paymentId`; duplicate and out-of-order notifications therefore cannot regress a terminal Solidus payment.

Operational state is available in:

- `solidus_nexi_payment_sources` for provider IDs and authoritative cumulative amounts;
- `solidus_nexi_operations` for logical requests, idempotency keys, and unknown outcomes;
- `solidus_nexi_webhook_receipts` for event deduplication and processing status.

Run `bin/rails 'solidus_nexi:reconcile[42]'` for one source, or `bin/rails solidus_nexi:reconcile` to enqueue all stale/unknown operations that have a known Nexi payment ID.

Do not log or persist full Nexi payloads: retrieval responses may include consumer or masked-card data that this extension does not need.

## Migrating from `spree_dibs`

See [docs/migration.md](docs/migration.md). Old DIBS login/password settings and card sources are not migrated or assumed to be valid Nexi Checkout credentials.

## Development

```sh
bin/setup
bin/rake extension:test_app
bin/rake
bundle exec rubocop
```

Use `SOLIDUS_BRANCH=v4.6` and an appropriate `RAILS_VERSION` to exercise the secondary compatibility target. Provider fixtures are sanitized and live under `spec/fixtures/nexi`. A real sandbox smoke test additionally requires merchant-specific Nexi test credentials and cannot be replaced by fixture tests.

## License

Copyright © 2014–2026 Tobias Bohwalli, FreeRunning Technologies, and contributors. Released under the [BSD 3-Clause License](LICENSE.md).
