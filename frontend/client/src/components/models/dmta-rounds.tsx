/**
 * DMTA Rounds — Models Molecular tab.
 *
 * Real campaign Bayesian loop controls (create campaign, start/stop, propose next
 * round) via /api/drug-discovery/{id}/…. Campaign id = project id so
 * GET /api/model-tracks/optimise resolves the same loop. Never invents scores;
 * trigger/propose surfaces the API error when assay data or a virtual library
 * is missing.
 */
import { useCallback, useState } from "react"
import { useQueryClient } from "@tanstack/react-query"
import { t } from "@/lib/i18n"
import { useActiveProjectSafe } from "@/contexts/active-project-context"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { HintTip } from "@/components/ui/hint-tip"
import { Loader2, Play, Square, RefreshCw } from "lucide-react"
import { seedLoopFixturesForCampaign } from "./dmta-loop-fixtures"
import type { OptimiseData } from "./models-panel"

async function errorDetail(res: Response): Promise<string> {
  const body = await res.json().catch(() => ({}))
  const v = body?.detail ?? body?.message ?? body?.error
  return typeof v === "string" ? v : `HTTP ${res.status}`
}

function proposalVerdictColor(verdict: string): string {
  if (verdict === "accepted") return "#22c55e"
  if (/reject/i.test(verdict)) return "#ef4444"
  return "#f59e0b"
}

