import { createHash } from "node:crypto";
import type { DeploymentMode } from "@paperclipai/shared";
import { unprocessable } from "../errors.js";
import type {
  PreparedSecretVersion,
  SecretProviderClientErrorCode,
  SecretProviderHealthCheck,
  SecretProviderModule,
  SecretProviderValidationResult,
  SecretProviderVaultRuntimeConfig,
  SecretProviderWriteContext,
  StoredSecretVersionMaterial,
} from "./types.js";
import { SecretProviderClientError, isSecretProviderClientError } from "./types.js";

const VAULT_SCHEME = "hashicorp_vault_v1";
const DEFAULT_KV_MOUNT = "secret";
const DEFAULT_PATH_PREFIX = "paperclip";
const DEFAULT_SECRET_KEY = "value";
const VAULT_REQUEST_TIMEOUT_MS = 30_000;
const VAULT_TOKEN_EXPIRATION_SKEW_MS = 60_000;

interface VaultConfig {
  address: string;
  roleId: string;
  secretId: string;
  mount: string;
  namespace: string | null;
  pathPrefix: string;
}

interface VaultMaterial extends StoredSecretVersionMaterial {
  scheme: typeof VAULT_SCHEME;
  mount: string;
  path: string;
  key: string;
  source: "managed" | "external_reference";
}

interface VaultLoginResult {
  token: string;
  leaseDurationSeconds: number | null;
}

interface VaultGateway {
  login(input: { roleId: string; secretId: string }): Promise<VaultLoginResult>;
  readKv(input: { token: string; mount: string; path: string }): Promise<{ data: Record<string, unknown> }>;
  writeKv(input: {
    token: string;
    mount: string;
    path: string;
    data: Record<string, unknown>;
  }): Promise<{ version: number | null }>;
  health(): Promise<{ status: number }>;
}

interface CachedVaultToken {
  token: string;
  expiresAt: number;
  pending: Promise<VaultLoginResult> | null;
}

// Cache is keyed by address+roleId so distinct provider vaults do not share tokens.
const vaultTokenCache = new Map<string, CachedVaultToken>();

export function __resetVaultTokenCacheForTests() {
  vaultTokenCache.clear();
}

function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function asOptionalNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function sanitizePathSegment(input: string): string {
  return input
    .trim()
    .replace(/[^A-Za-z0-9/_.+=@-]+/g, "-")
    .replace(/\/+/g, "/")
    .replace(/^\/+|\/+$/g, "");
}

function buildExternalRef(mount: string, path: string, key: string): string {
  return `vault://${mount}/${path}#${key}`;
}

function parseExternalRef(externalRef: string): { mount: string; path: string; key: string } {
  const trimmed = externalRef.trim();
  const match = /^vault:\/\/([^/]+)\/(.+?)#([^#]+)$/.exec(trimmed);
  if (!match) {
    throw unprocessable(
      "HashiCorp Vault external reference must look like vault://{mount}/{path}#{key}",
    );
  }
  return { mount: match[1]!, path: match[2]!, key: match[3]! };
}

function buildManagedPath(config: VaultConfig, context: SecretProviderWriteContext | undefined): string {
  if (!context) {
    throw unprocessable("HashiCorp Vault provider requires secret context for managed values");
  }
  return [
    sanitizePathSegment(config.pathPrefix),
    sanitizePathSegment(context.companyId),
    sanitizePathSegment(context.secretKey),
  ]
    .filter(Boolean)
    .join("/");
}

function resolveManagedTarget(input: {
  config: VaultConfig;
  context: SecretProviderWriteContext | undefined;
  externalRef: string | null | undefined;
}): { mount: string; path: string; key: string } {
  const expectedPath = buildManagedPath(input.config, input.context);
  const ref = asOptionalNonEmptyString(input.externalRef);
  if (ref) {
    const parsed = parseExternalRef(ref);
    if (parsed.path !== expectedPath || parsed.mount !== input.config.mount) {
      throw unprocessable(
        "HashiCorp Vault managed secret ref drifted outside the derived company scope",
      );
    }
    return parsed;
  }
  return { mount: input.config.mount, path: expectedPath, key: DEFAULT_SECRET_KEY };
}

