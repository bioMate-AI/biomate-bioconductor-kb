/**
 * Settings → LLM picker under the Chinese-LLM region policy (lib/llm-region.ts; the server decides
 * the region via GET /api/llm/policy and enforces it again on save and on every chat request).
 *  - China user: Chinese models only (no Claude/GPT/Gemini chips), the Chinese default, a typed
 *    non-Chinese slug rejected inline, no Anthropic-key provider.
 *  - Everyone else: unchanged — open + proprietary chips, the GLM default, the Anthropic option.
 */
import React from "react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { render, screen, fireEvent, waitFor, within, cleanup } from "@testing-library/react"

vi.mock("@/contexts/auth-context", () => ({ useAuth: () => ({ logout: vi.fn(), user: { id: "u1", email: "a@b.c" } }) }))
vi.mock("./RetrainAdapterCard", () => ({ RetrainAdapterCard: () => null }))
vi.mock("./mfa-settings", () => ({ MfaSettings: () => null }))

import { SettingsDialog } from "./settings-dialog"
import { modelGroups, effectivePick, pickRejected, type LlmPolicy } from "@/lib/llm-region"

const CN_POLICY: LlmPolicy = { region: "cn", reasons: ["ip"], allowedVendors: ["deepseek", "z-ai", "qwen", "moonshotai"], defaultModel: "deepseek/deepseek-v4.1-flash", anthropicKeyAllowed: false, chineseModelAvailable: true }
const INTL_POLICY: LlmPolicy = { region: "intl", reasons: [], allowedVendors: "all", defaultModel: null, anthropicKeyAllowed: true, chineseModelAvailable: true }

function stubServer(policy: LlmPolicy, stored: Record<string, unknown> = {}) {
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input)
    const json = (body: unknown) => ({ ok: true, status: 200, json: async () => body }) as unknown as Response
    if (url.startsWith("/api/llm/policy")) return json(policy)
    if (url.startsWith("/api/user/llm-api-keys")) return json({ anthropic: false, openrouter: false, selected_model: null, ...stored })
    if (url.startsWith("/api/user/api-keys")) return json([])
    return json({})
  }) as unknown as typeof fetch
}

afterEach(() => { cleanup(); vi.restoreAllMocks() })

async function openOpenRouter() {
  render(<SettingsDialog open onOpenChange={() => {}} />)
  fireEvent.click(await screen.findByText("OpenRouter"))
  return screen.findByTestId("llm-model-quickpick")
}

describe("China user", () => {
  it("only Chinese chips, the Chinese default, no Anthropic provider, and the region note", async () => {
    stubServer(CN_POLICY)
    const picks = await openOpenRouter()
    await waitFor(() => expect((screen.getByTestId("input-llm-model") as HTMLInputElement).value).toBe("deepseek/deepseek-v4.1-flash"))
    const chips = within(picks).getAllByRole("button").map(b => b.textContent || "")
    expect(chips.some(c => /claude|gpt|gemini|grok|mistral|llama/i.test(c))).toBe(false)
    expect(chips.some(c => /glm-5\.3-prime/.test(c))).toBe(true)
    expect(screen.getByTestId("llm-region-note")).toBeTruthy()
    expect(screen.queryByText("Anthropic (BYOK)")).toBeNull()
  })
  it("a stored non-Chinese pick is replaced by the Chinese default", async () => {
    stubServer(CN_POLICY, { openrouter: true, selected_model: "anthropic/claude-opus-5.5" })
    render(<SettingsDialog open onOpenChange={() => {}} />)
    await waitFor(() => expect((screen.getByTestId("input-llm-model") as HTMLInputElement).value).toBe("deepseek/deepseek-v4.1-flash"))
  })
  it("a typed non-Chinese slug is rejected inline", async () => {
    stubServer(CN_POLICY)
    await openOpenRouter()
    const input = await screen.findByTestId("input-llm-model")
    fireEvent.change(input, { target: { value: "anthropic/claude-sonnet-5.5" } })
    expect(await screen.findByTestId("llm-model-region-error")).toBeTruthy()
    fireEvent.change(input, { target: { value: "qwen/qwen3-235b-a22b-2507" } })
    await waitFor(() => expect(screen.queryByTestId("llm-model-region-error")).toBeNull())
  })
})

describe("user outside the region (unchanged)", () => {
  it("open + proprietary chips, the GLM default, no region note, no rejection", async () => {
    stubServer(INTL_POLICY)
    const picks = await openOpenRouter()
    await waitFor(() => expect((screen.getByTestId("input-llm-model") as HTMLInputElement).value).toBe("z-ai/glm-5.3-prime"))
    const chips = within(picks).getAllByRole("button").map(b => b.textContent || "")
    expect(chips.some(c => /claude-opus/.test(c))).toBe(true)
    expect(chips.some(c => /glm-5\.3-prime/.test(c))).toBe(true)
    expect(screen.queryByTestId("llm-region-note")).toBeNull()
    expect(screen.getByText("Anthropic (BYOK)")).toBeTruthy()
    fireEvent.change(screen.getByTestId("input-llm-model"), { target: { value: "anthropic/claude-sonnet-5.5" } })
    expect(screen.queryByTestId("llm-model-region-error")).toBeNull()
  })
})

describe("picker helpers", () => {
  it("groups, effective pick and rejection follow the region", () => {
    expect(modelGroups("cn").map(g => g.key)).toEqual(["chinese"])
    expect(modelGroups("intl").map(g => g.key)).toEqual(["open", "proprietary"])
    expect(effectivePick(CN_POLICY, "z-ai/glm-5.3-prime")).toBe("z-ai/glm-5.3-prime")
    expect(effectivePick(CN_POLICY, "openai/gpt-6.1-sol-pro")).toBe("deepseek/deepseek-v4.1-flash")
    expect(effectivePick(INTL_POLICY, "z-ai/glm-5.3-prime")).toBe("z-ai/glm-5.3-prime")
    expect(effectivePick(INTL_POLICY, null)).toBe("z-ai/glm-5.3-prime")
    expect(pickRejected(CN_POLICY, "anthropic/claude-opus-5.5")).toBe(true)
    expect(pickRejected(INTL_POLICY, "anthropic/claude-opus-5.5")).toBe(false)
  })
})
