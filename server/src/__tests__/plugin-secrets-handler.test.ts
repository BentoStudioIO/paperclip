import { describe, expect, it, vi } from "vitest";
import { createPluginSecretsHandler } from "../services/plugin-secrets-handler.js";

const PLUGIN_ID = "11111111-1111-4111-8111-111111111111";
const SECRET_REF = "77777777-7777-4777-8777-777777777777";
const COMPANY_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const COMPANY_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function makeHandler(resolveSecretValue: (companyId: string, secretId: string) => Promise<string>) {
  return createPluginSecretsHandler({
    db: {} as never,
    pluginId: PLUGIN_ID,
    resolveSecretValue,
  });
}

describe("createPluginSecretsHandler", () => {
  it("resolves a same-company secret ref to its value", async () => {
    const resolveSecretValue = vi.fn(async () => "s3cr3t-value");
    const handler = makeHandler(resolveSecretValue);

    const value = await handler.resolve(
      { secretRef: SECRET_REF },
      { invocationScope: { companyId: COMPANY_A } },
    );

    expect(value).toBe("s3cr3t-value");
    expect(resolveSecretValue).toHaveBeenCalledWith(COMPANY_A, SECRET_REF);
  });

  it("masks a cross-company secret as InvalidSecretRefError (no existence oracle)", async () => {
    // resolveSecretValue enforces ownership and throws for another company's
    // secret; the handler must rewrite that into an opaque invalid-ref error.
    const resolveSecretValue = vi.fn(async () => {
      const err = new Error("Secret must belong to same company");
      err.name = "UnprocessableError";
      throw err;
    });
    const handler = makeHandler(resolveSecretValue);

    await expect(
      handler.resolve(
        { secretRef: SECRET_REF },
        { invocationScope: { companyId: COMPANY_B } },
      ),
    ).rejects.toThrow(/invalid secret reference/i);
    expect(resolveSecretValue).toHaveBeenCalledWith(COMPANY_B, SECRET_REF);
  });

  it("rejects with InvalidSecretRefError when the invocation scope is missing", async () => {
    const resolveSecretValue = vi.fn(async () => "should-not-resolve");
    const handler = makeHandler(resolveSecretValue);

    await expect(handler.resolve({ secretRef: SECRET_REF })).rejects.toThrow(
      /invalid secret reference/i,
    );
    expect(resolveSecretValue).not.toHaveBeenCalled();
  });

  it("rejects with InvalidSecretRefError when the invocation scope is flagged invalid", async () => {
    const resolveSecretValue = vi.fn(async () => "should-not-resolve");
    const handler = makeHandler(resolveSecretValue);

    await expect(
      handler.resolve(
        { secretRef: SECRET_REF },
        { invocationScope: { companyId: COMPANY_A }, invalidInvocationScope: true },
      ),
    ).rejects.toThrow(/invalid secret reference/i);
    expect(resolveSecretValue).not.toHaveBeenCalled();
  });

  it("still rejects malformed secret refs before reaching resolution", async () => {
    const resolveSecretValue = vi.fn(async () => "should-not-resolve");
    const handler = makeHandler(resolveSecretValue);

    await expect(
      handler.resolve(
        { secretRef: "not-a-uuid" },
        { invocationScope: { companyId: COMPANY_A } },
      ),
    ).rejects.toThrow(/invalid secret reference/i);
    expect(resolveSecretValue).not.toHaveBeenCalled();
  });
});
