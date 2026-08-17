# Testing Solidus Nexi

The suite follows Solidus's recommended balance: unit and integration examples cover success, failure, and race paths; Capybara covers the customer handoff and the admin view; merchant-provider checks remain explicit and opt-in.

## Local and CI suite

```sh
bin/setup
bin/check-env
bin/rake extension:test_app
CI=1 bin/rake
bundle exec rubocop
```

`bin/check-env` prints variable names only. It requires a 32-byte `SOLIDUS_PREFERENCES_MASTER_KEY`, Test Secret API key, alphanumeric webhook secrets, supported environment/country values, HTTPS terms pages, and a pathless public HTTPS application origin. Leave `NEXI_CHECKOUT_PREVIOUS_WEBHOOK_SECRET` empty unless a secret rotation is in progress.

Normal specs block external HTTP. Provider responses under `spec/fixtures/nexi` cover API errors, financial states, malformed responses, duplicate webhooks, unknown outcomes, and idempotent reconciliation. System specs render the shipped Solidus storefront partial, exercise the hosted redirect handoff, and render provider state in the real Solidus admin payment page.

CI runs the primary Solidus target against SQLite, PostgreSQL 16, and MySQL 8.4. The database jobs build a fresh host application and run every extension migration before executing the complete suite.

## Merchant API contract

Run this only with test credentials:

```sh
NEXI_TEST_ENVIRONMENT=1 bundle exec rspec spec/provider
```

The provider specs refuse any `NEXI_CHECKOUT_ENVIRONMENT` other than `test`. They verify the merchant key with a read-only request, create one disposable 100 SEK hosted checkout, and retrieve it through Nexi's Payment API. The checkout is not completed, charged, or subscribed to webhooks. It remains visible in the TEST portal until Nexi expires it.

These specs are excluded from ordinary CI. Do not put merchant credentials in GitHub repository secrets merely to make pull-request checks call Nexi.

## Hosted payment release gate

The third-party card and 3D Secure screens are a manual release gate. Before running it, point `NEXI_CHECKOUT_PUBLIC_BASE_URL` at the mounted application through a public HTTPS endpoint and run the Active Job worker. A homepage or unrelated domain is not sufficient: Nexi must reach `/solidus_nexi/webhooks/:payment_method_id` and receive HTTP 200.

Use Nexi's published success card with a future expiry and any three-digit CVC. Complete these flows in the TEST portal and verify both Nexi and Solidus after every step:

1. With auto-capture off, complete checkout, receive a reservation webhook, reconcile to `pending`, capture once, and reconcile repeatedly without a duplicate capture.
2. With auto-capture off, complete another reservation, cancel it, and reconcile to `void`.
3. With auto-capture on, complete checkout, reconcile to `completed`, refund the full amount, receive refund completion, and retain one local refund with the provider transaction ID.
4. Repeat checkout with Nexi's reservation-failure and charge-failure cards. Confirm no successful Solidus financial state is recorded.
5. Exercise Nexi's documented delayed-response amount and a reason-code amount. Confirm a timeout is treated as unknown, a new checkout is blocked, and the original payment is recovered by webhook/reconciliation.
6. Replay one valid webhook and send one invalid Authorization value. Confirm the valid event is deduplicated and the invalid request changes no records.

Record the Solidus order/payment numbers, Nexi payment IDs, final states, and test date for the release evidence. Never record cardholder fields, API keys, or webhook Authorization values.

Provider references:

- [Nexi test environment](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/test-environment/)
- [Nexi test card processing](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/test-card-processing/)
- [Nexi hosted Checkout](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/web-integration/integrate-checkout-on-your-website-hosted/)
- [Nexi webhooks](https://developer.nexigroup.com/nexi-checkout/en-EU/docs/track-events-using-webhooks/)
- [Solidus testing guidance](https://guides.solidus.io/4.6/getting-started/testing-solidus/)
