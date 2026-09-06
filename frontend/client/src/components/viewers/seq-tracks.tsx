/**
 * SeqTracks — genomic score tracks for the sequence/variant-effect models.
 *
 * A per-base score is only actionable as an interval. The flagged-intervals
 * list is the output; the tracks are how you check it.
 *
 * Track kinds:
 *   line  — a per-base numeric signal (model score, conservation) drawn as an
 *           area+line, values in `values`
 *   marks — highlighted intervals [start,end] drawn as bars, in `intervals`
 *   ticks — point features (variants) drawn as vertical ticks, positions in
 *           `values`
 *
 * Pure presentational — all data via props.
 */

import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { AlignLeft } from "lucide-react"

// ---------------------------------------------------------------------------
// Types (data contract)
// ---------------------------------------------------------------------------

export interface SeqTrack {
  kind: "line" | "marks" | "ticks"
  name: string
  /** For 'line' (per-base signal 0–100) and 'ticks' (point positions). */
  values?: number[]
  /** For 'marks' — [start, end] intervals in track coordinate space. */
  intervals?: [number, number][]
}

export interface FlaggedInterval {
  start: number
  end: number
  context: string
  why: string
}

export interface SeqTracksProps {
  /** Human-readable locus label, e.g. "chr7:5,527,100–5,530,600". */
  locus: string
  tracks: SeqTrack[]
  /** The actionable output: intervals the model flagged for review. */
  flagged?: FlaggedInterval[]
  /** Length of the locus in bp (used only for a header chip). */
  bp?: number
  /** Fired when a flagged interval's "open" button is clicked. */
  onOpenInterval?: (interval: FlaggedInterval) => void
  className?: string
}

// ---------------------------------------------------------------------------
// Track geometry helpers
// ---------------------------------------------------------------------------

const VW = 100 // svg viewbox width
const VH = 20  // svg viewbox height

function linePath(values: number[]): string {
  if (values.length === 0) return ""
  const denom = Math.max(1, values.length - 1)
  return values
    .map((v, i) => `${i === 0 ? "M" : "L"}${((i * VW) / denom).toFixed(2)},${(VH - (VH - 2) * v / 100).toFixed(2)}`)
    .join(" ")
}

// Coordinate extent used to normalise mark/tick positions to the viewbox.
function extentOf(track: SeqTrack): number {
  if (track.kind === "marks") {
    return Math.max(1, ...(track.intervals ?? []).map(([, b]) => b))
  }
  return Math.max(1, ...(track.values ?? [0]))
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function SeqTracks({ locus, tracks, flagged = [], bp, onOpenInterval, className }: SeqTracksProps) {
  return (
    <Card className={className} data-testid="seq-tracks">
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-sm">
          <AlignLeft className="h-4 w-4" />
          Score tracks
        </CardTitle>
        <CardDescription className="flex items-center gap-2 flex-wrap">
          <Badge variant="outline" className="text-xs font-mono">{locus}</Badge>
          {bp != null && (
            <span className="text-[10px] text-muted-foreground">{bp.toLocaleString()} bp</span>
          )}
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-3">
        {/* Tracks */}
        <div className="space-y-1" data-testid="seq-track-rows">
          {tracks.map(track => {
            const extent = extentOf(track)
            return (
              <div key={track.name} className="flex items-center gap-2" data-testid={`seq-track-${track.name}`}>
                <span className="text-[10px] text-muted-foreground w-24 shrink-0 truncate" title={track.name}>
                  {track.name}
                </span>
                <svg
                  viewBox={`0 0 ${VW} ${VH}`}
                  preserveAspectRatio="none"
                  className="flex-1 h-6 rounded bg-muted/30"
                  role="img"
                  aria-label={track.name}
                >
                  {track.kind === "line" && track.values && (
                    <>
                      {/* reference muted blue for the per-base signal */}
                      <path d={`${linePath(track.values)} L${VW},${VH} L0,${VH} Z`} fill="rgba(75,143,214,0.12)" />
                      <path d={linePath(track.values)} fill="none" stroke="#4b8fd6" strokeWidth={0.7} vectorEffect="non-scaling-stroke" />
                    </>
                  )}
                  {track.kind === "marks" && (track.intervals ?? []).map(([a, b], i) => (
                    <rect
                      key={i}
                      x={(a * VW) / extent}
                      y={4}
                      width={((b - a) * VW) / extent}
                      height={12}
                      fill="var(--warn)"
                      opacity={0.75}
                      rx={0.6}
                    />
                  ))}
                  {track.kind === "ticks" && (track.values ?? []).map((x, i) => (
                    <rect key={i} x={(x * VW) / extent} y={3} width={0.5} height={14} fill="var(--text-dim)" />
                  ))}
                </svg>
              </div>
            )
          })}
        </div>

        {/* Flagged intervals — the actionable output */}
        {flagged.length > 0 && (
          <div className="space-y-1" data-testid="seq-flagged">
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Flagged intervals</p>
            {flagged.map((f, i) => (
              <div
                key={`${f.start}-${f.end}-${i}`}
                className="flex items-center gap-2 rounded border px-2 py-1 flex-wrap"
                data-testid={`seq-flag-${i}`}
              >
                <span className="text-[11px] font-mono">{f.start.toLocaleString()}–{f.end.toLocaleString()}</span>
                <Badge variant="outline" className="text-[10px]">{f.context}</Badge>
                <span className="text-[10px] text-muted-foreground flex-1 min-w-[8rem]">{f.why}</span>
                <button
                  type="button"
                  className="text-[10px] text-primary hover:underline shrink-0"
                  onClick={() => onOpenInterval?.(f)}
                >
                  open
                </button>
              </div>
            ))}
          </div>
        )}

        <p className="text-[10px] text-muted-foreground">
          A per-base score is only actionable as an interval. Flagged regions are the output; the
          tracks are how you check them.
        </p>
      </CardContent>
    </Card>
  )
}
