import { useState, useEffect, useCallback } from "react"
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { Slider } from "@/components/ui/slider"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Separator } from "@/components/ui/separator"
import { Alert, AlertDescription } from "@/components/ui/alert"
import {
  FlaskConical,
  Play,
  RotateCcw,
  ArrowRight,
  Clock,
  HardDrive,
  DollarSign,
  CheckCircle2,
  AlertCircle,
  Loader2,
  TrendingUp,
  Sparkles,
  X
} from "lucide-react"
import { cn } from "@/lib/utils"
import {
  startPilotRun,
  pollPilotStatus,
  getFullRunEstimate,
  type PilotStatusResponse,
  type FullRunEstimateResponse
} from "@/lib/ai-assistant-api"
import type { TuningConfig, PilotResult, FullRunEstimate, ParameterRecommendation } from "@shared/schema"

interface PilotRunPanelProps {
  workflowId: string
  totalSamples: number
  initialConfig?: TuningConfig
  onStartPilot?: (config: TuningConfig) => Promise<void>
  onComplete?: (result: PilotResult, estimate: FullRunEstimate) => void
  onProceedToFull?: (params: Record<string, any>) => void
  onApplyRecommendation?: (paramKey: string, value: any) => void
  onClose?: () => void
  parameterRecommendations?: Record<string, ParameterRecommendation>
  className?: string
}

type PanelState = 'configure' | 'running' | 'complete'

