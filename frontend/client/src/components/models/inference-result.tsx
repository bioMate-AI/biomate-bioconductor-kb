/**
 * InferenceResultView — routes a completed inference result to the right
 * wave-1 evidence viewer BY EVIDENCE CLASS:
 *
 *   structure -> 3D-structure slot + PlddtChart + PaeHeatmap
 *   genomic   -> SeqTracks
 *   chemical  -> HitGrid
 *
 * The result may be a labelled stub (backend unreachable): shape is correct but
 * carries no measured science, so we badge it and the viewers render their
 * empty/held states honestly. No value is fabricated here.
 */

import { useState } from "react"
import { Badge } from "@/components/ui/badge"
import { AlertTriangle, Boxes } from "lucide-react"
import { PlddtChart } from "@/components/viewers/plddt-chart"
import { PaeHeatmap } from "@/components/viewers/pae-heatmap"
import { SeqTracks, type SeqTrack, type FlaggedInterval } from "@/components/viewers/seq-tracks"
import { HitGrid, type ChemHit, type HitVerdict } from "@/components/viewers/hit-grid"
import type {
  InferenceResult,
  StructureResult,
  GenomicResult,
  ChemicalResult,
  EvidenceClass,
} from "./types"
import { isStub } from "./types"

// The WS1 hit verdicts are open strings; narrow to the viewer's union, default "held".
const HIT_VERDICTS: HitVerdict[] = ["accepted", "flagged", "rejected", "held"]
function toHitVerdict(v: string): HitVerdict {
  return (HIT_VERDICTS as string[]).includes(v) ? (v as HitVerdict) : "held"
}

function StubBanner({ reason }: { reason?: string }) {
  return (
    <div
      className="flex items-start gap-2 rounded border border-amber-500/40 bg-amber-500/5 px-2 py-1.5 text-fs-xs"
      data-testid="inference-stub-badge"
    >
      <AlertTriangle className="h-3.5 w-3.5 shrink-0 text-amber-500 mt-0.5" />
      <div>
        <span className="font-semibold text-amber-600">Shape-only (stub)</span>
        <span className="text-muted-foreground">
          {" "}— the model backend was unreachable, so this shows the result layout without measured
          values.{reason ? ` ${reason}` : ""}
        </span>
      </div>
    </div>
  )
}

interface InferenceResultViewProps {
  result: InferenceResult
  /** Evidence class chosen by the parent for the selected domain. */
  evidenceClass: EvidenceClass
  onOpenModel?: (modelId: string) => void
  className?: string
}

export function InferenceResultView({
  result,
  evidenceClass,
  onOpenModel,
  className,
}: InferenceResultViewProps) {
  const cls = (result.evidenceClass as EvidenceClass) ?? evidenceClass
  const stub = isStub(result)

  return (
    <div className={className} data-testid="inference-result" data-evidence-class={cls}>
      {stub && <StubBanner reason={result.stub_reason} />}

      {cls === "structure" && <StructureView r={result as StructureResult} />}
      {cls === "genomic" && <GenomicView r={result as GenomicResult} />}
      {cls === "chemical" && <ChemicalView r={result as ChemicalResult} onOpenModel={onOpenModel} />}
    </div>
  )
}

// ── structure ────────────────────────────────────────────────────────────────
function StructureView({ r }: { r: StructureResult }) {
  // pLDDT chart and structure selection are ONE selection (Spec 03 §3.8.1).
  // The inference backend returns a file *ref* (a string), not a fetchable
  // OutputDataset, so we cannot mount a live 3D viewer here — but we still wire
  // the selection so the slot names the residue the 3D view would centre on,
  // and it lands live once the structure file is opened in the full step view.
  const [selected, setSelected] = useState<number | null>(null)

  return (
    <div className="space-y-3 mt-2" data-testid="inference-structure">
      {/* 3D-structure slot — the backend returns a file ref, not a fetchable
          OutputDataset, so we name what goes here rather than faking a viewer. */}
      <div
        className="rounded border bg-muted/40 flex flex-col items-center justify-center py-8 text-center"
        data-testid="inference-structure-slot"
        data-selected-residue={selected ?? ''}
      >
        <Boxes className="h-6 w-6 text-muted-foreground mb-1" />
        <span className="text-xs text-muted-foreground">3D structure viewer</span>
        {r.structureFileRef ? (
          <span className="text-fs-xs font-mono text-muted-foreground mt-1 break-all px-2">
            {r.structureFileRef}
          </span>
        ) : (
          <span className="text-fs-xs text-muted-foreground mt-1">no structure file returned</span>
        )}
        {selected !== null && (
          <span
            className="text-fs-xs text-muted-foreground mt-1"
            data-testid="inference-structure-selection"
          >
            centred on residue {selected} — open the structure file to view
          </span>
        )}
      </div>
      <PlddtChart
        plddt={r.plddt ?? []}
        regions={r.regions ?? []}
        onSelectResidue={setSelected}
      />
      <PaeHeatmap pae={r.pae ?? []} />
    </div>
  )
}

// ── genomic ──────────────────────────────────────────────────────────────────
function GenomicView({ r }: { r: GenomicResult }) {
  // Map WS1's interval objects to the SeqTracks tuple contract.
  const tracks: SeqTrack[] = (r.tracks ?? []).map((t) => ({
    kind: t.kind,
    name: t.name,
    values: t.values,
    intervals: (t.intervals ?? []).map((iv) => [iv.start, iv.end] as [number, number]),
  }))
  const flagged: FlaggedInterval[] = (r.flagged ?? []).map((f) => ({
    start: f.start,
    end: f.end,
    context: f.context,
    why: f.why,
  }))
  return (
    <div className="mt-2" data-testid="inference-genomic">
      <SeqTracks locus={r.locus ?? "user-supplied"} tracks={tracks} flagged={flagged} />
    </div>
  )
}

// ── chemical ─────────────────────────────────────────────────────────────────
function ChemicalView({
  r,
  onOpenModel,
}: {
  r: ChemicalResult
  onOpenModel?: (modelId: string) => void
}) {
  const hits: ChemHit[] = (r.hits ?? []).map((h) => ({
    id: h.id,
    smiles: h.smiles,
    // A stub/held hit has no measured score — keep it null (NOT 0) so HitGrid
    // sorts it as unranked rather than as the worst real score.
    score: h.score ?? null,
    confidence: h.confidence,
    herg: h.herg ?? "—",
    drugLike: h.drugLike ?? "—",
    verdict: toHitVerdict(h.verdict),
  }))
  return (
    <div className="mt-2" data-testid="inference-chemical">
      <HitGrid hits={hits} onOpenModel={onOpenModel} />
    </div>
  )
}