function readProviderVaultConfig(input: SecretProviderVaultRuntimeConfig): VaultConfig {
  if (input.provider !== "vault") {
    throw unprocessable("HashiCorp Vault provider received a mismatched provider vault");
  }
  if (input.status === "disabled") {
    throw unprocessable("HashiCorp Vault provider vault is disabled");
  }
  if (input.status === "coming_soon") {
    throw unprocessable("HashiCorp Vault provider vault runtime is locked while coming soon");
  }
  return buildVaultConfig({
    address: asOptionalNonEmptyString(input.config.address),
    mount: asOptionalNonEmptyString(input.config.mountPath),
    namespace: asOptionalNonEmptyString(input.config.namespace),
    pathPrefix: asOptionalNonEmptyString(input.config.secretPathPrefix),
  });
}

function loadVaultConfigFromEnv(): VaultConfig {
  return buildVaultConfig({
    address: asOptionalNonEmptyString(process.env.VAULT_ADDR),
    mount: asOptionalNonEmptyString(process.env.VAULT_KV_MOUNT),
    namespace: asOptionalNonEmptyString(process.env.VAULT_NAMESPACE),
    pathPrefix: asOptionalNonEmptyString(process.env.PAPERCLIP_SECRETS_VAULT_PREFIX),
  });
}

function buildVaultConfig(overrides: {
  address: string | null;
  mount: string | null;
  namespace: string | null;
  pathPrefix: string | null;
}): VaultConfig {
  return {
    address: (overrides.address ?? "").replace(/\/+$/, ""),
    roleId: asOptionalNonEmptyString(process.env.VAULT_APPROLE_ROLE_ID) ?? "",
    secretId: asOptionalNonEmptyString(process.env.VAULT_APPROLE_SECRET_ID) ?? "",
    mount: sanitizePathSegment(overrides.mount ?? DEFAULT_KV_MOUNT) || DEFAULT_KV_MOUNT,
    namespace: overrides.namespace,
    pathPrefix: sanitizePathSegment(overrides.pathPrefix ?? DEFAULT_PATH_PREFIX) || DEFAULT_PATH_PREFIX,
  };
}

function missingConfigFields(config: VaultConfig): string[] {
  const missing: string[] = [];
  if (!config.address) missing.push("VAULT_ADDR");
  if (!config.roleId) missing.push("VAULT_APPROLE_ROLE_ID (role_id)");
  if (!config.secretId) missing.push("VAULT_APPROLE_SECRET_ID (secret_id)");
  return missing;
}

function classifyVaultError(status: number | undefined, message: string): SecretProviderClientErrorCode {
  if (status === 404) return "not_found";
  if (status === 403) return "access_denied";
  if (status === 429) return "throttled";
  if (status === 400 || status === 422) return "invalid_request";
  if (status === 503 || status === 0) return "provider_unavailable";
  if (/ECONN|ENOTFOUND|ETIMEDOUT|fetch failed|network|timeout/i.test(message)) {
    return "provider_unavailable";
  }
  return "provider_error";
}

function vaultSafeMessage(code: SecretProviderClientErrorCode): string {
  switch (code) {
    case "access_denied":
      return "HashiCorp Vault denied the request. Check the AppRole policy for this provider vault.";
    case "throttled":
      return "HashiCorp Vault throttled the request. Wait and try again.";
    case "not_found":
      return "HashiCorp Vault could not find the requested secret.";
    case "invalid_request":
      return "HashiCorp Vault rejected the request.";
    case "provider_unavailable":
      return "HashiCorp Vault is unavailable right now.";
    case "provider_error":
    default:
      return "HashiCorp Vault request failed.";
  }
}

function normalizeVaultError(operation: string, error: unknown): never {
  if (isSecretProviderClientError(error)) throw error;
  const rawMessage = error instanceof Error ? error.message : String(error);
  const status = (error as { status?: number })?.status;
  const code = classifyVaultError(status, rawMessage);
  throw new SecretProviderClientError({
    code,
    provider: "vault",
    operation,
    message: vaultSafeMessage(code),
    rawMessage,
    cause: error,
  });
}

