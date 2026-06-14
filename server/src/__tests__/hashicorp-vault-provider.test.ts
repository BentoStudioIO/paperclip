import { afterEach, describe, expect, it, vi } from "vitest";
import {
  createHashiCorpVaultProvider,
  __resetVaultTokenCacheForTests,
} from "../secrets/hashicorp-vault-provider.js";
import { SecretProviderClientError } from "../secrets/types.js";

const BASE_CONFIG = {
  address: "https://vault.example.com",
  roleId: "role-1",
  secretId: "secret-1",
  mount: "secret",
  namespace: null,
  pathPrefix: "paperclip",
} as const;

const WRITE_CONTEXT = {
  companyId: "company-1",
  secretKey: "openai-api-key",
  secretName: "OpenAI API Key",
  version: 1,
};

afterEach(() => {
  __resetVaultTokenCacheForTests();
  vi.restoreAllMocks();
});

describe("hashicorpVaultProvider", () => {
  it("logs in via AppRole, caches the token, and reuses it across calls", async () => {
    const calls: string[] = [];
    let loginCount = 0;
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG },
      gateway: {
        async login() {
          loginCount += 1;
          calls.push("login");
          return { token: "vault-token-1", leaseDurationSeconds: 3600 };
        },
        async readKv(input) {
          calls.push(`readKv:${input.token}:${input.path}`);
          return { data: { value: "resolved-value" } };
        },
        async writeKv() {
          throw new Error("not used");
        },
        async health() {
          throw new Error("not used");
        },
      },
    });

    const first = await provider.resolveVersion({
      material: { scheme: "hashicorp_vault_v1", mount: "secret", path: "paperclip/company-1/openai-api-key", key: "value", source: "managed" },
      externalRef: "vault://secret/paperclip/company-1/openai-api-key#value",
    });
    const second = await provider.resolveVersion({
      material: { scheme: "hashicorp_vault_v1", mount: "secret", path: "paperclip/company-1/openai-api-key", key: "value", source: "managed" },
      externalRef: "vault://secret/paperclip/company-1/openai-api-key#value",
    });

    expect(first).toBe("resolved-value");
    expect(second).toBe("resolved-value");
    expect(loginCount).toBe(1);
    expect(calls).toEqual([
      "login",
      "readKv:vault-token-1:paperclip/company-1/openai-api-key",
      "readKv:vault-token-1:paperclip/company-1/openai-api-key",
    ]);
  });

  it("re-logs in once when a cached token is rejected with 403", async () => {
    const tokens: string[] = [];
    let loginCount = 0;
    let readCount = 0;
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG },
      gateway: {
        async login() {
          loginCount += 1;
          return { token: `vault-token-${loginCount}`, leaseDurationSeconds: 3600 };
        },
        async readKv(input) {
          tokens.push(input.token);
          readCount += 1;
          if (readCount === 1) {
            throw new SecretProviderClientError({
              code: "access_denied",
              provider: "vault",
              operation: "readKv",
              message: "denied",
              status: 403,
            });
          }
          return { data: { value: "resolved-after-relogin" } };
        },
        async writeKv() {
          throw new Error("not used");
        },
        async health() {
          throw new Error("not used");
        },
      },
    });

    const resolved = await provider.resolveVersion({
      material: { scheme: "hashicorp_vault_v1", mount: "secret", path: "paperclip/company-1/openai-api-key", key: "value", source: "managed" },
      externalRef: "vault://secret/paperclip/company-1/openai-api-key#value",
    });

    expect(resolved).toBe("resolved-after-relogin");
    expect(loginCount).toBe(2);
    expect(tokens).toEqual(["vault-token-1", "vault-token-2"]);
  });

  it("maps a KV-v2 404 read to secret_not_found", async () => {
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG },
      gateway: {
        async login() {
          return { token: "vault-token-1", leaseDurationSeconds: 3600 };
        },
        async readKv() {
          throw new SecretProviderClientError({
            code: "not_found",
            provider: "vault",
            operation: "readKv",
            message: "missing",
            status: 404,
          });
        },
        async writeKv() {
          throw new Error("not used");
        },
        async health() {
          throw new Error("not used");
        },
      },
    });

    let thrown: unknown;
    try {
      await provider.resolveVersion({
        material: { scheme: "hashicorp_vault_v1", mount: "secret", path: "paperclip/company-1/missing", key: "value", source: "managed" },
        externalRef: "vault://secret/paperclip/company-1/missing#value",
      });
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(SecretProviderClientError);
    expect(thrown).toMatchObject({ code: "not_found", status: 404 });
  });

  it("creates a managed KV-v2 secret under the configured prefix and returns a parseable externalRef", async () => {
    const calls: Array<{ op: string; mount: string; path: string; data: Record<string, unknown>; token: string }> = [];
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG },
      gateway: {
        async login() {
          return { token: "vault-token-1", leaseDurationSeconds: 3600 };
        },
        async readKv() {
          throw new Error("not used");
        },
        async writeKv(input) {
          calls.push({ op: "writeKv", mount: input.mount, path: input.path, data: input.data, token: input.token });
          return { version: 4 };
        },
        async health() {
          throw new Error("not used");
        },
      },
    });

    const prepared = await provider.createSecret({
      value: "super-secret-value",
      context: WRITE_CONTEXT,
    });

    expect(calls).toEqual([
      {
        op: "writeKv",
        mount: "secret",
        path: "paperclip/company-1/openai-api-key",
        data: { value: "super-secret-value" },
        token: "vault-token-1",
      },
    ]);
    expect(prepared.externalRef).toBe("vault://secret/paperclip/company-1/openai-api-key#value");
    expect(prepared.providerVersionRef).toBe("4");
    expect(JSON.stringify(prepared)).not.toContain("super-secret-value");
  });

  it("writes a new KV-v2 version against the same managed path", async () => {
    const calls: Array<{ path: string; data: Record<string, unknown> }> = [];
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG },
      gateway: {
        async login() {
          return { token: "vault-token-1", leaseDurationSeconds: 3600 };
        },
        async readKv() {
          throw new Error("not used");
        },
        async writeKv(input) {
          calls.push({ path: input.path, data: input.data });
          return { version: 5 };
        },
        async health() {
          throw new Error("not used");
        },
      },
    });

    const prepared = await provider.createVersion({
      value: "rotated-value",
      externalRef: "vault://secret/paperclip/company-1/openai-api-key#value",
      context: { ...WRITE_CONTEXT, version: 2 },
    });

    expect(calls).toEqual([
      { path: "paperclip/company-1/openai-api-key", data: { value: "rotated-value" } },
    ]);
    expect(prepared.providerVersionRef).toBe("5");
    expect(JSON.stringify(prepared)).not.toContain("rotated-value");
  });

  it("validateConfig fails clearly when required AppRole config is missing", async () => {
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG, roleId: "", secretId: "" },
      gateway: {
        async login() {
          throw new Error("not used");
        },
        async readKv() {
          throw new Error("not used");
        },
        async writeKv() {
          throw new Error("not used");
        },
        async health() {
          throw new Error("not used");
        },
      },
    });

    const result = await provider.validateConfig();
    expect(result.ok).toBe(false);
    expect(result.warnings.join("\n")).toMatch(/role_?id/i);
    expect(result.warnings.join("\n")).toMatch(/secret_?id/i);
  });

  it("links external Vault references as metadata-only material", async () => {
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG },
      gateway: {
        async login() {
          throw new Error("not used");
        },
        async readKv() {
          throw new Error("not used");
        },
        async writeKv() {
          throw new Error("not used");
        },
        async health() {
          throw new Error("not used");
        },
      },
    });

    const prepared = await provider.linkExternalSecret({
      externalRef: "vault://kv/team/shared#api_key",
    });

    expect(prepared.externalRef).toBe("vault://kv/team/shared#api_key");
    expect(prepared.valueSha256).toBeTruthy();
  });

  it("reports health as ok for a reachable Vault and warn for a sealed/standby one", async () => {
    const statuses = [200, 503];
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG },
      gateway: {
        async login() {
          throw new Error("not used");
        },
        async readKv() {
          throw new Error("not used");
        },
        async writeKv() {
          throw new Error("not used");
        },
        async health() {
          return { status: statuses.shift()! };
        },
      },
    });

    const ok = await provider.healthCheck();
    const degraded = await provider.healthCheck();

    expect(ok.status).toBe("ok");
    expect(degraded.status).toBe("warn");
  });

  it("reports health as warn (not error) when Vault is unreachable", async () => {
    const provider = createHashiCorpVaultProvider({
      config: { ...BASE_CONFIG },
      gateway: {
        async login() {
          throw new Error("not used");
        },
        async readKv() {
          throw new Error("not used");
        },
        async writeKv() {
          throw new Error("not used");
        },
        async health() {
          throw new SecretProviderClientError({
            code: "provider_unavailable",
            provider: "vault",
            operation: "health",
            message: "unreachable",
            status: 503,
          });
        },
      },
    });

    const health = await provider.healthCheck();
    expect(health.status).toBe("warn");
    expect(health.message).toMatch(/unavailable|unreachable/i);
  });

  it("signs Vault HTTP requests with X-Vault-Token and AppRole login over the default gateway", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
      const href = String(url);
      if (href.endsWith("/v1/auth/approle/login")) {
        return new Response(
          JSON.stringify({ auth: { client_token: "s.tok123", lease_duration: 3600 } }),
          { status: 200 },
        );
      }
      if (href.includes("/v1/secret/data/")) {
        return new Response(
          JSON.stringify({ data: { data: { value: "resolved-http" } } }),
          { status: 200 },
        );
      }
      return new Response("{}", { status: 404 });
    });

    const provider = createHashiCorpVaultProvider({ config: { ...BASE_CONFIG } });
    const resolved = await provider.resolveVersion({
      material: { scheme: "hashicorp_vault_v1", mount: "secret", path: "paperclip/company-1/openai-api-key", key: "value", source: "managed" },
      externalRef: "vault://secret/paperclip/company-1/openai-api-key#value",
    });

    expect(resolved).toBe("resolved-http");
    const loginCall = fetchMock.mock.calls.find(([u]) => String(u).endsWith("/v1/auth/approle/login"));
    const readCall = fetchMock.mock.calls.find(([u]) => String(u).includes("/v1/secret/data/"));
    expect(loginCall).toBeTruthy();
    expect(readCall).toBeTruthy();
    const readHeaders = readCall?.[1]?.headers as Record<string, string>;
    expect(readHeaders["X-Vault-Token"]).toBe("s.tok123");
  });
});
