# Migration from spree_dibs

`solidus_nexi` replaces the historical synchronous DIBS/ActiveMerchant gateway with Nexi Checkout. Treat the cutover as a new payment-provider integration.

1. Deploy the new gem and migrations while the legacy gateway remains available for historical records.
2. Obtain Nexi Checkout test and live API credentials. Do not copy the old DIBS login/password values.
3. Configure a new high-entropy webhook Authorization secret, terms URLs, HTTPS public base URL, and `SOLIDUS_PREFERENCES_MASTER_KEY`.
4. Create and test a new `SolidusNexi::PaymentMethod` in Nexi's test environment.
5. Prove create, hosted completion, webhook receipt, full capture/cancel/refund, idempotent repeat, and lost-response reconciliation with the merchant test account.
6. Enable the new payment method for customers, then deactivate the historical `Spree::Gateway::Dibs` method.
7. Keep old payment records and the old gem version available for audit/history. Do not migrate card sources: `solidus_nexi` never stores reusable card data.

There is no process-global ActiveMerchant test mode, SSL override, two-digit card-year mutation, or compatibility alias for `Spree::Gateway::Dibs` in the new integration.