export function RoundsSection({
  data,
  projectId,
  onOpenModel,
}: {
  data?: OptimiseData
  projectId?: string
  onOpenModel: (id: string) => void
}) {
  const context = useActiveProjectSafe()
  const qc = useQueryClient()
  const campaignId = projectId || context?.activeProjectId || ""
  const [busy, setBusy] = useState<"create" | "start" | "stop" | "trigger" | null>(null)
  const [actionError, setActionError] = useState("")
  const [actionOk, setActionOk] = useState("")
  const [localCampaign, setLocalCampaign] = useState(campaignId)
  const [modality, setModality] = useState<"small_molecule" | "peptide" | "biologic">("small_molecule")
  const [seed, setSeed] = useState("")

  const refresh = useCallback(() => {
    qc.invalidateQueries({ queryKey: ["/api/model-tracks/optimise"] })
  }, [qc])

  const createCampaign = async () => {
    if (!campaignId) {
      setActionError(t("models.rounds_need_project"))
      return
    }
    setBusy("create"); setActionError(""); setActionOk("")
    try {
      const res = await fetch("/api/drug-discovery/campaigns", {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          campaign_id: campaignId,
          molecule_name: "Models DMTA loop",
          objective: "balance",
          user_id: "",
          modality,
        }),
      })
      // 409 = already exists for this project id — still seed fixtures so propose works.
      if (!res.ok && res.status !== 409) throw new Error(await errorDetail(res))
      setLocalCampaign(campaignId)
      if (modality === "small_molecule") {
        // Only the small-molecule demo (real public BACE data) is bundled. We do
        // NOT fabricate peptide/biologic assay values — those campaigns start
        // empty and the user ingests their own measured sequences.
        const seed = await seedLoopFixturesForCampaign(campaignId)
        setActionOk(
          t("models.rounds_created_seeded", {
            assays: String(seed.assaysIngested),
            library: String(seed.librarySize),
          }),
        )
        if (seed.warnings.length) setActionError(seed.warnings.join("; "))
      } else {
        setActionOk(t("models.rounds_created_sequence", { modality: t(`models.rounds_modality_${modality}`) }))
      }
      refresh()
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(null)
    }
  }

  const generateLibrary = async () => {
    const id = localCampaign || campaignId
    if (!id) { setActionError(t("models.rounds_need_project")); return }
    if (!seed.trim()) { setActionError(t("models.rounds_gen_need_seed")); return }
    setBusy("trigger"); setActionError(""); setActionOk("")
    try {
      const res = await fetch(`/api/drug-discovery/${encodeURIComponent(id)}/generate-library`, {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ seed: seed.trim(), max_size: 200, modality }),
      })
      if (!res.ok) throw new Error(await errorDetail(res))
      const body = await res.json().catch(() => ({})) as { library_size?: number }
      setActionOk(t("models.rounds_gen_ok", { n: String(body.library_size ?? 0) }))
      refresh()
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(null)
    }
  }

  const loopAction = async (action: "start" | "stop" | "trigger") => {
    const id = localCampaign || campaignId
    if (!id) {
      setActionError(t("models.rounds_need_project"))
      return
    }
    setBusy(action); setActionError(""); setActionOk("")
    try {
      const res = await fetch(`/api/drug-discovery/${encodeURIComponent(id)}/retrain/${action}`, {
        method: "POST", credentials: "include",
      })
      if (!res.ok) throw new Error(await errorDetail(res))
      setActionOk(
        action === "start" ? t("models.rounds_started")
          : action === "stop" ? t("models.rounds_stopped_ok")
            : t("models.rounds_triggered"),
      )
      refresh()
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(null)
    }
  }

  const controls = (
    <div className="space-y-2" data-testid="optimise-controls">
      <p className="text-fs-xs text-muted-foreground">{t("models.rounds_controls_hint")}</p>
      <div className="flex flex-wrap items-center gap-1.5" data-testid="optimise-modality" role="group" aria-label={t("models.rounds_modality_label")}>
        <span className="text-fs-xs text-muted-foreground">{t("models.rounds_modality_label")}</span>
        {(["small_molecule", "peptide", "biologic"] as const).map((m) => (
          <Button key={m} type="button" size="sm" variant={modality === m ? "default" : "outline"}
            className="h-7 text-xs" disabled={!!busy} onClick={() => setModality(m)}
            data-testid={`optimise-modality-${m}`}>
            {t(`models.rounds_modality_${m}`)}
          </Button>
        ))}
      </div>
      {modality !== "small_molecule" && (
        <div className="flex flex-wrap items-center gap-1.5" data-testid="optimise-generate">
          <input
            type="text" value={seed} onChange={(e) => setSeed(e.target.value)}
            placeholder={t("models.rounds_gen_seed_placeholder")} spellCheck={false}
            className="h-7 w-56 rounded border bg-background px-2 text-xs font-mono"
            data-testid="optimise-gen-seed" aria-label={t("models.rounds_gen_seed_placeholder")}
          />
          <Button type="button" size="sm" variant="outline" className="h-7 text-xs"
            disabled={!!busy || !campaignId || !seed.trim()} onClick={generateLibrary}
            data-testid="optimise-generate-library">
            {t("models.rounds_gen_button")}
          </Button>
          <span className="text-fs-xs text-muted-foreground">{t("models.rounds_gen_hint")}</span>
        </div>
      )}
      <div className="flex flex-wrap gap-1.5">
        <Button type="button" size="sm" variant="outline" className="h-7 text-xs"
          disabled={!!busy || !campaignId} onClick={createCampaign}
          data-testid="optimise-create-campaign">
          {busy === "create" ? <Loader2 className="mr-1 h-3 w-3 animate-spin" /> : null}
          {t("models.rounds_create")}
        </Button>
        <Button type="button" size="sm" className="h-7 text-xs"
          disabled={!!busy || !campaignId} onClick={() => loopAction("start")}
          data-testid="optimise-start">
          {busy === "start" ? <Loader2 className="mr-1 h-3 w-3 animate-spin" /> : <Play className="mr-1 h-3 w-3" />}
          {t("models.rounds_start")}
        </Button>
        <Button type="button" size="sm" variant="outline" className="h-7 text-xs"
          disabled={!!busy || !campaignId} onClick={() => loopAction("stop")}
          data-testid="optimise-stop">
          {busy === "stop" ? <Loader2 className="mr-1 h-3 w-3 animate-spin" /> : <Square className="mr-1 h-3 w-3" />}
          {t("models.rounds_stop")}
        </Button>
        <Button type="button" size="sm" variant="secondary" className="h-7 text-xs"
          disabled={!!busy || !campaignId} onClick={() => loopAction("trigger")}
          data-testid="optimise-trigger">
          {busy === "trigger" ? <Loader2 className="mr-1 h-3 w-3 animate-spin" /> : <RefreshCw className="mr-1 h-3 w-3" />}
          {t("models.rounds_propose")}
        </Button>
        <HintTip hint={t("models.hint_bayesian_round")}>
          <span className="inline-flex h-7 items-center px-1 text-fs-xs text-muted-foreground underline decoration-dotted"
            data-testid="optimise-jargon-bayesian">{t("models.rounds_bayesian_label")}</span>
        </HintTip>
      </div>
      {!campaignId && (
        <p className="text-fs-xs text-muted-foreground" data-testid="optimise-need-project">
          {t("models.rounds_need_project")}
        </p>
      )}
      {actionOk && <p className="text-fs-xs text-muted-foreground" data-testid="optimise-action-ok">{actionOk}</p>}
      {actionError && (
        <p className="text-fs-xs text-destructive break-words" data-testid="optimise-action-error">{actionError}</p>
      )}
    </div>
  )

  if (!data) {
    return (
      <Card data-testid="track-optimise">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{t("models.rounds_heading")}</CardTitle>
          <p className="text-fs-xs text-muted-foreground">{t("models.tab_purpose_molecular_rounds")}</p>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-xs text-muted-foreground" data-testid="optimise-empty">
            {t("models.rounds_empty")}
          </p>
          {controls}
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-3" data-testid="track-optimise">
      <Card data-testid="optimise-loop">
        <CardHeader className="pb-2">
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle className="text-sm">{t("models.rounds_heading")}</CardTitle>
            <Badge
              variant="outline"
              className="ml-auto gap-1 text-fs-xs"
              style={{ color: data.running ? "#22c55e" : "#94a3b8" }}
              data-testid="optimise-loop-state"
            >
              <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: data.running ? "#22c55e" : "#94a3b8" }} />
              {data.running ? t("models.rounds_running", { round: String(data.round) }) : t("models.rounds_stopped")}
            </Badge>
          </div>
        </CardHeader>
        <CardContent className="space-y-2">
          <div className="grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1 text-xs">
            <span className="text-muted-foreground">{t("models.rounds_surrogate")}</span>
            <span className="flex flex-wrap items-center gap-1" data-testid="optimise-surrogates">
              {data.surrogates.length ? (
                data.surrogates.map((s, i) => (
                  <span key={s.id} className="flex items-center gap-1">
                    {i > 0 && <span className="text-muted-foreground">+</span>}
                    <button
                      type="button"
                      className="font-mono text-primary hover:underline"
                      onClick={() => onOpenModel(s.id)}
                      data-testid={`optimise-surrogate-${s.id}`}
                    >
                      {s.label}
                    </button>
                  </span>
                ))
              ) : (
                <span className="text-muted-foreground">—</span>
              )}
            </span>
            {data.budget && (
              <>
                <span className="text-muted-foreground">
                  <HintTip hint={t("models.hint_budget")}>
                    <span className="underline decoration-dotted">{t("models.rounds_budget")}</span>
                  </HintTip>
                </span>
                <span>{data.budget}</span>
              </>
            )}
            {data.refitPolicy && (
              <>
                <span className="text-muted-foreground">{t("models.rounds_refit")}</span>
                <span>{data.refitPolicy}</span>
              </>
            )}
          </div>
          <div className="space-y-1" data-testid="optimise-rounds">
            {data.rounds.map((r) => (
              <div key={r.round} className="flex items-center gap-2 text-xs" data-testid={`optimise-round-${r.round}`}>
                <span className="inline-block h-1.5 w-1.5 shrink-0 rounded-full bg-muted-foreground" />
                <span className="font-semibold">{r.round}</span>
                <Badge variant="outline" className="text-fs-xs">{r.status}</Badge>
                <span>{r.what}</span>
                <span className="ml-auto text-fs-xs text-muted-foreground">{r.when}</span>
              </div>
            ))}
          </div>
          {controls}
        </CardContent>
      </Card>

      <Card data-testid="optimise-proposal">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{t("models.rounds_proposal", { round: String(data.round) })}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-1">
          <div className="rounded border text-xs" data-testid="optimise-proposal-table">
            <div className="grid grid-cols-[1.2fr_0.8fr_0.9fr_1.2fr] gap-2 bg-muted px-2 py-1 font-semibold">
              <span>{t("models.col_candidate")}</span>
              <span>{t("models.col_score")}</span>
              <span>{t("models.col_confidence")}</span>
              <span>{t("models.col_verdict")}</span>
            </div>
            {data.proposal.length ? (
              data.proposal.map((p) => (
                <div
                  key={p.id}
                  className="grid grid-cols-[1.2fr_0.8fr_0.9fr_1.2fr] items-center gap-2 border-t px-2 py-1"
                  data-testid={`optimise-proposal-${p.id}`}
                >
                  <span className="truncate font-mono font-semibold">{p.id}</span>
                  <span className="font-mono">{p.score}</span>
                  <span className="text-muted-foreground">{p.confidence}</span>
                  <Badge
                    variant="outline"
                    className="w-fit gap-1 text-fs-xs"
                    style={{ color: proposalVerdictColor(p.verdict) }}
                    data-testid={`optimise-proposal-verdict-${p.id}`}
                  >
                    <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: proposalVerdictColor(p.verdict) }} />
                    {p.verdict}
                  </Badge>
                </div>
              ))
            ) : (
              <p className="border-t px-2 py-2 text-fs-xs text-muted-foreground">{t("models.rounds_no_proposal")}</p>
            )}
          </div>
          <p className="pt-1 text-fs-xs text-muted-foreground">{t("models.rounds_rejected_note")}</p>
        </CardContent>
      </Card>
    </div>
  )
}
