/**
 * Tests for the llmGenerate frontend client.
 *
 * Verifies the wire format (request body, headers, URL) and response
 * parsing against a mock fetch — no real LLM hit.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { llmGenerate } from "../llm-client";

describe("llmGenerate", () => {
  const originalFetch = global.fetch;
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env.GALAXY_URL = "http://galaxy-test:8080";
    process.env.BILLING_INTERNAL_KEY = "test-key-abc";
  });
  afterEach(() => {
    global.fetch = originalFetch;
    process.env = originalEnv;
  });

  it("POSTs to /internal/llm/generate with correct shape", async () => {
    let capturedUrl = "";
    let capturedInit: RequestInit | undefined;
    global.fetch = (async (url: any, init?: any) => {
      capturedUrl = String(url);
      capturedInit = init;
      return new Response(
        JSON.stringify({
          text: "the answer",
          model_used: "gemini:gemini-3.1-pro-preview",
          fallback_depth: 0,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }) as any;

    const result = await llmGenerate({
      prompt: "What is 2+2?",
      system: "You are a math tutor.",
      maxTokens: 100,
      temperature: 0.3,
    });

    expect(capturedUrl).toBe("http://galaxy-test:8080/internal/llm/generate");
    expect(capturedInit?.method).toBe("POST");
    const headers = capturedInit?.headers as Record<string, string>;
    expect(headers["X-Internal-Key"]).toBe("test-key-abc");
    expect(headers["Content-Type"]).toBe("application/json");
    const body = JSON.parse(String(capturedInit?.body));
    expect(body).toEqual({
      prompt: "What is 2+2?",
      system: "You are a math tutor.",
      max_tokens: 100,
      temperature: 0.3,
    });
    expect(result).toEqual({
      text: "the answer",
      modelUsed: "gemini:gemini-3.1-pro-preview",
      fallbackDepth: 0,
    });
  });

  it("defaults max_tokens=4096 and temperature=0.7 when unspecified", async () => {
    let body: any;
    global.fetch = (async (_url: any, init?: any) => {
      body = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({ text: "x", model_used: "m", fallback_depth: 0 }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }) as any;
    await llmGenerate({ prompt: "hi" });
    expect(body.max_tokens).toBe(4096);
    expect(body.temperature).toBe(0.7);
  });

  it("forwards json_mode only when true", async () => {
    let body: any;
    global.fetch = (async (_u: any, init?: any) => {
      body = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({ text: "x", model_used: "m", fallback_depth: 0 }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }) as any;
    await llmGenerate({ prompt: "hi", jsonMode: true });
    expect(body.json_mode).toBe(true);

    await llmGenerate({ prompt: "hi" });
    expect(body.json_mode).toBeUndefined();
  });

  it("rejects on empty prompt before the network call", async () => {
    let called = false;
    global.fetch = (async () => { called = true; return new Response("", { status: 200 }); }) as any;
    await expect(llmGenerate({ prompt: "" })).rejects.toThrow(/prompt is required/);
    await expect(llmGenerate({ prompt: "   " })).rejects.toThrow(/prompt is required/);
    expect(called).toBe(false);
  });

  it("throws on non-2xx with status + body preview", async () => {
    global.fetch = (async () =>
      new Response("internal explosion", { status: 502 })) as any;
    await expect(llmGenerate({ prompt: "hi" })).rejects.toThrow(/HTTP 502/);
  });

  it("throws when response lacks `text` field", async () => {
    global.fetch = (async () =>
      new Response(JSON.stringify({ model_used: "x" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      })) as any;
    await expect(llmGenerate({ prompt: "hi" })).rejects.toThrow(/missing.*text/);
  });
});
