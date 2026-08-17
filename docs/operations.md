# Operating Solidus Nexi

This guide is for the people who support payments after deployment. It explains what the extension records, when it retries, and how to recover without creating duplicate financial actions.

## Source of truth

Nexi's retrieved payment resource is the financial source of truth. A browser return means only that the customer reached a return URL. A webhook means an event was delivered. In both cases, the extension retrieves the payment and validates its ID, order reference, amount, and currency before applying a Solidus state.

The adapter keeps terminal state from moving backwards when an older webhook arrives late. It also creates missing capture or refund records idempotently when Nexi completed an action whose local response was lost.

## Local records

Three extension-owned tables support operations:

| Table | What it answers |
| --- | --- |
| `solidus_nexi_payment_sources` | Which Nexi payment and charge belong to this Solidus payment, and what cumulative amounts were last retrieved? |
| `solidus_nexi_operations` | What logical mutation was requested, which idempotency key was used, and is its outcome known? |
| `solidus_nexi_webhook_receipts` | Which event IDs were received, queued, processed, ignored, or failed? |

The operation states are `pending`, `dispatched`, `succeeded`, `rejected`, `unknown`, `reconciled`, and `abandoned`. An `unknown` operation does not mean failure. It means the request may have reached Nexi but the application cannot safely claim success or retry without following the endpoint-specific policy. `abandoned` is used only for a checkout create whose provider identity is still unknown after Nexi's 48-hour checkout lifetime plus a safety margin.

## Retry policy

| Operation | Provider idempotency used | Behavior after an uncertain response |
| --- | --- | --- |
| Create payment | No | Do not replay while the checkout can still exist. Persist any returned payment ID before local validation and recover it through retrieval. With no returned ID or webhook, abandon only after the 48-hour checkout lifetime plus five minutes. |
| Charge | Yes | Retry only the same logical operation with the persisted key and unchanged amount. |
| Cancel | No | Do not replay. Retrieve the payment and reconcile before another operator action. |
| Refund | Yes | Retry only the same logical operation with the persisted key and unchanged charge/amount. |
| Retrieve | Not needed | Background jobs use bounded backoff for transport, provider-availability, and rate-limit failures. |

The adapter deliberately generates no hidden client retries for mutations. A timeout or server error after dispatch is preserved as an uncertain outcome instead of being reported as a clean failure.

## Webhook behavior

Webhooks are registered separately on every Nexi payment. The receiver:

1. finds the payment method named in the route;
2. authenticates the HTTP Authorization value;
3. validates and minimizes the event envelope;
4. inserts or finds the receipt under a unique event-ID constraint;
5. queues provider retrieval when work is required; and
6. returns HTTP 200 with an empty body.

Unknown event names are retained and acknowledged, then handled through the same provider-retrieval path. Failed or abandoned jobs can be queued again; processed and ignored receipts are terminal.

Deactivating a payment method blocks it from new checkout sessions but keeps its webhook endpoint available for existing payments. Deleting the payment method would remove that recovery path and should not be part of a routine cutover.

## Manual reconciliation

Enqueue a known payment source by local source ID:

```sh
bin/rails 'solidus_nexi:reconcile[42]'
```

Enqueue all sources whose provider state or known operations are stale or require reconciliation:

```sh
bin/rails solidus_nexi:reconcile
```

The task queues work; it does not perform provider calls inside the command. Make sure the Active Job backend is running.

The all-sources form excludes sources without a provider payment ID. When checkout creation has an uncertain result before that ID is known, wait for an authenticated webhook to recover it from the matching order reference. If Nexi returned an ID before local persistence failed, the operation retains it and reconciliation uses that exact ID. Creating a second checkout remains blocked while the original checkout can exist.

## Incident checklist

### A checkout cannot be created

Confirm that the payment method is active and available to the order's store. Check the API key, `test`/`live` setting, terms URL, public base URL, supported currency, and order total. A current unknown create operation must be reconciled rather than replaced. If no provider identity can be recovered, a normal retry is permitted only after the recorded operation reaches the safe abandonment cutoff.

### Webhooks receive 401

Compare the value registered on the affected Nexi payment with the current and previous configured webhook secrets. Do not log the inbound header. During normal rotation, keep the previous generation until callbacks for payments created with it are no longer needed.

### Webhooks repeat

Repeated delivery is expected until Nexi receives HTTP 200. Check the receipt's status and job backend. The unique event ID prevents duplicate receipts, while repeated reconciliation is designed to be idempotent.

### An operation remains unknown

If the source has a provider payment ID, enqueue reconciliation and inspect the next retrieved status. For create without a known ID, use the authenticated webhook recovery path. Do not manually mark the Solidus payment successful merely because the request was sent.

### Retrieval is rate-limited

Let the job's bounded retry policy honor the provider delay. Avoid repeatedly running the all-sources task: Nexi limits retrieval frequency for an individual payment.

## Routine checks

- Review operations where `reconciliation_required` is true.
- Review payment sources where `reconciliation_required` is true; this includes unexpected partial provider state and conflicts with a terminal local payment.
- Review failed webhook receipts and confirm the job backend is healthy.
- Watch sources whose `last_reconciled_at` is unexpectedly old during an active payment.
- Confirm that logs contain identifiers and result classes, not credentials or provider bodies.
- Remove an expired previous webhook secret after its operational window closes.
- Run the merchant test lifecycle again before changing credentials, checkout settings, or provider API assumptions.

## Current limitations

The extension supports full capture, full cancellation, and full refund only. It does not implement recurring payments, payment profiles, partial financial actions, or a provider reporting interface. A Nexi checkout session is treated as reusable locally for up to 48 hours. An unresolved creation with no provider identity is retained for five additional minutes before it can be safely abandoned; a known provider identity must always be reconciled.
