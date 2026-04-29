/**
 * Motion Histogram Chart
 * Shows per-micrograph total motion distribution from motion_report_batch_*.json.
 * Micrographs with total motion > ~30 Å are typically considered poor quality.
 */

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ReferenceLine, ResponsiveContainer } from 'recharts'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Activity } from 'lucide-react'

interface MotionReportData {
  num_micrographs?: number
  avg_total_motion_A?: number
  min_total_motion_A?: number
  max_total_motion_A?: number
  num_accepted?: number
  per_micrograph_motion_A?: number[]
  step?: string
  batch_id?: string
}

interface MotionHistogramChartProps {
  data: MotionReportData
}

function buildHistogram(values: number[], binCount = 20) {
  if (!values.length) return []
  const min = Math.min(...values)
  const max = Math.max(...values)
  const step = (max - min) / binCount || 1
  const bins = Array.from({ length: binCount }, (_, i) => ({
    range: `${(min + i * step).toFixed(0)}–${(min + (i + 1) * step).toFixed(0)}`,
    midpoint: min + (i + 0.5) * step,
    count: 0,
  }))
  for (const v of values) {
    const idx = Math.min(Math.floor((v - min) / step), binCount - 1)
    bins[idx].count++
  }
  return bins
}

export function MotionHistogramChart({ data }: MotionHistogramChartProps) {
  const perMic = data.per_micrograph_motion_A
  const hasDistribution = Array.isArray(perMic) && perMic.length > 0

  const histData = hasDistribution ? buildHistogram(perMic!) : []
  const mean = data.avg_total_motion_A
  const REJECT_THRESHOLD = 30  // Å — conventional cutoff

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-sm">
          <Activity className="h-4 w-4" />
          Beam-Induced Motion
        </CardTitle>
        <CardDescription className="flex gap-2 flex-wrap">
          {data.num_micrographs != null && (
            <Badge variant="outline" className="text-xs">{data.num_micrographs} micrographs</Badge>
          )}
          {mean != null && (
            <Badge variant="default" className="text-xs">Mean {mean.toFixed(1)} Å</Badge>
          )}
          {data.min_total_motion_A != null && (
            <Badge variant="outline" className="text-xs">
              {data.min_total_motion_A.toFixed(1)}–{data.max_total_motion_A?.toFixed(1)} Å range
            </Badge>
          )}
          {data.batch_id && (
            <Badge variant="outline" className="text-xs">{data.batch_id}</Badge>
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {hasDistribution ? (
          <>
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={histData} margin={{ top: 8, right: 16, bottom: 24, left: 8 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis
                  dataKey="midpoint"
                  type="number"
                  domain={['dataMin', 'dataMax']}
                  label={{ value: 'Total motion (Å)', position: 'insideBottom', offset: -12, fontSize: 11 }}
                  tickFormatter={v => v.toFixed(0)}
                  fontSize={11}
                />
                <YAxis fontSize={11} label={{ value: 'Count', angle: -90, position: 'insideLeft', fontSize: 11 }} />
                <Tooltip formatter={(v: any) => [`${v} micrographs`, 'count']} labelFormatter={v => `~${Number(v).toFixed(0)} Å`} />
                <ReferenceLine x={REJECT_THRESHOLD} stroke="#ef4444" strokeDasharray="4 2"
                  label={{ value: `${REJECT_THRESHOLD} Å cutoff`, position: 'top', fontSize: 10, fill: '#ef4444' }} />
                {mean != null && (
                  <ReferenceLine x={mean} stroke="#3b82f6" strokeDasharray="4 2"
                    label={{ value: 'mean', position: 'insideTopRight', fontSize: 10, fill: '#3b82f6' }} />
                )}
                <Bar dataKey="count" fill="#3b82f6" radius={[2, 2, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
            <p className="text-[10px] text-muted-foreground text-center mt-1">
              Micrographs above {REJECT_THRESHOLD} Å are typically excluded from further processing
            </p>
          </>
        ) : (
          // Summary stats only — per-micrograph array not yet exported by pipeline
          <div className="space-y-2 py-2">
            {mean != null ? (
              <div className="grid grid-cols-3 gap-3">
                <div className="text-center p-2 rounded bg-muted/50">
                  <div className="text-xs text-muted-foreground">Mean motion</div>
                  <div className="text-sm font-semibold">{mean.toFixed(1)} Å</div>
                </div>
                <div className="text-center p-2 rounded bg-muted/50">
                  <div className="text-xs text-muted-foreground">Min</div>
                  <div className="text-sm font-semibold">{data.min_total_motion_A?.toFixed(1) ?? '—'} Å</div>
                </div>
                <div className="text-center p-2 rounded bg-muted/50">
                  <div className="text-xs text-muted-foreground">Max</div>
                  <div className="text-sm font-semibold">{data.max_total_motion_A?.toFixed(1) ?? '—'} Å</div>
                </div>
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">Motion statistics not available for this batch.</p>
            )}
            <p className="text-[10px] text-muted-foreground">
              Per-micrograph distribution requires pipeline update to export individual values.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
