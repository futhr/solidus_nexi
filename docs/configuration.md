# Configuring Solidus Nexi

The install generator creates `config/initializers/solidus_nexi.rb`, mounts the engine at `/solidus_nexi`, and copies the migrations. Provider credentials are encrypted Solidus payment-method preferences; environment variables seed those preferences without exposing them in the admin form.

## Environment

| Variable | Required | Purpose |
| --- | --- | --- |
| `SOLIDUS_PREFERENCES_MASTER_KEY` | Yes | Exactly 32 secret bytes used by Solidus to encrypt credentials. |
| `NEXI_CHECKOUT_API_KEY` | Yes | Nexi Secret API key for the selected TEST or LIVE environment. This is not the portal Checkout Key. |
| `NEXI_CHECKOUT_WEBHOOK_SECRET` | Yes | An 8–64 character alphanumeric value sent as the webhook Authorization value. |
| `NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET` | No | Previous webhook secret during one rotation window. |
| `NEXI_CHECKOUT_ENVIRONMENT` | No | `test` by default; use `live` only after merchant verification. |
| `NEXI_CHECKOUT_COUNTRY` | No | ISO 3166-1 alpha-3 checkout country; defaults to `SWE`. |
| `NEXI_CHECKOUT_TERMS_URL` | Yes | HTTPS terms URL required in the Nexi checkout payload. |
| `NEXI_CHECKOUT_MERCHANT_TERMS_URL` | No | Optional HTTPS merchant/privacy terms URL. |
| `NEXI_CHECKOUT_PUBLIC_BASE_URL` | Yes | Public HTTPS origin used to build webhook, return, and cancel URLs. It must not contain a path, query, or fragment. |

The generated initializer fails at boot when only one credential is present or when the environment is invalid. If neither credential is present, it does not register static preferences; configure the payment method through another secure Solidus preference source instead.

For repository development, `bin/setup` copies `.env.example` to `.env` when needed. Dotenv is loaded only by development and test helpers. Production applications should inject secrets through their deployment platform or secret manager.

## TEST sandbox URLs

The opt-in provider contract creates and retrieves an uncompleted checkout. Reserved `.example` HTTPS values are enough for that check because no browser or callback reaches them:

```sh
NEXI_TEST_ENVIRONMENT=1 bundle exec rspec spec/provider
```

A complete hosted-card run needs a public HTTPS tunnel to the local application. Replace the placeholder origin with the tunnel origin, point the terms URL at a reachable sandbox page, start the job worker, and run `bin/check-env`. LIVE configuration must use the store's real public origin and merchant terms.

## Payment method

After installing the engine, create `SolidusNexi::PaymentMethod` in Solidus Admin and assign it to the required stores. Choose TEST or LIVE through the standard Solidus `server` and `test_mode` preferences, set auto-capture as required, and confirm the method is active.

When environment credentials are present, the generated initializer registers a static preference set named `nexi_checkout_env_credentials`. Secrets are deliberately excluded from the payment method's admin preference form.

Supported payment currencies are CHF, CZK, DKK, EUR, GBP, NOK, PLN, SEK, and USD. Nexi's checkout country is independent of the order currency.

## Custom storefront paths

The default return and cancel destinations are `/checkout/confirm` and `/checkout/payment`. Override them for a headless or custom storefront:

```ruby
SolidusNexi.configure do |config|
  config.return_path_resolver = lambda do |source|
    "/orders/#{source.payments.first.order.number}"
  end
  config.cancel_path_resolver = ->(_source) { "/checkout/payment" }
end
```

Resolvers receive the `SolidusNexi::PaymentSource`. They must return a local path; the return controller rejects cross-host redirects.

## Secret rotation

Set the new value in `NEXI_CHECKOUT_WEBHOOK_SECRET` and keep the immediately previous value in `NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET`. New checkouts register the new value while callbacks created during the preceding generation remain valid. Remove the previous value after that checkout window has expired and outstanding payments have been reconciled.

API key rotation is provider-controlled. Replace the encrypted preference, verify it in TEST or through a controlled LIVE check, and do not remove the old merchant credential until in-flight operational work is accounted for.
