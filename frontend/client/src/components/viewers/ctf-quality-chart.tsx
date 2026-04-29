/**
 * CTF Quality Chart
 * Shows defocus distribution and CTF fit quality from ctf_report_batch_*.json.
 * Defocus range 0.5–4 µm is typical for SPA. CTF fit < 5 Å is considered good.
 */

import {
  ScatterChart, Scatter, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, ReferenceLine,
} from 'recharts'
import { BarChart, Bar } from 'recharts'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Waves } from 'lucide-react'

interface CtfReportData {
  num_micrographs?: number
  avg_defocus_A?: number
  min_defocus_A?: number
  max_defocus_A?: number
  avg_ctf_fit_to_A?: number
  avg_astigmatism_A?: number
  avg_fit_quality?: number
  per_micrograph_defocus_A?: number[]
  per_micrograph_fit_A?: number[]
  batch_id?: string
  cs_job_uid?: string
}

interface CtfQualityChartProps {
  data: CtfReportData
}

function buildHistogram(values: number[], binCount = 15) {
  if (!values.length) return []
  const min = Math.min(...values)
  const max = Math.max(...values)
  const step = (max - min) / binCount || 1
  const bins = Array.from({ length: binCount }, (_, i) => ({
    midpoint: min + (i + 0.5) * step,
    label: `${((min + i * step) / 10000).toFixed(2)}`,
    count: 0,
  }))
  for (const v of values) {
    const idx = Math.min(Math.floor((v - min) / step), binCount - 1)
    bins[idx].count++
  }
  return bins
}

export function CtfQualityChart({ data }: CtfQualityChartProps) {
  const defArr = data.per_micrograph_defocus_A
  const fitArr = data.per_micrograph_fit_A
  const hasDistribution = Array.isArray(defArr) && defArr.length > 0

  // Convert defocus from Å to µm for display
  const defocusHistData = hasDistribution
    ? buildHistogram(defArr!.map(v => v / 10000))  // Å → µm
    : []

  const scatterData = hasDistribution && Array.isArray(fitArr) && fitArr.length === defArr!.length
    ? defArr!.map((d, i) => ({ defocus: parseFloat((d / 10000).toFixed(3)), fit: parseFloat(fitArr![i].toFixed(1)) }))
    : []

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-sm">
          <Waves className="h-4 w-4" />
          CTF Estimation
        </CardTitle>
        <CardDescription className="flex gap-2 flex-wrap">
          {data.num_micrographs != null && (
            <Badge variant="outline" className="text-xs">{data.num_micrographs} micrographs</Badge>
          )}
          {data.avg_defocus_A != null && (
            <Badge variant="default" className="text-xs">
              Mean defocus {(data.avg_defocus_A / 10000).toFixed(2)} µm
            </Badge>
          )}
          {data.avg_ctf_fit_to_A != null && (
            <Badge variant={data.avg_ctf_fit_to_A < 5 ? 'default' : 'destructive'} className="text-xs">
              CTF fit {data.avg_ctf_fit_to_A.toFixed(1)} Å
            </Badge>
          )}
          {data.avg_astigmatism_A != null && (
            <Badge variant="outline" className="text-xs">
              Astig {data.avg_astigmatism_A.toFixed(0)} Å
            </Badge>
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {hasDistribution && defocusHistData.length > 0 ? (
          <>
            <div>
              <p className="text-xs font-medium mb-1">Defocus distribution (µm)</p>
              <ResponsiveContainer width="100%" height={160}>
                <BarChart data={defocusHistData} margin={{ top: 4, right: 8, bottom: 16, left: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                  <XAxis dataKey="midpoint" tickFormatter={v => v.toFixed(1)} fontSize={10}
                    label={{ value: 'Defocus (µm)', position: 'insideBottom', offset: -10, fontSize: 10 }} />
                  <YAxis fontSize={10} />
                  <Tooltip formatter={(v: any) => [`${v}`, 'count']} labelFormatter={v => `~${Number(v).toFixed(2)} µm`} />
                  <ReferenceLine x={0.5} stroke="#f97316" strokeDasharray="3 2" />
                  <ReferenceLine x={4.0} stroke="#f97316" strokeDasharray="3 2" />
                  <Bar dataKey="count" fill="#8b5cf6" radius={[2, 2, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
              <p className="text-[10px] text-muted-foreground text-center">Orange lines: typical 0.5–4 µm range</p>
            </div>
            {scatterData.length > 0 && (
              <div>
                <p className="text-xs font-medium mb-1">Defocus vs CTF fit quality</p>
                <ResponsiveContainer width="100%" height={160}>
                  <ScatterChart margin={{ top: 4, right: 8, bottom: 16, left: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                    <XAxis dataKey="defocus" type="number" name="Defocus (µm)" fontSize={10}
                      label={{ value: 'Defocus (µm)', position: 'insideBottom', offset: -10, fontSize: 10 }} />
                    <YAxis dataKey="fit" type="number" name="CTF fit (Å)" fontSize={10}
                      label={{ value: 'CTF fit (Å)', angle: -90, position: 'insideLeft', fontSize: 10 }} />
                    <Tooltip cursor={{ strokeDasharray: '3 3' }}
                      formatter={(v: any, name: string) => [typeof v === 'number' ? v.toFixed(2) : v, name]} />
                    <ReferenceLine y={5} stroke="#ef4444" strokeDasharray="3 2"
                      label={{ value: '5 Å threshold', fontSize: 9, fill: '#ef4444' }} />
                    <Scatter data={scatterData} fill="#8b5cf6" opacity={0.7} />
                  </ScatterChart>
                </ResponsiveContainer>
                <p className="text-[10px] text-muted-foreground text-center">Points below 5 Å = well-fitted CTF</p>
              </div>
            )}
          </>
        ) : (
          // Summary stats only
          <div className="space-y-2">
            <div className="grid grid-cols-2 gap-3">
              {data.avg_defocus_A != null && (
                <div className="text-center p-2 rounded bg-muted/50">
                  <div className="text-xs text-muted-foreground">Mean defocus</div>
                  <div className="text-sm font-semibold">{(data.avg_defocus_A / 10000).toFixed(2)} µm</div>
                </div>
              )}
              {data.avg_ctf_fit_to_A != null && (
                <div className="text-center p-2 rounded bg-muted/50">
                  <div className="text-xs text-muted-foreground">CTF fit</div>
                  <div className={`text-sm font-semibold ${data.avg_ctf_fit_to_A < 5 ? 'text-green-600' : 'text-red-500'}`}>
                    {data.avg_ctf_fit_to_A.toFixed(1)} Å
                  </div>
                </div>
              )}
              {data.min_defocus_A != null && (
                <div className="text-center p-2 rounded bg-muted/50">
                  <div className="text-xs text-muted-foreground">Defocus range</div>
                  <div className="text-sm font-semibold">
                    {(data.min_defocus_A / 10000).toFixed(2)}–{(data.max_defocus_A! / 10000).toFixed(2)} µm
                  </div>
                </div>
              )}
              {data.avg_astigmatism_A != null && (
                <div className="text-center p-2 rounded bg-muted/50">
                  <div className="text-xs text-muted-foreground">Astigmatism</div>
                  <div className="text-sm font-semibold">{data.avg_astigmatism_A.toFixed(0)} Å</div>
                </div>
              )}
            </div>
            <p className="text-[10px] text-muted-foreground">
              Per-micrograph scatter plot requires pipeline update to export individual values.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
