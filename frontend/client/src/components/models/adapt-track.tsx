/**
 * Adapt track — "house style". The adaptation pillar, surfaced.
 *
 * What it HONESTLY is: BioMate records the phrasings you accept when you edit its
 * regulatory / report drafts (the `after` you kept vs. the `before` it proposed).
 * "Apply" compiles those accepted exemplars into a per-project retrieval index that
 * BioMate consults when it writes — so it reuses YOUR wording. It PERSONALISES
 * output; it does NOT retrain model weights. (Weight fine-tuning / LoRA is a
 * separate, gated path, not this button.) The copy here says exactly that — no
 * "training" language over a retrieval compile.
 *
 * Wires the existing, tested hooks (useAdaptTrack / useAdaptToggle /
 * useAdaptRetrain). Every string comes from the models.* i18n namespace.
 */
import { useState } from "react"
import { t } from "@/lib/i18n"
import { useActiveProjectSafe } from "@/contexts/active-project-context"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { useAdaptTrack, useAdaptToggle, useAdaptRetrain } from "./models-api"

export function AdaptTrack({ project }: { project?: string }) {
  const ctx = useActiveProjectSafe()
  const projectId = project || ctx?.activeProjectId || ""
  const scoped = projectId || undefined
  const query = useAdaptTrack(scoped)
  const toggle = useAdaptToggle()
  const retrain = useAdaptRetrain()
  const [msg, setMsg] = useState("")
  const [err, setErr] = useState("")

  const pairs = query.data?.pairs ?? []
  const pending = query.data?.pendingCount ?? 0
  const activeCount = pairs.filter((p) => p.on).length

  const apply = async () => {
    setMsg("")
    setErr("")
    try {
      const res = await retrain.mutateAsync({ project: scoped })
      setMsg(t("models.adapt_applied", { n: String(res?.edit_pair_count ?? activeCount) }))
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e))
    }
  }

  return (
    <div className="space-y-3" data-testid="adapt-track">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{t("models.adapt_heading")}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {/* What it is, and — critically — what it is NOT. */}
          <p className="text-fs-xs text-muted-foreground" data-testid="adapt-intro">
            {t("models.adapt_intro")}
          </p>
          <p className="text-fs-xs text-muted-foreground" data-testid="adapt-mechanism">
            {t("models.adapt_mechanism")}
          </p>
          <div className="flex flex-wrap items-center gap-2 pt-1">
            <Button
              type="button"
              size="sm"
              className="h-7 text-xs"
              disabled={retrain.isPending || activeCount === 0}
              onClick={apply}
              data-testid="adapt-apply"
            >
              {retrain.isPending ? t("models.adapt_applying") : t("models.adapt_apply")}
            </Button>
            <span className="text-fs-xs text-muted-foreground" data-testid="adapt-pending">
              {t("models.adapt_pending", { n: String(pending) })}
            </span>
          </div>
          {msg && (
            <p className="text-fs-xs text-emerald-600" role="status" data-testid="adapt-applied-msg">
              {msg}
            </p>
          )}
          {err && (
            <p className="text-fs-xs text-destructive" role="alert" data-testid="adapt-error">
              {err}
            </p>
          )}
          <p className="text-fs-xs text-muted-foreground/70" data-testid="adapt-lora-note">
            {t("models.adapt_lora_note")}
          </p>
        </CardContent>
      </Card>

      {query.isPending ? (
        <p role="status" className="text-fs-xs text-muted-foreground">
          {t("models.activity_loading")}
        </p>
      ) : query.isError ? (
        <div role="alert" className="rounded-lg border border-destructive/30 p-3 text-fs-xs" data-testid="adapt-load-error">
          <p className="text-muted-foreground">{t("models.activity_error")}</p>
          <Button variant="outline" size="sm" className="mt-1 h-7 text-xs" onClick={() => query.refetch()}>
            {t("models.retry")}
          </Button>
        </div>
      ) : pairs.length === 0 ? (
        <p className="text-fs-xs text-muted-foreground" data-testid="adapt-empty">
          {t("models.adapt_empty")}
        </p>
      ) : (
        <div className="space-y-2" data-testid="adapt-pairs">
          {pairs.map((p) => (
            <div key={p.id} className="space-y-1 rounded-lg border p-2" data-testid={`adapt-pair-${p.id}`}>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-1.5">
                  {p.scope && (
                    <Badge variant="outline" className="text-fs-xs">
                      {p.scope}
                    </Badge>
                  )}
                  {p.source && <span className="text-fs-xs text-muted-foreground">{p.source}</span>}
                </div>
                <Button
                  type="button"
                  size="sm"
                  variant={p.on ? "default" : "outline"}
                  className="h-6 text-xs"
                  disabled={toggle.isPending}
                  onClick={() => toggle.mutate({ pairId: p.id, on: !p.on, project: scoped })}
                  data-testid={`adapt-toggle-${p.id}`}
                  aria-pressed={p.on}
                >
                  {p.on ? t("models.adapt_on") : t("models.adapt_off")}
                </Button>
              </div>
              <div className="grid grid-cols-1 gap-1 sm:grid-cols-2">
                <div>
                  <span className="text-fs-xs text-muted-foreground">{t("models.adapt_before")}</span>
                  <p className="text-fs-xs text-muted-foreground line-through opacity-70">{p.before}</p>
                </div>
                <div>
                  <span className="text-fs-xs text-muted-foreground">{t("models.adapt_after")}</span>
                  <p className="text-fs-xs text-emerald-700 dark:text-emerald-400">{p.after}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
