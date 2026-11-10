/**
 * DeepLearningModelsTab — the "Deep Learning & Foundation Models" track of the
 * Models panel.
 *
 * Purpose: make BioMate's ML/DL methods discoverable (hierarchical + searchable)
 * instead of only reachable by chatting. Two sections, both driven by the one
 * top-of-tab search box:
 *
 *   A) "Train a model" — the runnable training model_types grouped into method
 *      families (config.py MODEL_TYPES, minus the chemprop_gnn STUB). A family
 *      is a heading; each method is a card. A card whose configuration the
 *      ModelSetup form can express (sklearn_tabular, sklearn_gbr, ludwig_tabular)
 *      launches ModelSetup pre-selected to that model_type. A card the form can't
 *      yet express (the LLM family needs task_type=text_generation; the diffusion
 *      family is GENERATIVE with PDB / h5ad inputs) is labelled honestly and routes
 *      to a chat draft instead of the classification form — we never open a form
 *      that cannot configure the method.
 *
 *   B) "Pre-built foundation models & workflows" — a search over the real catalog
 *      (POST /api/workflows/search), seeded with a default query so it is never
 *      empty on open. Surfaces the existing DL / FM workflows (Transcriptformer,
 *      perturbation models, VAEs, embeddings, Biotransformer, …) that are
 *      otherwise only findable by chatting. Each hit opens in chat via the real
 *      ?draft= bridge.
 *
 * The top search box filters BOTH sections: method cards by their resolved
 * name / family / description, and the workflow search by the typed query (the
 * default seed query is used while the box is empty).
 */

import { useEffect, useRef, useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Search, Sparkles, X } from "lucide-react"
import { ModelSetup } from "./model-setup"
import { SpecSetup } from "./spec-setup"
import { tOr } from "@/lib/i18n"

/** Default query so Section B is populated on open (never an empty section). */
export const DEFAULT_WF_QUERY = "foundation model deep learning transformer GNN embedding"

/** A training method card. Every method opens a real structured form inline:
 * `panel: "model"` launches ModelSetup (classification/regression) pre-selected
 * to `type`; `panel: "spec"` launches SpecSetup — the structured LLM /
 * generative-diffusion form whose fields mirror LLMSpec / DiffusionSpec /
 * SCDiffusionSpec in `ml_training/config.py`. `badge` is an honest family tag
 * (e.g. "LLM", "generative") shown on spec cards. */
interface Method {
  type: string
  panel: "model" | "spec"
  familyKey: string
  familyFallback: string
  nameKey: string
  nameFallback: string
  descKey: string
  descFallback: string
  /** Optional honest family tag badge (spec cards). */
  badgeKey?: string
  badgeFallback?: string
}

