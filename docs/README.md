# Solidus Nexi architecture and code map

This document maps the engine's runtime paths and ownership boundaries. Nexi's retrieved payment resource is the financial source of truth. Browser returns and webhook bodies trigger retrieval; neither can directly mark a Solidus payment successful.

## Code map

```mermaid
flowchart TB
  subgraph Host[Solidus host application]
    Routes[Engine routes]
    Views[Storefront and admin partials]
    Payment[Spree::Payment]
    Refund[Spree::Refund]
    Jobs[Active Job backend]
  end

  subgraph Engine[SolidusNexi Rails engine]
    Controllers[Checkout, return, and webhook controllers]
    Services[Checkout and financial services]
    Models[PaymentSource, Operation, WebhookReceipt]
    Processing[PaymentProcessing prepend]
    Reconciliation[ReconcilePayment and RefundReconciliation]
  end

  subgraph Protocol[Nexi protocol layer]
    Client[Client and NetHttpTransport]
    Payload[OrderSerializer and CheckoutPayload]
    Snapshot[PaymentSnapshot and StateMapper]
    Webhook[Webhook parser and authenticator]
  end

  Nexi[Nexi Checkout API]

  Views --> Routes --> Controllers
  Controllers --> Services
  Services --> Payload
  Services --> Models
  Processing --> Services
  Payment --> Processing
  Refund --> Processing
  Controllers --> Webhook
  Webhook --> Models
  Models --> Jobs
  Jobs --> Reconciliation
  Reconciliation --> Snapshot
  Services --> Client
  Reconciliation --> Client
  Client <--> Nexi
  Reconciliation --> Payment
  Reconciliation --> Refund
```

| Area | Responsibility |
| --- | --- |
| `lib/solidus_nexi` | Gem entry point, configuration, engine wiring, public URL policy, and install generator. |
| `lib/solidus_nexi/nexi` | HTTP client, transport policy, typed errors, money conversion, canonical JSON, provider snapshots, state mapping, and webhook validation. This layer has no Solidus models. |
| `app/controllers/solidus_nexi` | Guest-token-protected checkout creation, opaque return tokens, authenticated webhook intake, and bounded HTTP responses. |
| `app/services/solidus_nexi` | Order serialization, checkout creation, capture, cancellation, refund, and provider-to-local reconciliation. |
| `app/models/solidus_nexi` | Solidus payment-method adapter plus durable provider identity, operation intent, amount snapshot, and webhook receipt records. |
| `app/jobs/solidus_nexi` | Retried provider retrieval and recovery of failed or stale webhook work. |
| `app/views/spree` | Solidus storefront, API, and admin integration partials. |
| `db/migrate` | Portable payment-source, operation-journal, and webhook-inbox tables. |
| `spec` | Unit, service, request, system, generator, task, and opt-in Nexi TEST contract coverage. |

## Checkout creation

```mermaid
sequenceDiagram
  actor Customer
  participant Storefront
  participant Controller as CheckoutSessionsController
  participant CheckoutBuilder as CreateCheckout
  participant Database
  participant Nexi

  Customer->>Storefront: Select Nexi Checkout
  Storefront->>Controller: POST order number, guest token, payment method
  Controller->>Controller: Authenticate order and validate payment method
  Controller->>CheckoutBuilder: Build webhook, return, and cancel URLs
  CheckoutBuilder->>Database: Lock order and look for reusable checkout
  alt Open checkout exists
    Database-->>CheckoutBuilder: Existing source and hosted URL
  else New checkout required
    CheckoutBuilder->>Database: Create source, payment, and create-operation intent
    CheckoutBuilder->>Database: Claim operation dispatch
    CheckoutBuilder->>Nexi: POST payment payload
    Nexi-->>CheckoutBuilder: Payment ID and hosted URL
    CheckoutBuilder->>Database: Persist provider identity and mark operation succeeded
  end
  CheckoutBuilder-->>Controller: Checkout result
  Controller-->>Customer: 303 hosted redirect or JSON response
```

Checkout creation is serialized under the order lock. An existing unexpired hosted page is reused only when its amount and canonical serialized order context still match. A same-total change to item identity, description, tax allocation, or shipping blocks the stale page and late reconciliation until it expires safely. A create request has no Nexi idempotency key, so an uncertain result blocks another checkout until the original is recovered or its 48-hour provider lifetime plus safety margin has elapsed.

## Return and webhook reconciliation

