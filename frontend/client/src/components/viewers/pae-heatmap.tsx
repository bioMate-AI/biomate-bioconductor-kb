/**
 * PaeHeatmap — pairwise alignment error (PAE) n×n matrix for a predicted
 * structure.
 *
 * Answers the question per-residue confidence cannot: "can I trust the relative
 * placement of these two domains?". Two confident domains can still be placed
 * wrongly relative to each other — that is what this reads.
 *
 * Colour scale 0–30 Å: blue (low error, reliable) → red (high error). Hover a
 * cell to see the block indices and whether the relative placement is reliable
 * (< 8 Å) or should be treated as unresolved.
 *
 * Pure presentational — all data via props.
 */

import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Grid3x3 } from "lucide-react"

// ---------------------------------------------------------------------------
// Types (data contract)
// ---------------------------------------------------------------------------

export interface PaeHeatmapProps {
  /** n×n matrix of expected position errors in Ångström (0 = perfect). */
  pae: number[][]
  /** Threshold (Å) below which relative placement is considered reliable. */
  reliableThreshold?: number
  className?: string
}

// blue (low) → red (high), clamped at maxScale Å
function paeColor(v: number, maxScale: number): string {
  const t = Math.min(1, Math.max(0, v / maxScale))
  const r = Math.round(30 + 210 * t)
  const g = Math.round(80 + 140 * (1 - Math.abs(t - 0.5) * 2)) // brighter mid
  const b = Math.round(200 - 160 * t)
  return `rgb(${r},${g},${b})`
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function PaeHeatmap({ pae, reliableThreshold = 8, className }: PaeHeatmapProps) {
  const [cell, setCell] = useState<{ i: number; j: number; v: number } | null>(null)

  const n = pae.length
  const MAX_SCALE = 30

  if (n === 0) {
    return (
      <Card className={className} data-testid="pae-heatmap">
        <CardContent className="py-4">
          <p className="text-xs text-muted-foreground">No pairwise alignment error data available.</p>
        </CardContent>
      </Card>
    )
  }

  const reliable = cell != null && cell.v < reliableThreshold

  return (
    <Card className={className} data-testid="pae-heatmap">
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-sm">
          <Grid3x3 className="h-4 w-4" />
          Pairwise alignment error
        </CardTitle>
        <CardDescription className="text-[10px] text-muted-foreground">
          lower is better · Ångström · blue = reliable, red = unresolved
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-2">
        <div
          className="grid gap-0 w-full max-w-[320px] mx-auto aspect-square rounded overflow-hidden border"
          style={{ gridTemplateColumns: `repeat(${n}, 1fr)` }}
          data-testid="pae-grid"
          role="img"
          aria-label="Pairwise alignment error heatmap"
        >
          {pae.flatMap((row, i) =>
            row.map((v, j) => (
              <span
                key={`${i}-${j}`}
                data-testid={`pae-cell-${i}-${j}`}
                className="block w-full h-full"
                style={{ background: paeColor(v, MAX_SCALE), aspectRatio: "1 / 1" }}
                onMouseEnter={() => setCell({ i, j, v })}
                onMouseLeave={() => setCell(null)}
              />
            )),
          )}
        </div>

        {/* Read-out */}
        <div className="flex items-center gap-2 flex-wrap text-xs min-h-[20px]" data-testid="pae-readout">
          {cell ? (
            <>
              <span className="font-mono">block {cell.i + 1} × {cell.j + 1}</span>
              <span className="font-mono font-semibold">{cell.v} Å</span>
              <span
                className="text-[10px]"
                style={{ color: reliable ? "var(--ok)" : "var(--err)" }}
              >
                {reliable
                  ? "relative placement reliable (<8 Å)"
                  : "treat as unresolved"}
              </span>
            </>
          ) : (
            <span className="text-[10px] text-muted-foreground">
              Two confident domains can still be placed wrongly relative to each other — that is
              what this reads.
            </span>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