function asVaultMaterial(value: StoredSecretVersionMaterial): VaultMaterial {
  if (
    value &&
    typeof value === "object" &&
    value.scheme === VAULT_SCHEME &&
    typeof value.mount === "string" &&
    typeof value.path === "string" &&
    typeof value.key === "string" &&
    (value.source === "managed" || value.source === "external_reference")
  ) {
    return value as VaultMaterial;
  }
  throw unprocessable("Invalid HashiCorp Vault material");
}

function createManagedMaterial(mount: string, path: string, key: string): VaultMaterial {
  return { scheme: VAULT_SCHEME, mount, path, key, source: "managed" };
}

function createExternalReferenceMaterial(externalRef: string): PreparedSecretVersion {
  const normalized = externalRef.trim();
  const parsed = parseExternalRef(normalized);
  const fingerprint = sha256Hex(`${VAULT_SCHEME}:${normalized}`);
  return {
    material: { scheme: VAULT_SCHEME, ...parsed, source: "external_reference" },
    valueSha256: fingerprint,
    fingerprintSha256: fingerprint,
    externalRef: normalized,
    providerVersionRef: null,
  };
}

class VaultHttpGateway implements VaultGateway {
  constructor(private readonly config: VaultConfig) {}

  private headers(token?: string): Record<string, string> {
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (token) headers["X-Vault-Token"] = token;
    if (this.config.namespace) headers["X-Vault-Namespace"] = this.config.namespace;
    return headers;
  }

