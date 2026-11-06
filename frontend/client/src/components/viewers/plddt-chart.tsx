/**
 * PlddtChart — per-residue confidence bar chart for a predicted structure.
 *
 * The honest companion to a 3D structure picture: it names which parts of the
 * model to believe. Colour bands follow the AlphaFold pLDDT convention:
 *   90+   very high  (green)
 *   70–89 confident  (blue)
 *   50–69 low        (amber)
 *   <50   very low   (red)
 *
 * Pure presentational — all data arrives via props. Click a residue (or a
 * region row) to fire onSelectResidue(n), which the parent uses to centre the
 * 3Dmol structure-viewer on residue n (1-based). Chart selection and structure
 * selection are one selection, not two.
 */

import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Activity } from "lucide-react"

// ---------------------------------------------------------------------------
// Types (data contract — mirrored by the backend that returns exactly this)
// ---------------------------------------------------------------------------

export interface PlddtRegion {
  label: string
  start: number   // 1-based inclusive
  end: number     // 1-based inclusive
  note?: string
}

export interface PlddtChartProps {
  /** Per-residue pLDDT (0–100), one entry per residue, index 0 = residue 1. */
  plddt: number[]
  /** Notable regions (flexible loops, confident core, …). */
  regions?: PlddtRegion[]
  /**
   * Called with a 1-based residue number when the user clicks a bar or a
   * region row. Wire this to structure-viewer to centre the 3D view.
   */
  onSelectResidue?: (residue: number) => void
  className?: string
}

// ---------------------------------------------------------------------------
// Colour bands
// ---------------------------------------------------------------------------

interface Band { min: number; color: string; label: string }

// Band colours follow the reference design: very-high/low map to the status
// tokens (--ok/--warn), confident/very-low use the reference's muted blue/red
// (#4b8fd6 / #c0563f) rather than the saturated Tailwind primaries.
const PL_BANDS: Band[] = [
  { min: 90, color: "var(--ok)",   label: "very high" }, // green
  { min: 70, color: "#4b8fd6",     label: "confident" }, // reference blue
  { min: 50, color: "var(--warn)", label: "low" },       // amber
  { min: 0,  color: "#c0563f",     label: "very low" },  // reference red
]

function bandOf(v: number): Band {
  return PL_BANDS.find(b => v >= b.min) ?? PL_BANDS[PL_BANDS.length - 1]
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function PlddtChart({ plddt, regions = [], onSelectResidue, className }: PlddtChartProps) {
  const [hover, setHover] = useState<number | null>(null)
  const [sel, setSel] = useState<number | null>(null)

  const n = plddt.length

  if (n === 0) {
    return (
      <Card className={className} data-testid="plddt-chart">
        <CardContent className="py-4">
          <p className="text-xs text-muted-foreground">No per-residue confidence data available.</p>
        </CardContent>
      </Card>
    )
  }

  const mean = Math.round(plddt.reduce((a, b) => a + b, 0) / n)
  const W = 100
  const H = 34

  // Index of the residue currently being read (hover takes precedence).
  const active = hover !== null ? hover : sel

  const select = (idx: number) => {
    setSel(idx)
    onSelectResidue?.(idx + 1) // 1-based residue number
  }

  return (
    <Card className={className} data-testid="plddt-chart">
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-sm">
          <Activity className="h-4 w-4" />
          Per-residue confidence
        </CardTitle>
        <CardDescription className="flex items-center gap-2 flex-wrap">
          <Badge variant="outline" className="text-xs" data-testid="plddt-mean">mean {mean}</Badge>
          <span className="flex items-center gap-2 flex-wrap text-[10px] text-muted-foreground">
            {PL_BANDS.map(b => (
              <span key={b.label} className="inline-flex items-center gap-1">
                <span className="inline-block h-2 w-2 rounded-sm" style={{ background: b.color }} />
                {b.label}
              </span>
            ))}
          </span>
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-2">
        {/* Bar chart */}
        <div className="w-full">
          <svg
            viewBox={`0 0 ${W} ${H}`}
            preserveAspectRatio="none"
            className="w-full"
            style={{ height: 120 }}
            role="img"
            aria-label="Per-residue confidence bar chart"
          >
            {[50, 70, 90].map(y => (
              <line
                key={y}
                x1={0}
                x2={W}
                y1={H - (H * y) / 100}
                y2={H - (H * y) / 100}
                stroke="var(--border)"
                strokeWidth={0.25}
                vectorEffect="non-scaling-stroke"
              />
            ))}
            {plddt.map((v, i) => (
              <rect
                key={i}
                data-testid={`plddt-bar-${i}`}
                x={(i * W) / n}
                y={H - (H * v) / 100}
                width={(W / n) * 0.92}
                height={(H * v) / 100}
                fill={bandOf(v).color}
                opacity={hover === null || hover === i ? 1 : 0.55}
                onMouseEnter={() => setHover(i)}
                onMouseLeave={() => setHover(null)}
                onClick={() => select(i)}
                style={{ cursor: "pointer" }}
              />
            ))}
          </svg>
          <div className="flex justify-between text-[10px] text-muted-foreground font-mono px-0.5">
            <span>1</span>
            <span>{n}</span>
          </div>
        </div>

        {/* Read-out */}
        <div className="flex items-center gap-2 flex-wrap text-xs min-h-[20px]" data-testid="plddt-readout">
          {active !== null ? (
            <>
              <span className="font-mono font-semibold">residue {active + 1}</span>
              <span className="font-mono">{plddt[active]}</span>
              <Badge variant="outline" className="text-xs" style={{ color: bandOf(plddt[active]).color }}>
                {bandOf(plddt[active]).label}
              </Badge>
              <span className="text-[10px] text-muted-foreground">click to centre the 3D view here</span>
            </>
          ) : (
            <span className="text-[10px] text-muted-foreground">
              Hover a residue for its score; click to centre the 3D view on it.
            </span>
          )}
        </div>

        {/* Regions list */}
        {regions.length > 0 && (
          <div className="space-y-1" data-testid="plddt-regions">
            {regions.map(r => {
              const startIdx = Math.max(0, Math.min(n - 1, r.start - 1))
              const b = bandOf(plddt[startIdx])
              return (
                <button
                  key={r.label}
                  type="button"
                  data-testid={`plddt-region-${r.label}`}
                  className="w-full flex items-center gap-2 rounded border px-2 py-1 text-left hover:bg-muted/50 transition-colors"
                  onClick={() => select(startIdx)}
                >
                  <span className="inline-block h-2.5 w-2.5 rounded-full shrink-0" style={{ background: b.color }} />
                  <span className="text-xs font-semibold shrink-0">{r.label}</span>
                  {r.note && <span className="text-[10px] text-muted-foreground truncate">{r.note}</span>}
                </button>
              )
            })}
          </div>
        )}

        <p className="text-[10px] text-muted-foreground">
          A structure picture with no confidence chart invites a claim its low-confidence loops
          cannot support. The two are one output, shown together.
        </p>
      </CardContent>
    </Card>
  )
}
