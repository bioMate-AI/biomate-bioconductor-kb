// @vitest-environment node
/**
 * Settings → LLM endpoints under the Chinese-LLM region policy (llm-policy-routes.ts).
 * Real express + real HTTP; only the DB is an in-memory map. The region comes from the request
 * itself (Accept-Language, the client IP via X-Forwarded-For with `trust proxy` as in index.ts).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import express from "express";
import type { AddressInfo } from "net";
import type http from "http";
import { registerLlmPolicyRoutes } from "./llm-policy-routes";

let server: http.Server;
let base = "";
const rows = new Map<string, any>();

beforeAll(async () => {
  const app = express();
  app.set("trust proxy", 1);
  registerLlmPolicyRoutes(app, {
    authenticateToken: (req: any, _res, next) => { req.user = { id: "u1" }; next(); },
    query: async (sql, params) => {
      if (sql.startsWith("SELECT")) return { rows: [{ llm_api_keys: rows.get(String(params[0])) ?? {} }] };
      rows.set(String(params[1]), JSON.parse(String(params[0])));
      return { rows: [] };
    },
    encryptField: (v) => `enc:${v}`,
  });
  await new Promise<void>((r) => { server = app.listen(0, "127.0.0.1", () => r()); });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => server?.close());
beforeEach(() => rows.clear());

const CN = { "accept-language": "zh-CN,zh;q=0.9" };
const US = { "accept-language": "en-US,en;q=0.9", "x-forwarded-for": "104.63.31.236" };
const HK_IP = { "accept-language": "en-US", "x-forwarded-for": "47.242.215.11" };

const patch = (headers: Record<string, string>, body: unknown) =>
  fetch(`${base}/api/user/llm-api-keys`, { method: "PATCH", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body) });

describe("GET /api/llm/policy", () => {
  it("a Chinese browser is a China user: Chinese vendors, the Chinese default, no Anthropic key", async () => {
    const p = await (await fetch(`${base}/api/llm/policy`, { headers: CN })).json();
    expect(p).toMatchObject({ region: "cn", reasons: ["accept_language"], anthropicKeyAllowed: false, defaultModel: "deepseek/deepseek-v4.1-flash" });
    expect(p.allowedVendors).toContain("deepseek");
  });
  it("an English browser in Hong Kong is a China user by IP", async () => {
    const p = await (await fetch(`${base}/api/llm/policy`, { headers: HK_IP })).json();
    expect(p).toMatchObject({ region: "cn", reasons: ["ip"] });
  });
  it("the Settings language counts (uiLanguage / the biomate_ui_lang cookie)", async () => {
    expect((await (await fetch(`${base}/api/llm/policy?uiLanguage=zh`, { headers: US })).json()).region).toBe("cn");
    expect((await (await fetch(`${base}/api/llm/policy`, { headers: { ...US, cookie: "biomate_ui_lang=zh" } })).json()).region).toBe("cn");
  });
  it("a US user: everything allowed", async () => {
    expect(await (await fetch(`${base}/api/llm/policy`, { headers: US })).json())
      .toMatchObject({ region: "intl", allowedVendors: "all", anthropicKeyAllowed: true, defaultModel: null });
  });
});

describe("PATCH /api/user/llm-api-keys", () => {
  it("China user: a non-Chinese model is rejected with 400 model_not_allowed_in_region and nothing is saved", async () => {
    const r = await patch(CN, { selected_model: "anthropic/claude-sonnet-5.5" });
    expect(r.status).toBe(400);
    const body = await r.json();
    expect(body.code).toBe("model_not_allowed_in_region");
    expect(body.error).toContain("国产大模型");
    expect(rows.get("u1")).toBeUndefined();
  });
  it("China user: an Anthropic key is rejected with 400 provider_not_allowed_in_region", async () => {
    const r = await patch(HK_IP, { provider: "anthropic", key: "sk-ant-x" });
    expect(r.status).toBe(400);
    expect((await r.json()).code).toBe("provider_not_allowed_in_region");
  });
  it("China user: a Chinese model is saved", async () => {
    const r = await patch(CN, { provider: "openrouter", key: "sk-or", selected_model: "moonshotai/kimi-k3" });
    expect(r.status).toBe(200);
    expect(rows.get("u1")).toEqual({ openrouter: "enc:sk-or", selected_model: "moonshotai/kimi-k3" });
  });
  it("US user: any model and an Anthropic key are saved (GLM included)", async () => {
    expect((await patch(US, { selected_model: "z-ai/glm-5.3-prime" })).status).toBe(200);
    expect(rows.get("u1").selected_model).toBe("z-ai/glm-5.3-prime");
    expect((await patch(US, { selected_model: "anthropic/claude-opus-5.5" })).status).toBe(200);
    expect((await patch(US, { provider: "anthropic", key: "sk-ant" })).status).toBe(200);
    expect(rows.get("u1")).toMatchObject({ anthropic: "enc:sk-ant", selected_model: "anthropic/claude-opus-5.5" });
  });
  it("removing a key stays allowed for China users", async () => {
    rows.set("u1", { anthropic: "enc:old" });
    expect((await patch(CN, { provider: "anthropic", key: "" })).status).toBe(200);
    expect(rows.get("u1")).toEqual({});
  });
});
