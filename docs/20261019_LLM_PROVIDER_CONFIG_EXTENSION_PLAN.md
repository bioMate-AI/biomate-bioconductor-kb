# LLM Provider Configuration — Extension Plan

**Date:** 2026-10-19
**Goal:** let a user run BioMate on any popular LLM (open- or closed-source), with
**their own key** (a provider key *or* an OpenRouter key), **notify them when a key is
rate-limited**, and let them **point BioMate at their own on-premise LLM**.

---

## 1. What BioMate has today

- **Settings → LLM Provider** (`settings-dialog.tsx`): three choices — **BioMate Default**
  (shared Claude, full workflow execution), **Anthropic (BYOK)** (your Anthropic key),
  **OpenRouter** (your OpenRouter key + a model slug, default `deepseek/deepseek-chat-v3-5`).
- **Key store:** `GET/PATCH /api/user/llm-api-keys` (encrypted; never returned to the browser).
- **Routing:** a YAML fallback chain `backend/config/llm_providers.yml`; `llm-client.ts`
  (Node) + `llm_router.py` / `model_resolver.py` (Python) — **no model strings hard-coded
  in TS**, so providers/models are config-driven and extensible.
- **On-prem seed:** `localOnly()` + `localMessagesClient()` already route to a local
  Anthropic-compatible endpoint (the on-prem own-model path).
- **429 handling:** `galaxy-assistant.ts` retries 429/529 — but only for BioMate's own
  key, and it is **not surfaced to the user** as "your key is rate-limited".

So the foundation exists; this is an **extension**, not a rebuild.

---

## 2. How other harnesses do it (research)

The universal pattern is **"any OpenAI-compatible endpoint"** — one generic provider that
takes a **Base URL + API key + model name**, which simultaneously covers *new cloud
providers* and *on-prem runtimes*:

- **Cline** — named providers + an **"OpenAI Compatible"** provider: pick it, paste a
  **Base URL** (e.g. `https://api.provider.com/v1`) + key + model name + capability
  fields. Points at a gateway, local runtime, or internal inference endpoint.
- **Jan** — a **Custom Provider** = any OpenAI-compatible API, cloud *or* local; it
  explicitly lists **vLLM, LM Studio, Ollama, SGLang, TensorRT-LLM, LocalAI,
  text-generation-webui** and enterprise gateways. Ollama = `http://localhost:11434/v1`
  (`OLLAMA_HOST=0.0.0.0 ollama serve` to expose it).
- **LibreChat** — `librechat.yaml` **custom endpoints**: any OpenAI-compatible service,
  `baseURL` + models (Ollama → `http://localhost:11434/v1/`).
- **Open WebUI** — add a **URL + API key** for Ollama / OpenAI-compatible / Open
  Responses; models then appear in the dropdown.

**Takeaway:** named BYOK providers for the big closed models + **OpenRouter** as the
"200+ models, one key" aggregator (covers most open-source too) + a generic
**OpenAI-compatible (Base URL)** provider that doubles as the **on-prem** mechanism.

---

## 3. Design — the extension

### 3.1 Provider list (Settings → LLM Provider)
Keep **BioMate Default**. Add, as radio/selectable providers, each with a BYOK key field:
- **Closed, named BYOK:** Anthropic (have), **OpenAI**, **Google (Gemini)**, **xAI (Grok)**,
  **DeepSeek**, **Mistral**, (optionally Groq / Together / Fireworks).
- **OpenRouter** (have) — the aggregator: one key → 200+ models, open *and* closed
  (DeepSeek, Qwen, Llama, Mistral, GPT, Claude, Gemini…). This is the simplest "all
  popular LLMs" answer; keep it prominent.
- **Custom (OpenAI-compatible)** — **Base URL + (optional) API key + model name** +
  capability flags (supports tools? vision? streaming?). This single provider covers both
  any niche/new cloud API **and on-prem** (next section).

Model selection: free-text slug (as OpenRouter already does) with a help link; optionally
a fetched model list for providers that expose `/models`.