export function PilotRunPanel({
  workflowId,
  totalSamples,
  initialConfig,
  onStartPilot,
  onComplete,
  onProceedToFull,
  onApplyRecommendation,
  onClose,
  parameterRecommendations = {},
  className
}: PilotRunPanelProps) {
  const [panelState, setPanelState] = useState<PanelState>('configure')
  const [config, setConfig] = useState<TuningConfig>(initialConfig || {
    pilot_fraction: 0.1,
    sampling_strategy: 'stratified',
    min_pilot_samples: 3,
    max_pilot_samples: 50,
  })
  const [pilotResult, setPilotResult] = useState<PilotResult | null>(null)
  const [estimate, setEstimate] = useState<FullRunEstimate | null>(null)
  const [appliedRecommendations, setAppliedRecommendations] = useState<Set<string>>(new Set())
  const [error, setError] = useState<string | null>(null)

  const pilotSize = Math.max(
    config.min_pilot_samples || 3,
    Math.min(
      config.max_pilot_samples || 50,
      Math.round(totalSamples * (config.pilot_fraction || 0.1))
    )
  )

  const handleStartPilot = async () => {
    setPanelState('running')
    setError(null)
    setPilotResult({
      pilot_id: 'pending',
      status: 'running',
      progress: 0,
    })

    try {
      // Call the parent handler if provided
      await onStartPilot?.(config)

      // Start the pilot run via API
      const startResponse = await startPilotRun(
        workflowId,
        totalSamples,
        config
      )

      console.log('[PilotRunPanel] Pilot started:', startResponse)

      // Update with real pilot ID
      setPilotResult({
        pilot_id: startResponse.pilot_id,
        status: 'running',
        progress: 0,
      })

      // Poll for status updates
      const finalStatus = await pollPilotStatus(
        startResponse.pilot_id,
        (status) => {
          // Update progress as we poll
          setPilotResult({
            pilot_id: status.pilot_id,
            status: status.status,
            progress: status.progress,
            runtime_seconds: status.runtime_seconds,
            peak_memory_gb: status.peak_memory_gb,
            quality_metrics: status.quality_metrics,
            error_message: status.error_message
          })
        },
        2000, // Poll every 2 seconds
        300   // Max 10 minutes
      )

      if (finalStatus.status === 'complete') {
        // Get the full run estimate
        const estimateResponse = await getFullRunEstimate(startResponse.pilot_id)

        const fullEstimate: FullRunEstimate = {
          estimated_runtime_seconds: estimateResponse.estimated_runtime_seconds,
          estimated_runtime_display: estimateResponse.estimated_runtime_display,
          estimated_memory_gb: estimateResponse.estimated_memory_gb,
          estimated_cost_usd: estimateResponse.estimated_cost_usd,
          confidence: estimateResponse.confidence,
          scaling_factors: estimateResponse.scaling_factors
        }

        setEstimate(fullEstimate)
        setPanelState('complete')

        const finalResult: PilotResult = {
          pilot_id: finalStatus.pilot_id,
          status: 'complete',
          progress: 100,
          runtime_seconds: finalStatus.runtime_seconds,
          peak_memory_gb: finalStatus.peak_memory_gb,
          quality_metrics: finalStatus.quality_metrics
        }

        setPilotResult(finalResult)
        onComplete?.(finalResult, fullEstimate)
      } else {
        // Pilot failed
        setError(finalStatus.error_message || 'Pilot run failed')
        setPilotResult({
          pilot_id: finalStatus.pilot_id,
          status: 'failed',
          progress: finalStatus.progress,
          error_message: finalStatus.error_message
        })
      }

    } catch (err: any) {
      console.error('[PilotRunPanel] Error:', err)
      setError(err.message || 'Failed to run pilot')
      setPilotResult({
        pilot_id: 'error',
        status: 'failed',
        progress: 0,
        error_message: err.message || 'Failed to run pilot'
      })
      setPanelState('configure')
    }
  }

  const handleRerunPilot = () => {
    setPanelState('configure')
    setPilotResult(null)
    setEstimate(null)
    setAppliedRecommendations(new Set())
  }

  const handleApplyRecommendation = (paramKey: string) => {
    const rec = parameterRecommendations[paramKey]
    if (rec) {
      onApplyRecommendation?.(paramKey, rec.recommended_value)
      setAppliedRecommendations(prev => new Set(prev).add(paramKey))
    }
  }

  const handleApplyAllRecommendations = () => {
    Object.keys(parameterRecommendations).forEach(key => {
      handleApplyRecommendation(key)
    })
  }

  const handleProceedToFull = () => {
    const appliedParams: Record<string, any> = {}
    appliedRecommendations.forEach(key => {
      const rec = parameterRecommendations[key]
      if (rec) {
        appliedParams[key] = rec.recommended_value
      }
    })
    onProceedToFull?.(appliedParams)
  }

  const formatTime = (seconds: number): string => {
    if (seconds < 60) return `${Math.round(seconds)}s`
    if (seconds < 3600) return `${Math.round(seconds / 60)}m ${Math.round(seconds % 60)}s`
    return `${Math.floor(seconds / 3600)}h ${Math.round((seconds % 3600) / 60)}m`
  }

  return (
    <Card className={cn("border-2 border-primary/20", className)}>
      <CardHeader className="p-4 pb-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <FlaskConical className="h-5 w-5 text-primary" />
            <CardTitle className="text-base">
              {panelState === 'configure' && 'Pilot Run Configuration'}
              {panelState === 'running' && 'Pilot Run in Progress'}
              {panelState === 'complete' && 'Pilot Run Complete'}
            </CardTitle>
          </div>
          {panelState === 'complete' && (
            <Badge variant="secondary" className="bg-green-500/10 text-green-600">
              <CheckCircle2 className="h-3 w-3 mr-1" />
              Complete
            </Badge>
          )}
        </div>
        {panelState === 'configure' && (
          <CardDescription className="text-xs mt-1">
            Your dataset has {totalSamples} samples. Running a pilot on a subset helps optimize parameters before full analysis.
          </CardDescription>
        )}
      </CardHeader>

      <CardContent className="p-4 pt-2">
        {/* Configuration State */}
        {panelState === 'configure' && (
          <div className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label className="text-sm">Pilot Size</Label>
                <span className="text-sm font-medium">
                  {Math.round(config.pilot_fraction! * 100)}% ({pilotSize} samples)
                </span>
              </div>
              <Slider
                value={[config.pilot_fraction! * 100]}
                onValueChange={([value]) => setConfig(prev => ({ ...prev, pilot_fraction: value / 100 }))}
                min={5}
                max={30}
                step={1}
                className="w-full"
              />
            </div>

            <Separator />

            <div className="space-y-2">
              <Label className="text-sm">Sampling Strategy</Label>
              <RadioGroup
                value={config.sampling_strategy}
                onValueChange={(value) => setConfig(prev => ({ ...prev, sampling_strategy: value as any }))}
                className="grid gap-2"
              >
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="stratified" id="stratified" />
                  <Label htmlFor="stratified" className="text-xs font-normal cursor-pointer">
                    <span className="font-medium">Stratified</span> - Preserves group balance (recommended)
                  </Label>
                </div>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="random" id="random" />
                  <Label htmlFor="random" className="text-xs font-normal cursor-pointer">
                    <span className="font-medium">Random</span> - Random sample selection
                  </Label>
                </div>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="first_n" id="first_n" />
                  <Label htmlFor="first_n" className="text-xs font-normal cursor-pointer">
                    <span className="font-medium">First N</span> - First N samples in order
                  </Label>
                </div>
              </RadioGroup>
            </div>

            <div className="flex items-center gap-2 p-2 bg-muted/50 rounded-md">
              <Clock className="h-4 w-4 text-muted-foreground" />
              <span className="text-xs text-muted-foreground">
                Estimated pilot time: ~{Math.round(pilotSize * 0.5)} seconds
              </span>
            </div>
          </div>
        )}

        {/* Running State */}
        {panelState === 'running' && pilotResult && (
          <div className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm">Processing {pilotSize} samples...</span>
                <span className="text-sm font-medium">{pilotResult.progress}%</span>
              </div>
              <Progress value={pilotResult.progress} className="h-2" />
            </div>

            <div className="flex items-center justify-center py-4">
              <Loader2 className="h-8 w-8 text-primary animate-spin" />
            </div>

            {pilotResult.error_message && (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>{pilotResult.error_message}</AlertDescription>
              </Alert>
            )}
          </div>
        )}

        {/* Complete State */}
        {panelState === 'complete' && pilotResult && estimate && (
          <div className="space-y-4">
            {/* Pilot Metrics */}
            <div className="grid grid-cols-3 gap-3">
              <div className="p-2 bg-muted/50 rounded-md text-center">
                <Clock className="h-4 w-4 mx-auto text-muted-foreground mb-1" />
                <div className="text-sm font-medium">{formatTime(pilotResult.runtime_seconds || 0)}</div>
                <div className="text-xs text-muted-foreground">Runtime</div>
              </div>
              <div className="p-2 bg-muted/50 rounded-md text-center">
                <HardDrive className="h-4 w-4 mx-auto text-muted-foreground mb-1" />
                <div className="text-sm font-medium">{pilotResult.peak_memory_gb?.toFixed(1)} GB</div>
                <div className="text-xs text-muted-foreground">Memory</div>
              </div>
              <div className="p-2 bg-muted/50 rounded-md text-center">
                <TrendingUp className="h-4 w-4 mx-auto text-muted-foreground mb-1" />
                <div className="text-sm font-medium">
                  {pilotResult.quality_metrics?.accuracy
                    ? `${(pilotResult.quality_metrics.accuracy * 100).toFixed(0)}%`
                    : 'N/A'}
                </div>
                <div className="text-xs text-muted-foreground">Quality</div>
              </div>
            </div>

            <Separator />

            {/* Full Run Estimate */}
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <Sparkles className="h-4 w-4 text-primary" />
                <span className="text-sm font-medium">Full Run Estimate ({totalSamples} samples)</span>
              </div>

              <div className="grid grid-cols-3 gap-3">
                <div className="p-2 border rounded-md text-center">
                  <div className="text-sm font-medium">{estimate.estimated_runtime_display}</div>
                  <div className="text-xs text-muted-foreground">Runtime</div>
                </div>
                <div className="p-2 border rounded-md text-center">
                  <div className="text-sm font-medium">{estimate.estimated_memory_gb.toFixed(0)} GB</div>
                  <div className="text-xs text-muted-foreground">RAM</div>
                </div>
                {estimate.estimated_cost_usd && (
                  <div className="p-2 border rounded-md text-center">
                    <div className="text-sm font-medium">${estimate.estimated_cost_usd.toFixed(2)}</div>
                    <div className="text-xs text-muted-foreground">Cost</div>
                  </div>
                )}
              </div>

            </div>

            {/* Parameter Recommendations */}
            {Object.keys(parameterRecommendations).length > 0 && (
              <>
                <Separator />
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium">Parameter Recommendations</span>
                    <Button
                      size="sm"
                      variant="ghost"
                      className="h-7 text-xs"
                      onClick={handleApplyAllRecommendations}
                    >
                      Apply All
                    </Button>
                  </div>

                  {Object.entries(parameterRecommendations).map(([key, rec]) => (
                    <div key={key} className="flex items-center justify-between p-2 bg-muted/50 rounded-md">
                      <div className="flex-1">
                        <span className="text-xs font-medium">{rec.parameter_name}:</span>
                        <span className="text-xs ml-1">
                          {String(rec.current_value || 'default')} → {String(rec.recommended_value)}
                        </span>
                        {rec.reason && (
                          <p className="text-xs text-muted-foreground">{rec.reason}</p>
                        )}
                      </div>
                      <Button
                        size="sm"
                        variant={appliedRecommendations.has(key) ? "secondary" : "outline"}
                        className="h-6 text-xs ml-2"
                        onClick={() => handleApplyRecommendation(key)}
                        disabled={appliedRecommendations.has(key)}
                      >
                        {appliedRecommendations.has(key) ? (
                          <>
                            <CheckCircle2 className="h-3 w-3 mr-1" />
                            Applied
                          </>
                        ) : (
                          'Apply'
                        )}
                      </Button>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>
        )}
      </CardContent>

      {/* Error display */}
      {error && (
        <div className="px-4 pb-2">
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        </div>
      )}

      <CardFooter className="p-4 pt-0 gap-2">
        {panelState === 'configure' && (
          <>
            <Button variant="outline" className="flex-1" onClick={onClose}>
              Cancel
            </Button>
            <Button className="flex-1" onClick={handleStartPilot}>
              <Play className="h-4 w-4 mr-2" />
              Start Pilot Run
            </Button>
          </>
        )}

        {panelState === 'running' && (
          <Button variant="outline" className="flex-1" onClick={onClose} disabled>
            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
            Running...
          </Button>
        )}

        {panelState === 'complete' && (
          <>
            <Button variant="outline" className="flex-1" onClick={handleRerunPilot}>
              <RotateCcw className="h-4 w-4 mr-2" />
              Re-run Pilot
            </Button>
            <Button className="flex-1" onClick={handleProceedToFull}>
              {appliedRecommendations.size > 0 ? 'Apply & ' : ''}Run Full Analysis
              <ArrowRight className="h-4 w-4 ml-2" />
            </Button>
          </>
        )}
      </CardFooter>
    </Card>
  )
}