// Families grouped as the task specifies. Honest labels only — sklearn_tabular is
// GradientBoosting-only today (more estimators are a known follow-up, not faked);
// chemprop_gnn is a STUB and is deliberately NOT surfaced.
const METHODS: Method[] = [
  {
    type: "sklearn_tabular",
    panel: "model",
    familyKey: "models.dl_family_tabular",
    familyFallback: "Tabular ML",
    nameKey: "models.dl_m_sklearn_tabular",
    nameFallback: "Tabular classifier / regressor (scikit-learn)",
    descKey: "models.dl_d_sklearn_tabular",
    descFallback: "GradientBoosting over a feature matrix. More estimators are a known follow-up.",
  },
  {
    type: "sklearn_gbr",
    panel: "model",
    familyKey: "models.dl_family_molecular",
    familyFallback: "Molecular",
    nameKey: "models.dl_m_sklearn_gbr",
    nameFallback: "Molecular property baseline",
    descKey: "models.dl_d_sklearn_gbr",
    descFallback: "RDKit descriptors + gradient boosting — a cheap non-DL baseline.",
  },
  {
    type: "ludwig_tabular",
    panel: "model",
    familyKey: "models.dl_family_dl",
    familyFallback: "Deep learning",
    nameKey: "models.dl_m_ludwig_tabular",
    nameFallback: "Ludwig neural net",
    descKey: "models.dl_d_ludwig_tabular",
    descFallback: "Low-code deep-learning model over tabular features.",
  },
  {
    type: "ludwig_llm",
    panel: "spec",
    familyKey: "models.dl_family_llm",
    familyFallback: "LLM fine-tuning",
    nameKey: "models.dl_m_ludwig_llm",
    nameFallback: "Ludwig LLM (LoRA / QLoRA)",
    descKey: "models.dl_d_ludwig_llm",
    descFallback: "Low-code LLM fine-tuning with LoRA / QLoRA adapters.",
    badgeKey: "models.dl_badge_llm_tag",
    badgeFallback: "LLM",
  },
  {
    type: "trl_dpo",
    panel: "spec",
    familyKey: "models.dl_family_llm",
    familyFallback: "LLM fine-tuning",
    nameKey: "models.dl_m_trl_dpo",
    nameFallback: "TRL DPO (preference optimization)",
    descKey: "models.dl_d_trl_dpo",
    descFallback: "Direct preference optimization over chosen/rejected response pairs.",
    badgeKey: "models.dl_badge_llm_tag",
    badgeFallback: "LLM",
  },
  {
    type: "trl_grpo",
    panel: "spec",
    familyKey: "models.dl_family_llm",
    familyFallback: "LLM fine-tuning",
    nameKey: "models.dl_m_trl_grpo",
    nameFallback: "TRL GRPO (reinforcement learning)",
    descKey: "models.dl_d_trl_grpo",
    descFallback: "Reinforcement learning (GRPO) against a reward signal.",
    badgeKey: "models.dl_badge_llm_tag",
    badgeFallback: "LLM",
  },
  {
    type: "protein_diffusion",
    panel: "spec",
    familyKey: "models.dl_family_diffusion",
    familyFallback: "Generative / Diffusion",
    nameKey: "models.dl_m_protein_diffusion",
    nameFallback: "RFdiffusion (protein backbone design)",
    descKey: "models.dl_d_protein_diffusion",
    descFallback: "Generative protein backbone design over PDB / mmCIF structure inputs.",
    badgeKey: "models.dl_badge_generative_tag",
    badgeFallback: "generative",
  },
  {
    type: "scrna_diffusion",
    panel: "spec",
    familyKey: "models.dl_family_diffusion",
    familyFallback: "Generative / Diffusion",
    nameKey: "models.dl_m_scrna_diffusion",
    nameFallback: "scDiffusion / CFGen (single-cell generation)",
    descKey: "models.dl_d_scrna_diffusion",
    descFallback: "Generative single-cell expression profiles over an h5ad dataset.",
    badgeKey: "models.dl_badge_generative_tag",
    badgeFallback: "generative",
  },
  {
    type: "tabular_diffusion",
    panel: "spec",
    familyKey: "models.dl_family_diffusion",
    familyFallback: "Generative / Diffusion",
    nameKey: "models.dl_m_tabular_diffusion",
    nameFallback: "TabDDPM / TabSyn (tabular generation)",
    descKey: "models.dl_d_tabular_diffusion",
    descFallback: "Generative synthetic rows over a numeric/categorical feature matrix (CSV/parquet).",
    badgeKey: "models.dl_badge_generative_tag",
    badgeFallback: "generative",
  },
]

/** Catalog hit returned by /api/workflows/search candidate_workflows[]. */
interface WorkflowHit {
  name: string
  domain: string
  description: string
  filename: string
  score?: number
}

function openDraft(draft: string, onOpenChat?: (draft: string) => void) {
  if (onOpenChat) onOpenChat(draft)
  else window.location.assign(`/?draft=${encodeURIComponent(draft)}`)
}

export interface DeepLearningModelsTabProps {
  /** Override chat navigation (tests / embedding). Defaults to ?draft= bridge. */
  onOpenChat?: (draft: string) => void
}