### 3.2 On-prem LLM — "how to do that"
Use the **Custom (OpenAI-compatible)** provider. The user runs an OpenAI-compatible server
on their own infra and enters its **Base URL** (+ key if the server requires one) + the
model name. Document the common runtimes inline:
| Runtime | Base URL (example) | Note |
|---|---|---|
| **Ollama** | `http://<host>:11434/v1` | `OLLAMA_HOST=0.0.0.0 ollama serve` to expose |
| **vLLM** | `http://<host>:8000/v1` | `--served-model-name` sets the model id |
| **LM Studio** | `http://<host>:1234/v1` | "Local Server" tab |
| **Text-Gen-Inference / SGLang / LocalAI** | `http://<host>:<port>/v1` | all OpenAI-compatible |
- BioMate already has `localMessagesClient()`/`localOnly()` — **generalize** it to a
  user-configurable `baseURL` + `apiKey` + `model` read from the key store (instead of
  env-only), so an end user (not just a self-hosted deploy) can set it in Settings.
- Network caveat: BioMate's server must be able to reach the user's endpoint. For a
  *cloud* BioMate reaching a *private* on-prem model, document that the endpoint must be
  reachable (VPN/tunnel/allowlisted egress) — this is the real constraint, same as every
  other hosted harness.

### 3.3 Rate-limit notification
- Detect **HTTP 429** (and read **`Retry-After`**) from the active provider. BioMate
  already retries 429/529; extend it so that **when the failing key is the *user's* key**
  and retries are exhausted, it returns a typed error and the chat surfaces a **toast +
  inline banner**: *"Your <provider> key hit its rate limit (retry in N s). Switch
  provider, wait, or use BioMate Default."* with a one-click switch to Default.
- Also surface **401/invalid-key** and **402/quota-exhausted** distinctly ("key invalid"
  vs "credits exhausted" vs "rate-limited") — OpenRouter and most providers return these.
- Keep BioMate-Default 429s on the existing silent-retry path (don't alarm users about the
  shared pool unless it hard-fails).

### 3.4 Capability honesty
The default BioMate Claude supports **full agentic workflow execution** (tool-use/SSE).
Some BYOK/on-prem models are weaker at tool-use. Keep the current honest hint ("BioMate
Default — workflow execution") and show a per-provider capability note so users aren't
surprised when a small local model can't drive a workflow. (Ties to the on-prem own-model
work — see `project_onprem_uses_own_llm`.)

---

## 4. Implementation phases
1. **Key store + config:** extend `llm_providers.yml` + `/api/user/llm-api-keys` to hold
   per-provider keys, a `custom` entry `{baseURL, apiKey, model, capabilities}`, and the
   selected provider/model. (Encrypted as today.)
2. **Routing:** extend `llm-client.ts` + `model_resolver.py` so a user-selected provider /
   custom base URL is used for that user's chat calls (OpenAI-compatible client for the
   generic path; native SDK for Anthropic/Google where it helps).
3. **UI:** expand Settings → LLM Provider with the provider list + the Custom
   (Base URL/key/model) form + on-prem runtime hints.
4. **Rate-limit UX:** typed 429/401/402 errors from the LLM path → chat toast/banner +
   "switch to Default". Reuse the existing toast system.
5. **Tests:** key round-trip, provider routing selection, 429→notification, a mocked
   OpenAI-compatible (on-prem) call.

---

## 5. Direct answers to the questions
- **All popular LLMs (open + closed):** named BYOK for the big closed ones + **OpenRouter**
  (one key, 200+ incl. open-source) + a **Custom OpenAI-compatible** provider for anything
  else. That trio is what Cline/Jan/LibreChat/Open WebUI converge on.
- **Own key or OpenRouter key:** already the model; just broaden the provider list.
- **Rate-limit notification:** detect 429 + `Retry-After` on the *user's* key → toast +
  banner + one-click switch to Default (plus distinct 401/402 messages).
- **On-prem:** the **Custom (OpenAI-compatible) Base URL** provider — the exact mechanism
  every harness uses; generalize BioMate's existing `localMessagesClient` to a
  user-settable base URL, and document Ollama/vLLM/LM Studio/TGI endpoints.

## Sources
- [Cline — OpenRouter / custom provider](https://docs.cline.bot/provider-config/openrouter)
- [Jan — Custom Providers (vLLM/Ollama/LM Studio/…)](https://docs.jan.ai/jan/custom-provider)
- [LibreChat — custom endpoints](https://www.librechat.ai/docs/quick_start/custom_endpoints)
- [Open WebUI — connect a provider](https://docs.openwebui.com/getting-started/quick-start/connect-a-provider)
