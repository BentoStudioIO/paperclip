# HashiCorp Vault Provider

Operational contract for the `vault` secret provider (KV-v2 + AppRole).

## Scope

- Backing store for Paperclip-managed secrets when the deployment runs HashiCorp Vault.
- Source of truth for secret values is Vault (KV-v2), not Postgres. Paperclip stores
  only metadata needed for ownership, bindings, version selection, audit, and runtime resolution.
- Vault bootstrap credentials (AppRole `role_id` / `secret_id`) are deployment/runtime
  credentials, not Paperclip-managed company secrets.
- Linked external references are metadata-only: Paperclip stores a `vault://...#key`
  pointer; it never copies plaintext into Postgres.

## Bootstrap Trust Model

Paperclip cannot use `company_secrets` to unlock the Vault provider that stores those
secrets. The AppRole credentials must exist in the process environment before the
Paperclip server starts:

- `VAULT_ADDR` — e.g. `https://vault.bentostudio.io`
- `VAULT_APPROLE_ROLE_ID`
- `VAULT_APPROLE_SECRET_ID`
- `VAULT_KV_MOUNT` (optional, default `secret`)
- `VAULT_NAMESPACE` (optional, Vault Enterprise namespaces)
- `PAPERCLIP_SECRETS_VAULT_PREFIX` (optional, default `paperclip`)

Select the provider at runtime with `PAPERCLIP_SECRETS_PROVIDER=vault`.

## Auth

AppRole login: `POST {VAULT_ADDR}/v1/auth/approle/login {role_id, secret_id}` →
`auth.client_token`. The token is cached per `address|role_id` and honored until
`lease_duration` (minus a 60s skew). On a `403` from any KV call the provider deletes
the cached token, re-logs in once, and retries. Subsequent calls send `X-Vault-Token`
(and `X-Vault-Namespace` when configured).

## Path Convention & externalRef

Paperclip-managed values live under `{mount}/{prefix}/{companyId}/{secretKey}` —
e.g. `secret/paperclip/company-1/openai-api-key`. The Vault `paperclip` policy must be
scoped to `{mount}/data/{prefix}/*` (default `secret/data/paperclip/*`).

KV-v2 stores multiple keys per path; Paperclip writes the value under the key `value`.
The `externalRef` encodes mount + path + key:

```
vault://{mount}/{path}#{key}
vault://secret/paperclip/company-1/openai-api-key#value
```

Managed writes/reads derive the path from the secret context and reject any stored
ref that drifts outside the derived company scope.

## Operations

- `createSecret` / `createVersion` — KV-v2 write `POST {addr}/v1/{mount}/data/{path}
  {"data":{value}}`. KV-v2 versions automatically; `providerVersionRef` is the returned
  KV version number.
- `resolveVersion` — KV-v2 read `GET {addr}/v1/{mount}/data/{path}` → `.data.data.{key}`.
- `linkExternalSecret` — stores the `vault://...#key` pointer as metadata only.
- `deleteOrArchive` — no destructive Vault delete; metadata removal is handled in the
  Paperclip DB and the Vault path is left intact.

## Error Mapping

- `404` → `secret_not_found`
- `403` → `access_denied` (triggers one re-login + retry)
- `429` → `throttled`; `400/422` → `invalid_request`
- network / `503` → `provider_unavailable`; otherwise `provider_error`

Raw Vault error text is captured on `rawMessage`; the user-facing `message` is generic.

## Health

`GET {addr}/v1/sys/health`:

- `200` → `ok` (unsealed, active)
- `429` (standby), `472`/`473` (DR / perf standby), `501` (uninitialized), `503` (sealed)
  → `warn` (reachable but degraded — managed read/write will fail until active)
- unreachable → `warn` (never `error`, to match provider-vault health UX)