  private async call(
    operation: string,
    input: { method: string; path: string; token?: string; body?: unknown; expectStatus?: boolean },
  ): Promise<{ status: number; json: Record<string, unknown> }> {
    let response: Response;
    try {
      response = await fetch(`${this.config.address}${input.path}`, {
        method: input.method,
        headers: this.headers(input.token),
        body: input.body === undefined ? undefined : JSON.stringify(input.body),
        signal: AbortSignal.timeout(VAULT_REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      normalizeVaultError(operation, error);
    }
    const text = await response.text();
    const json = text ? (JSON.parse(text) as Record<string, unknown>) : {};
    if (input.expectStatus) return { status: response.status, json };
    if (!response.ok) {
      const errors = Array.isArray(json.errors) ? json.errors.join("; ") : response.statusText;
      const code = classifyVaultError(response.status, String(errors));
      throw new SecretProviderClientError({
        code,
        provider: "vault",
        operation,
        message: vaultSafeMessage(code),
        status: response.status,
        rawMessage: `${response.status}: ${errors}`,
      });
    }
    return { status: response.status, json };
  }

  async login(input: { roleId: string; secretId: string }): Promise<VaultLoginResult> {
    const { json } = await this.call("login", {
      method: "POST",
      path: "/v1/auth/approle/login",
      body: { role_id: input.roleId, secret_id: input.secretId },
    });
    const auth = json.auth as { client_token?: string; lease_duration?: number } | undefined;
    if (!auth?.client_token) {
      throw new SecretProviderClientError({
        code: "provider_error",
        provider: "vault",
        operation: "login",
        message: vaultSafeMessage("provider_error"),
        rawMessage: "AppRole login did not return a client token",
      });
    }
    return {
      token: auth.client_token,
      leaseDurationSeconds: typeof auth.lease_duration === "number" ? auth.lease_duration : null,
    };
  }

  async readKv(input: { token: string; mount: string; path: string }) {
    const { json } = await this.call("readKv", {
      method: "GET",
      path: `/v1/${input.mount}/data/${input.path}`,
      token: input.token,
    });
    const outer = json.data as { data?: Record<string, unknown> } | undefined;
    return { data: outer?.data ?? {} };
  }

  async writeKv(input: { token: string; mount: string; path: string; data: Record<string, unknown> }) {
    const { json } = await this.call("writeKv", {
      method: "POST",
      path: `/v1/${input.mount}/data/${input.path}`,
      token: input.token,
      body: { data: input.data },
    });
    const meta = json.data as { version?: number } | undefined;
    return { version: typeof meta?.version === "number" ? meta.version : null };
  }

  async health() {
    const { status } = await this.call("health", {
      method: "GET",
      path: "/v1/sys/health",
      expectStatus: true,
    });
    return { status };
  }
}

export function createHashiCorpVaultProvider(options?: {
  config?: VaultConfig;
  gateway?: VaultGateway;
}): SecretProviderModule {
  function resolveConfig(providerConfig?: SecretProviderVaultRuntimeConfig | null): VaultConfig {
    if (providerConfig) return readProviderVaultConfig(providerConfig);
    return options?.config ?? loadVaultConfigFromEnv();
  }

  function resolveGateway(config: VaultConfig): VaultGateway {
    return options?.gateway ?? new VaultHttpGateway(config);
  }

  async function getToken(config: VaultConfig, gateway: VaultGateway, forceRefresh: boolean): Promise<string> {
    const cacheKey = `${config.address}|${config.roleId}`;
    const now = Date.now();
    let cached = vaultTokenCache.get(cacheKey);
    if (!cached) {
      cached = { token: "", expiresAt: 0, pending: null };
      vaultTokenCache.set(cacheKey, cached);
    }
    if (!forceRefresh && cached.token && cached.expiresAt > now) return cached.token;
    if (!forceRefresh && cached.pending) return (await cached.pending).token;

    const login = gateway.login({ roleId: config.roleId, secretId: config.secretId });
    cached.pending = login;
    try {
      const result = await login;
      cached.token = result.token;
      cached.expiresAt = result.leaseDurationSeconds
        ? now + result.leaseDurationSeconds * 1000 - VAULT_TOKEN_EXPIRATION_SKEW_MS
        : now + 5 * 60_000;
      return result.token;
    } finally {
      cached.pending = null;
    }
  }

  // Runs op with a cached token; on 403 forces a single re-login and retries once.
  async function withToken<T>(
    config: VaultConfig,
    gateway: VaultGateway,
    op: (token: string) => Promise<T>,
  ): Promise<T> {
    const token = await getToken(config, gateway, false);
    try {
      return await op(token);
    } catch (error) {
      if (isSecretProviderClientError(error) && error.code === "access_denied") {
        vaultTokenCache.delete(`${config.address}|${config.roleId}`);
        return op(await getToken(config, gateway, true));
      }
      throw error;
    }
  }

  async function validateConfig(input?: {
    deploymentMode?: DeploymentMode;
    strictMode?: boolean;
    providerConfig?: SecretProviderVaultRuntimeConfig | null;
  }): Promise<SecretProviderValidationResult> {
    const warnings: string[] = [];
    if (input?.deploymentMode === "authenticated" && input.strictMode !== true) {
      warnings.push("Strict secret mode should be enabled for authenticated deployments");
    }
    const config = resolveConfig(input?.providerConfig);
    const missing = missingConfigFields(config);
    if (missing.length > 0) {
      return { ok: false, warnings: [`HashiCorp Vault provider requires: ${missing.join(", ")}`] };
    }
    return { ok: true, warnings };
  }

  async function healthCheck(input?: {
    deploymentMode?: DeploymentMode;
    strictMode?: boolean;
    providerConfig?: SecretProviderVaultRuntimeConfig | null;
  }): Promise<SecretProviderHealthCheck> {
    const config = resolveConfig(input?.providerConfig);
    const missing = missingConfigFields(config);
    const details = { address: config.address, mount: config.mount, pathPrefix: config.pathPrefix };
    if (missing.length > 0) {
      return {
        provider: "vault",
        status: "warn",
        message: `HashiCorp Vault provider is not ready: missing ${missing.join(", ")}.`,
        warnings: [`Missing required Vault config: ${missing.join(", ")}.`],
        details: { ...details, missingConfig: missing },
      };
    }
    try {
      const { status } = await resolveGateway(config).health();
      // Vault /sys/health: 200 ok, 429 standby, 472/473 DR/perf-standby, 501 not-initialized, 503 sealed.
      const reachableDegraded = new Set([429, 472, 473, 501, 503]);
      if (status === 200) {
        return {
          provider: "vault",
          status: "ok",
          message: "HashiCorp Vault is reachable, unsealed, and active.",
          details: { ...details, vaultStatus: status },
          backupGuidance: [
            "Back up Paperclip metadata separately from Vault-stored secret values.",
            "Restoring access requires the Paperclip database plus the same Vault mount and AppRole policy.",
          ],
        };
      }
      if (reachableDegraded.has(status)) {
        return {
          provider: "vault",
          status: "warn",
          message: "HashiCorp Vault is reachable but degraded (sealed, standby, or uninitialized).",
          warnings: [`Vault /sys/health returned ${status}; managed read/write will fail until it is active.`],
          details: { ...details, vaultStatus: status },
        };
      }
      return {
        provider: "vault",
        status: "warn",
        message: `HashiCorp Vault health returned an unexpected status ${status}.`,
        warnings: [`Vault /sys/health returned ${status}.`],
        details: { ...details, vaultStatus: status },
      };
    } catch (error) {
      return {
        provider: "vault",
        status: "warn",
        message: isSecretProviderClientError(error)
          ? "HashiCorp Vault is unavailable right now."
          : error instanceof Error
            ? error.message
            : String(error),
        warnings: ["Managed secret create/rotate/resolve calls will fail until Vault is reachable."],
        details,
      };
    }
  }

  return {
    id: "vault",
    descriptor() {
      const configured = missingConfigFields(resolveConfig()).length === 0;
      return {
        id: "vault",
        label: "HashiCorp Vault",
        requiresExternalRef: false,
        supportsManagedValues: true,
        supportsExternalReferences: true,
        configured,
      };
    },
    validateConfig,
    async createSecret(input) {
      const config = resolveConfig(input.providerConfig);
      const gateway = resolveGateway(config);
      const valueSha256 = sha256Hex(input.value);
      const target = resolveManagedTarget({ config, context: input.context, externalRef: null });
      try {
        const written = await withToken(config, gateway, (token) =>
          gateway.writeKv({ token, mount: target.mount, path: target.path, data: { [target.key]: input.value } }),
        );
        return {
          material: createManagedMaterial(target.mount, target.path, target.key),
          valueSha256,
          fingerprintSha256: valueSha256,
          externalRef: buildExternalRef(target.mount, target.path, target.key),
          providerVersionRef: written.version === null ? null : String(written.version),
        };
      } catch (error) {
        normalizeVaultError("createSecret", error);
      }
    },
    async createVersion(input) {
      const config = resolveConfig(input.providerConfig);
      const gateway = resolveGateway(config);
      const valueSha256 = sha256Hex(input.value);
      const target = resolveManagedTarget({ config, context: input.context, externalRef: input.externalRef });
      try {
        const written = await withToken(config, gateway, (token) =>
          gateway.writeKv({ token, mount: target.mount, path: target.path, data: { [target.key]: input.value } }),
        );
        return {
          material: createManagedMaterial(target.mount, target.path, target.key),
          valueSha256,
          fingerprintSha256: valueSha256,
          externalRef: buildExternalRef(target.mount, target.path, target.key),
          providerVersionRef: written.version === null ? null : String(written.version),
        };
      } catch (error) {
        normalizeVaultError("createVersion", error);
      }
    },
    async linkExternalSecret(input) {
      return createExternalReferenceMaterial(input.externalRef);
    },
    async resolveVersion(input) {
      const config = resolveConfig(input.providerConfig);
      const gateway = resolveGateway(config);
      const material = asVaultMaterial(input.material);
      const target = asOptionalNonEmptyString(input.externalRef)
        ? parseExternalRef(input.externalRef!.trim())
        : { mount: material.mount, path: material.path, key: material.key };
      try {
        const read = await withToken(config, gateway, (token) =>
          gateway.readKv({ token, mount: target.mount, path: target.path }),
        );
        const value = read.data[target.key];
        if (typeof value !== "string") {
          throw new SecretProviderClientError({
            code: "not_found",
            provider: "vault",
            operation: "resolveVersion",
            message: vaultSafeMessage("not_found"),
            status: 404,
            rawMessage: `Key "${target.key}" is absent at the Vault path`,
          });
        }
        return value;
      } catch (error) {
        normalizeVaultError("resolveVersion", error);
      }
    },
    async deleteOrArchive() {
      // KV-v2 destructive deletes are intentionally not performed from Paperclip; metadata
      // deletion is handled in the Paperclip DB and the underlying Vault path is left intact.
    },
    healthCheck,
  };
}

export const vaultProvider = createHashiCorpVaultProvider();
