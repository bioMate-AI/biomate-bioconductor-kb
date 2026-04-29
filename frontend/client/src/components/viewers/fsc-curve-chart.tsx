/**
 * FSC Curve Chart
 * Renders the Fourier Shell Correlation curve from fsc_validation.json.
 * Gold-standard resolution = last shell where FSC >= 0.143.
 */

import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ReferenceLine, ResponsiveContainer, Legend,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { AlertCircle, TrendingDown } from 'lucide-react'

interface FscPoint {
  spatial_frequency: number
  resolution_angstroms: number
  fsc: number
}

interface FscData {
  fsc_curve: FscPoint[]
  fsc_0143_resolution?: number
  fsc_05_resolution?: number
  cs_job_uid?: string
}

interface FscCurveChartProps {
  data: FscData
}

export function FscCurveChart({ data }: FscCurveChartProps) {
  const curve = data.fsc_curve || []

  if (curve.length === 0) {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground p-3">
        <AlertCircle className="h-4 w-4 shrink-0" />
        FSC curve data not available — CryoSPARC may not have exported this slot.
        Check the validation job (job UID: {data.cs_job_uid ?? '—'}) in CryoSPARC directly.
      </div>
    )
  }

  // Recharts wants the domain in ascending X order; FSC curves go low freq → high freq
  const chartData = curve.map(p => ({
    res: parseFloat(p.resolution_angstroms.toFixed(1)),
    fsc: parseFloat(p.fsc.toFixed(4)),
    freq: p.spatial_frequency,
  })).sort((a, b) => b.res - a.res) // high resolution Å = low number, plot left-to-right going finer

  const res0143 = data.fsc_0143_resolution
  const res05   = data.fsc_05_resolution

  const customTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null
    const d = payload[0].payload
    return (
      <div className="bg-background border rounded px-2 py-1 text-xs shadow">
        <div>{d.res} Å</div>
        <div>FSC = {d.fsc.toFixed(3)}</div>
      </div>
    )
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-sm">
          <TrendingDown className="h-4 w-4" />
          FSC Curve
        </CardTitle>
        <CardDescription className="flex gap-2 flex-wrap">
          {res0143 != null && (
            <Badge variant="default" className="text-xs">
              Resolution (0.143) = {res0143} Å
            </Badge>
          )}
          {res05 != null && (
            <Badge variant="outline" className="text-xs">
              FSC 0.5 = {res05} Å
            </Badge>
          )}
          {data.cs_job_uid && (
            <Badge variant="outline" className="text-xs">
              Job {data.cs_job_uid}
            </Badge>
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={260}>
          <LineChart data={chartData} margin={{ top: 8, right: 16, bottom: 24, left: 8 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
            <XAxis
              dataKey="res"
              type="number"
              domain={['dataMin', 'dataMax']}
              reversed
              label={{ value: 'Resolution (Å)', position: 'insideBottom', offset: -12, fontSize: 11 }}
              tickFormatter={v => `${v}`}
              fontSize={11}
            />
            <YAxis
              domain={[0, 1]}
              label={{ value: 'FSC', angle: -90, position: 'insideLeft', fontSize: 11 }}
              fontSize={11}
            />
            <Tooltip content={customTooltip} />
            <ReferenceLine y={0.143} stroke="#ef4444" strokeDasharray="4 2"
              label={{ value: '0.143', position: 'right', fontSize: 10, fill: '#ef4444' }} />
            <ReferenceLine y={0.5} stroke="#f97316" strokeDasharray="4 2"
              label={{ value: '0.5', position: 'right', fontSize: 10, fill: '#f97316' }} />
            {res0143 != null && (
              <ReferenceLine x={res0143} stroke="#ef4444" strokeDasharray="2 2" />
            )}
            <Line
              type="monotone" dataKey="fsc"
              stroke="#3b82f6" strokeWidth={2} dot={false}
              name="FSC"
            />
          </LineChart>
        </ResponsiveContainer>
        <p className="text-[10px] text-muted-foreground text-center mt-1">
          Gold-standard FSC — 0.143 criterion gives resolution estimate
        </p>
      </CardContent>
    </Card>
  )
}