```mermaid
sequenceDiagram
  participant Nexi
  participant Webhook as WebhooksController
  participant Inbox as WebhookReceipt
  participant Job as ProcessWebhookJob
  participant Reconcile as ReconcilePayment
  participant Payment as Solidus records

  Nexi->>Webhook: POST event with Authorization
  Webhook->>Webhook: Authenticate and parse bounded envelope
  Webhook->>Inbox: Insert under payment-method and event-ID uniqueness
  Inbox-->>Webhook: New or existing receipt
  Webhook->>Job: Enqueue work when required
  Webhook-->>Nexi: 200 OK
  Job->>Inbox: Claim receipt under row lock
  Job->>Reconcile: Provider payment ID and event references
  Reconcile->>Nexi: GET complete payment
  Nexi-->>Reconcile: Current payment resource
  Reconcile->>Reconcile: Validate identity, order, amount, currency, and event IDs
  Reconcile->>Payment: Apply monotonic state and missing financial records
  Reconcile->>Inbox: Mark processed or ignored
```

The browser return path also enqueues `ReconcilePaymentJob` before redirecting to the local storefront. Duplicate events are safe: the receipt's unique constraint deduplicates intake, and reconciliation compares cumulative provider amounts with existing Solidus capture and refund records.

## Financial mutations

```mermaid
flowchart TD
  Request[Solidus capture, void, or credit] --> Validate[Require full supported amount and provider identity]
  Validate --> Intent[Create or find immutable Operation intent]
  Intent --> Claim{Claim dispatch under lock?}
  Claim -- No --> Existing{Already successful?}
  Existing -- Yes --> Result[Return recorded provider identity]
  Existing -- No --> Busy[Raise operation in progress or reconciliation required]
  Claim -- Yes --> Provider[Call Nexi once]
  Provider -->|Definitive rejection| Rejected[Mark rejected]
  Provider -->|Rate limited before known outcome| Pending[Return operation to pending]
  Provider -->|Timeout, transport ambiguity, or malformed success| Unknown[Mark unknown and enqueue reconciliation]
  Provider -->|Success| Persist[Persist provider IDs and succeeded or accepted status]
  Persist --> Result
  Unknown --> Retrieve[Retrieve payment state]
  Retrieve --> Reconciled[Reconcile operation and Solidus records]
```

Capture and refund persist Nexi idempotency keys per logical operation and may replay only that unchanged intent. Cancellation and checkout creation are not replayed after an uncertain outcome. Refund initiation is asynchronous: a successful POST is `accepted` until retrieval reports completion or failure.

## Local data model

```mermaid
erDiagram
  SPREE_PAYMENT_METHOD ||--o{ PAYMENT_SOURCE : configures
  SPREE_ORDER ||--o{ SPREE_PAYMENT : contains
  SPREE_PAYMENT_METHOD ||--o{ SPREE_PAYMENT : processes
  PAYMENT_SOURCE ||--o{ SPREE_PAYMENT : backs
  SPREE_PAYMENT ||--o{ OPERATION : journals
  SPREE_PAYMENT ||--o{ SPREE_REFUND : records
  SPREE_PAYMENT_METHOD ||--o{ WEBHOOK_RECEIPT : receives

  PAYMENT_SOURCE {
    string provider_payment_id
    string provider_charge_id
    string return_token
    integer reserved_amount_minor
    integer charged_amount_minor
    integer refunded_amount_minor
    integer cancelled_amount_minor
    boolean reconciliation_required
  }
  OPERATION {
    string kind
    string status
    string logical_reference
    string request_fingerprint
    string idempotency_key
    string provider_request_id
    boolean reconciliation_required
  }
  WEBHOOK_RECEIPT {
    string event_id
    string event_name
    string provider_payment_id
    string status
    integer attempts
  }
```

`PaymentSource` holds the latest validated provider snapshot. `Operation` is an immutable-intent journal for external side effects. `WebhookReceipt` is a durable inbox; it stores the minimal event envelope rather than the complete request body.

## Payment state

```mermaid
stateDiagram-v2
  [*] --> checkout
  checkout --> processing
  checkout --> pending: full reservation retrieved
  checkout --> completed: full charge retrieved
  checkout --> void: full cancellation retrieved
  checkout --> failed: exact provider failure
  processing --> pending
  processing --> completed
  processing --> void
  processing --> failed
  pending --> completed
  pending --> void
  pending --> failed
  completed --> completed: refund outcome updates records
```

Terminal payment states never move backwards. Unexpected partial amounts, mismatched references, and ambiguous refund outcomes leave the source flagged for reconciliation instead of guessing a state.

## Reliability boundaries

- Every provider response is parsed as a bounded JSON object and identifiers are format-checked before persistence.
- Provider mutations have no hidden transport retries. Unknown outcomes become durable operation state.
- The application stores minor currency units at the provider boundary and validates the supported currency set.
- Webhook Authorization accepts the current and one previous secret using constant-time comparison.
- Return tokens are random and independent of provider IDs; checkout creation requires the Solidus order guest token.
- Logs contain operation names, result classes, duration, and provider request IDs—not credentials, webhook Authorization values, or provider bodies.
- Background retrieval uses bounded retries, honors a safe `Retry-After` range, and can recover failed or stale webhook receipts from the database.

See [Operations](operations.md) for retry and incident procedures and [Testing](testing.md) for the executable coverage of these boundaries.
