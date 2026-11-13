/**
 * The user's LLM settings (Settings → LLM) and the region policy behind them
 * (llm-region-policy.ts, docs/20261112_CN_LLM_REGION_POLICY.md).
 *
 *   GET   /api/llm/policy          — the caller's region and what the Settings picker may offer
 *   GET   /api/user/llm-api-keys   — which keys are stored (booleans only) + the stored model pick
 *   PATCH /api/user/llm-api-keys   — save a key / model pick; China users may only save a Chinese
 *                                    model and no Anthropic key (400, with a code)
 *
 * The chat stream enforces the policy again on every request, whatever is stored.
 */
import express, { type Express, type RequestHandler } from "express";
import { classifyRegion, regionSignalsFromRequest, policySummary, checkModelPick } from "./llm-region-policy";

export interface LlmPolicyRouteDeps {
  authenticateToken: RequestHandler;
  query: (sql: string, params: unknown[]) => Promise<{ rows: any[] }>;
  encryptField: (plain: string) => string;
}

const VALID_PROVIDERS = ["anthropic", "openrouter"];

export function registerLlmPolicyRoutes(app: Express, deps: LlmPolicyRouteDeps): void {
  const { authenticateToken, query, encryptField } = deps;
  const regionOf = (req: any, uiLanguage?: unknown) => classifyRegion(regionSignalsFromRequest(req, uiLanguage));

  app.get("/api/llm/policy", (req, res) => {
    res.json(policySummary(regionOf(req, req.query.uiLanguage)));
  });

  app.get("/api/user/llm-api-keys", authenticateToken, async (req: any, res) => {
    try {
      const row = await query(`SELECT llm_api_keys FROM users WHERE id = $1`, [req.user!.id]);
      const stored = (row.rows[0]?.llm_api_keys ?? {}) as any;
      res.json({
        anthropic: !!stored.anthropic,
        openrouter: !!stored.openrouter,
        selected_model: stored.selected_model ?? null,
      });
    } catch (error: any) {
      console.error("[llm-api-keys] get error:", error?.message);
      res.status(500).json({ error: "Failed to get LLM API keys" });
    }
  });

  app.patch("/api/user/llm-api-keys", authenticateToken, express.json(), async (req: any, res) => {
    try {
      const { provider, key, selected_model, uiLanguage } = req.body ?? {};
      if (provider !== undefined && (typeof provider !== "string" || !VALID_PROVIDERS.includes(provider))) {
        return res.status(400).json({ error: `provider must be one of: ${VALID_PROVIDERS.join(", ")}` });
      }
      // China-region users: Chinese models only, and no Anthropic key (it would only ever reach Claude).
      const region = regionOf(req, uiLanguage);
      if (region.region === "cn") {
        if (provider === "anthropic" && typeof key === "string" && key.trim()) {
          return res.status(400).json({
            code: "provider_not_allowed_in_region",
            error: "Only Chinese models (国产大模型) are available in your region; an Anthropic key cannot be used. 您所在地区仅可使用国产大模型，无法使用 Anthropic 密钥。",
            region: region.region, reasons: region.reasons,
          });
        }
        if (checkModelPick(region.region, selected_model)) {
          return res.status(400).json({
            code: "model_not_allowed_in_region",
            error: "Only Chinese models (国产大模型) are available in your region. 您所在地区仅可使用国产大模型。",
            region: region.region, reasons: region.reasons, model: selected_model,
          });
        }
      }
      const rowResult = await query(`SELECT llm_api_keys FROM users WHERE id = $1`, [req.user!.id]);
      const existing: Record<string, string> = rowResult.rows[0]?.llm_api_keys ?? {};
      if (provider) {
        if (typeof key === "string" && key.trim().length > 0) {
          existing[provider] = encryptField(key.trim());
        } else if (key !== undefined) {
          delete existing[provider];
        }
      }
      if (selected_model !== undefined) {
        if (typeof selected_model === "string" && selected_model.trim().length > 0) {
          existing.selected_model = selected_model.trim();
        } else {
          delete existing.selected_model;
        }
      }
      await query(`UPDATE users SET llm_api_keys = $1::jsonb, updated_at = NOW() WHERE id = $2`, [JSON.stringify(existing), req.user!.id]);
      res.json({ ok: true, anthropic: !!existing.anthropic, openrouter: !!existing.openrouter, selected_model: existing.selected_model ?? null });
    } catch (error: any) {
      console.error("[llm-api-keys] patch error:", error?.message);
      res.status(500).json({ error: "Failed to update LLM API keys" });
    }
  });
}
