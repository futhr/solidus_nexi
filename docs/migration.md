# Migrating from `spree_dibs`

`solidus_nexi` is a successor to the old DIBS gateway, not an in-place upgrade. The provider contract, checkout experience, credentials, database records, and Ruby namespace all change. Plan the cutover as a new payment integration alongside a separate Solidus platform upgrade.

The final legacy source is preserved by the `v2.1.0` tag. That tag is the rollback and audit reference for the old code; it is not a compatibility layer inside the new gem.

## What changes

| Legacy `spree_dibs` | New `solidus_nexi` |
| --- | --- |
| `Spree::Gateway::Dibs` | `SolidusNexi::PaymentMethod` |
| ActiveMerchant DIBS fork | Direct Nexi Checkout Payment API client |
| Login/password preferences | Nexi API key and webhook Authorization secret |
| Synchronous card gateway | Nexi-hosted checkout plus asynchronous reconciliation |
| Process-global test behavior | Test/live selection on each payment method |
| Reusable card-shaped source assumptions | Non-reusable hosted checkout source |
| Legacy SSL workaround | Verified modern HTTPS transport |

The new extension does not migrate card sources, DIBS credentials, transaction IDs, or payment-method rows. It never aliases `Spree::Gateway::Dibs` to the new class.

## Before the cutover

1. Inventory every active DIBS payment method and the historical records that still need to be viewable for support, accounting, refunds, or audits.
2. Decide how the host application will retain access to old STI records whose type is `Spree::Gateway::Dibs`. Keep an archival compatibility package or application-owned read-only class if those rows must still be loaded. Do not repoint them to `SolidusNexi::PaymentMethod`.
3. Obtain separate Nexi Checkout test and live integration keys. Old DIBS login/password values are not assumed to work with the current API.
4. Create a high-entropy webhook Authorization secret, a 32-byte `SOLIDUS_PREFERENCES_MASTER_KEY`, public HTTPS terms pages, and the public HTTPS origin for callbacks.
5. Back up the application database and record the current payment-method configuration before changing production traffic.

Historical refunds are an operational decision. If an old payment still needs to be refunded through the legacy provider path, retain the old application or another approved operational path until its refund window has closed.

## Staged migration

### 1. Install the new extension

Install `solidus_nexi`, run its generator, and migrate the three new tables. The migrations do not rewrite existing Spree or Solidus payment data.

```sh
bin/rails generate solidus_nexi:install --auto-run-migrations
```

### 2. Configure a new payment method

Create a new `SolidusNexi::PaymentMethod`; do not reuse or retag the legacy row. Start with Nexi's test environment, associate the method only with a test store when possible, and leave the historical DIBS method unchanged.

### 3. Prove the merchant test lifecycle

Use the merchant account to complete all of the following before production:

- create a payment and follow the hosted redirect;
- receive and authenticate a reservation or charge webhook;
- deliver the same event ID twice without duplicating local effects;
- capture with one persisted idempotency key and repeat that intent safely;
- cancel an uncaptured reservation;
- refund a full charge and repeat that intent safely;
- lose a simulated response and reconcile the provider result; and
- confirm that secrets and customer/card payloads are absent from logs and database records.

### 4. Enable customer traffic

Enable the Nexi method for the intended stores. Disable the old DIBS method for new checkouts only after the test lifecycle is complete. Keep the historical data and its access strategy in place for the period defined by the business.

### 5. Observe the cutover

Monitor unknown operations, webhook failures, provider status, and reconciliation age during the first production transactions. Use the reconciliation task only for sources with known Nexi payment IDs. Never resolve an uncertain creation by blindly creating another provider payment.

## Rollback

Disabling `SolidusNexi::PaymentMethod` stops new hosted checkouts while authenticated callbacks for existing Nexi payments continue to work. That behavior lets operators drain in-flight payments without opening new ones.

A rollback must not delete the new source, operation, or webhook-receipt tables. Those records are needed to reconcile payments already created at Nexi. Restore the previous customer payment option only if its provider credentials and historical runtime remain safe to operate.

## What must not return

Do not carry forward the old ActiveMerchant fork, process-global gateway mode, SSL protocol override, two-digit card-year mutation, credential fixtures, or a constant alias that makes old payments appear to be new Nexi payments.