export function DeepLearningModelsTab({ onOpenChat }: DeepLearningModelsTabProps) {
  const [filter, setFilter] = useState("")
  const [setupType, setSetupType] = useState<string | null>(null)
  const [hits, setHits] = useState<WorkflowHit[]>([])
  const [wfLoading, setWfLoading] = useState(true)
  const [wfError, setWfError] = useState("")
  const setupRef = useRef<HTMLDivElement | null>(null)

  // Section B: debounced search over the real catalog. Empty box → default seed
  // query so the section is populated on open.
  useEffect(() => {
    const query = filter.trim() || DEFAULT_WF_QUERY
    const controller = new AbortController()
    const handle = setTimeout(() => {
      setWfLoading(true)
      setWfError("")
      fetch("/api/workflows/search", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query, limit: 8 }),
        signal: controller.signal,
      })
        .then(async (response) => {
          if (!response.ok) throw new Error(tOr("models.dl_search_error", "Could not search workflows."))
          return response.json()
        })
        .then((body) => {
          if (controller.signal.aborted) return
          const list: WorkflowHit[] = Array.isArray(body?.candidate_workflows)
            ? body.candidate_workflows
            : body?.success && body?.workflow_name
            ? [{ name: body.workflow_name, domain: body.domain ?? "", description: body.description ?? "", filename: body.nextflow_path ?? "" }]
            : []
          setHits(list)
        })
        .catch((cause) => {
          if (!controller.signal.aborted) setWfError(cause.message)
        })
        .finally(() => {
          if (!controller.signal.aborted) setWfLoading(false)
        })
    }, 350)
    return () => {
      controller.abort()
      clearTimeout(handle)
    }
  }, [filter])

  // Section A: filter method cards by their resolved name / family / description.
  const needle = filter.trim().toLowerCase()
  const resolved = METHODS.map((m) => ({
    m,
    name: tOr(m.nameKey, m.nameFallback),
    family: tOr(m.familyKey, m.familyFallback),
    desc: tOr(m.descKey, m.descFallback),
  }))
  const matched = resolved.filter(
    (r) => !needle || `${r.name} ${r.family} ${r.desc}`.toLowerCase().includes(needle),
  )
  // Group the matched methods by family, preserving METHODS order.
  const families: { key: string; family: string; items: typeof matched }[] = []
  for (const r of matched) {
    let group = families.find((g) => g.key === r.m.familyKey)
    if (!group) {
      group = { key: r.m.familyKey, family: r.family, items: [] }
      families.push(group)
    }
    group.items.push(r)
  }

  const launchForm = (type: string) => {
    setSetupType(type)
    // Scroll the setup form into view after it renders (no-op where unsupported).
    requestAnimationFrame(() => {
      try {
        setupRef.current?.scrollIntoView?.({ behavior: "smooth", block: "nearest" })
      } catch {
        /* scrollIntoView is not implemented in some environments (jsdom) */
      }
    })
  }

  return (
    <div className="space-y-3" data-testid="dl-fm-tab">
      {/* Top-of-tab search box — filters BOTH sections. */}
      <div className="relative">
        <Search className="pointer-events-none absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
        <input
          className="block w-full rounded border bg-background py-1.5 pl-7 pr-2 text-sm"
          placeholder={tOr("models.dl_search_placeholder", "Search methods and pre-built models…")}
          value={filter}
          onChange={(event) => setFilter(event.target.value)}
          data-testid="dl-fm-search"
          aria-label={tOr("models.dl_search_placeholder", "Search methods and pre-built models…")}
        />
      </div>

      {/* ── Section A — Train a model (method families) ───────────────────── */}
      <Card data-testid="dl-section-train">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{tOr("models.dl_section_train", "Train a model")}</CardTitle>
          <p className="text-fs-xs text-muted-foreground">
            {tOr(
              "models.dl_train_hint",
              "Method families. A form-ready method opens the training form pre-selected; a generative or LLM method opens in chat because the form cannot configure it yet.",
            )}
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          {families.length ? (
            families.map((group) => (
              <div key={group.key} data-testid={`dl-family-${group.key}`}>
                <p className="mb-1 text-xs font-semibold">{group.family}</p>
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                  {group.items.map((r) => (
                    <div
                      key={r.m.type}
                      className="rounded border px-2 py-1.5 text-xs"
                      data-testid={`dl-method-${r.m.type}`}
                    >
                      <div className="flex items-center gap-1.5">
                        <span className="font-semibold">{r.name}</span>
                        {r.m.panel === "spec" && r.m.badgeKey && (
                          <Badge
                            variant="outline"
                            className="ml-auto gap-1 text-fs-xs"
                            data-testid={`dl-method-badge-${r.m.type}`}
                          >
                            <Sparkles className="h-2.5 w-2.5" />
                            {tOr(r.m.badgeKey, r.m.badgeFallback ?? "")}
                          </Badge>
                        )}
                      </div>
                      <p className="mt-0.5 text-fs-xs text-muted-foreground">{r.desc}</p>
                      <p className="mt-0.5 text-fs-xs uppercase tracking-wide text-muted-foreground">{r.family}</p>
                      <Button
                        size="sm"
                        variant="outline"
                        className="mt-1 h-6 px-2 text-fs-xs"
                        onClick={() => launchForm(r.m.type)}
                        data-testid={`dl-method-configure-${r.m.type}`}
                      >
                        {tOr("models.dl_configure", "Configure")}
                      </Button>
                    </div>
                  ))}
                </div>
              </div>
            ))
          ) : (
            <p className="text-fs-xs text-muted-foreground" data-testid="dl-methods-empty">
              {tOr("models.dl_no_methods", "No methods match your search.")}
            </p>
          )}

          {/* Inline ModelSetup, pre-selected to the chosen form-ready model_type. */}
          {setupType && (
            <div ref={setupRef} className="space-y-1" data-testid="dl-setup">
              <div className="flex items-center gap-2">
                <p className="text-xs font-semibold">{tOr("models.dl_setup_heading", "Configure training")}</p>
                <Button
                  size="sm"
                  variant="ghost"
                  className="ml-auto h-6 gap-1 px-2 text-fs-xs"
                  onClick={() => setSetupType(null)}
                  data-testid="dl-setup-close"
                >
                  <X className="h-3 w-3" />
                  {tOr("models.dl_close", "Close")}
                </Button>
              </div>
              {METHODS.find((m) => m.type === setupType)?.panel === "spec" ? (
                <SpecSetup key={setupType} initialType={setupType} />
              ) : (
                <ModelSetup key={setupType} initialType={setupType} />
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── Section B — Pre-built foundation models & workflows ───────────── */}
      <Card data-testid="dl-section-prebuilt">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">
            {tOr("models.dl_section_prebuilt", "Pre-built foundation models & workflows")}
          </CardTitle>
          <p className="text-fs-xs text-muted-foreground">
            {tOr(
              "models.dl_prebuilt_hint",
              "Searches the real workflow catalog. Open a hit in chat to review and run it.",
            )}
          </p>
        </CardHeader>
        <CardContent className="space-y-2">
          {wfLoading ? (
            <p className="text-fs-xs text-muted-foreground" data-testid="dl-wf-loading">
              {tOr("models.dl_searching", "Searching workflows…")}
            </p>
          ) : wfError ? (
            <p role="alert" className="text-fs-xs text-destructive" data-testid="dl-wf-error">
              {wfError}
            </p>
          ) : hits.length ? (
            hits.map((hit) => (
              <div
                key={hit.filename || hit.name}
                className="rounded border px-2 py-1.5 text-xs"
                data-testid={`dl-wf-${hit.name}`}
              >
                <div className="flex items-center gap-1.5 flex-wrap">
                  <span className="font-semibold">{hit.name}</span>
                  {hit.domain && (
                    <Badge variant="outline" className="text-fs-xs">{tOr(`domain.${hit.domain}`, hit.domain)}</Badge>
                  )}
                  <button
                    type="button"
                    className="ml-auto text-primary hover:underline"
                    onClick={() => openDraft(`Open and run the ${hit.name} workflow.`, onOpenChat)}
                    data-testid={`dl-wf-open-${hit.name}`}
                  >
                    {tOr("models.dl_open_in_chat", "Open in chat →")}
                  </button>
                </div>
                {hit.description && (
                  <p className="mt-0.5 text-fs-xs text-muted-foreground line-clamp-2">{hit.description}</p>
                )}
              </div>
            ))
          ) : (
            <p className="text-fs-xs text-muted-foreground" data-testid="dl-wf-empty">
              {tOr("models.dl_no_workflows", "No matching workflows.")}
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
