# Security policy

`solidus_nexi` handles payment orchestration and provider credentials. Treat reports involving authentication, payment state, idempotency, callback processing, or unintended data retention as security-sensitive even when no card number is exposed.

## Supported versions

Until the first stable RubyGems release, security fixes are made only on the latest `0.1.0` prerelease line. The historical `spree_dibs` releases are archived and unsupported.

## Reporting a vulnerability

Send a private report to `hi@futhr.io`. Please include the affected version or commit, the smallest safe reproduction, the expected and observed behavior, and the practical impact.

Do not open a public issue containing:

- Nexi API keys or webhook Authorization values;
- `SOLIDUS_PREFERENCES_MASTER_KEY`;
- customer, order, card, or wallet data;
- raw provider responses or webhook bodies; or
- instructions that would let another person reproduce an active exploit.

Use synthetic identifiers and sanitized payloads. If a secret was included accidentally, rotate it before sending the report.

## Security boundary

The integration uses Nexi's hosted checkout so raw PAN and CVV data remain on Nexi-controlled pages. The extension stores provider payment, charge, refund, event, and request identifiers together with cumulative minor-unit amounts and local operation state. It does not intentionally store complete provider resources or webhook bodies.

Nexi API keys and webhook credentials are encrypted Solidus preferences protected by the host application's 32-byte preferences master key. The API key is sent only to Nexi's HTTPS API endpoint. Callback credentials are compared safely before any receipt or payment state is written.

Webhook event IDs are protected by a database unique constraint. Valid events are acknowledged with HTTP 200 and processed asynchronously; financial state is derived from a provider retrieval rather than trusted directly from the callback or browser return.

## Deployment expectations

- Keep the preferences master key and Nexi credentials in the deployment secret manager.
- Use separate credentials for test and live environments.
- Serve checkout returns and webhooks over public HTTPS.
- Keep Rails parameter filtering enabled for API keys and both webhook-secret generations.
- Restrict database and job-console access because operation records contain payment identifiers.
- Retain only the logs needed for operations, and never add request/response body logging around the Nexi client.
- Rotate a suspected webhook secret by moving the old value to the previous-secret slot only when it is still safe to accept; remove compromised values as soon as the affected payments have another recovery path.
- Keep Solidus, Rails, Ruby, and this gem on supported security releases.

See [Operations](docs/operations.md) for the incident and reconciliation workflow.
